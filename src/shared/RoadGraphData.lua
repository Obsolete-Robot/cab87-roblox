local HttpService = game:GetService("HttpService")

local RoadSampling = require(script.Parent:WaitForChild("RoadSampling"))

local RoadGraphData = {}

RoadGraphData.SCHEMA = "cab87-road-network"
RoadGraphData.VERSION = 2
RoadGraphData.EDITOR_ROOT_NAME = "Cab87RoadEditor"
RoadGraphData.ROAD_GRAPH_NAME = "RoadGraph"
RoadGraphData.RUNTIME_DATA_NAME = "AuthoredRoadGraphData"
RoadGraphData.NODES_NAME = "Nodes"
RoadGraphData.EDGES_NAME = "Edges"
RoadGraphData.EDGE_POINTS_NAME = "Points"
RoadGraphData.POLYGON_FILLS_NAME = "PolygonFills"
RoadGraphData.POLYGON_FILL_POINTS_NAME = "Points"
RoadGraphData.BUILDINGS_NAME = "Buildings"
RoadGraphData.BUILDING_VERTICES_NAME = "Vertices"

local DEFAULT_CHAMFER_ANGLE_DEG = 70
local DEFAULT_SIDEWALK_WIDTH = 12
local DEFAULT_MESH_RESOLUTION = 20
local DEFAULT_IMPORT_SCALE = 1
local DEFAULT_BUILDING_BASE_ELEVATION = 4
local DEFAULT_BUILDING_HEIGHT = 80
local DEFAULT_BUILDING_COLOR = "#64748b"
local DEFAULT_BUILDING_MATERIAL = "Concrete"

local function finiteNumber(value)
	local number = tonumber(value)
	if number and number == number and number ~= math.huge and number ~= -math.huge then
		return number
	end
	return nil
end

local function sanitizeId(value, prefix, index)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return string.format("%s%d", prefix, index)
end

