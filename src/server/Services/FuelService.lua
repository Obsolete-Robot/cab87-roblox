local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FuelService = {}
FuelService.__index = FuelService

local STATES = {
	idle = "idle",
	starting = "starting",
	refueling = "refueling",
	cancelled = "cancelled",
	completed = "completed",
	failed = "failed",
}

local function toNumber(value, fallback)
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return fallback
end

local function toVector3(value)
	if typeof(value) == "Vector3" then
		return value
	end
	return nil
end

function FuelService.new(options)
	options = options or {}
	return setmetatable({
		config = options.config or {},
		players = options.players or Players,
		economyService = options.economyService,
		taxiService = options.taxiService,
		remote = options.remote,
		stateRemote = options.stateRemote,
		stateByPlayer = {},
		stationsById = {},
		connections = {},
	}, FuelService)
end

function FuelService:_fuelCapacity()
	return math.max(toNumber(self.config.fuelCapacity, 100), 1)
end

function FuelService:_fuelCapacityForPlayer(player)
	local cab = self.taxiService and self.taxiService:getCabForPlayer(player)
	if cab then
		local capacity = toNumber(cab:GetAttribute(self.config.carFuelCapacityAttribute or "Cab87FuelCapacity"), nil)
		if capacity then
			return math.max(capacity, 1)
		end
	end

	return self:_fuelCapacity()
end

function FuelService:_buildStations()
	self.stationsById = {}
	for _, station in ipairs(self.config.fuelStations or {}) do
		if type(station) == "table" and type(station.id) == "string" and station.id ~= "" then
			local position = toVector3(station.position)
			if position then
				self.stationsById[station.id] = {
					id = station.id,
					kind = station.kind == "cab_company" and "cab_company" or "paid",
					name = station.name or station.id,
					position = position,
				}
			end
		end
	end
end

function FuelService:_ensurePlayerState(player)
	local state = self.stateByPlayer[player]
	if state then
		return state
	end

	state = {
		fuel = self:_fuelCapacityForPlayer(player),
		state = STATES.idle,
		stationId = nil,
		startedAt = 0,
		completeAt = 0,
		price = 0,
		paidCharged = false,
		cooldownUntil = 0,
		nextBurnPublishAt = 0,
		lastPublishedFuel = self:_fuelCapacityForPlayer(player),
	}
	self.stateByPlayer[player] = state
	self:_publish(player)
	return state
end

function FuelService:_fire(player, payload)
	if self.stateRemote and player then
		self.stateRemote:FireClient(player, payload)
	end
end

function FuelService:_publish(player, reason)
	local state = self:_ensurePlayerState(player)
	local capacity = self:_fuelCapacityForPlayer(player)
	state.fuel = math.clamp(state.fuel, 0, capacity)
	local station = state.stationId and self.stationsById[state.stationId] or nil
	local payload = {
		fuel = state.fuel,
		capacity = capacity,
		state = state.state,
		stationId = state.stationId,
		stationName = station and station.name or nil,
		stationKind = station and station.kind or nil,
		price = state.price,
		startedAt = state.startedAt,
		completeAt = state.completeAt,
		reason = reason,
		serverTime = Workspace:GetServerTimeNow(),
	}
	state.lastPublishedFuel = state.fuel
	self:_fire(player, payload)

	local cab = self.taxiService and self.taxiService:getCabForPlayer(player)
	if cab then
		cab:SetAttribute(self.config.carFuelAmountAttribute or "Cab87FuelAmount", state.fuel)
		cab:SetAttribute(self.config.carFuelCapacityAttribute or "Cab87FuelCapacity", payload.capacity)
		cab:SetAttribute(self.config.carRefuelStateAttribute or "Cab87RefuelState", state.state)
		cab:SetAttribute(self.config.carRefuelStationAttribute or "Cab87RefuelStation", state.stationId or "")
	end
end

function FuelService:_getStation(player, stationId)
	local station = self.stationsById[stationId]
	if not station then
		return nil, "invalid_station"
	end

	local cab = self.taxiService and self.taxiService:getCabForPlayer(player)
	if not cab then
		return nil, "missing_cab"
	end

	local primary = cab.PrimaryPart or cab:FindFirstChildWhichIsA("BasePart")
	if not primary then
		return nil, "missing_cab"
	end

	local baseRadius = station.kind == "cab_company"
		and toNumber(self.config.fuelCabCompanyStationRadius, 34)
		or toNumber(self.config.fuelRefuelStationRadius, 28)
	local distance = (Vector3.new(primary.Position.X, 0, primary.Position.Z) - Vector3.new(station.position.X, 0, station.position.Z)).Magnitude
	if distance > math.max(baseRadius, 1) then
		return nil, "too_far"
	end

	return station
end

