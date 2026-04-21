local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local StateContracts = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StateContracts"))

local GameplayStateReplicator = {}
GameplayStateReplicator.__index = GameplayStateReplicator

local ACTIONS = StateContracts.actions

local function getConfigNumber(config, key, fallback)
	local value = config and config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function vectorSignature(vector)
	if typeof(vector) ~= "Vector3" then
		return ""
	end

	return string.format("%.1f,%.1f,%.1f", vector.X, vector.Y, vector.Z)
end

local function numberSignature(value)
	return tostring(math.floor((value or 0) * 10 + 0.5) / 10)
end

local function fareSignature(fare)
	return table.concat({
		fare.status,
		numberSignature(fare.estimatedPayout),
		numberSignature(fare.activeValue),
		numberSignature(fare.payout),
		numberSignature(fare.timeComponent),
		numberSignature(fare.speedBonus),
		numberSignature(fare.damagePenalty),
		numberSignature(fare.damageCollisions),
		numberSignature(fare.damageSeverity),
		numberSignature(fare.damagePoints),
		numberSignature(fare.durationSeconds),
		numberSignature(fare.routeDistance),
	}, "|")
end

local function cabSignature(snapshot)
	return table.concat({
		snapshot.cabId,
		snapshot.mode,
		snapshot.status,
		numberSignature(snapshot.distance),
		vectorSignature(snapshot.destination),
		snapshot.destinationLabel,
		numberSignature(snapshot.completedFares),
		numberSignature(snapshot.waitingPassengers),
		fareSignature(snapshot.fare),
	}, "|")
end

function GameplayStateReplicator.new(options)
	options = options or {}
	local self = setmetatable({
		config = options.config or {},
		players = options.players or Players,
		remote = options.remotes and options.remotes.gameplayStateUpdated or options.remote,
		cabChannels = {},
		shiftStatesByPlayer = {},
		connections = {},
	}, GameplayStateReplicator)

	if self.players and self.players.PlayerAdded then
		table.insert(self.connections, self.players.PlayerAdded:Connect(function(player)
			task.defer(function()
				self:publishSnapshot(player)
			end)
		end))

		table.insert(self.connections, self.players.PlayerRemoving:Connect(function(player)
			self.shiftStatesByPlayer[player] = nil
		end))
	end

	return self
end

function GameplayStateReplicator:_getCabInterval()
	return math.max(getConfigNumber(self.config, "gameplayStateBroadcastIntervalSeconds", 0.2), 0.05)
end

function GameplayStateReplicator:_fire(targetPlayer, action, payload)
	if not self.remote then
		return
	end

	if targetPlayer then
		self.remote:FireClient(targetPlayer, action, payload)
	else
		self.remote:FireAllClients(action, payload)
	end
end

function GameplayStateReplicator:publishCabState(snapshot, force)
	local normalized = StateContracts.normalizeCabHudState(snapshot)
	local cabId = normalized.cabId
	local channel = self.cabChannels[cabId]
	if not channel then
		channel = {
			lastPublishedAt = 0,
			lastSignature = nil,
			latest = nil,
		}
		self.cabChannels[cabId] = channel
	end

	channel.latest = normalized
	local signature = cabSignature(normalized)
	local now = Workspace:GetServerTimeNow()
	if force or (signature ~= channel.lastSignature and now - channel.lastPublishedAt >= self:_getCabInterval()) then
		channel.lastPublishedAt = now
		channel.lastSignature = signature
		self:_fire(nil, ACTIONS.cabState, normalized)
	end
end

function GameplayStateReplicator:publishShiftState(snapshot, targetPlayer)
	local normalized = StateContracts.normalizeShiftHudState(snapshot)
	if targetPlayer then
		self.shiftStatesByPlayer[targetPlayer] = normalized
	end

	self:_fire(targetPlayer, ACTIONS.shiftState, normalized)
end

function GameplayStateReplicator:publishPayoutSummary(player, summary)
	if not player then
		return
	end

	local normalized = StateContracts.normalizePayoutSummary(summary)
	self:_fire(player, ACTIONS.payoutSummary, {
		shiftId = normalized.shiftId,
		serverTime = normalized.serverTime,
		payoutSummary = normalized,
	})
end

function GameplayStateReplicator:publishSnapshot(player)
	if not player then
		return
	end

	local cabStates = {}
	for _, channel in pairs(self.cabChannels) do
		if channel.latest then
			table.insert(cabStates, channel.latest)
		end
	end

	self:_fire(player, ACTIONS.snapshot, {
		cabStates = cabStates,
		shiftState = self.shiftStatesByPlayer[player],
	})
end

function GameplayStateReplicator:destroy()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.cabChannels)
	table.clear(self.shiftStatesByPlayer)
end

return GameplayStateReplicator