local function sanitizeName(value, fallback)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function sanitizeColor(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function sanitizePositiveNumber(value, fallback)
	local number = finiteNumber(value)
	if number and number > 0 then
		return number
	end
	return fallback
end

local function sanitizePolygonFills(fills, nodeLookup)
	local normalized = {}
	if type(fills) ~= "table" then
		return normalized
	end

	for index, fill in ipairs(fills) do
		if type(fill) == "table" and type(fill.points) == "table" then
			local points = {}
			local used = {}
			for _, nodeId in ipairs(fill.points) do
				if type(nodeId) == "string" and nodeLookup[nodeId] and not used[nodeId] then
					table.insert(points, nodeId)
					used[nodeId] = true
				end
			end

			if #points >= 3 then
				table.insert(normalized, {
					id = sanitizeId(fill.id, "pf", index),
					points = points,
					color = sanitizeColor(fill.color) or "#10b981",
				})
			end
		end
	end

	return normalized
end

local function clonePolygonFills(fills, nodeLookup)
	local cloned = {}
	for index, fill in ipairs(fills or {}) do
		if type(fill) == "table" then
			local points = {}
			local used = {}
			for _, nodeId in ipairs(fill.points or {}) do
				if type(nodeId) == "string" and (not nodeLookup or nodeLookup[nodeId]) and not used[nodeId] then
					table.insert(points, nodeId)
					used[nodeId] = true
				end
			end

			if #points >= 3 then
				table.insert(cloned, {
					id = sanitizeId(fill.id, "pf", index),
					points = points,
					color = sanitizeColor(fill.color) or "#10b981",
				})
			end
		end
	end
	return cloned
end

local graphPointToVector

local function sanitizeBuildingMaterial(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return DEFAULT_BUILDING_MATERIAL
end

local function sanitizeBuildings(buildings, planeY)
	local normalized = {}
	if type(buildings) ~= "table" then
		return normalized
	end

	for index, building in ipairs(buildings) do
		if type(building) == "table" and type(building.vertices) == "table" then
			local baseZ = finiteNumber(building.baseZ) or DEFAULT_BUILDING_BASE_ELEVATION
			local vertices = {}
			for _, vertex in ipairs(building.vertices) do
				local point = graphPointToVector({
					x = vertex.x,
					y = vertex.y,
					z = baseZ,
				}, planeY)
				if point then
					local previous = vertices[#vertices]
					if not previous or (previous - point).Magnitude > 0.01 then
						table.insert(vertices, point)
					end
				end
			end

			if #vertices > 2 and (vertices[1] - vertices[#vertices]).Magnitude <= 0.01 then
				table.remove(vertices)
			end

			if #vertices >= 3 then
				table.insert(normalized, {
					id = sanitizeId(building.id, "b", index),
					name = sanitizeName(building.name, nil),
					vertices = vertices,
					baseZ = baseZ,
					height = sanitizePositiveNumber(building.height, DEFAULT_BUILDING_HEIGHT),
					color = sanitizeColor(building.color) or DEFAULT_BUILDING_COLOR,
					material = sanitizeBuildingMaterial(building.material),
				})
			end
		end
	end

	return normalized
end

local function cloneBuildings(buildings)
	local cloned = {}
	for index, building in ipairs(buildings or {}) do
		if type(building) == "table" and type(building.vertices) == "table" then
			local vertices = {}
			for _, vertex in ipairs(building.vertices) do
				if typeof(vertex) == "Vector3" then
					table.insert(vertices, vertex)
				end
			end

			if #vertices >= 3 then
				table.insert(cloned, {
					id = sanitizeId(building.id, "b", index),
					name = sanitizeName(building.name, nil),
					vertices = vertices,
					baseZ = finiteNumber(building.baseZ) or DEFAULT_BUILDING_BASE_ELEVATION,
					height = sanitizePositiveNumber(building.height, DEFAULT_BUILDING_HEIGHT),
					color = sanitizeColor(building.color) or DEFAULT_BUILDING_COLOR,
					material = sanitizeBuildingMaterial(building.material),
				})
			end
		end
	end
	return cloned
end

local function sanitizeScale(value)
	local number = finiteNumber(value) or DEFAULT_IMPORT_SCALE
	return math.max(number, 0.001)
end

local function scaleNumber(value, scale)
	local number = finiteNumber(value)
	if number then
		return number * scale
	end
	return nil
end

graphPointToVector = function(point, planeY, pointScale)
	if type(point) ~= "table" then
		return nil
	end

	local scale = sanitizeScale(pointScale)
	local x = finiteNumber(point.x)
	local horizontalZ = finiteNumber(point.y)
	local elevation = finiteNumber(point.elevation)
	if horizontalZ then
		if elevation == nil then
			elevation = finiteNumber(point.z) or 0
		end
	else
		horizontalZ = finiteNumber(point.z)
		elevation = elevation or 0
	end
	if not (x and horizontalZ) then
		return nil
	end

	return Vector3.new(x * scale, (finiteNumber(planeY) or 0) + elevation * scale, horizontalZ * scale)
end

local function vectorToGraphPoint(position, planeY)
	local elevation = position.Y - (finiteNumber(planeY) or 0)
	return {
		x = position.X,
		y = position.Z,
		z = elevation,
		elevation = elevation,
	}
end

local function scaleVectorFromPlane(position, planeY, pointScale)
	local baseY = finiteNumber(planeY) or 0
	return Vector3.new(position.X * pointScale, baseY + (position.Y - baseY) * pointScale, position.Z * pointScale)
end

local function childFolders(parent, name)
	local child = parent and parent:FindFirstChild(name)
	if child and child:IsA("Folder") then
		return child
	end
	return nil
end

local function sortedChildren(parent)
	local children = {}
	if not parent then
		return children
	end

	for _, child in ipairs(parent:GetChildren()) do
		table.insert(children, child)
	end
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)
	return children
end

local function graphFolderFromRoot(root)
	if not root then
		return nil
	end

	if root.Name == RoadGraphData.ROAD_GRAPH_NAME or root.Name == RoadGraphData.RUNTIME_DATA_NAME then
		return root
	end

	local runtimeData = root:FindFirstChild(RoadGraphData.RUNTIME_DATA_NAME)
	if runtimeData and runtimeData:IsA("Folder") then
		return runtimeData
	end

	local graphData = root:FindFirstChild(RoadGraphData.ROAD_GRAPH_NAME)
	if graphData and graphData:IsA("Folder") then
		return graphData
	end

	return nil
end

function RoadGraphData.defaultSettings(config)
	return {
		chamferAngleDeg = finiteNumber(config and config.roadGraphDefaultChamferAngleDeg) or DEFAULT_CHAMFER_ANGLE_DEG,
		crosswalkWidth = finiteNumber(config and config.roadGraphDefaultCrosswalkWidth) or 14,
		sidewalkWidth = finiteNumber(config and config.roadGraphDefaultSidewalkWidth) or DEFAULT_SIDEWALK_WIDTH,
		meshResolution = finiteNumber(config and config.roadGraphMeshResolution)
			or finiteNumber(config and config.roadGraphSplineSegments)
			or DEFAULT_MESH_RESOLUTION,
	}
end

function RoadGraphData.decodeJson(text, options)
	local ok, payloadOrErr = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if not ok then
		return nil, "JSON decode failed: " .. tostring(payloadOrErr)
	end

	return RoadGraphData.normalizePayload(payloadOrErr, options)
end

function RoadGraphData.normalizePayload(payload, options)
	options = options or {}
	if type(payload) ~= "table" then
		return nil, "Road graph JSON root must be an object"
	end

	if payload.schema ~= nil and payload.schema ~= RoadGraphData.SCHEMA then
		return nil, string.format("Unsupported road graph schema %s", tostring(payload.schema))
	end

	local nodes = payload.nodes
	local edges = payload.edges
	if type(nodes) ~= "table" or type(edges) ~= "table" then
		return nil, "Road graph JSON must include nodes and edges arrays"
	end

	local planeY = finiteNumber(options.planeY) or finiteNumber(payload.importPlaneY) or 0
	local pointScale = sanitizeScale(options.pointScale)
	local widthScale = sanitizeScale(options.widthScale)
	local settings = RoadGraphData.defaultSettings(options.config)
	if type(payload.settings) == "table" then
		settings.chamferAngleDeg = finiteNumber(payload.settings.chamferAngleDeg) or settings.chamferAngleDeg
		settings.crosswalkWidth = finiteNumber(payload.settings.crosswalkWidth) or settings.crosswalkWidth
		settings.sidewalkWidth = finiteNumber(payload.settings.sidewalkWidth) or settings.sidewalkWidth
		settings.meshResolution = finiteNumber(payload.settings.meshResolution)
			or finiteNumber(payload.settings.splineSegments)
			or settings.meshResolution
	end

	local normalizedNodes = {}
	local nodeLookup = {}
	for index, node in ipairs(nodes) do
		if type(node) == "table" then
			local nodeId = sanitizeId(node.id, "n", index)
			local position = graphPointToVector(node.point, planeY)
			if position and not nodeLookup[nodeId] then
				local normalized = {
					id = nodeId,
					point = position,
					transitionSmoothness = finiteNumber(node.transitionSmoothness),
					ignoreMeshing = node.ignoreMeshing == true,
				}
				table.insert(normalizedNodes, normalized)
				nodeLookup[nodeId] = normalized
			end
		end
	end

	local normalizedEdges = {}
	for index, edge in ipairs(edges) do
		if type(edge) == "table" then
			local source = type(edge.source) == "string" and edge.source or nil
			local target = type(edge.target) == "string" and edge.target or nil
			if source and nodeLookup[source] and (target == nil or nodeLookup[target]) then
				local controlPoints = {}
				if type(edge.points) == "table" then
					for _, point in ipairs(edge.points) do
						local position = graphPointToVector(point, planeY)
						if position then
							table.insert(controlPoints, position)
						end
					end
				end

				table.insert(normalizedEdges, {
					id = sanitizeId(edge.id, "e", index),
					source = source,
					target = target,
					points = controlPoints,
					width = RoadSampling.sanitizeRoadWidth(edge.width),
					sidewalk = math.max(finiteNumber(edge.sidewalk) or settings.sidewalkWidth, 0),
					sidewalkLeft = finiteNumber(edge.sidewalkLeft),
					sidewalkRight = finiteNumber(edge.sidewalkRight),
					transitionSmoothness = finiteNumber(edge.transitionSmoothness),
					color = sanitizeColor(edge.color),
					name = sanitizeName(edge.name, nil),
				})
			end
		end
	end

	if #normalizedNodes == 0 then
		return nil, "Road graph did not include any valid nodes"
	end
	if #normalizedEdges == 0 then
		return nil, "Road graph did not include any valid edges"
	end

	local graph = {
		schema = RoadGraphData.SCHEMA,
		version = RoadGraphData.VERSION,
		planeY = planeY,
		importPointScale = pointScale,
		importWidthScale = widthScale,
		settings = settings,
		nodes = normalizedNodes,
		edges = normalizedEdges,
		polygonFills = sanitizePolygonFills(payload.polygonFills, nodeLookup),
		buildings = sanitizeBuildings(payload.buildings, planeY),
	}

	if pointScale ~= DEFAULT_IMPORT_SCALE or widthScale ~= DEFAULT_IMPORT_SCALE then
		return RoadGraphData.scaleGraph(graph, {
			pointScale = pointScale,
			widthScale = widthScale,
		}), nil
	end

	return graph, nil
end

function RoadGraphData.scaleGraph(graph, options)
	options = options or {}
	if type(graph) ~= "table" then
		return nil
	end

	local pointScale = sanitizeScale(options.pointScale or graph.importPointScale)
	local widthScale = sanitizeScale(options.widthScale or graph.importWidthScale)
	local planeY = finiteNumber(graph.planeY) or 0
	local settings = RoadGraphData.defaultSettings(options.config)
	if type(graph.settings) == "table" then
		settings.chamferAngleDeg = finiteNumber(graph.settings.chamferAngleDeg) or settings.chamferAngleDeg
		settings.crosswalkWidth = finiteNumber(graph.settings.crosswalkWidth) or settings.crosswalkWidth
		settings.sidewalkWidth = finiteNumber(graph.settings.sidewalkWidth) or settings.sidewalkWidth
		settings.meshResolution = finiteNumber(graph.settings.meshResolution)
			or finiteNumber(graph.settings.splineSegments)
			or settings.meshResolution
	end
	settings.crosswalkWidth *= widthScale
	settings.sidewalkWidth *= widthScale

	local nodes = {}
	local nodeLookup = {}
	for index, node in ipairs(graph.nodes or {}) do
		if type(node) == "table" and typeof(node.point) == "Vector3" then
			local nodeId = sanitizeId(node.id, "n", index)
			local scaledNode = {
				id = nodeId,
				point = scaleVectorFromPlane(node.point, planeY, pointScale),
				transitionSmoothness = scaleNumber(node.transitionSmoothness, pointScale),
				ignoreMeshing = node.ignoreMeshing == true,
			}
			table.insert(nodes, scaledNode)
			nodeLookup[nodeId] = scaledNode
		end
	end

	local edges = {}
	for index, edge in ipairs(graph.edges or {}) do
		if type(edge) == "table" then
			local points = {}
			for _, point in ipairs(edge.points or {}) do
				if typeof(point) == "Vector3" then
					table.insert(points, scaleVectorFromPlane(point, planeY, pointScale))
				end
			end

			local edgeSidewalk = scaleNumber(edge.sidewalk, widthScale) or settings.sidewalkWidth
			table.insert(edges, {
				id = sanitizeId(edge.id, "e", index),
				source = edge.source,
				target = edge.target,
				points = points,
				width = RoadSampling.sanitizeRoadWidth((finiteNumber(edge.width) or RoadSampling.DEFAULT_ROAD_WIDTH) * widthScale),
				sidewalk = math.max(edgeSidewalk, 0),
				sidewalkLeft = scaleNumber(edge.sidewalkLeft, widthScale),
				sidewalkRight = scaleNumber(edge.sidewalkRight, widthScale),
				transitionSmoothness = scaleNumber(edge.transitionSmoothness, pointScale),
				color = sanitizeColor(edge.color),
				name = sanitizeName(edge.name, nil),
			})
		end
	end

	local buildings = {}
	for index, building in ipairs(graph.buildings or {}) do
		if type(building) == "table" then
			local vertices = {}
			for _, vertex in ipairs(building.vertices or {}) do
				if typeof(vertex) == "Vector3" then
					table.insert(vertices, scaleVectorFromPlane(vertex, planeY, pointScale))
				end
			end

			if #vertices >= 3 then
				local baseZ = vertices[1].Y - planeY
				table.insert(buildings, {
					id = sanitizeId(building.id, "b", index),
					name = sanitizeName(building.name, nil),
					vertices = vertices,
					baseZ = baseZ,
					height = sanitizePositiveNumber(building.height, DEFAULT_BUILDING_HEIGHT) * pointScale,
					color = sanitizeColor(building.color) or DEFAULT_BUILDING_COLOR,
					material = sanitizeBuildingMaterial(building.material),
				})
			end
		end
	end

	return {
		schema = graph.schema or RoadGraphData.SCHEMA,
		version = tonumber(graph.version) or RoadGraphData.VERSION,
		planeY = planeY,
		importPointScale = pointScale,
		importWidthScale = widthScale,
		settings = settings,
		nodes = nodes,
		edges = edges,
		nodeLookup = nodeLookup,
		polygonFills = clonePolygonFills(graph.polygonFills, nodeLookup),
		buildings = buildings,
	}
end

function RoadGraphData.hasGraph(root)
	local graphFolder = graphFolderFromRoot(root)
	if not graphFolder then
		return false
	end

	local nodesFolder = childFolders(graphFolder, RoadGraphData.NODES_NAME)
	local edgesFolder = childFolders(graphFolder, RoadGraphData.EDGES_NAME)
	return nodesFolder ~= nil and edgesFolder ~= nil and #nodesFolder:GetChildren() > 0 and #edgesFolder:GetChildren() > 0
end

function RoadGraphData.clearGraph(root, name)
	local graphName = name or RoadGraphData.ROAD_GRAPH_NAME
	local existing = root and root:FindFirstChild(graphName)
	if existing then
		existing:Destroy()
	end
end

function RoadGraphData.writeGraph(root, graph, name)
	assert(root, "RoadGraphData.writeGraph requires a root Instance")
	assert(graph, "RoadGraphData.writeGraph requires graph data")

	local graphName = name or RoadGraphData.ROAD_GRAPH_NAME
	RoadGraphData.clearGraph(root, graphName)

	local graphFolder = Instance.new("Folder")
	graphFolder.Name = graphName
	graphFolder:SetAttribute("Schema", graph.schema or RoadGraphData.SCHEMA)
	graphFolder:SetAttribute("Version", tonumber(graph.version) or RoadGraphData.VERSION)
	graphFolder:SetAttribute("PlaneY", finiteNumber(graph.planeY) or 0)
	graphFolder:SetAttribute("ImportPointScale", sanitizeScale(graph.importPointScale))
	graphFolder:SetAttribute("ImportWidthScale", sanitizeScale(graph.importWidthScale))
	graphFolder:SetAttribute("ChamferAngleDeg", finiteNumber(graph.settings and graph.settings.chamferAngleDeg) or DEFAULT_CHAMFER_ANGLE_DEG)
	graphFolder:SetAttribute("CrosswalkWidth", finiteNumber(graph.settings and graph.settings.crosswalkWidth) or 14)
	graphFolder:SetAttribute("DefaultSidewalkWidth", finiteNumber(graph.settings and graph.settings.sidewalkWidth) or DEFAULT_SIDEWALK_WIDTH)
	graphFolder:SetAttribute(
		"MeshResolution",
		finiteNumber(graph.settings and graph.settings.meshResolution)
			or finiteNumber(graph.settings and graph.settings.splineSegments)
			or DEFAULT_MESH_RESOLUTION
	)
	graphFolder.Parent = root

	local nodesFolder = Instance.new("Folder")
	nodesFolder.Name = RoadGraphData.NODES_NAME
	nodesFolder.Parent = graphFolder

	for index, node in ipairs(graph.nodes or {}) do
		local nodeValue = Instance.new("Vector3Value")
		nodeValue.Name = sanitizeId(node.id, "n", index)
		nodeValue.Value = node.point
		nodeValue:SetAttribute("NodeId", sanitizeId(node.id, "n", index))
		if finiteNumber(node.transitionSmoothness) then
			nodeValue:SetAttribute("TransitionSmoothness", math.max(finiteNumber(node.transitionSmoothness), 0))
		end
		if node.ignoreMeshing == true then
			nodeValue:SetAttribute("IgnoreMeshing", true)
		end
		nodeValue.Parent = nodesFolder
	end

	local edgesFolder = Instance.new("Folder")
	edgesFolder.Name = RoadGraphData.EDGES_NAME
	edgesFolder.Parent = graphFolder

	for index, edge in ipairs(graph.edges or {}) do
		local edgeFolder = Instance.new("Folder")
		edgeFolder.Name = sanitizeId(edge.id, "e", index)
		edgeFolder:SetAttribute("EdgeId", sanitizeId(edge.id, "e", index))
		edgeFolder:SetAttribute("Source", edge.source)
		if edge.target then
			edgeFolder:SetAttribute("Target", edge.target)
		end
		edgeFolder:SetAttribute("Width", RoadSampling.sanitizeRoadWidth(edge.width))
		edgeFolder:SetAttribute("Sidewalk", math.max(finiteNumber(edge.sidewalk) or DEFAULT_SIDEWALK_WIDTH, 0))
		if finiteNumber(edge.sidewalkLeft) then
			edgeFolder:SetAttribute("SidewalkLeft", math.max(finiteNumber(edge.sidewalkLeft), 0))
		end
		if finiteNumber(edge.sidewalkRight) then
			edgeFolder:SetAttribute("SidewalkRight", math.max(finiteNumber(edge.sidewalkRight), 0))
		end
		if finiteNumber(edge.transitionSmoothness) then
			edgeFolder:SetAttribute("TransitionSmoothness", math.max(finiteNumber(edge.transitionSmoothness), 0))
		end
		if edge.color then
			edgeFolder:SetAttribute("Color", edge.color)
		end
		if edge.name then
			edgeFolder:SetAttribute("DisplayName", edge.name)
		end
		edgeFolder.Parent = edgesFolder

		local pointsFolder = Instance.new("Folder")
		pointsFolder.Name = RoadGraphData.EDGE_POINTS_NAME
		pointsFolder.Parent = edgeFolder
		for pointIndex, point in ipairs(edge.points or {}) do
			local pointValue = Instance.new("Vector3Value")
			pointValue.Name = string.format("P%04d", pointIndex)
			pointValue.Value = point
			pointValue.Parent = pointsFolder
		end
	end

	local polygonFills = clonePolygonFills(graph.polygonFills)
	if #polygonFills > 0 then
		local fillsFolder = Instance.new("Folder")
		fillsFolder.Name = RoadGraphData.POLYGON_FILLS_NAME
		fillsFolder.Parent = graphFolder

		for index, fill in ipairs(polygonFills) do
			local fillFolder = Instance.new("Folder")
			fillFolder.Name = sanitizeId(fill.id, "pf", index)
			fillFolder:SetAttribute("FillId", sanitizeId(fill.id, "pf", index))
			fillFolder:SetAttribute("Color", sanitizeColor(fill.color) or "#10b981")
			fillFolder.Parent = fillsFolder

			local pointsFolder = Instance.new("Folder")
			pointsFolder.Name = RoadGraphData.POLYGON_FILL_POINTS_NAME
			pointsFolder.Parent = fillFolder

			for pointIndex, nodeId in ipairs(fill.points or {}) do
				local pointValue = Instance.new("StringValue")
				pointValue.Name = string.format("P%04d", pointIndex)
				pointValue.Value = nodeId
				pointValue.Parent = pointsFolder
			end
		end
	end

	local buildings = cloneBuildings(graph.buildings)
	if #buildings > 0 then
		local buildingsFolder = Instance.new("Folder")
		buildingsFolder.Name = RoadGraphData.BUILDINGS_NAME
		buildingsFolder.Parent = graphFolder

		for index, building in ipairs(buildings) do
			local buildingFolder = Instance.new("Folder")
			buildingFolder.Name = sanitizeId(building.id, "b", index)
			buildingFolder:SetAttribute("BuildingId", sanitizeId(building.id, "b", index))
			if building.name then
				buildingFolder:SetAttribute("DisplayName", building.name)
			end
			buildingFolder:SetAttribute("BaseZ", finiteNumber(building.baseZ) or DEFAULT_BUILDING_BASE_ELEVATION)
			buildingFolder:SetAttribute("Height", sanitizePositiveNumber(building.height, DEFAULT_BUILDING_HEIGHT))
			buildingFolder:SetAttribute("Color", sanitizeColor(building.color) or DEFAULT_BUILDING_COLOR)
			buildingFolder:SetAttribute("Material", sanitizeBuildingMaterial(building.material))
			buildingFolder.Parent = buildingsFolder

			local verticesFolder = Instance.new("Folder")
			verticesFolder.Name = RoadGraphData.BUILDING_VERTICES_NAME
			verticesFolder.Parent = buildingFolder

			for vertexIndex, vertex in ipairs(building.vertices or {}) do
				local vertexValue = Instance.new("Vector3Value")
				vertexValue.Name = string.format("V%04d", vertexIndex)
				vertexValue.Value = vertex
				vertexValue.Parent = verticesFolder
			end
		end
	end

	graphFolder:SetAttribute("NodeCount", #(graph.nodes or {}))
	graphFolder:SetAttribute("EdgeCount", #(graph.edges or {}))
	graphFolder:SetAttribute("PolygonFillCount", #polygonFills)
	graphFolder:SetAttribute("BuildingCount", #buildings)
	return graphFolder
end

function RoadGraphData.collectGraph(root, config)
	local graphFolder = graphFolderFromRoot(root)
	if not graphFolder then
		return nil
	end

	local settings = RoadGraphData.defaultSettings(config)
	settings.chamferAngleDeg = finiteNumber(graphFolder:GetAttribute("ChamferAngleDeg")) or settings.chamferAngleDeg
	settings.crosswalkWidth = finiteNumber(graphFolder:GetAttribute("CrosswalkWidth")) or settings.crosswalkWidth
	settings.sidewalkWidth = finiteNumber(graphFolder:GetAttribute("DefaultSidewalkWidth")) or settings.sidewalkWidth
	settings.meshResolution = finiteNumber(graphFolder:GetAttribute("MeshResolution"))
		or finiteNumber(graphFolder:GetAttribute("SplineSegments"))
		or settings.meshResolution

	local nodes = {}
	local nodeLookup = {}
	local nodesFolder = childFolders(graphFolder, RoadGraphData.NODES_NAME)
	for index, child in ipairs(sortedChildren(nodesFolder)) do
		if child:IsA("Vector3Value") then
			local nodeId = sanitizeId(child:GetAttribute("NodeId") or child.Name, "n", index)
			local node = {
				id = nodeId,
				point = child.Value,
				transitionSmoothness = finiteNumber(child:GetAttribute("TransitionSmoothness")),
				ignoreMeshing = child:GetAttribute("IgnoreMeshing") == true,
			}
			table.insert(nodes, node)
			nodeLookup[nodeId] = node
		end
	end

	local edges = {}
	local edgesFolder = childFolders(graphFolder, RoadGraphData.EDGES_NAME)
	for index, edgeFolder in ipairs(sortedChildren(edgesFolder)) do
		if edgeFolder:IsA("Folder") then
			local source = edgeFolder:GetAttribute("Source")
			local target = edgeFolder:GetAttribute("Target")
			if type(source) == "string" and nodeLookup[source] and (target == nil or nodeLookup[target]) then
				local points = {}
				local pointsFolder = childFolders(edgeFolder, RoadGraphData.EDGE_POINTS_NAME)
				for _, pointValue in ipairs(sortedChildren(pointsFolder)) do
					if pointValue:IsA("Vector3Value") then
						table.insert(points, pointValue.Value)
					end
				end

				table.insert(edges, {
					id = sanitizeId(edgeFolder:GetAttribute("EdgeId") or edgeFolder.Name, "e", index),
					source = source,
					target = target,
					points = points,
					width = RoadSampling.sanitizeRoadWidth(edgeFolder:GetAttribute("Width")),
					sidewalk = math.max(finiteNumber(edgeFolder:GetAttribute("Sidewalk")) or settings.sidewalkWidth, 0),
					sidewalkLeft = finiteNumber(edgeFolder:GetAttribute("SidewalkLeft")),
					sidewalkRight = finiteNumber(edgeFolder:GetAttribute("SidewalkRight")),
					transitionSmoothness = finiteNumber(edgeFolder:GetAttribute("TransitionSmoothness")),
					color = sanitizeColor(edgeFolder:GetAttribute("Color")),
					name = sanitizeName(edgeFolder:GetAttribute("DisplayName"), nil),
				})
			end
		end
	end

	local polygonFills = {}
	local fillsFolder = childFolders(graphFolder, RoadGraphData.POLYGON_FILLS_NAME)
	for index, fillFolder in ipairs(sortedChildren(fillsFolder)) do
		if fillFolder:IsA("Folder") then
			local points = {}
			local pointsFolder = childFolders(fillFolder, RoadGraphData.POLYGON_FILL_POINTS_NAME)
			for _, pointValue in ipairs(sortedChildren(pointsFolder)) do
				if pointValue:IsA("StringValue") and nodeLookup[pointValue.Value] then
					table.insert(points, pointValue.Value)
				end
			end

			if #points >= 3 then
				table.insert(polygonFills, {
					id = sanitizeId(fillFolder:GetAttribute("FillId") or fillFolder.Name, "pf", index),
					points = points,
					color = sanitizeColor(fillFolder:GetAttribute("Color")) or "#10b981",
				})
			end
		end
	end

	local buildings = {}
	local buildingsFolder = childFolders(graphFolder, RoadGraphData.BUILDINGS_NAME)
	for index, buildingFolder in ipairs(sortedChildren(buildingsFolder)) do
		if buildingFolder:IsA("Folder") then
			local vertices = {}
			local verticesFolder = childFolders(buildingFolder, RoadGraphData.BUILDING_VERTICES_NAME)
			for _, vertexValue in ipairs(sortedChildren(verticesFolder)) do
				if vertexValue:IsA("Vector3Value") then
					table.insert(vertices, vertexValue.Value)
				end
			end

			if #vertices >= 3 then
				table.insert(buildings, {
					id = sanitizeId(buildingFolder:GetAttribute("BuildingId") or buildingFolder.Name, "b", index),
					name = sanitizeName(buildingFolder:GetAttribute("DisplayName"), nil),
					vertices = vertices,
					baseZ = finiteNumber(buildingFolder:GetAttribute("BaseZ")) or (vertices[1].Y - (finiteNumber(graphFolder:GetAttribute("PlaneY")) or 0)),
					height = sanitizePositiveNumber(buildingFolder:GetAttribute("Height"), DEFAULT_BUILDING_HEIGHT),
					color = sanitizeColor(buildingFolder:GetAttribute("Color")) or DEFAULT_BUILDING_COLOR,
					material = sanitizeBuildingMaterial(buildingFolder:GetAttribute("Material")),
				})
			end
		end
	end

	if #nodes == 0 or #edges == 0 then
		return nil
	end

	return {
		schema = graphFolder:GetAttribute("Schema") or RoadGraphData.SCHEMA,
		version = tonumber(graphFolder:GetAttribute("Version")) or RoadGraphData.VERSION,
		planeY = finiteNumber(graphFolder:GetAttribute("PlaneY")) or 0,
		importPointScale = sanitizeScale(graphFolder:GetAttribute("ImportPointScale")),
		importWidthScale = sanitizeScale(graphFolder:GetAttribute("ImportWidthScale")),
		settings = settings,
		nodes = nodes,
		edges = edges,
		nodeLookup = nodeLookup,
		polygonFills = polygonFills,
		buildings = buildings,
	}
end

function RoadGraphData.toPayload(graph)
	local nodes = {}
	for _, node in ipairs(graph.nodes or {}) do
		table.insert(nodes, {
			id = node.id,
			point = vectorToGraphPoint(node.point, graph.planeY),
			transitionSmoothness = node.transitionSmoothness,
			ignoreMeshing = if node.ignoreMeshing == true then true else nil,
		})
	end

	local edges = {}
	for _, edge in ipairs(graph.edges or {}) do
		local points = {}
		for _, point in ipairs(edge.points or {}) do
			table.insert(points, vectorToGraphPoint(point, graph.planeY))
		end
		table.insert(edges, {
			id = edge.id,
			source = edge.source,
			target = edge.target,
			points = points,
			width = edge.width,
			sidewalk = edge.sidewalk,
			sidewalkLeft = edge.sidewalkLeft,
			sidewalkRight = edge.sidewalkRight,
			transitionSmoothness = edge.transitionSmoothness,
			color = edge.color,
			name = edge.name,
		})
	end

	local buildings = {}
	for index, building in ipairs(graph.buildings or {}) do
		if type(building) == "table" and type(building.vertices) == "table" then
			local vertices = {}
			for _, vertex in ipairs(building.vertices) do
				if typeof(vertex) == "Vector3" then
					table.insert(vertices, {
						x = vertex.X,
						y = vertex.Z,
					})
				end
			end

			if #vertices >= 3 then
				local baseZ = finiteNumber(building.baseZ)
				if baseZ == nil and typeof(building.vertices[1]) == "Vector3" then
					baseZ = building.vertices[1].Y - (finiteNumber(graph.planeY) or 0)
				end
				table.insert(buildings, {
					id = sanitizeId(building.id, "b", index),
					name = building.name,
					vertices = vertices,
					baseZ = baseZ or DEFAULT_BUILDING_BASE_ELEVATION,
					height = sanitizePositiveNumber(building.height, DEFAULT_BUILDING_HEIGHT),
					color = sanitizeColor(building.color) or DEFAULT_BUILDING_COLOR,
					material = sanitizeBuildingMaterial(building.material),
				})
			end
		end
	end

	return {
		schema = RoadGraphData.SCHEMA,
		version = RoadGraphData.VERSION,
		settings = graph.settings,
		nodes = nodes,
		edges = edges,
		polygonFills = clonePolygonFills(graph.polygonFills),
		buildings = buildings,
	}
end

return RoadGraphData
