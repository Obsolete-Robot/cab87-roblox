local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GpsService = {}

local ROAD_SPLINE_DATA_NAME = "AuthoredRoadSplineData"
local ROAD_SPLINES_NAME = "Splines"
local ROAD_POINTS_NAME = "RoadPoints"
local GPS_BASE_TRANSPARENCY_ATTR = "Cab87BaseTransparency"

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

local function getConfigColor(key, fallback)
	local value = Config[key]
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local function horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function horizontalDistanceSquared(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return dx * dx + dz * dz
end

local function sortedChildren(parent, className)
	local children = {}
	if not parent then
		return children
	end

	for _, child in ipairs(parent:GetChildren()) do
		if not className or child:IsA(className) then
			table.insert(children, child)
		end
	end

	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)

	return children
end

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

local function getRoutePointPosition(point)
	if point:IsA("BasePart") then
		return point.Position
	end

	return point.Value
end

local function getRouteBucketKey(ix, iz)
	return tostring(ix) .. ":" .. tostring(iz)
end

local function newRouteGraph()
	local mergeDistance = math.max(getConfigNumber("passengerRouteGraphNodeMergeDistance", 5), 0)
	local bucketSize = math.max(mergeDistance, 4)
	return {
		nodes = {},
		edges = {},
		edgeLookup = {},
		nodeBuckets = {},
		bucketSize = bucketSize,
		mergeDistance = mergeDistance,
		maxMergeHeight = math.max(getConfigNumber("passengerRouteGraphMaxMergeHeight", 7), 0),
	}
end

local function getNearbyRouteNodeIds(graph, position, radius)
	local bucketSize = graph.bucketSize
	local bucketRadius = math.max(1, math.ceil(radius / bucketSize))
	local centerX = math.floor(position.X / bucketSize)
	local centerZ = math.floor(position.Z / bucketSize)
	local nodeIds = {}

	for x = centerX - bucketRadius, centerX + bucketRadius do
		for z = centerZ - bucketRadius, centerZ + bucketRadius do
			local bucket = graph.nodeBuckets[getRouteBucketKey(x, z)]
			if bucket then
				for _, nodeId in ipairs(bucket) do
					table.insert(nodeIds, nodeId)
				end
			end
		end
	end

	return nodeIds
end

local function addRouteNode(graph, position)
	local mergeDistance = graph.mergeDistance
	if mergeDistance > 0 then
		for _, nodeId in ipairs(getNearbyRouteNodeIds(graph, position, mergeDistance)) do
			local node = graph.nodes[nodeId]
			if node
				and math.abs(node.position.Y - position.Y) <= graph.maxMergeHeight
				and horizontalDistance(node.position, position) <= mergeDistance
			then
				return nodeId
			end
		end
	end

	local nodeId = #graph.nodes + 1
	graph.nodes[nodeId] = {
		position = position,
		neighbors = {},
	}

	local ix = math.floor(position.X / graph.bucketSize)
	local iz = math.floor(position.Z / graph.bucketSize)
	local key = getRouteBucketKey(ix, iz)
	local bucket = graph.nodeBuckets[key]
	if not bucket then
		bucket = {}
		graph.nodeBuckets[key] = bucket
	end
	table.insert(bucket, nodeId)

	return nodeId
end

local function addRouteEdge(graph, a, b)
	if not a or not b or a == b then
		return
	end

	local key = if a < b then tostring(a) .. ":" .. tostring(b) else tostring(b) .. ":" .. tostring(a)
	if graph.edgeLookup[key] then
		return
	end

	local aPosition = graph.nodes[a].position
	local bPosition = graph.nodes[b].position
	local cost = horizontalDistance(aPosition, bPosition)
	if cost <= 0.1 then
		return
	end

	graph.edgeLookup[key] = true
	table.insert(graph.nodes[a].neighbors, { id = b, cost = cost })
	table.insert(graph.nodes[b].neighbors, { id = a, cost = cost })
	table.insert(graph.edges, { a = a, b = b, cost = cost })
end

local function connectRouteJunction(graph, center, radius)
	local junctionId = addRouteNode(graph, center)
	local connectRadius = math.max(radius + getConfigNumber("passengerRouteJunctionExtraRadius", 10), graph.mergeDistance)

	for _, nodeId in ipairs(getNearbyRouteNodeIds(graph, center, connectRadius)) do
		local node = graph.nodes[nodeId]
		if nodeId ~= junctionId
			and node
			and math.abs(node.position.Y - center.Y) <= graph.maxMergeHeight
			and horizontalDistance(node.position, center) <= connectRadius
		then
			addRouteEdge(graph, junctionId, nodeId)
		end
	end
end

