local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadGraphData = require(Shared:WaitForChild("RoadGraphData"))
local RoadSampling = require(Shared:WaitForChild("RoadSampling"))
local RoadSplineData = require(Shared:WaitForChild("RoadSplineData"))

local MinimapController = {}

local WORLD_NAME = "Cab87World"
local ROAD_EDITOR_ROOT_NAME = "Cab87RoadEditor"
local RUNTIME_SPLINE_DATA_NAME = RoadSplineData.RUNTIME_DATA_NAME
local RUNTIME_GRAPH_DATA_NAME = RoadGraphData.RUNTIME_DATA_NAME
local BAKED_ROAD_GRAPH_RUNTIME_NAME = "RoadGraphBakedRuntime"
local BAKED_ROAD_GRAPH_SURFACES_NAME = "RoadGraphBakedSurfaces"
local ROAD_GRAPH_SURFACES_NAME = "RoadGraphSurfaces"
local CLIENT_VISUALS_NAME = "AuthoredRoadClientVisuals"
local RUNTIME_MESH_NAME = "AuthoredRoadRuntimeMesh"
local GENERATED_ROADS_NAME = "Roads"
local LEGACY_ROAD_NETWORK_NAME = RoadSplineData.NETWORK_NAME
local MINIMAP_ROAD_MESH_NAME = "MinimapRoadMesh"
local MINIMAP_BACKGROUND_COLOR = Color3.fromRGB(218, 220, 224)
local MINIMAP_PANEL_COLOR = Color3.fromRGB(232, 234, 237)
local MINIMAP_BORDER_COLOR = Color3.fromRGB(154, 160, 166)
local MINIMAP_ROAD_COLOR = Color3.fromRGB(255, 255, 255)
local MINIMAP_SIDEWALK_COLOR = Color3.fromRGB(232, 234, 237)
local MINIMAP_CROSSWALK_COLOR = Color3.fromRGB(248, 249, 250)
local MINIMAP_ROUTE_COLOR = Color3.fromRGB(26, 115, 232)
local MINIMAP_PASSENGER_MARKER_STROKE = Color3.fromRGB(18, 18, 20)
local MINIMAP_ROUTE_LIFT = 4
local MINIMAP_ROAD_LIFT = 0.12
local MINIMAP_LOG_PREFIX = "[cab87 minimap]"
local MAX_SOURCE_DEBUG_PARTS = 6

local player = Players.LocalPlayer

local function minimapDebugLog(message, ...)
	if Config.minimapDebugLogging ~= true and Config.authoredRoadDebugLogging ~= true then
		return
	end

	local ok, formatted = pcall(string.format, tostring(message), ...)
	print(MINIMAP_LOG_PREFIX .. " " .. (ok and formatted or tostring(message)))
end

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

local function getMinimapSurfaceStyle(part)
	local surfaceType = part and part:GetAttribute("SurfaceType")
	if surfaceType == "sidewalk" then
		return MINIMAP_SIDEWALK_COLOR, Enum.Material.SmoothPlastic
	elseif surfaceType == "crosswalk" then
		return MINIMAP_CROSSWALK_COLOR, Enum.Material.SmoothPlastic
	elseif surfaceType == "building" then
		return Color3.fromRGB(76, 85, 99), Enum.Material.SmoothPlastic
	end

	return MINIMAP_ROAD_COLOR, Enum.Material.SmoothPlastic
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

local function safeProperty(instance, propertyName)
	local ok, value = pcall(function()
		return instance[propertyName]
		end)
	if ok then
		return value
	end
	return nil
end

local function describePart(part)
	if not part then
		return "nil"
	end

	local className = part.ClassName
	local meshId = safeProperty(part, "MeshId")
	local meshContent = safeProperty(part, "MeshContent")
	return string.format(
		"%s class=%s size=(%.1f,%.1f,%.1f) surfaceType=%s meshMode=%s contentMode=%s tris=%s meshId=%s meshContent=%s",
		part.Name,
		className,
		part.Size.X,
		part.Size.Y,
		part.Size.Z,
		tostring(part:GetAttribute("SurfaceType")),
		tostring(part:GetAttribute("MeshMode")),
		tostring(part:GetAttribute("MeshContentMode")),
		tostring(part:GetAttribute("TriangleCount") or part:GetAttribute("EditableMeshFaceCount")),
		tostring(meshId),
		tostring(meshContent)
	)
end

local function hasUsableMeshContent(part)
	if not part then
		return false
	end
	if not part:IsA("MeshPart") then
		return true
	end

	local meshId = safeProperty(part, "MeshId")
	if type(meshId) == "string" and meshId ~= "" then
		return true
	end

	local meshContent = safeProperty(part, "MeshContent")
	if meshContent and tostring(meshContent) ~= "Content{SourceType=None}" then
		return true
	end

	return false
end

local function shouldUsePartForMinimapRoadMesh(part)
	local surfaceType = part and part:GetAttribute("SurfaceType")
	return surfaceType == "road" or surfaceType == "crosswalk" or surfaceType == "building"
end

local function describeSource(source)
	if not source then
		return "nil"
	end

	return string.format(
		"%s class=%s generatedBy=%s version=%s surfacePartsAttr=%s minimap=%s",
		source:GetFullName(),
		source.ClassName,
		tostring(source:GetAttribute("GeneratedBy")),
		tostring(source:GetAttribute("Version")),
		tostring(source:GetAttribute("SurfacePartCount")),
		tostring(source:GetAttribute("MinimapRoadMesh") or source:GetAttribute("BakedMinimapRoadMesh"))
	)
end

local function formatBounds(bounds)
	if not bounds or bounds.minX == math.huge then
		return "empty"
	end

	return string.format(
		"min=(%.1f,%.1f) max=(%.1f,%.1f)",
		bounds.minX,
		bounds.minZ,
		bounds.maxX,
		bounds.maxZ
	)
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

local function addOverlaySegment(segments, bounds, a, b, pixelWidth)
	if distanceXZ(a, b) < 0.5 then
		return
	end

	table.insert(segments, {
		ax = a.X,
		az = a.Z,
		bx = b.X,
		bz = b.Z,
		width = 0,
		pixelWidth = pixelWidth,
		color = Color3.fromRGB(98, 106, 108),
	})
	includePosition(bounds, a)
	includePosition(bounds, b)
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

