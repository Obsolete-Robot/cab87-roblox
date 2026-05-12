local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadGraph = require(Shared:WaitForChild("RoadGraph"))
local RoadGraphData = require(Shared:WaitForChild("RoadGraphData"))
local RoadGraphMesher = require(Shared:WaitForChild("RoadGraphMesher"))
local RoadSampling = require(Shared:WaitForChild("RoadSampling"))
local RoadSplineData = require(Shared:WaitForChild("RoadSplineData"))

local GpsService = {}

local ROAD_SPLINE_DATA_NAME = RoadSplineData.RUNTIME_DATA_NAME
local GPS_BASE_TRANSPARENCY_ATTR = "Cab87BaseTransparency"
local DEBUG_PREFIX = "[cab87 gps]"

local function getConfigNumber(key, fallback)
	local value = Config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
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

local function debugLoggingEnabled()
	return Config.passengerDebugLogging == true
end

local function debugLog(message, ...)
	if not debugLoggingEnabled() then
		return
	end

	local ok, formatted = pcall(string.format, tostring(message), ...)
	print(DEBUG_PREFIX .. " " .. (ok and formatted or tostring(message)))
end

local function formatVector(position)
	if typeof(position) ~= "Vector3" then
		return "nil"
	end

	return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
end

local function countParts(instances)
	local count = 0
	for _, instance in ipairs(instances or {}) do
		if instance and instance:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local function graphDataRoot(world)
	return world and (world:FindFirstChild(RoadGraphData.RUNTIME_DATA_NAME) or world:FindFirstChild(RoadGraphData.ROAD_GRAPH_NAME))
end

local function graphTransformSummary(world)
	local root = graphDataRoot(world)
	if not root then
		return "none"
	end

	return string.format(
		"%s status=%s error=%s offset=(%s,%s) matrix=[%s,%s;%s,%s]",
		tostring(root:GetAttribute("ImportedGlbCoordinateTransform") or "none"),
		tostring(root:GetAttribute("ImportedGlbCoordinateTransformApplied")),
		tostring(root:GetAttribute("ImportedGlbCoordinateTransformError")),
		tostring(root:GetAttribute("ImportedGlbCoordinateOffsetX")),
		tostring(root:GetAttribute("ImportedGlbCoordinateOffsetZ")),
		tostring(root:GetAttribute("ImportedGlbCoordinateXX")),
		tostring(root:GetAttribute("ImportedGlbCoordinateXZ")),
		tostring(root:GetAttribute("ImportedGlbCoordinateZX")),
		tostring(root:GetAttribute("ImportedGlbCoordinateZZ"))
	)
end

local function getConfigColor(key, fallback)
	local value = Config[key]
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local horizontalDistance = RoadSampling.distanceXZ

local function setPartRuntimeDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function makePart(parent, props)
	local part = Instance.new("Part")
	setPartRuntimeDefaults(part)
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local function makeHiddenPart(parent, name)
	local part = makePart(parent, {
		Name = name,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = Vector3.zero,
		Transparency = 1,
		Color = Color3.fromRGB(255, 255, 255),
	})
	part:SetAttribute(GPS_BASE_TRANSPARENCY_ATTR, 1)
	return part
end

local function setModelVisible(model, visible)
	if not model then
		return
	end

	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			local baseTransparency = item:GetAttribute(GPS_BASE_TRANSPARENCY_ATTR)
			if type(baseTransparency) ~= "number" then
				baseTransparency = item.Transparency
				item:SetAttribute(GPS_BASE_TRANSPARENCY_ATTR, baseTransparency)
			end

			item.Transparency = if visible then baseTransparency else 1
		elseif item:IsA("BillboardGui") or item:IsA("SurfaceGui") then
			item.Enabled = visible
		end
	end

	model:SetAttribute("Visible", visible)
end

