local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

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
			elseif item.Name == "Building" then
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

	return world, driveSurfaces, crashObstacles, {
		position = Config.carSpawn,
		yaw = 0,
	}
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
	})
	taxiService:start()

	local debugTuningService = DebugTuningService.new({
		config = Config,
		remote = remotes.debugTune,
	})
	local passengerService = nil
	debugTuningService:onChanged(function(key, value)
		taxiService:applyLiveTuning(key, value)
		if passengerService and passengerService.applyLiveTuning then
			passengerService.applyLiveTuning(key)
		end
	end)
	debugTuningService:start()

	local initialPlayer = Players:GetPlayers()[1]
	local playerCab = nil
	if initialPlayer then
		playerCab = taxiService:spawnCabForPlayer(initialPlayer, Config.carDefaultProfileName, spawnPose, {
			world = world,
			startController = false,
		})
	else
		playerCab = taxiService:createCab({
			world = world,
			spawnPose = spawnPose,
			profileName = Config.carDefaultProfileName,
		})
	end
	local car = playerCab.car
	local gpsService = GpsService.start({
		world = world,
		car = car,
		driveSurfaces = driveSurfaces,
	})
	local shiftService = startShiftService(remotes, stateReplicator, economyService)
	local fareService = FareService.new({
		config = Config,
		car = car,
		shiftService = shiftService,
		ownerUserId = playerCab.ownerUserId,
	})
	if shiftService and shiftService.onPhaseChanged then
		shiftService:onPhaseChanged(function(snapshot)
			if fareService and fareService.onShiftPhaseChanged then
				fareService:onShiftPhaseChanged(snapshot and snapshot.phase)
			end
		end)
	end

	taxiService:startCabController(playerCab, {
		spawnPose = playerCab.spawnPose or spawnPose,
		driverMode = "Player",
		fareService = fareService,
		ownerPlayer = playerCab.ownerPlayer,
		ownerUserId = playerCab.ownerUserId,
	})

	passengerService = PassengerService.start({
		world = world,
		car = car,
		driveSurfaces = driveSurfaces,
		spawnPose = spawnPose,
		gpsService = gpsService,
		fareService = fareService,
		stateReplicator = stateReplicator,
	})
end

local ok, err = xpcall(bootstrap, debug.traceback)
if not ok then
	warn("[cab87] Server bootstrap failed: " .. tostring(err))
	error(err)
end
