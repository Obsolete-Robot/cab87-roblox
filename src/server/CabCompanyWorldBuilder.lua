local CabCompanyWorldBuilder = {}

local DEFAULT_CAB_SPAWN_OFFSET = Vector3.new(0, 0, 75)
local DEFAULT_SERVICE_OFFSET = Vector3.new(50, 0, 40)

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

local function setVectorAttributes(instance, prefix, value)
	instance:SetAttribute(prefix .. "X", value.X)
	instance:SetAttribute(prefix .. "Y", value.Y)
	instance:SetAttribute(prefix .. "Z", value.Z)
end

local function distanceXZ(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function clearGeneratedObstaclesNear(world, center, radius)
	if radius <= 0 then
		return
	end

	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant:IsA("BasePart")
			and (descendant.Name == "Building" or descendant:GetAttribute("CrashObstacle") == true)
			and distanceXZ(descendant.Position, center) <= radius
		then
			descendant:Destroy()
		end
	end
end

local function makeMarker(parent, props, attributes)
	local marker = makePart(parent, props)
	marker.CanCollide = false
	marker.CanTouch = false
	for key, value in pairs(attributes or {}) do
		marker:SetAttribute(key, value)
	end
	return marker
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

	local refuelYaw = options.refuelYaw or spawnYaw
	local refuelPosition = options.refuelPosition
	local refuelGround = cabSpawnGround
	local refuelMarkerPosition = nil
	if typeof(refuelPosition) == "Vector3" then
		refuelGround = Vector3.new(refuelPosition.X, groundY, refuelPosition.Z)
		refuelMarkerPosition = Vector3.new(refuelPosition.X, groundY + 0.35, refuelPosition.Z)
	end

	local serviceYaw = options.serviceYaw or spawnYaw
	local servicePosition = options.servicePosition
	local serviceGround
	local serviceMarkerPosition
	if typeof(servicePosition) == "Vector3" then
		serviceGround = Vector3.new(servicePosition.X, groundY, servicePosition.Z)
		serviceMarkerPosition = Vector3.new(servicePosition.X, groundY + 0.35, servicePosition.Z)
	else
		local serviceOffset = getVector3(config, "cabCompanyServiceOffset", DEFAULT_SERVICE_OFFSET)
		serviceMarkerPosition = localPoint(serviceOffset) + Vector3.new(0, 0.35, 0)
		serviceGround = Vector3.new(serviceMarkerPosition.X, groundY, serviceMarkerPosition.Z)
	end

	local existingRoot = world:FindFirstChild("CabCompany")
	if existingRoot then
		existingRoot:Destroy()
	end

	local clearRadius = math.max(getNumber(config, "cabCompanyMarkerClearRadius", 80), 0)
	clearGeneratedObstaclesNear(world, cabSpawnGround, clearRadius)
	clearGeneratedObstaclesNear(world, refuelGround, clearRadius)
	if serviceGround then
		clearGeneratedObstaclesNear(world, serviceGround, clearRadius)
	end

	local cabCompanyRoot = Instance.new("Folder")
	cabCompanyRoot.Name = "CabCompany"
	cabCompanyRoot.Parent = world

	local markersFolder = Instance.new("Folder")
	markersFolder.Name = "Markers"
	markersFolder.Parent = cabCompanyRoot

	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "Spawn"
	spawnFolder.Parent = cabCompanyRoot

	local spawnPoint = makeMarker(spawnFolder, {
		Name = "CabSpawnPoint",
		Size = Vector3.new(14, 0.35, 14),
		CFrame = makeYawCFrame(cabSpawnPosition - Vector3.new(0, 1.5, 0), spawnYaw),
		Color = Color3.fromRGB(255, 205, 69),
		Material = Enum.Material.Neon,
	}, {
		Cab87MarkerType = "CabCompany",
		Cab87MarkerDescription = "Cab spawn and fallback cab depot marker",
	})

	if refuelMarkerPosition then
		makeMarker(markersFolder, {
			Name = "CabRefuelPoint",
			Size = Vector3.new(12, 0.35, 12),
			CFrame = makeYawCFrame(refuelMarkerPosition, refuelYaw),
			Color = Color3.fromRGB(95, 255, 160),
			Material = Enum.Material.Neon,
		}, {
			Cab87MarkerType = "CabRefuel",
			Cab87MarkerDescription = "Free refuel marker",
			StationId = "cab-company",
			RefuelMode = "cab_company",
			DisplayName = "Cab Depot",
		})
	end

	makeMarker(markersFolder, {
		Name = "CabServicePoint",
		Size = Vector3.new(12, 0.35, 12),
		CFrame = makeYawCFrame(serviceMarkerPosition, serviceYaw),
		Color = Color3.fromRGB(116, 209, 255),
		Material = Enum.Material.Neon,
	}, {
		Cab87MarkerType = "CabService",
		Cab87MarkerDescription = "Cab recover and garage/shop marker",
	})

	local playerSpawnOffset = getVector3(config, "cabCompanyPlayerSpawnOffset", Vector3.new(-26, 1, 36))
	local playerSpawnYaw = options.playerSpawnYaw or getNumber(config, "cabCompanyPlayerSpawnYaw", spawnYaw)
	local playerSpawnPosition = options.playerSpawnPosition
	local playerSpawnMarkerPosition
	local hasPlayerSpawnMarker = typeof(playerSpawnPosition) == "Vector3"
	if typeof(playerSpawnPosition) == "Vector3" then
		playerSpawnMarkerPosition = playerSpawnPosition
	else
		playerSpawnMarkerPosition = localPoint(playerSpawnOffset)
		playerSpawnPosition = playerSpawnMarkerPosition + Vector3.new(0, 3, 0)
	end

	if hasPlayerSpawnMarker then
		makeMarker(spawnFolder, {
			Name = "PlayerSpawnPoint",
			Size = Vector3.new(8, 0.35, 8),
			CFrame = makeYawCFrame(playerSpawnMarkerPosition, playerSpawnYaw),
			Color = Color3.fromRGB(115, 214, 255),
			Material = Enum.Material.Neon,
		}, {
			Cab87MarkerType = "PlayerSpawn",
			PlayerSpawn = true,
			Cab87MarkerDescription = "Player spawn marker",
		})
	end

	world:SetAttribute("CabCompanySpawnX", cabSpawnPosition.X)
	world:SetAttribute("CabCompanySpawnY", cabSpawnPosition.Y)
	world:SetAttribute("CabCompanySpawnZ", cabSpawnPosition.Z)
	world:SetAttribute("CabCompanySpawnYaw", spawnYaw)
	world:SetAttribute("CabCompanyPlayerSpawnX", playerSpawnPosition.X)
	world:SetAttribute("CabCompanyPlayerSpawnY", playerSpawnPosition.Y)
	world:SetAttribute("CabCompanyPlayerSpawnZ", playerSpawnPosition.Z)
	world:SetAttribute("CabCompanyPlayerSpawnYaw", playerSpawnYaw)
	world:SetAttribute("CabCompanyRefuelX", refuelGround.X)
	world:SetAttribute("CabCompanyRefuelY", refuelGround.Y)
	world:SetAttribute("CabCompanyRefuelZ", refuelGround.Z)
	setVectorAttributes(world, "CabCompanyCenter", refuelGround)

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
		refuelPosition = refuelGround,
		driveSurfaces = driveSurfaces,
		crashObstacles = crashObstacles,
	}

	appendAll(result.driveSurfaces, options.extraDriveSurfaces)
	appendAll(result.crashObstacles, options.extraCrashObstacles)

	return result
end

CabCompanyWorldBuilder.yawFromCFrame = yawFromCFrame

return CabCompanyWorldBuilder
