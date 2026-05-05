local HttpService = game:GetService("HttpService")

local RoadSampling = require(script.Parent:WaitForChild("RoadSampling"))

local RoadGraphData = {}

RoadGraphData.SCHEMA = "cab87-road-network"
RoadGraphData.VERSION = 1
RoadGraphData.EDITOR_ROOT_NAME = "Cab87RoadEditor"
RoadGraphData.ROAD_GRAPH_NAME = "RoadGraph"
RoadGraphData.RUNTIME_DATA_NAME = "AuthoredRoadGraphData"
RoadGraphData.NODES_NAME = "Nodes"
RoadGraphData.EDGES_NAME = "Edges"
RoadGraphData.EDGE_POINTS_NAME = "Points"

local DEFAULT_CHAMFER_ANGLE_DEG = 70
local DEFAULT_SIDEWALK_WIDTH = 12
local DEFAULT_MESH_RESOLUTION = 20
local DEFAULT_IMPORT_SCALE = 1

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

local function graphPointToVector(point, planeY, pointScale)
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
	local pointScale = sanitizeScale(options.pointScale or payload.importPointScale)
	local widthScale = sanitizeScale(options.widthScale or payload.importWidthScale)
	local settings = RoadGraphData.defaultSettings(options.config)
	if type(payload.settings) == "table" then
		settings.chamferAngleDeg = finiteNumber(payload.settings.chamferAngleDeg) or settings.chamferAngleDeg
		settings.crosswalkWidth = finiteNumber(payload.settings.crosswalkWidth) or settings.crosswalkWidth
		settings.sidewalkWidth = finiteNumber(payload.settings.sidewalkWidth) or settings.sidewalkWidth
		settings.meshResolution = finiteNumber(payload.settings.meshResolution)
			or finiteNumber(payload.settings.splineSegments)
			or settings.meshResolution
	end
	settings.crosswalkWidth *= widthScale
	settings.sidewalkWidth *= widthScale

	local normalizedNodes = {}
	local nodeLookup = {}
	for index, node in ipairs(nodes) do
		if type(node) == "table" then
			local nodeId = sanitizeId(node.id, "n", index)
			local position = graphPointToVector(node.point, planeY, pointScale)
			if position and not nodeLookup[nodeId] then
				local normalized = {
					id = nodeId,
					point = position,
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
						local position = graphPointToVector(point, planeY, pointScale)
						if position then
							table.insert(controlPoints, position)
						end
					end
				end
				local edgeSidewalk = scaleNumber(edge.sidewalk, widthScale) or settings.sidewalkWidth

				table.insert(normalizedEdges, {
					id = sanitizeId(edge.id, "e", index),
					source = source,
					target = target,
					points = controlPoints,
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
	end

	if #normalizedNodes == 0 then
		return nil, "Road graph did not include any valid nodes"
	end
	if #normalizedEdges == 0 then
		return nil, "Road graph did not include any valid edges"
	end

	return {
		schema = RoadGraphData.SCHEMA,
		version = RoadGraphData.VERSION,
		planeY = planeY,
		importPointScale = pointScale,
		importWidthScale = widthScale,
		settings = settings,
		nodes = normalizedNodes,
		edges = normalizedEdges,
	}, nil
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

	graphFolder:SetAttribute("NodeCount", #(graph.nodes or {}))
	graphFolder:SetAttribute("EdgeCount", #(graph.edges or {}))
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
	}
end

function RoadGraphData.toPayload(graph)
	local nodes = {}
	for _, node in ipairs(graph.nodes or {}) do
		table.insert(nodes, {
			id = node.id,
			point = vectorToGraphPoint(node.point, graph.planeY),
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

	return {
		schema = RoadGraphData.SCHEMA,
		version = RoadGraphData.VERSION,
		settings = graph.settings,
		nodes = nodes,
		edges = edges,
	}
end

return RoadGraphData
