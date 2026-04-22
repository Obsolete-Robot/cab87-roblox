local Players = game:GetService("Players")

local TaxiController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("TaxiController"))

local OWNER_USER_ID_ATTRIBUTE_FALLBACK = "Cab87OwnerUserId"

local TaxiService = {}
TaxiService.__index = TaxiService

local function getOwnerUserId(owner)
	if typeof(owner) == "Instance" and owner:IsA("Player") then
		return owner.UserId
	end

	if type(owner) == "number" and owner == owner and owner > 0 then
		return math.floor(owner)
	end

	return nil
end

local function getOwnerAttributeName(config)
	local attributeName = config and config.carOwnerUserIdAttribute
	if type(attributeName) == "string" and attributeName ~= "" then
		return attributeName
	end

	return OWNER_USER_ID_ATTRIBUTE_FALLBACK
end

local function getPlayerForUserId(players, ownerPlayer, ownerUserId)
	if typeof(ownerPlayer) == "Instance" and ownerPlayer:IsA("Player") and ownerPlayer.UserId == ownerUserId then
		return ownerPlayer
	end

	if ownerUserId and players and players.GetPlayerByUserId then
		return players:GetPlayerByUserId(ownerUserId)
	end

	return nil
end

function TaxiService.new(options)
	options = options or {}

	return setmetatable({
		config = options.config or {},
		players = options.players or Players,
		cabFactory = options.cabFactory,
		remotes = options.remotes or {},
		world = options.world,
		driveSurfaces = options.driveSurfaces or {},
		crashObstacles = options.crashObstacles or {},
		cabHandles = {},
		activeCabsByUserId = {},
		handleByCar = {},
		controllersBySeat = {},
		connections = {},
		started = false,
		cleanupOwnedCabsOnPlayerRemoving = options.cleanupOwnedCabsOnPlayerRemoving ~= false,
		destroyOwnedCabsOnPlayerRemoving = options.destroyOwnedCabsOnPlayerRemoving == true,
		stopReleasedControllersOnPlayerRemoving = options.stopReleasedControllersOnPlayerRemoving == true,
	}, TaxiService)
end

function TaxiService:_trackConnection(connection)
	table.insert(self.connections, connection)
	return connection
end

function TaxiService:_trackHandleConnection(handle, connection)
	handle.connections = handle.connections or {}
	table.insert(handle.connections, connection)
	return connection
end

function TaxiService:_disconnectHandleConnections(handle)
	for _, connection in ipairs(handle.connections or {}) do
		connection:Disconnect()
	end
	if handle.connections then
		table.clear(handle.connections)
	end
end

function TaxiService:_isHandleActive(handle)
	return handle ~= nil and handle.car ~= nil and handle.car.Parent ~= nil
end

function TaxiService:_setCabOwnerAttribute(handle, ownerUserId)
	if handle and handle.car then
		handle.car:SetAttribute(getOwnerAttributeName(self.config), ownerUserId)
	end
end

function TaxiService:_getActiveCabForUserId(ownerUserId)
	local resolvedUserId = getOwnerUserId(ownerUserId)
	if not resolvedUserId then
		return nil
	end

	local handle = self.activeCabsByUserId[resolvedUserId]
	if self:_isHandleActive(handle) then
		return handle
	end

	self.activeCabsByUserId[resolvedUserId] = nil
	return nil
end

function TaxiService:_removeHandle(handle)
	if not handle then
		return
	end

	if handle.ownerUserId and self.activeCabsByUserId[handle.ownerUserId] == handle then
		self.activeCabsByUserId[handle.ownerUserId] = nil
	end

	if handle.car and self.handleByCar[handle.car] == handle then
		self.handleByCar[handle.car] = nil
	end

	for index = #self.cabHandles, 1, -1 do
		if self.cabHandles[index] == handle then
			table.remove(self.cabHandles, index)
			break
		end
	end
end

function TaxiService:_setHandleOwner(handle, ownerPlayer, ownerUserId, options)
	options = options or {}
	if not handle then
		return false, nil
	end

	local resolvedUserId = getOwnerUserId(ownerPlayer) or getOwnerUserId(ownerUserId)
	if resolvedUserId and not options.allowDuplicate then
		local existingHandle = self:_getActiveCabForUserId(resolvedUserId)
		if existingHandle and existingHandle ~= handle then
			self:_setCabOwnerAttribute(handle, nil)
			if handle.controller and options.updateController ~= false then
				handle.controller:clearOwner({
					notify = false,
				})
			end
			return false, existingHandle
		end
	end

	local previousUserId = handle.ownerUserId
	if previousUserId and previousUserId ~= resolvedUserId and self.activeCabsByUserId[previousUserId] == handle then
		self.activeCabsByUserId[previousUserId] = nil
	end

	handle.ownerUserId = resolvedUserId
	handle.ownerPlayer = if resolvedUserId
		then getPlayerForUserId(self.players, ownerPlayer, resolvedUserId)
		else nil
	self:_setCabOwnerAttribute(handle, resolvedUserId)

	if resolvedUserId and not options.skipRegistry then
		self.activeCabsByUserId[resolvedUserId] = handle
	end

	if handle.controller and options.updateController ~= false then
		handle.controller:setOwner(handle.ownerPlayer, resolvedUserId, {
			notify = false,
		})
	end

	return true, handle
