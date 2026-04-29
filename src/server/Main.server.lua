local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GameManagerSettings = require(Shared:WaitForChild("GameManagerSettings"))
local VehicleCatalog = require(Shared:WaitForChild("VehicleCatalog"))

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
local FuelService = require(servicesFolder:WaitForChild("FuelService"))
local GameplayStateReplicator = require(servicesFolder:WaitForChild("GameplayStateReplicator"))
local PersistenceService = require(servicesFolder:WaitForChild("PersistenceService"))
local ShiftService = require(servicesFolder:WaitForChild("ShiftService"))
local TaxiService = require(servicesFolder:WaitForChild("TaxiService"))
local VehicleInventoryService = require(servicesFolder:WaitForChild("VehicleInventoryService"))

local function yawToForward(yaw)
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

local function cframeFromPose(pose)
	local yaw = (pose and pose.yaw) or 0
	local position = pose and pose.position
	if typeof(position) ~= "Vector3" then
		position = Config.carSpawn
	end

	return CFrame.lookAt(position, position + yawToForward(yaw))
end

local function yawFromCFrame(cframe)
	local look = cframe.LookVector
	local horizontal = Vector3.new(look.X, 0, look.Z)
	if horizontal.Magnitude <= 0.001 then
		return 0
	end

	local unit = horizontal.Unit
	return math.atan2(unit.X, unit.Z)
end

local function resolvePlayerSpawnPose(world, fallbackPose)
	local cabCompanyRoot = world and world:FindFirstChild("CabCompany")
	local spawnFolder = cabCompanyRoot and cabCompanyRoot:FindFirstChild("Spawn")
	local spawnPart = spawnFolder and spawnFolder:FindFirstChild("PlayerSpawnPoint")
	if spawnPart and spawnPart:IsA("BasePart") then
		return {
			position = spawnPart.Position + Vector3.new(0, 3, 0),
			yaw = yawFromCFrame(spawnPart.CFrame),
		}
	end

	local x = world and world:GetAttribute("CabCompanyPlayerSpawnX")
	local y = world and world:GetAttribute("CabCompanyPlayerSpawnY")
	local z = world and world:GetAttribute("CabCompanyPlayerSpawnZ")
	local yaw = world and world:GetAttribute("CabCompanyPlayerSpawnYaw")
	if type(x) == "number" and type(y) == "number" and type(z) == "number" then
		return {
			position = Vector3.new(x, y, z),
			yaw = type(yaw) == "number" and yaw or 0,
		}
	end

	return {
		position = (fallbackPose and fallbackPose.position or Config.carSpawn) + Vector3.new(0, 3, 0),
		yaw = (fallbackPose and fallbackPose.yaw) or 0,
	}
end

local function placeCharacterAtSpawn(player, character, spawnPose)
	if not (player and character and spawnPose) then
		return
	end

	task.defer(function()
		local rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
		if not rootPart then
			return
		end
		if player.Character ~= character or not character.Parent then
			return
		end

		character:PivotTo(cframeFromPose(spawnPose))
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end)
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

