local RoadGraphMesher = {}

local EPSILON = 1e-4
local DEFAULT_MESH_RESOLUTION = 20

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

local function signedAreaXZ(points)
	local area = 0
	for index, point in ipairs(points or {}) do
		local nextPoint = points[(index % #points) + 1]
		area += point.X * nextPoint.Z - nextPoint.X * point.Z
	end
	return area
end

local function removeConsecutiveDuplicatePoints(points, epsilon)
	local result = {}
	local threshold = epsilon or 0.01
	for _, point in ipairs(points or {}) do
		local previous = result[#result]
		if not previous or horizontalDistance(previous, point) > threshold then
			table.insert(result, point)
		end
	end

	while #result > 1 and horizontalDistance(result[1], result[#result]) <= threshold do
		table.remove(result, #result)
	end
	return result
end

local function pointInTriangleXZ(point, a, b, c)
	local v0x = c.X - a.X
	local v0z = c.Z - a.Z
	local v1x = b.X - a.X
	local v1z = b.Z - a.Z
	local v2x = point.X - a.X
	local v2z = point.Z - a.Z

	local dot00 = v0x * v0x + v0z * v0z
	local dot01 = v0x * v1x + v0z * v1z
	local dot02 = v0x * v2x + v0z * v2z
	local dot11 = v1x * v1x + v1z * v1z
	local dot12 = v1x * v2x + v1z * v2z
	local denom = dot00 * dot11 - dot01 * dot01
	if math.abs(denom) <= EPSILON then
		return false
	end

	local invDenom = 1 / denom
	local u = (dot11 * dot02 - dot01 * dot12) * invDenom
	local v = (dot00 * dot12 - dot01 * dot02) * invDenom
	return u > EPSILON and v > EPSILON and (u + v) < 1 - EPSILON
end

local function triangulateSimplePolygon(points)
	local boundary = removeConsecutiveDuplicatePoints(points, 0.01)
	if #boundary < 3 then
		return {}
	end

	local area = signedAreaXZ(boundary)
	if math.abs(area) <= EPSILON then
		return {}
	end

	local isCounterClockwise = area > 0
	local indices = {}
	for index = 1, #boundary do
		table.insert(indices, index)
	end

	local triangles = {}
	local guard = 0
	local maxIterations = #boundary * #boundary
	while #indices > 3 and guard < maxIterations do
		guard += 1
		local earIndex = nil

		for i = 1, #indices do
			local previousIndex = indices[((i - 2) % #indices) + 1]
			local currentIndex = indices[i]
			local nextIndex = indices[(i % #indices) + 1]
			local a = boundary[previousIndex]
			local b = boundary[currentIndex]
			local c = boundary[nextIndex]
			local ab = b - a
			local bc = c - b
			local cross = crossXZ(ab, bc)
			local convex = if isCounterClockwise then cross > EPSILON else cross < -EPSILON

			if convex then
				local containsPoint = false
				for _, candidateIndex in ipairs(indices) do
					if candidateIndex ~= previousIndex and candidateIndex ~= currentIndex and candidateIndex ~= nextIndex then
						if pointInTriangleXZ(boundary[candidateIndex], a, b, c) then
							containsPoint = true
							break
						end
					end
				end

				if not containsPoint then
					earIndex = i
					if isCounterClockwise then
						addTriangle(triangles, a, b, c)
					else
						addTriangle(triangles, a, c, b)
					end
					break
				end
			end
		end

		if not earIndex then
			break
		end
		table.remove(indices, earIndex)
	end

	if #indices == 3 then
		local a = boundary[indices[1]]
		local b = boundary[indices[2]]
		local c = boundary[indices[3]]
		if isCounterClockwise then
			addTriangle(triangles, a, b, c)
		else
			addTriangle(triangles, a, c, b)
		end
	end

	return triangles
end

local function cubicBezier(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	local mt = 1 - t
	local mt2 = mt * mt
	local mt3 = mt2 * mt
	return p0 * mt3 + p1 * (3 * mt2 * t) + p2 * (3 * mt * t2) + p3 * t3
end

local function sanitizeMeshResolution(value)
	local number = tonumber(value)
	if not number or number ~= number or number == math.huge or number == -math.huge then
		return DEFAULT_MESH_RESOLUTION
	end
	return math.max(number, 1)
end

local function bezierLength(p0, p1, p2, p3)
	local length = 0
	local previous = p0
	local steps = 15
	for step = 1, steps do
		local t = step / steps
		local current = cubicBezier(p0, p1, p2, p3, t)
		length += horizontalDistance(previous, current)
		previous = current
	end
	return length
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

local function sampleSpline(points, segmentLength)
	local safeSegmentLength = sanitizeMeshResolution(segmentLength)
	local cubicPoints = ensurePiecewiseCubic(points)
	if #cubicPoints == 0 then
		return {}
	elseif #cubicPoints == 1 then
		return { cubicPoints[1] }
	elseif #cubicPoints < 4 then
		local result = {}
		local distance = horizontalDistance(cubicPoints[1], cubicPoints[2])
		local steps = math.max(math.ceil(distance / safeSegmentLength), 1)
		for i = 0, steps do
			table.insert(result, cubicPoints[1]:Lerp(cubicPoints[2], i / steps))
		end
		return result
	end

	local result = {}
	for i = 1, #cubicPoints - 1, 3 do
		local p0 = cubicPoints[i]
		local p1 = cubicPoints[i + 1]
		local p2 = cubicPoints[i + 2]
		local p3 = cubicPoints[i + 3]
		if not (p0 and p1 and p2 and p3) then
			break
		end
		local steps = math.max(math.ceil(bezierLength(p0, p1, p2, p3) / safeSegmentLength), 1)
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

local function getEdgeSidewalk(edge, settings)
	return math.max(tonumber(edge.sidewalk) or tonumber(settings and settings.sidewalkWidth) or 12, 0)
end

local function getEdgeSidewalkLeft(edge, settings)
	return math.max(tonumber(edge.sidewalkLeft) or getEdgeSidewalk(edge, settings), 0)
end

local function getEdgeSidewalkRight(edge, settings)
	return math.max(tonumber(edge.sidewalkRight) or getEdgeSidewalk(edge, settings), 0)
end

local function getOutgoingLeftSidewalk(outgoing, settings)
	if outgoing.isSource then
		return getEdgeSidewalkLeft(outgoing.edge, settings)
	end
	return getEdgeSidewalkRight(outgoing.edge, settings)
end

local function getOutgoingRightSidewalk(outgoing, settings)
	if outgoing.isSource then
		return getEdgeSidewalkRight(outgoing.edge, settings)
	end
	return getEdgeSidewalkLeft(outgoing.edge, settings)
end

local function getEdgeTransitionSmoothness(edge)
	return math.max(tonumber(edge.transitionSmoothness) or 0, 0)
end

local function getNodeTransitionSmoothness(node)
	return math.max(tonumber(node and node.transitionSmoothness) or 0, 0)
end

local function getOutgoingTransitionSmoothness(outgoing, node)
	return getEdgeTransitionSmoothness(outgoing.edge) + getNodeTransitionSmoothness(node)
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

local function calculateBothCornerPoints(center, dir1, width1, sw1, smoothness1, dir2, width2, sw2, smoothness2, chamferAngleDeg)
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

			local finalT = capT + smoothness1
			local finalU = capU + smoothness2
			local finalOuterT = capOuterT + smoothness1
			local finalOuterU = capOuterU + smoothness2

			if
				finalT ~= t
				or finalU ~= u
				or finalOuterT ~= outerT
				or finalOuterU ~= outerU
				or smoothness1 > 0
				or smoothness2 > 0
			then
				return {
					pointAt(a, dir1, finalT),
					pointAt(b, dir2, finalU),
				}, {
					pointAt(outerA, dir1, finalOuterT),
					pointAt(outerB, dir2, finalOuterU),
				}
			end
		end

		local finalT = t + smoothness1
		local finalU = u + smoothness2
		local finalOuterT = outerT + smoothness1
		local finalOuterU = outerU + smoothness2
		if smoothness1 > 0 or smoothness2 > 0 then
			return {
				pointAt(a, dir1, finalT),
				pointAt(b, dir2, finalU),
			}, {
				pointAt(outerA, dir1, finalOuterT),
				pointAt(outerB, dir2, finalOuterU),
			}
		end

		return {
			pointAt(a, dir1, t),
		}, {
			pointAt(outerA, dir1, outerT),
		}
	end

	return {
		pointAt(a, dir1, smoothness1),
		pointAt(b, dir2, smoothness2),
	}, {
		pointAt(outerA, dir1, smoothness1),
		pointAt(outerB, dir2, smoothness2),
	}
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
		local sidewalk1 = getOutgoingRightSidewalk(r1, settings)
		local sidewalk2 = getOutgoingLeftSidewalk(r2, settings)
		if count == 1 then
			local left = leftFromDir(r1.dir)
			local right = rightFromDir(r1.dir)
			local width = r1.edge.width * 0.5
			local outerWidthLeft = width + getOutgoingLeftSidewalk(r1, settings)
			local outerWidthRight = width + getOutgoingRightSidewalk(r1, settings)
			corners[i] = {
				node.point + left * width,
				node.point + right * width,
			}
			outerCorners[i] = {
				node.point + left * outerWidthLeft,
				node.point + right * outerWidthRight,
			}
		else
			local innerPoints, outerPoints = calculateBothCornerPoints(
				node.point,
				r1.dir,
				r1.edge.width,
				sidewalk1,
				getOutgoingTransitionSmoothness(r1, node),
				r2.dir,
				r2.edge.width,
				sidewalk2,
				getOutgoingTransitionSmoothness(r2, node),
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

	if #basePoints == 3 then
		local mid = basePoints[2]
		table.insert(result, sourceCut:Lerp(mid, 2 / 3))
		table.insert(result, targetCut:Lerp(mid, 2 / 3))
		table.insert(result, targetCut)
		table.insert(result, targetCut:Lerp(pN, 1 / 3))
		table.insert(result, targetCut:Lerp(pN, 2 / 3))
		table.insert(result, pN)
	elseif #basePoints > 2 then
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
	return sampleSpline(getExtendedEdgeControlPoints(edge, nodes, edges, nodeLookup, settings), settings.meshResolution)
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
		roadEdgeTriangles = {},
		roadHubTriangles = {},
		sidewalkTriangles = {},
		crosswalkTriangles = {},
		hubs = {},
		roadPolygons = {},
		polygonFillGroups = {},
		polygonFillTriangles = {},
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

local function findEdgeBetween(edges, firstNodeId, secondNodeId)
	for _, edge in ipairs(edges or {}) do
		if (edge.source == firstNodeId and edge.target == secondNodeId) or (edge.source == secondNodeId and edge.target == firstNodeId) then
			return edge
		end
	end
	return nil
end

local function appendCurve(target, curve, reverse)
	if reverse then
		for index = #(curve or {}), 1, -1 do
			table.insert(target, curve[index])
		end
	else
		for _, point in ipairs(curve or {}) do
			table.insert(target, point)
		end
	end
end

local function nearestPolygonPointIndex(polygon, point)
	local nearestIndex = nil
	local nearestDistance = math.huge
	for index, candidate in ipairs(polygon or {}) do
		local distance = horizontalDistance(candidate, point)
		if distance < nearestDistance then
			nearestIndex = index
			nearestDistance = distance
		end
	end
	return nearestIndex, nearestDistance
end

local function buildHubPath(polygon, startIndex, endIndex, step)
	local result = {}
	if not startIndex or not endIndex or #polygon == 0 then
		return result
	end

	local index = startIndex
	while #result < #polygon + 2 do
		table.insert(result, polygon[index])
		if index == endIndex then
			break
		end
		index += step
		if index > #polygon then
			index = 1
		elseif index < 1 then
			index = #polygon
		end
	end
	return result
end

local function buildPolygonFillMeshes(mesh, graph, settings)
	local polygonFills = graph.polygonFills or {}
	if #polygonFills == 0 then
		return
	end

	local nodes = graph.nodes or {}
	local edges = graph.edges or {}
	local nodeLookup = graph.nodeLookup or nodesById(nodes)
	local roadPolygonsById = {}
	for _, roadPolygon in ipairs(mesh.roadPolygons or {}) do
		roadPolygonsById[roadPolygon.id] = roadPolygon
	end

	local hubsById = {}
	for _, hub in ipairs(mesh.hubs or {}) do
		hubsById[hub.id] = hub
	end

	for fillIndex, fill in ipairs(polygonFills) do
		if type(fill) ~= "table" or type(fill.points) ~= "table" or #fill.points < 3 then
			continue
		end

		local fillNodes = {}
		for _, nodeId in ipairs(fill.points) do
			local node = nodeLookup[nodeId]
			if node then
				table.insert(fillNodes, node)
			end
		end
		if #fillNodes < 3 then
			continue
		end

		local nodePolygon = {}
		for _, node in ipairs(fillNodes) do
			table.insert(nodePolygon, node.point)
		end
		local isClockwise = signedAreaXZ(nodePolygon) > 0
		local segments = {}

		for index, firstNodeId in ipairs(fill.points) do
			local secondNodeId = fill.points[(index % #fill.points) + 1]
			local firstNode = nodeLookup[firstNodeId]
			local secondNode = nodeLookup[secondNodeId]
			if not (firstNode and secondNode) then
				continue
			end

			local edge = findEdgeBetween(edges, firstNodeId, secondNodeId)
			local roadPolygon = edge and roadPolygonsById[edge.id] or nil
			local curve = {}
			if roadPolygon then
				local isForward = edge.source == firstNodeId
				local useRightCurve = if isClockwise then isForward else not isForward
				local chosenCurve = if useRightCurve then roadPolygon.outerRightCurve else roadPolygon.outerLeftCurve
				if chosenCurve and #chosenCurve >= 2 then
					appendCurve(curve, chosenCurve, not isForward)
				end
			end

			if #curve < 2 then
				table.insert(curve, firstNode.point)
				table.insert(curve, secondNode.point)
			end
			table.insert(segments, {
				nodeId = secondNodeId,
				curve = curve,
			})
		end

		local boundaryPoints = {}
		for index, segment in ipairs(segments) do
			appendCurve(boundaryPoints, segment.curve, false)

			local nextSegment = segments[(index % #segments) + 1]
			local endPoint = segment.curve[#segment.curve]
			local nextStart = nextSegment and nextSegment.curve[1] or nil
			local hub = hubsById[segment.nodeId]
			if endPoint and nextStart and hub and #(hub.outerPolygon or {}) > 0 then
				local endIndex, endDistance = nearestPolygonPointIndex(hub.outerPolygon, endPoint)
				local startIndex, startDistance = nearestPolygonPointIndex(hub.outerPolygon, nextStart)
				local maxJoinDistance = math.max(tonumber(settings.sidewalkWidth) or 12, 12) * 12.5
				if endIndex and startIndex and endDistance < maxJoinDistance and startDistance < maxJoinDistance then
					local forwardPath = buildHubPath(hub.outerPolygon, endIndex, startIndex, 1)
					local backwardPath = buildHubPath(hub.outerPolygon, endIndex, startIndex, -1)
					local chosenPath = if isClockwise then backwardPath else forwardPath
					appendCurve(boundaryPoints, chosenPath, false)
				end
			end
		end

		local uniqueBoundaryPoints = removeConsecutiveDuplicatePoints(boundaryPoints, 0.01)
		local fillTriangles = triangulateSimplePolygon(uniqueBoundaryPoints)
		if #fillTriangles > 0 then
			local group = {
				id = fill.id or string.format("polygonFill%d", fillIndex),
				color = fill.color or "#10b981",
				triangles = fillTriangles,
			}
			table.insert(mesh.polygonFillGroups, group)
			for _, triangle in ipairs(fillTriangles) do
				table.insert(mesh.polygonFillTriangles, triangle)
			end
		end
	end
end

function RoadGraphMesher.buildNetworkMesh(graph, options)
	options = options or {}
	local settings = table.clone(graph.settings or {})
	settings.chamferAngleDeg = tonumber(options.chamferAngleDeg) or tonumber(settings.chamferAngleDeg) or 70
	settings.crosswalkWidth = tonumber(options.crosswalkWidth) or tonumber(settings.crosswalkWidth) or 14
	settings.sidewalkWidth = tonumber(options.sidewalkWidth) or tonumber(settings.sidewalkWidth) or 12
	settings.meshResolution = sanitizeMeshResolution(
		options.meshResolution or settings.meshResolution or options.splineSegments or settings.splineSegments
	)

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
			local sidewalk1 = getOutgoingRightSidewalk(r1, settings)
			local sidewalk2 = getOutgoingLeftSidewalk(r2, settings)
			if count == 1 then
				local left = leftFromDir(r1.dir)
				local right = rightFromDir(r1.dir)
				local width = r1.edge.width * 0.5
				local sidewalkLeft = getOutgoingLeftSidewalk(r1, settings)
				local sidewalkRight = getOutgoingRightSidewalk(r1, settings)
				local outerWidthLeft = width + sidewalkLeft
				local outerWidthRight = width + sidewalkRight
				corners[i] = {
					points = {
						node.point + left * width,
						node.point + right * width,
					},
					sidewalkWidth = math.max(sidewalkLeft, sidewalkRight),
				}
				outerCorners[i] = {
					node.point + left * outerWidthLeft,
					node.point + right * outerWidthRight,
				}
			else
				local innerPoints, outerPoints = calculateBothCornerPoints(
					node.point,
					r1.dir,
					r1.edge.width,
					sidewalk1,
					getOutgoingTransitionSmoothness(r1, node),
					r2.dir,
					r2.edge.width,
					sidewalk2,
					getOutgoingTransitionSmoothness(r2, node),
					settings.chamferAngleDeg
				)
				corners[i] = {
					points = innerPoints,
					sidewalkWidth = math.max(sidewalk1, sidewalk2),
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
				addTriangle(mesh.roadHubTriangles, node.point, hubPolygon[i], hubPolygon[(i % #hubPolygon) + 1])
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
			local outerLeftWidth = halfWidth + getEdgeSidewalkLeft(edge, settings)
			local outerRightWidth = halfWidth + getEdgeSidewalkRight(edge, settings)
			table.insert(leftPoints, p2 + left * halfWidth)
			table.insert(rightPoints, p2 + right * halfWidth)
			table.insert(outerLeftPoints, p2 + left * outerLeftWidth)
			table.insert(outerRightPoints, p2 + right * outerRightWidth)
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
					local outerLeftWidth = halfWidth + getEdgeSidewalkLeft(edge, settings)
					local outerRightWidth = halfWidth + getEdgeSidewalkRight(edge, settings)
					table.insert(leftPoints, p2 + leftFromDir(dir) * halfWidth)
					table.insert(rightPoints, p2 + rightFromDir(dir) * halfWidth)
					table.insert(outerLeftPoints, p2 + leftFromDir(dir) * outerLeftWidth)
					table.insert(outerRightPoints, p2 + rightFromDir(dir) * outerRightWidth)
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
				leftCurve = { baseLeft },
				rightCurve = { baseRight },
				outerPolygon = outerPolygon,
				outerLeftCurve = { outerBaseLeft },
				outerRightCurve = { outerBaseRight },
				sidewalkWidth = getEdgeSidewalk(edge, settings),
			})
			local roadPolygon = mesh.roadPolygons[#mesh.roadPolygons]
			for _, point in ipairs(leftPoints) do
				table.insert(roadPolygon.leftCurve, point)
			end
			for _, point in ipairs(rightPoints) do
				table.insert(roadPolygon.rightCurve, point)
			end
			for _, point in ipairs(outerLeftPoints) do
				table.insert(roadPolygon.outerLeftCurve, point)
			end
			for _, point in ipairs(outerRightPoints) do
				table.insert(roadPolygon.outerRightCurve, point)
			end
			if targetBaseLeft and targetBaseRight and outerTargetBaseLeft and outerTargetBaseRight then
				table.insert(roadPolygon.leftCurve, targetBaseRight)
				table.insert(roadPolygon.rightCurve, targetBaseLeft)
				table.insert(roadPolygon.outerLeftCurve, outerTargetBaseRight)
				table.insert(roadPolygon.outerRightCurve, outerTargetBaseLeft)
			end

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
				addQuadTriangles(mesh.roadEdgeTriangles, currentLeft, currentRight, nextRight, nextLeft)
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
				addTriangle(mesh.roadEdgeTriangles, currentLeft, currentRight, targetBaseLeft)
				addTriangle(mesh.roadEdgeTriangles, currentLeft, targetBaseLeft, targetBaseRight)
				addTriangle(mesh.sidewalkTriangles, currentOuterLeft, currentLeft, targetBaseRight)
				addTriangle(mesh.sidewalkTriangles, currentOuterLeft, targetBaseRight, outerTargetBaseRight)
				addTriangle(mesh.sidewalkTriangles, currentRight, currentOuterRight, outerTargetBaseLeft)
				addTriangle(mesh.sidewalkTriangles, currentRight, outerTargetBaseLeft, targetBaseLeft)
			end
		end
	end

	buildPolygonFillMeshes(mesh, graph, settings)

	addTrianglesToBounds(mesh.bounds, mesh.roadTriangles)
	addTrianglesToBounds(mesh.bounds, mesh.sidewalkTriangles)
	addTrianglesToBounds(mesh.bounds, mesh.crosswalkTriangles)
	addTrianglesToBounds(mesh.bounds, mesh.polygonFillTriangles)
	return mesh
end

function RoadGraphMesher.sampleEdgeCenterLines(graph, options)
	return RoadGraphMesher.buildNetworkMesh(graph, options).centerLines
end

return RoadGraphMesher
