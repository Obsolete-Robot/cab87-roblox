local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local VehicleCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VehicleCatalog"))

local serverRoot = script.Parent
local runtimeFolder = serverRoot:WaitForChild("Runtime")
local servicesFolder = serverRoot:WaitForChild("Services")
local factoriesFolder = serverRoot:WaitForChild("Factories")

local AuthoredRoadRuntime = require(serverRoot:WaitForChild("AuthoredRoadRuntime"))
local GpsService = require(serverRoot:WaitForChild("GpsService"))
local MapGenerator = require(serverRoot:WaitForChild("MapGenerator"))
local PassengerService = require(serverRoot:WaitForChild("PassengerService"))
local RemoteRegistry = require(runtimeFolder:WaitForChild("RemoteRegistry"))
local CabFactory = require(factoriesFolder:WaitForChild("CabFactory"))
local CabCompanyService = require(servicesFolder:WaitForChild("CabCompanyService"))
local DebugTuningService = require(servicesFolder:WaitForChild("DebugTuningService"))
local EconomyService = require(servicesFolder:WaitForChild("EconomyService"))
local FareService = require(servicesFolder:WaitForChild("FareService"))
local GameplayStateReplicator = require(servicesFolder:WaitForChild("GameplayStateReplicator"))
local ShiftService = require(servicesFolder:WaitForChild("ShiftService"))
local TaxiService = require(servicesFolder:WaitForChild("TaxiService"))

local function yawToForward(yaw)
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

