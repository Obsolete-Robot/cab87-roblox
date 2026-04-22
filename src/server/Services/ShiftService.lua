local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ShiftService = {}
ShiftService.__index = ShiftService

local PHASE_PREPARING = "Preparing"
local PHASE_ACTIVE = "Active"
local PHASE_ENDING = "Ending"
local PHASE_INTERMISSION = "Intermission"
local SHIFT_STATE_ACTION = "State"
local SHIFT_SNAPSHOT_ACTION = "Snapshot"
local SHIFT_PAYOUT_ACTION = "PayoutSummary"

local function loadRemoteActions()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local remotesModule = shared and shared:FindFirstChild("Remotes")
	if not remotesModule then
		return
	end

	local ok, Remotes = pcall(require, remotesModule)
	if not ok then
		warn("[cab87] Remotes module failed to load; using default shift remote actions: " .. tostring(Remotes))
		return
	end

	if type(Remotes.actions) == "table" then
		if type(Remotes.actions.shiftStateUpdated) == "string" then
			SHIFT_STATE_ACTION = Remotes.actions.shiftStateUpdated
		end
		if type(Remotes.actions.shiftStateSnapshot) == "string" then
			SHIFT_SNAPSHOT_ACTION = Remotes.actions.shiftStateSnapshot
		end
		if type(Remotes.actions.shiftPayoutSummary) == "string" then
			SHIFT_PAYOUT_ACTION = Remotes.actions.shiftPayoutSummary
		end
	end
end

loadRemoteActions()

local function getConfigNumber(config, key, fallback)
	local value = config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function getNonNegativeConfigNumber(config, key, fallback)
	return math.max(getConfigNumber(config, key, fallback), 0)
end

local function setAttributeIfNamed(instance, attributeName, value)
	if type(attributeName) == "string" and attributeName ~= "" then
		instance:SetAttribute(attributeName, value)
	end
end

local function isDebugLoggingEnabled(config)
	return config.shiftDebugLogging == true
end

function ShiftService.new(options)
	options = options or {}

	return setmetatable({
		config = options.config or {},
		players = options.players or Players,
		remote = options.remotes and options.remotes.shiftStateUpdated or nil,
		stateReplicator = options.stateReplicator,
		connections = {},
		playerStates = {},
		running = false,
		phase = PHASE_PREPARING,
		shiftId = 0,
		phaseElapsed = 0,
		phaseDuration = 0,
		timeRemaining = 0,
		broadcastElapsed = 0,
		lastBroadcastSecond = nil,
		phaseChangedListeners = {},
		economyService = options.economyService,
	}, ShiftService)
end

function ShiftService:onPhaseChanged(listener)
	if type(listener) ~= "function" then
		return function() end
	end

	table.insert(self.phaseChangedListeners, listener)
	local removed = false
	return function()
		if removed then
			return
		end
		removed = true
		for index = #self.phaseChangedListeners, 1, -1 do
			if self.phaseChangedListeners[index] == listener then
				table.remove(self.phaseChangedListeners, index)
				break
			end
		end
	end
end

function ShiftService:_emitPhaseChanged(snapshot)
	for _, listener in ipairs(self.phaseChangedListeners) do
		local ok, err = pcall(listener, snapshot)
		if not ok then
			warn("[cab87] Shift phase listener failed: " .. tostring(err))
		end
	end
end

function ShiftService:_getBroadcastInterval()
	return math.max(getConfigNumber(self.config, "shiftBroadcastIntervalSeconds", 0.5), 0.1)
end

function ShiftService:_getInitialPreparationDuration()
	return getNonNegativeConfigNumber(self.config, "shiftInitialPreparationSeconds", 5)
end

function ShiftService:_getShiftDuration()
	return math.max(getConfigNumber(self.config, "shiftDurationSeconds", 180), 1)
end

function ShiftService:_getEndingDuration()
	return getNonNegativeConfigNumber(self.config, "shiftEndingSeconds", 4)
end

function ShiftService:_getIntermissionDuration()
	return math.max(getConfigNumber(self.config, "shiftIntermissionSeconds", 20), 1)
end

function ShiftService:_ensurePlayerState(player)
	local state = self.playerStates[player]
	if not state then
		state = {
			grossMoney = 0,
			fareTotals = 0,
			bonuses = 0,
			timePenalties = 0,
			damagePenalties = 0,
		}
		self.playerStates[player] = state
	end

	setAttributeIfNamed(player, self.config.shiftGrossMoneyAttribute, state.grossMoney)
	return state
