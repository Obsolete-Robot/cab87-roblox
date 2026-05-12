local RoadGraphMesher = {}

local EPSILON = 1e-4
local DEFAULT_MESH_RESOLUTION = 20
local nodesById

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

local function polygonSignedAreaXZ(points)
	local area = 0
	for i = 1, #points do
		local p1 = points[i]
		local p2 = points[(i % #points) + 1]
		area += p1.X * p2.Z - p2.X * p1.Z
	end
	return area * 0.5
end

local function findEdgeBetween(edges, sourceId, targetId)
	for _, edge in ipairs(edges or {}) do
		if (edge.source == sourceId and edge.target == targetId) or (edge.source == targetId and edge.target == sourceId) then
			return edge
		end
	end
	return nil
end

local function findRoadPolygon(roadPolygons, edgeId)
	for _, roadPolygon in ipairs(roadPolygons or {}) do
		if roadPolygon.id == edgeId then
			return roadPolygon
		end
	end
	return nil
end

local function findHub(hubs, nodeId)
	for _, hub in ipairs(hubs or {}) do
		if hub.id == nodeId then
			return hub
		end
	end
	return nil
end

local function appendPoints(target, points, reverse)
	if not points then
		return
	end

	if reverse then
		for i = #points, 1, -1 do
			table.insert(target, points[i])
		end
	else
		for _, point in ipairs(points or {}) do
			table.insert(target, point)
		end
	end
end

local function orderedUniqueAroundCenter(center, points)
	local records = {}
	local used = {}

	for _, point in ipairs(points or {}) do
		if horizontalDistance(point, center) > EPSILON then
			local key = string.format("%.2f:%.2f", point.X, point.Z)
			if not used[key] then
				used[key] = true
				local dx = point.X - center.X
				local dz = point.Z - center.Z
				table.insert(records, {
					point = point,
					angle = math.atan2(dz, dx),
					distanceSq = dx * dx + dz * dz,
				})
			end
		end
	end

	table.sort(records, function(a, b)
		if math.abs(a.angle - b.angle) <= EPSILON then
			return a.distanceSq < b.distanceSq
		end
		return a.angle < b.angle
	end)

	local result = {}
	for _, record in ipairs(records) do
		table.insert(result, record.point)
	end
	return result
end

local function pointInPolygonXZ(point, polygon)
	if #polygon == 0 then
		return false
	end

	local isInside = false
	local minX = polygon[1].X
	local maxX = polygon[1].X
	local minZ = polygon[1].Z
	local maxZ = polygon[1].Z
	for index = 2, #polygon do
		minX = math.min(minX, polygon[index].X)
		maxX = math.max(maxX, polygon[index].X)
		minZ = math.min(minZ, polygon[index].Z)
		maxZ = math.max(maxZ, polygon[index].Z)
	end

	if point.X < minX or point.X > maxX or point.Z < minZ or point.Z > maxZ then
		return false
	end

	for i = 1, #polygon do
		local j = if i == 1 then #polygon else i - 1
		local pi = polygon[i]
		local pj = polygon[j]
		if
			(pi.Z > point.Z) ~= (pj.Z > point.Z)
			and point.X < (pj.X - pi.X) * (point.Z - pi.Z) / (pj.Z - pi.Z) + pi.X
		then
			isInside = not isInside
		end
	end

	return isInside
end

local function segmentIntersectXZ(p0, p1, p2, p3)
	local s1X = p1.X - p0.X
	local s1Z = p1.Z - p0.Z
	local s2X = p3.X - p2.X
	local s2Z = p3.Z - p2.Z

	local denom = -s2X * s1Z + s1X * s2Z
	if math.abs(denom) < 1e-10 then
		return nil
	end

	local s = (-s1Z * (p0.X - p2.X) + s1X * (p0.Z - p2.Z)) / denom
	local t = (s2X * (p0.Z - p2.Z) - s2Z * (p0.X - p2.X)) / denom

	if s >= 0 and s <= 1 and t >= 0 and t <= 1 then
		return Vector3.new(p0.X + t * s1X, p0.Y + t * (p1.Y - p0.Y), p0.Z + t * s1Z)
	end

	return nil
end

local function intersectSegmentPolygonXZ(p1, p2, polygon)
	local closest = nil
	local minDistance = math.huge
	for i = 1, #polygon do
		local poly1 = polygon[i]
		local poly2 = polygon[(i % #polygon) + 1]
		local intersection = segmentIntersectXZ(p1, p2, poly1, poly2)
		if intersection then
			local distance = horizontalDistance(intersection, p1)
			if distance < minDistance then
				minDistance = distance
				closest = intersection
			end
		end
	end
	return closest
end

local function circumcircleContains(point, a, b, c)
	local ax = a.X
	local az = a.Z
	local bx = b.X
	local bz = b.Z
	local cx = c.X
	local cz = c.Z

	local denom = 2 * (ax * (bz - cz) + bx * (cz - az) + cx * (az - bz))
	if math.abs(denom) <= EPSILON then
		return false
	end

	local aLen = ax * ax + az * az
	local bLen = bx * bx + bz * bz
	local cLen = cx * cx + cz * cz
	local ux = (aLen * (bz - cz) + bLen * (cz - az) + cLen * (az - bz)) / denom
	local uz = (aLen * (cx - bx) + bLen * (ax - cx) + cLen * (bx - ax)) / denom
	local dx = ux - point.X
	local dz = uz - point.Z
	local radiusDx = ux - ax
	local radiusDz = uz - az

	return dx * dx + dz * dz <= radiusDx * radiusDx + radiusDz * radiusDz + 0.001
end

local function edgeKey(a, b)
	if a < b then
		return tostring(a) .. ":" .. tostring(b)
	end
	return tostring(b) .. ":" .. tostring(a)
end

local function triangulateDelaunay(points)
	local pointCount = #points
	if pointCount < 3 then
		return {}
	end

	local minX = points[1].X
	local maxX = points[1].X
	local minZ = points[1].Z
	local maxZ = points[1].Z
	for index = 2, pointCount do
		local point = points[index]
		minX = math.min(minX, point.X)
		maxX = math.max(maxX, point.X)
		minZ = math.min(minZ, point.Z)
		maxZ = math.max(maxZ, point.Z)
	end

	local width = maxX - minX
	local height = maxZ - minZ
	local delta = math.max(width, height)
	if delta <= EPSILON then
		return {}
	end

	local midX = (minX + maxX) * 0.5
	local midZ = (minZ + maxZ) * 0.5
	local vertices = table.clone(points)
	table.insert(vertices, Vector3.new(midX - 20 * delta, 0, midZ - delta))
	table.insert(vertices, Vector3.new(midX, 0, midZ + 20 * delta))
	table.insert(vertices, Vector3.new(midX + 20 * delta, 0, midZ - delta))

	local superA = pointCount + 1
	local superB = pointCount + 2
	local superC = pointCount + 3
	local triangles = {
		{ superA, superB, superC },
	}

	for pointIndex = 1, pointCount do
		local point = vertices[pointIndex]
		local badTriangles = {}
		local badLookup = {}
		local boundaryEdges = {}

		for triangleIndex, triangle in ipairs(triangles) do
			if
				circumcircleContains(
					point,
					vertices[triangle[1]],
					vertices[triangle[2]],
					vertices[triangle[3]]
				)
			then
				table.insert(badTriangles, triangle)
				badLookup[triangleIndex] = true
			end
		end

		for _, triangle in ipairs(badTriangles) do
			local edges = {
				{ triangle[1], triangle[2] },
				{ triangle[2], triangle[3] },
				{ triangle[3], triangle[1] },
			}
			for _, edge in ipairs(edges) do
				local key = edgeKey(edge[1], edge[2])
				local record = boundaryEdges[key]
				if record then
					record.count += 1
				else
					boundaryEdges[key] = {
						a = edge[1],
						b = edge[2],
						count = 1,
					}
				end
			end
		end

		local retainedTriangles = {}
		for triangleIndex, triangle in ipairs(triangles) do
			if not badLookup[triangleIndex] then
				table.insert(retainedTriangles, triangle)
			end
		end
		triangles = retainedTriangles

		for _, edge in pairs(boundaryEdges) do
			if edge.count == 1 then
				table.insert(triangles, { edge.a, edge.b, pointIndex })
			end
		end
	end

	local result = {}
	for _, triangle in ipairs(triangles) do
		if triangle[1] <= pointCount and triangle[2] <= pointCount and triangle[3] <= pointCount then
			table.insert(result, triangle)
		end
	end
	return result
end

local function buildGridMesh(boundaryPoints)
	local totalSegLen = 0
	local count = 0
	for i = 1, #boundaryPoints - 1 do
		local distance = horizontalDistance(boundaryPoints[i + 1], boundaryPoints[i])
		if distance > 0.001 then
			totalSegLen += distance
			count += 1
		end
	end

	local spacing = if count > 0 then (totalSegLen / count) * 1.5 else 30
	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge
	for _, point in ipairs(boundaryPoints) do
		minX = math.min(minX, point.X)
		maxX = math.max(maxX, point.X)
		minZ = math.min(minZ, point.Z)
		maxZ = math.max(maxZ, point.Z)
	end

	local width = maxX - minX
	local height = maxZ - minZ
	if width > 10000 or height > 10000 then
		return {}
	end

	local internalPoints = {}
	for x = minX + spacing, maxX - EPSILON, spacing do
		for z = minZ + spacing, maxZ - EPSILON, spacing do
			local point = Vector3.new(x, 0, z)
			if pointInPolygonXZ(point, boundaryPoints) then
				local tooClose = false
				for _, boundaryPoint in ipairs(boundaryPoints) do
					if horizontalDistance(boundaryPoint, point) < spacing * 0.7 then
						tooClose = true
						break
					end
				end
				if not tooClose then
					table.insert(internalPoints, point)
				end
			end
		end
	end

	for index, point in ipairs(internalPoints) do
		local sumY = 0
		local sumW = 0
		for _, boundaryPoint in ipairs(boundaryPoints) do
			local distance = horizontalDistance(boundaryPoint, point)
			local weight = 1 / (distance * distance * distance + 0.0001)
			sumY += boundaryPoint.Y * weight
			sumW += weight
		end
		internalPoints[index] = Vector3.new(point.X, if sumW > 0 then sumY / sumW else 0, point.Z)
	end

	local allPoints = {}
	appendPoints(allPoints, boundaryPoints, false)
	appendPoints(allPoints, internalPoints, false)

	local used = {}
	local filteredPoints = {}
	for _, point in ipairs(allPoints) do
		local key = string.format("%.2f,%.2f", point.X, point.Z)
		if not used[key] then
			used[key] = true
			table.insert(filteredPoints, point)
		end
	end

	if #filteredPoints < 3 then
		return {}
	end

	local triangles = triangulateDelaunay(filteredPoints)
	local result = {}
	for _, triangle in ipairs(triangles) do
		local p0 = filteredPoints[triangle[1]]
		local p1 = filteredPoints[triangle[2]]
		local p2 = filteredPoints[triangle[3]]
		local centroid = Vector3.new((p0.X + p1.X + p2.X) / 3, 0, (p0.Z + p1.Z + p2.Z) / 3)
		if pointInPolygonXZ(centroid, boundaryPoints) then
			addTriangle(result, p0, p1, p2)
		end
	end

	return result
end

local function buildPolygonFillTriangles(mesh, graph, edgeSplines)
	local polygonFills = graph.polygonFills or {}
	if #polygonFills == 0 then
		return
	end

	local nodes = graph.nodes or {}
	local edges = graph.edges or {}
	local nodeLookup = graph.nodeLookup or nodesById(nodes)
	local joinThreshold = 20

	for _, fill in ipairs(polygonFills) do
		if #(fill.points or {}) < 3 then
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

		local signedArea = 0
		for i = 1, #fillNodes do
			local p1 = fillNodes[i].point
			local p2 = fillNodes[(i % #fillNodes) + 1].point
			signedArea += p1.X * p2.Z - p2.X * p1.Z
		end
		local isClockwise = signedArea > 0

		local segments = {}
		for i = 1, #fill.points do
			local n1Id = fill.points[i]
			local n2Id = fill.points[(i % #fill.points) + 1]
			local n1 = nodeLookup[n1Id]
			local n2 = nodeLookup[n2Id]
			if not (n1 and n2) then
				continue
			end

			local edge = findEdgeBetween(edges, n1Id, n2Id)
			local roadPolygon = edge and findRoadPolygon(mesh.roadPolygons, edge.id) or nil
			local curve = {}
			if roadPolygon and not roadPolygon.ignoreMeshing then
				local isForward = edge.source == n1Id
				local useRightCurve = if isClockwise then isForward else not isForward
				local chosenCurve = if useRightCurve then roadPolygon.outerRightCurve else roadPolygon.outerLeftCurve
				appendPoints(curve, chosenCurve, not isForward)
			elseif roadPolygon then
				local isForward = edge.source == n1Id
				local pLeftStart = roadPolygon.outerLeftCurve[1]
				local pRightStart = roadPolygon.outerRightCurve[1]
				local pLeftEnd = roadPolygon.outerLeftCurve[#roadPolygon.outerLeftCurve]
				local pRightEnd = roadPolygon.outerRightCurve[#roadPolygon.outerRightCurve]

				if pLeftStart and pRightStart and pLeftEnd and pRightEnd then
					local midStartPoint = (pLeftStart + pRightStart) * 0.5
					local midEndPoint = (pLeftEnd + pRightEnd) * 0.5
					local midStart = if isForward then midStartPoint else midEndPoint
					local midEnd = if isForward then midEndPoint else midStartPoint

					table.insert(curve, midStart)

					local spline = edgeSplines and edgeSplines[edge.id] or nil
					if spline and #spline > 2 then
						if isForward then
							for splineIndex = 2, #spline - 1 do
								table.insert(curve, spline[splineIndex])
							end
						else
							for splineIndex = #spline - 1, 2, -1 do
								table.insert(curve, spline[splineIndex])
							end
						end
					end

					table.insert(curve, midEnd)
				end
			elseif edge and edgeSplines and edgeSplines[edge.id] and #edgeSplines[edge.id] > 0 then
				local isForward = edge.source == n1Id
				appendPoints(curve, edgeSplines[edge.id], not isForward)
			else
				table.insert(curve, n1.point)
				table.insert(curve, n2.point)
			end

			if not roadPolygon then
				local targetHub = findHub(mesh.hubs, n2Id)
				if targetHub and #(targetHub.outerPolygon or {}) > 0 and #curve > 1 then
					local endIndex = #curve
					while endIndex > 1 and pointInPolygonXZ(curve[endIndex], targetHub.outerPolygon) do
						endIndex -= 1
					end
					if endIndex < #curve then
						local exactIntersection =
							intersectSegmentPolygonXZ(curve[endIndex], curve[endIndex + 1], targetHub.outerPolygon)
						while #curve > endIndex do
							table.remove(curve)
						end
						if exactIntersection then
							table.insert(curve, exactIntersection)
						end
					end
				end

				local sourceHub = findHub(mesh.hubs, n1Id)
				if sourceHub and #(sourceHub.outerPolygon or {}) > 0 and #curve > 1 then
					local startIndex = 1
					while startIndex < #curve and pointInPolygonXZ(curve[startIndex], sourceHub.outerPolygon) do
						startIndex += 1
					end
					if startIndex > 1 then
						local exactIntersection =
							intersectSegmentPolygonXZ(curve[startIndex], curve[startIndex - 1], sourceHub.outerPolygon)
						local clippedCurve = {}
						if exactIntersection then
							table.insert(clippedCurve, exactIntersection)
						end
						for curveIndex = startIndex, #curve do
							table.insert(clippedCurve, curve[curveIndex])
						end
						curve = clippedCurve
					end
				end
			end
			table.insert(segments, curve)
		end

		local boundaryPoints = {}
		for i = 1, #segments do
			local curve = segments[i]
			local nextCurve = segments[(i % #segments) + 1]
			appendPoints(boundaryPoints, curve, false)

			local endPoint = curve[#curve]
			local startPoint = nextCurve and nextCurve[1]
			local nodeId = fill.points[(i % #fill.points) + 1]
			local hub = findHub(mesh.hubs, nodeId)
			if endPoint and startPoint and hub and #(hub.outerPolygon or {}) > 0 then
				local minEnd = math.huge
				local minStart = math.huge
				local endIndex = nil
				local startIndex = nil
				for hubIndex, hubPoint in ipairs(hub.outerPolygon) do
					local endDistance = horizontalDistance(hubPoint, endPoint)
					local startDistance = horizontalDistance(hubPoint, startPoint)
					if endDistance < minEnd then
						minEnd = endDistance
						endIndex = hubIndex
					end
					if startDistance < minStart then
						minStart = startDistance
						startIndex = hubIndex
					end
				end

				if endIndex and startIndex and minEnd < joinThreshold and minStart < joinThreshold then
					local path1 = { hub.outerPolygon[endIndex] }
					local k1 = endIndex
					while k1 ~= startIndex and #path1 < #hub.outerPolygon + 2 do
						k1 = (k1 % #hub.outerPolygon) + 1
						table.insert(path1, hub.outerPolygon[k1])
					end

					local path2 = { hub.outerPolygon[endIndex] }
					local k2 = endIndex
					while k2 ~= startIndex and #path2 < #hub.outerPolygon + 2 do
						k2 -= 1
						if k2 < 1 then
							k2 = #hub.outerPolygon
						end
						table.insert(path2, hub.outerPolygon[k2])
					end

					appendPoints(boundaryPoints, if isClockwise then path2 else path1, false)
				end
			end
		end

		if #boundaryPoints < 3 then
			continue
		end

		local uniqueBoundaryPoints = {}
		for i = 1, #boundaryPoints do
			local point = boundaryPoints[i]
			local nextPoint = boundaryPoints[(i % #boundaryPoints) + 1]
			if horizontalDistance(point, nextPoint) > 0.01 then
				table.insert(uniqueBoundaryPoints, point)
			end
		end

		local fillTriangles = buildGridMesh(uniqueBoundaryPoints)
		if #fillTriangles > 0 then
			local record = {
				id = fill.id,
				color = fill.color or "#10b981",
				boundary = uniqueBoundaryPoints,
				triangles = fillTriangles,
			}
			table.insert(mesh.polygonFills, record)
			table.insert(mesh.polygonTriangles, record)
		end
	end
end

local function buildBuildingMeshes(mesh, graph)
	for index, building in ipairs(graph.buildings or {}) do
		if type(building) ~= "table" or type(building.vertices) ~= "table" or #(building.vertices or {}) < 3 then
			continue
		end

		local height = tonumber(building.height) or 80
		if height <= EPSILON then
			continue
		end

		local baseVertices = {}
		for _, vertex in ipairs(building.vertices) do
			if typeof(vertex) == "Vector3" then
				table.insert(baseVertices, vertex)
			end
		end
		if #baseVertices < 3 then
			continue
		end

		if horizontalDistance(baseVertices[1], baseVertices[#baseVertices]) <= 0.01 then
			table.remove(baseVertices)
		end
		if #baseVertices < 3 then
			continue
		end

		local topVertices = {}
		for _, vertex in ipairs(baseVertices) do
			table.insert(topVertices, Vector3.new(vertex.X, vertex.Y + height, vertex.Z))
		end

		local topTriangles = buildGridMesh(topVertices)
		local bottomSourceTriangles = buildGridMesh(baseVertices)
		local bottomTriangles = {}
		for _, triangle in ipairs(bottomSourceTriangles) do
			addTriangle(bottomTriangles, triangle[1], triangle[3], triangle[2])
		end

		local wallTriangles = {}
		for vertexIndex = 1, #baseVertices do
			local nextIndex = (vertexIndex % #baseVertices) + 1
			local baseA = baseVertices[vertexIndex]
			local baseB = baseVertices[nextIndex]
			local topB = topVertices[nextIndex]
			local topA = topVertices[vertexIndex]
			addTriangle(wallTriangles, baseA, baseB, topB)
			addTriangle(wallTriangles, baseA, topB, topA)
		end

		local triangles = {}
		for _, triangle in ipairs(topTriangles) do
			table.insert(triangles, triangle)
			table.insert(mesh.buildingTriangles, triangle)
		end
		for _, triangle in ipairs(bottomTriangles) do
			table.insert(triangles, triangle)
			table.insert(mesh.buildingTriangles, triangle)
		end
		for _, triangle in ipairs(wallTriangles) do
			table.insert(triangles, triangle)
			table.insert(mesh.buildingTriangles, triangle)
		end

		if #triangles > 0 then
			table.insert(mesh.buildingMeshes, {
				id = building.id or ("b" .. tostring(index)),
				name = building.name,
				vertices = baseVertices,
				baseZ = building.baseZ,
				height = height,
				color = building.color or "#64748b",
				material = building.material or "Concrete",
				triangles = triangles,
				topTriangles = topTriangles,
				bottomTriangles = bottomTriangles,
				wallTriangles = wallTriangles,
			})
		end
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

function nodesById(nodes)
	local lookup = {}
	for _, node in ipairs(nodes or {}) do
		lookup[node.id] = node
	end
	return lookup
end

local function nodeIgnoresMeshing(node)
	return node and node.ignoreMeshing == true
end

local function edgeIgnoresMeshing(edge, nodeLookup)
	if not edge then
		return true
	end

	local sourceNode = nodeLookup[edge.source]
	local targetNode = edge.target and nodeLookup[edge.target] or nil
	return nodeIgnoresMeshing(sourceNode) or nodeIgnoresMeshing(targetNode)
end

local function filterRoadNodes(nodes)
	local roadNodes = {}
	for _, node in ipairs(nodes or {}) do
		if not nodeIgnoresMeshing(node) then
			table.insert(roadNodes, node)
		end
	end
	return roadNodes
end

local function filterRoadEdges(edges, nodeLookup)
	local roadEdges = {}
	for _, edge in ipairs(edges or {}) do
		if not edgeIgnoresMeshing(edge, nodeLookup) then
			table.insert(roadEdges, edge)
		end
	end
	return roadEdges
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

local function getConnectionTransitionSmoothness(outgoing, node)
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
		local finalT = t
		local finalU = u
		local finalOuterT = outerT
		local finalOuterU = outerU

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

			finalT = capT + smoothness1
			finalU = capU + smoothness2
			finalOuterT = capOuterT + smoothness1
			finalOuterU = capOuterU + smoothness2
		else
			finalT = t + smoothness1
			finalU = u + smoothness2
			finalOuterT = outerT + smoothness1
			finalOuterU = outerU + smoothness2
		end

		local innerA = pointAt(a, dir1, finalT)
		local innerB = pointAt(b, dir2, finalU)
		local outerAChamfer = pointAt(outerA, dir1, finalOuterT)
		local outerBChamfer = pointAt(outerB, dir2, finalOuterU)
		local chamferVector = innerB - innerA
		local chamferLength = horizontalDistance(innerB, innerA)

		if chamferLength > 1e-4 and (finalT ~= t or finalU ~= u) then
			local outward = Vector3.new(chamferVector.Z / chamferLength, 0, -chamferVector.X / chamferLength)
			local midpoint = (innerA + innerB) * 0.5
			if outward:Dot(midpoint - center) < 0 then
				outward = -outward
			end

			local outerLinePoint = midpoint + outward * math.max(sw1, sw2)
			local det1 = chamferVector.X * dir1.Z - chamferVector.Z * dir1.X
			if math.abs(det1) > 1e-5 then
				local outerNumerator = ((outerLinePoint.Z - outerA.Z) * chamferVector.X) - ((outerLinePoint.X - outerA.X) * chamferVector.Z)
				local outerTOnRay = outerNumerator / det1
				outerAChamfer = pointAt(outerA, dir1, outerTOnRay)
				finalOuterT = outerTOnRay
			end

			local det2 = chamferVector.X * dir2.Z - chamferVector.Z * dir2.X
			if math.abs(det2) > 1e-5 then
				local outerNumerator = ((outerLinePoint.Z - outerB.Z) * chamferVector.X) - ((outerLinePoint.X - outerB.X) * chamferVector.Z)
				local outerUOnRay = outerNumerator / det2
				outerBChamfer = pointAt(outerB, dir2, outerUOnRay)
				finalOuterU = outerUOnRay
			end
		end

		if finalT ~= t or finalU ~= u or finalOuterT ~= outerT or finalOuterU ~= outerU then
			return {
				innerA,
				innerB,
			}, {
				outerAChamfer,
				outerBChamfer,
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
				getConnectionTransitionSmoothness(r1, node),
				r2.dir,
				r2.edge.width,
				sidewalk2,
				getConnectionTransitionSmoothness(r2, node),
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
		polygonFills = {},
		polygonTriangles = {},
		buildingMeshes = {},
		buildingTriangles = {},
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
	local roadNodes = filterRoadNodes(nodes)
	local roadEdges = filterRoadEdges(edges, nodeLookup)

	local nodeClearances = {}
	local nodeCorners = {}
	local nodeOuterCorners = {}

	for _, node in ipairs(roadNodes) do
		local outgoing = getOutgoing(node, roadEdges, nodeLookup)
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
					getConnectionTransitionSmoothness(r1, node),
					r2.dir,
					r2.edge.width,
					sidewalk2,
					getConnectionTransitionSmoothness(r2, node),
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

		local orderedHubPolygon = orderedUniqueAroundCenter(node.point, hubPolygon)

		table.insert(mesh.hubs, {
			id = node.id,
			polygon = orderedHubPolygon,
			corners = corners,
			outerPolygon = hubOuterPolygon,
			outerCorners = outerCorners,
		})

		if #orderedHubPolygon >= 3 then
			for i = 1, #orderedHubPolygon do
				local nextPoint = orderedHubPolygon[(i % #orderedHubPolygon) + 1]
				addTriangle(mesh.roadTriangles, node.point, nextPoint, orderedHubPolygon[i])
				addTriangle(mesh.roadHubTriangles, node.point, nextPoint, orderedHubPolygon[i])
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

	for _, edge in ipairs(roadEdges) do
		local sourceNode = nodeLookup[edge.source]
		local targetNode = edge.target and nodeLookup[edge.target] or nil
		if not sourceNode then
			continue
		end
		local skipRoadMeshing = edgeIgnoresMeshing(edge, nodeLookup)

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
			local targetBaseA, targetBaseB = getEdgeBases(targetNode, edge, false, nodeCorners)
			local outerTargetBaseA, outerTargetBaseB = getEdgeBases(targetNode, edge, false, nodeOuterCorners)
			-- Target node bases are local to the target-facing connection. Road-Maker reverses
			-- them here so road polygons and polygon-fill boundaries stay edge-forward.
			targetBaseRight, targetBaseLeft = targetBaseA, targetBaseB
			outerTargetBaseRight, outerTargetBaseLeft = outerTargetBaseA, outerTargetBaseB
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

			if isTrueJunction(sourceNode.id, roadEdges, nodeLookup) then
				local startDir = getDir(spline[1], spline[math.min(2, #spline)])
				local newLeft = baseLeft + startDir * crosswalkWidth
				local newRight = baseRight + startDir * crosswalkWidth
				local newOuterLeft = outerBaseLeft + startDir * crosswalkWidth
				local newOuterRight = outerBaseRight + startDir * crosswalkWidth
				local polygon = { baseLeft, baseRight, newRight, newLeft }
				if hasCrosswalk(edge.id, true, roadEdges, nodeLookup) then
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
				if isTrueJunction(targetNode.id, roadEdges, nodeLookup) then
					local endDir = getDir(spline[#spline], spline[math.max(1, #spline - 1)])
					local newLeft = targetBaseLeft + endDir * crosswalkWidth
					local newRight = targetBaseRight + endDir * crosswalkWidth
					local newOuterLeft = outerTargetBaseLeft + endDir * crosswalkWidth
					local newOuterRight = outerTargetBaseRight + endDir * crosswalkWidth
					local crosswalkPolygon = { targetBaseLeft, targetBaseRight, newRight, newLeft }
					if hasCrosswalk(edge.id, false, roadEdges, nodeLookup) then
						table.insert(mesh.crosswalks, { edgeId = edge.id, nodeId = targetNode.id, polygon = crosswalkPolygon })
						addQuadTriangles(mesh.crosswalkTriangles, targetBaseRight, targetBaseLeft, newLeft, newRight)
					end
					table.insert(mesh.sidewalkPolygons, { outerTargetBaseLeft, targetBaseLeft, newLeft, newOuterLeft })
					table.insert(mesh.sidewalkPolygons, { targetBaseRight, outerTargetBaseRight, newOuterRight, newRight })
					addQuadTriangles(mesh.sidewalkTriangles, targetBaseLeft, outerTargetBaseLeft, newOuterLeft, newLeft)
					addQuadTriangles(mesh.sidewalkTriangles, outerTargetBaseRight, targetBaseRight, newRight, newOuterRight)
					targetBaseLeft, targetBaseRight = newLeft, newRight
					outerTargetBaseLeft, outerTargetBaseRight = newOuterLeft, newOuterRight
				end

				table.insert(fullCenterLine, (targetBaseLeft + targetBaseRight) * 0.5)
				table.insert(polygon, targetBaseRight)
				table.insert(polygon, targetBaseLeft)
				table.insert(outerPolygon, outerTargetBaseRight)
				table.insert(outerPolygon, outerTargetBaseLeft)
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
				leftCurve = { baseLeft, table.unpack(leftPoints) },
				rightCurve = { baseRight, table.unpack(rightPoints) },
				outerPolygon = outerPolygon,
				outerLeftCurve = { outerBaseLeft, table.unpack(outerLeftPoints) },
				outerRightCurve = { outerBaseRight, table.unpack(outerRightPoints) },
				sidewalkWidth = getEdgeSidewalk(edge, settings),
				ignoreMeshing = skipRoadMeshing,
			})

			if targetBaseLeft and targetBaseRight and outerTargetBaseLeft and outerTargetBaseRight then
				local roadPolygon = mesh.roadPolygons[#mesh.roadPolygons]
				table.insert(roadPolygon.leftCurve, targetBaseLeft)
				table.insert(roadPolygon.rightCurve, targetBaseRight)
				table.insert(roadPolygon.outerLeftCurve, outerTargetBaseLeft)
				table.insert(roadPolygon.outerRightCurve, outerTargetBaseRight)
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
				addTriangle(mesh.roadTriangles, currentLeft, currentRight, targetBaseRight)
				addTriangle(mesh.roadTriangles, currentLeft, targetBaseRight, targetBaseLeft)
				addTriangle(mesh.roadEdgeTriangles, currentLeft, currentRight, targetBaseRight)
				addTriangle(mesh.roadEdgeTriangles, currentLeft, targetBaseRight, targetBaseLeft)
				addTriangle(mesh.sidewalkTriangles, currentOuterLeft, currentLeft, targetBaseLeft)
				addTriangle(mesh.sidewalkTriangles, currentOuterLeft, targetBaseLeft, outerTargetBaseLeft)
				addTriangle(mesh.sidewalkTriangles, currentRight, currentOuterRight, outerTargetBaseRight)
				addTriangle(mesh.sidewalkTriangles, currentRight, outerTargetBaseRight, targetBaseRight)
			end
		end
	end

	buildPolygonFillTriangles(mesh, graph, edgeSplines)
	buildBuildingMeshes(mesh, graph)

	addTrianglesToBounds(mesh.bounds, mesh.roadTriangles)
	addTrianglesToBounds(mesh.bounds, mesh.sidewalkTriangles)
	addTrianglesToBounds(mesh.bounds, mesh.crosswalkTriangles)
	addTrianglesToBounds(mesh.bounds, mesh.buildingTriangles)
	for _, fill in ipairs(mesh.polygonFills) do
		addTrianglesToBounds(mesh.bounds, fill.triangles)
	end
	return mesh
end

function RoadGraphMesher.sampleEdgeCenterLines(graph, options)
	return RoadGraphMesher.buildNetworkMesh(graph, options).centerLines
end

return RoadGraphMesher
