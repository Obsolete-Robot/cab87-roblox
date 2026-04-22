local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local Remotes = require(shared:WaitForChild("Remotes"))
local StateContracts = require(shared:WaitForChild("StateContracts"))

local GameplayStateStore = {}

local remoteName = Remotes.getServerToClientName("gameplayStateUpdated")
local remote = ReplicatedStorage:WaitForChild(remoteName)
local cabIdAttribute = Config.gameplayStateCabIdAttribute or "Cab87GameplayCabId"
local actions = StateContracts.actions

local state = {
	activeCabId = nil,
	cabStates = {},
	shiftState = nil,
	payoutSummary = nil,
	listeners = {},
}

local function notify(kind, payload)
	for _, listener in ipairs(state.listeners) do
		local ok, err = pcall(listener, kind, payload)
		if not ok then
			warn("[cab87] Gameplay state listener failed: " .. tostring(err))
		end
	end
end

local function applyCabState(snapshot)
	local cabState = StateContracts.normalizeCabHudState(snapshot)
	state.cabStates[cabState.cabId] = cabState
	state.activeCabId = cabState.cabId
	notify("cabState", cabState)
end

local function applyShiftState(snapshot)
	state.shiftState = StateContracts.normalizeShiftHudState(snapshot)
	notify("shiftState", state.shiftState)
end

local function applyPayoutSummary(payload)
	if type(payload) ~= "table" then
		return
	end

	local summary = payload.payoutSummary or payload
	if type(summary) ~= "table" then
		return
	end

	local normalizedInput = table.clone(summary)
	if type(normalizedInput.shiftId) ~= "number" then
		normalizedInput.shiftId = payload.shiftId
	end
	if type(normalizedInput.serverTime) ~= "number" then
		normalizedInput.serverTime = payload.serverTime
	end

	state.payoutSummary = StateContracts.normalizePayoutSummary(normalizedInput)
	notify("payoutSummary", state.payoutSummary)
end

local function applySnapshot(payload)
	if type(payload) ~= "table" then
		return
	end

	if type(payload.cabStates) == "table" then
		for _, cabState in ipairs(payload.cabStates) do
			applyCabState(cabState)
		end
	elseif type(payload.cabState) == "table" then
		applyCabState(payload.cabState)
	end

	if type(payload.shiftState) == "table" then
		applyShiftState(payload.shiftState)
	end

	if type(payload.payoutSummary) == "table" then
		applyPayoutSummary(payload)
	end

	notify("snapshot", payload)
end

local function getCabId(cab)
	if cab then
		local cabId = cab:GetAttribute(cabIdAttribute)
		if type(cabId) == "string" and cabId ~= "" then
			return cabId
		end
	end

	return state.activeCabId
end

function GameplayStateStore.getCabState(cab)
	local cabId = getCabId(cab)
	if cabId and state.cabStates[cabId] then
		return state.cabStates[cabId]
	end

	if state.activeCabId then
		return state.cabStates[state.activeCabId]
	end

	return nil
end

function GameplayStateStore.getShiftState()
	return state.shiftState
end

function GameplayStateStore.getPayoutSummary()
	return state.payoutSummary
end

function GameplayStateStore.onChanged(listener)
	if type(listener) ~= "function" then
		return function() end
	end

	table.insert(state.listeners, listener)
	local disconnected = false

	return function()
		if disconnected then
			return
		end
		disconnected = true

		for index = #state.listeners, 1, -1 do
			if state.listeners[index] == listener then
				table.remove(state.listeners, index)
				break
			end
		end
	end
end

if remote:IsA("RemoteEvent") then
	remote.OnClientEvent:Connect(function(action, payload)
		if action == actions.snapshot then
			applySnapshot(payload)
		elseif action == actions.cabState then
			applyCabState(payload)
		elseif action == actions.shiftState then
			applyShiftState(payload)
		elseif action == actions.payoutSummary then
			applyPayoutSummary(payload)
		end
	end)
else
	warn("[cab87] Gameplay state remote is not a RemoteEvent: " .. remote:GetFullName())
end

return GameplayStateStore
