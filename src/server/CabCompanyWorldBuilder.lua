local CabCompanyWorldBuilder = {}

local DEFAULT_CAB_SPAWN_OFFSET = Vector3.new(0, 0, 75)

local function getVector3(config, key, fallback)
	local value = config and config[key]
	if typeof(value) == "Vector3" then
		return value
	end

	return fallback
end

local function getNumber(config, key, fallback)
	local value = config and config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
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

local function rotationForYaw(yaw)
	return CFrame.Angles(0, yaw or 0, 0)
end

local function rotateOffset(offset, yaw)
	return rotationForYaw(yaw):VectorToWorldSpace(offset)
end

local function makeYawCFrame(position, yaw)
	return CFrame.new(position) * rotationForYaw(yaw)
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

local function addZone(parent, zoneName, center, size, yaw, color)
	local zone = makePart(parent, {
		Name = zoneName,
		Size = size,
		CFrame = makeYawCFrame(center, yaw),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
		CanTouch = false,
	})
	zone:SetAttribute("ServiceZone", true)
	zone:SetAttribute("ZoneType", zoneName)
	return zone
end

local function setVectorAttributes(instance, prefix, value)
	instance:SetAttribute(prefix .. "X", value.X)
	instance:SetAttribute(prefix .. "Y", value.Y)
	instance:SetAttribute(prefix .. "Z", value.Z)
end

local function appendAll(target, source)
	for _, item in ipairs(source or {}) do
		table.insert(target, item)
	end
end

