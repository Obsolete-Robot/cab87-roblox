local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PassengerService = {}

local ROAD_SPLINE_DATA_NAME = "AuthoredRoadSplineData"
local ROAD_SPLINES_NAME = "Splines"
local ROAD_POINTS_NAME = "RoadPoints"
local PASSENGER_BASE_TRANSPARENCY_ATTR = "Cab87BaseTransparency"
local PASSENGER_TORSO_Y = 2.1
local PASSENGER_COLORS = {
	Color3.fromRGB(49, 151, 255),
	Color3.fromRGB(255, 122, 65),
	Color3.fromRGB(181, 92, 255),
	Color3.fromRGB(70, 210, 135),
	Color3.fromRGB(255, 216, 84),
	Color3.fromRGB(245, 82, 117),
}

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

local function getConfigColor(key, fallback)
	local value = Config[key]
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local function horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function getPassengerStopReservationDistance()
	local pickupRadius = math.max(getConfigNumber("passengerPickupRadius", 24), 1)
	local deliveryRadius = math.max(getConfigNumber("passengerDeliveryRadius", 28), 1)
	local stopSeparation = math.max(getConfigNumber("passengerStopMinSeparation", 80), 1)
	return math.max(stopSeparation, pickupRadius + deliveryRadius + 12)
end

local function horizontalUnit(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	local magnitude = horizontal.Magnitude
	if magnitude <= 0.001 then
		return nil
	end

	return horizontal / magnitude
end

local function sortedChildren(parent, className)
	local children = {}
	if not parent then
		return children
	end

	for _, child in ipairs(parent:GetChildren()) do
		if not className or child:IsA(className) then
			table.insert(children, child)
		end
	end

	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)

	return children
end

local function setPartRuntimeDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function makePart(parent, props)
	local part = Instance.new("Part")
	setPartRuntimeDefaults(part)
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local function setModelVisible(model, visible)
	if not model then
		return
	end

	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			local baseTransparency = item:GetAttribute(PASSENGER_BASE_TRANSPARENCY_ATTR)
			if type(baseTransparency) ~= "number" then
				baseTransparency = item.Transparency
				item:SetAttribute(PASSENGER_BASE_TRANSPARENCY_ATTR, baseTransparency)
			end

			item.Transparency = if visible then baseTransparency else 1
		elseif item:IsA("BillboardGui") or item:IsA("SurfaceGui") then
			item.Enabled = visible
		end
	end

	model:SetAttribute("Visible", visible)
end

local function recreateFolder(parent, name)
	local oldFolder = parent:FindFirstChild(name)
	if oldFolder then
		oldFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
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

local function collectAuthoredRoadCandidates(world, minSeparation)
	local candidates = {}
	local spacing = math.max(getConfigNumber("passengerStopSpacing", 160), 24)
	local dataRoot = world:FindFirstChild(ROAD_SPLINE_DATA_NAME)
	local splinesFolder = dataRoot and dataRoot:FindFirstChild(ROAD_SPLINES_NAME)
	if not (splinesFolder and splinesFolder:IsA("Folder")) then
		return candidates
	end

	for _, spline in ipairs(sortedChildren(splinesFolder, "Model")) do
		local pointsFolder = spline:FindFirstChild(ROAD_POINTS_NAME)
		local points = sortedChildren(pointsFolder, "Vector3Value")
		local distanceSinceLastStop = spacing
		local previousPosition = nil

		for _, point in ipairs(points) do
			local position = point.Value
			if previousPosition then
				distanceSinceLastStop += horizontalDistance(position, previousPosition)
			end

			if distanceSinceLastStop >= spacing then
				addCandidate(candidates, position, minSeparation)
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
	local edgeInset = math.max(getConfigNumber("passengerStopRoadEdgeInset", 12), 0)
	local configuredLateralOffset = math.max(getConfigNumber("passengerStopLateralOffset", 18), 0)

	for _, surface in ipairs(driveSurfaces or {}) do
		if canUseSurfaceForStops(surface) then
			local size = surface.Size
			local longAxisIsX = size.X >= size.Z
			local longSize = if longAxisIsX then size.X else size.Z
			local shortSize = if longAxisIsX then size.Z else size.X
			local halfLong = math.max(longSize * 0.5 - edgeInset, 0)
			local span = halfLong * 2
			local count = math.max(1, math.floor(span / spacing + 0.5) + 1)
			local maxLateral = math.max(shortSize * 0.5 - edgeInset, 0)
			local lateralOffset = math.min(configuredLateralOffset, maxLateral)
			local lateralOffsets = { 0 }

			if lateralOffset >= 6 then
				lateralOffsets = { -lateralOffset, lateralOffset }
			end

			for i = 1, count do
				local along = if count == 1 then 0 else -halfLong + span * ((i - 1) / (count - 1))
				for _, lateral in ipairs(lateralOffsets) do
					local localPosition = if longAxisIsX
						then Vector3.new(along, size.Y * 0.5, lateral)
						else Vector3.new(lateral, size.Y * 0.5, along)
					local worldPosition = surface.CFrame:PointToWorldSpace(localPosition)
					addCandidate(candidates, worldPosition, minSeparation)
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

