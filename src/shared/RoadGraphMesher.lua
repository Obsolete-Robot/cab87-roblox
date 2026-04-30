local RoadGraphMesher = {}

local EPSILON = 1e-4

local function clonePoint(point)
	return Vector3.new(point.X, point.Y, point.Z)
end

local function horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function getDir(fromPoint, toPoint)
	local dx = toPoint.X - fromPoint.X
	local dz = toPoint.Z - fromPoint.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= EPSILON then
		return Vector3.xAxis
	end
	return Vector3.new(dx / length, 0, dz / length)
end

local function leftFromDir(dir)
	return Vector3.new(dir.Z, 0, -dir.X)
end

local function rightFromDir(dir)
	return Vector3.new(-dir.Z, 0, dir.X)
end

local function crossXZ(a, b)
	return a.X * b.Z - a.Z * b.X
end

local function pointAt(point, dir, distance)
	return Vector3.new(point.X + dir.X * distance, point.Y, point.Z + dir.Z * distance)
end

local function addTriangle(target, a, b, c)
	table.insert(target, { clonePoint(a), clonePoint(b), clonePoint(c) })
end

local function addQuadTriangles(target, a, b, c, d)
	addTriangle(target, a, b, c)
	addTriangle(target, a, c, d)
end

local function addPolygonToBounds(bounds, polygon)
	for _, point in ipairs(polygon or {}) do
		bounds.minX = math.min(bounds.minX, point.X)
		bounds.maxX = math.max(bounds.maxX, point.X)
		bounds.minZ = math.min(bounds.minZ, point.Z)
		bounds.maxZ = math.max(bounds.maxZ, point.Z)
	end
end

local function addTrianglesToBounds(bounds, triangles)
	for _, triangle in ipairs(triangles or {}) do
		addPolygonToBounds(bounds, triangle)
	end
end