local function filterUsableRoadParts(parts, source)
	local usableParts = {}
	local skippedParts = 0
	local skippedSurfaceParts = 0
	for _, part in ipairs(parts or {}) do
		if not shouldUsePartForMinimapRoadMesh(part) then
			skippedSurfaceParts += 1
			if skippedSurfaceParts <= MAX_SOURCE_DEBUG_PARTS then
				minimapDebugLog("skipping non-road minimap part from %s: %s", source and source.Name or "?", describePart(part))
			end
		elseif hasUsableMeshContent(part) then
			table.insert(usableParts, part)
		else
			skippedParts += 1
			if skippedParts <= MAX_SOURCE_DEBUG_PARTS then
				minimapDebugLog("skipping unusable mesh part from %s: %s", source and source.Name or "?", describePart(part))
			end
		end
	end

	if skippedParts > 0 or skippedSurfaceParts > 0 then
		minimapDebugLog(
			"source %s usable mesh parts: usable=%d skippedInvalidContent=%d skippedNonRoadSurface=%d",
			source and source.Name or "?",
			#usableParts,
			skippedParts,
			skippedSurfaceParts
		)
	end
	return usableParts
end

local function appendSource(sources, source)
	if source then
		table.insert(sources, source)
	end
end

local function appendBakedGraphSurfaceSources(sources, world, editorRoot)
	local bakedRuntime = editorRoot and editorRoot:FindFirstChild(BAKED_ROAD_GRAPH_RUNTIME_NAME)
	local worldBakedRuntime = world and world:FindFirstChild(BAKED_ROAD_GRAPH_RUNTIME_NAME)

	appendSource(sources, bakedRuntime and bakedRuntime:FindFirstChild(BAKED_ROAD_GRAPH_SURFACES_NAME))
	appendSource(sources, worldBakedRuntime and worldBakedRuntime:FindFirstChild(BAKED_ROAD_GRAPH_SURFACES_NAME))
	appendSource(sources, editorRoot and editorRoot:FindFirstChild(BAKED_ROAD_GRAPH_SURFACES_NAME))
	appendSource(sources, world and world:FindFirstChild(BAKED_ROAD_GRAPH_SURFACES_NAME))
	appendSource(sources, editorRoot and editorRoot:FindFirstChild(ROAD_GRAPH_SURFACES_NAME))
	appendSource(sources, world and world:FindFirstChild(ROAD_GRAPH_SURFACES_NAME))
end

