local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadSampling = require(Shared:WaitForChild("RoadSampling"))
local RoadSplineData = require(Shared:WaitForChild("RoadSplineData"))

local MinimapController = {}

local WORLD_NAME = "Cab87World"
local RUNTIME_SPLINE_DATA_NAME = RoadSplineData.RUNTIME_DATA_NAME
local CLIENT_VISUALS_NAME = "AuthoredRoadClientVisuals"
local RUNTIME_MESH_NAME = "AuthoredRoadRuntimeMesh"
local GENERATED_ROADS_NAME = "Roads"

local player = Players.LocalPlayer

local function getConfigNumber(key, fallback)
	local value = Config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function getConfigColor(key, fallback)
	local value = Config[key]
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local function getConfigString(key, fallback)
	local value = Config[key]
	if type(value) == "string" and value ~= "" then
		return value
	end

	return fallback
end

local sortedChildren = RoadSplineData.sortedChildren
local distanceXZ = RoadSampling.distanceXZ

local function simplifySamples(samples)
	local spacing = math.max(getConfigNumber("minimapRoadPointSpacing", 28), 1)
	local simplified = {}

	for index, sample in ipairs(samples) do
		if #simplified == 0
			or index == #samples
			or distanceXZ(sample, simplified[#simplified]) >= spacing
		then
			table.insert(simplified, sample)
		end
	end

	if #simplified == 1 and #samples >= 2 then
		table.insert(simplified, samples[#samples])
	end

	return simplified
end

local function newBounds()
	return {
		minX = math.huge,
		maxX = -math.huge,
		minZ = math.huge,
		maxZ = -math.huge,
	}
end

local function includePosition(bounds, position, padding)
	padding = padding or 0
	bounds.minX = math.min(bounds.minX, position.X - padding)
	bounds.maxX = math.max(bounds.maxX, position.X + padding)
	bounds.minZ = math.min(bounds.minZ, position.Z - padding)
	bounds.maxZ = math.max(bounds.maxZ, position.Z + padding)
end

local function includePartBounds(bounds, part)
	local halfSize = part.Size * 0.5
	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				includePosition(bounds, part.CFrame:PointToWorldSpace(Vector3.new(
					halfSize.X * xSign,
					halfSize.Y * ySign,
					halfSize.Z * zSign
				)))
			end
		end
	end
end

local function addRoadSegment(segments, bounds, a, b, width)
	if distanceXZ(a, b) < 0.5 then
		return
	end

	table.insert(segments, {
		ax = a.X,
		az = a.Z,
		bx = b.X,
		bz = b.Z,
		width = width,
	})
	includePosition(bounds, a, width * 0.5)
	includePosition(bounds, b, width * 0.5)
end

local function collectRoadPartsFromContainer(container)
	local parts = {}
	if not container then
		return parts
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function collectMeshRoadData(world)
	if not world then
		return nil
	end

	local sources = {
		world:FindFirstChild(CLIENT_VISUALS_NAME),
		world:FindFirstChild(RUNTIME_MESH_NAME),
		world:FindFirstChild(GENERATED_ROADS_NAME),
	}

	for _, source in ipairs(sources) do
		local parts = collectRoadPartsFromContainer(source)
		if #parts > 0 then
			local bounds = newBounds()
			for _, part in ipairs(parts) do
				includePartBounds(bounds, part)
			end
			return {
				meshParts = parts,
				bounds = bounds,
				source = source.Name,
			}
		end
	end

	return nil
end

local function collectAuthoredRoadData(dataRoot)
	local segments = {}
	local bounds = newBounds()

	for _, chain in ipairs(RoadSplineData.collectSampledChains(dataRoot, {
		defaultRoadWidth = RoadSampling.getConfiguredRoadWidth(Config),
		sampleStep = Config.authoredRoadSampleStepStuds,
	})) do
		local simplified = simplifySamples(chain.samples)
		for i = 1, #simplified - 1 do
			addRoadSegment(segments, bounds, simplified[i], simplified[i + 1], chain.width)
		end
	end

	return {
		segments = segments,
		bounds = bounds,
		source = "AuthoredRoadSplineData",
	}
end

local function collectGeneratedRoadData(world)
	local roadsFolder = world and world:FindFirstChild(GENERATED_ROADS_NAME)
	local segments = {}
	local bounds = newBounds()

	if not (roadsFolder and roadsFolder:IsA("Folder")) then
		return nil
	end

	for _, road in ipairs(roadsFolder:GetChildren()) do
		if road:IsA("BasePart") then
			local size = road.Size
			local isXLong = size.X >= size.Z
			local halfAxis = if isXLong
				then road.CFrame.RightVector * (size.X * 0.5)
				else road.CFrame.LookVector * (size.Z * 0.5)
			local width = if isXLong then size.Z else size.X
			addRoadSegment(segments, bounds, road.Position - halfAxis, road.Position + halfAxis, width)
		end
	end

	return {
		segments = segments,
		bounds = bounds,
		source = GENERATED_ROADS_NAME,
	}
end

local function readRoadData(world)
	if not world then
		return nil
	end

	local mesh = collectMeshRoadData(world)
	if mesh then
		return mesh
	end

	local dataRoot = world:FindFirstChild(RUNTIME_SPLINE_DATA_NAME)
	if dataRoot then
		local authored = collectAuthoredRoadData(dataRoot)
		if #authored.segments > 0 then
			return authored
		end
	end

	local generated = collectGeneratedRoadData(world)
	if generated and #generated.segments > 0 then
		return generated
	end

	return nil
end

local function createUi(parentGui)
	local size = math.max(getConfigNumber("minimapSizePixels", 220), 120)
	local inset = 18

	local root = Instance.new("Frame")
	root.Name = "Minimap"
	root.Position = UDim2.fromOffset(inset, inset)
	root.Size = UDim2.fromOffset(size, size)
	root.BackgroundColor3 = Color3.fromRGB(19, 35, 32)
	root.BackgroundTransparency = 0.06
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = parentGui

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 8)
	rootCorner.Parent = root

	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = Color3.fromRGB(255, 206, 38)
	rootStroke.Transparency = 0.12
	rootStroke.Thickness = 2
	rootStroke.Parent = root

	local viewport = Instance.new("Frame")
	viewport.Name = "Viewport"
	viewport.Position = UDim2.fromOffset(8, 8)
	viewport.Size = UDim2.new(1, -16, 1, -16)
	viewport.BackgroundColor3 = Color3.fromRGB(18, 28, 30)
	viewport.BackgroundTransparency = 0.02
	viewport.BorderSizePixel = 0
	viewport.ClipsDescendants = true
	viewport.Parent = root

	local viewportCorner = Instance.new("UICorner")
	viewportCorner.CornerRadius = UDim.new(0, 6)
	viewportCorner.Parent = viewport

	local meshViewport = Instance.new("ViewportFrame")
	meshViewport.Name = "RoadMesh"
	meshViewport.BackgroundTransparency = 1
	meshViewport.BorderSizePixel = 0
	meshViewport.Size = UDim2.fromScale(1, 1)
	meshViewport.Visible = false
	meshViewport.ZIndex = 1
	meshViewport.Ambient = Color3.fromRGB(180, 180, 180)
	meshViewport.LightColor = Color3.fromRGB(255, 255, 255)
	meshViewport.LightDirection = Vector3.new(0, -1, 0)
	meshViewport.Parent = viewport

	local meshCamera = Instance.new("Camera")
	meshCamera.Name = "MinimapMeshCamera"
	meshCamera.FieldOfView = 12
	meshCamera.Parent = meshViewport
	meshViewport.CurrentCamera = meshCamera

	local meshWorld = Instance.new("WorldModel")
	meshWorld.Name = "RoadMeshWorld"
	meshWorld.Parent = meshViewport

	local roadLayer = Instance.new("Frame")
	roadLayer.Name = "Roads"
	roadLayer.BackgroundTransparency = 1
	roadLayer.Size = UDim2.fromScale(1, 1)
	roadLayer.ZIndex = 2
	roadLayer.Parent = viewport

	local routeLayer = Instance.new("Frame")
	routeLayer.Name = "Route"
	routeLayer.BackgroundTransparency = 1
	routeLayer.Size = UDim2.fromScale(1, 1)
	routeLayer.ZIndex = 3
	routeLayer.Parent = viewport

	local routeLine = Instance.new("Frame")
	routeLine.Name = "DestinationLine"
	routeLine.AnchorPoint = Vector2.new(0.5, 0.5)
	routeLine.BackgroundColor3 = getConfigColor("passengerDeliveryColor", Color3.fromRGB(255, 70, 55))
	routeLine.BorderSizePixel = 0
	routeLine.Visible = false
	routeLine.ZIndex = 3
	routeLine.Parent = routeLayer

	local routeLineCorner = Instance.new("UICorner")
	routeLineCorner.CornerRadius = UDim.new(1, 0)
	routeLineCorner.Parent = routeLine

	local routeSegments = {}

	local destinationMarker = Instance.new("Frame")
	destinationMarker.Name = "DestinationMarker"
	destinationMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	destinationMarker.BackgroundColor3 = getConfigColor("passengerDeliveryColor", Color3.fromRGB(255, 70, 55))
	destinationMarker.BorderSizePixel = 0
	destinationMarker.Rotation = 45
	destinationMarker.Visible = false
	destinationMarker.ZIndex = 4
	destinationMarker.Parent = routeLayer

	local destinationMarkerStroke = Instance.new("UIStroke")
	destinationMarkerStroke.Color = Color3.fromRGB(18, 18, 20)
	destinationMarkerStroke.Transparency = 0.15
	destinationMarkerStroke.Thickness = 2
	destinationMarkerStroke.Parent = destinationMarker

	local playerMarker = Instance.new("TextLabel")
	playerMarker.Name = "PlayerMarker"
	playerMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	playerMarker.Position = UDim2.fromScale(0.5, 0.5)
	playerMarker.Size = UDim2.fromOffset(24, 24)
	playerMarker.BackgroundTransparency = 1
	playerMarker.Font = Enum.Font.GothamBlack
	playerMarker.Text = utf8.char(9650)
	playerMarker.TextColor3 = Color3.fromRGB(255, 206, 38)
	playerMarker.TextSize = 22
	playerMarker.TextStrokeColor3 = Color3.fromRGB(18, 18, 20)
	playerMarker.TextStrokeTransparency = 0.2
	playerMarker.ZIndex = 5
	playerMarker.Parent = viewport

	return {
		root = root,
		viewport = viewport,
		meshViewport = meshViewport,
		meshCamera = meshCamera,
		meshWorld = meshWorld,
		meshClones = {},
		roadLayer = roadLayer,
		routeLayer = routeLayer,
		routeLine = routeLine,
		routeSegments = routeSegments,
		destinationMarker = destinationMarker,
		playerMarker = playerMarker,
	}
end

local function clearLayer(layer)
	for _, child in ipairs(layer:GetChildren()) do
		child:Destroy()
	end
end

local function clearMeshWorld(ui)
	for _, child in ipairs(ui.meshWorld:GetChildren()) do
		child:Destroy()
	end
	table.clear(ui.meshClones)
end

local function addMeshClone(ui, sourcePart)
	local ok, cloneOrErr = pcall(function()
		return sourcePart:Clone()
	end)
	if not ok or not cloneOrErr or not cloneOrErr:IsA("BasePart") then
		return
	end

	local clone = cloneOrErr
	clone.Name = sourcePart.Name
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.CastShadow = false
	clone.Transparency = 0
	clone.Color = Color3.fromRGB(78, 86, 88)
	clone.Material = Enum.Material.SmoothPlastic
	clone.Parent = ui.meshWorld
	table.insert(ui.meshClones, clone)
end

local function buildRoadUi(ui, mapData)
	clearLayer(ui.roadLayer)
	clearMeshWorld(ui)

	local roadItems = {}
	if not mapData then
		ui.meshViewport.Visible = false
		return roadItems
	end

	if mapData.meshParts and #mapData.meshParts > 0 then
		for _, part in ipairs(mapData.meshParts) do
			addMeshClone(ui, part)
		end
		ui.meshViewport.Visible = #ui.meshClones > 0
		if ui.meshViewport.Visible then
			return roadItems
		end
	end

	ui.meshViewport.Visible = false
	for _, segment in ipairs(mapData.segments) do
		local frame = Instance.new("Frame")
		frame.Name = "Road"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundColor3 = Color3.fromRGB(72, 78, 82)
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.ZIndex = 2
		frame.Parent = ui.roadLayer

		table.insert(roadItems, {
			frame = frame,
			ax = segment.ax,
			az = segment.az,
			bx = segment.bx,
			bz = segment.bz,
			width = segment.width,
		})
	end

	return roadItems
end

local function getCabPose(cab)
	if not cab then
		return nil
	end

	local pivotValue = cab:FindFirstChild(Config.carServerPivotValueName)
	local pivot = if pivotValue and pivotValue:IsA("CFrameValue") then pivotValue.Value else cab:GetPivot()
	local forward = -pivot.LookVector
	return pivot.Position, Vector3.new(forward.X, 0, forward.Z)
end

local function getCharacterPose()
	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not (root and root:IsA("BasePart")) then
		return nil
	end

	local forward = root.CFrame.LookVector
	return root.Position, Vector3.new(forward.X, 0, forward.Z)
end

local function getDrivenCabFromTracker(cabTracker)
	local cab = nil
	if type(cabTracker) == "function" then
		cab = cabTracker()
	elseif type(cabTracker) == "table" and type(cabTracker.getDrivenCab) == "function" then
		cab = cabTracker.getDrivenCab()
	end

	return cab
end

local function getTrackedPose(cabTracker)
	local cab = getDrivenCabFromTracker(cabTracker)
	local position, forward = getCabPose(cab)
	if position then
		return position, forward, cab
	end

	return getCharacterPose()
end

local function getCabDestination(cab)
	if not cab then
		return nil
	end

	local modeAttribute = Config.passengerFareModeAttribute
	if type(modeAttribute) == "string" and cab:GetAttribute(modeAttribute) ~= "delivery" then
		return nil
	end

	local destinationAttribute = Config.passengerDestinationAttribute
	if type(destinationAttribute) ~= "string" then
		return nil
	end

	local destination = cab:GetAttribute(destinationAttribute)
	if typeof(destination) ~= "Vector3" then
		return nil
	end

	return destination
end

local function updateRoadSegment(item, playerPosition, scale, halfWidth, halfHeight, viewportWidth, viewportHeight)
	local ax = halfWidth + (item.ax - playerPosition.X) * scale
	local ay = halfHeight + (item.az - playerPosition.Z) * scale
	local bx = halfWidth + (item.bx - playerPosition.X) * scale
	local by = halfHeight + (item.bz - playerPosition.Z) * scale
	local dx = bx - ax
	local dy = by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	local roadPixels = math.clamp(
		item.width * scale,
		getConfigNumber("minimapRoadMinPixels", 3),
		getConfigNumber("minimapRoadMaxPixels", 16)
	)

	local padding = math.max(roadPixels, 8)
	local minX = math.min(ax, bx) - padding
	local maxX = math.max(ax, bx) + padding
	local minY = math.min(ay, by) - padding
	local maxY = math.max(ay, by) + padding
	local visible = length >= 1
		and maxX >= 0
		and minX <= viewportWidth
		and maxY >= 0
		and minY <= viewportHeight

	item.frame.Visible = visible
	if not visible then
		return
	end

	item.frame.Position = UDim2.fromOffset((ax + bx) * 0.5, (ay + by) * 0.5)
	item.frame.Size = UDim2.fromOffset(length, roadPixels)
	item.frame.Rotation = math.deg(math.atan2(dy, dx))
end

local function updateMeshViewport(ui, playerPosition, worldSpan)
	if #ui.meshClones == 0 then
		ui.meshViewport.Visible = false
		return
	end

	local fieldOfView = math.rad(ui.meshCamera.FieldOfView)
	local cameraHeight = worldSpan / (2 * math.tan(fieldOfView * 0.5))
	local target = Vector3.new(playerPosition.X, playerPosition.Y, playerPosition.Z)
	ui.meshCamera.CFrame = CFrame.lookAt(
		target + Vector3.new(0, cameraHeight, 0),
		target,
		Vector3.new(0, 0, -1)
	)
	ui.meshViewport.Visible = true
end

local function getGpsGuide(world)
	if not world then
		return nil
	end

	local guide = world:FindFirstChild(getConfigString("gpsGuideFolderName", "GpsGuide"))
	if guide then
		return guide
	end

	local markerFolder = world:FindFirstChild(getConfigString("passengerMarkersFolderName", "PassengerMarkers"))
	return markerFolder and markerFolder:FindFirstChild(getConfigString("passengerDeliveryGuideFolderName", "DeliveryGuide"))
end

local function getWorldRouteSegmentParts(world)
	local guide = getGpsGuide(world)
	if not (guide and guide:GetAttribute("Visible") == true) then
		return {}
	end

	local routeLine = guide:FindFirstChild("RouteLine")
	if not (routeLine and routeLine:IsA("Folder")) then
		return {}
	end

	local parts = {}
	for _, child in ipairs(sortedChildren(routeLine, "BasePart")) do
		if child.Transparency < 0.99 and child.Size.Z > 0.05 then
			table.insert(parts, child)
		end
	end

	return parts
end

local function ensureRouteSegmentFrames(ui, count)
	local routeColor = getConfigColor("passengerDeliveryColor", Color3.fromRGB(255, 70, 55))
	while #ui.routeSegments < count do
		local frame = Instance.new("Frame")
		frame.Name = string.format("RouteSegment_%02d", #ui.routeSegments + 1)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundColor3 = routeColor
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.ZIndex = 3
		frame.Parent = ui.routeLayer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame

		table.insert(ui.routeSegments, frame)
	end
end

local function hideDestinationGuide(ui)
	ui.routeLine.Visible = false
	ui.destinationMarker.Visible = false
	for _, frame in ipairs(ui.routeSegments) do
		frame.Visible = false
	end
end

local function updateMinimapRouteSegment(frame, part, playerPosition, scale, halfWidth, halfHeight, viewportWidth, viewportHeight)
	local halfLength = part.Size.Z * 0.5
	local center = part.Position
	local direction = part.CFrame.LookVector
	local a = center - direction * halfLength
	local b = center + direction * halfLength
	local ax = halfWidth + (a.X - playerPosition.X) * scale
	local ay = halfHeight + (a.Z - playerPosition.Z) * scale
	local bx = halfWidth + (b.X - playerPosition.X) * scale
	local by = halfHeight + (b.Z - playerPosition.Z) * scale
	local dx = bx - ax
	local dy = by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	local linePixels = math.max(getConfigNumber("minimapRouteLinePixels", 4), 1)
	local padding = math.max(linePixels, 8)
	local visible = length >= 1
		and math.max(ax, bx) + padding >= 0
		and math.min(ax, bx) - padding <= viewportWidth
		and math.max(ay, by) + padding >= 0
		and math.min(ay, by) - padding <= viewportHeight

	frame.Visible = visible
	if not visible then
		return
	end

	frame.BackgroundColor3 = getConfigColor("passengerDeliveryColor", Color3.fromRGB(255, 70, 55))
	frame.Position = UDim2.fromOffset((ax + bx) * 0.5, (ay + by) * 0.5)
	frame.Size = UDim2.fromOffset(length, linePixels)
	frame.Rotation = math.deg(math.atan2(dy, dx))
end

local function updateDestinationMarker(ui, cab, playerPosition, scale, viewportWidth, viewportHeight, halfWidth, halfHeight)
	local destination = getCabDestination(cab)
	if not destination then
		return
	end

	local targetX = halfWidth + (destination.X - playerPosition.X) * scale
	local targetY = halfHeight + (destination.Z - playerPosition.Z) * scale
	local markerSize = math.max(getConfigNumber("minimapDestinationMarkerPixels", 16), 8)
	local padding = markerSize * 0.5 + 4
	local routeColor = getConfigColor("passengerDeliveryColor", Color3.fromRGB(255, 70, 55))
	local visible = targetX + padding >= 0
		and targetX - padding <= viewportWidth
		and targetY + padding >= 0
		and targetY - padding <= viewportHeight

	ui.destinationMarker.BackgroundColor3 = routeColor
	ui.destinationMarker.Position = UDim2.fromOffset(targetX, targetY)
	ui.destinationMarker.Size = UDim2.fromOffset(markerSize, markerSize)
	ui.destinationMarker.Visible = visible
end

local function updateDestinationGuide(ui, world, cab, playerPosition, scale, halfWidth, halfHeight, viewportWidth, viewportHeight)
	hideDestinationGuide(ui)

	local routeParts = getWorldRouteSegmentParts(world)
	if #routeParts == 0 then
		return
	end

	ensureRouteSegmentFrames(ui, #routeParts)
	for index, part in ipairs(routeParts) do
		updateMinimapRouteSegment(
			ui.routeSegments[index],
			part,
			playerPosition,
			scale,
			halfWidth,
			halfHeight,
			viewportWidth,
			viewportHeight
		)
	end

	for index = #routeParts + 1, #ui.routeSegments do
		ui.routeSegments[index].Visible = false
	end

	updateDestinationMarker(ui, cab, playerPosition, scale, viewportWidth, viewportHeight, halfWidth, halfHeight)
end

function MinimapController.start(parentGui, cabTracker)
	if Config.minimapEnabled == false then
		return nil
	end

	local ui = createUi(parentGui)
	local currentMap = nil
	local roadItems = {}
	local watchedWorld = nil
	local worldConnections = {}
	local connections = {}
	local rebuildSerial = 0
	local updateAccumulator = 0
	local destroyed = false

	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(connections, connection)
		return connection
	end

	local function disconnectWorld()
		for _, connection in ipairs(worldConnections) do
			connection:Disconnect()
		end
		worldConnections = {}
	end

	local function rebuild()
		if destroyed then
			return
		end

		currentMap = readRoadData(watchedWorld)
		roadItems = buildRoadUi(ui, currentMap)
		ui.root.Visible = false
	end

	local function scheduleRebuild(delayTime)
		rebuildSerial += 1
		local serial = rebuildSerial
		task.delay(delayTime or 0.25, function()
			if not destroyed and serial == rebuildSerial then
				rebuild()
			end
		end)
	end

	local function watchWorld(world)
		if destroyed then
			return
		end

		disconnectWorld()
		watchedWorld = world
		currentMap = nil
		roadItems = buildRoadUi(ui, nil)
		ui.root.Visible = false

		local function watchMapContainer(container)
			if not container then
				return
			end

			table.insert(worldConnections, container.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("Vector3Value") or descendant:IsA("BasePart") then
					scheduleRebuild(0.35)
				end
			end))
			table.insert(worldConnections, container.DescendantRemoving:Connect(function(descendant)
				if descendant:IsA("Vector3Value") or descendant:IsA("BasePart") then
					scheduleRebuild(0.35)
				end
			end))
		end

		if watchedWorld then
			table.insert(worldConnections, watchedWorld.ChildAdded:Connect(function(child)
				if child.Name == RUNTIME_SPLINE_DATA_NAME
					or child.Name == GENERATED_ROADS_NAME
					or child.Name == CLIENT_VISUALS_NAME
					or child.Name == RUNTIME_MESH_NAME
				then
					watchMapContainer(child)
					scheduleRebuild(0.35)
				end
			end))

			table.insert(worldConnections, watchedWorld.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					watchWorld(nil)
				end
			end))

			watchMapContainer(watchedWorld:FindFirstChild(RUNTIME_SPLINE_DATA_NAME))
			watchMapContainer(watchedWorld:FindFirstChild(GENERATED_ROADS_NAME))
			watchMapContainer(watchedWorld:FindFirstChild(CLIENT_VISUALS_NAME))
			watchMapContainer(watchedWorld:FindFirstChild(RUNTIME_MESH_NAME))
		end

		scheduleRebuild(0.35)
	end

	connect(Workspace.ChildAdded, function(child)
		if child.Name == WORLD_NAME and child:IsA("Model") then
			watchWorld(child)
		end
	end)

	local existingWorld = Workspace:FindFirstChild(WORLD_NAME)
	if existingWorld and existingWorld:IsA("Model") then
		watchWorld(existingWorld)
	else
		watchWorld(nil)
	end

	connect(RunService.RenderStepped, function(dt)
		if destroyed then
			return
		end

		updateAccumulator += dt
		local refreshRate = math.max(getConfigNumber("minimapRefreshRate", 1 / 30), 1 / 60)
		if updateAccumulator < refreshRate then
			return
		end
		updateAccumulator = 0

		local playerPosition, forward, cab = getTrackedPose(cabTracker)
		local hasRoadVisuals = #roadItems > 0 or #ui.meshClones > 0
		ui.root.Visible = currentMap ~= nil and playerPosition ~= nil and hasRoadVisuals
		if not ui.root.Visible then
			return
		end

		local viewportSize = ui.viewport.AbsoluteSize
		if viewportSize.X <= 0 or viewportSize.Y <= 0 then
			return
		end

		local span = math.max(getConfigNumber("minimapWorldSpanStuds", 720), 120)
		local scale = math.min(viewportSize.X, viewportSize.Y) / span
		local halfWidth = viewportSize.X * 0.5
		local halfHeight = viewportSize.Y * 0.5

		if #ui.meshClones > 0 then
			updateMeshViewport(ui, playerPosition, span)
			for _, item in ipairs(roadItems) do
				item.frame.Visible = false
			end
		else
			ui.meshViewport.Visible = false
			for _, item in ipairs(roadItems) do
				updateRoadSegment(item, playerPosition, scale, halfWidth, halfHeight, viewportSize.X, viewportSize.Y)
			end
		end

		updateDestinationGuide(ui, watchedWorld, cab, playerPosition, scale, halfWidth, halfHeight, viewportSize.X, viewportSize.Y)

		ui.playerMarker.Position = UDim2.fromOffset(halfWidth, halfHeight)
		if forward and forward.Magnitude > 0.001 then
			ui.playerMarker.Rotation = math.deg(math.atan2(forward.X, -forward.Z))
		end
	end)

	return {
		destroy = function()
			destroyed = true
			rebuildSerial += 1
			disconnectWorld()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			table.clear(connections)
			ui.root:Destroy()
		end,
	}
end

return MinimapController