local function cubicBezier(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	local mt = 1 - t
	local mt2 = mt * mt
	local mt3 = mt2 * mt
	return p0 * mt3 + p1 * (3 * mt2 * t) + p2 * (3 * mt * t2) + p3 * t3
end

local function ensurePiecewiseCubic(points)
	if #points < 2 or #points % 3 == 1 then
		return points
	end

	local result = { points[1] }
	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		table.insert(result, a:Lerp(b, 1 / 3))
		table.insert(result, a:Lerp(b, 2 / 3))
		table.insert(result, b)
	end
	return result
end

local function sampleSpline(points, segmentsPerCurve)
	local cubicPoints = ensurePiecewiseCubic(points)
	if #cubicPoints == 0 then
		return {}
	elseif #cubicPoints == 1 then
		return { cubicPoints[1] }
	elseif #cubicPoints < 4 then
		local result = {}
		local steps = math.max(math.floor(segmentsPerCurve or 15), 1)
		for i = 0, steps do
			table.insert(result, cubicPoints[1]:Lerp(cubicPoints[2], i / steps))
		end
		return result
	end

	local result = {}
	local steps = math.max(math.floor(segmentsPerCurve or 15), 1)
	for i = 1, #cubicPoints - 1, 3 do
		local p0 = cubicPoints[i]
		local p1 = cubicPoints[i + 1]
		local p2 = cubicPoints[i + 2]
		local p3 = cubicPoints[i + 3]
		if not (p0 and p1 and p2 and p3) then
			break
		end
		for step = 0, steps do
			if i == 1 or step > 0 then
				table.insert(result, cubicBezier(p0, p1, p2, p3, step / steps))
			end
		end
	end
	return result
end

local function nodesById(nodes)
	local lookup = {}
	for _, node in ipairs(nodes or {}) do
		lookup[node.id] = node
	end
	return lookup
end

local function getEdgeControlPoints(edge, nodeLookup)
	local sourceNode = nodeLookup[edge.source]
	if not sourceNode then
		return {}
	end

	local points = { sourceNode.point }
	for _, point in ipairs(edge.points or {}) do
		table.insert(points, point)
	end
	if edge.target then
		local targetNode = nodeLookup[edge.target]
		if targetNode then
			table.insert(points, targetNode.point)
		end
	end
	return points
end

local function getIncidentConnections(nodeId, edges)
	local connections = {}
	for _, edge in ipairs(edges or {}) do
		if edge.source == nodeId then
			table.insert(connections, {
				edge = edge,
				isSource = true,
			})
		end
		if edge.target == nodeId then
			table.insert(connections, {
				edge = edge,
				isSource = false,
			})
		end
	end
	return connections
end

local function connectionKey(edge, isSource)
	return tostring(edge.id) .. "_" .. tostring(isSource)
end

local function lineIntersectionWithParameters(a, dirA, b, dirB)
	local denom = crossXZ(dirA, dirB)
	if math.abs(denom) <= 1e-5 then
		return nil, nil, nil
	end

	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local tA = (dx * dirB.Z - dz * dirB.X) / denom
	local tB = (dx * dirA.Z - dz * dirA.X) / denom
	return Vector3.new(a.X + dirA.X * tA, a.Y, a.Z + dirA.Z * tA), tA, tB
end

local function calculateBothCornerPoints(center, dir1, width1, sw1, dir2, width2, sw2, chamferAngleDeg)
	local right1 = rightFromDir(dir1)
	local left2 = leftFromDir(dir2)

	local w1 = width1 * 0.5
	local w2 = width2 * 0.5
	local outerW1 = w1 + sw1
	local outerW2 = w2 + sw2

	local a = center + right1 * w1
	local b = center + left2 * w2
	local outerA = center + right1 * outerW1
	local outerB = center + left2 * outerW2

	local cross = crossXZ(dir1, dir2)
	if math.abs(cross) > 0.001 then
		local dx = b.X - a.X
		local dz = b.Z - a.Z
		local t = (dx * dir2.Z - dz * dir2.X) / cross
		local u = (dx * dir1.Z - dz * dir1.X) / cross

		local outerDx = outerB.X - outerA.X
		local outerDz = outerB.Z - outerA.Z
		local outerT = (outerDx * dir2.Z - outerDz * dir2.X) / cross
		local outerU = (outerDx * dir1.Z - outerDz * dir1.X) / cross

		local dot = dir1.X * dir2.X + dir1.Z * dir2.Z
		local interiorAngle = math.atan2(cross, dot)
		if interiorAngle < 0 then
			interiorAngle += math.pi * 2
		end
		local interiorAngleDeg = math.deg(interiorAngle)

		local chamferAngle = chamferAngleDeg or 70
		local isSharp = interiorAngleDeg < chamferAngle or interiorAngleDeg > (360 - chamferAngle)
		local isNearlyStraight = interiorAngleDeg > 150 and interiorAngleDeg < 210
		if isSharp or isNearlyStraight then
			local maxDistInner = math.max(w1, w2) * 1.5
			local maxDistOuter = math.max(outerW1, outerW2) * 1.5

			local straightCapInner = math.max(w1, w2) * 0.1
			local straightCapOuter = math.max(outerW1, outerW2) * 0.1

			local spikeCapT = math.max(w1, w2) * 5
			local spikeCapOuterT = math.max(outerW1, outerW2) * 5

			local function capDistance(value, straightCap, negativeCap, positiveCap)
				if isNearlyStraight then
					return math.clamp(value, -straightCap, straightCap)
				elseif value < 0 then
					return math.max(value, -negativeCap)
				end
				return math.min(value, positiveCap)
			end

			local capT = capDistance(t, straightCapInner, maxDistInner, spikeCapT)
			local capU = capDistance(u, straightCapInner, maxDistInner, spikeCapT)
			local capOuterT = capDistance(outerT, straightCapOuter, maxDistOuter, spikeCapOuterT)
			local capOuterU = capDistance(outerU, straightCapOuter, maxDistOuter, spikeCapOuterT)

			if capT ~= t or capU ~= u or capOuterT ~= outerT or capOuterU ~= outerU then
				return {
					pointAt(a, dir1, capT),
					pointAt(b, dir2, capU),
				}, {
					pointAt(outerA, dir1, capOuterT),
					pointAt(outerB, dir2, capOuterU),
				}
			end
		end

		return {
			pointAt(a, dir1, t),
		}, {
			pointAt(outerA, dir1, outerT),
		}
	end

	return { a, b }, { outerA, outerB }
end

local function getOutgoing(node, edges, nodeLookup)
	local outgoing = {}
	for _, connection in ipairs(getIncidentConnections(node.id, edges)) do
		local edge = connection.edge
		local controlPoints = getEdgeControlPoints(edge, nodeLookup)
		local isSource = connection.isSource
		local p2 = if isSource then controlPoints[2] else controlPoints[#controlPoints - 1]
		if p2 then
			local dir = getDir(node.point, p2)
			table.insert(outgoing, {
				edge = edge,
				angle = math.atan2(dir.Z, dir.X),
				isSource = isSource,
				dir = dir,
			})
		end
	end
	table.sort(outgoing, function(a, b)
		return a.angle < b.angle
	end)
	return outgoing
end

local function isTrueJunction(nodeId, edges, nodeLookup)
	local node = nodeLookup[nodeId]
	if not node then
		return false
	end

	local outgoing = getOutgoing(node, edges, nodeLookup)
	if #outgoing > 2 then
		return true
	elseif #outgoing < 2 then
		return false
	end

	local dot = outgoing[1].dir:Dot(outgoing[2].dir)
	return dot > -0.95
end

local function hasCrosswalk(edgeId, isSource, edges, nodeLookup)
	local edge = nil
	for _, candidate in ipairs(edges or {}) do
		if candidate.id == edgeId then
			edge = candidate
			break
		end
	end
	if not edge then
		return false
	end

	local nodeId = if isSource then edge.source else edge.target
	if not nodeId then
		return false
	end

	local node = nodeLookup[nodeId]
	if not node then
		return false
	end

	local outgoing = getOutgoing(node, edges, nodeLookup)
	if #outgoing > 2 then
		return true
	elseif #outgoing < 2 then
		return false
	end

	local dot = outgoing[1].dir:Dot(outgoing[2].dir)
	if dot < -0.95 then
		return false
	elseif dot > -0.25 then
		return true
	end

	local keys = {
		connectionKey(outgoing[1].edge, outgoing[1].isSource),
		connectionKey(outgoing[2].edge, outgoing[2].isSource),
	}
	table.sort(keys)
	return connectionKey(edge, isSource) == keys[1]
end

local function getEdgeClearance(nodeId, edge, isSourceQuery, nodes, edges, nodeLookup, settings)
	local node = nodeLookup[nodeId]
	if not node then
		return 0
	end

	local outgoing = getOutgoing(node, edges, nodeLookup)
	local count = #outgoing
	if count == 0 then
		return 0
	end

	local corners = {}
	local outerCorners = {}
	for i = 1, count do
		local r1 = outgoing[i]
		local r2 = outgoing[(i % count) + 1]
		local sidewalk = math.max(r1.edge.sidewalk or settings.sidewalkWidth, r2.edge.sidewalk or settings.sidewalkWidth)
		if count == 1 then
			local left = leftFromDir(r1.dir)
			local right = rightFromDir(r1.dir)
			local width = r1.edge.width * 0.5
			local outerWidth = width + sidewalk
			corners[i] = {
				node.point + left * width,
				node.point + right * width,
			}
			outerCorners[i] = {
				node.point + left * outerWidth,
				node.point + right * outerWidth,
			}
		else
			local innerPoints, outerPoints = calculateBothCornerPoints(
				node.point,
				r1.dir,
				r1.edge.width,
				sidewalk,
				r2.dir,
				r2.edge.width,
				sidewalk,
				settings.chamferAngleDeg
			)
			corners[i] = innerPoints
			outerCorners[i] = outerPoints
		end
	end

	local outIndex = nil
	for index, outgoingEdge in ipairs(outgoing) do
		if outgoingEdge.edge == edge and outgoingEdge.isSource == isSourceQuery then
			outIndex = index
			break
		end
	end
	if not outIndex then
		return 0
	end

	local previousIndex = outIndex - 1
	if previousIndex < 1 then
		previousIndex = count
	end
	local outgoingEdge = outgoing[outIndex]
	local baseLeft = if count == 1 then corners[1][1] else corners[previousIndex][#corners[previousIndex]]
	local baseRight = if count == 1 then corners[1][2] else corners[outIndex][1]
	local outerBaseLeft = if count == 1 then outerCorners[1][1] else outerCorners[previousIndex][#outerCorners[previousIndex]]
	local outerBaseRight = if count == 1 then outerCorners[1][2] else outerCorners[outIndex][1]
	local dir = outgoingEdge.dir
	return math.max(
		(baseLeft - node.point):Dot(dir),
		(baseRight - node.point):Dot(dir),
		(outerBaseLeft - node.point):Dot(dir),
		(outerBaseRight - node.point):Dot(dir)
	)
end

local function getExtendedEdgeControlPoints(edge, nodes, edges, nodeLookup, settings)
	local basePoints = getEdgeControlPoints(edge, nodeLookup)
	if #basePoints < 2 then
		return basePoints
	end

	local result = {}
	local p0 = basePoints[1]
	local u1 = basePoints[2]
	local dir0 = getDir(p0, u1)
	local sourceLength = horizontalDistance(p0, u1)
	local sourceClearance = getEdgeClearance(edge.source, edge, true, nodes, edges, nodeLookup, settings)
		+ (if isTrueJunction(edge.source, edges, nodeLookup) then settings.crosswalkWidth else 0)
	if #basePoints == 2 and sourceClearance > sourceLength * 0.5 - 5 then
		sourceClearance = math.max(0, sourceLength * 0.5 - 5)
	elseif #basePoints > 2 and sourceClearance > sourceLength - 5 then
		sourceClearance = math.max(0, sourceLength - 5)
	end
	local sourceCut = p0 + dir0 * sourceClearance

	table.insert(result, p0)
	table.insert(result, p0:Lerp(sourceCut, 1 / 3))
	table.insert(result, p0:Lerp(sourceCut, 2 / 3))
	table.insert(result, sourceCut)

	local pN = basePoints[#basePoints]
	local beforeLast = basePoints[#basePoints - 1]
	local dirN = getDir(pN, beforeLast)
	local targetLength = horizontalDistance(pN, beforeLast)
	local targetClearance = if edge.target
		then getEdgeClearance(edge.target, edge, false, nodes, edges, nodeLookup, settings)
			+ (if isTrueJunction(edge.target, edges, nodeLookup) then settings.crosswalkWidth else 0)
		else 0
	if #basePoints == 2 and targetClearance > targetLength * 0.5 - 5 then
		targetClearance = math.max(0, targetLength * 0.5 - 5)
	elseif #basePoints > 2 and targetClearance > targetLength - 5 then
		targetClearance = math.max(0, targetLength - 5)
	end
	local targetCut = pN + dirN * targetClearance

	if #basePoints > 2 then
		for i = 2, #basePoints - 1 do
			table.insert(result, basePoints[i])
		end

		table.insert(result, targetCut)
		table.insert(result, targetCut:Lerp(pN, 1 / 3))
		table.insert(result, targetCut:Lerp(pN, 2 / 3))
		table.insert(result, pN)
	else
		table.insert(result, sourceCut:Lerp(targetCut, 1 / 3))
		table.insert(result, sourceCut:Lerp(targetCut, 2 / 3))
		table.insert(result, targetCut)
		table.insert(result, targetCut:Lerp(pN, 1 / 3))
		table.insert(result, targetCut:Lerp(pN, 2 / 3))
		table.insert(result, pN)
	end

	return result
end

local function sampleEdgeSpline(edge, nodes, edges, nodeLookup, settings)
	return sampleSpline(getExtendedEdgeControlPoints(edge, nodes, edges, nodeLookup, settings), settings.splineSegments)
end

local function getEdgeBases(node, edge, isSource, nodeCorners)
	local corners = nodeCorners[node.id]
	if not corners then
		return nil
	end
	local bases = corners[connectionKey(edge, isSource)] or corners[edge.id]
	if not bases or #bases < 2 then
		return nil
	end
	return bases[1], bases[2]
end

local function makeMeshData()
	return {
		roadTriangles = {},
		sidewalkTriangles = {},
		crosswalkTriangles = {},
		hubs = {},
		roadPolygons = {},
		sidewalkPolygons = {},
		crosswalks = {},
		centerLines = {},
		bounds = {
			minX = math.huge,
			maxX = -math.huge,
			minZ = math.huge,
			maxZ = -math.huge,
		},
	}
end

function RoadGraphMesher.buildNetworkMesh(graph, options)
	options = options or {}
	local settings = table.clone(graph.settings or {})
	settings.chamferAngleDeg = tonumber(options.chamferAngleDeg) or tonumber(settings.chamferAngleDeg) or 70
	settings.crosswalkWidth = tonumber(options.crosswalkWidth) or tonumber(settings.crosswalkWidth) or 14
	settings.sidewalkWidth = tonumber(options.sidewalkWidth) or tonumber(settings.sidewalkWidth) or 12
	settings.splineSegments = math.max(math.floor(tonumber(options.splineSegments) or tonumber(settings.splineSegments) or 15), 1)

	local nodes = graph.nodes or {}
	local edges = graph.edges or {}
	local nodeLookup = graph.nodeLookup or nodesById(nodes)
	local mesh = makeMeshData()
	local edgeSplines = {}
	for _, edge in ipairs(edges) do
		edgeSplines[edge.id] = sampleEdgeSpline(edge, nodes, edges, nodeLookup, settings)
	end

	local nodeClearances = {}
	local nodeCorners = {}
	local nodeOuterCorners = {}

	for _, node in ipairs(nodes) do
		local outgoing = getOutgoing(node, edges, nodeLookup)
		local count = #outgoing
		if count == 0 then
			continue
		end

		local corners = {}
		local outerCorners = {}
		for i = 1, count do
			local r1 = outgoing[i]
			local r2 = outgoing[(i % count) + 1]
			local sidewalk = math.max(r1.edge.sidewalk or settings.sidewalkWidth, r2.edge.sidewalk or settings.sidewalkWidth)
			if count == 1 then
				local left = leftFromDir(r1.dir)
				local right = rightFromDir(r1.dir)
				local width = r1.edge.width * 0.5
				local outerWidth = width + sidewalk
				corners[i] = {
					points = {
						node.point + left * width,
						node.point + right * width,
					},
					sidewalkWidth = sidewalk,
				}
				outerCorners[i] = {
					node.point + left * outerWidth,
					node.point + right * outerWidth,
				}
			else
				local innerPoints, outerPoints = calculateBothCornerPoints(
					node.point,
					r1.dir,
					r1.edge.width,
					sidewalk,
					r2.dir,
					r2.edge.width,
					sidewalk,
					settings.chamferAngleDeg
				)
				corners[i] = {
					points = innerPoints,
					sidewalkWidth = sidewalk,
				}
				outerCorners[i] = outerPoints
			end
		end

		local hubPolygon = {}
		local hubOuterPolygon = {}
		local clearances = {}
		local squaredBases = {}
		local squaredOuterBases = {}

		for i = 1, count do
			for _, point in ipairs(corners[i].points) do
				table.insert(hubPolygon, point)
			end
			for _, point in ipairs(outerCorners[i]) do
				table.insert(hubOuterPolygon, point)
			end

			local rIndex = (i % count) + 1
			local outgoingEdge = outgoing[rIndex]
			local baseLeft = if count == 1 then corners[1].points[1] else corners[i].points[#corners[i].points]
			local baseRight = if count == 1 then corners[1].points[2] else corners[rIndex].points[1]
			local outerBaseLeft = if count == 1 then outerCorners[1][1] else outerCorners[i][#outerCorners[i]]
			local outerBaseRight = if count == 1 then outerCorners[1][2] else outerCorners[rIndex][1]

			local dir = outgoingEdge.dir
			local distLeft = (baseLeft - node.point):Dot(dir)
			local distRight = (baseRight - node.point):Dot(dir)
			local outerDistLeft = (outerBaseLeft - node.point):Dot(dir)
			local outerDistRight = (outerBaseRight - node.point):Dot(dir)
			local maxDist = math.max(distLeft, distRight, outerDistLeft, outerDistRight)

			if count > 1 then
				local squaredLeft = baseLeft + dir * (maxDist - distLeft)
				local squaredRight = baseRight + dir * (maxDist - distRight)
				local outerSquaredLeft = outerBaseLeft + dir * (maxDist - outerDistLeft)
				local outerSquaredRight = outerBaseRight + dir * (maxDist - outerDistRight)

				if distLeft < maxDist - 0.01 then
					table.insert(hubPolygon, squaredLeft)
					local polygon = { outerBaseLeft, baseLeft, squaredLeft, outerSquaredLeft }
					table.insert(mesh.sidewalkPolygons, polygon)
					addQuadTriangles(mesh.sidewalkTriangles, baseLeft, squaredLeft, outerSquaredLeft, outerBaseLeft)
				end
				if distRight < maxDist - 0.01 then
					table.insert(hubPolygon, squaredRight)
					local polygon = { outerSquaredRight, squaredRight, baseRight, outerBaseRight }
					table.insert(mesh.sidewalkPolygons, polygon)
					addTriangle(mesh.sidewalkTriangles, baseRight, outerSquaredRight, squaredRight)
					addTriangle(mesh.sidewalkTriangles, baseRight, outerBaseRight, outerSquaredRight)
				end

				if outerDistLeft < maxDist - 0.01 then
					table.insert(hubOuterPolygon, outerSquaredLeft)
				end
				if outerDistRight < maxDist - 0.01 then
					table.insert(hubOuterPolygon, outerSquaredRight)
				end

				local key = connectionKey(outgoingEdge.edge, outgoingEdge.isSource)
				squaredBases[key] = { squaredLeft, squaredRight }
				squaredOuterBases[key] = { outerSquaredLeft, outerSquaredRight }
			else
				local key = connectionKey(outgoingEdge.edge, outgoingEdge.isSource)
				squaredBases[key] = { baseLeft, baseRight }
				squaredOuterBases[key] = { outerBaseLeft, outerBaseRight }
			end

			clearances[connectionKey(outgoingEdge.edge, outgoingEdge.isSource)] = maxDist
		end

		table.insert(mesh.hubs, {
			id = node.id,
			polygon = hubPolygon,
			corners = corners,
			outerPolygon = hubOuterPolygon,
			outerCorners = outerCorners,
		})

		if #hubPolygon >= 3 then
			for i = 1, #hubPolygon do
				addTriangle(mesh.roadTriangles, node.point, hubPolygon[i], hubPolygon[(i % #hubPolygon) + 1])
			end
		end

		for i = 1, #corners do
			local innerPoints = corners[i].points
			local outerPoints = outerCorners[i]
			local polygon = {}
			for _, point in ipairs(outerPoints) do
				table.insert(polygon, point)
			end
			for j = #innerPoints, 1, -1 do
				table.insert(polygon, innerPoints[j])
			end
			table.insert(mesh.sidewalkPolygons, polygon)

			for j = 1, #innerPoints - 1 do
				addTriangle(mesh.sidewalkTriangles, innerPoints[j], outerPoints[j], outerPoints[j + 1])
				addTriangle(mesh.sidewalkTriangles, innerPoints[j], outerPoints[j + 1], innerPoints[j + 1])
			end
		end

		nodeClearances[node.id] = clearances
		nodeCorners[node.id] = squaredBases
		nodeOuterCorners[node.id] = squaredOuterBases
	end

	for _, edge in ipairs(edges) do
		local sourceNode = nodeLookup[edge.source]
		local targetNode = edge.target and nodeLookup[edge.target] or nil
		if not sourceNode then
			continue
		end

		local spline = edgeSplines[edge.id] or {}
		if #spline < 2 then
			continue
		end

		local halfWidth = edge.width * 0.5
		local sourceClearance = (nodeClearances[sourceNode.id] and nodeClearances[sourceNode.id][connectionKey(edge, true)]) or 0
		local targetClearance = if targetNode then ((nodeClearances[targetNode.id] and nodeClearances[targetNode.id][connectionKey(edge, false)]) or 0) else 0
		local baseLeft, baseRight = getEdgeBases(sourceNode, edge, true, nodeCorners)
		local outerBaseLeft, outerBaseRight = getEdgeBases(sourceNode, edge, true, nodeOuterCorners)
		local targetBaseLeft, targetBaseRight
		local outerTargetBaseLeft, outerTargetBaseRight
		if targetNode then
			targetBaseLeft, targetBaseRight = getEdgeBases(targetNode, edge, false, nodeCorners)
			outerTargetBaseLeft, outerTargetBaseRight = getEdgeBases(targetNode, edge, false, nodeOuterCorners)
		end

		local leftPoints = {}
		local rightPoints = {}
		local outerLeftPoints = {}
		local outerRightPoints = {}
		local centerLine = {}

		local controlPoints = getEdgeControlPoints(edge, nodeLookup)
		local sourceDir = getDir(controlPoints[1], controlPoints[2] or spline[2])
		local targetDir = if targetNode then getDir(controlPoints[#controlPoints], controlPoints[#controlPoints - 1]) else Vector3.zero

		for j = 2, #spline do
			local p1 = spline[j - 1]
			local p2 = spline[j]
			local srcDist = horizontalDistance(p2, sourceNode.point)
			if srcDist < sourceClearance + edge.width + 20 then
				local sourceProjection = (p2 - sourceNode.point):Dot(sourceDir)
				if sourceProjection < sourceClearance + 1 then
					continue
				end
			end

			if targetNode and j >= #spline then
				continue
			end

			if targetNode then
				local targetDistance = horizontalDistance(p2, targetNode.point)
				if targetDistance < targetClearance + edge.width + 20 then
					local targetProjection = (p2 - targetNode.point):Dot(targetDir)
					if targetProjection < targetClearance + 1 then
						continue
					end
				end
			end

			table.insert(centerLine, p2)
			local dir = getDir(p1, p2)
			if j < #spline then
				dir = getDir(spline[j - 1], spline[j + 1])
			end
			local left = leftFromDir(dir)
			local right = rightFromDir(dir)
			local outerWidth = halfWidth + (edge.sidewalk or settings.sidewalkWidth)
			table.insert(leftPoints, p2 + left * halfWidth)
			table.insert(rightPoints, p2 + right * halfWidth)
			table.insert(outerLeftPoints, p2 + left * outerWidth)
			table.insert(outerRightPoints, p2 + right * outerWidth)
		end

		if baseLeft and baseRight and outerBaseLeft and outerBaseRight then
			local crosswalkWidth = settings.crosswalkWidth

			if isTrueJunction(sourceNode.id, edges, nodeLookup) then
				local startDir = getDir(spline[1], spline[math.min(2, #spline)])
				local newLeft = baseLeft + startDir * crosswalkWidth
				local newRight = baseRight + startDir * crosswalkWidth
				local newOuterLeft = outerBaseLeft + startDir * crosswalkWidth
				local newOuterRight = outerBaseRight + startDir * crosswalkWidth
				local polygon = { baseLeft, baseRight, newRight, newLeft }
				if hasCrosswalk(edge.id, true, edges, nodeLookup) then
					table.insert(mesh.crosswalks, { edgeId = edge.id, nodeId = sourceNode.id, polygon = polygon })
					addQuadTriangles(mesh.crosswalkTriangles, baseLeft, baseRight, newRight, newLeft)
				end
				table.insert(mesh.sidewalkPolygons, { outerBaseLeft, baseLeft, newLeft, newOuterLeft })
				table.insert(mesh.sidewalkPolygons, { baseRight, outerBaseRight, newOuterRight, newRight })
				addQuadTriangles(mesh.sidewalkTriangles, outerBaseLeft, baseLeft, newLeft, newOuterLeft)
				addQuadTriangles(mesh.sidewalkTriangles, baseRight, outerBaseRight, newOuterRight, newRight)
				baseLeft, baseRight = newLeft, newRight
				outerBaseLeft, outerBaseRight = newOuterLeft, newOuterRight
			end

			local fullCenterLine = { (baseLeft + baseRight) * 0.5 }
			for _, point in ipairs(centerLine) do
				table.insert(fullCenterLine, point)
			end

			local polygon = { baseLeft, baseRight }
			local outerPolygon = { outerBaseLeft, outerBaseRight }
			for _, point in ipairs(rightPoints) do
				table.insert(polygon, point)
			end
			for _, point in ipairs(outerRightPoints) do
				table.insert(outerPolygon, point)
			end

			if targetBaseLeft and targetBaseRight and outerTargetBaseLeft and outerTargetBaseRight then
				if isTrueJunction(targetNode.id, edges, nodeLookup) then
					local endDir = getDir(spline[#spline], spline[math.max(1, #spline - 1)])
					local newLeft = targetBaseLeft + endDir * crosswalkWidth
					local newRight = targetBaseRight + endDir * crosswalkWidth
					local newOuterLeft = outerTargetBaseLeft + endDir * crosswalkWidth
					local newOuterRight = outerTargetBaseRight + endDir * crosswalkWidth
					local crosswalkPolygon = { targetBaseLeft, targetBaseRight, newRight, newLeft }
					if hasCrosswalk(edge.id, false, edges, nodeLookup) then
						table.insert(mesh.crosswalks, { edgeId = edge.id, nodeId = targetNode.id, polygon = crosswalkPolygon })
						addQuadTriangles(mesh.crosswalkTriangles, targetBaseLeft, targetBaseRight, newRight, newLeft)
					end
					table.insert(mesh.sidewalkPolygons, { outerTargetBaseLeft, targetBaseLeft, newLeft, newOuterLeft })
					table.insert(mesh.sidewalkPolygons, { targetBaseRight, outerTargetBaseRight, newOuterRight, newRight })
					addQuadTriangles(mesh.sidewalkTriangles, outerTargetBaseLeft, targetBaseLeft, newLeft, newOuterLeft)
					addQuadTriangles(mesh.sidewalkTriangles, targetBaseRight, outerTargetBaseRight, newOuterRight, newRight)
					targetBaseLeft, targetBaseRight = newLeft, newRight
					outerTargetBaseLeft, outerTargetBaseRight = newOuterLeft, newOuterRight
				end

				table.insert(fullCenterLine, (targetBaseLeft + targetBaseRight) * 0.5)
				table.insert(polygon, targetBaseLeft)
				table.insert(polygon, targetBaseRight)
				table.insert(outerPolygon, outerTargetBaseLeft)
				table.insert(outerPolygon, outerTargetBaseRight)
			else
				if #leftPoints == 0 then
					local dir = getDir(sourceNode.point, spline[#spline])
					local p2 = spline[#spline]
					local outerWidth = halfWidth + (edge.sidewalk or settings.sidewalkWidth)
					table.insert(leftPoints, p2 + leftFromDir(dir) * halfWidth)
					table.insert(rightPoints, p2 + rightFromDir(dir) * halfWidth)
					table.insert(outerLeftPoints, p2 + leftFromDir(dir) * outerWidth)
					table.insert(outerRightPoints, p2 + rightFromDir(dir) * outerWidth)
					table.insert(polygon, rightPoints[#rightPoints])
					table.insert(outerPolygon, outerRightPoints[#outerRightPoints])
					table.insert(fullCenterLine, p2)
				else
					local lastLeft = leftPoints[#leftPoints]
					local lastRight = rightPoints[#rightPoints]
					table.insert(fullCenterLine, (lastLeft + lastRight) * 0.5)
				end
			end

			for i = #leftPoints, 1, -1 do
				table.insert(polygon, leftPoints[i])
			end
			for i = #outerLeftPoints, 1, -1 do
				table.insert(outerPolygon, outerLeftPoints[i])
			end

			fullCenterLine.edgeId = edge.id
			fullCenterLine.width = edge.width
			table.insert(mesh.centerLines, fullCenterLine)
			table.insert(mesh.roadPolygons, {
				id = edge.id,
				polygon = polygon,
				leftCurve = leftPoints,
				rightCurve = rightPoints,
				outerPolygon = outerPolygon,
				outerLeftCurve = outerLeftPoints,
				outerRightCurve = outerRightPoints,
				sidewalkWidth = edge.sidewalk or settings.sidewalkWidth,
			})

			local currentLeft = baseLeft
			local currentRight = baseRight
			local currentOuterLeft = outerBaseLeft
			local currentOuterRight = outerBaseRight
			for j = 1, #leftPoints do
				local nextLeft = leftPoints[j]
				local nextRight = rightPoints[j]
				local nextOuterLeft = outerLeftPoints[j]
				local nextOuterRight = outerRightPoints[j]
				addQuadTriangles(mesh.roadTriangles, currentLeft, currentRight, nextRight, nextLeft)
				addQuadTriangles(mesh.sidewalkTriangles, currentOuterLeft, currentLeft, nextLeft, nextOuterLeft)
				addTriangle(mesh.sidewalkTriangles, currentRight, currentOuterRight, nextOuterRight)
				addTriangle(mesh.sidewalkTriangles, currentRight, nextOuterRight, nextRight)
				currentLeft = nextLeft
				currentRight = nextRight
				currentOuterLeft = nextOuterLeft
				currentOuterRight = nextOuterRight
			end

			if targetBaseLeft and targetBaseRight and outerTargetBaseLeft and outerTargetBaseRight then
				addTriangle(mesh.roadTriangles, currentLeft, currentRight, targetBaseLeft)
				addTriangle(mesh.roadTriangles, currentLeft, targetBaseLeft, targetBaseRight)
				addTriangle(mesh.sidewalkTriangles, currentOuterLeft, currentLeft, targetBaseRight)
				addTriangle(mesh.sidewalkTriangles, currentOuterLeft, targetBaseRight, outerTargetBaseRight)
				addTriangle(mesh.sidewalkTriangles, currentRight, currentOuterRight, outerTargetBaseLeft)
				addTriangle(mesh.sidewalkTriangles, currentRight, outerTargetBaseLeft, targetBaseLeft)
			end
		end
	end

	addTrianglesToBounds(mesh.bounds, mesh.roadTriangles)
	addTrianglesToBounds(mesh.bounds, mesh.sidewalkTriangles)
	addTrianglesToBounds(mesh.bounds, mesh.crosswalkTriangles)
	return mesh
end

function RoadGraphMesher.sampleEdgeCenterLines(graph, options)
	return RoadGraphMesher.buildNetworkMesh(graph, options).centerLines
end

return RoadGraphMesher
