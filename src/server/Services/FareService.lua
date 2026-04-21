local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FareRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FareRules"))

local FareService = {}
FareService.__index = FareService

local function roundNumber(value)
	return math.floor((value or 0) + 0.5)
end

function FareService.new(options)
	options = options or {}
	return setmetatable({
		config = options.config or {},
		car = options.car,
		shiftService = options.shiftService,
		activeFare = nil,
		lastDamageEvent = nil,
		lastResult = {
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
		},
	}, FareService)
end

function FareService:_getDriverPlayer()
	if not self.car then
		return nil
	end

	local seat = self.car:FindFirstChild("DriverSeat")
	local humanoid = seat and seat:IsA("VehicleSeat") and seat.Occupant or nil
	return humanoid and Players:GetPlayerFromCharacter(humanoid.Parent) or nil
end

function FareService:_getConfigNumber(name, fallback)
	local value = self.config and self.config[name]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

function FareService:_emptyDamageSnapshot()
	return {
		collisions = 0,
		severity = 0,
		points = 0,
	}
end

function FareService:_writeDamageAttributes(snapshot)
	if not self.car then
		return
	end

	local countAttr = self.config.carDamageCollisionCountAttribute
	local severityAttr = self.config.carDamageSeverityAttribute
	local pointsAttr = self.config.carDamagePenaltyAttribute
	if type(countAttr) == "string" and countAttr ~= "" then
		self.car:SetAttribute(countAttr, snapshot.collisions)
	end
	if type(severityAttr) == "string" and severityAttr ~= "" then
		self.car:SetAttribute(severityAttr, snapshot.severity)
	end
	if type(pointsAttr) == "string" and pointsAttr ~= "" then
		self.car:SetAttribute(pointsAttr, snapshot.points)
	end
end

function FareService:_setDamageSnapshot(snapshot)
	if self.activeFare then
		self.activeFare.damage = {
			collisions = snapshot.collisions,
			severity = snapshot.severity,
			points = snapshot.points,
		}
	end

	self:_writeDamageAttributes(snapshot)
end

function FareService:getActiveDamageSnapshot()
	if self.activeFare and self.activeFare.damage then
		return {
			collisions = self.activeFare.damage.collisions,
			severity = self.activeFare.damage.severity,
			points = self.activeFare.damage.points,
		}
	end

	return self:_emptyDamageSnapshot()
end

function FareService:recordDamage(eventKind, severity)
	if not self.activeFare then
		return nil
	end

	local safeSeverity = math.max(severity or 0, 0)
	if safeSeverity <= 0 then
		return self:getActiveDamageSnapshot()
	end

	local now = Workspace:GetServerTimeNow()
	local forgivenessWindow = math.max(self:_getConfigNumber("carDamageForgivenessWindowSeconds", 0), 0)
	if self.activeFare.lastDamageAt and now - self.activeFare.lastDamageAt < forgivenessWindow then
		return self:getActiveDamageSnapshot()
	end

	local severityScale = math.max(self:_getConfigNumber("carDamageSeverityToPointsScale", 1), 0)
	local nextSnapshot = self:getActiveDamageSnapshot()
	nextSnapshot.collisions += 1
	nextSnapshot.severity += safeSeverity
	nextSnapshot.points += safeSeverity * severityScale

	self.activeFare.lastDamageAt = now
	self.lastDamageEvent = {
		time = now,
		kind = eventKind,
		severity = safeSeverity,
		collisions = nextSnapshot.collisions,
		points = nextSnapshot.points,
	}

	self:_setDamageSnapshot(nextSnapshot)
	return nextSnapshot
end

function FareService:_getNumberAttribute(name, fallback)
	if not self.car or type(name) ~= "string" or name == "" then
		return fallback
	end

	local value = self.car:GetAttribute(name)
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

function FareService:_setLastResult(result)
	self.lastResult = result
end