local function makePart(parent, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local function trackPart(list, part)
	table.insert(list, part)
	return part
end

local function makeRamp(parent, basePosition, yaw)
	local pitch = math.atan2(Config.rampHeight, Config.rampRun)
	local slopeLength = math.sqrt(Config.rampRun * Config.rampRun + Config.rampHeight * Config.rampHeight)
	local forward = yawToForward(yaw)
	local centerXZ = basePosition + forward * (Config.rampRun * 0.5)
	local centerY = Config.roadSurfaceY - (Config.rampThickness * 0.5 * math.cos(pitch))
		+ Config.rampHeight * 0.5

	return makePart(parent, {
		Name = "JumpRamp",
		Size = Vector3.new(Config.rampWidth, Config.rampThickness, slopeLength),
		CFrame = CFrame.new(Vector3.new(centerXZ.X, centerY, centerXZ.Z))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(-pitch, 0, 0),
		Color = Color3.fromRGB(238, 177, 46),
		Material = Enum.Material.Metal,
	})
end

local function makeLandingPlatform(parent, basePosition, yaw)
	local forward = yawToForward(yaw)
	local centerXZ = basePosition + forward * (Config.rampRun + Config.stuntPlatformGap)
	local thickness = 2
	local topY = Config.roadSurfaceY + Config.stuntPlatformHeight

	return makePart(parent, {
		Name = "LandingPad",
		Size = Vector3.new(Config.stuntPlatformWidth, thickness, Config.stuntPlatformLength),
		CFrame = CFrame.new(Vector3.new(centerXZ.X, topY - thickness * 0.5, centerXZ.Z))
			* CFrame.Angles(0, yaw, 0),
		Color = Color3.fromRGB(67, 78, 89),
		Material = Enum.Material.Concrete,
	})
end

local function buildStuntFeatures(world, driveSurfaces)
	local laneOffset = Config.roadWidth * 0.25
	local features = {
		{ base = Vector3.new(-laneOffset, 0, -Config.blockSize * 2), yaw = 0 },
		{ base = Vector3.new(laneOffset, 0, Config.blockSize * 2), yaw = math.pi },
		{ base = Vector3.new(-Config.blockSize * 2, 0, laneOffset), yaw = math.pi * 0.5 },
		{ base = Vector3.new(Config.blockSize * 2, 0, -laneOffset), yaw = -math.pi * 0.5 },
	}

	for _, feature in ipairs(features) do
		trackPart(driveSurfaces, makeRamp(world, feature.base, feature.yaw))
		trackPart(driveSurfaces, makeLandingPlatform(world, feature.base, feature.yaw))
	end
end

local function collectWorldParts(world)
	local driveSurfaces = {}
	local crashObstacles = {}

	for _, item in ipairs(world:GetDescendants()) do
		if item:IsA("BasePart") then
			if item:GetAttribute("DriveSurface") == true
				or item.Name == "Ground"
				or item.Name == "Road_NS"
				or item.Name == "Road_EW"
			then
				table.insert(driveSurfaces, item)
			elseif item.Name == "Building" or item:GetAttribute("CrashObstacle") == true then
				table.insert(crashObstacles, item)
			end
		end
	end

	return driveSurfaces, crashObstacles
end

local function authoredRoadStartupLog(message, ...)
	if Config.authoredRoadDebugLogging == true then
		local ok, formatted = pcall(string.format, tostring(message), ...)
		print("[cab87 roads server] " .. (ok and formatted or tostring(message)))
	end
end

local function createGeneratedWorld()
	authoredRoadStartupLog("creating generated fallback world")
	local world = MapGenerator.Generate()
	local driveSurfaces, crashObstacles = collectWorldParts(world)
	buildStuntFeatures(world, driveSurfaces)

	local spawnPose = {
		position = Config.carSpawn,
		yaw = 0,
	}
	local spawnX = world:GetAttribute("CabCompanySpawnX")
	local spawnY = world:GetAttribute("CabCompanySpawnY")
	local spawnZ = world:GetAttribute("CabCompanySpawnZ")
	local spawnYaw = world:GetAttribute("CabCompanySpawnYaw")
	if type(spawnX) == "number" and type(spawnY) == "number" and type(spawnZ) == "number" then
		spawnPose.position = Vector3.new(spawnX, spawnY, spawnZ)
		spawnPose.yaw = type(spawnYaw) == "number" and spawnYaw or 0
	end

	return world, driveSurfaces, crashObstacles, spawnPose
end

local function createRuntimeWorld()
	local authoredRoadRoot = AuthoredRoadRuntime.getRoot()
	authoredRoadStartupLog(
		"startup: useAuthoredRoadEditorWorld=%s root=%s",
		tostring(Config.useAuthoredRoadEditorWorld == true),
		authoredRoadRoot and authoredRoadRoot:GetFullName() or "nil"
	)

	local okHasAuthoredRoad, hasAuthoredRoad = pcall(function()
		return AuthoredRoadRuntime.hasRoadData(authoredRoadRoot)
	end)
	if not okHasAuthoredRoad then
		warn("[cab87] Authored road data check failed; using generated map: " .. tostring(hasAuthoredRoad))
		hasAuthoredRoad = false
	end
	authoredRoadStartupLog("hasAuthoredRoad=%s", tostring(hasAuthoredRoad == true))

	if not hasAuthoredRoad then
		return createGeneratedWorld()
	end

	authoredRoadStartupLog("creating authored road world")
	local okWorld, world, driveSurfaces, crashObstacles, spawnPose = pcall(function()
		return AuthoredRoadRuntime.createWorld(authoredRoadRoot)
	end)
	if okWorld and world then
		authoredRoadStartupLog(
			"authored road world active: driveSurfaces=%d spawn=(%.1f, %.1f, %.1f)",
			#(driveSurfaces or {}),
			spawnPose.position.X,
			spawnPose.position.Y,
			spawnPose.position.Z
		)
		return world, driveSurfaces, crashObstacles, spawnPose
	end

	warn("[cab87] Authored road world failed; using generated map so the taxi can spawn: " .. tostring(world))
	return createGeneratedWorld()
end

local function startShiftService(remotes, stateReplicator, economyService)
	local shiftService = ShiftService.new({
		config = Config,
		remotes = remotes,
		stateReplicator = stateReplicator,
		economyService = economyService,
	})
	shiftService:start()
	return shiftService
end

local function bootstrap()
	local remotes = RemoteRegistry.ensure({
		config = Config,
	})
	local stateReplicator = GameplayStateReplicator.new({
		config = Config,
		remotes = remotes,
	})
	local world, driveSurfaces, crashObstacles, spawnPose = createRuntimeWorld()
	local economyService = EconomyService.new({
		config = Config,
	})
	economyService:start()

	local cabFactory = CabFactory.new({
		config = Config,
	})
	local taxiService = TaxiService.new({
		config = Config,
		cabFactory = cabFactory,
		remotes = remotes,
		world = world,
		driveSurfaces = driveSurfaces,
		crashObstacles = crashObstacles,
		destroyOwnedCabsOnPlayerRemoving = true,
		stopReleasedControllersOnPlayerRemoving = true,
	})
	taxiService:start()

	local shiftService = startShiftService(remotes, stateReplicator, economyService)
	local activeCabRuntime = nil
	local activePassengerService = nil
	local activeFareService = nil

	if shiftService and shiftService.onPhaseChanged then
		shiftService:onPhaseChanged(function(snapshot)
			if activeFareService and activeFareService.onShiftPhaseChanged then
				activeFareService:onShiftPhaseChanged(snapshot and snapshot.phase)
			end
		end)
	end

	local function stopActiveCabRuntime()
		local runtime = activeCabRuntime
		if not runtime then
			return
		end

		activeCabRuntime = nil
		activePassengerService = nil
		activeFareService = nil

		if runtime.destroyConnection then
			runtime.destroyConnection:Disconnect()
		end

		if runtime.passengerService and runtime.passengerService.stop then
			runtime.passengerService.stop()
		end

		if runtime.gpsService and runtime.gpsService.stop then
			runtime.gpsService:stop()
		end
	end

	local function startCabRuntime(handle, runtimeSpawnPose)
		if not (handle and handle.car and handle.car.Parent) then
			return nil
		end

		if activeCabRuntime and activeCabRuntime.handle == handle then
			return activeCabRuntime
		end

		stopActiveCabRuntime()

		local gpsService = GpsService.start({
			world = world,
			car = handle.car,
			driveSurfaces = driveSurfaces,
		})
		local fareService = FareService.new({
			config = Config,
			car = handle.car,
			shiftService = shiftService,
			ownerPlayer = handle.ownerPlayer,
			ownerUserId = handle.ownerUserId,
		})

		if handle.controller and handle.controller.setFareService then
			handle.controller:setFareService(fareService)
		end

		taxiService:startCabController(handle, {
			spawnPose = handle.spawnPose or runtimeSpawnPose or spawnPose,
			driverMode = "Player",
			fareService = fareService,
			ownerPlayer = handle.ownerPlayer,
			ownerUserId = handle.ownerUserId,
		})

		local passengerService = PassengerService.start({
			world = world,
			car = handle.car,
			driveSurfaces = driveSurfaces,
			spawnPose = handle.spawnPose or runtimeSpawnPose or spawnPose,
			gpsService = gpsService,
			fareService = fareService,
			stateReplicator = stateReplicator,
		})

		local runtime = {
			handle = handle,
			gpsService = gpsService,
			fareService = fareService,
			passengerService = passengerService,
			destroyConnection = nil,
		}
		runtime.destroyConnection = handle.car.Destroying:Connect(function()
			if activeCabRuntime == runtime then
				stopActiveCabRuntime()
			end
		end)

		activeCabRuntime = runtime
		activePassengerService = passengerService
		activeFareService = fareService

		return runtime
	end

	local debugTuningService = DebugTuningService.new({
		config = Config,
		remote = remotes.debugTune,
	})
	debugTuningService:onChanged(function(key, value)
		taxiService:applyLiveTuning(key, value)
		if activePassengerService and activePassengerService.applyLiveTuning then
			activePassengerService.applyLiveTuning(key)
		end
	end)
	debugTuningService:start()

	local cabCompanyService = CabCompanyService.new({
		config = Config,
		remotes = remotes,
		world = world,
		taxiService = taxiService,
		vehicleCatalog = VehicleCatalog,
		onCabReady = function(handle, request)
			startCabRuntime(handle, request and request.spawnPose or spawnPose)
		end,
	})
	cabCompanyService:start()

	local initialPlayer = Players:GetPlayers()[1]
	if initialPlayer then
		local playerCab = taxiService:spawnCabForPlayer(initialPlayer, Config.carDefaultTaxiId, spawnPose, {
			world = world,
			startController = false,
		})
		startCabRuntime(playerCab, spawnPose)
	end
end

local ok, err = xpcall(bootstrap, debug.traceback)
if not ok then
	warn("[cab87] Server bootstrap failed: " .. tostring(err))
	error(err)
end
