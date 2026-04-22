local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local GameplayStateStore = require(script.Parent:WaitForChild("GameplayStateStore"))

local function setAttributeIfPresent(name, value, expectedType)
	if type(name) == "string" and type(value) == expectedType then
		player:SetAttribute(name, value)
	end
end

local function mirrorShiftState(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	setAttributeIfPresent(Config.shiftPhaseAttribute, snapshot.phase, "string")
	setAttributeIfPresent(Config.shiftIdAttribute, snapshot.shiftId, "number")
	setAttributeIfPresent(Config.shiftTimeRemainingAttribute, snapshot.timeRemaining, "number")
	setAttributeIfPresent(Config.shiftDurationAttribute, snapshot.duration, "number")
	setAttributeIfPresent(Config.shiftGrossMoneyAttribute, snapshot.grossMoney, "number")
	setAttributeIfPresent(Config.shiftBankMoneyAttribute, snapshot.bankMoney, "number")
end

local function mirrorPayoutSummary(summary)
	if type(summary) ~= "table" then
		return
	end

	setAttributeIfPresent(Config.shiftPayoutSummaryEventIdAttribute, summary.eventId, "number")
	setAttributeIfPresent(Config.shiftPayoutFareTotalsAttribute, summary.fareTotals, "number")
	setAttributeIfPresent(Config.shiftPayoutBonusesAttribute, summary.bonuses, "number")
	setAttributeIfPresent(Config.shiftPayoutTimePenaltiesAttribute, summary.timePenalties, "number")
	setAttributeIfPresent(Config.shiftPayoutDamagePenaltiesAttribute, summary.damagePenalties, "number")
	setAttributeIfPresent(Config.shiftPayoutMedallionFeeRateAttribute, summary.medallionFeeRate, "number")
	setAttributeIfPresent(Config.shiftPayoutMedallionFeeAmountAttribute, summary.medallionFeeAmount, "number")
	setAttributeIfPresent(Config.shiftPayoutNetDepositAttribute, summary.netDeposit, "number")
	setAttributeIfPresent(Config.shiftBankMoneyAttribute, summary.bankBalance, "number")
	setAttributeIfPresent(Config.shiftGrossMoneyAttribute, summary.grossEarnings, "number")
end

local disconnect = GameplayStateStore.onChanged(function(kind, payload)
	if kind == "shiftState" then
		mirrorShiftState(payload)
	elseif kind == "payoutSummary" then
		mirrorPayoutSummary(payload)
	end
end)

mirrorShiftState(GameplayStateStore.getShiftState())
mirrorPayoutSummary(GameplayStateStore.getPayoutSummary())

script.Destroying:Connect(function()
	disconnect()
end)
