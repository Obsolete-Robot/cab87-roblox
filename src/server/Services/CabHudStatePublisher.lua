local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local StateContracts = require(Shared:WaitForChild("StateContracts"))

local CabHudStatePublisher = {}

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

local function setAttributeIfChanged(instance, attributeName, value)
	if type(attributeName) ~= "string" or attributeName == "" then
		return
	end

	if instance:GetAttribute(attributeName) ~= value then
		instance:SetAttribute(attributeName, value)
	end
end

local function roundSigned(value)
	local numeric = value or 0
	if numeric >= 0 then
		return math.floor(numeric + 0.5)
	end

	return math.ceil(numeric - 0.5)
end

function CabHudStatePublisher.publish(service, cabPosition, cabSpeed, nearestPickupDistance, waitingCount)
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
	local distance = nearestPickupDistance
	local destination = nil

	local fareSnapshot = nil
	if service.fareService and service.fareService.getActiveSnapshot then
		fareSnapshot = service.fareService:getActiveSnapshot()
	end
	if not fareSnapshot and service.fareService and service.fareService.getLastResult then
		fareSnapshot = service.fareService:getLastResult()
	end

	if service.mode == "boarding" then
		status = "Passenger boarding"
		local passenger = service.activePassenger
		distance = passenger and service.horizontalDistance(cabPosition, passenger.pickupStop.position) or 0
	elseif service.mode == "delivery" then
		status = "Deliver passenger"
		local passenger = service.activePassenger
		if passenger then
			destination = passenger.targetStop.position
			distance = service.horizontalDistance(cabPosition, passenger.targetStop.position)
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

	if service.mode == "pickup" and fareSnapshot then
		if fareSnapshot.status == "completed" then
			status = "Fare completed"
		elseif fareSnapshot.status == "failed" then
			status = "Fare failed"
		end
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

	local fareState = StateContracts.normalizeFareSnapshot({
		status = tostring(fareSnapshot.status or "idle"),
		estimatedPayout = math.max(math.floor((fareSnapshot.estimatedPayout or 0) + 0.5), 0),
		activeValue = math.max(math.floor((fareSnapshot.activeValue or 0) + 0.5), 0),
		payout = math.max(math.floor((fareSnapshot.payout or 0) + 0.5), 0),
		timeComponent = roundSigned(fareSnapshot.timeComponent or 0),
		speedBonus = math.max(math.floor((fareSnapshot.speedBonus or 0) + 0.5), 0),
		damagePenalty = math.max(math.floor((fareSnapshot.damagePenalty or 0) + 0.5), 0),
		damageCollisions = math.max(math.floor((fareSnapshot.damageCollisions or 0) + 0.5), 0),
		damageSeverity = math.max(fareSnapshot.damageSeverity or 0, 0),
		damagePoints = math.max(fareSnapshot.damagePoints or 0, 0),
		durationSeconds = math.max(fareSnapshot.durationSeconds or 0, 0),
		routeDistance = math.max(fareSnapshot.routeDistance or 0, 0),
	})
	local now = Workspace:GetServerTimeNow()
	local forcePublish = service.forceNextCabStatePublish == true
	service.forceNextCabStatePublish = false
	local cabState = StateContracts.normalizeCabHudState({
		cabId = service.cabStateId,
		mode = service.mode,
		status = status,
		distance = math.floor(distance + 0.5),
		destination = destination,
		destinationLabel = "No destination",
		completedFares = service.faresCompleted,
		waitingPassengers = waitingCount,
		serverTime = now,
		fare = fareState,
	})
	local mirrorInterval = math.max(getConfigNumber("gameplayStateBroadcastIntervalSeconds", 0.2), 0.05)
	local shouldMirrorAttributes = forcePublish
		or not service.lastCabAttributeMirrorAt
		or now - service.lastCabAttributeMirrorAt >= mirrorInterval

	if shouldMirrorAttributes then
		service.lastCabAttributeMirrorAt = now
		setAttributeIfChanged(service.car, modeAttr, cabState.mode)
		setAttributeIfChanged(service.car, statusAttr, cabState.status)
		setAttributeIfChanged(service.car, distanceAttr, cabState.distance)
		setAttributeIfChanged(service.car, destinationAttr, cabState.destination)
		setAttributeIfChanged(service.car, completedAttr, cabState.completedFares)
		setAttributeIfChanged(service.car, waitingAttr, cabState.waitingPassengers)
		setAttributeIfChanged(service.car, fareEstimateAttr, cabState.fare.estimatedPayout)
		setAttributeIfChanged(service.car, fareActiveAttr, cabState.fare.activeValue)
		setAttributeIfChanged(service.car, farePayoutAttr, cabState.fare.payout)
		setAttributeIfChanged(service.car, fareTimeComponentAttr, cabState.fare.timeComponent)
		setAttributeIfChanged(service.car, fareSpeedBonusAttr, cabState.fare.speedBonus)
		setAttributeIfChanged(service.car, fareDamagePenaltyAttr, cabState.fare.damagePenalty)
		setAttributeIfChanged(service.car, fareDamageCollisionsAttr, cabState.fare.damageCollisions)
		setAttributeIfChanged(service.car, fareDamageSeverityAttr, cabState.fare.damageSeverity)
		setAttributeIfChanged(service.car, fareDamagePointsAttr, cabState.fare.damagePoints)
		setAttributeIfChanged(service.car, fareResultStatusAttr, cabState.fare.status)
		setAttributeIfChanged(service.car, fareDurationAttr, cabState.fare.durationSeconds)
		setAttributeIfChanged(service.car, fareRouteDistanceAttr, cabState.fare.routeDistance)
	end

	if service.stateReplicator and service.stateReplicator.publishCabState then
		service.stateReplicator:publishCabState(cabState, forcePublish)
	end
end

return CabHudStatePublisher