local function recreateModel(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function newRouteGraph()
	return RoadGraph.new({
		mergeDistance = getConfigNumber("passengerRouteGraphNodeMergeDistance", 5),
		maxMergeHeight = getConfigNumber("passengerRouteGraphMaxMergeHeight", 7),
	})
end

local addRouteNode = RoadGraph.addNode
local addRouteEdge = RoadGraph.addEdge

local function edgesById(edges)
	local lookup = {}
	for _, edge in ipairs(edges or {}) do
		if edge.id then
			lookup[edge.id] = edge
		end
	end
	return lookup
end

local function isOneWayEdge(edge)
	return edge and edge.oneWay == true
end

local function isReverseOneWayEdge(edge)
	return isOneWayEdge(edge) and edge.oneWayDirection == "reverse"
end

local function appendRoutePoint(points, point)
	if typeof(point) ~= "Vector3" then
		return
	end

	local previous = points[#points]
	if previous and (previous - point).Magnitude <= 0.01 then
		return
	end

	table.insert(points, point)
end

local function addRoutePolyline(graph, points, edge)
	if #points < 2 then
		return
	end

	local directed = isOneWayEdge(edge)
	local options = {
		directed = directed,
		width = edge and edge.width or nil,
	}
	local previousNodeId = nil

	if isReverseOneWayEdge(edge) then
		for i = #points, 1, -1 do
			local nodeId = addRouteNode(graph, points[i])
			if previousNodeId then
				addRouteEdge(graph, previousNodeId, nodeId, options)
			end
			previousNodeId = nodeId
		end
	else
		for _, point in ipairs(points) do
			local nodeId = addRouteNode(graph, point)
			if previousNodeId then
				addRouteEdge(graph, previousNodeId, nodeId, options)
			end
			previousNodeId = nodeId
		end
	end
end

local function buildAuthoredRouteGraph(world)
	local graphData = RoadGraphData.collectGraph(world, Config)
	if graphData then
		local meshData = RoadGraphMesher.buildNetworkMesh(graphData, graphData.settings)
		local graph = newRouteGraph()
		local authoredNodesById = {}
		local authoredEdgesById = edgesById(graphData.edges)
		local routedEdges = {}

		for _, node in ipairs(graphData.nodes or {}) do
			authoredNodesById[node.id] = node
			addRouteNode(graph, node.point)
		end

		for _, centerLine in ipairs(meshData.centerLines or {}) do
			local edge = authoredEdgesById[centerLine.edgeId]
			if edge then
				routedEdges[edge.id] = true
			end
			local routePoints = {}
			if edge and authoredNodesById[edge.source] then
				appendRoutePoint(routePoints, authoredNodesById[edge.source].point)
			end
			for _, position in ipairs(centerLine) do
				appendRoutePoint(routePoints, position)
			end
			if edge and edge.target and authoredNodesById[edge.target] then
				appendRoutePoint(routePoints, authoredNodesById[edge.target].point)
			end
			addRoutePolyline(graph, routePoints, edge)
		end

		for _, edge in ipairs(graphData.edges or {}) do
			if not routedEdges[edge.id] and edge.target and authoredNodesById[edge.source] and authoredNodesById[edge.target] then
				addRoutePolyline(graph, {
					authoredNodesById[edge.source].point,
					authoredNodesById[edge.target].point,
				}, edge)
			end
		end

		if #graph.nodes > 0 and #graph.edges > 0 then
			debugLog(
				"authored route graph: world=%s graph=%d nodes/%d edges centerLines=%d route=%d nodes/%d edges transform=%s",
				world and world:GetFullName() or "nil",
				#(graphData.nodes or {}),
				#(graphData.edges or {}),
				#(meshData.centerLines or {}),
				#graph.nodes,
				#graph.edges,
				graphTransformSummary(world)
			)
			return graph
		end
	end

	local dataRoot = world:FindFirstChild(ROAD_SPLINE_DATA_NAME)
	if not dataRoot then
		return nil
	end

	local records = RoadSplineData.collectSplineRecords(dataRoot)
	if #records == 0 then
		return nil
	end

	local graph = newRouteGraph()
	RoadGraph.addSplineRecords(graph, records)

	for _, junction in ipairs(RoadSplineData.collectJunctions(dataRoot, { defaultRadius = 0, minRadius = 0 })) do
		RoadGraph.connectJunction(graph, junction.center, junction.radius, getConfigNumber("passengerRouteJunctionExtraRadius", 10))
	end

	if #graph.nodes == 0 or #graph.edges == 0 then
		return nil
	end

	return graph
end

local function addGeneratedRoadPoint(road, position, axisValue)
	table.insert(road.points, {
		position = position,
		axisValue = axisValue,
	})
end

local function buildGeneratedRouteGraph(driveSurfaces)
	local verticalRoads = {}
	local horizontalRoads = {}

	for _, surface in ipairs(driveSurfaces or {}) do
		if surface:IsA("BasePart") and surface.Name == "Road_NS" then
			local halfLength = surface.Size.Z * 0.5
			local y = surface.Position.Y + surface.Size.Y * 0.5
			local road = {
				x = surface.Position.X,
				zMin = surface.Position.Z - halfLength,
				zMax = surface.Position.Z + halfLength,
				y = y,
				width = surface.Size.X,
				points = {},
			}
			addGeneratedRoadPoint(road, Vector3.new(road.x, y, road.zMin), road.zMin)
			addGeneratedRoadPoint(road, Vector3.new(road.x, y, road.zMax), road.zMax)
			table.insert(verticalRoads, road)
		elseif surface:IsA("BasePart") and surface.Name == "Road_EW" then
			local halfLength = surface.Size.X * 0.5
			local y = surface.Position.Y + surface.Size.Y * 0.5
			local road = {
				z = surface.Position.Z,
				xMin = surface.Position.X - halfLength,
				xMax = surface.Position.X + halfLength,
				y = y,
				width = surface.Size.Z,
				points = {},
			}
			addGeneratedRoadPoint(road, Vector3.new(road.xMin, y, road.z), road.xMin)
			addGeneratedRoadPoint(road, Vector3.new(road.xMax, y, road.z), road.xMax)
			table.insert(horizontalRoads, road)
		end
	end

	if #verticalRoads == 0 or #horizontalRoads == 0 then
		return nil
	end

	for _, vertical in ipairs(verticalRoads) do
		for _, horizontal in ipairs(horizontalRoads) do
			if vertical.x >= horizontal.xMin
				and vertical.x <= horizontal.xMax
				and horizontal.z >= vertical.zMin
				and horizontal.z <= vertical.zMax
			then
				local y = math.max(vertical.y, horizontal.y)
				local position = Vector3.new(vertical.x, y, horizontal.z)
				addGeneratedRoadPoint(vertical, position, horizontal.z)
				addGeneratedRoadPoint(horizontal, position, vertical.x)
			end
		end
	end

	local graph = newRouteGraph()
	local function addRoadEdges(road)
		table.sort(road.points, function(a, b)
			return a.axisValue < b.axisValue
		end)

		local previousNodeId = nil
		for _, point in ipairs(road.points) do
			local nodeId = addRouteNode(graph, point.position)
			if previousNodeId then
				addRouteEdge(graph, previousNodeId, nodeId, {
					width = road.width,
				})
			end
			previousNodeId = nodeId
		end
	end

	for _, road in ipairs(verticalRoads) do
		addRoadEdges(road)
	end
	for _, road in ipairs(horizontalRoads) do
		addRoadEdges(road)
	end

	if #graph.nodes == 0 or #graph.edges == 0 then
		return nil
	end

	return graph
end

local function buildRouteGraph(world, driveSurfaces)
	local graph = buildAuthoredRouteGraph(world)
	if graph then
		graph.source = "authored"
		return graph
	end

	graph = buildGeneratedRouteGraph(driveSurfaces)
	if graph then
		graph.source = "generated"
	end

	return graph
end

local function createRouteSegment(parent, index)
	local routeColor = getConfigColor("passengerRouteColor", Color3.fromRGB(255, 70, 55))
	local transparency = math.clamp(getConfigNumber("passengerRouteTransparency", 0.05), 0, 1)
	local segment = makePart(parent, {
		Name = string.format("RouteSegment_%02d", index),
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, -1000, 0),
		Color = routeColor,
		Material = Enum.Material.Neon,
		Transparency = transparency,
	})
	segment:SetAttribute(GPS_BASE_TRANSPARENCY_ATTR, transparency)
	return segment
end

local function makeArrowBar(parent, name, a, b, width, color)
	local delta = b - a
	local length = math.max(delta.Magnitude, 0.1)
	local bar = makePart(parent, {
		Name = name,
		Size = Vector3.new(width, width, length),
		CFrame = CFrame.lookAt((a + b) * 0.5, b),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0,
	})
	bar:SetAttribute(GPS_BASE_TRANSPARENCY_ATTR, 0)
	return bar
end

local function createGpsGuide(parent)
	local guide = recreateModel(parent, getConfigString("gpsGuideFolderName", "GpsGuide"))
	guide:SetAttribute("GeneratedBy", "Cab87GpsService")

	local routeFolder = Instance.new("Folder")
	routeFolder.Name = "RouteLine"
	routeFolder.Parent = guide

	local maxSegments = math.max(4, math.floor(getConfigNumber("passengerRouteMaxSegments", 30)))
	local segments = {}
	for i = 1, maxSegments do
		table.insert(segments, createRouteSegment(routeFolder, i))
	end

	local arrow = Instance.new("Model")
	arrow.Name = "DestinationArrow"
	arrow:SetAttribute("GeneratedBy", "Cab87GpsService")
	arrow.Parent = guide

	local arrowColor = getConfigColor("passengerDeliveryColor", Color3.fromRGB(255, 70, 55))
	local arrowWidth = math.max(getConfigNumber("passengerDeliveryArrowWidth", 1.35), 0.25)
	local arrowHeight = math.max(getConfigNumber("passengerDeliveryArrowHeight", 16), 4)
	local arrowHeadWidth = math.max(getConfigNumber("passengerDeliveryArrowHeadWidth", 5.5), 1)
	local headBaseY = math.max(arrowHeadWidth * 0.75, 2)
	local pivot = makeHiddenPart(arrow, "Pivot")

	makeArrowBar(arrow, "Shaft", Vector3.new(0, arrowHeight, 0), Vector3.new(0, headBaseY, 0), arrowWidth, arrowColor)
	makeArrowBar(arrow, "HeadXPositive", Vector3.new(arrowHeadWidth, headBaseY, 0), Vector3.zero, arrowWidth, arrowColor)
	makeArrowBar(arrow, "HeadXNegative", Vector3.new(-arrowHeadWidth, headBaseY, 0), Vector3.zero, arrowWidth, arrowColor)
	makeArrowBar(arrow, "HeadZPositive", Vector3.new(0, headBaseY, arrowHeadWidth), Vector3.zero, arrowWidth, arrowColor)
	makeArrowBar(arrow, "HeadZNegative", Vector3.new(0, headBaseY, -arrowHeadWidth), Vector3.zero, arrowWidth, arrowColor)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DropLabel"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(130, 34)
	billboard.StudsOffset = Vector3.new(0, arrowHeight + 1.5, 0)
	billboard.Parent = pivot

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = "DROP"
	label.TextColor3 = arrowColor
	label.TextSize = 28
	label.TextStrokeColor3 = Color3.fromRGB(20, 5, 5)
	label.TextStrokeTransparency = 0.15
	label.Parent = billboard

	arrow.PrimaryPart = pivot
	setModelVisible(guide, false)

	return {
		model = guide,
		segments = segments,
		arrow = arrow,
		maxSegments = maxSegments,
		visible = false,
	}
end

local function setRouteSegmentVisible(segment, visible)
	local baseTransparency = segment:GetAttribute(GPS_BASE_TRANSPARENCY_ATTR)
	if type(baseTransparency) ~= "number" then
		baseTransparency = math.clamp(getConfigNumber("passengerRouteTransparency", 0.05), 0, 1)
	end

	segment.Transparency = if visible then baseTransparency else 1
end

local function setGpsGuideVisible(service, visible)
	local guide = service.gpsGuide
	if not guide or guide.visible == visible then
		return
	end

	guide.visible = visible
	if visible then
		setModelVisible(guide.arrow, true)
		for _, segment in ipairs(guide.segments) do
			setRouteSegmentVisible(segment, false)
		end
		guide.model:SetAttribute("Visible", true)
	else
		setModelVisible(guide.model, false)
	end
end

local function getSurfacePosition(service, position, fallbackY)
	local raycastParams = service.surfaceRaycastParams
	if raycastParams then
		local localAbove = math.max(getConfigNumber("passengerRouteSurfaceSearchAbove", 10), 0.5)
		local localBelow = math.max(getConfigNumber("passengerRouteSurfaceSearchBelow", 32), 0.5)
		local localOrigin = Vector3.new(position.X, position.Y + localAbove, position.Z)
		local result = Workspace:Raycast(localOrigin, Vector3.new(0, -(localAbove + localBelow), 0), raycastParams)
		if result then
			return result.Position
		end

		local rayHeight = math.max(getConfigNumber("passengerRouteRaycastHeight", 140), 1)
		local rayDepth = math.max(getConfigNumber("passengerRouteRaycastDepth", 260), rayHeight + 1)
		local origin = Vector3.new(position.X, position.Y + rayHeight, position.Z)
		result = Workspace:Raycast(origin, Vector3.new(0, -rayDepth, 0), raycastParams)
		if result then
			return result.Position
		end
	end

	return Vector3.new(position.X, fallbackY or position.Y, position.Z)
end

local function getHorizontalDirection(fromPosition, toPosition)
	local delta = Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
	if delta.Magnitude <= 0.001 then
		return nil
	end

	return delta.Unit
end

local function getRouteTurnAngle(a, b, c)
	local into = getHorizontalDirection(a, b)
	local out = getHorizontalDirection(b, c)
	if not into or not out then
		return 0
	end

	return math.acos(math.clamp(into:Dot(out), -1, 1))
end

local function buildDisplayRoutePointsWithSpacing(points, spacing, turnThreshold)
	local displayPoints = { points[1] }
	local distanceSinceKept = 0

	for i = 2, #points - 1 do
		distanceSinceKept += horizontalDistance(points[i - 1], points[i])
		local turnAngle = getRouteTurnAngle(points[i - 1], points[i], points[i + 1])
		if distanceSinceKept >= spacing or turnAngle >= turnThreshold then
			table.insert(displayPoints, points[i])
			distanceSinceKept = 0
		end
	end

	table.insert(displayPoints, points[#points])
	return displayPoints
end

local function buildDisplayRoutePoints(points, maxSegments)
	if #points <= 2 then
		return points, math.max(#points - 1, 0)
	end

	local spacing = math.max(getConfigNumber("passengerRouteSegmentLength", 32), 8)
	local turnThreshold = math.rad(math.max(getConfigNumber("passengerRouteTurnKeepDegrees", 12), 0))
	local displayPoints = buildDisplayRoutePointsWithSpacing(points, spacing, turnThreshold)

	while #displayPoints - 1 > maxSegments and spacing < 512 do
		spacing *= 1.35
		displayPoints = buildDisplayRoutePointsWithSpacing(points, spacing, turnThreshold)
	end

	if #displayPoints - 1 > maxSegments then
		local compacted = { displayPoints[1] }
		local step = (#displayPoints - 1) / maxSegments
		for i = 1, maxSegments - 1 do
			table.insert(compacted, displayPoints[math.floor(i * step + 0.5) + 1])
		end
		table.insert(compacted, displayPoints[#displayPoints])
		displayPoints = compacted
	end

	return displayPoints, math.max(#displayPoints - 1, 0)
end

local function getRouteLaneDirection(points, index)
	local previousDirection = if index > 1 then getHorizontalDirection(points[index - 1], points[index]) else nil
	local nextDirection = if index < #points then getHorizontalDirection(points[index], points[index + 1]) else nil
	if previousDirection and nextDirection and previousDirection:Dot(nextDirection) > -0.75 then
		local combined = previousDirection + nextDirection
		if combined.Magnitude > 0.001 then
			return combined.Unit
		end
	end

	return nextDirection or previousDirection
end

local function getRouteLaneOffset(service, point, routeWidth)
	local snap = RoadGraph.findNearestEdge(service.routeGraph, point)
	local roadWidth = snap and snap.edge and snap.edge.width or RoadSampling.DEFAULT_ROAD_WIDTH
	local halfRoadWidth = math.max(roadWidth * 0.5, 0)
	local configuredOffset = Config.passengerRouteLaneOffset
	local offset = if type(configuredOffset) == "number"
		then configuredOffset
		else roadWidth * math.max(getConfigNumber("passengerRouteLaneOffsetScale", 0.25), 0)
	local laneEdgeInset = math.max(getConfigNumber("passengerRouteLaneEdgeInset", 4), 0)
	local maxOffset = math.max(halfRoadWidth - routeWidth * 0.5 - laneEdgeInset, 0)
	return math.clamp(offset, 0, maxOffset), snap
end

local function getRouteLanePoint(service, displayPoints, index, routeWidth)
	local point = displayPoints[index]
	local direction = getRouteLaneDirection(displayPoints, index)
	if not direction then
		return point
	end

	local offset, snap = getRouteLaneOffset(service, point, routeWidth)
	local centerPoint = if snap then snap.position else point
	local right = Vector3.new(-direction.Z, 0, direction.X)
	return centerPoint + right * offset
end

local function updateRouteLine(service, cabPosition, targetPosition)
	local guide = service.gpsGuide
	if not guide then
		return
	end

	local routePath = RoadGraph.findPath(service.routeGraph, cabPosition, targetPosition)
	if not routePath or #routePath < 2 then
		for _, segment in ipairs(guide.segments) do
			setRouteSegmentVisible(segment, false)
		end
		if debugLoggingEnabled() and (service.elapsedTime or 0) >= (service.nextRouteDebugLogAt or 0) then
			debugLog(
				"route failed: cab=%s target=%s graphSource=%s nodes=%s edges=%s driveSurfaces=%d transform=%s",
				formatVector(cabPosition),
				formatVector(targetPosition),
				tostring(service.routeGraph and service.routeGraph.source or "none"),
				tostring(service.routeGraph and #service.routeGraph.nodes or 0),
				tostring(service.routeGraph and #service.routeGraph.edges or 0),
				countParts(service.driveSurfaces),
				graphTransformSummary(service.world)
			)
			service.nextRouteDebugLogAt = (service.elapsedTime or 0) + math.max(getConfigNumber("passengerDebugLogInterval", 2), 0.25)
		end
		return
	end

	local displayPoints, segmentCount = buildDisplayRoutePoints(routePath, guide.maxSegments)
	local heightOffset = getConfigNumber("passengerRouteHeightOffset", 1.65)
	local routeWidth = math.max(getConfigNumber("passengerRouteWidth", 2.6), 0.2)
	local points = {}

	for index, _ in ipairs(displayPoints) do
		local lanePoint = getRouteLanePoint(service, displayPoints, index, routeWidth)
		local surfacePoint = getSurfacePosition(service, lanePoint, lanePoint.Y)
		table.insert(points, Vector3.new(lanePoint.X, surfacePoint.Y + heightOffset, lanePoint.Z))
	end
	if debugLoggingEnabled() and (service.elapsedTime or 0) >= (service.nextRouteDebugLogAt or 0) then
		debugLog(
			"route update: cab=%s target=%s pathPoints=%d displaySegments=%d first=%s last=%s graphSource=%s transform=%s",
			formatVector(cabPosition),
			formatVector(targetPosition),
			#routePath,
			segmentCount,
			formatVector(routePath[1]),
			formatVector(routePath[#routePath]),
			tostring(service.routeGraph and service.routeGraph.source or "none"),
			graphTransformSummary(service.world)
		)
		service.nextRouteDebugLogAt = (service.elapsedTime or 0) + math.max(getConfigNumber("passengerDebugLogInterval", 2), 0.25)
	end

	local routeThickness = math.max(getConfigNumber("passengerRouteThickness", 0.18), 0.05)
	for i, segment in ipairs(guide.segments) do
		if i <= segmentCount then
			local a = points[i]
			local b = points[i + 1]
			local segmentLength = (b - a).Magnitude
			if segmentLength > 0.05 then
				segment.Size = Vector3.new(routeWidth, routeThickness, segmentLength)
				segment.CFrame = CFrame.lookAt((a + b) * 0.5, b)
				setRouteSegmentVisible(segment, true)
			else
				setRouteSegmentVisible(segment, false)
			end
		else
			setRouteSegmentVisible(segment, false)
		end
	end
end

local function updateDestinationArrow(service, targetPosition)
	local guide = service.gpsGuide
	if not guide or not guide.arrow then
		return
	end

	local targetGround = getSurfacePosition(service, targetPosition, targetPosition.Y)
	local tipHeight = math.max(getConfigNumber("passengerDeliveryArrowTipHeight", 4.5), 0)
	local bounceHeight = math.max(getConfigNumber("passengerDeliveryArrowBounceHeight", 3.5), 0)
	local bounceSpeed = math.max(getConfigNumber("passengerDeliveryArrowBounceSpeed", 2.4), 0)
	local bounce = (math.sin((service.elapsedTime or 0) * math.pi * 2 * bounceSpeed) * 0.5 + 0.5) * bounceHeight
	guide.arrow:PivotTo(CFrame.new(targetGround + Vector3.new(0, tipHeight + bounce, 0)))
end

local function updateService(service, dt)
	dt = math.min(dt, 0.1)
	service.elapsedTime += dt

	local destination = service.destination
	if not destination then
		setGpsGuideVisible(service, false)
		return
	end

	setGpsGuideVisible(service, true)
	updateDestinationArrow(service, destination)

	service.routeUpdateAccumulator += dt
	if service.routeUpdateAccumulator >= getConfigNumber("passengerRouteUpdateInterval", 1 / 20) then
		service.routeUpdateAccumulator = 0
		updateRouteLine(service, service.car:GetPivot().Position, destination)
	end
end

function GpsService.start(options)
	local world = options and options.world
	local car = options and options.car
	if not (world and car) then
		return nil
	end

	local service = {
		world = world,
		car = car,
		driveSurfaces = options.driveSurfaces,
		destination = nil,
		elapsedTime = 0,
		routeUpdateAccumulator = math.huge,
		nextRouteDebugLogAt = 0,
	}

	service.routeGraph = buildRouteGraph(world, options.driveSurfaces)
	if options.driveSurfaces and #options.driveSurfaces > 0 then
		service.surfaceRaycastParams = RaycastParams.new()
		service.surfaceRaycastParams.FilterType = Enum.RaycastFilterType.Include
		service.surfaceRaycastParams.FilterDescendantsInstances = options.driveSurfaces
	end
	service.gpsGuide = createGpsGuide(world)
	service.world:SetAttribute("GpsRouteGraphSource", service.routeGraph and service.routeGraph.source or "none")
	service.world:SetAttribute("GpsRouteGraphNodes", service.routeGraph and #service.routeGraph.nodes or 0)
	service.world:SetAttribute("GpsRouteGraphEdges", service.routeGraph and #service.routeGraph.edges or 0)
	debugLog(
		"started gps: world=%s meshSource=%s visualSource=%s graphSource=%s nodes=%d edges=%d driveSurfaces=%d transform=%s",
		world:GetFullName(),
		tostring(world:GetAttribute("AuthoredRoadMeshSource")),
		tostring(world:GetAttribute("AuthoredRoadVisualSource")),
		service.routeGraph and tostring(service.routeGraph.source) or "none",
		service.routeGraph and #service.routeGraph.nodes or 0,
		service.routeGraph and #service.routeGraph.edges or 0,
		countParts(options.driveSurfaces),
		graphTransformSummary(world)
	)

	function service:setDestination(destination)
		if typeof(destination) ~= "Vector3" then
			self:clearDestination()
			return
		end

		self.destination = destination
		self.routeUpdateAccumulator = math.huge
		debugLog("set destination: %s", formatVector(destination))
		setGpsGuideVisible(self, true)
		updateDestinationArrow(self, destination)
	end

	function service:clearDestination()
		self.destination = nil
		self.routeUpdateAccumulator = math.huge
		setGpsGuideVisible(self, false)
	end

	function service:stop()
		if self.heartbeatConnection then
			self.heartbeatConnection:Disconnect()
			self.heartbeatConnection = nil
		end

		if self.gpsGuide and self.gpsGuide.model and self.gpsGuide.model.Parent then
			self.gpsGuide.model:Destroy()
		end
	end

	service.heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		updateService(service, dt)
	end)

	return service
end

return GpsService