function CabCompanyWorldBuilder.create(world, config, options)
	assert(world, "CabCompanyWorldBuilder.create requires a world")
	config = config or {}
	options = options or {}

	local driveSurfaces = {}
	local crashObstacles = {}
	local rideHeight = getNumber(config, "carRideHeight", 2.3)
	local spawnYaw = options.cabSpawnYaw or getNumber(config, "cabCompanySpawnYaw", 0)
	local center = options.center or getVector3(config, "cabCompanyCenter", Vector3.new(0, getNumber(config, "roadSurfaceY", 0), -960))
	local groundY = if type(options.groundY) == "number" then options.groundY else center.Y
	local cabSpawnOffset = getVector3(config, "cabCompanyCabSpawnOffset", DEFAULT_CAB_SPAWN_OFFSET)

	local cabSpawnPosition = options.cabSpawnPosition
	local cabSpawnGround
	if typeof(cabSpawnPosition) == "Vector3" then
		if type(options.groundY) ~= "number" then
			groundY = cabSpawnPosition.Y - rideHeight
		end
		cabSpawnGround = Vector3.new(cabSpawnPosition.X, groundY, cabSpawnPosition.Z)
		if not options.center then
			local rotatedOffset = rotateOffset(Vector3.new(cabSpawnOffset.X, 0, cabSpawnOffset.Z), spawnYaw)
			center = Vector3.new(cabSpawnGround.X - rotatedOffset.X, groundY, cabSpawnGround.Z - rotatedOffset.Z)
		else
			center = Vector3.new(center.X, groundY, center.Z)
		end
	else
		center = Vector3.new(center.X, groundY, center.Z)
		local rotatedOffset = rotateOffset(Vector3.new(cabSpawnOffset.X, 0, cabSpawnOffset.Z), spawnYaw)
		cabSpawnGround = Vector3.new(center.X + rotatedOffset.X, groundY, center.Z + rotatedOffset.Z)
		cabSpawnPosition = cabSpawnGround + Vector3.new(0, rideHeight, 0)
	end

	local function localPoint(offset)
		local rotated = rotateOffset(Vector3.new(offset.X, 0, offset.Z), spawnYaw)
		return Vector3.new(center.X + rotated.X, groundY + offset.Y, center.Z + rotated.Z)
	end

	local existingRoot = world:FindFirstChild("CabCompany")
	if existingRoot then
		existingRoot:Destroy()
	end

	local cabCompanyRoot = Instance.new("Folder")
	cabCompanyRoot.Name = "CabCompany"
	cabCompanyRoot.Parent = world

	local landmarksFolder = Instance.new("Folder")
	landmarksFolder.Name = "Landmarks"
	landmarksFolder.Parent = cabCompanyRoot

	local zonesFolder = Instance.new("Folder")
	zonesFolder.Name = "ServiceZones"
	zonesFolder.Parent = cabCompanyRoot

	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "Spawn"
	spawnFolder.Parent = cabCompanyRoot

	local lotSize = getVector3(config, "cabCompanyLotSize", Vector3.new(220, 1, 220))
	local buildingSize = getVector3(config, "cabCompanyBuildingSize", Vector3.new(110, 50, 70))
	local garageSize = getVector3(config, "cabCompanyGarageSize", Vector3.new(140, 24, 60))
	local refuelIslandSize = getVector3(config, "cabCompanyRefuelIslandSize", Vector3.new(48, 8, 26))
	local freeRefuelOffset = getVector3(config, "cabCompanyFreeRefuelOffset", Vector3.new(-50, 0, 40))
	local freeRefuelGround = localPoint(Vector3.new(freeRefuelOffset.X, 0, freeRefuelOffset.Z))
	local freeRefuelCenter = freeRefuelGround + Vector3.new(0, 1, 0)

	local lot = makePart(landmarksFolder, {
		Name = "CabCompanyLot",
		Size = lotSize,
		CFrame = makeYawCFrame(Vector3.new(center.X, groundY + 0.1, center.Z), spawnYaw),
		Color = Color3.fromRGB(53, 56, 64),
		Material = Enum.Material.Asphalt,
	})
	lot:SetAttribute("DriveSurface", true)
	table.insert(driveSurfaces, lot)

	local hq = makePart(landmarksFolder, {
		Name = "CabCompanyHQ",
		Size = buildingSize,
		CFrame = makeYawCFrame(localPoint(Vector3.new(0, buildingSize.Y * 0.5, -58)), spawnYaw),
		Color = Color3.fromRGB(228, 189, 64),
		Material = Enum.Material.Concrete,
	})
	hq:SetAttribute("CrashObstacle", true)
	table.insert(crashObstacles, hq)

	local garage = makePart(landmarksFolder, {
		Name = "CabCompanyGarage",
		Size = garageSize,
		CFrame = makeYawCFrame(localPoint(Vector3.new(45, garageSize.Y * 0.5, 52)), spawnYaw),
		Color = Color3.fromRGB(66, 73, 86),
		Material = Enum.Material.Metal,
	})
	garage:SetAttribute("CrashObstacle", true)
	table.insert(crashObstacles, garage)

	local beacon = makePart(landmarksFolder, {
		Name = "CabCompanyBeacon",
		Size = Vector3.new(8, 90, 8),
		CFrame = makeYawCFrame(localPoint(Vector3.new(-72, 45, -80)), spawnYaw),
		Color = Color3.fromRGB(94, 203, 255),
		Material = Enum.Material.Neon,
	})
	beacon:SetAttribute("CrashObstacle", true)
	table.insert(crashObstacles, beacon)

	local refuelIsland = makePart(landmarksFolder, {
		Name = "CabCompanyRefuelIsland",
		Size = refuelIslandSize,
		CFrame = makeYawCFrame(
			Vector3.new(freeRefuelCenter.X, groundY + refuelIslandSize.Y * 0.5, freeRefuelCenter.Z),
			spawnYaw
		),
		Color = Color3.fromRGB(156, 171, 191),
		Material = Enum.Material.Concrete,
	})
	refuelIsland:SetAttribute("CrashObstacle", true)
	table.insert(crashObstacles, refuelIsland)

	local spawnPoint = makePart(spawnFolder, {
		Name = "CabSpawnPoint",
		Size = Vector3.new(6, 1, 6),
		CFrame = makeYawCFrame(cabSpawnPosition - Vector3.new(0, 1.5, 0), spawnYaw),
		Color = Color3.fromRGB(255, 205, 69),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	spawnPoint:SetAttribute("DriveSurface", true)
	table.insert(driveSurfaces, spawnPoint)

	local playerSpawnOffset = getVector3(config, "cabCompanyPlayerSpawnOffset", Vector3.new(-26, 1, 36))
	local playerSpawnYaw = options.playerSpawnYaw or getNumber(config, "cabCompanyPlayerSpawnYaw", spawnYaw)
	local playerSpawnPosition = options.playerSpawnPosition
	local playerSpawnMarkerPosition
	if typeof(playerSpawnPosition) == "Vector3" then
		playerSpawnMarkerPosition = playerSpawnPosition
	else
		playerSpawnMarkerPosition = localPoint(playerSpawnOffset)
		playerSpawnPosition = playerSpawnMarkerPosition + Vector3.new(0, 3, 0)
	end

	local playerSpawnPoint = makePart(spawnFolder, {
		Name = "PlayerSpawnPoint",
		Size = Vector3.new(8, 1, 8),
		CFrame = makeYawCFrame(playerSpawnMarkerPosition, playerSpawnYaw),
		Color = Color3.fromRGB(115, 214, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	playerSpawnPoint:SetAttribute("PlayerSpawn", true)

	addZone(
		zonesFolder,
		"CabPickupZone",
		localPoint(Vector3.new(0, 1, 55)),
		Vector3.new(42, 2, 30),
		spawnYaw,
		Color3.fromRGB(255, 213, 82)
	)
	addZone(
		zonesFolder,
		"GarageZone",
		localPoint(Vector3.new(45, 1, 52)),
		Vector3.new(52, 2, 40),
		spawnYaw,
		Color3.fromRGB(116, 209, 255)
	)
	addZone(
		zonesFolder,
		"FreeRefuelZone",
		freeRefuelCenter,
		Vector3.new(34, 2, 30),
		spawnYaw,
		Color3.fromRGB(113, 255, 147)
	)
	addZone(
		zonesFolder,
		"ServiceDeskZone",
		localPoint(Vector3.new(0, 1, -20)),
		Vector3.new(48, 2, 36),
		spawnYaw,
		Color3.fromRGB(234, 126, 255)
	)

	world:SetAttribute("CabCompanySpawnX", cabSpawnPosition.X)
	world:SetAttribute("CabCompanySpawnY", cabSpawnPosition.Y)
	world:SetAttribute("CabCompanySpawnZ", cabSpawnPosition.Z)
	world:SetAttribute("CabCompanySpawnYaw", spawnYaw)
	world:SetAttribute("CabCompanyPlayerSpawnX", playerSpawnPosition.X)
	world:SetAttribute("CabCompanyPlayerSpawnY", playerSpawnPosition.Y)
	world:SetAttribute("CabCompanyPlayerSpawnZ", playerSpawnPosition.Z)
	world:SetAttribute("CabCompanyPlayerSpawnYaw", playerSpawnYaw)
	world:SetAttribute("CabCompanyRefuelX", freeRefuelGround.X)
	world:SetAttribute("CabCompanyRefuelY", freeRefuelGround.Y)
	world:SetAttribute("CabCompanyRefuelZ", freeRefuelGround.Z)
	setVectorAttributes(world, "CabCompanyCenter", center)

	if options.source then
		world:SetAttribute("CabCompanySource", options.source)
	end

	local result = {
		root = cabCompanyRoot,
		spawnPose = {
			position = cabSpawnPosition,
			yaw = spawnYaw,
		},
		playerSpawnPose = {
			position = playerSpawnPosition,
			yaw = playerSpawnYaw,
		},
		refuelPosition = freeRefuelGround,
		driveSurfaces = driveSurfaces,
		crashObstacles = crashObstacles,
	}

	appendAll(result.driveSurfaces, options.extraDriveSurfaces)
	appendAll(result.crashObstacles, options.extraCrashObstacles)

	return result
end

CabCompanyWorldBuilder.yawFromCFrame = yawFromCFrame

return CabCompanyWorldBuilder
