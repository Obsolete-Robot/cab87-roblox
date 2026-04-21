local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_SHIFT_STATE_REMOTE_NAME = "Cab87ShiftStateUpdated"
local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local function getRemoteName()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	local remotesModule = shared and shared:FindFirstChild("Remotes")
	if not remotesModule then
		return DEFAULT_SHIFT_STATE_REMOTE_NAME
	end

	local ok, Remotes = pcall(require, remotesModule)
	if not ok then
		warn("[cab87] Remotes module failed to load on client; using default shift remote name: " .. tostring(Remotes))
		return DEFAULT_SHIFT_STATE_REMOTE_NAME
	end

	return Remotes.serverToClient and Remotes.serverToClient.shiftStateUpdated
		or DEFAULT_SHIFT_STATE_REMOTE_NAME
end

local function setAttributeIfPresent(name, value, expectedType)
	if type(value) == expectedType then
		player:SetAttribute(name, value)
	end
end

local function applySnapshot(action, snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	if action == "PayoutSummary" then
		local summary = snapshot.payoutSummary
		if type(summary) ~= "table" then
			return
		end

		setAttributeIfPresent(Config.shiftPayoutSummaryEventIdAttribute, summary.eventId, "number")
		setAttributeIfPresent(Config.shiftPayoutFareTotalsAttribute, summary.fareTotals, "number")
		setAttributeIfPresent(Config.shiftPayoutBonusesAttribute, summary.bonuses, "number")
		setAttributeIfPresent(Config.shiftPayoutDamagePenaltiesAttribute, summary.damagePenalties, "number")
		setAttributeIfPresent(Config.shiftPayoutMedallionFeeRateAttribute, summary.medallionFeeRate, "number")
		setAttributeIfPresent(Config.shiftPayoutMedallionFeeAmountAttribute, summary.medallionFeeAmount, "number")
		setAttributeIfPresent(Config.shiftPayoutNetDepositAttribute, summary.netDeposit, "number")
		setAttributeIfPresent(Config.shiftGrossMoneyAttribute, summary.grossEarnings, "number")
		return
	end

	setAttributeIfPresent(Config.shiftPhaseAttribute, snapshot.phase, "string")
	setAttributeIfPresent(Config.shiftIdAttribute, snapshot.shiftId, "number")
	setAttributeIfPresent(Config.shiftTimeRemainingAttribute, snapshot.timeRemaining, "number")
	setAttributeIfPresent(Config.shiftDurationAttribute, snapshot.duration, "number")
end

local remote = ReplicatedStorage:WaitForChild(getRemoteName())
remote.OnClientEvent:Connect(applySnapshot)
