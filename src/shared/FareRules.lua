local FareRules = {}

local function getConfigNumber(config, key, fallback)
	local value = config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function roundMoney(value)
	return math.max(0, math.floor(value + 0.5))
end

function FareRules.buildEstimate(config, routeDistance)
	local baseValue = getConfigNumber(config, "fareBaseValue", 10)
	local distancePerUnit = math.max(getConfigNumber(config, "fareDistanceStudsPerUnit", 45), 1)
	local distanceValue = routeDistance / distancePerUnit
	local estimate = baseValue + distanceValue

	return {
		baseFare = roundMoney(baseValue),
		distanceValue = roundMoney(distanceValue),
		estimatedPayout = roundMoney(estimate),
	}
end

function FareRules.finalizeFare(config, routeDistance, elapsedSeconds, damageInput)
	local estimate = FareRules.buildEstimate(config, routeDistance)
	local targetSpeed = math.max(getConfigNumber(config, "fareTimeTargetStudsPerSecond", 32), 1)
	local expectedSeconds = math.max(routeDistance / targetSpeed, 1)
	local paceRatio = expectedSeconds / math.max(elapsedSeconds, 0.1)

	local timeBonusMax = math.max(getConfigNumber(config, "fareTimeBonusMax", 12), 0)
	local timePenaltyMax = math.max(getConfigNumber(config, "fareTimePenaltyMax", 12), 0)
	local timeComponent = 0
	if paceRatio > 1 then
		timeComponent = math.min((paceRatio - 1) * timeBonusMax, timeBonusMax)
	else
		timeComponent = -math.min((1 - paceRatio) * timePenaltyMax, timePenaltyMax)
	end

	local fastThreshold = math.max(getConfigNumber(config, "fareSpeedBonusFastThreshold", 1.15), 1)
	local perfectThreshold = math.max(getConfigNumber(config, "fareSpeedBonusPerfectThreshold", fastThreshold), fastThreshold)
	local speedBonus = 0
	if paceRatio >= perfectThreshold then
		speedBonus = math.max(getConfigNumber(config, "fareSpeedBonusPerfectValue", 12), 0)
	elseif paceRatio >= fastThreshold then
		speedBonus = math.max(getConfigNumber(config, "fareSpeedBonusFastValue", 6), 0)
	end

	local damagePoints = math.max(damageInput or 0, 0)
	local damagePenalty = damagePoints * math.max(getConfigNumber(config, "fareDamagePenaltyPerPoint", 1), 0)

	local rawTotal = estimate.estimatedPayout + timeComponent + speedBonus - damagePenalty
	local minPayout = math.max(getConfigNumber(config, "fareMinimumPayout", 8), 0)
	local maxPayout = math.max(getConfigNumber(config, "fareMaximumPayout", 180), minPayout)
	local finalPayout = math.clamp(rawTotal, minPayout, maxPayout)

	return {
		baseFare = estimate.baseFare,
		distanceValue = estimate.distanceValue,
		estimatedPayout = estimate.estimatedPayout,
		timeComponent = roundMoney(timeComponent),
		speedBonus = roundMoney(speedBonus),
		damagePenalty = roundMoney(damagePenalty),
		finalPayout = roundMoney(finalPayout),
		routeDistance = routeDistance,
		elapsedSeconds = elapsedSeconds,
		expectedSeconds = expectedSeconds,
	}
end

return FareRules
