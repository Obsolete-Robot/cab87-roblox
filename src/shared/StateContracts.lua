local StateContracts = {}

StateContracts.remoteName = "Cab87GameplayStateUpdated"
StateContracts.defaultCabId = "PlayerCab"

StateContracts.actions = {
	snapshot = "Snapshot",
	cabState = "CabState",
	shiftState = "ShiftState",
	payoutSummary = "PayoutSummary",
}

-- Attributes remain as Studio/debug mirrors only. HUD code should read these
-- contracts through the client state store instead of polling attributes.
StateContracts.attributeMirrors = {
	cab = "Cab fare/passenger attributes mirror the latest CabHudState for Studio inspection and legacy helpers.",
	player = "Player shift/payout attributes mirror local client state for Studio inspection and legacy helpers.",
	replicatedStorage = "Global shift attributes mirror the latest ShiftHudState for Studio inspection.",
}

export type FareSnapshot = {
	status: string,
	estimatedPayout: number,
	activeValue: number,
	payout: number,
	timeComponent: number,
	speedBonus: number,
	damagePenalty: number,
	damageCollisions: number,
	damageSeverity: number,
	damagePoints: number,
	durationSeconds: number,
	routeDistance: number,
}

export type CabHudState = {
	cabId: string,
	mode: string,
	status: string,
	distance: number,
	destination: Vector3?,
	destinationLabel: string,
	completedFares: number,
	waitingPassengers: number,
	serverTime: number,
	fare: FareSnapshot,
}

export type ShiftHudState = {
	phase: string,
	shiftId: number,
	timeRemaining: number,
	duration: number,
	phaseElapsed: number,
	serverTime: number,
	grossMoney: number,
}

export type PayoutSummary = {
	eventId: number,
	shiftId: number,
	serverTime: number,
	grossEarnings: number,
	fareTotals: number,
	bonuses: number,
	damagePenalties: number,
	medallionFeeRate: number,
	medallionFeeAmount: number,
	netDeposit: number,
}

