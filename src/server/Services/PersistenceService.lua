local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PersistenceService = {}
PersistenceService.__index = PersistenceService

local SCHEMA_VERSION = 1

local function getStarterTaxiId(vehicleCatalog, config)
	if vehicleCatalog and vehicleCatalog.getStarterTaxiId then
		return vehicleCatalog.getStarterTaxiId()
	end

	return config.carDefaultTaxiId or "starter_taxi"
end

local function makeDefaultProfile(vehicleCatalog, config)
	local starterTaxiId = getStarterTaxiId(vehicleCatalog, config)
	return {
		schemaVersion = SCHEMA_VERSION,
		bankMoney = 0,
		ownedTaxiIds = {
			[starterTaxiId] = true,
		},
		equippedTaxiId = starterTaxiId,
	}
end

local function sanitizeOwnedTaxiIds(rawOwned, starterTaxiId, vehicleCatalog)
	local owned = {}
	if type(rawOwned) == "table" then
		for taxiId, isOwned in pairs(rawOwned) do
			if isOwned == true and type(taxiId) == "string" then
				if not vehicleCatalog or not vehicleCatalog.isKnownTaxiId or vehicleCatalog.isKnownTaxiId(taxiId) then
					owned[taxiId] = true
				end
			end
		end
	end

	owned[starterTaxiId] = true
	return owned
end

local function sanitizeProfile(rawProfile, vehicleCatalog, config)
	local starterTaxiId = getStarterTaxiId(vehicleCatalog, config)
	local profile = {
		schemaVersion = SCHEMA_VERSION,
		bankMoney = 0,
		ownedTaxiIds = {},
		equippedTaxiId = starterTaxiId,
	}

	if type(rawProfile) ~= "table" then
		profile.ownedTaxiIds = sanitizeOwnedTaxiIds(nil, starterTaxiId, vehicleCatalog)
		return profile
	end

	if type(rawProfile.bankMoney) == "number" then
		profile.bankMoney = math.max(math.floor(rawProfile.bankMoney + 0.5), 0)
	end

	profile.ownedTaxiIds = sanitizeOwnedTaxiIds(rawProfile.ownedTaxiIds, starterTaxiId, vehicleCatalog)

	if type(rawProfile.equippedTaxiId) == "string" and profile.ownedTaxiIds[rawProfile.equippedTaxiId] then
		profile.equippedTaxiId = rawProfile.equippedTaxiId
	end

	return profile
end

local function encodeOwnedTaxiIds(ownedTaxiIds)
	local ids = {}
	for taxiId, owned in pairs(ownedTaxiIds or {}) do
		if owned == true then
			table.insert(ids, taxiId)
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

function PersistenceService.new(options)
	options = options or {}

	local storeName = options.storeName or "Cab87PlayerProfile"
	local scope = options.scope
	local dataStore
	if type(scope) == "string" and scope ~= "" then
		dataStore = DataStoreService:GetDataStore(storeName, scope)
	else
		dataStore = DataStoreService:GetDataStore(storeName)
	end

	return setmetatable({
		config = options.config or {},
		vehicleCatalog = options.vehicleCatalog,
		players = options.players or Players,
		dataStore = dataStore,
		profilesByPlayer = {},
		dirtyByPlayer = {},
		connections = {},
		running = false,
	}, PersistenceService)
end

function PersistenceService:_setPlayerAttributes(player, profile)
	if not (player and profile) then
		return
	end

	local equippedAttribute = self.config.vehicleEquippedTaxiIdAttribute or "Cab87EquippedTaxiId"
	local ownedAttribute = self.config.vehicleOwnedTaxiIdsAttribute or "Cab87OwnedTaxiIds"
	local selectedAttribute = self.config.carSelectedTaxiIdAttribute or "Cab87SelectedTaxiId"

	player:SetAttribute(equippedAttribute, profile.equippedTaxiId)
	player:SetAttribute(selectedAttribute, profile.equippedTaxiId)
	player:SetAttribute(ownedAttribute, encodeOwnedTaxiIds(profile.ownedTaxiIds))
end

function PersistenceService:_keyForPlayer(player)
	return string.format("player:%d", player.UserId)
end

function PersistenceService:_retry(operationName, callback)
	local attempts = 3
	local lastError = nil

	for attempt = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end

		lastError = result
		warn(string.format("[cab87] Persistence %s attempt %d/%d failed: %s", operationName, attempt, attempts, tostring(result)))
		if attempt < attempts then
			task.wait(0.5 * attempt)
		end
	end

	return false, lastError