local function buildRefuelStations(world)
	local stations = Config.fuelStations or {}
	if #stations == 0 then
		return
	end

	local root = world:FindFirstChild("RefuelStations")
	if root and not root:IsA("Folder") then
		root:Destroy()
		root = nil
	end
	if not root then
		root = Instance.new("Folder")
		root.Name = "RefuelStations"
		root.Parent = world
	end

	local function getCabCompanyStationPosition(station)
		if station.kind ~= "cab_company" then
			return station.position
		end

		local x = world:GetAttribute("CabCompanyRefuelX")
		local y = world:GetAttribute("CabCompanyRefuelY")
		local z = world:GetAttribute("CabCompanyRefuelZ")
		if type(x) == "number" and type(y) == "number" and type(z) == "number" then
			return Vector3.new(x, y, z)
		end

		local spawnX = world:GetAttribute("CabCompanySpawnX")
		local spawnY = world:GetAttribute("CabCompanySpawnY")
		local spawnZ = world:GetAttribute("CabCompanySpawnZ")
		if type(spawnX) == "number" and type(spawnY) == "number" and type(spawnZ) == "number" then
			return Vector3.new(spawnX, spawnY, spawnZ)
		end

		return station.position
	end

	local function getCabCompanyStationMarker()
		local cabCompanyRoot = world:FindFirstChild("CabCompany")
		local markersFolder = cabCompanyRoot and cabCompanyRoot:FindFirstChild("Markers")
		local refuelMarker = markersFolder and markersFolder:FindFirstChild("CabRefuelPoint")
		if refuelMarker and refuelMarker:IsA("BasePart") then
			return refuelMarker
		end

		local spawnFolder = cabCompanyRoot and cabCompanyRoot:FindFirstChild("Spawn")
		local marker = spawnFolder and spawnFolder:FindFirstChild("CabSpawnPoint")
		if marker and marker:IsA("BasePart") then
			return marker
		end

		return nil
	end

	local function setStationAttributes(marker, station, stationPosition)
		marker:SetAttribute("StationId", station.id)
		marker:SetAttribute("RefuelMode", station.kind == "cab_company" and "cab_company" or "paid")
		marker:SetAttribute("DisplayName", station.name or station.id)
		marker:SetAttribute("StationX", stationPosition.X)
		marker:SetAttribute("StationY", stationPosition.Y)
		marker:SetAttribute("StationZ", stationPosition.Z)
	end

	for _, station in ipairs(stations) do
		local stationPosition = type(station) == "table" and getCabCompanyStationPosition(station) or nil
		if type(station) == "table"
			and typeof(stationPosition) == "Vector3"
			and type(station.id) == "string"
			and station.id ~= ""
		then
			local cabCompanyMarker = station.kind == "cab_company" and getCabCompanyStationMarker() or nil
			if cabCompanyMarker then
				local duplicate = root:FindFirstChild(station.id)
				if duplicate then
					duplicate:Destroy()
				end
				setStationAttributes(cabCompanyMarker, station, stationPosition)
			else
				local marker = root:FindFirstChild(station.id)
				if marker and not marker:IsA("Part") then
					marker:Destroy()
					marker = nil
				end
				if not marker then
					marker = Instance.new("Part")
					marker.Name = station.id
					marker.Parent = root
				end

				local radius = station.kind == "cab_company" and Config.fuelCabCompanyStationRadius or Config.fuelRefuelStationRadius
				marker.Anchored = true
				marker.CanCollide = false
				marker.Shape = Enum.PartType.Cylinder
				marker.Size = Vector3.new(radius * 2, 0.4, radius * 2)
				marker.CFrame = CFrame.new(stationPosition + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
				marker.Transparency = 0.45
				marker.Material = Enum.Material.Neon
				marker.Color = station.kind == "cab_company" and Color3.fromRGB(95, 255, 160) or Color3.fromRGB(91, 169, 255)
				setStationAttributes(marker, station, stationPosition)
			end
		end
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
	world:SetAttribute("Source", "Procedural")
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

local function createBlankWorld()
	authoredRoadStartupLog("creating blank runtime world; procedural fallback is disabled")
	local oldWorld = Workspace:FindFirstChild("Cab87World")
	if oldWorld then
		oldWorld:Destroy()
	end

	local world = Instance.new("Model")
	world.Name = "Cab87World"
	world:SetAttribute("GeneratorVersion", "blank")
	world:SetAttribute("Source", "Blank")
	world:SetAttribute("ProceduralWorldEnabled", false)
	world:SetAttribute("NeedsClientRoadMesh", false)
	world.Parent = Workspace

	return world, {}, {}, {
		position = Config.carSpawn,
		yaw = 0,
	}
end

local function createRuntimeWorld(gameSettings)
	local proceduralWorldEnabled = GameManagerSettings.isEnabled(gameSettings, "ProceduralWorldEnabled")
	local manager = GameManagerSettings.getManager(Workspace)
	Workspace:SetAttribute("Cab87ManagerFound", manager ~= nil)
	Workspace:SetAttribute("Cab87ManagerClassName", manager and manager.ClassName or "")
	Workspace:SetAttribute("Cab87ProceduralWorldEnabled", proceduralWorldEnabled)
	local authoredRoadRoot = AuthoredRoadRuntime.getRoot()
	authoredRoadStartupLog(
		"startup: useAuthoredRoadEditorWorld=%s proceduralWorldEnabled=%s root=%s",
		tostring(Config.useAuthoredRoadEditorWorld == true),
		tostring(proceduralWorldEnabled == true),
		authoredRoadRoot and authoredRoadRoot:GetFullName() or "nil"
	)

	local okHasAuthoredRoad, hasAuthoredRoad = pcall(function()
		return AuthoredRoadRuntime.hasRoadData(authoredRoadRoot)
	end)
	if not okHasAuthoredRoad then
		warn("[cab87] Authored road data check failed: " .. tostring(hasAuthoredRoad))
		hasAuthoredRoad = false
	end
	Workspace:SetAttribute("Cab87AuthoredRoadDetected", hasAuthoredRoad == true)
	authoredRoadStartupLog("hasAuthoredRoad=%s", tostring(hasAuthoredRoad == true))

	if not hasAuthoredRoad then
		if proceduralWorldEnabled then
			Workspace:SetAttribute("Cab87RuntimeWorldSource", "ProceduralFallbackNoAuthoredRoad")
			return createGeneratedWorld()
		end

		warn("[cab87] No authored road data found and procedural world generation is disabled.")
		Workspace:SetAttribute("Cab87RuntimeWorldSource", "BlankNoAuthoredRoad")
		return createBlankWorld()
	end

	authoredRoadStartupLog("creating authored road world")
	local okWorld, world, driveSurfaces, crashObstacles, spawnPose = pcall(function()
		return AuthoredRoadRuntime.createWorld(authoredRoadRoot)
	end)
	if okWorld and world then
		Workspace:SetAttribute("Cab87RuntimeWorldSource", tostring(world:GetAttribute("AuthoredRoadFormat") or "AuthoredRoad"))
		authoredRoadStartupLog(
			"authored road world active: driveSurfaces=%d spawn=(%.1f, %.1f, %.1f)",
			#(driveSurfaces or {}),
			spawnPose.position.X,
			spawnPose.position.Y,
			spawnPose.position.Z
		)
		return world, driveSurfaces, crashObstacles, spawnPose
	end

	if proceduralWorldEnabled then
		warn("[cab87] Authored road world failed; using generated map so the taxi can spawn: " .. tostring(world))
		Workspace:SetAttribute("Cab87RuntimeWorldSource", "ProceduralFallbackAuthoredRoadFailed")
		return createGeneratedWorld()
	end

	warn("[cab87] Authored road world failed and procedural world generation is disabled: " .. tostring(world))
	Workspace:SetAttribute("Cab87RuntimeWorldSource", "BlankAuthoredRoadFailed")
	return createBlankWorld()
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

local function getCabConfigOverrides(gameSettings)
	if GameManagerSettings.getCabVisualStyle(gameSettings) == "Blocky" then
		return {
			carForceProceduralVisual = true,
		}
	end

	return nil
end

local function bootstrap()
	local gameSettings = GameManagerSettings.readWorkspaceSettings(Workspace)
	GameManagerSettings.ensureRuntimeSettings(ReplicatedStorage, gameSettings)

	local passengersEnabled = GameManagerSettings.isEnabled(gameSettings, "PassengersEnabled")
	local shiftEnabled = GameManagerSettings.isEnabled(gameSettings, "ShiftEnabled")
	local cabConfigOverrides = getCabConfigOverrides(gameSettings)

	local remotes = RemoteRegistry.ensure({
		config = Config,
	})
	local stateReplicator = GameplayStateReplicator.new({
		config = Config,
		remotes = remotes,
	})
	local world, driveSurfaces, crashObstacles, spawnPose = createRuntimeWorld(gameSettings)
	buildRefuelStations(world)
	local persistenceService = PersistenceService.new({
		config = Config,
		vehicleCatalog = VehicleCatalog,
	})
	persistenceService:start()

	local economyService = EconomyService.new({
		config = Config,
		persistenceService = persistenceService,
	})
	economyService:start()

	local vehicleInventoryService = VehicleInventoryService.new({
		config = Config,
		remotes = remotes,
		vehicleCatalog = VehicleCatalog,
		economyService = economyService,
		persistenceService = persistenceService,
	})
	vehicleInventoryService:start()

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

	local fuelService = FuelService.new({
		config = Config,
		economyService = economyService,
		taxiService = taxiService,
		world = world,
		remote = remotes.requestRefuel,
		stateRemote = remotes.fuelStateUpdated,
	})
	fuelService:start()

	local shiftService = if shiftEnabled then startShiftService(remotes, stateReplicator, economyService) else nil
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

		local gpsService = nil
		if passengersEnabled then
			gpsService = GpsService.start({
				world = world,
				car = handle.car,
				driveSurfaces = driveSurfaces,
			})
		end
		local fareService = FareService.new({
			config = Config,
			car = handle.car,
			shiftService = shiftService,
			economyService = economyService,
			freeplayPayoutsEnabled = not shiftEnabled,
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

		local passengerService = nil
		if passengersEnabled then
			passengerService = PassengerService.start({
				world = world,
				car = handle.car,
				driveSurfaces = driveSurfaces,
				spawnPose = handle.spawnPose or runtimeSpawnPose or spawnPose,
				gpsService = gpsService,
				fareService = fareService,
				stateReplicator = stateReplicator,
			})
		end

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
		vehicleInventoryService = vehicleInventoryService,
		cabConfigOverrides = cabConfigOverrides,
		shopPromptEnabled = GameManagerSettings.isEnabled(gameSettings, "UiGarageShopEnabled"),
		onCabReady = function(handle, request)
			startCabRuntime(handle, request and request.spawnPose or spawnPose)
		end,
	})
	cabCompanyService:start()
	vehicleInventoryService:setShopAccessValidator(function(player)
		return cabCompanyService:isShopEligible(player)
	end)

	if Config.playerUseCabCompanySpawn == true then
		local playerSpawnPose = resolvePlayerSpawnPose(world, spawnPose)
		Players.PlayerAdded:Connect(function(player)
			player.CharacterAdded:Connect(function(character)
				placeCharacterAtSpawn(player, character, playerSpawnPose)
			end)
			if player.Character then
				placeCharacterAtSpawn(player, player.Character, playerSpawnPose)
			end
		end)
		for _, player in ipairs(Players:GetPlayers()) do
			player.CharacterAdded:Connect(function(character)
				placeCharacterAtSpawn(player, character, playerSpawnPose)
			end)
			if player.Character then
				placeCharacterAtSpawn(player, player.Character, playerSpawnPose)
			end
		end
	end

	local starterCab = taxiService:spawnCab({
		taxiId = Config.carDefaultTaxiId,
		spawnPose = spawnPose,
		world = world,
		configOverrides = cabConfigOverrides,
	})
	startCabRuntime(starterCab, spawnPose)
end

local ok, err = xpcall(bootstrap, debug.traceback)
if not ok then
	warn("[cab87] Server bootstrap failed: " .. tostring(err))
	error(err)
end