local DEFAULT_FARE = {
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

local DEFAULT_SHIFT = {
	phase = "Preparing",
	shiftId = 0,
	timeRemaining = 0,
	duration = 0,
	phaseElapsed = 0,
	serverTime = 0,
	grossMoney = 0,
}

local DEFAULT_PAYOUT = {
	eventId = 0,
	shiftId = 0,
	serverTime = 0,
	grossEarnings = 0,
	fareTotals = 0,
	bonuses = 0,
	damagePenalties = 0,
	medallionFeeRate = 0,
	medallionFeeAmount = 0,
	netDeposit = 0,
}

local function finiteNumber(value, fallback)
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function nonNegativeNumber(value, fallback)
	return math.max(finiteNumber(value, fallback), 0)
end

local function integerNumber(value, fallback)
	return math.floor(finiteNumber(value, fallback) + 0.5)
end

local function stringValue(value, fallback)
	if type(value) == "string" and value ~= "" then
		return value
	end

	return fallback
end

local function vector3Value(value)
	if typeof(value) == "Vector3" then
		return value
	end

	return nil
end

function StateContracts.normalizeFareSnapshot(snapshot)
	snapshot = if type(snapshot) == "table" then snapshot else DEFAULT_FARE

	return {
		status = stringValue(snapshot.status, DEFAULT_FARE.status),
		estimatedPayout = nonNegativeNumber(snapshot.estimatedPayout, DEFAULT_FARE.estimatedPayout),
		activeValue = nonNegativeNumber(snapshot.activeValue, DEFAULT_FARE.activeValue),
		payout = nonNegativeNumber(snapshot.payout, DEFAULT_FARE.payout),
		timeComponent = integerNumber(snapshot.timeComponent, DEFAULT_FARE.timeComponent),
		speedBonus = nonNegativeNumber(snapshot.speedBonus, DEFAULT_FARE.speedBonus),
		damagePenalty = nonNegativeNumber(snapshot.damagePenalty, DEFAULT_FARE.damagePenalty),
		damageCollisions = nonNegativeNumber(snapshot.damageCollisions, DEFAULT_FARE.damageCollisions),
		damageSeverity = nonNegativeNumber(snapshot.damageSeverity, DEFAULT_FARE.damageSeverity),
		damagePoints = nonNegativeNumber(snapshot.damagePoints, DEFAULT_FARE.damagePoints),
		durationSeconds = nonNegativeNumber(snapshot.durationSeconds, DEFAULT_FARE.durationSeconds),
		routeDistance = nonNegativeNumber(snapshot.routeDistance, DEFAULT_FARE.routeDistance),
	}
end

function StateContracts.normalizeCabHudState(snapshot)
	snapshot = if type(snapshot) == "table" then snapshot else {}

	return {
		cabId = stringValue(snapshot.cabId, StateContracts.defaultCabId),
		mode = stringValue(snapshot.mode, "pickup"),
		status = stringValue(snapshot.status, "Find a pickup"),
		distance = nonNegativeNumber(snapshot.distance, 0),
		destination = vector3Value(snapshot.destination),
		destinationLabel = stringValue(snapshot.destinationLabel, "No destination"),
		completedFares = nonNegativeNumber(snapshot.completedFares, 0),
		waitingPassengers = nonNegativeNumber(snapshot.waitingPassengers, 0),
		serverTime = nonNegativeNumber(snapshot.serverTime, 0),
		fare = StateContracts.normalizeFareSnapshot(snapshot.fare),
	}
end

function StateContracts.normalizeShiftHudState(snapshot)
	snapshot = if type(snapshot) == "table" then snapshot else DEFAULT_SHIFT

	return {
		phase = stringValue(snapshot.phase, DEFAULT_SHIFT.phase),
		shiftId = nonNegativeNumber(snapshot.shiftId, DEFAULT_SHIFT.shiftId),
		timeRemaining = nonNegativeNumber(snapshot.timeRemaining, DEFAULT_SHIFT.timeRemaining),
		duration = nonNegativeNumber(snapshot.duration, DEFAULT_SHIFT.duration),
		phaseElapsed = nonNegativeNumber(snapshot.phaseElapsed, DEFAULT_SHIFT.phaseElapsed),
		serverTime = nonNegativeNumber(snapshot.serverTime, DEFAULT_SHIFT.serverTime),
		grossMoney = nonNegativeNumber(snapshot.grossMoney, DEFAULT_SHIFT.grossMoney),
	}
end

function StateContracts.normalizePayoutSummary(summary)
	summary = if type(summary) == "table" then summary else DEFAULT_PAYOUT

	return {
		eventId = nonNegativeNumber(summary.eventId, DEFAULT_PAYOUT.eventId),
		shiftId = nonNegativeNumber(summary.shiftId, DEFAULT_PAYOUT.shiftId),
		serverTime = nonNegativeNumber(summary.serverTime, DEFAULT_PAYOUT.serverTime),
		grossEarnings = nonNegativeNumber(summary.grossEarnings, DEFAULT_PAYOUT.grossEarnings),
		fareTotals = nonNegativeNumber(summary.fareTotals, DEFAULT_PAYOUT.fareTotals),
		bonuses = nonNegativeNumber(summary.bonuses, DEFAULT_PAYOUT.bonuses),
		damagePenalties = nonNegativeNumber(summary.damagePenalties, DEFAULT_PAYOUT.damagePenalties),
		medallionFeeRate = nonNegativeNumber(summary.medallionFeeRate, DEFAULT_PAYOUT.medallionFeeRate),
		medallionFeeAmount = nonNegativeNumber(summary.medallionFeeAmount, DEFAULT_PAYOUT.medallionFeeAmount),
		netDeposit = nonNegativeNumber(summary.netDeposit, DEFAULT_PAYOUT.netDeposit),
	}
end

return StateContracts
