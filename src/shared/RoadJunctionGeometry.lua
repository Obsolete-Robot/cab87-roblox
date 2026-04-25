local RoadSampling = require(script.Parent:WaitForChild("RoadSampling"))

local RoadJunctionGeometry = {}

local CUT_PADDING_NEAR = 15
local CUT_PADDING_FAR = 15

local function horizontalDirection(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 1e-4 then
		return nil
	end
	return horizontal.Unit
end

local function directionForRoad(center, road)
	if typeof(road.direction) == "Vector3" then
		return horizontalDirection(road.direction)
	end
	if typeof(road.endPoint) == "Vector3" then
		return horizontalDirection(road.endPoint - center)
	end
	return nil
end

local function roadSideFromDirection(direction)
	local side = Vector3.yAxis:Cross(direction)
	if side.Magnitude <= 1e-4 then
		return Vector3.xAxis
	end
	return side.Unit
end

local function lineIntersectionWithParametersXZ(a, dirA, b, dirB)
	local cross = dirA.X * dirB.Z - dirA.Z * dirB.X
	if math.abs(cross) <= 1e-4 then
		return nil, nil, nil
	end

	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local t = (dx * dirB.Z - dz * dirB.X) / cross
	local u = (dx * dirA.Z - dz * dirA.X) / cross
	return Vector3.new(a.X + dirA.X * t, a.Y, a.Z + dirA.Z * t), t, u
end

local function copySortedRoads(center, roads)
	local sortedRoads = {}
	for index, road in ipairs(roads or {}) do
		local direction = directionForRoad(center, road)
		local width = RoadSampling.sanitizeRoadWidth(road.width)
		if direction then
			local copied = {}
			for key, value in pairs(road) do
				copied[key] = value
			end
			copied.id = copied.id or tostring(index)
			copied.width = width
			copied.halfWidth = width * 0.5
			copied.direction = direction
			copied.angle = math.atan2(direction.Z, direction.X)
			table.insert(sortedRoads, copied)
		end
	end

	table.sort(sortedRoads, function(a, b)
		return a.angle < b.angle
	end)

	return sortedRoads
end

function RoadJunctionGeometry.calculate(center, roads)
	local sortedRoads = copySortedRoads(center, roads)
	local roadCount = #sortedRoads
	local vertices = {}
	local corners = {}

	if roadCount < 2 then
		return {
			vertices = vertices,
			sortedRoads = sortedRoads,
			roadCutDistances = {},
			corners = corners,
		}
	end

	for index, road in ipairs(sortedRoads) do
		local nextRoad = sortedRoads[(index % roadCount) + 1]
		local direction = road.direction
		local side = roadSideFromDirection(direction)
		local nextDirection = nextRoad.direction
		local nextSide = roadSideFromDirection(nextDirection)
		local halfWidth = road.halfWidth
		local nextHalfWidth = nextRoad.halfWidth

		local endPoint = road.endPoint
		if typeof(endPoint) ~= "Vector3" then
			endPoint = center + direction * math.max(halfWidth + CUT_PADDING_NEAR + CUT_PADDING_FAR, road.width)
		end

		table.insert(vertices, Vector3.new(
			endPoint.X + side.X * halfWidth,
			center.Y,
			endPoint.Z + side.Z * halfWidth
		))
		table.insert(vertices, Vector3.new(
			endPoint.X - side.X * halfWidth,
			center.Y,
			endPoint.Z - side.Z * halfWidth
		))

		local fromSide = Vector3.new(
			center.X - side.X * halfWidth,
			center.Y,
			center.Z - side.Z * halfWidth
		)
		local toSide = Vector3.new(
			center.X + nextSide.X * nextHalfWidth,
			center.Y,
			center.Z + nextSide.Z * nextHalfWidth
		)
		local cornerPoints = {}
		local maxExtension = math.max(halfWidth, nextHalfWidth) * 1.5 + 50
		local intersection, fromT, toT = lineIntersectionWithParametersXZ(fromSide, direction, toSide, nextDirection)

		if intersection then
			if fromT > maxExtension or toT > maxExtension or fromT < 0 or toT < 0 then
				local safeFromT = math.clamp(fromT, 0, maxExtension)
				local safeToT = math.clamp(toT, 0, maxExtension)
				table.insert(cornerPoints, Vector3.new(
					fromSide.X + direction.X * safeFromT,
					center.Y,
					fromSide.Z + direction.Z * safeFromT
				))
				table.insert(cornerPoints, Vector3.new(
					toSide.X + nextDirection.X * safeToT,
					center.Y,
					toSide.Z + nextDirection.Z * safeToT
				))
			else
				table.insert(cornerPoints, Vector3.new(intersection.X, center.Y, intersection.Z))
			end
		else
			table.insert(cornerPoints, fromSide)
			table.insert(cornerPoints, toSide)
		end

		corners[index] = cornerPoints
		for _, point in ipairs(cornerPoints) do
			table.insert(vertices, point)
		end
	end

	local roadCutDistances = {}
	for index, road in ipairs(sortedRoads) do
		local maxProjection = 0
		local previousIndex = index - 1
		if previousIndex < 1 then
			previousIndex = roadCount
		end

		local cornerPoints = {}
		for _, point in ipairs(corners[previousIndex] or {}) do
			table.insert(cornerPoints, point)
		end
		for _, point in ipairs(corners[index] or {}) do
			table.insert(cornerPoints, point)
		end

		for _, point in ipairs(cornerPoints) do
			local projection = (point - center):Dot(road.direction)
			if projection > maxProjection then
				maxProjection = projection
			end
		end

		local cutDistance = math.max(maxProjection, road.halfWidth) + CUT_PADDING_NEAR
		roadCutDistances[road.id] = cutDistance + CUT_PADDING_FAR
	end

	return {
		vertices = vertices,
		sortedRoads = sortedRoads,
		roadCutDistances = roadCutDistances,
		corners = corners,
	}
end

function RoadJunctionGeometry.sideFromDirection(direction)
	return roadSideFromDirection(direction)
end

return RoadJunctionGeometry