local function shuffle(values, rng)
	for i = #values, 2, -1 do
		local j = rng:NextInteger(1, i)
		values[i], values[j] = values[j], values[i]
	end
end

local function createStopPart(parent, id, position)
	local part = makePart(parent, {
		Name = string.format("PassengerStop_%03d", id),
		Size = Vector3.new(2, 0.2, 2),
		Position = position,
		Transparency = 1,
		Color = Color3.fromRGB(255, 255, 255),
	})
	part:SetAttribute("PassengerStopId", id)
	part:SetAttribute("GeneratedBy", "Cab87PassengerService")
	return part
end

local function createPassengerStops(world, driveSurfaces, spawnPose, rng)
	local folderName = getConfigString("passengerStopFolderName", "PassengerStops")
	local folder = recreateFolder(world, folderName)
	local minSeparation = math.max(getConfigNumber("passengerStopMinSeparation", 80), 1)
	local maxStops = math.max(2, math.floor(getConfigNumber("passengerMaxStops", 36)))
	local candidates = collectAuthoredRoadCandidates(world, minSeparation)

	if #candidates == 0 then
		candidates = collectSurfaceCandidates(driveSurfaces, minSeparation)
	end

	ensureMinimumCandidateCount(candidates, spawnPose)
	shuffle(candidates, rng)

	local stops = {}
	for i = 1, math.min(#candidates, maxStops) do
		local position = candidates[i]
		table.insert(stops, {
			id = i,
			position = position,
			instance = createStopPart(folder, i, position),
		})
	end

	folder:SetAttribute("StopCount", #stops)
	return stops, folder
end

local function createCircleMarker(parent, name, position, radius, color)
	local marker = Instance.new("Model")
	marker.Name = name
	marker:SetAttribute("Radius", radius)
	marker:SetAttribute("GeneratedBy", "Cab87PassengerService")
	marker.Parent = parent

	local segments = math.max(12, math.floor(getConfigNumber("passengerMarkerSegments", 28)))
	local thickness = math.max(getConfigNumber("passengerMarkerThickness", 0.35), 0.05)
	local transparency = math.clamp(getConfigNumber("passengerMarkerTransparency", 0.12), 0, 1)
	local heightOffset = getConfigNumber("passengerMarkerHeightOffset", 0.25)
	local segmentLength = (2 * math.pi * radius / segments) * 0.92
	local y = position.Y + heightOffset

	for i = 1, segments do
		local angle = ((i - 1) / segments) * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local segmentPosition = Vector3.new(position.X, y, position.Z) + radial * radius
		local segment = makePart(marker, {
			Name = string.format("Segment_%02d", i),
			Size = Vector3.new(thickness, 0.12, segmentLength),
			CFrame = CFrame.lookAt(segmentPosition, segmentPosition + tangent),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = transparency,
		})
		segment:SetAttribute(PASSENGER_BASE_TRANSPARENCY_ATTR, transparency)
	end

	return marker
end

local function getSurfacePosition(service, position, fallbackY)
	local raycastParams = service.surfaceRaycastParams
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

local function createPassengerModel(parent, passengerId, position, rng)
	local model = Instance.new("Model")
	model.Name = string.format("Passenger_%03d", passengerId)
	model:SetAttribute("PassengerId", passengerId)
	model:SetAttribute("GeneratedBy", "Cab87PassengerService")
	model.Parent = parent

	local shirtColor = PASSENGER_COLORS[((passengerId - 1) % #PASSENGER_COLORS) + 1]
	local pantsColor = Color3.fromRGB(
		rng:NextInteger(35, 80),
		rng:NextInteger(40, 90),
		rng:NextInteger(45, 100)
	)

	local torso = makePart(model, {
		Name = "Torso",
		Size = Vector3.new(1.7, 2.2, 0.85),
		Position = position + Vector3.new(0, PASSENGER_TORSO_Y, 0),
		Color = shirtColor,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.1, 1.1, 1.1),
		Position = position + Vector3.new(0, 3.55, 0),
		Color = Color3.fromRGB(232, 184, 142),
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "LeftLeg",
		Size = Vector3.new(0.65, 1.55, 0.65),
		Position = position + Vector3.new(-0.42, 0.72, 0),
		Color = pantsColor,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "RightLeg",
		Size = Vector3.new(0.65, 1.55, 0.65),
		Position = position + Vector3.new(0.42, 0.72, 0),
		Color = pantsColor,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "LeftArm",
		Size = Vector3.new(0.45, 1.75, 0.45),
		Position = position + Vector3.new(-1.08, 2.05, 0),
		Color = shirtColor,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "RightArm",
		Size = Vector3.new(0.45, 1.75, 0.45),
		Position = position + Vector3.new(1.08, 2.05, 0),
		Color = shirtColor,
		Material = Enum.Material.SmoothPlastic,
	})

	model.PrimaryPart = torso
	return model
end

local function setPassengerGroundPose(passenger, groundPosition, lookAt, moving, pose)
	local runBob = if moving then math.abs(math.sin(passenger.runPhase or 0)) * 0.16 else 0
	local heightOffset = (pose and pose.heightOffset) or 0
	local torsoPosition = groundPosition + Vector3.new(0, PASSENGER_TORSO_Y + runBob + heightOffset, 0)
	local lookDirection = lookAt and Vector3.new(lookAt.X - groundPosition.X, 0, lookAt.Z - groundPosition.Z) or Vector3.zero
	local pivot

	if lookDirection.Magnitude > 0.001 then
		pivot = CFrame.lookAt(torsoPosition, torsoPosition + lookDirection.Unit)
	else
		pivot = CFrame.new(torsoPosition)
	end

	local pitchRadians = (pose and pose.pitchRadians) or 0
	local rollRadians = (pose and pose.rollRadians) or 0
	if math.abs(pitchRadians) > 0.001 or math.abs(rollRadians) > 0.001 then
		pivot *= CFrame.Angles(pitchRadians, 0, rollRadians)
	end

	passenger.position = groundPosition
	passenger.model:PivotTo(pivot)
end

local function moveTowards(current, target, maxDistance)
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= maxDistance or distance <= 0.001 then
		return target, true
	end

	return current + delta.Unit * maxDistance, false
end

local function easeOutQuad(alpha)
	local inverse = 1 - alpha
	return 1 - inverse * inverse
end

local function getCabDoorPosition(car)
	local pivot = car:GetPivot()
	local rideHeight = getConfigNumber("carRideHeight", 2.3)
	return pivot:PointToWorldSpace(Vector3.new(-6.3, -rideHeight + 0.15, 0.8))
end

local function getCabSpeed(car)
	local speedAttribute = getConfigString("carSpeedAttribute", "Cab87Speed")
	local speed = car:GetAttribute(speedAttribute)
	if type(speed) ~= "number" then
		return 0
	end

	return math.max(speed, 0)
end

local function getCabMotionDirection(service, cabPivot, cabPosition)
	local previousCabPosition = service.previousCabPosition
	if previousCabPosition then
		local delta = Vector3.new(cabPosition.X - previousCabPosition.X, 0, cabPosition.Z - previousCabPosition.Z)
		local deltaDirection = horizontalUnit(delta)
		if deltaDirection then
			service.previousCabMotionDirection = deltaDirection
			return deltaDirection
		end
	end

	local fallbackDirection = horizontalUnit(cabPivot:VectorToWorldSpace(Vector3.new(0, 0, 1)))
	return service.previousCabMotionDirection or fallbackDirection
end

local function getPerpendicularRight(direction)
	return Vector3.new(direction.Z, 0, -direction.X)
end

local function getPassengerCabThreat(passenger, cabPosition, cabDirection, cabSpeed)
	if not cabDirection or cabSpeed < getConfigNumber("passengerDiveMinCabSpeed", 18) then
		return nil
	end

	local toPassenger = Vector3.new(
		passenger.position.X - cabPosition.X,
		0,
		passenger.position.Z - cabPosition.Z
	)
	local forwardDistance = toPassenger:Dot(cabDirection)
	if forwardDistance < 0 then
		return nil
	end

	local lookAhead = math.clamp(
		cabSpeed * getConfigNumber("passengerDiveReactionTime", 0.4),
		getConfigNumber("passengerDiveMinAheadDistance", 18),
		getConfigNumber("passengerDiveMaxAheadDistance", 54)
	)
	if forwardDistance > lookAhead then
		return nil
	end

	local right = getPerpendicularRight(cabDirection)
	local lateralOffset = toPassenger:Dot(right)
	local threatHalfWidth = math.max(getConfigNumber("passengerDiveThreatHalfWidth", 9), 1)
	if math.abs(lateralOffset) > threatHalfWidth then
		return nil
	end

	return {
		right = right,
		lateralOffset = lateralOffset,
		threatHalfWidth = threatHalfWidth,
	}
end

local function startPassengerDive(service, passenger, threat)
	local side = 1
	if threat.lateralOffset < -0.05 then
		side = -1
	elseif math.abs(threat.lateralOffset) <= 0.05 and passenger.id % 2 == 1 then
		side = -1
	end

	local diveDirection = threat.right * side
	local clearance = math.max(getConfigNumber("passengerDiveClearance", 8), 0)
	local requiredDistance = threat.threatHalfWidth + clearance - math.abs(threat.lateralOffset)
	local diveDistance = math.clamp(
		requiredDistance,
		getConfigNumber("passengerDiveMinDistance", 14),
		getConfigNumber("passengerDiveMaxDistance", 30)
	)
	local targetPosition = getSurfacePosition(
		service,
		passenger.position + diveDirection * diveDistance,
		passenger.position.Y
	)
	local diveSpeed = math.max(getConfigNumber("passengerDiveSpeed", 72), 1)

	passenger.dive = {
		elapsed = 0,
		duration = math.max(diveDistance / diveSpeed, 0.08),
		startPosition = passenger.position,
		targetPosition = targetPosition,
		direction = diveDirection,
		side = side,
	}
	passenger.diveCooldown = math.max(getConfigNumber("passengerDiveCooldown", 0.9), 0)
	if passenger.status == "waiting" then
		passenger.diveReturnDelay = math.max(getConfigNumber("passengerDiveReturnDelay", 0.55), 0)
	end

	passenger.model:SetAttribute("Diving", true)
	passenger.model:SetAttribute("DiveTarget", targetPosition)
end

local function tryStartPassengerDive(service, passenger, cabPosition, cabDirection, cabSpeed)
	if passenger.dive or (passenger.diveCooldown or 0) > 0 then
		return false
	end

	local threat = getPassengerCabThreat(passenger, cabPosition, cabDirection, cabSpeed)
	if not threat then
		return false
	end

	startPassengerDive(service, passenger, threat)
	return true
end

local function updatePassengerDive(passenger, dt)
	local dive = passenger.dive
	if not dive then
		return false
	end

	dive.elapsed += dt
	local alpha = math.clamp(dive.elapsed / dive.duration, 0, 1)
	local easedAlpha = easeOutQuad(alpha)
	local arcHeight = math.max(getConfigNumber("passengerDiveArcHeight", 5), 0)
	local arcOffset = math.sin(alpha * math.pi) * arcHeight
	local nextPosition = dive.startPosition:Lerp(dive.targetPosition, easedAlpha) + Vector3.new(0, arcOffset, 0)
	local divePoseAlpha = math.sin(alpha * math.pi)
	local leanRadians = math.rad(getConfigNumber("passengerDiveLeanDegrees", 62)) * divePoseAlpha
	local rollRadians = math.rad(getConfigNumber("passengerDiveRollDegrees", 26)) * (dive.side or 1) * divePoseAlpha

	passenger.runPhase += dt * 18
	setPassengerGroundPose(passenger, nextPosition, nextPosition + dive.direction, true, {
		heightOffset = -0.35 * divePoseAlpha,
		pitchRadians = -leanRadians,
		rollRadians = rollRadians,
	})

	if alpha >= 1 then
		passenger.dive = nil
		passenger.model:SetAttribute("Diving", false)
	end

	return true
end

local function updatePassengerDiveTimers(passenger, dt)
	passenger.diveCooldown = math.max((passenger.diveCooldown or 0) - dt, 0)
	passenger.diveReturnDelay = math.max((passenger.diveReturnDelay or 0) - dt, 0)
end

local function clearPassengerDive(passenger)
	passenger.dive = nil
	passenger.diveReturnDelay = 0
	if passenger.model then
		passenger.model:SetAttribute("Diving", false)
	end
end

local function isCabClearOfPosition(cabPosition, position)
	return horizontalDistance(cabPosition, position) >= getConfigNumber("passengerDiveClearDistance", 34)
end

local function setPickupMarkersVisible(service, visible)
	for _, passenger in ipairs(service.passengers) do
		if passenger.status == "waiting" then
			setModelVisible(passenger.pickupMarker, visible)
		end
	end
end

local function countWaitingPassengers(service)
	local count = 0
	for _, passenger in ipairs(service.passengers) do
		if passenger.status == "waiting" then
			count += 1
		end
	end

	return count
end

local function isStopReservedByPassenger(service, stop)
	local reservationDistance = getPassengerStopReservationDistance()

	for _, passenger in ipairs(service.passengers) do
		if
			passenger.pickupStop
			and passenger.status ~= "exiting"
			and horizontalDistance(passenger.pickupStop.position, stop.position) <= reservationDistance
		then
			return true
		end

		if
			passenger.targetStop
			and horizontalDistance(passenger.targetStop.position, stop.position) <= reservationDistance
		then
			return true
		end
	end

	return false
end

local function isPickupStopAvailable(service, stop)
	return not isStopReservedByPassenger(service, stop)
end

local function choosePickupStop(service)
	local candidates = {}
	for _, stop in ipairs(service.stops) do
		if isPickupStopAvailable(service, stop) then
			table.insert(candidates, stop)
		end
	end

	if #candidates == 0 then
		return nil
	end

	return candidates[service.rng:NextInteger(1, #candidates)]
end

local function chooseTargetStop(service, pickupStop)
	local minDistance = math.max(getConfigNumber("passengerMinTripDistance", 320), 1)
	local candidates = {}
	local farthestStop = nil
	local farthestDistance = -math.huge

	for _, stop in ipairs(service.stops) do
		if stop ~= pickupStop and not isStopReservedByPassenger(service, stop) then
			local distance = horizontalDistance(stop.position, pickupStop.position)
			if distance >= minDistance then
				table.insert(candidates, stop)
			end

			if distance > farthestDistance then
				farthestDistance = distance
				farthestStop = stop
			end
		end
	end

	if #candidates > 0 then
		return candidates[service.rng:NextInteger(1, #candidates)]
	end

	return farthestStop
end

local function spawnWaitingPassenger(service)
	local pickupStop = choosePickupStop(service)
	if not pickupStop then
		return nil
	end

	local targetStop = chooseTargetStop(service, pickupStop)
	if not targetStop then
		return nil
	end

	service.nextPassengerId += 1
	local passengerId = service.nextPassengerId
	local pickupRadius = math.max(getConfigNumber("passengerPickupRadius", 24), 1)
	local deliveryRadius = math.max(getConfigNumber("passengerDeliveryRadius", 28), 1)
	local passenger = {
		id = passengerId,
		status = "waiting",
		pickupStop = pickupStop,
		targetStop = targetStop,
		runPhase = 0,
		position = pickupStop.position,
		model = createPassengerModel(service.passengerFolder, passengerId, pickupStop.position, service.rng),
	}

	passenger.pickupMarker = createCircleMarker(
		service.markerFolder,
		string.format("PickupCircle_%03d", passengerId),
		pickupStop.position,
		pickupRadius,
		getConfigColor("passengerPickupColor", Color3.fromRGB(70, 255, 120))
	)
	passenger.deliveryMarker = createCircleMarker(
		service.markerFolder,
		string.format("DeliveryCircle_%03d", passengerId),
		targetStop.position,
		deliveryRadius,
		getConfigColor("passengerDeliveryColor", Color3.fromRGB(255, 70, 55))
	)

	passenger.model:SetAttribute("PickupStopId", pickupStop.id)
	passenger.model:SetAttribute("TargetStopId", targetStop.id)
	passenger.model:SetAttribute("Diving", false)
	passenger.pickupMarker:SetAttribute("PassengerId", passengerId)
	passenger.pickupMarker:SetAttribute("PickupStopId", pickupStop.id)
	passenger.deliveryMarker:SetAttribute("PassengerId", passengerId)
	passenger.deliveryMarker:SetAttribute("TargetStopId", targetStop.id)

	setPassengerGroundPose(passenger, pickupStop.position, targetStop.position, false)
	setModelVisible(passenger.deliveryMarker, false)
	setModelVisible(passenger.pickupMarker, service.mode == "pickup")
	table.insert(service.passengers, passenger)
	return passenger
end

local function ensureWaitingPassengerCount(service)
	local targetCount = math.max(1, math.floor(getConfigNumber("passengerActiveCount", 5)))
	while countWaitingPassengers(service) < targetCount do
		if not spawnWaitingPassenger(service) then
			break
		end
	end

	setPickupMarkersVisible(service, service.mode == "pickup")
end

local function clearGpsDestination(service)
	local gpsService = service.gpsService
	if gpsService and gpsService.clearDestination then
		gpsService:clearDestination()
	end
end

local function setGpsDestination(service, destination)
	local gpsService = service.gpsService
	if gpsService and gpsService.setDestination then
		gpsService:setDestination(destination)
	end
end

local function destroyPassengerMarker(marker)
	if marker and marker.Parent then
		marker:Destroy()
	end
end

local function destroyPassenger(passenger)
	if passenger.model and passenger.model.Parent then
		passenger.model:Destroy()
	end

	destroyPassengerMarker(passenger.pickupMarker)
	destroyPassengerMarker(passenger.deliveryMarker)
end

local function removeWaitingPassengersNearStop(service, stop)
	local reservationDistance = getPassengerStopReservationDistance()

	for i = #service.passengers, 1, -1 do
		local passenger = service.passengers[i]
		if
			passenger.status == "waiting"
			and passenger.pickupStop
			and horizontalDistance(passenger.pickupStop.position, stop.position) <= reservationDistance
		then
			destroyPassenger(passenger)
			table.remove(service.passengers, i)
		end
	end
end

local function startBoarding(service, passenger)
	if service.activePassenger then
		return
	end

	service.activePassenger = passenger
	service.mode = "boarding"
	service.pickupCooldown = getConfigNumber("passengerModeSwitchCooldown", 0.45)
	passenger.status = "boarding"
	passenger.runPhase = 0
	clearPassengerDive(passenger)
	clearGpsDestination(service)
	setPickupMarkersVisible(service, false)
	setModelVisible(passenger.pickupMarker, false)
	setModelVisible(passenger.deliveryMarker, false)
end

local function completeBoarding(service, passenger)
	passenger.status = "inCab"
	service.mode = "delivery"
	service.pickupCooldown = getConfigNumber("passengerModeSwitchCooldown", 0.45)
	if service.fareService and service.fareService.beginFare then
		local routeDistance = horizontalDistance(passenger.pickupStop.position, passenger.targetStop.position)
		service.fareService:beginFare(routeDistance)
	end
	removeWaitingPassengersNearStop(service, passenger.targetStop)
	setModelVisible(passenger.model, false)
	setModelVisible(passenger.deliveryMarker, true)
	setPickupMarkersVisible(service, false)
	setGpsDestination(service, passenger.targetStop.position)
	ensureWaitingPassengerCount(service)
end

local function completeDelivery(service)
	local passenger = service.activePassenger
	if not passenger then
		return
	end

	if service.fareService and service.fareService.completeFare then
		service.fareService:completeFare()
	end

	removeWaitingPassengersNearStop(service, passenger.targetStop)
	service.activePassenger = nil
	service.mode = "pickup"
	service.pickupCooldown = getConfigNumber("passengerModeSwitchCooldown", 0.45)
	service.faresCompleted += 1
	clearGpsDestination(service)

	passenger.status = "exiting"
	passenger.runPhase = 0
	passenger.position = getCabDoorPosition(service.car)
	passenger.exitTarget = passenger.targetStop.position
	passenger.model.Parent = service.passengerFolder
	setPassengerGroundPose(passenger, passenger.position, passenger.exitTarget, false)
	setModelVisible(passenger.model, true)
	destroyPassengerMarker(passenger.pickupMarker)
	destroyPassengerMarker(passenger.deliveryMarker)
	ensureWaitingPassengerCount(service)
	setPickupMarkersVisible(service, true)
end

local function finishExiting(service, passenger)
	if passenger.model and passenger.model.Parent then
		passenger.model:Destroy()
	end

	for i = #service.passengers, 1, -1 do
		if service.passengers[i] == passenger then
			table.remove(service.passengers, i)
			break
		end
	end
end

local function updateWaitingPassenger(service, passenger, dt, cabPosition, cabDirection, cabSpeed)
	updatePassengerDiveTimers(passenger, dt)
	tryStartPassengerDive(service, passenger, cabPosition, cabDirection, cabSpeed)
	if updatePassengerDive(passenger, dt) then
		return
	end

	local pickupPosition = passenger.pickupStop.position
	if horizontalDistance(passenger.position, pickupPosition) <= 0.25 then
		return
	end

	if (passenger.diveReturnDelay or 0) > 0 or not isCabClearOfPosition(cabPosition, pickupPosition) then
		setPassengerGroundPose(passenger, passenger.position, passenger.targetStop.position, false)
		return
	end

	local maxDistance = math.max(getConfigNumber("passengerDiveReturnSpeed", 16), 1) * dt
	local nextPosition, arrived = moveTowards(passenger.position, pickupPosition, maxDistance)
	passenger.runPhase += dt * 8
	setPassengerGroundPose(passenger, nextPosition, pickupPosition, true)

	if arrived then
		setPassengerGroundPose(passenger, pickupPosition, passenger.targetStop.position, false)
	end
end

local function updateBoarding(service, passenger, dt)
	local target = getCabDoorPosition(service.car)
	local fallbackSpeed = getConfigNumber("passengerWalkSpeed", 24)
	local maxDistance = math.max(getConfigNumber("passengerBoardingSpeed", fallbackSpeed), 1) * dt
	local nextPosition, arrived = moveTowards(passenger.position, target, maxDistance)
	passenger.runPhase += dt * 10
	setPassengerGroundPose(passenger, nextPosition, target, true)

	if arrived or horizontalDistance(nextPosition, target) <= 1.5 then
		completeBoarding(service, passenger)
	end
end

local function updateExiting(service, passenger, dt, cabPosition, cabDirection, cabSpeed)
	updatePassengerDiveTimers(passenger, dt)
	tryStartPassengerDive(service, passenger, cabPosition, cabDirection, cabSpeed)
	if updatePassengerDive(passenger, dt) then
		return
	end

	local target = passenger.exitTarget or passenger.targetStop.position
	local fallbackSpeed = getConfigNumber("passengerWalkSpeed", 24)
	local maxDistance = math.max(getConfigNumber("passengerExitSpeed", fallbackSpeed), 1) * dt
	local nextPosition, arrived = moveTowards(passenger.position, target, maxDistance)
	passenger.runPhase += dt * 10
	setPassengerGroundPose(passenger, nextPosition, target, true)

	if arrived or horizontalDistance(nextPosition, target) <= 1.5 then
		finishExiting(service, passenger)
	end
end

local function getNearestWaitingPassenger(service, cabPosition, radius)
	local nearestPassenger = nil
	local nearestDistance = math.huge

	for _, passenger in ipairs(service.passengers) do
		if passenger.status == "waiting" then
			local distance = horizontalDistance(cabPosition, passenger.pickupStop.position)
			if distance <= radius and distance < nearestDistance then
				nearestPassenger = passenger
				nearestDistance = distance
			end
		end
	end

	return nearestPassenger, nearestDistance
end

local function getNearestPickupDistance(service, cabPosition)
	local nearestDistance = math.huge
	for _, passenger in ipairs(service.passengers) do
		if passenger.status == "waiting" then
			nearestDistance = math.min(nearestDistance, horizontalDistance(cabPosition, passenger.pickupStop.position))
		end
	end

	return nearestDistance
end

local function updateCabFareAttributes(service, cabPosition, cabSpeed)
	local modeAttr = getConfigString("passengerFareModeAttribute", "Cab87FareMode")
	local statusAttr = getConfigString("passengerFareStatusAttribute", "Cab87FareStatus")
	local distanceAttr = getConfigString("passengerFareDistanceAttribute", "Cab87FareDistance")
	local destinationAttr = getConfigString("passengerDestinationAttribute", "Cab87FareDestination")
	local completedAttr = getConfigString("passengerFareCompletedAttribute", "Cab87FaresCompleted")
	local waitingAttr = getConfigString("passengerWaitingCountAttribute", "Cab87WaitingPassengers")
	local fareEstimateAttr = getConfigString("passengerFareEstimateAttribute", "Cab87FareEstimate")
	local fareActiveAttr = getConfigString("passengerFareActiveValueAttribute", "Cab87FareActiveValue")
	local farePayoutAttr = getConfigString("passengerFarePayoutAttribute", "Cab87FarePayout")
	local fareTimeComponentAttr = getConfigString("passengerFareTimeComponentAttribute", "Cab87FareTimeComponent")
	local fareSpeedBonusAttr = getConfigString("passengerFareSpeedBonusAttribute", "Cab87FareSpeedBonus")
	local fareDamagePenaltyAttr = getConfigString("passengerFareDamagePenaltyAttribute", "Cab87FareDamagePenalty")
	local fareDamageCollisionsAttr = getConfigString("passengerFareDamageCollisionsAttribute", "Cab87FareDamageCollisions")
	local fareDamageSeverityAttr = getConfigString("passengerFareDamageSeverityAttribute", "Cab87FareDamageSeverity")
	local fareDamagePointsAttr = getConfigString("passengerFareDamagePointsAttribute", "Cab87FareDamagePoints")
	local fareResultStatusAttr = getConfigString("passengerFareResultStatusAttribute", "Cab87FareResultStatus")
	local fareDurationAttr = getConfigString("passengerFareDurationAttribute", "Cab87FareDuration")
	local fareRouteDistanceAttr = getConfigString("passengerFareRouteDistanceAttribute", "Cab87FareRouteDistance")
	local stoppedSpeed = getConfigNumber("passengerStoppedSpeed", 1.25)
	local status = "Find a pickup"
	local distance = getNearestPickupDistance(service, cabPosition)
	local destination = nil

	if service.mode == "boarding" then
		status = "Passenger boarding"
		local passenger = service.activePassenger
		distance = passenger and horizontalDistance(cabPosition, passenger.pickupStop.position) or 0
	elseif service.mode == "delivery" then
		status = "Deliver passenger"
		local passenger = service.activePassenger
		if passenger then
			destination = passenger.targetStop.position
			distance = horizontalDistance(cabPosition, passenger.targetStop.position)
			if distance <= getConfigNumber("passengerDeliveryRadius", 28) and cabSpeed > stoppedSpeed then
				status = "Stop to drop off"
			end
		else
			distance = 0
		end
	elseif distance == math.huge then
		status = "No pickups"
		distance = 0
	elseif distance <= getConfigNumber("passengerPickupRadius", 24) and cabSpeed > stoppedSpeed then
		status = "Stop to board"
	end

	service.car:SetAttribute(modeAttr, service.mode)
	service.car:SetAttribute(statusAttr, status)
	service.car:SetAttribute(distanceAttr, math.floor(distance + 0.5))
	service.car:SetAttribute(destinationAttr, destination)
	service.car:SetAttribute(completedAttr, service.faresCompleted)
	service.car:SetAttribute(waitingAttr, countWaitingPassengers(service))

	local fareSnapshot = nil
	if service.fareService and service.fareService.getActiveSnapshot then
		fareSnapshot = service.fareService:getActiveSnapshot()
	end
	if not fareSnapshot and service.fareService and service.fareService.getLastResult then
		fareSnapshot = service.fareService:getLastResult()
	end

	fareSnapshot = fareSnapshot or {
		status = "idle",
		estimatedPayout = 0,
		activeValue = 0,
		payout = 0,
		timeComponent = 0,
		speedBonus = 0,
		damagePenalty = 0,
		damageCollisions = 0,
		damageSeverity = 0,
		damagePoints = 0,
		durationSeconds = 0,
		routeDistance = 0,
	}

	service.car:SetAttribute(fareEstimateAttr, math.max(math.floor((fareSnapshot.estimatedPayout or 0) + 0.5), 0))
	service.car:SetAttribute(fareActiveAttr, math.max(math.floor((fareSnapshot.activeValue or 0) + 0.5), 0))
	service.car:SetAttribute(farePayoutAttr, math.max(math.floor((fareSnapshot.payout or 0) + 0.5), 0))
	service.car:SetAttribute(fareTimeComponentAttr, math.floor((fareSnapshot.timeComponent or 0) + 0.5))
	service.car:SetAttribute(fareSpeedBonusAttr, math.max(math.floor((fareSnapshot.speedBonus or 0) + 0.5), 0))
	service.car:SetAttribute(fareDamagePenaltyAttr, math.max(math.floor((fareSnapshot.damagePenalty or 0) + 0.5), 0))
	service.car:SetAttribute(fareDamageCollisionsAttr, math.max(math.floor((fareSnapshot.damageCollisions or 0) + 0.5), 0))
	service.car:SetAttribute(fareDamageSeverityAttr, math.max(fareSnapshot.damageSeverity or 0, 0))
	service.car:SetAttribute(fareDamagePointsAttr, math.max(fareSnapshot.damagePoints or 0, 0))
	service.car:SetAttribute(fareResultStatusAttr, tostring(fareSnapshot.status or "idle"))
	service.car:SetAttribute(fareDurationAttr, math.max(fareSnapshot.durationSeconds or 0, 0))
	service.car:SetAttribute(fareRouteDistanceAttr, math.max(fareSnapshot.routeDistance or 0, 0))
end

local function updateService(service, dt)
	dt = math.min(dt, 0.1)
	service.elapsedTime += dt
	service.lastDeltaTime = dt
	service.pickupCooldown = math.max((service.pickupCooldown or 0) - dt, 0)

	local cabPivot = service.car:GetPivot()
	local cabPosition = cabPivot.Position
	local cabSpeed = getCabSpeed(service.car)
	local cabMotionDirection = getCabMotionDirection(service, cabPivot, cabPosition)

	for i = #service.passengers, 1, -1 do
		local passenger = service.passengers[i]
		if passenger.status == "waiting" then
			updateWaitingPassenger(service, passenger, dt, cabPosition, cabMotionDirection, cabSpeed)
		elseif passenger.status == "boarding" then
			updateBoarding(service, passenger, dt)
		elseif passenger.status == "exiting" then
			updateExiting(service, passenger, dt, cabPosition, cabMotionDirection, cabSpeed)
		end
	end

	local stoppedSpeed = getConfigNumber("passengerStoppedSpeed", 1.25)
	local hasDriver = service.car:GetAttribute("Cab87HasDriver") == true

	if service.mode == "pickup" then
		ensureWaitingPassengerCount(service)

		if hasDriver and service.pickupCooldown <= 0 and cabSpeed <= stoppedSpeed then
			local passenger = getNearestWaitingPassenger(
				service,
				cabPosition,
				math.max(getConfigNumber("passengerPickupRadius", 24), 1)
			)
			if passenger then
				startBoarding(service, passenger)
			end
		end
	elseif service.mode == "delivery" and hasDriver and cabSpeed <= stoppedSpeed then
		local passenger = service.activePassenger
		if passenger and horizontalDistance(cabPosition, passenger.targetStop.position) <= getConfigNumber("passengerDeliveryRadius", 28) then
			completeDelivery(service)
		end
	end

	updateCabFareAttributes(service, cabPosition, cabSpeed)
	service.previousCabPosition = cabPosition
end

function PassengerService.start(options)
	local world = options and options.world
	local car = options and options.car
	if not (world and car) then
		return nil
	end

	local rngSeed = tonumber(world:GetAttribute("Seed")) or os.time()
	local service = {
		world = world,
		car = car,
		rng = Random.new(rngSeed),
		mode = "pickup",
		activePassenger = nil,
		faresCompleted = 0,
		nextPassengerId = 0,
		passengers = {},
		pickupCooldown = 0,
		elapsedTime = 0,
		lastDeltaTime = 0,
		gpsService = options.gpsService,
		fareService = options.fareService,
		previousCabPosition = nil,
		previousCabMotionDirection = nil,
	}

	service.stopFolder = nil
	service.passengerFolder = recreateFolder(world, getConfigString("passengerFolderName", "Passengers"))
	service.markerFolder = recreateFolder(world, getConfigString("passengerMarkersFolderName", "PassengerMarkers"))
	service.stops, service.stopFolder = createPassengerStops(world, options.driveSurfaces, options.spawnPose, service.rng)
	if options.driveSurfaces and #options.driveSurfaces > 0 then
		service.surfaceRaycastParams = RaycastParams.new()
		service.surfaceRaycastParams.FilterType = Enum.RaycastFilterType.Include
		service.surfaceRaycastParams.FilterDescendantsInstances = options.driveSurfaces
	end
	service.world:SetAttribute("PassengerStopCount", #service.stops)

	ensureWaitingPassengerCount(service)
	updateCabFareAttributes(service, car:GetPivot().Position, getCabSpeed(car))

	service.heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		updateService(service, dt)
	end)

	function service.stop()
		clearGpsDestination(service)
		if service.fareService and service.fareService.failFare and service.mode == "delivery" then
			service.fareService:failFare()
		end

		if service.heartbeatConnection then
			service.heartbeatConnection:Disconnect()
			service.heartbeatConnection = nil
		end

		if service.passengerFolder and service.passengerFolder.Parent then
			service.passengerFolder:Destroy()
		end

		if service.markerFolder and service.markerFolder.Parent then
			service.markerFolder:Destroy()
		end

		if service.stopFolder and service.stopFolder.Parent then
			service.stopFolder:Destroy()
		end
	end

	return service
end

return PassengerService