end

function TaxiService:_clearControllerForHandle(handle)
	if not handle then
		return
	end

	if handle.seat and self.controllersBySeat[handle.seat] == handle.controller then
		self.controllersBySeat[handle.seat] = nil
	end
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

local function getPlayerRootPart(player)
	if not (player and player:IsA("Player")) then
		return nil
	end

	local character = player.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	local primaryPart = character.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	return nil
end

local function getYawFromLookVector(lookVector, fallbackYaw)
	local horizontal = Vector3.new(lookVector.X, 0, lookVector.Z)
	if horizontal.Magnitude <= 0.001 then
		return fallbackYaw or 0
	end

	local unit = horizontal.Unit
	return math.atan2(unit.X, unit.Z)
end

function TaxiService:_resolveSpawnPose(spawnPose, ownerPlayer, carConfig)
	if not ownerPlayer then
		return spawnPose
	end

	local rootPart = getPlayerRootPart(ownerPlayer)
	if not rootPart then
		return spawnPose
	end

	local fallbackPose = spawnPose or {
		position = carConfig.carSpawn,
		yaw = 0,
	}

	local fallbackY = (fallbackPose.position and fallbackPose.position.Y) or rootPart.Position.Y
	return {
		position = Vector3.new(rootPart.Position.X, fallbackY, rootPart.Position.Z),
		yaw = getYawFromLookVector(rootPart.CFrame.LookVector, fallbackPose.yaw),
	}
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

	if self.cleanupOwnedCabsOnPlayerRemoving and self.players and self.players.PlayerRemoving then
		self:_trackConnection(self.players.PlayerRemoving:Connect(function(player)
			self:releaseCabForPlayer(player, {
				destroy = self.destroyOwnedCabsOnPlayerRemoving,
				stopController = self.stopReleasedControllersOnPlayerRemoving,
			})
		end))
	end
end

function TaxiService:createCab(options)
	options = options or {}

	local cabFactory = assert(self.cabFactory, "TaxiService requires a cabFactory")
	local profileName = options.profileName or options.taxiId
	local carConfig = options.config or cabFactory:createConfig(profileName, options.configOverrides)
	local ownerPlayer = options.ownerPlayer
	local ownerUserId = getOwnerUserId(ownerPlayer) or getOwnerUserId(options.ownerUserId)
	if ownerUserId and not options.allowDuplicate and self:_getActiveCabForUserId(ownerUserId) then
		error("TaxiService already has an active cab for userId " .. tostring(ownerUserId), 2)
	end

	local resolvedSpawnPose = self:_resolveSpawnPose(options.spawnPose, ownerPlayer, carConfig)
	local car, seat, driftEmitters = cabFactory:createCab(options.world or self.world, resolvedSpawnPose, carConfig)
	local handle = {
		taxiId = options.taxiId or profileName,
		car = car,
		seat = seat,
		driftEmitters = driftEmitters,
		spawnPose = resolvedSpawnPose,
		config = carConfig,
		ownerPlayer = nil,
		ownerUserId = nil,
		controller = nil,
		connections = {},
	}

	self.handleByCar[car] = handle
	table.insert(self.cabHandles, handle)
	self:_setHandleOwner(handle, ownerPlayer, ownerUserId, {
		allowDuplicate = options.allowDuplicate,
		updateController = false,
	})

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
		spawnPose = options.spawnPose or handle.spawnPose,
		config = handle.config,
		driverMode = options.driverMode or handle.config.driverMode,
		inputProvider = options.inputProvider,
		fareService = options.fareService,
		ownerPlayer = options.ownerPlayer or handle.ownerPlayer,
		ownerUserId = options.ownerUserId or handle.ownerUserId,
		ownerChanged = function(_, ownerPlayer, ownerUserId)
			local ok, existingHandle = self:_setHandleOwner(handle, ownerPlayer, ownerUserId, {
				updateController = false,
			})
			if not ok then
				warn(
					string.format(
						"[cab87] Refused duplicate cab ownership for userId %s; existing cab is %s",
						tostring(ownerUserId),
						existingHandle and existingHandle.car and existingHandle.car:GetFullName() or "unknown"
					)
				)
				if handle.controller then
					handle.controller:clearOwner({
						notify = false,
					})
				end
			end
		end,
	})

	handle.controller = controller
	self.controllersBySeat[handle.seat] = controller
	controller:start()

	self:_trackHandleConnection(handle, handle.car.Destroying:Connect(function()
		self:_clearControllerForHandle(handle)
		self:_setHandleOwner(handle, nil, nil, {
			updateController = false,
		})
		self:_removeHandle(handle)
		self:_disconnectHandleConnections(handle)
		handle.controller = nil
	end))

	return controller