end

function PersistenceService:loadProfile(player)
	if self.profilesByPlayer[player] then
		return self.profilesByPlayer[player], false
	end

	local defaultProfile = makeDefaultProfile(self.vehicleCatalog, self.config)
	local key = self:_keyForPlayer(player)

	local ok, result = self:_retry("load", function()
		return self.dataStore:GetAsync(key)
	end)

	local profile
	if ok then
		profile = sanitizeProfile(result, self.vehicleCatalog, self.config)
	else
		warn("[cab87] Using fallback session profile for " .. player.Name .. " after load failure")
		profile = defaultProfile
	end

	self.profilesByPlayer[player] = profile
	self:_setPlayerAttributes(player, profile)

	return profile, ok
end

function PersistenceService:getProfile(player)
	local profile = self.profilesByPlayer[player]
	if profile then
		return profile
	end

	return self:loadProfile(player)
end

function PersistenceService:getBankMoney(player)
	local profile = self:getProfile(player)
	return profile and profile.bankMoney or 0
end

function PersistenceService:setBankMoney(player, amount)
	local profile = self:getProfile(player)
	if not profile then
		return 0
	end

	profile.bankMoney = math.max(math.floor((amount or 0) + 0.5), 0)
	self.dirtyByPlayer[player] = true
	return profile.bankMoney
end

function PersistenceService:getEquippedTaxiId(player)
	local profile = self:getProfile(player)
	return profile and profile.equippedTaxiId or getStarterTaxiId(self.vehicleCatalog, self.config)
end

function PersistenceService:isTaxiOwned(player, taxiId)
	local profile = self:getProfile(player)
	if not profile then
		return false
	end

	return profile.ownedTaxiIds[taxiId] == true
end

function PersistenceService:addOwnedTaxi(player, taxiId)
	local profile = self:getProfile(player)
	if not profile then
		return false
	end

	if profile.ownedTaxiIds[taxiId] then
		return false
	end

	profile.ownedTaxiIds[taxiId] = true
	self.dirtyByPlayer[player] = true
	self:_setPlayerAttributes(player, profile)
	return true
end

function PersistenceService:setEquippedTaxiId(player, taxiId)
	local profile = self:getProfile(player)
	if not profile then
		return false
	end

	if profile.ownedTaxiIds[taxiId] ~= true then
		return false
	end

	profile.equippedTaxiId = taxiId
	self.dirtyByPlayer[player] = true
	self:_setPlayerAttributes(player, profile)
	return true
end

function PersistenceService:getOwnedTaxiIds(player)
	local profile = self:getProfile(player)
	local owned = {}
	if not profile then
		return owned
	end

	for taxiId, isOwned in pairs(profile.ownedTaxiIds) do
		if isOwned then
			table.insert(owned, taxiId)
		end
	end
	table.sort(owned)
	return owned
end

function PersistenceService:saveProfile(player)
	local profile = self.profilesByPlayer[player]
	if not profile then
		return true
	end

	if not self.dirtyByPlayer[player] then
		return true
	end

	local key = self:_keyForPlayer(player)
	local payload = {
		schemaVersion = SCHEMA_VERSION,
		bankMoney = profile.bankMoney,
		ownedTaxiIds = table.clone(profile.ownedTaxiIds),
		equippedTaxiId = profile.equippedTaxiId,
	}

	local ok = self:_retry("save", function()
		self.dataStore:SetAsync(key, payload)
		return true
	end)

	if ok then
		self.dirtyByPlayer[player] = nil
	end

	return ok
end

function PersistenceService:start()
	if self.running then
		return
	end
	self.running = true

	for _, player in ipairs(self.players:GetPlayers()) do
		self:loadProfile(player)
	end

	table.insert(self.connections, self.players.PlayerAdded:Connect(function(player)
		self:loadProfile(player)
	end))

	table.insert(self.connections, self.players.PlayerRemoving:Connect(function(player)
		self:saveProfile(player)
		self.profilesByPlayer[player] = nil
		self.dirtyByPlayer[player] = nil
	end))

	game:BindToClose(function()
		for _, player in ipairs(self.players:GetPlayers()) do
			self:saveProfile(player)
		end
	end)
end

function PersistenceService:stop()
	if not self.running then
		return
	end

	self.running = false
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return PersistenceService