end

function ShiftService:_removePlayerState(player)
	self.playerStates[player] = nil
end

function ShiftService:_resetShiftTotals()
	for _, player in ipairs(self.players:GetPlayers()) do
		local state = self:_ensurePlayerState(player)
		state.grossMoney = 0
		state.fareTotals = 0
		state.bonuses = 0
		state.timePenalties = 0
		state.damagePenalties = 0
		setAttributeIfNamed(player, self.config.shiftGrossMoneyAttribute, state.grossMoney)
	end
end

function ShiftService:_publishPayoutSummary(player, summary)
	if self.stateReplicator and self.stateReplicator.publishPayoutSummary then
		local stateSummary = table.clone(summary)
		stateSummary.shiftId = self.shiftId
		stateSummary.serverTime = Workspace:GetServerTimeNow()
		self.stateReplicator:publishPayoutSummary(player, stateSummary)
	end

	if not self.remote then
		return
	end

	self.remote:FireClient(player, SHIFT_PAYOUT_ACTION, {
		shiftId = self.shiftId,
		serverTime = Workspace:GetServerTimeNow(),
		payoutSummary = summary,
	})
end

function ShiftService:_finalizeShiftPayouts()
	for _, player in ipairs(self.players:GetPlayers()) do
		local state = self:_ensurePlayerState(player)
		local summary = nil

		if self.economyService and self.economyService.createShiftPayoutSummary then
			summary = self.economyService:createShiftPayoutSummary(player, state.grossMoney, {
				fareTotals = state.fareTotals,
				bonuses = state.bonuses,
				timePenalties = state.timePenalties,
				damagePenalties = state.damagePenalties,
			})
		end

		if not summary then
			local grossEarnings = math.max(math.floor((state.grossMoney or 0) + 0.5), 0)
			summary = {
				eventId = 0,
				grossEarnings = grossEarnings,
				fareTotals = math.max(math.floor((state.fareTotals or 0) + 0.5), 0),
				bonuses = math.max(math.floor((state.bonuses or 0) + 0.5), 0),
				timePenalties = math.max(math.floor((state.timePenalties or 0) + 0.5), 0),
				damagePenalties = math.max(math.floor((state.damagePenalties or 0) + 0.5), 0),
				medallionFeeRate = 0,
				medallionFeeAmount = 0,
				netDeposit = grossEarnings,
				bankBalance = grossEarnings,
			}
		end

		self:_publishPayoutSummary(player, summary)
	end
end

function ShiftService:_getSnapshot(player)
	local playerState = player and self:_ensurePlayerState(player) or nil

	return {
		phase = self.phase,
		shiftId = self.shiftId,
		timeRemaining = math.max(self.timeRemaining, 0),
		duration = self.phaseDuration,
		phaseElapsed = self.phaseElapsed,
		serverTime = Workspace:GetServerTimeNow(),
		grossMoney = playerState and playerState.grossMoney or 0,
		bankMoney = (player and self.economyService and self.economyService.getBankMoney)
				and self.economyService:getBankMoney(player)
			or 0,
	}
end

function ShiftService:_setReplicatedAttributes(snapshot)
	setAttributeIfNamed(ReplicatedStorage, self.config.shiftPhaseAttribute, snapshot.phase)
	setAttributeIfNamed(ReplicatedStorage, self.config.shiftIdAttribute, snapshot.shiftId)
	setAttributeIfNamed(ReplicatedStorage, self.config.shiftTimeRemainingAttribute, snapshot.timeRemaining)
	setAttributeIfNamed(ReplicatedStorage, self.config.shiftDurationAttribute, snapshot.duration)
end

function ShiftService:_publish(action, targetPlayer)
	local snapshot = self:_getSnapshot()
	self:_setReplicatedAttributes(snapshot)

	if self.stateReplicator and self.stateReplicator.publishShiftState then
		if targetPlayer then
			self.stateReplicator:publishShiftState(self:_getSnapshot(targetPlayer), targetPlayer)
		else
			for _, player in ipairs(self.players:GetPlayers()) do
				self.stateReplicator:publishShiftState(self:_getSnapshot(player), player)
			end
		end
	end

	if not self.remote then
		return
	end

	if targetPlayer then
		self.remote:FireClient(targetPlayer, action, snapshot)
	else
		self.remote:FireAllClients(action, snapshot)
	end
end

function ShiftService:_publishState(targetPlayer)
	self:_publish(SHIFT_STATE_ACTION, targetPlayer)
end