local function collectMeshRoadData(world, hasGraphRoadData)
	if not world then
		return nil
	end

	local editorRoot = Workspace:FindFirstChild(ROAD_EDITOR_ROOT_NAME)
	local sources = {}
	appendSource(sources, world:FindFirstChild(MINIMAP_ROAD_MESH_NAME))
	appendBakedGraphSurfaceSources(sources, world, editorRoot)
	appendSource(sources, world:FindFirstChild(CLIENT_VISUALS_NAME))
	appendSource(sources, world:FindFirstChild(RUNTIME_MESH_NAME))

	if not hasGraphRoadData then
		appendSource(sources, world:FindFirstChild(LEGACY_ROAD_NETWORK_NAME))
		appendSource(sources, editorRoot and editorRoot:FindFirstChild(LEGACY_ROAD_NETWORK_NAME))
		appendSource(sources, world:FindFirstChild(GENERATED_ROADS_NAME))
	end

	for _, source in ipairs(sources) do
		local allParts = collectRoadPartsFromContainer(source)
		minimapDebugLog("candidate mesh source: %s partCount=%d", describeSource(source), #allParts)
		for index = 1, math.min(#allParts, MAX_SOURCE_DEBUG_PARTS) do
			minimapDebugLog("candidate part[%d]: %s", index, describePart(allParts[index]))
		end
		local parts = filterUsableRoadParts(allParts, source)
		if #parts > 0 then
			local maxMeshParts = math.max(math.floor(getConfigNumber("minimapViewportMaxMeshParts", 256)), 1)
			if #parts > maxMeshParts then
				minimapDebugLog(
					"skipping mesh source %s: partCount=%d exceeds minimapViewportMaxMeshParts=%d",
					source.Name,
					#parts,
					maxMeshParts
				)
				continue
			end

			local bounds = newBounds()
			for _, part in ipairs(parts) do
				includePartBounds(bounds, part)
			end
			minimapDebugLog(
				"selected mesh source: %s partCount=%d bounds=%s",
				describeSource(source),
				#parts,
				formatBounds(bounds)
			)
			return {
				meshParts = parts,
				bounds = bounds,
				source = source.Name,
			}
		end
	end

	return nil
end

local function clipLineToRect(ax, ay, bx, by, minX, minY, maxX, maxY)
	local dx = bx - ax
	local dy = by - ay
	local u1 = 0
	local u2 = 1

	local function clipTest(p, q)
		if p == 0 then
			return q >= 0
		end

		local r = q / p
		if p < 0 then
			if r > u2 then
				return false
			end
			if r > u1 then
				u1 = r
			end
		else
			if r < u1 then
				return false
			end
			if r < u2 then
				u2 = r
			end
		end

		return true
	end

	if not clipTest(-dx, ax - minX) then
		return nil
	end
	if not clipTest(dx, maxX - ax) then
		return nil
	end
	if not clipTest(-dy, ay - minY) then
		return nil
	end
	if not clipTest(dy, maxY - ay) then
		return nil
	end

	return ax + u1 * dx, ay + u1 * dy, ax + u2 * dx, ay + u2 * dy
end

local function setClippedLineFrame(frame, ax, ay, bx, by, linePixels, viewportWidth, viewportHeight)
	local inset = math.max(linePixels * 0.5 + 1, 1)
	if viewportWidth <= inset * 2 or viewportHeight <= inset * 2 then
		frame.Visible = false
		return
	end

	local clippedAx, clippedAy, clippedBx, clippedBy = clipLineToRect(
		ax,
		ay,
		bx,
		by,
		inset,
		inset,
		viewportWidth - inset,
		viewportHeight - inset
	)
	if not clippedAx then
		frame.Visible = false
		return
	end

	local dx = clippedBx - clippedAx
	local dy = clippedBy - clippedAy
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1 then
		frame.Visible = false
		return
	end

	frame.Position = UDim2.fromOffset((clippedAx + clippedBx) * 0.5, (clippedAy + clippedBy) * 0.5)
	frame.Size = UDim2.fromOffset(length, linePixels)
	frame.Rotation = math.deg(math.atan2(dy, dx))
	frame.Visible = true
end

local function collectAuthoredRoadData(dataRoot)
	local segments = {}
	local junctionSegments = {}
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

	for _, junction in ipairs(RoadSplineData.collectJunctions(dataRoot, {
		defaultRadius = RoadSampling.DEFAULT_ROAD_WIDTH * 0.5,
		minRadius = 2,
	})) do
		if junction.boundary and #junction.boundary >= 3 then
			local pixelWidth = math.max(getConfigNumber("minimapJunctionOutlinePixels", 4), 1)
			for i = 1, #junction.boundary do
				local nextIndex = (i % #junction.boundary) + 1
				addOverlaySegment(junctionSegments, bounds, junction.boundary[i], junction.boundary[nextIndex], pixelWidth)
			end
		end
	end

	return {
		segments = segments,
		junctionSegments = junctionSegments,
		bounds = bounds,
		source = "AuthoredRoadSplineData",
	}
end

local function collectGraphRoadData(world)
	local dataRoot = world and world:FindFirstChild(RUNTIME_GRAPH_DATA_NAME)
	local graph = dataRoot and RoadGraphData.collectGraph(dataRoot, Config)
	if not graph then
		return nil
	end

	local segments = {}
	local bounds = newBounds()
	local defaultRoadWidth = RoadSampling.getConfiguredRoadWidth(Config)

	for _, edge in ipairs(graph.edges or {}) do
		local points = {}
		local sourceNode = graph.nodeLookup and graph.nodeLookup[edge.source]
		if sourceNode then
			table.insert(points, sourceNode.point)
		end

		for _, point in ipairs(edge.points or {}) do
			table.insert(points, point)
		end

		local targetNode = edge.target and graph.nodeLookup and graph.nodeLookup[edge.target]
		if targetNode then
			table.insert(points, targetNode.point)
		end

		local roadWidth = RoadSampling.sanitizeRoadWidth(edge.width, defaultRoadWidth)
		for index = 1, #points - 1 do
			addRoadSegment(segments, bounds, points[index], points[index + 1], roadWidth)
		end
	end

	if #segments == 0 then
		return nil
	end

	return {
		graph = graph,
		segments = segments,
		junctionSegments = {},
		bounds = bounds,
		source = RUNTIME_GRAPH_DATA_NAME,
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
		minimapDebugLog("readRoadData: no Cab87World yet")
		return nil
	end

	local dataRoot = world:FindFirstChild(RUNTIME_SPLINE_DATA_NAME)
	local graph = collectGraphRoadData(world)
	local mesh = collectMeshRoadData(world, graph ~= nil)
	local authored = nil
	if dataRoot then
		authored = collectAuthoredRoadData(dataRoot)
	end

	if graph then
		graph.meshParts = if mesh and mesh.source ~= GENERATED_ROADS_NAME then mesh.meshParts else nil
		minimapDebugLog(
			"readRoadData: graph source=%s graphSegments=%d meshSource=%s meshParts=%d",
			tostring(graph.source),
			#(graph.segments or {}),
			tostring(mesh and mesh.source),
			mesh and #(mesh.meshParts or {}) or 0
		)
		return graph
	end

	if mesh then
		mesh.segments = authored and authored.segments or {}
		mesh.junctionSegments = authored and authored.junctionSegments or {}
		minimapDebugLog(
			"readRoadData: mesh source=%s meshParts=%d fallbackSegments=%d",
			tostring(mesh.source),
			#(mesh.meshParts or {}),
			#(mesh.segments or {})
		)
		return mesh
	end

	if authored then
		if #authored.segments > 0 or #authored.junctionSegments > 0 then
			minimapDebugLog(
				"readRoadData: authored spline source segments=%d junctionSegments=%d",
				#authored.segments,
				#authored.junctionSegments
			)
			return authored
		end
	end

	local generated = collectGeneratedRoadData(world)
	if generated and #generated.segments > 0 then
		minimapDebugLog("readRoadData: generated road fallback segments=%d", #generated.segments)
		return generated
	end

	minimapDebugLog("readRoadData: no road data found in %s", world:GetFullName())
	return nil
end

local function createUi(parentGui)
	local size = math.max(getConfigNumber("minimapSizePixels", 220), 120)
	local inset = 18

	local root = Instance.new("Frame")
	root.Name = "Minimap"
	root.Position = UDim2.fromOffset(inset, inset)
	root.Size = UDim2.fromOffset(size, size)
	root.BackgroundColor3 = MINIMAP_PANEL_COLOR
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Visible = false
	root.Parent = parentGui

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 8)
	rootCorner.Parent = root

	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = MINIMAP_BORDER_COLOR
	rootStroke.Transparency = 0.05
	rootStroke.Thickness = 2
	rootStroke.Parent = root

	local viewport = Instance.new("Frame")
	viewport.Name = "Viewport"
	viewport.Position = UDim2.fromOffset(8, 8)
	viewport.Size = UDim2.new(1, -16, 1, -16)
	viewport.BackgroundColor3 = MINIMAP_BACKGROUND_COLOR
	viewport.BackgroundTransparency = 0
	viewport.BorderSizePixel = 0
	viewport.ClipsDescendants = true
	viewport.Parent = root

	local viewportCorner = Instance.new("UICorner")
	viewportCorner.CornerRadius = UDim.new(0, 6)
	viewportCorner.Parent = viewport

	local meshViewport = Instance.new("ViewportFrame")
	meshViewport.Name = "RoadMesh"
	meshViewport.BackgroundColor3 = MINIMAP_BACKGROUND_COLOR
	meshViewport.BackgroundTransparency = 0
	meshViewport.BorderSizePixel = 0
	meshViewport.Size = UDim2.fromScale(1, 1)
	meshViewport.Visible = false
	meshViewport.ZIndex = 1
	meshViewport.Ambient = Color3.fromRGB(255, 255, 255)
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

	local meshRoadModel = Instance.new("Model")
	meshRoadModel.Name = "RoadMesh"
	meshRoadModel.Parent = meshWorld

	local meshRouteModel = Instance.new("Model")
	meshRouteModel.Name = "RouteGuide"
	meshRouteModel.Parent = meshWorld

	local roadLayer = Instance.new("Frame")
	roadLayer.Name = "Roads"
	roadLayer.BackgroundTransparency = 1
	roadLayer.ClipsDescendants = true
	roadLayer.Size = UDim2.fromScale(1, 1)
	roadLayer.ZIndex = 2
	roadLayer.Parent = viewport

	local routeLayer = Instance.new("Frame")
	routeLayer.Name = "Route"
	routeLayer.BackgroundTransparency = 1
	routeLayer.ClipsDescendants = true
	routeLayer.Size = UDim2.fromScale(1, 1)
	routeLayer.ZIndex = 3
	routeLayer.Parent = viewport

	local routeLine = Instance.new("Frame")
	routeLine.Name = "DestinationLine"
	routeLine.AnchorPoint = Vector2.new(0.5, 0.5)
	routeLine.BackgroundColor3 = MINIMAP_ROUTE_COLOR
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
	destinationMarker.BackgroundColor3 = MINIMAP_ROUTE_COLOR
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

	local passengerLayer = Instance.new("Frame")
	passengerLayer.Name = "PassengerPickups"
	passengerLayer.BackgroundTransparency = 1
	passengerLayer.ClipsDescendants = true
	passengerLayer.Size = UDim2.fromScale(1, 1)
	passengerLayer.ZIndex = 4
	passengerLayer.Parent = viewport

	local playerMarker = Instance.new("Frame")
	playerMarker.Name = "PlayerMarker"
	playerMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	playerMarker.Position = UDim2.fromScale(0.5, 0.5)
	playerMarker.Size = UDim2.fromOffset(14, 24)
	playerMarker.BackgroundColor3 = Color3.fromRGB(255, 206, 38)
	playerMarker.BorderSizePixel = 0
	playerMarker.ZIndex = 5
	playerMarker.Parent = viewport

	local playerMarkerCorner = Instance.new("UICorner")
	playerMarkerCorner.CornerRadius = UDim.new(0, 3)
	playerMarkerCorner.Parent = playerMarker

	local playerMarkerStroke = Instance.new("UIStroke")
	playerMarkerStroke.Color = Color3.fromRGB(18, 18, 20)
	playerMarkerStroke.Transparency = 0.08
	playerMarkerStroke.Thickness = 2
	playerMarkerStroke.Parent = playerMarker

	local playerMarkerHood = Instance.new("Frame")
	playerMarkerHood.Name = "Hood"
	playerMarkerHood.AnchorPoint = Vector2.new(0.5, 0)
	playerMarkerHood.Position = UDim2.fromScale(0.5, 0)
	playerMarkerHood.Size = UDim2.new(0.55, 0, 0.28, 0)
	playerMarkerHood.BackgroundColor3 = Color3.fromRGB(255, 238, 130)
	playerMarkerHood.BorderSizePixel = 0
	playerMarkerHood.ZIndex = 6
	playerMarkerHood.Parent = playerMarker

	local playerMarkerHoodCorner = Instance.new("UICorner")
	playerMarkerHoodCorner.CornerRadius = UDim.new(0, 2)
	playerMarkerHoodCorner.Parent = playerMarkerHood

	return {
		root = root,
		viewport = viewport,
		meshViewport = meshViewport,
		meshCamera = meshCamera,
		meshWorld = meshWorld,
		meshRoadModel = meshRoadModel,
		meshRouteModel = meshRouteModel,
		meshClones = {},
		routeMeshParts = {},
		destinationMeshMarker = nil,
		roadLayer = roadLayer,
		routeLayer = routeLayer,
		routeLine = routeLine,
		routeSegments = routeSegments,
		destinationMarker = destinationMarker,
		passengerLayer = passengerLayer,
		passengerMarkers = {},
		playerMarker = playerMarker,
	}
end

local function clearLayer(layer)
	for _, child in ipairs(layer:GetChildren()) do
		child:Destroy()
	end
end

local function clearMeshWorld(ui)
	for _, child in ipairs(ui.meshRoadModel:GetChildren()) do
		child:Destroy()
	end
	table.clear(ui.meshClones)
end

local function addMeshClone(ui, sourcePart)
	local ok, cloneOrErr = pcall(function()
		return sourcePart:Clone()
	end)
	if not ok or not cloneOrErr or not cloneOrErr:IsA("BasePart") then
		minimapDebugLog("mesh clone failed: source=%s error=%s", describePart(sourcePart), tostring(cloneOrErr))
		return false
	end

	local clone = cloneOrErr
	local color, material = getMinimapSurfaceStyle(sourcePart)
	clone.Name = sourcePart.Name
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.CastShadow = false
	clone.Transparency = 0
	clone.Color = color
	clone.Material = material
	clone.CFrame = clone.CFrame + Vector3.new(0, MINIMAP_ROAD_LIFT, 0)
	clone.Parent = ui.meshRoadModel
	table.insert(ui.meshClones, clone)
	if #ui.meshClones <= MAX_SOURCE_DEBUG_PARTS then
		minimapDebugLog("mesh clone[%d]: source={%s} clone={%s}", #ui.meshClones, describePart(sourcePart), describePart(clone))
	end
	return true
end

local function buildRoadUi(ui, mapData)
	clearLayer(ui.roadLayer)
	clearMeshWorld(ui)

	local roadItems = {}
	if not mapData then
		ui.meshViewport.Visible = false
		return roadItems
	end

	local hasMesh = false
	if mapData.meshParts and #mapData.meshParts > 0 then
		local failedClones = 0
		for _, part in ipairs(mapData.meshParts) do
			if not addMeshClone(ui, part) then
				failedClones += 1
			end
		end
		ui.meshViewport.Visible = #ui.meshClones > 0
		hasMesh = ui.meshViewport.Visible
		minimapDebugLog(
			"buildRoadUi: source=%s sourceParts=%d clonedParts=%d failedClones=%d meshViewportVisible=%s",
			tostring(mapData.source),
			#mapData.meshParts,
			#ui.meshClones,
			failedClones,
			tostring(ui.meshViewport.Visible)
		)
	end

	if not hasMesh then
		ui.meshViewport.Visible = false
		minimapDebugLog(
			"buildRoadUi: using 2D fallback source=%s graph=%s segments=%d junctionSegments=%d",
			tostring(mapData.source),
			tostring(mapData.graph ~= nil),
			#(mapData.segments or {}),
			#(mapData.junctionSegments or {})
		)
	end

	local segments = {}
	local allowSegmentFallback = mapData.graph == nil or not hasMesh
	if not hasMesh and allowSegmentFallback then
		for _, segment in ipairs(mapData.segments or {}) do
			table.insert(segments, segment)
		end
	end
	if allowSegmentFallback then
		for _, segment in ipairs(mapData.junctionSegments or {}) do
			table.insert(segments, segment)
		end
	end

	for _, segment in ipairs(segments) do
		local frame = Instance.new("Frame")
		frame.Name = segment.pixelWidth and "JunctionBoundary" or "Road"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundColor3 = segment.color or MINIMAP_ROAD_COLOR
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.ZIndex = segment.pixelWidth and 3 or 2
		frame.Parent = ui.roadLayer

		table.insert(roadItems, {
			frame = frame,
			ax = segment.ax,
			az = segment.az,
			bx = segment.bx,
			bz = segment.bz,
			width = segment.width,
			pixelWidth = segment.pixelWidth,
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

local function cabHasPassenger(cab)
	if not cab then
		return false
	end

	local modeAttribute = Config.passengerFareModeAttribute
	return type(modeAttribute) == "string" and cab:GetAttribute(modeAttribute) == "delivery"
end

local function getMinimapForward(forward)
	if typeof(forward) ~= "Vector3" then
		return Vector3.new(0, 0, -1)
	end

	local horizontal = Vector3.new(forward.X, 0, forward.Z)
	if horizontal.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return horizontal.Unit
end

local function getMinimapRight(mapForward)
	return Vector3.new(-mapForward.Z, 0, mapForward.X)
end

local function yawFromForward(forward)
	local mapForward = getMinimapForward(forward)
	return math.atan2(mapForward.X, mapForward.Z)
end

local function forwardFromYaw(yaw)
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

local function shortestAngleDelta(fromYaw, toYaw)
	return math.atan2(math.sin(toYaw - fromYaw), math.cos(toYaw - fromYaw))
end

local function relativeHeadingDegrees(forward, mapForward)
	return -math.deg(shortestAngleDelta(yawFromForward(mapForward), yawFromForward(forward)))
end

local function smoothForwardToward(currentForward, targetForward, dt)
	local smoothing = math.max(getConfigNumber("minimapRotationSmoothing", 2), 0)
	if smoothing <= 0 then
		return getMinimapForward(targetForward)
	end

	local currentYaw = yawFromForward(currentForward)
	local targetYaw = yawFromForward(targetForward)
	local alpha = 1 - math.exp(-smoothing * math.max(dt, 0))
	return forwardFromYaw(currentYaw + shortestAngleDelta(currentYaw, targetYaw) * alpha)
end

local function isJunctionNode(graph, node)
	if not (graph and node) then
		return false
	end

	local outgoing = {}
	for _, edge in ipairs(graph.edges or {}) do
		local otherNodeId = nil
		if edge.source == node.id then
			otherNodeId = edge.target
		elseif edge.target == node.id then
			otherNodeId = edge.source
		end

		local otherNode = otherNodeId and graph.nodeLookup and graph.nodeLookup[otherNodeId]
		if otherNode and typeof(otherNode.point) == "Vector3" then
			local offset = Vector3.new(otherNode.point.X - node.point.X, 0, otherNode.point.Z - node.point.Z)
			if offset.Magnitude > 0.001 then
				table.insert(outgoing, offset.Unit)
			end
		end
	end

	if #outgoing ~= 2 then
		return #outgoing > 0
	end
	return outgoing[1]:Dot(outgoing[2]) > -0.95
end

local function positionIsInJunction(mapData, position)
	local graph = mapData and mapData.graph
	if not graph then
		return false
	end

	local holdDistance = math.max(getConfigNumber("minimapJunctionOrientationHoldStuds", 72), 0)
	local holdDistanceSq = holdDistance * holdDistance
	if holdDistanceSq <= 0 then
		return false
	end

	for _, node in ipairs(graph.nodes or {}) do
		if typeof(node.point) == "Vector3" and isJunctionNode(graph, node) then
			local dx = position.X - node.point.X
			local dz = position.Z - node.point.Z
			if dx * dx + dz * dz <= holdDistanceSq then
				return true
			end
		end
	end

	return false
end

local function closestRoadForward(mapData, position, referenceForward)
	if positionIsInJunction(mapData, position) then
		return nil
	end

	local bestForward = nil
	local bestDistanceSq = math.huge
	local px = position.X
	local pz = position.Z
	local reference = getMinimapForward(referenceForward)

	for _, segment in ipairs(mapData and mapData.segments or {}) do
		local ax = tonumber(segment.ax)
		local az = tonumber(segment.az)
		local bx = tonumber(segment.bx)
		local bz = tonumber(segment.bz)
		if ax and az and bx and bz then
			local dx = bx - ax
			local dz = bz - az
			local lengthSq = dx * dx + dz * dz
			if lengthSq > 0.25 then
				local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / lengthSq, 0, 1)
				local cx = ax + dx * t
				local cz = az + dz * t
				local distanceSq = (px - cx) * (px - cx) + (pz - cz) * (pz - cz)
				if distanceSq < bestDistanceSq then
					local forward = Vector3.new(dx, 0, dz).Unit
					if forward:Dot(reference) < 0 then
						forward = -forward
					end
					bestForward = forward
					bestDistanceSq = distanceSq
				end
			end
		end
	end

	return bestForward
end

local function getPlayerScreenY(viewportHeight)
	local scale = math.clamp(getConfigNumber("minimapPlayerVerticalScale", 2 / 3), 0.5, 0.85)
	return viewportHeight * scale
end

local function projectToMinimap(position, playerPosition, mapForward, mapRight, halfWidth, playerScreenY, scale)
	local offset = Vector3.new(position.X - playerPosition.X, 0, position.Z - playerPosition.Z)
	return halfWidth + offset:Dot(mapRight) * scale, playerScreenY - offset:Dot(mapForward) * scale
end

local function updateRoadSegment(item, playerPosition, mapForward, mapRight, scale, halfWidth, playerScreenY, viewportWidth, viewportHeight)
	local a = Vector3.new(item.ax, playerPosition.Y, item.az)
	local b = Vector3.new(item.bx, playerPosition.Y, item.bz)
	local ax, ay = projectToMinimap(a, playerPosition, mapForward, mapRight, halfWidth, playerScreenY, scale)
	local bx, by = projectToMinimap(b, playerPosition, mapForward, mapRight, halfWidth, playerScreenY, scale)
	local dx = bx - ax
	local dy = by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	local roadPixels = item.pixelWidth or math.clamp(
		item.width * scale,
		getConfigNumber("minimapRoadMinPixels", 3),
		getConfigNumber("minimapRoadMaxPixels", 16)
	)

	local visible = length >= 1
		and math.max(ax, bx) >= 0
		and math.min(ax, bx) <= viewportWidth
		and math.max(ay, by) >= 0
		and math.min(ay, by) <= viewportHeight
	if not visible then
		item.frame.Visible = false
		return
	end

	setClippedLineFrame(item.frame, ax, ay, bx, by, roadPixels, viewportWidth, viewportHeight)
end

local function updateMeshViewport(ui, playerPosition, mapForward, worldSpan)
	if #ui.meshClones == 0 then
		ui.meshViewport.Visible = false
		return
	end

	local fieldOfView = math.rad(ui.meshCamera.FieldOfView)
	local cameraHeight = worldSpan / (2 * math.tan(fieldOfView * 0.5))
	local playerVerticalScale = math.clamp(getConfigNumber("minimapPlayerVerticalScale", 2 / 3), 0.5, 0.85)
	local targetOffset = (playerVerticalScale - 0.5) * worldSpan
	local target = Vector3.new(playerPosition.X, playerPosition.Y, playerPosition.Z) + mapForward * targetOffset
	ui.meshCamera.CFrame = CFrame.lookAt(
		target + Vector3.new(0, cameraHeight, 0),
		target,
		mapForward
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

local function markerHasVisibleParts(marker)
	for _, descendant in ipairs(marker:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.99 then
			return true
		end
	end

	return false
end

local function getPickupMarkerPosition(marker)
	if marker:IsA("BasePart") then
		return marker.Position
	end

	if marker:IsA("Model") then
		local ok, cframe = pcall(function()
			return marker:GetBoundingBox()
		end)
		if ok and typeof(cframe) == "CFrame" then
			return cframe.Position
		end
	end

	return nil
end

local function collectPassengerPickupPositions(world)
	local markerFolder = world and world:FindFirstChild(getConfigString("passengerMarkersFolderName", "PassengerMarkers"))
	if not markerFolder then
		return {}
	end

	local markerInstances = markerFolder:GetChildren()
	table.sort(markerInstances, function(a, b)
		return a.Name < b.Name
	end)

	local positions = {}
	for _, marker in ipairs(markerInstances) do
		if marker:GetAttribute("PickupStopId") ~= nil then
			local visibleAttribute = marker:GetAttribute("Visible")
			local visible = if visibleAttribute ~= nil then visibleAttribute == true else markerHasVisibleParts(marker)
			if visible then
				local position = getPickupMarkerPosition(marker)
				if position then
					table.insert(positions, position)
				end
			end
		end
	end

	return positions
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

local function createViewportRoutePart(parent, name)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Color = MINIMAP_ROUTE_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function ensureViewportRouteParts(ui, count)
	while #ui.routeMeshParts < count do
		table.insert(
			ui.routeMeshParts,
			createViewportRoutePart(ui.meshRouteModel, string.format("RouteSegment_%02d", #ui.routeMeshParts + 1))
		)
	end
end

local function hideViewportDestinationGuide(ui)
	for _, part in ipairs(ui.routeMeshParts) do
		part.Transparency = 1
	end
	if ui.destinationMeshMarker then
		ui.destinationMeshMarker.Transparency = 1
	end
end

local function updateViewportDestinationMarker(ui, cab, scale)
	local destination = getCabDestination(cab)
	if not destination then
		if ui.destinationMeshMarker then
			ui.destinationMeshMarker.Transparency = 1
		end
		return
	end

	if not ui.destinationMeshMarker then
		ui.destinationMeshMarker = createViewportRoutePart(ui.meshRouteModel, "DestinationMarker")
	end

	local markerSize = math.max(getConfigNumber("minimapDestinationMarkerPixels", 16), 8)
	local markerStuds = math.max(markerSize / math.max(scale, 0.001), 8)
	local marker = ui.destinationMeshMarker
	marker.Color = MINIMAP_ROUTE_COLOR
	marker.Material = Enum.Material.SmoothPlastic
	marker.Size = Vector3.new(markerStuds, 0.35, markerStuds)
	marker.CFrame = CFrame.new(destination + Vector3.new(0, MINIMAP_ROUTE_LIFT + 0.4, 0))
		* CFrame.Angles(0, math.rad(45), 0)
	marker.Transparency = 0
end

local function updateViewportDestinationGuide(ui, world, cab, scale)
	hideViewportDestinationGuide(ui)

	local routeParts = getWorldRouteSegmentParts(world)
	ensureViewportRouteParts(ui, #routeParts)

	local routeWidthPixels = math.max(getConfigNumber("minimapRouteLinePixels", 4) * 3, 12)
	local routeWidthStuds = math.max(routeWidthPixels / math.max(scale, 0.001), 14)
	for index, sourcePart in ipairs(routeParts) do
		local routePart = ui.routeMeshParts[index]
		routePart.Color = MINIMAP_ROUTE_COLOR
		routePart.Material = Enum.Material.SmoothPlastic
		routePart.Size = Vector3.new(routeWidthStuds, 0.45, sourcePart.Size.Z)
		routePart.CFrame = sourcePart.CFrame + Vector3.new(0, MINIMAP_ROUTE_LIFT, 0)
		routePart.Transparency = 0
	end

	updateViewportDestinationMarker(ui, cab, scale)
end

local function ensureRouteSegmentFrames(ui, count)
	while #ui.routeSegments < count do
		local frame = Instance.new("Frame")
		frame.Name = string.format("RouteSegment_%02d", #ui.routeSegments + 1)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundColor3 = MINIMAP_ROUTE_COLOR
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

local function updateMinimapRouteSegment(
	frame,
	part,
	playerPosition,
	mapForward,
	mapRight,
	scale,
	halfWidth,
	playerScreenY,
	viewportWidth,
	viewportHeight
)
	local halfLength = part.Size.Z * 0.5
	local center = part.Position
	local direction = part.CFrame.LookVector
	local a = center - direction * halfLength
	local b = center + direction * halfLength
	local ax, ay = projectToMinimap(a, playerPosition, mapForward, mapRight, halfWidth, playerScreenY, scale)
	local bx, by = projectToMinimap(b, playerPosition, mapForward, mapRight, halfWidth, playerScreenY, scale)
	local dx = bx - ax
	local dy = by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	local linePixels = math.max(getConfigNumber("minimapRouteLinePixels", 4) * 3, 12)
	local visible = length >= 1
		and math.max(ax, bx) >= 0
		and math.min(ax, bx) <= viewportWidth
		and math.max(ay, by) >= 0
		and math.min(ay, by) <= viewportHeight
	if not visible then
		frame.Visible = false
		return
	end

	frame.BackgroundColor3 = MINIMAP_ROUTE_COLOR
	setClippedLineFrame(frame, ax, ay, bx, by, linePixels, viewportWidth, viewportHeight)
end

local function updateDestinationMarker(
	ui,
	cab,
	playerPosition,
	mapForward,
	mapRight,
	scale,
	viewportWidth,
	viewportHeight,
	halfWidth,
	playerScreenY
)
	local destination = getCabDestination(cab)
	if not destination then
		return
	end

	local targetX, targetY = projectToMinimap(destination, playerPosition, mapForward, mapRight, halfWidth, playerScreenY, scale)
	local markerSize = math.max(getConfigNumber("minimapDestinationMarkerPixels", 16), 8)
	local padding = markerSize * 0.5 + 4
	local routeColor = MINIMAP_ROUTE_COLOR
	local visible = targetX - padding >= 0
		and targetX + padding <= viewportWidth
		and targetY - padding >= 0
		and targetY + padding <= viewportHeight

	ui.destinationMarker.BackgroundColor3 = routeColor
	ui.destinationMarker.Position = UDim2.fromOffset(targetX, targetY)
	ui.destinationMarker.Size = UDim2.fromOffset(markerSize, markerSize)
	ui.destinationMarker.Visible = visible
end

local function updateDestinationGuide(
	ui,
	world,
	cab,
	playerPosition,
	mapForward,
	mapRight,
	scale,
	halfWidth,
	playerScreenY,
	viewportWidth,
	viewportHeight
)
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
			mapForward,
			mapRight,
			scale,
			halfWidth,
			playerScreenY,
			viewportWidth,
			viewportHeight
		)
	end

	for index = #routeParts + 1, #ui.routeSegments do
		ui.routeSegments[index].Visible = false
	end

	updateDestinationMarker(ui, cab, playerPosition, mapForward, mapRight, scale, viewportWidth, viewportHeight, halfWidth, playerScreenY)
end

local function createPassengerPickupMarker(parent, index)
	local marker = Instance.new("Frame")
	marker.Name = string.format("PassengerPickupMarker_%02d", index)
	marker.AnchorPoint = Vector2.new(0.5, 1)
	marker.BackgroundTransparency = 1
	marker.BorderSizePixel = 0
	marker.Visible = false
	marker.ZIndex = 4
	marker.Parent = parent

	local tip = Instance.new("Frame")
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(0.5, 0.72)
	tip.Size = UDim2.fromScale(0.5, 0.4)
	tip.BackgroundColor3 = getConfigColor("passengerPickupColor", Color3.fromRGB(70, 255, 120))
	tip.BorderSizePixel = 0
	tip.Rotation = 45
	tip.ZIndex = 4
	tip.Parent = marker

	local tipStroke = Instance.new("UIStroke")
	tipStroke.Color = MINIMAP_PASSENGER_MARKER_STROKE
	tipStroke.Transparency = 0.12
	tipStroke.Thickness = 1.5
	tipStroke.Parent = tip

	local head = Instance.new("Frame")
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0)
	head.Size = UDim2.fromScale(0.86, 0.68)
	head.BackgroundColor3 = getConfigColor("passengerPickupColor", Color3.fromRGB(70, 255, 120))
	head.BorderSizePixel = 0
	head.ZIndex = 5
	head.Parent = marker

	local headCorner = Instance.new("UICorner")
	headCorner.CornerRadius = UDim.new(1, 0)
	headCorner.Parent = head

	local headStroke = Instance.new("UIStroke")
	headStroke.Color = MINIMAP_PASSENGER_MARKER_STROKE
	headStroke.Transparency = 0.08
	headStroke.Thickness = 1.5
	headStroke.Parent = head

	return marker
end

local function ensurePassengerPickupMarkers(ui, count)
	while #ui.passengerMarkers < count do
		table.insert(ui.passengerMarkers, createPassengerPickupMarker(ui.passengerLayer, #ui.passengerMarkers + 1))
	end
end

local function hidePassengerPickupMarkers(ui)
	for _, marker in ipairs(ui.passengerMarkers) do
		marker.Visible = false
	end
end

local function updatePassengerPickupMarkers(
	ui,
	world,
	cab,
	playerPosition,
	mapForward,
	mapRight,
	scale,
	halfWidth,
	playerScreenY,
	viewportWidth,
	viewportHeight
)
	if cabHasPassenger(cab) then
		hidePassengerPickupMarkers(ui)
		return
	end

	local positions = collectPassengerPickupPositions(world)
	ensurePassengerPickupMarkers(ui, #positions)

	local markerColor = getConfigColor("passengerPickupColor", Color3.fromRGB(70, 255, 120))
	local markerWidth = math.max(getConfigNumber("minimapPassengerMarkerPixels", 16), 10)
	local markerHeight = markerWidth * 1.25
	local paddingX = markerWidth * 0.5
	local paddingY = markerHeight
	local visibleCount = 0

	for _, position in ipairs(positions) do
		local x, y = projectToMinimap(position, playerPosition, mapForward, mapRight, halfWidth, playerScreenY, scale)
		if x + paddingX >= 0 and x - paddingX <= viewportWidth and y + paddingY >= 0 and y <= viewportHeight then
			visibleCount += 1
			local marker = ui.passengerMarkers[visibleCount]
			marker.Position = UDim2.fromOffset(x, y)
			marker.Size = UDim2.fromOffset(markerWidth, markerHeight)
			marker.Visible = true

			local head = marker:FindFirstChild("Head")
			local tip = marker:FindFirstChild("Tip")
			if head and head:IsA("Frame") then
				head.BackgroundColor3 = markerColor
			end
			if tip and tip:IsA("Frame") then
				tip.BackgroundColor3 = markerColor
			end
		end
	end

	for index = visibleCount + 1, #ui.passengerMarkers do
		ui.passengerMarkers[index].Visible = false
	end
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
	local orientationPollAccumulator = math.huge
	local orientationTargetForward = nil
	local orientationForward = nil
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
		orientationPollAccumulator = math.huge
		minimapDebugLog(
			"rebuild complete: world=%s mapSource=%s roadItems=%d meshClones=%d",
			watchedWorld and watchedWorld:GetFullName() or "nil",
			currentMap and tostring(currentMap.source) or "nil",
			#roadItems,
			#ui.meshClones
		)
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
		minimapDebugLog("watchWorld: %s", watchedWorld and watchedWorld:GetFullName() or "nil")
		currentMap = nil
		orientationTargetForward = nil
		orientationForward = nil
		orientationPollAccumulator = math.huge
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
					or child.Name == RUNTIME_GRAPH_DATA_NAME
					or child.Name == GENERATED_ROADS_NAME
					or child.Name == BAKED_ROAD_GRAPH_RUNTIME_NAME
					or child.Name == BAKED_ROAD_GRAPH_SURFACES_NAME
					or child.Name == ROAD_GRAPH_SURFACES_NAME
					or child.Name == LEGACY_ROAD_NETWORK_NAME
					or child.Name == MINIMAP_ROAD_MESH_NAME
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
			watchMapContainer(watchedWorld:FindFirstChild(RUNTIME_GRAPH_DATA_NAME))
			watchMapContainer(watchedWorld:FindFirstChild(GENERATED_ROADS_NAME))
			watchMapContainer(watchedWorld:FindFirstChild(BAKED_ROAD_GRAPH_RUNTIME_NAME))
			watchMapContainer(watchedWorld:FindFirstChild(BAKED_ROAD_GRAPH_SURFACES_NAME))
			watchMapContainer(watchedWorld:FindFirstChild(ROAD_GRAPH_SURFACES_NAME))
			watchMapContainer(watchedWorld:FindFirstChild(LEGACY_ROAD_NETWORK_NAME))
			watchMapContainer(watchedWorld:FindFirstChild(MINIMAP_ROAD_MESH_NAME))
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
		local frameDt = updateAccumulator
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
		local playerScreenY = getPlayerScreenY(viewportSize.Y)
		local fallbackForward = getMinimapForward(forward)
		local orientationPollSeconds = math.max(getConfigNumber("minimapRoadOrientationPollSeconds", 0.2), 0.05)
		orientationPollAccumulator += frameDt
		if orientationPollAccumulator >= orientationPollSeconds or not orientationTargetForward then
			orientationPollAccumulator = 0
			local referenceForward = orientationTargetForward or fallbackForward
			if not orientationTargetForward or math.abs(orientationTargetForward:Dot(fallbackForward)) > 0.35 then
				referenceForward = fallbackForward
			end
			local sampledRoadForward = closestRoadForward(currentMap, playerPosition, referenceForward)
			if sampledRoadForward then
				orientationTargetForward = sampledRoadForward
			elseif not orientationTargetForward then
				orientationTargetForward = fallbackForward
			end
		end
		orientationForward = if orientationForward
			then smoothForwardToward(orientationForward, orientationTargetForward, frameDt)
			else orientationTargetForward
		local mapForward = orientationForward
		local mapRight = getMinimapRight(mapForward)

		if #ui.meshClones > 0 then
			updateMeshViewport(ui, playerPosition, mapForward, span)
			updateViewportDestinationGuide(ui, watchedWorld, cab, scale)
			hideDestinationGuide(ui)
		else
			ui.meshViewport.Visible = false
			hideViewportDestinationGuide(ui)
			for _, item in ipairs(roadItems) do
				updateRoadSegment(
					item,
					playerPosition,
					mapForward,
					mapRight,
					scale,
					halfWidth,
					playerScreenY,
					viewportSize.X,
					viewportSize.Y
				)
			end
			updateDestinationGuide(
				ui,
				watchedWorld,
				cab,
				playerPosition,
				mapForward,
				mapRight,
				scale,
				halfWidth,
				playerScreenY,
				viewportSize.X,
				viewportSize.Y
			)
		end

		updatePassengerPickupMarkers(
			ui,
			watchedWorld,
			cab,
			playerPosition,
			mapForward,
			mapRight,
			scale,
			halfWidth,
			playerScreenY,
			viewportSize.X,
			viewportSize.Y
		)

		ui.playerMarker.Position = UDim2.fromOffset(halfWidth, playerScreenY)
		ui.playerMarker.Rotation = relativeHeadingDegrees(fallbackForward, mapForward)
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
