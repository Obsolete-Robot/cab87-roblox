local RoadSampling = {}

RoadSampling.DEFAULT_ROAD_WIDTH = 28
RoadSampling.MIN_ROAD_WIDTH = 8
RoadSampling.MAX_ROAD_WIDTH = 200
RoadSampling.ROAD_WIDTH_ATTR = "RoadWidth"

function RoadSampling.sanitizeRoadWidth(value, defaultWidth)
	local fallback = tonumber(defaultWidth) or RoadSampling.DEFAULT_ROAD_WIDTH
	local width = tonumber(value) or fallback
	return math.clamp(width, RoadSampling.MIN_ROAD_WIDTH, RoadSampling.MAX_ROAD_WIDTH)
end

function RoadSampling.getConfiguredRoadWidth(config)
	local configuredDefault = config and tonumber(config.authoredRoadCollisionWidth)
	return RoadSampling.sanitizeRoadWidth(configuredDefault, RoadSampling.DEFAULT_ROAD_WIDTH)
end

function RoadSampling.getSplineRoadWidth(spline, defaultWidth)
	local configuredDefault = RoadSampling.sanitizeRoadWidth(defaultWidth, RoadSampling.DEFAULT_ROAD_WIDTH)
	local attrValue = spline and spline:GetAttribute(RoadSampling.ROAD_WIDTH_ATTR)
	return RoadSampling.sanitizeRoadWidth(attrValue, configuredDefault)
end

function RoadSampling.distanceXZ(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function RoadSampling.distanceXZSquared(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return dx * dx + dz * dz
end

function RoadSampling.horizontalUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-4 then
		return nil
	end
	return flat.Unit
end

function RoadSampling.catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

function RoadSampling.samplePositions(positions, closedCurve, sampleStep)
	if #positions < 2 then
		local copy = {}
		for _, position in ipairs(positions) do
			table.insert(copy, position)
		end
		return copy
	end

	if closedCurve and #positions < 3 then
		closedCurve = false
	end

	local samples = {}
	sampleStep = math.max(tonumber(sampleStep) or 8, 1)
	if closedCurve then
		local count = #positions
		for i = 1, count do
			local p0 = positions[((i - 2) % count) + 1]
			local p1 = positions[i]
			local p2 = positions[(i % count) + 1]
			local p3 = positions[((i + 1) % count) + 1]
			local segmentLen = (p2 - p1).Magnitude
			local subdivisions = math.max(2, math.floor(segmentLen / sampleStep))

			for s = 0, subdivisions - 1 do
				table.insert(samples, RoadSampling.catmullRom(p0, p1, p2, p3, s / subdivisions))
			end
		end

		if #samples > 1 then
			table.insert(samples, samples[1])
		end
	else
		for i = 1, #positions - 1 do
			local p0 = positions[math.max(1, i - 1)]
			local p1 = positions[i]
			local p2 = positions[i + 1]
			local p3 = positions[math.min(#positions, i + 2)]
			local segmentLen = (p2 - p1).Magnitude
			local subdivisions = math.max(2, math.floor(segmentLen / sampleStep))

			for s = 0, subdivisions - 1 do
				table.insert(samples, RoadSampling.catmullRom(p0, p1, p2, p3, s / subdivisions))
			end
		end

		table.insert(samples, positions[#positions])
	end

	return samples
end

function RoadSampling.sampleLoopIsClosed(samples)
	if #samples < 3 then
		return false
	end
	return RoadSampling.distanceXZ(samples[1], samples[#samples]) <= 0.05 and math.abs(samples[1].Y - samples[#samples].Y) <= 0.05
end

function RoadSampling.getRoadSampleTangent(samples, index, edgeCount, closedLoop, fallbackDir)
	if closedLoop then
		local prevIndex = index - 1
		if prevIndex < 1 then
			prevIndex = edgeCount
		end
		local nextIndex = index + 1
		if nextIndex > edgeCount then
			nextIndex = 1
		end
		local prevDir = RoadSampling.horizontalUnit(samples[index] - samples[prevIndex])
		local nextDir = RoadSampling.horizontalUnit(samples[nextIndex] - samples[index])
		if prevDir and nextDir then
			local combined = prevDir + nextDir
			if combined.Magnitude > 1e-4 then
				return combined.Unit
			end
		end
		return nextDir or prevDir or fallbackDir
	end

	if index == 1 then
		return RoadSampling.horizontalUnit(samples[2] - samples[1]) or fallbackDir
	elseif index == edgeCount then
		return RoadSampling.horizontalUnit(samples[edgeCount] - samples[edgeCount - 1]) or fallbackDir
	end

	local prevDir = RoadSampling.horizontalUnit(samples[index] - samples[index - 1])
	local nextDir = RoadSampling.horizontalUnit(samples[index + 1] - samples[index])
	if prevDir and nextDir then
		local combined = prevDir + nextDir
		if combined.Magnitude > 1e-4 then
			return combined.Unit
		end
	end
	return nextDir or prevDir or fallbackDir
end

function RoadSampling.polylineLength(points, closedLoop)
	local count = #points
	if count < 2 then
		return 0
	end

	local segmentCount = closedLoop and count or count - 1
	local total = 0
	for i = 1, segmentCount do
		local nextIndex = closedLoop and ((i % count) + 1) or (i + 1)
		total += (points[nextIndex] - points[i]).Magnitude
	end
	return total
end

function RoadSampling.samplePolylineAtFraction(points, closedLoop, fraction)
	local count = #points
	if count == 0 then
		return Vector3.zero
	elseif count == 1 then
		return points[1]
	end

	local totalLength = RoadSampling.polylineLength(points, closedLoop)
	if totalLength <= 1e-4 then
		return points[1]
	end

	local target = math.clamp(fraction, 0, 1) * totalLength
	if closedLoop then
		target = target % totalLength
	elseif target <= 0 then
		return points[1]
	elseif target >= totalLength then
		return points[count]
	end

	local traveled = 0
	local segmentCount = closedLoop and count or count - 1
	for i = 1, segmentCount do
		local nextIndex = closedLoop and ((i % count) + 1) or (i + 1)
		local a = points[i]
		local b = points[nextIndex]
		local segmentLength = (b - a).Magnitude
		if segmentLength > 1e-4 then
			if traveled + segmentLength >= target then
				return a:Lerp(b, (target - traveled) / segmentLength)
			end
			traveled += segmentLength
		end
	end

	return closedLoop and points[1] or points[count]
end

function RoadSampling.projectPointToSegmentXZ(position, a, b)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local lengthSquared = dx * dx + dz * dz
	if lengthSquared <= 0.001 then
		return a, 0, RoadSampling.distanceXZ(position, a)
	end

	local alpha = math.clamp(((position.X - a.X) * dx + (position.Z - a.Z) * dz) / lengthSquared, 0, 1)
	local projected = Vector3.new(
		a.X + dx * alpha,
		a.Y + (b.Y - a.Y) * alpha,
		a.Z + dz * alpha
	)
	return projected, alpha, RoadSampling.distanceXZ(position, projected)
end

return RoadSampling
