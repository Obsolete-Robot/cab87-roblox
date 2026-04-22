local Players = game:GetService("Players")

local EconomyService = {}
EconomyService.__index = EconomyService

local function getConfigNumber(config, key, fallback)
	local value = config and config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function setAttributeIfNamed(instance, attributeName, value)
	if type(attributeName) == "string" and attributeName ~= "" then
		instance:SetAttribute(attributeName, value)
	end
end

function EconomyService.new(options)
	options = options or {}

	return setmetatable({
		config = options.config or {},
		players = options.players or Players,
		persistenceService = options.persistenceService,
		bankByPlayer = {}, -- session-scoped until PersistenceService milestone lands
		payoutEventIdByPlayer = {},
		connections = {},
		running = false,
	}, EconomyService)
end

function EconomyService:_ensurePlayerBank(player)
	local bank = self.bankByPlayer[player]
	if type(bank) ~= "number" then
		if self.persistenceService and self.persistenceService.getBankMoney then
			bank = self.persistenceService:getBankMoney(player)
		else
			bank = 0
		end
		self.bankByPlayer[player] = bank
	end

	setAttributeIfNamed(player, self.config.shiftBankMoneyAttribute, bank)
	return bank
end

function EconomyService:getBankMoney(player)
	return self:_ensurePlayerBank(player)
end

function EconomyService:spendBankMoney(player, amount)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false, "invalidAmount"
	end

	local roundedAmount = math.max(math.floor(amount + 0.5), 0)
	local currentBank = self:_ensurePlayerBank(player)
	if currentBank < roundedAmount then
		return false, "insufficientFunds"
	end

	local nextBank = currentBank - roundedAmount
	self.bankByPlayer[player] = nextBank
	setAttributeIfNamed(player, self.config.shiftBankMoneyAttribute, nextBank)

	if self.persistenceService and self.persistenceService.setBankMoney then
		self.persistenceService:setBankMoney(player, nextBank)
	end

	return true
end

function EconomyService:createShiftPayoutSummary(player, grossEarnings, breakdown)
	if not player then
		return nil
	end

	local medallionFeeRate = math.clamp(getConfigNumber(self.config, "shiftMedallionFeeRate", 0.2), 0, 1)
	local gross = math.max(math.floor((grossEarnings or 0) + 0.5), 0)
	local fareTotals = math.max(math.floor(((breakdown and breakdown.fareTotals) or 0) + 0.5), 0)
	local bonuses = math.max(math.floor(((breakdown and breakdown.bonuses) or 0) + 0.5), 0)
	local timePenalties = math.max(math.floor(((breakdown and breakdown.timePenalties) or 0) + 0.5), 0)
	local damagePenalties = math.max(math.floor(((breakdown and breakdown.damagePenalties) or 0) + 0.5), 0)
	local medallionFeeAmount = math.max(math.floor(gross * medallionFeeRate + 0.5), 0)
	local netDeposit = math.max(gross - medallionFeeAmount, 0)

	local eventId = (self.payoutEventIdByPlayer[player] or 0) + 1
	self.payoutEventIdByPlayer[player] = eventId

	local bankBalance = self:_ensurePlayerBank(player) + netDeposit
	self.bankByPlayer[player] = bankBalance
	setAttributeIfNamed(player, self.config.shiftBankMoneyAttribute, bankBalance)
	if self.persistenceService and self.persistenceService.setBankMoney then
		self.persistenceService:setBankMoney(player, bankBalance)
		self.persistenceService:saveProfile(player)
	end
	setAttributeIfNamed(player, self.config.shiftPayoutSummaryEventIdAttribute, eventId)
	setAttributeIfNamed(player, self.config.shiftPayoutFareTotalsAttribute, fareTotals)
	setAttributeIfNamed(player, self.config.shiftPayoutBonusesAttribute, bonuses)
	setAttributeIfNamed(player, self.config.shiftPayoutTimePenaltiesAttribute, timePenalties)
	setAttributeIfNamed(player, self.config.shiftPayoutDamagePenaltiesAttribute, damagePenalties)
	setAttributeIfNamed(player, self.config.shiftPayoutMedallionFeeRateAttribute, medallionFeeRate)
	setAttributeIfNamed(player, self.config.shiftPayoutMedallionFeeAmountAttribute, medallionFeeAmount)
	setAttributeIfNamed(player, self.config.shiftPayoutNetDepositAttribute, netDeposit)

	return {
		eventId = eventId,
		grossEarnings = gross,
		fareTotals = fareTotals,
		bonuses = bonuses,
		timePenalties = timePenalties,
		damagePenalties = damagePenalties,
		medallionFeeRate = medallionFeeRate,
		medallionFeeAmount = medallionFeeAmount,
		netDeposit = netDeposit,
		bankBalance = bankBalance,
	}
end

function EconomyService:start()
	if self.running then
		return
	end

	self.running = true

	for _, player in ipairs(self.players:GetPlayers()) do
		self:_ensurePlayerBank(player)
	end

	table.insert(self.connections, self.players.PlayerAdded:Connect(function(player)
		self:_ensurePlayerBank(player)
	end))

	table.insert(self.connections, self.players.PlayerRemoving:Connect(function(player)
		self.bankByPlayer[player] = nil
		self.payoutEventIdByPlayer[player] = nil
	end))
end

function EconomyService:stop()
	if not self.running then
		return
	end

	self.running = false
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.bankByPlayer)
	table.clear(self.payoutEventIdByPlayer)
end

return EconomyService
