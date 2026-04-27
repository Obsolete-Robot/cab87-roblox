local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadGraphData = require(Shared:WaitForChild("RoadGraphData"))
local RoadGraphMesher = require(Shared:WaitForChild("RoadGraphMesher"))
local RoadSampling = require(Shared:WaitForChild("RoadSampling"))
local RoadSplineData = require(Shared:WaitForChild("RoadSplineData"))

local PassengerVisuals = require(script.Parent.Parent:WaitForChild("PassengerVisuals"))

local PassengerStopService = {}

PassengerStopService.STOP_LAYOUT_TUNING_KEYS = {
	passengerMaxStops = true,
	passengerStopMinSeparation = true,
	passengerStopRoadEdgeInset = true,
	passengerStopSpacing = true,
}

local ROAD_SPLINE_DATA_NAME = RoadSplineData.RUNTIME_DATA_NAME
local horizontalDistance = RoadSampling.distanceXZ

local function getConfigNumber(key, fallback)
	local value = Config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function getConfigString(key, fallback)
	local value = Config[key]
	if type(value) == "string" and value ~= "" then
		return value
	end

	return fallback
end

function PassengerStopService.recordStopLayoutValues(target)
	table.clear(target)
	for key in pairs(PassengerStopService.STOP_LAYOUT_TUNING_KEYS) do
		target[key] = Config[key]
	end
end

