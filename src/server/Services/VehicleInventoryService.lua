local Players = game:GetService("Players")

local VehicleInventoryService = {}
VehicleInventoryService.__index = VehicleInventoryService

local function buildCatalogSnapshot(vehicleCatalog, ownedTaxiIds, bankMoney, equippedTaxiId)
	local entries = {}
	for _, taxiId in ipairs(vehicleCatalog.listIds()) do
		local taxi = vehicleCatalog.getById(taxiId)
		local unlockPrice = vehicleCatalog.getUnlockPrice(taxiId) or 0
		table.insert(entries, {
			id = taxiId,
			displayName = taxi and taxi.displayName or taxiId,
			unlockPrice = unlockPrice,
			owned = ownedTaxiIds[taxiId] == true,
			equipped = equippedTaxiId == taxiId,
			affordable = bankMoney >= unlockPrice,
		})
	end

	return entries
end

function VehicleInventoryService.new(options)
	options = options or {}

	return setmetatable({
		config = options.config or {},
		players = options.players or Players,
		remotes = options.remotes or {},
		vehicleCatalog = options.vehicleCatalog,
		economyService = options.economyService,
		persistenceService = options.persistenceService,
		connections = {},
		running = false,
	}, VehicleInventoryService)
end

function VehicleInventoryService:_snapshotForPlayer(player)
	local ownedIds = self.persistenceService:getOwnedTaxiIds(player)
	local owned = {}
	for _, taxiId in ipairs(ownedIds) do
		owned[taxiId] = true
	end

	local bankMoney = self.economyService:getBankMoney(player)
	local equippedTaxiId = self.persistenceService:getEquippedTaxiId(player)

	return {
		bankMoney = bankMoney,
		equippedTaxiId = equippedTaxiId,
		ownedTaxiIds = ownedIds,
		catalog = buildCatalogSnapshot(self.vehicleCatalog, owned, bankMoney, equippedTaxiId),
	}
end

function VehicleInventoryService:_fireSnapshot(player, action, ok, reason)
	local remote = self.remotes.vehicleInventoryUpdated
	if not remote then
		return
	end

	remote:FireClient(player, {
		action = action,
		ok = ok,
		reason = reason,
		snapshot = self:_snapshotForPlayer(player),
	})
end

function VehicleInventoryService:isTaxiOwned(player, taxiId)
	if not (self.vehicleCatalog and self.vehicleCatalog.isKnownTaxiId and self.vehicleCatalog.isKnownTaxiId(taxiId)) then
		return false
	end

	return self.persistenceService:isTaxiOwned(player, taxiId)
end

function VehicleInventoryService:getEquippedTaxiId(player)
	return self.persistenceService:getEquippedTaxiId(player)
end

function VehicleInventoryService:equipTaxi(player, taxiId)
	if not self.vehicleCatalog.isKnownTaxiId(taxiId) then
		return false, "unknownTaxi"
	end

	if not self.persistenceService:isTaxiOwned(player, taxiId) then
		return false, "notOwned"
	end

	local ok = self.persistenceService:setEquippedTaxiId(player, taxiId)
	if not ok then
		return false, "equipFailed"
	end

	self.persistenceService:saveProfile(player)
	self:_fireSnapshot(player, "equip", true)
	return true
end

function VehicleInventoryService:purchaseTaxi(player, taxiId)
	if not self.vehicleCatalog.isKnownTaxiId(taxiId) then
		return false, "unknownTaxi"
	end

	if self.persistenceService:isTaxiOwned(player, taxiId) then
		return false, "alreadyOwned"
	end

	local unlockPrice = self.vehicleCatalog.getUnlockPrice(taxiId)
	if type(unlockPrice) ~= "number" then
		return false, "missingPrice"
	end

	local spent, reason = self.economyService:spendBankMoney(player, unlockPrice)
	if not spent then
		return false, reason or "insufficientFunds"
	end

	self.persistenceService:addOwnedTaxi(player, taxiId)
	self.persistenceService:setEquippedTaxiId(player, taxiId)
	self.persistenceService:saveProfile(player)
	self:_fireSnapshot(player, "purchase", true)
	return true
end

function VehicleInventoryService:_handleInventoryAction(player, payload)
	if type(payload) ~= "table" then
		self:_fireSnapshot(player, "snapshot", false, "invalidPayload")
		return
	end

	local action = payload.action
	local taxiId = payload.taxiId

	if action == "purchase" then
		local ok, reason = self:purchaseTaxi(player, taxiId)
		if not ok then
			self:_fireSnapshot(player, "purchase", false, reason)
		end
		return
	end

	if action == "equip" then
		local ok, reason = self:equipTaxi(player, taxiId)
		if not ok then
			self:_fireSnapshot(player, "equip", false, reason)
		end
		return
	end

	self:_fireSnapshot(player, "snapshot", true)
end

function VehicleInventoryService:start()
	if self.running then
		return
	end
	self.running = true

	table.insert(self.connections, self.players.PlayerAdded:Connect(function(player)
		task.defer(function()
			self:_fireSnapshot(player, "snapshot", true)
		end)
	end))

	for _, player in ipairs(self.players:GetPlayers()) do
		task.defer(function()
			self:_fireSnapshot(player, "snapshot", true)
		end)
	end

	if self.remotes.vehicleInventoryAction then
		table.insert(self.connections, self.remotes.vehicleInventoryAction.OnServerEvent:Connect(function(player, payload)
			self:_handleInventoryAction(player, payload)
		end))
	end
end

function VehicleInventoryService:stop()
	if not self.running then
		return
	end

	self.running = false
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return VehicleInventoryService
