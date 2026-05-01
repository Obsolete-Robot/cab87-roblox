local VehicleCatalog = {}

local TAXIS = {
	starter_taxi = {
		id = "starter_taxi",
		displayName = "Starter Taxi",
		profileName = "PlayerTaxi",
		modelAssetId = 130931394696553,
		stats = {
			speed = 120,
			acceleration = 95,
			handling = 2.0,
			fuelCapacity = 100,
		},
		unlockPrice = 0,
	},
	metro_taxi = {
		id = "metro_taxi",
		displayName = "Metro Taxi",
		profileName = "PlayerTaxi",
		modelAssetId = 130931394696553,
		stats = {
			speed = 132,
			acceleration = 108,
			handling = 2.15,
			fuelCapacity = 120,
		},
		unlockPrice = 350,
	},
}

local STARTER_TAXI_ID = "starter_taxi"

local function copyTaxiEntry(entry)
	if type(entry) ~= "table" then
		return nil
	end

	local clone = table.clone(entry)
	if type(entry.stats) == "table" then
		clone.stats = table.clone(entry.stats)
	end

	return clone
end

function VehicleCatalog.getStarterTaxiId()
	return STARTER_TAXI_ID
end

function VehicleCatalog.isKnownTaxiId(taxiId)
	return type(taxiId) == "string" and TAXIS[taxiId] ~= nil
end

function VehicleCatalog.getById(taxiId)
	if not VehicleCatalog.isKnownTaxiId(taxiId) then
		return nil
	end

	return copyTaxiEntry(TAXIS[taxiId])
end

function VehicleCatalog.getUnlockPrice(taxiId)
	local entry = TAXIS[taxiId]
	if not entry then
		return nil
	end

	return entry.unlockPrice
end

function VehicleCatalog.resolve(taxiId)
	if VehicleCatalog.isKnownTaxiId(taxiId) then
		return copyTaxiEntry(TAXIS[taxiId]), taxiId, false
	end

	local starter = TAXIS[STARTER_TAXI_ID]
	return copyTaxiEntry(starter), STARTER_TAXI_ID, taxiId ~= nil
end

function VehicleCatalog.listIds()
	local ids = {}
	for taxiId in pairs(TAXIS) do
		table.insert(ids, taxiId)
	end
	table.sort(ids)
	return ids
end

return VehicleCatalog