local function horizontalUnit(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	local magnitude = horizontal.Magnitude
	if magnitude <= 0.001 then
		return nil
	end

	return horizontal / magnitude
end

local function getPerpendicularRight(direction)
	return Vector3.new(direction.Z, 0, -direction.X)
end

local function addCandidate(candidates, position, minSeparation)
	for _, candidate in ipairs(candidates) do
		if horizontalDistance(candidate, position) < minSeparation then
			return false
		end
	end

	table.insert(candidates, position)
	return true
end

local function getPassengerStopRoadEdgeMargin()
	return math.max(getConfigNumber("passengerStopRoadEdgeInset", 4), 0)
end

local function getPassengerStopLateralDistance(roadWidth)
	local halfWidth = math.max((tonumber(roadWidth) or 0) * 0.5, 0)
	if halfWidth <= 0 then
		return 0
	end

	return math.max(halfWidth - math.min(getPassengerStopRoadEdgeMargin(), halfWidth), 0)
end

local function addRoadEdgeCandidate(candidates, centerPosition, tangent, roadWidth, minSeparation, preferredSide)
	local lateralDistance = getPassengerStopLateralDistance(roadWidth)
	if not tangent or lateralDistance <= 0.001 then
		return addCandidate(candidates, centerPosition, minSeparation)
	end

	local right = getPerpendicularRight(tangent)
	local firstSide = if preferredSide and preferredSide < 0 then -1 else 1
	local firstPosition = centerPosition + right * lateralDistance * firstSide
	if addCandidate(candidates, firstPosition, minSeparation) then
		return true
	end

	return addCandidate(candidates, centerPosition - right * lateralDistance * firstSide, minSeparation)
end

local function collectAuthoredRoadCandidates(world, minSeparation)
	local candidates = {}
	local spacing = math.max(getConfigNumber("passengerStopSpacing", 160), 24)
	local graphData = RoadGraphData.collectGraph(world, Config)
	if graphData then
		local meshData = RoadGraphMesher.buildNetworkMesh(graphData, graphData.settings)
		for recordIndex, centerLine in ipairs(meshData.centerLines or {}) do
			if #centerLine >= 2 then
				local distanceSinceLastStop = spacing
				local previousPosition = nil
				local fallbackDir = horizontalUnit(centerLine[2] - centerLine[1]) or Vector3.new(0, 0, 1)
				for index, position in ipairs(centerLine) do
					if previousPosition then
						distanceSinceLastStop += horizontalDistance(position, previousPosition)
					end

					if distanceSinceLastStop >= spacing then
						local tangent = RoadSampling.getRoadSampleTangent(centerLine, index, #centerLine, false, fallbackDir)
						local preferredSide = if ((#candidates + recordIndex) % 2 == 0) then 1 else -1
						addRoadEdgeCandidate(candidates, position, tangent, centerLine.width or RoadSampling.DEFAULT_ROAD_WIDTH, minSeparation, preferredSide)
						distanceSinceLastStop = 0
					end

					previousPosition = position
				end
			end
		end

		return candidates
	end

	local dataRoot = world:FindFirstChild(ROAD_SPLINE_DATA_NAME)
	if not dataRoot then
		return candidates
	end

	local defaultRoadWidth = RoadSampling.getConfiguredRoadWidth(Config)
	for recordIndex, record in ipairs(RoadSplineData.collectSplineRecords(dataRoot, {
		defaultRoadWidth = defaultRoadWidth,
	})) do
		local positions = if record.sampled
			then record.positions
			else RoadSampling.samplePositions(
				record.positions,
				record.closed,
				getConfigNumber("authoredRoadSampleStepStuds", 8)
			)
		local closedLoop = RoadSampling.sampleLoopIsClosed(positions)
		local edgeCount = if closedLoop then #positions - 1 else #positions
		if edgeCount < 2 then
			continue
		end

		local distanceSinceLastStop = spacing
		local previousPosition = nil
		local fallbackDir = horizontalUnit(positions[2] - positions[1]) or Vector3.new(0, 0, 1)

		for index = 1, edgeCount do
			local position = positions[index]
			if previousPosition then
				distanceSinceLastStop += horizontalDistance(position, previousPosition)
			end

			if distanceSinceLastStop >= spacing then
				local tangent = RoadSampling.getRoadSampleTangent(positions, index, edgeCount, closedLoop, fallbackDir)
				local preferredSide = if ((#candidates + recordIndex) % 2 == 0) then 1 else -1
				addRoadEdgeCandidate(candidates, position, tangent, record.width, minSeparation, preferredSide)
				distanceSinceLastStop = 0
			end

			previousPosition = position
		end
	end

	return candidates
end

local function canUseSurfaceForStops(surface)
	if not surface:IsA("BasePart") then
		return false
	end

	if surface.Name == "Ground" or surface.Name == "JumpRamp" or surface.Name == "LandingPad" then
		return false
	end

	return surface.Size.X >= 8 and surface.Size.Z >= 8
end

local function collectSurfaceCandidates(driveSurfaces, minSeparation)
	local candidates = {}
	local spacing = math.max(getConfigNumber("passengerStopSpacing", 160), 24)
	local edgeMargin = getPassengerStopRoadEdgeMargin()

	for _, surface in ipairs(driveSurfaces or {}) do
		if canUseSurfaceForStops(surface) then
			local size = surface.Size
			local longAxisIsX = size.X >= size.Z
			local longSize = if longAxisIsX then size.X else size.Z
			local shortSize = if longAxisIsX then size.Z else size.X
			local halfLong = math.max(longSize * 0.5 - edgeMargin, 0)
			local span = halfLong * 2
			local count = math.max(1, math.floor(span / spacing + 0.5) + 1)
			local lateralDistance = getPassengerStopLateralDistance(shortSize)

			for i = 1, count do
				local along = if count == 1 then 0 else -halfLong + span * ((i - 1) / (count - 1))
				local preferredSide = if (#candidates % 2 == 0) then 1 else -1
				for attempt = 1, 2 do
					local side = if attempt == 1 then preferredSide else -preferredSide
					local lateral = lateralDistance * side
					local localPosition = if longAxisIsX
						then Vector3.new(along, size.Y * 0.5, lateral)
						else Vector3.new(lateral, size.Y * 0.5, along)
					local worldPosition = surface.CFrame:PointToWorldSpace(localPosition)
					if addCandidate(candidates, worldPosition, minSeparation) or lateralDistance <= 0.001 then
						break
					end
				end
			end
		end
	end

	return candidates
end

local function getPassengerGroundFromCabPose(spawnPose)
	local rideHeight = getConfigNumber("carRideHeight", 2.3)
	local spawnPosition = (spawnPose and spawnPose.position) or Config.carSpawn
	return Vector3.new(spawnPosition.X, spawnPosition.Y - rideHeight, spawnPosition.Z)
end

local function ensureMinimumCandidateCount(candidates, spawnPose)
	local minTripDistance = math.max(getConfigNumber("passengerMinTripDistance", 320), 120)
	local center = getPassengerGroundFromCabPose(spawnPose)
	local fallbackPositions = {
		center,
		center + Vector3.new(minTripDistance, 0, 0),
		center - Vector3.new(minTripDistance, 0, 0),
		center + Vector3.new(0, 0, minTripDistance),
		center - Vector3.new(0, 0, minTripDistance),
	}

	for _, position in ipairs(fallbackPositions) do
		if #candidates >= 2 then
			break
		end

		addCandidate(candidates, position, 1)
	end
end

function PassengerStopService.createSurfaceRaycastParams(driveSurfaces)
	if not driveSurfaces or #driveSurfaces == 0 then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = driveSurfaces
	return raycastParams
end

function PassengerStopService.projectToSurface(raycastParams, position, fallbackY)
	if raycastParams then
		local rayHeight = math.max(getConfigNumber("passengerSurfaceRaycastHeight", 140), 1)
		local rayDepth = math.max(getConfigNumber("passengerSurfaceRaycastDepth", 260), rayHeight + 1)
		local origin = Vector3.new(position.X, position.Y + rayHeight, position.Z)
		local result = Workspace:Raycast(origin, Vector3.new(0, -rayDepth, 0), raycastParams)
		if result then
			return result.Position
		end
	end

	return Vector3.new(position.X, fallbackY or position.Y, position.Z)
end

local function shuffle(values, rng)
	for i = #values, 2, -1 do
		local j = rng:NextInteger(1, i)
		values[i], values[j] = values[j], values[i]
	end
end

function PassengerStopService.createPassengerStops(options)
	local world = options.world
	local driveSurfaces = options.driveSurfaces
	local spawnPose = options.spawnPose
	local rng = options.rng

	local folderName = getConfigString("passengerStopFolderName", "PassengerStops")
	local folder = PassengerVisuals.recreateFolder(world, folderName)
	local minSeparation = math.max(getConfigNumber("passengerStopMinSeparation", 80), 1)
	local maxStops = math.max(2, math.floor(getConfigNumber("passengerMaxStops", 36)))
	local candidates = collectAuthoredRoadCandidates(world, minSeparation)
	local surfaceRaycastParams = PassengerStopService.createSurfaceRaycastParams(driveSurfaces)

	if #candidates == 0 then
		candidates = collectSurfaceCandidates(driveSurfaces, minSeparation)
	end

	ensureMinimumCandidateCount(candidates, spawnPose)
	shuffle(candidates, rng)

	local stops = {}
	for i = 1, math.min(#candidates, maxStops) do
		local candidate = candidates[i]
		local position = PassengerStopService.projectToSurface(surfaceRaycastParams, candidate, candidate.Y)
		table.insert(stops, {
			id = i,
			position = position,
			instance = PassengerVisuals.createStop(folder, i, position),
		})
	end

	folder:SetAttribute("StopCount", #stops)
	return stops, folder, surfaceRaycastParams
end

return PassengerStopService
