local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadSampling = require(Shared:WaitForChild("RoadSampling"))
local StateContracts = require(Shared:WaitForChild("StateContracts"))
local PassengerVisuals = require(script.Parent:WaitForChild("PassengerVisuals"))
local ServicesFolder = script.Parent:WaitForChild("Services")
local PassengerStopService = require(ServicesFolder:WaitForChild("PassengerStopService"))
local CabHudStatePublisher = require(ServicesFolder:WaitForChild("CabHudStatePublisher"))

local PassengerService = {}

local STOP_LAYOUT_TUNING_KEYS = PassengerStopService.STOP_LAYOUT_TUNING_KEYS

local function recordStopLayoutValues(service)
	PassengerStopService.recordStopLayoutValues(service.stopLayoutValues)
end

local rebuildPassengerStops

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

local horizontalDistance = RoadSampling.distanceXZ

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

local function getPerpendicularRight(direction)
	return Vector3.new(direction.Z, 0, -direction.X)
end

local function getSurfacePosition(service, position, fallbackY)
	return PassengerStopService.projectToSurface(service.surfaceRaycastParams, position, fallbackY)
end

local function setPassengerGroundPose(passenger, groundPosition, lookAt, moving, pose)
	passenger.position = groundPosition
	PassengerVisuals.setPose(passenger.visual, groundPosition, lookAt, moving, passenger.runPhase, pose)
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

local function getCabOwnerPlayer(car)
	if not car then
		return nil
	end

	local seat = car:FindFirstChild("DriverSeat")
	if not (seat and seat:IsA("VehicleSeat")) then
		return nil
	end

	local occupant = seat.Occupant
	return occupant and Players:GetPlayerFromCharacter(occupant.Parent) or nil
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

	PassengerVisuals.setDiving(passenger.visual, true, targetPosition)
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
		PassengerVisuals.setDiving(passenger.visual, false)
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
	PassengerVisuals.setDiving(passenger.visual, false)
end

local function isCabClearOfPosition(cabPosition, position)
	return horizontalDistance(cabPosition, position) >= getConfigNumber("passengerDiveClearDistance", 34)
end

local function setPickupMarkersVisible(service, visible)
	for _, passenger in ipairs(service.passengers) do
		if passenger.status == "waiting" then
			PassengerVisuals.setPickupVisible(passenger.visual, visible)
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
	}
	passenger.visual = PassengerVisuals.createPassenger(
		service.passengerFolder,
		passengerId,
		pickupStop.position,
		service.rng
	)
	PassengerVisuals.setPassengerStops(passenger.visual, pickupStop.id, targetStop.id)
	PassengerVisuals.createPickupMarker(passenger.visual, service.markerFolder, passengerId, pickupStop, pickupRadius)
	PassengerVisuals.createDeliveryMarker(passenger.visual, service.markerFolder, passengerId, targetStop, deliveryRadius)

	setPassengerGroundPose(passenger, pickupStop.position, targetStop.position, false)
	PassengerVisuals.setDeliveryVisible(passenger.visual, false)
	PassengerVisuals.setPickupVisible(passenger.visual, service.mode == "pickup")
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

local function destroyPassenger(passenger)
	PassengerVisuals.destroyPassenger(passenger.visual)
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
	service.forceNextCabStatePublish = true
	service.pickupCooldown = getConfigNumber("passengerModeSwitchCooldown", 0.45)
	passenger.status = "boarding"
	passenger.runPhase = 0
	clearPassengerDive(passenger)
	clearGpsDestination(service)
	setPickupMarkersVisible(service, false)
	PassengerVisuals.setPickupVisible(passenger.visual, false)
	PassengerVisuals.setDeliveryVisible(passenger.visual, false)
end

local function completeBoarding(service, passenger)
	passenger.status = "inCab"
	service.mode = "delivery"
	service.forceNextCabStatePublish = true
	service.pickupCooldown = getConfigNumber("passengerModeSwitchCooldown", 0.45)
	if service.fareService and service.fareService.beginFare then
		local routeDistance = horizontalDistance(passenger.pickupStop.position, passenger.targetStop.position)
		service.fareService:beginFare(routeDistance, getCabOwnerPlayer(service.car))
	end
	removeWaitingPassengersNearStop(service, passenger.targetStop)
	PassengerVisuals.setPassengerVisible(passenger.visual, false)
	PassengerVisuals.setDeliveryVisible(passenger.visual, true)
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
	service.forceNextCabStatePublish = true
	service.pickupCooldown = getConfigNumber("passengerModeSwitchCooldown", 0.45)
	service.faresCompleted += 1
	clearGpsDestination(service)

	passenger.status = "exiting"
	passenger.runPhase = 0
	passenger.position = getCabDoorPosition(service.car)
	passenger.exitTarget = passenger.targetStop.position
	PassengerVisuals.setParent(passenger.visual, service.passengerFolder)
	setPassengerGroundPose(passenger, passenger.position, passenger.exitTarget, false)
	PassengerVisuals.setPassengerVisible(passenger.visual, true)
	PassengerVisuals.destroyMarkers(passenger.visual)
	ensureWaitingPassengerCount(service)
	setPickupMarkersVisible(service, true)
