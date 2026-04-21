local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FareRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FareRules"))

local FareService = {}
FareService.__index = FareService

function FareService.new(options)
	options = options or {}
	return setmetatable({
		config = options.config or {},
		car = options.car,
		shiftService = options.shiftService,
		activeFare = nil,
		lastResult = {
			status = "idle",
			estimatedPayout = 0,
			activeValue = 0,
			payout = 0,
			timeComponent = 0,
			speedBonus = 0,
			damagePenalty = 0,
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

function FareService:_getCurrentDamagePoints()
	return math.max(self:_getNumberAttribute(self.config.carDamagePenaltyAttribute, 0), 0)
end

function FareService:_resetDamageForFare()
	if self.car and type(self.config.carDamagePenaltyAttribute) == "string" and self.config.carDamagePenaltyAttribute ~= "" then
		self.car:SetAttribute(self.config.carDamagePenaltyAttribute, 0)
	end
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
	local startDamage = self:_getCurrentDamagePoints()
	self.activeFare = {
		routeDistance = routeDistance,
		startedAt = Workspace:GetServerTimeNow(),
		estimatedPayout = estimate.estimatedPayout,
		startDamage = startDamage,
	}
	self:_resetDamageForFare()
	self:_setLastResult({
		status = "active",
		estimatedPayout = estimate.estimatedPayout,
		activeValue = estimate.estimatedPayout,
		payout = 0,
		timeComponent = 0,
		speedBonus = 0,
		damagePenalty = 0,
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
		activeValue = self.activeFare.estimatedPayout,
		payout = 0,
		timeComponent = 0,
		speedBonus = 0,
		damagePenalty = 0,
		durationSeconds = math.max(Workspace:GetServerTimeNow() - self.activeFare.startedAt, 0),
		routeDistance = self.activeFare.routeDistance,
	}
end

function FareService:completeFare()
	if not self.activeFare then
		return self.lastResult
	end

	local elapsed = math.max(Workspace:GetServerTimeNow() - self.activeFare.startedAt, 0)
	local currentDamage = self:_getCurrentDamagePoints()
	local damageInput = math.max(currentDamage - (self.activeFare.startDamage or 0), 0)
	local result = FareRules.finalizeFare(self.config, self.activeFare.routeDistance, elapsed, damageInput)
	local payout = result.finalPayout
	local player = self:_getDriverPlayer()

	if self.shiftService and player and self.shiftService.addShiftMoney then
		self.shiftService:addShiftMoney(player, payout)
	end

	self.activeFare = nil
	self:_resetDamageForFare()
	self:_setLastResult({
		status = "completed",
		estimatedPayout = result.estimatedPayout,
		activeValue = result.estimatedPayout,
		payout = payout,
		timeComponent = result.timeComponent,
		speedBonus = result.speedBonus,
		damagePenalty = result.damagePenalty,
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
	self:_resetDamageForFare()
	self:_setLastResult({
		status = "failed",
		estimatedPayout = 0,
		activeValue = 0,
		payout = 0,
		timeComponent = 0,
		speedBonus = 0,
		damagePenalty = 0,
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