local function buildAuthoredRouteGraph(world)
	local dataRoot = world:FindFirstChild(ROAD_SPLINE_DATA_NAME)
	local splinesFolder = dataRoot and dataRoot:FindFirstChild(ROAD_SPLINES_NAME)
	if not (splinesFolder and splinesFolder:IsA("Folder")) then
		return nil
	end

	local graph = newRouteGraph()
	for _, spline in ipairs(sortedChildren(splinesFolder, "Model")) do
		local pointsFolder = spline:FindFirstChild(ROAD_POINTS_NAME)
		local points = sortedChildren(pointsFolder, nil)
		local firstNodeId = nil
		local previousNodeId = nil

		for _, point in ipairs(points) do
			if point:IsA("BasePart") or point:IsA("Vector3Value") then
				local nodeId = addRouteNode(graph, getRoutePointPosition(point))
				if not firstNodeId then
					firstNodeId = nodeId
				end

				if previousNodeId then
					addRouteEdge(graph, previousNodeId, nodeId)
				end

				previousNodeId = nodeId
			end
		end

		if firstNodeId and previousNodeId and firstNodeId ~= previousNodeId and spline:GetAttribute("ClosedCurve") == true then
			addRouteEdge(graph, previousNodeId, firstNodeId)
		end
	end

	local junctionsFolder = dataRoot:FindFirstChild("Junctions")
	if junctionsFolder and junctionsFolder:IsA("Folder") then
		for _, junctionData in ipairs(sortedChildren(junctionsFolder, "Vector3Value")) do
			local radius = math.max(tonumber(junctionData:GetAttribute("Radius")) or 0, 0)
			connectRouteJunction(graph, junctionData.Value, radius)
		end
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
				addRouteEdge(graph, previousNodeId, nodeId)
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
		local rayHeight = math.max(getConfigNumber("passengerRouteRaycastHeight", 140), 1)
		local rayDepth = math.max(getConfigNumber("passengerRouteRaycastDepth", 260), rayHeight + 1)
		local origin = Vector3.new(position.X, position.Y + rayHeight, position.Z)
		local result = Workspace:Raycast(origin, Vector3.new(0, -rayDepth, 0), raycastParams)
		if result then
			return result.Position
		end
	end

	return Vector3.new(position.X, fallbackY or position.Y, position.Z)
end

local function projectPointToRouteSegment(position, a, b)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local lengthSquared = dx * dx + dz * dz
	if lengthSquared <= 0.001 then
		return a, 0, horizontalDistance(position, a)
	end

	local alpha = math.clamp(((position.X - a.X) * dx + (position.Z - a.Z) * dz) / lengthSquared, 0, 1)
	local projected = Vector3.new(
		a.X + dx * alpha,
		a.Y + (b.Y - a.Y) * alpha,
		a.Z + dz * alpha
	)
	return projected, alpha, horizontalDistance(position, projected)
end

local function findNearestRouteEdge(graph, position)
	if not graph then
		return nil
	end

	local best = nil
	local bestScore = math.huge
	for _, edge in ipairs(graph.edges) do
		local a = graph.nodes[edge.a].position
		local b = graph.nodes[edge.b].position
		local projected, alpha, distance = projectPointToRouteSegment(position, a, b)
		local verticalPenalty = math.abs(position.Y - projected.Y) * 0.08
		local score = distance + verticalPenalty
		if score < bestScore then
			bestScore = score
			best = {
				edge = edge,
				position = projected,
				alpha = alpha,
				distance = distance,
			}
		end
	end

	return best
end

local function findNearestRouteNode(graph, position)
	local bestNodeId = nil
	local bestScore = math.huge

	for nodeId, node in ipairs(graph.nodes) do
		local score = horizontalDistanceSquared(position, node.position)
		if score < bestScore then
			bestScore = score
			bestNodeId = nodeId
		end
	end

	return bestNodeId
end

local function addTemporaryRouteConnection(neighbors, a, b, cost)
	if not a or not b or a == b then
		return
	end

	neighbors[a] = neighbors[a] or {}
	neighbors[b] = neighbors[b] or {}
	table.insert(neighbors[a], { id = b, cost = cost })
	table.insert(neighbors[b], { id = a, cost = cost })
end

local function connectTemporaryRouteNode(graph, neighbors, nodeId, position)
	local snap = findNearestRouteEdge(graph, position)
	if snap then
		local a = graph.nodes[snap.edge.a].position
		local b = graph.nodes[snap.edge.b].position
		addTemporaryRouteConnection(neighbors, nodeId, snap.edge.a, horizontalDistance(snap.position, a))
		addTemporaryRouteConnection(neighbors, nodeId, snap.edge.b, horizontalDistance(snap.position, b))
		return snap
	end

	local nearestNodeId = findNearestRouteNode(graph, position)
	if nearestNodeId then
		addTemporaryRouteConnection(neighbors, nodeId, nearestNodeId, horizontalDistance(position, graph.nodes[nearestNodeId].position))
	end

	return nil
end

