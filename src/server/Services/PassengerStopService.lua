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
local DEBUG_PREFIX = "[cab87 passenger stops]"

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

local function debugLoggingEnabled()
	return Config.passengerDebugLogging == true
end

local function debugLog(message, ...)
	if not debugLoggingEnabled() then
		return
	end

	local ok, formatted = pcall(string.format, tostring(message), ...)
	print(DEBUG_PREFIX .. " " .. (ok and formatted or tostring(message)))
end

local function formatVector(position)
	if typeof(position) ~= "Vector3" then
		return "nil"
	end

	return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
end

local function countParts(instances)
	local count = 0
	for _, instance in ipairs(instances or {}) do
		if instance and instance:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local function createBounds()
	return {
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge),
		count = 0,
	}
end

local function includeBounds(bounds, position)
	if typeof(position) ~= "Vector3" then
		return
	end

	bounds.count += 1
	bounds.min = Vector3.new(
		math.min(bounds.min.X, position.X),
		math.min(bounds.min.Y, position.Y),
		math.min(bounds.min.Z, position.Z)
	)
	bounds.max = Vector3.new(
		math.max(bounds.max.X, position.X),
		math.max(bounds.max.Y, position.Y),
		math.max(bounds.max.Z, position.Z)
	)
end

local function formatBounds(bounds)
	if not bounds or bounds.count <= 0 then
		return "empty"
	end

	return string.format("min=%s max=%s count=%d", formatVector(bounds.min), formatVector(bounds.max), bounds.count)
end

local function setVectorAttributes(instance, prefix, position)
	if not (instance and typeof(position) == "Vector3") then
		return
	end

	instance:SetAttribute(prefix .. "X", position.X)
	instance:SetAttribute(prefix .. "Y", position.Y)
	instance:SetAttribute(prefix .. "Z", position.Z)
end

local function setBoundsAttributes(instance, prefix, bounds)
	if not (instance and bounds and bounds.count > 0) then
		return
	end

	setVectorAttributes(instance, prefix .. "Min", bounds.min)
	setVectorAttributes(instance, prefix .. "Max", bounds.max)
	instance:SetAttribute(prefix .. "Count", bounds.count)
end

local function graphDataRoot(world)
	return world and (world:FindFirstChild(RoadGraphData.RUNTIME_DATA_NAME) or world:FindFirstChild(RoadGraphData.ROAD_GRAPH_NAME))
end