function ShiftService:_publishSnapshot(targetPlayer)
	self:_publish(SHIFT_SNAPSHOT_ACTION, targetPlayer)
end

function ShiftService:_beginPhase(phase, duration)
	if phase == PHASE_ACTIVE then
		self.shiftId += 1
		self:_resetShiftTotals()
	end

	self.phase = phase
	self.phaseElapsed = 0
	self.phaseDuration = duration
	self.timeRemaining = duration
	self.broadcastElapsed = 0
	self.lastBroadcastSecond = math.ceil(duration)

	if isDebugLoggingEnabled(self.config) then
		print(string.format(
			"[cab87 shift] serverTime=%.3f phase=%s shiftId=%d duration=%.1f",
			Workspace:GetServerTimeNow(),
			self.phase,
			self.shiftId,
			self.phaseDuration
		))
	end

	self:_publishState()
	self:_emitPhaseChanged(self:_getSnapshot())
end

function ShiftService:_advancePhase()
	if self.phase == PHASE_PREPARING then
		self:_beginPhase(PHASE_ACTIVE, self:_getShiftDuration())
	elseif self.phase == PHASE_ACTIVE then
		self:_finalizeShiftPayouts()
		local endingDuration = self:_getEndingDuration()
		if endingDuration > 0 then
			self:_beginPhase(PHASE_ENDING, endingDuration)
		else
			self:_beginPhase(PHASE_INTERMISSION, self:_getIntermissionDuration())
		end
	elseif self.phase == PHASE_ENDING then
		self:_beginPhase(PHASE_INTERMISSION, self:_getIntermissionDuration())
	else
		self:_beginPhase(PHASE_ACTIVE, self:_getShiftDuration())
	end
end

function ShiftService:_step(dt)
	self.phaseElapsed += dt
	self.timeRemaining = math.max(self.phaseDuration - self.phaseElapsed, 0)

	if self.phaseElapsed >= self.phaseDuration then
		self:_advancePhase()
		return
	end

	self.broadcastElapsed += dt
	local nextBroadcastSecond = math.ceil(self.timeRemaining)
	if self.broadcastElapsed >= self:_getBroadcastInterval() or nextBroadcastSecond ~= self.lastBroadcastSecond then
		self.broadcastElapsed = 0
		self.lastBroadcastSecond = nextBroadcastSecond
		self:_publishState()
	end
end

function ShiftService:addShiftMoney(player, amount, breakdown)
	if self.phase ~= PHASE_ACTIVE then
		return 0
	end

	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge then
		local state = self:_ensurePlayerState(player)
		return state.grossMoney
	end

	if amount == 0 then
		local state = self:_ensurePlayerState(player)
		return state.grossMoney
	end

	local state = self:_ensurePlayerState(player)
	state.grossMoney = math.max(state.grossMoney + amount, 0)
	if type(breakdown) == "table" then
		if type(breakdown.fareTotals) == "number" then
			state.fareTotals = math.max((state.fareTotals or 0) + breakdown.fareTotals, 0)
		end
		if type(breakdown.bonuses) == "number" then
			state.bonuses = math.max((state.bonuses or 0) + breakdown.bonuses, 0)
		end
		if type(breakdown.timePenalties) == "number" then
			state.timePenalties = math.max((state.timePenalties or 0) + breakdown.timePenalties, 0)
		end
		if type(breakdown.damagePenalties) == "number" then
			state.damagePenalties = math.max((state.damagePenalties or 0) + breakdown.damagePenalties, 0)
		end
	end
	setAttributeIfNamed(player, self.config.shiftGrossMoneyAttribute, state.grossMoney)
	self:_publishState()

	return state.grossMoney
end

function ShiftService:getPlayerShiftGross(player)
	local state = self:_ensurePlayerState(player)
	return state.grossMoney
end

function ShiftService:start()
	if self.running then
		return
	end

	self.running = true

	for _, player in ipairs(self.players:GetPlayers()) do
		self:_ensurePlayerState(player)
	end

	table.insert(self.connections, self.players.PlayerAdded:Connect(function(player)
		self:_ensurePlayerState(player)
		self:_publishSnapshot(player)
	end))

	table.insert(self.connections, self.players.PlayerRemoving:Connect(function(player)
		self:_removePlayerState(player)
	end))

	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end))

	self:_beginPhase(PHASE_PREPARING, self:_getInitialPreparationDuration())
end

function ShiftService:stop()
	if not self.running then
		return
	end

	self.running = false

	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.playerStates)
end

return ShiftService