local function heapPush(heap, item)
	table.insert(heap, item)
	local index = #heap
	while index > 1 do
		local parent = math.floor(index * 0.5)
		if heap[parent].cost <= item.cost then
			break
		end
		heap[index] = heap[parent]
		index = parent
	end
	heap[index] = item
end

local function heapPop(heap)
	local root = heap[1]
	if not root then
		return nil
	end

	local last = table.remove(heap)
	if #heap == 0 then
		return root
	end

	local index = 1
	while true do
		local left = index * 2
		local right = left + 1
		if left > #heap then
			break
		end

		local child = left
		if right <= #heap and heap[right].cost < heap[left].cost then
			child = right
		end

		if heap[child].cost >= last.cost then
			break
		end

		heap[index] = heap[child]
		index = child
	end

	heap[index] = last
	return root
end

local function getRouteNodePosition(graph, temporaryPositions, nodeId)
	return temporaryPositions[nodeId] or graph.nodes[nodeId].position
end

local function findRoutePath(graph, startPosition, targetPosition)
	if not graph or #graph.nodes == 0 or #graph.edges == 0 then
		return nil
	end

	local startId = #graph.nodes + 1
	local targetId = #graph.nodes + 2
	local temporaryPositions = {
		[startId] = startPosition,
		[targetId] = targetPosition,
	}
	local temporaryNeighbors = {}
	local startSnap = connectTemporaryRouteNode(graph, temporaryNeighbors, startId, startPosition)
	local targetSnap = connectTemporaryRouteNode(graph, temporaryNeighbors, targetId, targetPosition)

	if startSnap then
		temporaryPositions[startId] = startSnap.position
	end
	if targetSnap then
		temporaryPositions[targetId] = targetSnap.position
	end
	if startSnap and targetSnap and startSnap.edge == targetSnap.edge then
		addTemporaryRouteConnection(
			temporaryNeighbors,
			startId,
			targetId,
			horizontalDistance(temporaryPositions[startId], temporaryPositions[targetId])
		)
	end

	local distances = {
		[startId] = 0,
	}
	local previous = {}
	local heap = {}
	heapPush(heap, { id = startId, cost = 0 })

	local function relax(fromId, neighbor)
		local nextCost = distances[fromId] + neighbor.cost
		if not distances[neighbor.id] or nextCost < distances[neighbor.id] then
			distances[neighbor.id] = nextCost
			previous[neighbor.id] = fromId
			heapPush(heap, { id = neighbor.id, cost = nextCost })
		end
	end

	while #heap > 0 do
		local current = heapPop(heap)
		if current and current.cost == distances[current.id] then
			if current.id == targetId then
				break
			end

			if current.id <= #graph.nodes then
				for _, neighbor in ipairs(graph.nodes[current.id].neighbors) do
					relax(current.id, neighbor)
				end
			end

			for _, neighbor in ipairs(temporaryNeighbors[current.id] or {}) do
				relax(current.id, neighbor)
			end
		end
	end

	if not distances[targetId] then
		return nil
	end

	local reversed = {}
	local nodeId = targetId
	while nodeId do
		table.insert(reversed, getRouteNodePosition(graph, temporaryPositions, nodeId))
		nodeId = previous[nodeId]
	end

	local path = {}
	for i = #reversed, 1, -1 do
		table.insert(path, reversed[i])
	end

	return path
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

local function updateRouteLine(service, cabPosition, targetPosition)
	local guide = service.gpsGuide
	if not guide then
		return
	end

	local routePath = findRoutePath(service.routeGraph, cabPosition, targetPosition)
	if not routePath or #routePath < 2 then
		for _, segment in ipairs(guide.segments) do
			setRouteSegmentVisible(segment, false)
		end
		return
	end

	if horizontalDistance(cabPosition, routePath[1]) > 2 then
		table.insert(routePath, 1, cabPosition)
	end

	if horizontalDistance(targetPosition, routePath[#routePath]) > 2 then
		table.insert(routePath, targetPosition)
	end

	local displayPoints, segmentCount = buildDisplayRoutePoints(routePath, guide.maxSegments)
	local heightOffset = getConfigNumber("passengerRouteHeightOffset", 1.65)
	local points = {}

	for _, point in ipairs(displayPoints) do
		local surfacePoint = getSurfacePosition(service, point, point.Y)
		table.insert(points, Vector3.new(point.X, surfacePoint.Y + heightOffset, point.Z))
	end

	local routeWidth = math.max(getConfigNumber("passengerRouteWidth", 2.6), 0.2)
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
		destination = nil,
		elapsedTime = 0,
		routeUpdateAccumulator = math.huge,
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

	function service:setDestination(destination)
		if typeof(destination) ~= "Vector3" then
			self:clearDestination()
			return
		end

		self.destination = destination
		self.routeUpdateAccumulator = math.huge
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