local function graphTransformSummary(world)
	local root = graphDataRoot(world)
	if not root then
		return "none"
	end

	return string.format(
		"%s status=%s error=%s offset=(%s,%s) matrix=[%s,%s;%s,%s]",
		tostring(root:GetAttribute("ImportedGlbCoordinateTransform") or "none"),
		tostring(root:GetAttribute("ImportedGlbCoordinateTransformApplied")),
		tostring(root:GetAttribute("ImportedGlbCoordinateTransformError")),
		tostring(root:GetAttribute("ImportedGlbCoordinateOffsetX")),
		tostring(root:GetAttribute("ImportedGlbCoordinateOffsetZ")),
		tostring(root:GetAttribute("ImportedGlbCoordinateXX")),
		tostring(root:GetAttribute("ImportedGlbCoordinateXZ")),
		tostring(root:GetAttribute("ImportedGlbCoordinateZX")),
		tostring(root:GetAttribute("ImportedGlbCoordinateZZ"))
	)
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
		local graphBounds = createBounds()
		local centerLineBounds = createBounds()
		for recordIndex, centerLine in ipairs(meshData.centerLines or {}) do
			if #centerLine >= 2 then
				local distanceSinceLastStop = spacing
				local previousPosition = nil
				local fallbackDir = horizontalUnit(centerLine[2] - centerLine[1]) or Vector3.new(0, 0, 1)
				for index, position in ipairs(centerLine) do
					includeBounds(centerLineBounds, position)
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

		for _, node in ipairs(graphData.nodes or {}) do
			includeBounds(graphBounds, node.point)
		end
		if world then
			world:SetAttribute("PassengerStopCandidateSource", "RoadGraph")
			world:SetAttribute("PassengerStopGraphNodeCount", #(graphData.nodes or {}))
			world:SetAttribute("PassengerStopGraphEdgeCount", #(graphData.edges or {}))
			world:SetAttribute("PassengerStopGraphCenterLineCount", #(meshData.centerLines or {}))
			world:SetAttribute("PassengerStopRawCandidateCount", #candidates)
			setBoundsAttributes(world, "PassengerStopGraphBounds", graphBounds)
			setBoundsAttributes(world, "PassengerStopCenterLineBounds", centerLineBounds)
		end
		debugLog(
			"authored graph candidates: world=%s meshSource=%s graph=%d nodes/%d edges centerLines=%d candidates=%d graphBounds=%s centerLineBounds=%s transform=%s",
			world and world:GetFullName() or "nil",
			tostring(world and world:GetAttribute("AuthoredRoadMeshSource") or "unknown"),
			#(graphData.nodes or {}),
			#(graphData.edges or {}),
			#(meshData.centerLines or {}),
			#candidates,
			formatBounds(graphBounds),
			formatBounds(centerLineBounds),
			graphTransformSummary(world)
		)

		return candidates
	end

	local dataRoot = world:FindFirstChild(ROAD_SPLINE_DATA_NAME)
	if not dataRoot then
		if world then
			world:SetAttribute("PassengerStopCandidateSource", "none")
			world:SetAttribute("PassengerStopRawCandidateCount", 0)
		end
		debugLog("no authored graph or spline data found for passenger stops in %s", world and world:GetFullName() or "nil")
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

	if world then
		world:SetAttribute("PassengerStopCandidateSource", "LegacyCurve")
		world:SetAttribute("PassengerStopRawCandidateCount", #candidates)
	end
	debugLog(
		"legacy curve candidates: world=%s records=%d candidates=%d",
		world and world:GetFullName() or "nil",
		#RoadSplineData.collectSplineRecords(dataRoot, { defaultRoadWidth = defaultRoadWidth }),
		#candidates
	)

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
			return result.Position, true, result.Instance
		end
	end

	return Vector3.new(position.X, fallbackY or position.Y, position.Z), false, nil
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
	local candidateSource = if #candidates > 0 then tostring((world and world:GetAttribute("PassengerStopCandidateSource")) or "Authored") else "Surface"
	local rawCandidateCount = #candidates

	if #candidates == 0 then
		candidates = collectSurfaceCandidates(driveSurfaces, minSeparation)
		rawCandidateCount = #candidates
		if #candidates > 0 then
			candidateSource = "DriveSurface"
			if world then
				world:SetAttribute("PassengerStopCandidateSource", candidateSource)
				world:SetAttribute("PassengerStopRawCandidateCount", rawCandidateCount)
			end
			debugLog(
				"drive surface candidates: world=%s driveSurfaces=%d candidates=%d",
				world and world:GetFullName() or "nil",
				countParts(driveSurfaces),
				#candidates
			)
		end
	end

	ensureMinimumCandidateCount(candidates, spawnPose)
	if rawCandidateCount == 0 and #candidates > 0 then
		candidateSource = "FallbackAroundCab"
		if world then
			world:SetAttribute("PassengerStopCandidateSource", candidateSource)
		end
	end
	shuffle(candidates, rng)

	local stops = {}
	local candidateBounds = createBounds()
	local stopBounds = createBounds()
	local projectionHits = 0
	local projectionMisses = 0
	local sampleCount = math.max(0, math.floor(getConfigNumber("passengerDebugSampleCount", 6)))
	local samples = {}
	for i = 1, math.min(#candidates, maxStops) do
		local candidate = candidates[i]
		includeBounds(candidateBounds, candidate)
		local position, hitSurface, surface = PassengerStopService.projectToSurface(surfaceRaycastParams, candidate, candidate.Y)
		includeBounds(stopBounds, position)
		if hitSurface then
			projectionHits += 1
		else
			projectionMisses += 1
		end
		if #samples < sampleCount then
			table.insert(samples, {
				index = i,
				candidate = candidate,
				position = position,
				hitSurface = hitSurface,
				surface = surface,
			})
		end
		local instance = PassengerVisuals.createStop(folder, i, position)
		instance:SetAttribute("ProjectionHit", hitSurface)
		instance:SetAttribute("ProjectionSurface", surface and surface:GetFullName() or "")
		setVectorAttributes(instance, "Candidate", candidate)
		setVectorAttributes(instance, "Projected", position)
		table.insert(stops, {
			id = i,
			position = position,
			instance = instance,
		})
	end

	folder:SetAttribute("StopCount", #stops)
	folder:SetAttribute("CandidateSource", candidateSource)
	folder:SetAttribute("RawCandidateCount", rawCandidateCount)
	folder:SetAttribute("FinalCandidateCount", #candidates)
	folder:SetAttribute("ProjectionHitCount", projectionHits)
	folder:SetAttribute("ProjectionMissCount", projectionMisses)
	folder:SetAttribute("DriveSurfaceCount", countParts(driveSurfaces))
	setBoundsAttributes(folder, "CandidateBounds", candidateBounds)
	setBoundsAttributes(folder, "StopBounds", stopBounds)
	if world then
		world:SetAttribute("PassengerStopCandidateSource", candidateSource)
		world:SetAttribute("PassengerStopRawCandidateCount", rawCandidateCount)
		world:SetAttribute("PassengerStopFinalCandidateCount", #candidates)
		world:SetAttribute("PassengerStopProjectionHitCount", projectionHits)
		world:SetAttribute("PassengerStopProjectionMissCount", projectionMisses)
		world:SetAttribute("PassengerStopDriveSurfaceCount", countParts(driveSurfaces))
		setBoundsAttributes(world, "PassengerStopCandidateBounds", candidateBounds)
		setBoundsAttributes(world, "PassengerStopBounds", stopBounds)
	end
	debugLog(
		"created stops: world=%s source=%s rawCandidates=%d finalCandidates=%d stops=%d driveSurfaces=%d raycast=%s hits=%d misses=%d candidateBounds=%s stopBounds=%s spawn=%s transform=%s",
		world and world:GetFullName() or "nil",
		candidateSource,
		rawCandidateCount,
		#candidates,
		#stops,
		countParts(driveSurfaces),
		tostring(surfaceRaycastParams ~= nil),
		projectionHits,
		projectionMisses,
		formatBounds(candidateBounds),
		formatBounds(stopBounds),
		formatVector(spawnPose and spawnPose.position or nil),
		graphTransformSummary(world)
	)
	for _, sample in ipairs(samples) do
		debugLog(
			"stop sample[%d]: candidate=%s projected=%s hit=%s surface=%s",
			sample.index,
			formatVector(sample.candidate),
			formatVector(sample.position),
			tostring(sample.hitSurface),
			sample.surface and sample.surface:GetFullName() or "nil"
		)
	end
	return stops, folder, surfaceRaycastParams
end

return PassengerStopService
