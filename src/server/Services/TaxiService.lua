local TaxiController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("TaxiController"))

local TaxiService = {}
TaxiService.__index = TaxiService

function TaxiService.new(options)
	options = options or {}

	return setmetatable({
		config = options.config or {},
		cabFactory = options.cabFactory,
		remotes = options.remotes or {},
		world = options.world,
		driveSurfaces = options.driveSurfaces or {},
		crashObstacles = options.crashObstacles or {},
		cabHandles = {},
		controllersBySeat = {},
		connections = {},
		started = false,
	}, TaxiService)
end

function TaxiService:_trackConnection(connection)
	table.insert(self.connections, connection)
	return connection
end

function TaxiService:_getPlayerSeat(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.SeatPart or nil
end

function TaxiService:_routeDriveInput(player, ...)
	local seatPart = self:_getPlayerSeat(player)
	local controller = seatPart and self.controllersBySeat[seatPart]
	if controller then
		controller:handleDriveInput(player, ...)
	end
end

function TaxiService:start()
	if self.started then
		return
	end
	self.started = true

	local driveInputRemote = self.remotes.driveInput
	if driveInputRemote then
		self:_trackConnection(driveInputRemote.OnServerEvent:Connect(function(player, ...)
			self:_routeDriveInput(player, ...)
		end))
	end
end

function TaxiService:createCab(options)
	options = options or {}

	local cabFactory = assert(self.cabFactory, "TaxiService requires a cabFactory")
	local carConfig = options.config or cabFactory:createConfig(options.profileName, options.configOverrides)
	local car, seat, driftEmitters = cabFactory:createCab(options.world or self.world, options.spawnPose, carConfig)
	local handle = {
		car = car,
		seat = seat,
		driftEmitters = driftEmitters,
		config = carConfig,
		controller = nil,
	}

	table.insert(self.cabHandles, handle)
	return handle
end

function TaxiService:startCabController(handle, options)
	options = options or {}
	if handle.controller then
		return handle.controller
	end

	local controller = TaxiController.new({
		car = handle.car,
		seat = handle.seat,
		driftEmitters = handle.driftEmitters,
		cameraEventRemote = options.cameraEventRemote or self.remotes.cameraEvent,
		driveSurfaces = options.driveSurfaces or self.driveSurfaces,
		crashObstacles = options.crashObstacles or self.crashObstacles,
		spawnPose = options.spawnPose,
		config = handle.config,
		driverMode = options.driverMode or handle.config.driverMode,
		inputProvider = options.inputProvider,
		fareService = options.fareService,
	})

	handle.controller = controller
	self.controllersBySeat[handle.seat] = controller
	controller:start()

	self:_trackConnection(handle.car.Destroying:Connect(function()
		if self.controllersBySeat[handle.seat] == controller then
			self.controllersBySeat[handle.seat] = nil
		end
	end))

	return controller
end

function TaxiService:spawnCab(options)
	options = options or {}
	local handle = self:createCab(options)
	self:startCabController(handle, options)
	return handle
end

function TaxiService:applyLiveTuning(key, value)
	for index = #self.cabHandles, 1, -1 do
		local handle = self.cabHandles[index]
		local car = handle.car
		if not car or not car.Parent then
			table.remove(self.cabHandles, index)
		else
			self.cabFactory:applyLiveConfig(car, handle.config, key, value)
		end
	end
end

function TaxiService:stop()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)

	for _, handle in ipairs(self.cabHandles) do
		if handle.controller then
			handle.controller:stop()
			handle.controller = nil
		end
	end
	table.clear(self.controllersBySeat)
	self.started = false
end

return TaxiService