function FareService:beginFare(routeDistance)
	local estimate = FareRules.buildEstimate(self.config, routeDistance)
	self.activeFare = {
		routeDistance = routeDistance,
		startedAt = Workspace:GetServerTimeNow(),
		estimatedPayout = estimate.estimatedPayout,
		damage = self:_emptyDamageSnapshot(),
		lastDamageAt = nil,
	}
	self.lastDamageEvent = nil
	self:_writeDamageAttributes(self.activeFare.damage)
	self:_setLastResult({
		status = "active",
		estimatedPayout = estimate.estimatedPayout,
		activeValue = estimate.estimatedPayout,
		payout = 0,
		timeComponent = 0,
		speedBonus = 0,
		damagePenalty = 0,
		damageCollisions = 0,
		damageSeverity = 0,
		damagePoints = 0,
		durationSeconds = 0,
		routeDistance = routeDistance,
	})

	return self.lastResult
end

function FareService:getActiveSnapshot()
	if not self.activeFare then
		return nil
	end

	return {
		status = "active",
		estimatedPayout = self.activeFare.estimatedPayout,
		activeValue = math.max(self.activeFare.estimatedPayout - roundNumber(self.activeFare.damage.points), 0),
		payout = 0,
		timeComponent = 0,
		speedBonus = 0,
		damagePenalty = roundNumber(self.activeFare.damage.points),
		damageCollisions = roundNumber(self.activeFare.damage.collisions),
		damageSeverity = self.activeFare.damage.severity,
		damagePoints = self.activeFare.damage.points,
		durationSeconds = math.max(Workspace:GetServerTimeNow() - self.activeFare.startedAt, 0),
		routeDistance = self.activeFare.routeDistance,
	}
end

function FareService:completeFare()
	if not self.activeFare then
		return self.lastResult
	end

	local elapsed = math.max(Workspace:GetServerTimeNow() - self.activeFare.startedAt, 0)
	local damageInput = self.activeFare.damage and self.activeFare.damage.points or 0
	local result = FareRules.finalizeFare(self.config, self.activeFare.routeDistance, elapsed, damageInput)
	local payout = result.finalPayout
	local player = self:_getDriverPlayer()

	if self.shiftService and player and self.shiftService.addShiftMoney then
		self.shiftService:addShiftMoney(player, payout)
	end

	local completedDamage = self.activeFare.damage or self:_emptyDamageSnapshot()
	self.activeFare = nil
	self:_writeDamageAttributes(self:_emptyDamageSnapshot())
	self:_setLastResult({
		status = "completed",
		estimatedPayout = result.estimatedPayout,
		activeValue = result.estimatedPayout,
		payout = payout,
		timeComponent = result.timeComponent,
		speedBonus = result.speedBonus,
		damagePenalty = result.damagePenalty,
		damageCollisions = roundNumber(completedDamage.collisions),
		damageSeverity = completedDamage.severity,
		damagePoints = completedDamage.points,
		durationSeconds = result.elapsedSeconds,
		routeDistance = result.routeDistance,
	})

	return self.lastResult
end

function FareService:failFare()
	if not self.activeFare then
		return self.lastResult
	end

	local elapsed = math.max(Workspace:GetServerTimeNow() - self.activeFare.startedAt, 0)
	local routeDistance = self.activeFare.routeDistance
	self.activeFare = nil
	self.lastDamageEvent = nil
	self:_writeDamageAttributes(self:_emptyDamageSnapshot())
	self:_setLastResult({
		status = "failed",
		estimatedPayout = 0,
		activeValue = 0,
		payout = 0,
		timeComponent = 0,
		speedBonus = 0,
		damagePenalty = 0,
		damageCollisions = 0,
		damageSeverity = 0,
		damagePoints = 0,
		durationSeconds = elapsed,
		routeDistance = routeDistance,
	})

	return self.lastResult
end

function FareService:getLastResult()
	return self.lastResult
end

function FareService:hasActiveFare()
	return self.activeFare ~= nil
end

function FareService:onShiftPhaseChanged(phase)
	if phase ~= "Active" and self.activeFare then
		return self:failFare()
	end

	return self.lastResult
end

return FareService