end

local function failActiveDelivery(service)
	local passenger = service.activePassenger
	if not passenger then
		return
	end

	removeWaitingPassengersNearStop(service, passenger.targetStop)
	service.activePassenger = nil
	service.mode = "pickup"
	service.forceNextCabStatePublish = true
	service.pickupCooldown = getConfigNumber("passengerModeSwitchCooldown", 0.45)
	clearGpsDestination(service)

	destroyPassenger(passenger)
	for i = #service.passengers, 1, -1 do
		if service.passengers[i] == passenger then
			table.remove(service.passengers, i)
			break
		end
	end

	ensureWaitingPassengerCount(service)
	setPickupMarkersVisible(service, true)
end

local function finishExiting(service, passenger)
	PassengerVisuals.destroyPassenger(passenger.visual)

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
	CabHudStatePublisher.publish(
		service,
		cabPosition,
		cabSpeed,
		getNearestPickupDistance(service, cabPosition),
		countWaitingPassengers(service)
	)
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

	if service.mode == "delivery" and service.activePassenger and service.fareService then
		local hasActiveFare = service.fareService.hasActiveFare and service.fareService:hasActiveFare() or false
		if not hasActiveFare then
			local lastResult = service.fareService.getLastResult and service.fareService:getLastResult() or nil
			if lastResult and lastResult.status == "failed" then
				failActiveDelivery(service)
			end
		end
	end

	if service.pendingStopLayoutRebuild and service.mode == "pickup" then
		service.pendingStopLayoutRebuild = false
		rebuildPassengerStops(service)
		return
	end

	updateCabFareAttributes(service, cabPosition, cabSpeed)
	service.previousCabPosition = cabPosition
end

rebuildPassengerStops = function(service)
	clearGpsDestination(service)
	service.pendingStopLayoutRebuild = false
	service.forceNextCabStatePublish = true

	if service.fareService and service.fareService.failFare and service.mode == "delivery" then
		service.fareService:failFare()
	end

	for _, passenger in ipairs(service.passengers) do
		destroyPassenger(passenger)
	end

	table.clear(service.passengers)
	service.activePassenger = nil
	service.mode = "pickup"
	service.pickupCooldown = getConfigNumber("passengerModeSwitchCooldown", 0.45)
	service.nextPassengerId = 0
	service.rng = Random.new(service.rngSeed)

	if service.stopFolder and service.stopFolder.Parent then
		service.stopFolder:Destroy()
	end

	service.stops, service.stopFolder, service.surfaceRaycastParams = PassengerStopService.createPassengerStops({
		world = service.world,
		driveSurfaces = service.driveSurfaces,
		spawnPose = service.spawnPose,
		rng = service.rng,
	})
	service.world:SetAttribute("PassengerStopCount", #service.stops)
	recordStopLayoutValues(service)

	ensureWaitingPassengerCount(service)
	updateCabFareAttributes(service, service.car:GetPivot().Position, getCabSpeed(service.car))
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
		driveSurfaces = options.driveSurfaces,
		spawnPose = options.spawnPose,
		rngSeed = rngSeed,
		rng = Random.new(rngSeed),
		mode = "pickup",
		activePassenger = nil,
		faresCompleted = 0,
		nextPassengerId = 0,
		passengers = {},
		pickupCooldown = 0,
		elapsedTime = 0,
		lastDeltaTime = 0,
		pendingStopLayoutRebuild = false,
		stopLayoutValues = {},
		gpsService = options.gpsService,
		fareService = options.fareService,
		stateReplicator = options.stateReplicator,
		cabStateId = options.cabStateId or StateContracts.defaultCabId,
		forceNextCabStatePublish = true,
		lastCabAttributeMirrorAt = nil,
		previousCabPosition = nil,
		previousCabMotionDirection = nil,
		horizontalDistance = horizontalDistance,
	}
	car:SetAttribute(getConfigString("gameplayStateCabIdAttribute", "Cab87GameplayCabId"), service.cabStateId)

	service.stopFolder = nil
	service.passengerFolder = PassengerVisuals.recreateFolder(world, getConfigString("passengerFolderName", "Passengers"))
	service.markerFolder = PassengerVisuals.recreateFolder(world, getConfigString("passengerMarkersFolderName", "PassengerMarkers"))
	service.stops, service.stopFolder, service.surfaceRaycastParams = PassengerStopService.createPassengerStops({
		world = world,
		driveSurfaces = options.driveSurfaces,
		spawnPose = options.spawnPose,
		rng = service.rng,
	})
	service.world:SetAttribute("PassengerStopCount", #service.stops)
	recordStopLayoutValues(service)

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

	function service.applyLiveTuning(key)
		if STOP_LAYOUT_TUNING_KEYS[key] then
			if service.stopLayoutValues[key] == Config[key] then
				return
			end

			if service.mode ~= "pickup" then
				service.pendingStopLayoutRebuild = true
				return
			end

			rebuildPassengerStops(service)
		end
	end

	return service
end

return PassengerService
