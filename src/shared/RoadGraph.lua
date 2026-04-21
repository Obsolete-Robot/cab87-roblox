local RoadSampling = require(script.Parent:WaitForChild("RoadSampling"))

local RoadGraph = {}

local function getBucketKey(ix, iz)
	return tostring(ix) .. ":" .. tostring(iz)
end

function RoadGraph.new(options)
	options = options or {}
	local mergeDistance = math.max(tonumber(options.mergeDistance) or 0, 0)
	local bucketSize = math.max(tonumber(options.bucketSize) or mergeDistance, 4)
	return {
		nodes = {},
		edges = {},
		edgeLookup = {},
		nodeBuckets = {},
		bucketSize = bucketSize,
		mergeDistance = mergeDistance,
		maxMergeHeight = math.max(tonumber(options.maxMergeHeight) or 0, 0),
	}
end

function RoadGraph.getNearbyNodeIds(graph, position, radius)
	local bucketSize = graph.bucketSize
	local bucketRadius = math.max(1, math.ceil(radius / bucketSize))
	local centerX = math.floor(position.X / bucketSize)
	local centerZ = math.floor(position.Z / bucketSize)
	local nodeIds = {}

	for x = centerX - bucketRadius, centerX + bucketRadius do
		for z = centerZ - bucketRadius, centerZ + bucketRadius do
			local bucket = graph.nodeBuckets[getBucketKey(x, z)]
			if bucket then
				for _, nodeId in ipairs(bucket) do
					table.insert(nodeIds, nodeId)
				end
			end
		end
	end

	return nodeIds
end

function RoadGraph.addNode(graph, position)
	local mergeDistance = graph.mergeDistance
	if mergeDistance > 0 then
		for _, nodeId in ipairs(RoadGraph.getNearbyNodeIds(graph, position, mergeDistance)) do
			local node = graph.nodes[nodeId]
			if node
				and math.abs(node.position.Y - position.Y) <= graph.maxMergeHeight
				and RoadSampling.distanceXZ(node.position, position) <= mergeDistance
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
	local key = getBucketKey(ix, iz)
	local bucket = graph.nodeBuckets[key]
	if not bucket then
		bucket = {}
		graph.nodeBuckets[key] = bucket
	end
	table.insert(bucket, nodeId)

	return nodeId
end

function RoadGraph.addEdge(graph, a, b)
	if not a or not b or a == b then
		return
	end

	local key = if a < b then tostring(a) .. ":" .. tostring(b) else tostring(b) .. ":" .. tostring(a)
	if graph.edgeLookup[key] then
		return
	end

	local aPosition = graph.nodes[a].position
	local bPosition = graph.nodes[b].position
	local cost = RoadSampling.distanceXZ(aPosition, bPosition)
	if cost <= 0.1 then
		return
	end

	graph.edgeLookup[key] = true
	table.insert(graph.nodes[a].neighbors, { id = b, cost = cost })
	table.insert(graph.nodes[b].neighbors, { id = a, cost = cost })
	table.insert(graph.edges, { a = a, b = b, cost = cost })
end

function RoadGraph.connectJunction(graph, center, radius, extraRadius)
	local junctionId = RoadGraph.addNode(graph, center)
	local connectRadius = math.max((tonumber(radius) or 0) + (tonumber(extraRadius) or 0), graph.mergeDistance)

	for _, nodeId in ipairs(RoadGraph.getNearbyNodeIds(graph, center, connectRadius)) do
		local node = graph.nodes[nodeId]
		if nodeId ~= junctionId
			and node
			and math.abs(node.position.Y - center.Y) <= graph.maxMergeHeight
			and RoadSampling.distanceXZ(node.position, center) <= connectRadius
		then
			RoadGraph.addEdge(graph, junctionId, nodeId)
		end
	end
end

function RoadGraph.addSplineRecords(graph, records)
	for _, record in ipairs(records) do
		local firstNodeId = nil
		local previousNodeId = nil

		for _, position in ipairs(record.positions or {}) do
			local nodeId = RoadGraph.addNode(graph, position)
			if not firstNodeId then
				firstNodeId = nodeId
			end

			if previousNodeId then
				RoadGraph.addEdge(graph, previousNodeId, nodeId)
			end

			previousNodeId = nodeId
		end

		if firstNodeId and previousNodeId and firstNodeId ~= previousNodeId and record.closed == true then
			RoadGraph.addEdge(graph, previousNodeId, firstNodeId)
		end
	end
end

function RoadGraph.findNearestEdge(graph, position)
	if not graph then
		return nil
	end

	local best = nil
	local bestScore = math.huge
	for _, edge in ipairs(graph.edges) do
		local a = graph.nodes[edge.a].position
		local b = graph.nodes[edge.b].position
		local projected, alpha, distance = RoadSampling.projectPointToSegmentXZ(position, a, b)
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

function RoadGraph.findNearestNode(graph, position)
	local bestNodeId = nil
	local bestScore = math.huge

	for nodeId, node in ipairs(graph.nodes) do
		local score = RoadSampling.distanceXZSquared(position, node.position)
		if score < bestScore then
			bestScore = score
			bestNodeId = nodeId
		end
	end

	return bestNodeId
end

local function addTemporaryConnection(neighbors, a, b, cost)
	if not a or not b or a == b then
		return
	end

	neighbors[a] = neighbors[a] or {}
	neighbors[b] = neighbors[b] or {}
	table.insert(neighbors[a], { id = b, cost = cost })
	table.insert(neighbors[b], { id = a, cost = cost })
end

local function connectTemporaryNode(graph, neighbors, nodeId, position)
	local snap = RoadGraph.findNearestEdge(graph, position)
	if snap then
		local a = graph.nodes[snap.edge.a].position
		local b = graph.nodes[snap.edge.b].position
		addTemporaryConnection(neighbors, nodeId, snap.edge.a, RoadSampling.distanceXZ(snap.position, a))
		addTemporaryConnection(neighbors, nodeId, snap.edge.b, RoadSampling.distanceXZ(snap.position, b))
		return snap
	end

	local nearestNodeId = RoadGraph.findNearestNode(graph, position)
	if nearestNodeId then
		addTemporaryConnection(neighbors, nodeId, nearestNodeId, RoadSampling.distanceXZ(position, graph.nodes[nearestNodeId].position))
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

local function getNodePosition(graph, temporaryPositions, nodeId)
	return temporaryPositions[nodeId] or graph.nodes[nodeId].position
end

function RoadGraph.findPath(graph, startPosition, targetPosition)
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
	local startSnap = connectTemporaryNode(graph, temporaryNeighbors, startId, startPosition)
	local targetSnap = connectTemporaryNode(graph, temporaryNeighbors, targetId, targetPosition)

	if startSnap then
		temporaryPositions[startId] = startSnap.position
	end
	if targetSnap then
		temporaryPositions[targetId] = targetSnap.position
	end
	if startSnap and targetSnap and startSnap.edge == targetSnap.edge then
		addTemporaryConnection(
			temporaryNeighbors,
			startId,
			targetId,
			RoadSampling.distanceXZ(temporaryPositions[startId], temporaryPositions[targetId])
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
		table.insert(reversed, getNodePosition(graph, temporaryPositions, nodeId))
		nodeId = previous[nodeId]
	end

	local path = {}
	for i = #reversed, 1, -1 do
		table.insert(path, reversed[i])
	end

	return path
end

return RoadGraph