end

function TaxiService:spawnCab(options)
	options = options or {}
	local handle = self:createCab(options)
	self:startCabController(handle, options)
	return handle
end

function TaxiService:spawnCabForPlayer(player, taxiId, spawnPose, options)
	options = options or {}
	local ownerUserId = getOwnerUserId(player)
	assert(ownerUserId, "spawnCabForPlayer requires a Player")

	local existingHandle = self:_getActiveCabForUserId(ownerUserId)
	if existingHandle and not options.allowDuplicate then
		if options.replaceExisting then
			self:releaseCab(existingHandle, {
				destroy = true,
				stopController = true,
			})
		else
			return existingHandle, false
		end
	end

	local cabOptions = table.clone(options)
	cabOptions.ownerPlayer = player
	cabOptions.ownerUserId = ownerUserId
	cabOptions.profileName = taxiId or options.profileName
	cabOptions.taxiId = taxiId or options.taxiId
	cabOptions.spawnPose = spawnPose or options.spawnPose

	local handle = self:createCab(cabOptions)
	if options.startController ~= false then
		self:startCabController(handle, cabOptions)
	end

	return handle, true
end

function TaxiService:recoverCabForPlayer(player, taxiId, spawnPose, options)
	local cabOptions = table.clone(options or {})
	cabOptions.replaceExisting = true
	return self:spawnCabForPlayer(player, taxiId, spawnPose, cabOptions)
end

function TaxiService:getActiveCabForUserId(ownerUserId)
	return self:_getActiveCabForUserId(ownerUserId)
end

function TaxiService:getActiveCabForPlayer(player)
	return self:_getActiveCabForUserId(getOwnerUserId(player))
end

function TaxiService:getCabHandleFromCar(car)
	return self.handleByCar[car]
end

function TaxiService:getOwnerUserIdForCab(cabOrHandle)
	if type(cabOrHandle) == "table" and cabOrHandle.car then
		return cabOrHandle.ownerUserId
	end

	local handle = self.handleByCar[cabOrHandle]
	if handle then
		return handle.ownerUserId
	end

	if typeof(cabOrHandle) == "Instance" then
		return getOwnerUserId(cabOrHandle:GetAttribute(getOwnerAttributeName(self.config)))
	end

	return nil
end

function TaxiService:releaseCab(handle, options)
	options = options or {}
	if not handle then
		return nil
	end

	local shouldDestroy = options.destroy == true
	local shouldStopController = shouldDestroy or options.stopController == true

	self:_setHandleOwner(handle, nil, nil, {
		updateController = not shouldStopController,
	})

	if shouldStopController and handle.controller then
		handle.controller:stop()
		self:_clearControllerForHandle(handle)
		handle.controller = nil
	end

	if shouldDestroy then
		self:_disconnectHandleConnections(handle)
		self:_removeHandle(handle)
		if handle.car and handle.car.Parent then
			handle.car:Destroy()
		end
	end

	return handle
end

function TaxiService:releaseCabForPlayer(player, options)
	local handle = self:getActiveCabForPlayer(player)
	if not handle then
		return nil
	end

	return self:releaseCab(handle, options)
end

function TaxiService:destroyCabForPlayer(player)
	return self:releaseCabForPlayer(player, {
		destroy = true,
		stopController = true,
	})
end

function TaxiService:applyLiveTuning(key, value)
	for index = #self.cabHandles, 1, -1 do
		local handle = self.cabHandles[index]
		local car = handle.car
		if not car or not car.Parent then
			self:_setHandleOwner(handle, nil, nil, {
				updateController = false,
			})
			self:_removeHandle(handle)
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
		self:_disconnectHandleConnections(handle)
		self:_setHandleOwner(handle, nil, nil, {
			updateController = false,
		})
	end
	table.clear(self.controllersBySeat)
	table.clear(self.activeCabsByUserId)
	table.clear(self.handleByCar)
	table.clear(self.cabHandles)
	self.started = false
end

return TaxiService