function FuelService:requestRefuel(player, stationId, mode)
	local state = self:_ensurePlayerState(player)
	local now = Workspace:GetServerTimeNow()
	if now < state.cooldownUntil then
		return false, "cooldown"
	end

	if state.state == STATES.starting or state.state == STATES.refueling then
		return false, "already_refueling"
	end

	local station, stationErr = self:_getStation(player, stationId)
	if not station then
		state.state = STATES.failed
		self:_publish(player, stationErr)
		return false, stationErr
	end

	local isCabCompany = station.kind == "cab_company"
	if (mode == "cab_company") ~= isCabCompany then
		state.state = STATES.failed
		self:_publish(player, "mode_mismatch")
		return false, "mode_mismatch"
	end

	local capacity = self:_fuelCapacityForPlayer(player)
	state.fuel = math.clamp(state.fuel, 0, capacity)
	local missing = math.max(capacity - state.fuel, 0)
	if missing <= 0.01 then
		state.state = STATES.failed
		self:_publish(player, "tank_full")
		return false, "tank_full"
	end

	local price = 0
	if not isCabCompany then
		price = math.max(math.floor(missing * toNumber(self.config.fuelPaidPricePerUnit, 2) + 0.5), 0)
		local ok = self.economyService and self.economyService.spendBankMoney
			and self.economyService:spendBankMoney(player, price)
		if ok ~= true then
			state.state = STATES.failed
			self:_publish(player, "insufficient_funds")
			return false, "insufficient_funds"
		end
	end

	state.state = STATES.starting
	state.stationId = station.id
	state.startedAt = now
	state.price = price
	state.paidCharged = price > 0
	local duration = isCabCompany and toNumber(self.config.fuelCabCompanyRefuelDurationSeconds, 6.5)
		or toNumber(self.config.fuelPaidRefuelDurationSeconds, 2.5)
	state.completeAt = now + math.max(duration, 0.2)
	self:_publish(player, "started")

	return true
end

function FuelService:_cancel(player, reason)
	local state = self:_ensurePlayerState(player)
	if state.paidCharged and state.price > 0 and self.economyService and self.economyService.creditBankMoney then
		self.economyService:creditBankMoney(player, state.price)
	end

	state.state = STATES.cancelled
	state.stationId = nil
	state.startedAt = 0
	state.completeAt = 0
	state.price = 0
	state.paidCharged = false
	state.cooldownUntil = Workspace:GetServerTimeNow() + math.max(toNumber(self.config.fuelRefuelCooldownSeconds, 1), 0)
	self:_publish(player, reason or "cancelled")
end

function FuelService:_complete(player)
	local state = self:_ensurePlayerState(player)
	state.state = STATES.completed
	state.fuel = self:_fuelCapacityForPlayer(player)
	state.stationId = nil
	state.startedAt = 0
	state.completeAt = 0
	state.price = 0
	state.paidCharged = false
	state.cooldownUntil = Workspace:GetServerTimeNow() + math.max(toNumber(self.config.fuelRefuelCooldownSeconds, 1), 0)
	self:_publish(player, "completed")
end

function FuelService:_tickRefuel(player, state)
	local now = Workspace:GetServerTimeNow()
	if state.state == STATES.starting and now >= state.startedAt + 0.05 then
		state.state = STATES.refueling
		self:_publish(player, "refueling")
	end

	if state.state ~= STATES.refueling and state.state ~= STATES.starting then
		return
	end

	local station = state.stationId and self.stationsById[state.stationId]
	if not station then
		self:_cancel(player, "missing_station")
		return
	end

	local verifiedStation, err = self:_getStation(player, state.stationId)
	if not verifiedStation then
		self:_cancel(player, err)
		return
	end

	if now >= state.completeAt then
		self:_complete(player)
	end
end

function FuelService:_tickFuelBurn(player, state, dt)
	if state.state == STATES.starting or state.state == STATES.refueling then
		return
	end

	local cab = self.taxiService and self.taxiService:getCabForPlayer(player)
	if not cab then
		return
	end

	local speed = toNumber(cab:GetAttribute(self.config.carSpeedAttribute), 0)
	local maxSpeed = math.max(toNumber(self.config.carMaxForward, 120), 1)
	local burnRate = math.max(toNumber(self.config.fuelBurnPerSecondAtMaxSpeed, 0.38), 0)
	local capacity = self:_fuelCapacityForPlayer(player)
	state.fuel = math.clamp(state.fuel, 0, capacity)
	local burn = math.clamp(speed / maxSpeed, 0, 1) * burnRate * dt
	local previousFuel = state.fuel
	if burn > 0 then
		state.fuel = math.max(state.fuel - burn, 0)
	end

	local multiplier = 1
	if state.fuel <= 0.001 then
		multiplier = math.clamp(toNumber(self.config.fuelOutOfGasSpeedMultiplier, 0.33), 0.05, 1)
	end
	cab:SetAttribute(self.config.carConfigAttributePrefix .. "carMaxForward", maxSpeed * multiplier)

	local now = Workspace:GetServerTimeNow()
	local crossedLowFuel = previousFuel > (capacity * 0.2) and state.fuel <= (capacity * 0.2)
	local crossedOutOfFuel = previousFuel > 0.001 and state.fuel <= 0.001
	if crossedOutOfFuel or crossedLowFuel then
		self:_publish(player, "fuel_tick")
		state.nextBurnPublishAt = now + 0.2
		return
	end

	if math.abs(state.fuel - (state.lastPublishedFuel or previousFuel)) >= 0.1 and now >= (state.nextBurnPublishAt or 0) then
		self:_publish(player, "fuel_tick")
		state.nextBurnPublishAt = now + 0.25
	end
end

function FuelService:start()
	self:_buildStations()

	if self.remote then
		table.insert(self.connections, self.remote.OnServerEvent:Connect(function(player, stationId, mode)
			if typeof(stationId) ~= "string" or typeof(mode) ~= "string" then
				return
			end
			self:requestRefuel(player, stationId, mode)
		end))
	end

	table.insert(self.connections, self.players.PlayerAdded:Connect(function(player)
		self:_ensurePlayerState(player)
	end))

	table.insert(self.connections, self.players.PlayerRemoving:Connect(function(player)
		self.stateByPlayer[player] = nil
	end))

	for _, player in ipairs(self.players:GetPlayers()) do
		self:_ensurePlayerState(player)
	end

	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt)
		for player, state in pairs(self.stateByPlayer) do
			self:_tickRefuel(player, state)
			self:_tickFuelBurn(player, state, dt)
		end
	end))
end

function FuelService:stop()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.stateByPlayer)
end

return FuelService
