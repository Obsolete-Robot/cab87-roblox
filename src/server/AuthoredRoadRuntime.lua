local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadSampling = require(Shared:WaitForChild("RoadSampling"))
local RoadSplineData = require(Shared:WaitForChild("RoadSplineData"))
local CabCompanyWorldBuilder = require(script.Parent:WaitForChild("CabCompanyWorldBuilder"))

local AuthoredRoadRuntime = {}

local ROAD_EDITOR_ROOT_NAME = RoadSplineData.EDITOR_ROOT_NAME
local ROAD_EDITOR_SPLINES_NAME = RoadSplineData.SPLINES_NAME
local ROAD_EDITOR_POINTS_NAME = RoadSplineData.POINTS_NAME
local ROAD_EDITOR_NETWORK_NAME = RoadSplineData.NETWORK_NAME
local ROAD_EDITOR_WIREFRAME_NAME = RoadSplineData.WIREFRAME_NAME
local ROAD_WIDTH_ATTR = RoadSplineData.ROAD_WIDTH_ATTR
local RUNTIME_WORLD_NAME = "Cab87World"
local RUNTIME_SPLINE_DATA_NAME = RoadSplineData.RUNTIME_DATA_NAME
local DEFAULT_AUTHORED_ROAD_WIDTH = RoadSampling.DEFAULT_ROAD_WIDTH
local VISUAL_ROAD_THICKNESS = 0.35
local VISUAL_ROAD_SURFACE_OFFSET = 0.72
local ROAD_MESH_THICKNESS = 1.2
local ENDPOINT_WELD_DISTANCE = 22
local INTERSECTION_RADIUS_SCALE = 0.5
local INTERSECTION_BLEND_SCALE = 0.95
local INTERSECTION_MERGE_SCALE = 0.45
local INTERSECTION_RING_SEGMENTS = 28
local JUNCTION_VERTEX_EPSILON = 0.05
local JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE = 0.5
local ROAD_WIDTH_TRIANGULATION_STEP = 24
local ROAD_WIDTH_MAX_INTERNAL_LOOPS = 2
local ROAD_LOFT_LENGTH_STEP = Config.authoredRoadSampleStepStuds or 8
local ROAD_EDGE_CURVE_SMOOTH_STEP = math.max(1, ROAD_LOFT_LENGTH_STEP * 0.25)
local ROAD_EDGE_CURVE_FAIR_PASSES = 4
local ROAD_EDGE_CURVE_FAIR_ALPHA = 0.42
local INTERSECTION_HEIGHT_TOLERANCE_MIN = ROAD_MESH_THICKNESS * 2
local INTERSECTION_HEIGHT_TOLERANCE_MAX = ROAD_MESH_THICKNESS * 4
local INTERSECTION_HEIGHT_TOLERANCE_WIDTH_SCALE = 0.18
local ROAD_LOG_PREFIX = "[cab87 roads server]"

local function formatLogMessage(message, ...)
	local ok, formatted = pcall(string.format, tostring(message), ...)
	if ok then
		return formatted
	end
	return tostring(message)
end

local function roadDebugLog(message, ...)
	if Config.authoredRoadDebugLogging == true then
		print(ROAD_LOG_PREFIX .. " " .. formatLogMessage(message, ...))
	end
end

local function roadDebugWarn(message, ...)
	warn(ROAD_LOG_PREFIX .. " " .. formatLogMessage(message, ...))
end

local dataModelContentWarningShown = false

local function vectorToYaw(vector)
	return math.atan2(vector.X, vector.Z)
end

local function makePart(parent, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local sortedChildren = RoadSplineData.sortedChildren
local getAuthoredSplines = RoadSplineData.getSplines
local getAuthoredSplinePoints = RoadSplineData.getSplinePoints
local distanceXZ = RoadSampling.distanceXZ
local horizontalUnit = RoadSampling.horizontalUnit
local catmullRom = RoadSampling.catmullRom
local sampleLoopIsClosed = RoadSampling.sampleLoopIsClosed
local getRoadSampleTangent = RoadSampling.getRoadSampleTangent
local polylineLength = RoadSampling.polylineLength
local samplePolylineAtFraction = RoadSampling.samplePolylineAtFraction

local function getSplineRoadWidth(spline)
	return RoadSampling.getSplineRoadWidth(spline, RoadSampling.getConfiguredRoadWidth(Config))
end

local function sampleAuthoredSpline(points, closedCurve)
	return RoadSampling.samplePositions(
		RoadSplineData.getPointPositions(points),
		closedCurve,
		Config.authoredRoadSampleStepStuds
	)
end

local function createReplicatedSplineData(root, world)
	local oldData = world:FindFirstChild(RUNTIME_SPLINE_DATA_NAME)
	if oldData then
		oldData:Destroy()
	end

	local dataRoot = Instance.new("Folder")
	dataRoot.Name = RUNTIME_SPLINE_DATA_NAME
	dataRoot.Parent = world

	local splinesFolder = Instance.new("Folder")
	splinesFolder.Name = ROAD_EDITOR_SPLINES_NAME
	splinesFolder.Parent = dataRoot

	local splineCount = 0
	local pointCount = 0
	for _, spline in ipairs(getAuthoredSplines(root)) do
		local points = getAuthoredSplinePoints(spline)
		if #points >= 2 then
			splineCount += 1
			local splineData = Instance.new("Model")
			splineData.Name = spline.Name
			splineData:SetAttribute("ClosedCurve", spline:GetAttribute("ClosedCurve") == true)
			splineData:SetAttribute(ROAD_WIDTH_ATTR, getSplineRoadWidth(spline))
			splineData.Parent = splinesFolder

			local pointsData = Instance.new("Folder")
			pointsData.Name = ROAD_EDITOR_POINTS_NAME
			pointsData.Parent = splineData

			for _, point in ipairs(points) do
				pointCount += 1
				local pointData = Instance.new("Vector3Value")
				pointData.Name = point.Name
				pointData.Value = RoadSplineData.getPointPosition(point)
				pointData.Parent = pointsData
			end
		end
	end

	dataRoot:SetAttribute("SplineCount", splineCount)
	dataRoot:SetAttribute("PointCount", pointCount)
	roadDebugLog("replicated raw spline data: splines=%d points=%d", splineCount, pointCount)
	return dataRoot
end

local function hasAncestorNamed(instance, ancestorName)
	local current = instance.Parent
	while current do
		if current.Name == ancestorName then
			return true
		end
		current = current.Parent
	end

	return false
end

local function countRoadSurfaceParts(root)
	local count = 0
	if not root then
		return count
	end

	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") and not hasAncestorNamed(item, ROAD_EDITOR_WIREFRAME_NAME) then
			count += 1
		end
	end

	return count
end

local sanitizeRoadWidth = RoadSampling.sanitizeRoadWidth

local function hasAssetBackedMesh(part)
	if not part:IsA("MeshPart") then
		return true
	end

	local ok, meshId = pcall(function()
		return part.MeshId
	end)
	return ok and type(meshId) == "string" and meshId ~= ""
end

local function isTemporaryEditorMesh(part)
	return part:IsA("MeshPart")
		and part:GetAttribute("GeneratedBy") == "Cab87RoadEditor"
		and not hasAssetBackedMesh(part)
end

local function removeEditorDebugVisuals(root)
	if not root then
		return
	end

	for _, item in ipairs(root:GetDescendants()) do
		if item.Name == ROAD_EDITOR_WIREFRAME_NAME or (item:IsA("BasePart") and isTemporaryEditorMesh(item)) then
			item:Destroy()
		end
	end
end

local function configureRuntimePart(part, canQuery)
	part.Anchored = true
	part.CanCollide = canQuery
	part.CanQuery = canQuery
	part.CanTouch = false
end

local function trackPart(list, part)
	table.insert(list, part)
	return part
end

local function heightConnectTolerance(widthA, widthB)
	local width = math.min(sanitizeRoadWidth(widthA), sanitizeRoadWidth(widthB))
	return math.clamp(
		width * INTERSECTION_HEIGHT_TOLERANCE_WIDTH_SCALE,
		INTERSECTION_HEIGHT_TOLERANCE_MIN,
		INTERSECTION_HEIGHT_TOLERANCE_MAX
	)
end

local function positionsConnectIn3D(a, b, widthA, widthB)
	return math.abs(a.Y - b.Y) <= heightConnectTolerance(widthA, widthB)
end

local function collectSplineBuildData(root)
	return RoadSplineData.collectSampledChains(root, {
		defaultRoadWidth = RoadSampling.getConfiguredRoadWidth(Config),
		preserveSampledChains = false,
		sampleStep = Config.authoredRoadSampleStepStuds,
	})
end

local function getChainName(chain, fallback)
	if chain and chain.spline and chain.spline.Name then
		return chain.spline.Name
	end
	return fallback or "unknown"
end

local function maxRoadWidthForMembers(members)
	local width = nil
	for _, member in ipairs(members) do
		if member.chain then
			width = math.max(width or 0, member.chain.width)
		end
	end
	return width or DEFAULT_AUTHORED_ROAD_WIDTH
end

local function collectEndpointJunctions(chains)
	local endpoints = {}
	for _, chain in ipairs(chains) do
		if not chain.closed and #chain.samples >= 2 then
			table.insert(endpoints, { chain = chain, index = 1, pos = chain.samples[1] })
			table.insert(endpoints, { chain = chain, index = #chain.samples, pos = chain.samples[#chain.samples] })
		end
	end

	local clusters = {}
	for _, endpoint in ipairs(endpoints) do
		local placed = false
		local endpointWidth = endpoint.chain.width
		for _, cluster in ipairs(clusters) do
			local weldDistance = math.max(ENDPOINT_WELD_DISTANCE, math.max(cluster.width, endpointWidth) * 0.8)
			if distanceXZ(cluster.center, endpoint.pos) <= weldDistance and positionsConnectIn3D(cluster.center, endpoint.pos, cluster.width, endpointWidth) then
				table.insert(cluster.members, endpoint)
				cluster.width = math.max(cluster.width, endpointWidth)
				local sum = Vector3.zero
				for _, member in ipairs(cluster.members) do
					sum += member.pos
				end
				cluster.center = sum / #cluster.members
				placed = true
				break
			end
		end
		if not placed then
			table.insert(clusters, { center = endpoint.pos, members = { endpoint }, width = endpointWidth })
		end
	end

	local junctions = {}
	for _, cluster in ipairs(clusters) do
		if #cluster.members >= 2 then
			table.insert(junctions, {
				center = cluster.center,
				members = cluster.members,
			})
		end
	end

	return junctions
end

local function segmentIntersection2D(a, b, c, d)
	local function cross2(u, v)
		return u.X * v.Y - u.Y * v.X
	end

	local p = Vector2.new(a.X, a.Z)
	local r = Vector2.new(b.X - a.X, b.Z - a.Z)
	local q = Vector2.new(c.X, c.Z)
	local s = Vector2.new(d.X - c.X, d.Z - c.Z)

	local denom = cross2(r, s)
	if math.abs(denom) < 1e-6 then
		return nil
	end

	local qp = q - p
	local t = cross2(qp, s) / denom
	local u = cross2(qp, r) / denom
	local endpointEpsilon = 1e-4
	if t < -endpointEpsilon or t > 1 + endpointEpsilon or u < -endpointEpsilon or u > 1 + endpointEpsilon then
		return nil
	end

	t = math.clamp(t, 0, 1)
	u = math.clamp(u, 0, 1)
	return Vector2.new(p.X + r.X * t, p.Y + r.Y * t), t, u
end

local function collectCrossIntersections(chains)
	local junctions = {}
	for i = 1, #chains do
		local aChain = chains[i]
		for j = i + 1, #chains do
			local bChain = chains[j]
			for ai = 1, #aChain.samples - 1 do
				local a1 = aChain.samples[ai]
				local a2 = aChain.samples[ai + 1]
				for bi = 1, #bChain.samples - 1 do
					local b1 = bChain.samples[bi]
					local b2 = bChain.samples[bi + 1]
					local _, aT, bT = segmentIntersection2D(a1, a2, b1, b2)
					if aT and bT then
						local aPos = a1 + (a2 - a1) * aT
						local bPos = b1 + (b2 - b1) * bT
						if positionsConnectIn3D(aPos, bPos, aChain.width, bChain.width) then
							local pos = (aPos + bPos) * 0.5
							table.insert(junctions, {
								center = pos,
								members = {
									{ chain = aChain, segment = ai, t = aT, pos = pos },
									{ chain = bChain, segment = bi, t = bT, pos = pos },
								},
							})
						end
					end
				end
			end
		end
	end
	return junctions
end

local function mergeJunctions(rawJunctions)
	local clusters = {}
	for _, junction in ipairs(rawJunctions) do
		local placed = false
		local junctionWidth = maxRoadWidthForMembers(junction.members)
		for _, cluster in ipairs(clusters) do
			local mergeDistance = math.max(cluster.width, junctionWidth) * INTERSECTION_MERGE_SCALE
			if distanceXZ(cluster.center, junction.center) <= mergeDistance and positionsConnectIn3D(cluster.center, junction.center, cluster.width, junctionWidth) then
				for _, member in ipairs(junction.members) do
					table.insert(cluster.members, member)
				end
				cluster.width = math.max(cluster.width, junctionWidth)
				local sum = Vector3.zero
				for _, member in ipairs(cluster.members) do
					sum += member.pos or junction.center
				end
				cluster.center = sum / #cluster.members
				placed = true
				break
			end
		end
		if not placed then
			local members = {}
			for _, member in ipairs(junction.members) do
				table.insert(members, member)
			end
			table.insert(clusters, {
				center = junction.center,
				members = members,
				width = junctionWidth,
			})
		end
	end

	local junctions = {}
	for _, cluster in ipairs(clusters) do
		local radius = cluster.width * INTERSECTION_RADIUS_SCALE
		local blendRadius = math.max(cluster.width * INTERSECTION_BLEND_SCALE, radius + 0.05)
		local chainLookup = {}
		for _, member in ipairs(cluster.members) do
			if member.chain then
				chainLookup[member.chain] = true
			end
		end
		table.insert(junctions, {
			center = cluster.center,
			members = cluster.members,
			chains = chainLookup,
			width = cluster.width,
			radius = radius,
			blendRadius = blendRadius,
		})
	end
	return junctions
end

local function addInsertForChain(insertsByChain, chain, segment, t, pos)
	local inserts = insertsByChain[chain]
	if not inserts then
		inserts = {}
		insertsByChain[chain] = inserts
	end
	table.insert(inserts, {
		segment = segment,
		t = t,
		pos = pos,
	})
end

local function applyJunctionsToChains(chains, junctions)
	local insertsByChain = {}

	for _, junction in ipairs(junctions) do
		for _, member in ipairs(junction.members) do
			if member.index then
				member.chain.samples[member.index] = junction.center
			elseif member.segment and member.t then
				addInsertForChain(insertsByChain, member.chain, member.segment, member.t, junction.center)
			end
		end
	end

	for chain, inserts in pairs(insertsByChain) do
		table.sort(inserts, function(a, b)
			if a.segment == b.segment then
				return a.t > b.t
			end
			return a.segment > b.segment
		end)

		for _, insert in ipairs(inserts) do
			local before = chain.samples[insert.segment]
			local after = chain.samples[insert.segment + 1]
			if before and after and distanceXZ(before, insert.pos) > 0.05 and distanceXZ(after, insert.pos) > 0.05 then
				table.insert(chain.samples, insert.segment + 1, insert.pos)
			end
		end
	end

	for _, chain in ipairs(chains) do
		for i, sample in ipairs(chain.samples) do
			local bestJunction = nil
			local bestDistance = math.huge
			for _, junction in ipairs(junctions) do
				if junction.chains and junction.chains[chain] then
					local d = distanceXZ(sample, junction.center)
					local blendRadius = junction.blendRadius or (junction.radius + 0.05)
					if d <= blendRadius and d < bestDistance then
						bestDistance = d
						bestJunction = junction
					end
				end
			end

			if bestJunction then
				local alpha
				if bestDistance <= bestJunction.radius then
					alpha = 1
				else
					local blendRadius = bestJunction.blendRadius or (bestJunction.radius + 0.05)
					alpha = 1 - ((bestDistance - bestJunction.radius) / math.max(blendRadius - bestJunction.radius, 0.001))
					alpha = math.clamp(alpha, 0, 1)
				end

				chain.samples[i] = Vector3.new(
					sample.X,
					sample.Y + (bestJunction.center.Y - sample.Y) * alpha,
					sample.Z
				)
			end
		end

		if chain.closed and #chain.samples > 2 then
			chain.samples[#chain.samples] = chain.samples[1]
		end
	end
end

local function newMeshState()
	local editableMesh = AssetService:CreateEditableMesh()
	if not editableMesh then
		return nil, "EditableMesh creation failed"
	end

	return {
		mesh = editableMesh,
		vertexPositions = {},
		faces = 0,
	}
end

local function addMeshVertex(state, pos)
	local vertex = state.mesh:AddVertex(pos)
	state.vertexPositions[vertex] = pos
	return vertex
end

local function addMeshTriangle(state, a, b, c)
	state.mesh:AddTriangle(a, b, c)
	state.faces += 1
end

local function roadRightFromTangent(tangent)
	local right = Vector3.yAxis:Cross(tangent)
	if right.Magnitude < 1e-4 then
		return Vector3.xAxis
	end
	return right.Unit
end

local function crossXZ(a, b)
	return a.X * b.Z - a.Z * b.X
end

local function lineIntersectionXZ(a, dirA, b, dirB)
	local denom = crossXZ(dirA, dirB)
	if math.abs(denom) < 1e-5 then
		return nil
	end

	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local t = (dx * dirB.Z - dz * dirB.X) / denom
	return Vector3.new(a.X + dirA.X * t, a.Y, a.Z + dirA.Z * t)
end

local function addRoadLoftRowVertices(state, left, right, widthSegments)
	local row = {}
	for j = 0, widthSegments do
		row[j + 1] = addMeshVertex(state, left:Lerp(right, j / widthSegments))
	end
	return row
end

local function sampleSmoothedCurveControls(points, closedLoop, sampleStep)
	local count = #points
	if count < 3 then
		return points
	end

	local smoothed = {}
	local function appendPoint(point)
		local last = smoothed[#smoothed]
		if not last or (point - last).Magnitude > 1e-4 then
			table.insert(smoothed, point)
		end
	end

	local segmentCount = closedLoop and count or count - 1
	for i = 1, segmentCount do
		local p0
		local p1
		local p2
		local p3
		if closedLoop then
			p0 = points[((i - 2) % count) + 1]
			p1 = points[i]
			p2 = points[(i % count) + 1]
			p3 = points[((i + 1) % count) + 1]
		else
			p0 = points[math.max(1, i - 1)]
			p1 = points[i]
			p2 = points[i + 1]
			p3 = points[math.min(count, i + 2)]
		end

		local segmentLength = (p2 - p1).Magnitude
		local subdivisions = math.max(2, math.ceil(segmentLength / sampleStep))
		for s = 0, subdivisions - 1 do
			appendPoint(catmullRom(p0, p1, p2, p3, s / subdivisions))
		end
	end

	if not closedLoop then
		appendPoint(points[count])
	end

	return #smoothed >= count and smoothed or points
end

local function resamplePolylineControls(points, closedLoop, targetCount)
	targetCount = math.floor(targetCount)
	if targetCount <= 0 or #points == 0 then
		return {}
	elseif #points == 1 then
		return { points[1] }
	end

	targetCount = math.max(closedLoop and 3 or 2, targetCount)
	local resampled = {}
	for i = 1, targetCount do
		local fraction
		if closedLoop then
			fraction = (i - 1) / targetCount
		else
			fraction = targetCount > 1 and ((i - 1) / (targetCount - 1)) or 0
		end
		resampled[i] = samplePolylineAtFraction(points, closedLoop, fraction)
	end
	return resampled
end

local function fairEdgeCurveControls(points, closedLoop, sampleStep)
	local length = polylineLength(points, closedLoop)
	local targetCount
	if length > 1e-4 then
		targetCount = closedLoop and math.ceil(length / sampleStep) or (math.ceil(length / sampleStep) + 1)
		targetCount = math.max(#points, targetCount)
	else
		targetCount = #points
	end

	local relaxed = resamplePolylineControls(points, closedLoop, targetCount)
	for _ = 1, ROAD_EDGE_CURVE_FAIR_PASSES do
		local count = #relaxed
		if count < 3 then
			return relaxed
		end

		local nextPoints = {}
		for i = 1, count do
			if closedLoop or (i > 1 and i < count) then
				local prevIndex = i - 1
				if prevIndex < 1 then
					prevIndex = count
				end
				local nextIndex = i + 1
				if nextIndex > count then
					nextIndex = 1
				end

				local average = (relaxed[prevIndex] + relaxed[nextIndex]) * 0.5
				nextPoints[i] = relaxed[i]:Lerp(average, ROAD_EDGE_CURVE_FAIR_ALPHA)
			else
				nextPoints[i] = relaxed[i]
			end
		end
		relaxed = resamplePolylineControls(nextPoints, closedLoop, targetCount)
	end

	return sampleSmoothedCurveControls(relaxed, closedLoop, sampleStep)
end

local function getUniqueRoadSamples(samples, closedLoop)
	local unique = {}
	for _, sample in ipairs(samples) do
		table.insert(unique, sample)
	end
	if closedLoop and #unique > 1 and distanceXZ(unique[1], unique[#unique]) <= 0.05 then
		table.remove(unique, #unique)
	end
	return unique
end

local function buildRoadCrossSections(samples, roadWidth, surfaceYOffset, debugLabel)
	if #samples < 2 then
		return nil
	end

	roadWidth = sanitizeRoadWidth(roadWidth)
	local closedLoop = sampleLoopIsClosed(samples)
	local centerControls = getUniqueRoadSamples(samples, closedLoop)
	if #centerControls < (closedLoop and 3 or 2) then
		return nil
	end

	local centerLength = polylineLength(centerControls, closedLoop)
	if centerLength <= 1e-4 then
		return nil
	end

	local halfWidth = roadWidth * 0.5
	local widthSegments = math.min(ROAD_WIDTH_MAX_INTERNAL_LOOPS + 1, math.max(1, math.ceil(roadWidth / ROAD_WIDTH_TRIANGULATION_STEP)))
	local rowCount
	if closedLoop then
		rowCount = math.max(3, #centerControls, math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP))
	else
		rowCount = math.max(2, #centerControls, math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP) + 1)
	end
	local spanCount = closedLoop and rowCount or rowCount - 1
	local centers = {}
	local leftPositions = {}
	local rightPositions = {}
	local rights = {}
	local fallbackDir = Vector3.new(0, 0, 1)

	for i = 1, rowCount do
		local fraction = closedLoop and ((i - 1) / rowCount) or (rowCount > 1 and ((i - 1) / (rowCount - 1)) or 0)
		centers[i] = samplePolylineAtFraction(centerControls, closedLoop, fraction) + Vector3.new(0, surfaceYOffset, 0)
	end

	for i = 1, rowCount do
		local tangent
		if closedLoop then
			local prevIndex = i - 1
			if prevIndex < 1 then
				prevIndex = rowCount
			end
			local nextIndex = i + 1
			if nextIndex > rowCount then
				nextIndex = 1
			end
			tangent = horizontalUnit(centers[nextIndex] - centers[prevIndex])
		elseif i == 1 then
			tangent = horizontalUnit(centers[2] - centers[1])
		elseif i == rowCount then
			tangent = horizontalUnit(centers[rowCount] - centers[rowCount - 1])
		else
			tangent = horizontalUnit(centers[i + 1] - centers[i - 1])
		end

		fallbackDir = tangent or fallbackDir
		local right = roadRightFromTangent(fallbackDir)
		if i > 1 and rights[i - 1] and right:Dot(rights[i - 1]) < 0 then
			right = -right
		end
		rights[i] = right
		leftPositions[i] = centers[i] - right * halfWidth
		rightPositions[i] = centers[i] + right * halfWidth
	end

	if Config.authoredRoadDebugLogging == true and roadWidth >= 96 then
		roadDebugLog(
			"road loft %s: width=%.1f samples=%d rows=%d closed=%s spans=%d centerLen=%.1f widthSegments=%d",
			tostring(debugLabel or "road"),
			roadWidth,
			#samples,
			rowCount,
			tostring(closedLoop),
			spanCount,
			centerLength,
			widthSegments
		)
	end

	return {
		roadWidth = roadWidth,
		closed = closedLoop,
		rowCount = rowCount,
		spanCount = spanCount,
		widthSegments = widthSegments,
		centers = centers,
		left = leftPositions,
		right = rightPositions,
	}
end

local function collectAuthoredJunctions(root)
	local junctions = RoadSplineData.collectJunctions(root, {
		defaultRadius = DEFAULT_AUTHORED_ROAD_WIDTH * INTERSECTION_RADIUS_SCALE,
		minRadius = 1,
	})
	for _, junction in ipairs(junctions) do
		junction.blendRadius = junction.radius
		junction.portals = {}
		junction.chains = {}
	end
	return junctions
end

local function segmentCircleIntersections(a, b, center, radius)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local fx = a.X - center.X
	local fz = a.Z - center.Z
	local aa = dx * dx + dz * dz
	if aa <= 1e-6 then
		return {}
	end

	local bb = 2 * (fx * dx + fz * dz)
	local cc = fx * fx + fz * fz - radius * radius
	local discriminant = bb * bb - 4 * aa * cc
	if discriminant < -1e-6 then
		return {}
	end

	local root = math.sqrt(math.max(0, discriminant))
	local result = {}
	for _, t in ipairs({ (-bb - root) / (2 * aa), (-bb + root) / (2 * aa) }) do
		if t > 1e-4 and t < 1 - 1e-4 then
			table.insert(result, t)
		end
	end
	return result
end

local function junctionContainingPoint(point, junctions)
	local best = nil
	local bestDistance = math.huge
	for _, junction in ipairs(junctions) do
		local d = distanceXZ(point, junction.center)
		if d <= junction.radius - 1e-3 and d < bestDistance then
			best = junction
			bestDistance = d
		end
	end
	return best
end

local function junctionTouchingPoint(point, junctions)
	local best = nil
	local bestDistance = math.huge
	for _, junction in ipairs(junctions) do
		local d = distanceXZ(point, junction.center)
		if d <= junction.radius + JUNCTION_VERTEX_EPSILON and d < bestDistance then
			best = junction
			bestDistance = d
		end
	end
	return best
end

local function intervalOutsideJunctions(a, b, junctions)
	return junctionContainingPoint(a:Lerp(b, 0.5), junctions) == nil
end

local function copyChainWithSamples(sourceChain, samples, closed)
	local chain = {}
	for key, value in pairs(sourceChain) do
		chain[key] = value
	end
	local copiedSamples = {}
	for _, sample in ipairs(samples) do
		table.insert(copiedSamples, sample)
	end
	if closed and #copiedSamples > 1 and distanceXZ(copiedSamples[1], copiedSamples[#copiedSamples]) > 0.05 then
		table.insert(copiedSamples, copiedSamples[1])
	end
	chain.samples = copiedSamples
	chain.closed = closed
	return chain
end

local function closestPointOnSegmentXZ(a, b, point)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local lengthSq = dx * dx + dz * dz
	if lengthSq <= 1e-6 then
		return 0, a, distanceXZ(a, point)
	end

	local t = ((point.X - a.X) * dx + (point.Z - a.Z) * dz) / lengthSq
	t = math.clamp(t, 0, 1)
	local projected = a:Lerp(b, t)
	return t, projected, distanceXZ(projected, point)
end

local function buildChainPath(chain)
	local closedLoop = chain.closed or sampleLoopIsClosed(chain.samples)
	local samples = getUniqueRoadSamples(chain.samples, closedLoop)
	if #samples < (closedLoop and 3 or 2) then
		return nil
	end

	local distances = { 0 }
	local totalLength = 0
	for i = 1, #samples - 1 do
		totalLength += (samples[i + 1] - samples[i]).Magnitude
		distances[i + 1] = totalLength
	end
	if closedLoop then
		totalLength += (samples[1] - samples[#samples]).Magnitude
	end
	if totalLength <= 1e-4 then
		return nil
	end

	return {
		chain = chain,
		samples = samples,
		closed = closedLoop,
		distances = distances,
		totalLength = totalLength,
	}
end

local function pathSegmentInfo(path, segmentIndex)
	local samples = path.samples
	local nextIndex = segmentIndex + 1
	if nextIndex > #samples then
		nextIndex = 1
	end
	local startDistance = path.distances[segmentIndex]
	local endDistance = if path.closed and segmentIndex == #samples then path.totalLength else path.distances[nextIndex]
	return samples[segmentIndex], samples[nextIndex], startDistance, endDistance
end

local function pathPointAtDistance(path, distance)
	if path.closed then
		distance = distance % path.totalLength
	else
		distance = math.clamp(distance, 0, path.totalLength)
	end

	local segmentCount = path.closed and #path.samples or (#path.samples - 1)
	for i = 1, segmentCount do
		local a, b, startDistance, endDistance = pathSegmentInfo(path, i)
		if distance <= endDistance or i == segmentCount then
			local segmentLength = math.max(endDistance - startDistance, 1e-6)
			return a:Lerp(b, math.clamp((distance - startDistance) / segmentLength, 0, 1)), i
		end
	end

	return path.samples[#path.samples], segmentCount
end

local function collectPathSamples(path, startDistance, endDistance)
	local samples = {}
	local totalLength = path.totalLength
	local effectiveEnd = endDistance
	if path.closed and effectiveEnd <= startDistance then
		effectiveEnd += totalLength
	end

	local function appendPoint(point)
		if #samples == 0 or distanceXZ(samples[#samples], point) > 0.05 then
			table.insert(samples, point)
		end
	end

	appendPoint(pathPointAtDistance(path, startDistance))

	local passes = path.closed and 1 or 0
	for pass = 0, passes do
		local offset = pass * totalLength
		for i, sample in ipairs(path.samples) do
			local d = path.distances[i] + offset
			if d > startDistance + 0.05 and d < effectiveEnd - 0.05 then
				appendPoint(sample)
			end
		end
	end

	appendPoint(pathPointAtDistance(path, effectiveEnd))
	return samples
end

local function pathDistanceForSegment(path, segmentIndex, t)
	local _, _, startDistance, endDistance = pathSegmentInfo(path, segmentIndex)
	return startDistance + (endDistance - startDistance) * t
end

local function closestPathHit(path, point)
	local best = nil
	local segmentCount = path.closed and #path.samples or (#path.samples - 1)
	for i = 1, segmentCount do
		local a, b = pathSegmentInfo(path, i)
		local t, projected, d = closestPointOnSegmentXZ(a, b, point)
		if not best or d < best.distance then
			best = {
				path = path,
				chain = path.chain,
				segment = i,
				t = t,
				point = projected,
				distance = d,
				pathDistance = pathDistanceForSegment(path, i, t),
				lineDir = horizontalUnit(b - a) or Vector3.zAxis,
			}
		end
	end
	return best
end

local function collectExplicitJunctionHits(paths, junctions)
	local hitsByPath = {}
	for _, path in ipairs(paths) do
		hitsByPath[path] = {}
	end

	for _, junction in ipairs(junctions) do
		junction.hits = {}
		junction.portals = {}
		junction.chains = {}
		for _, path in ipairs(paths) do
			local hit = closestPathHit(path, junction.center)
			if hit and hit.distance <= junction.radius + JUNCTION_VERTEX_EPSILON then
				hit.junction = junction
				table.insert(junction.hits, hit)
				table.insert(hitsByPath[path], hit)
				junction.chains[path.chain] = true
			end
		end
	end

	return hitsByPath
end

local function computeExplicitJunctionCenter(junction)
	local hits = junction.hits or {}
	if #hits == 0 then
		return junction.center
	end

	local candidates = {}
	for i = 1, #hits do
		for j = i + 1, #hits do
			local a = hits[i]
			local b = hits[j]
			local intersection = lineIntersectionXZ(a.point, a.lineDir, b.point, b.lineDir)
			if intersection then
				table.insert(candidates, intersection)
			end
		end
	end

	local sum = Vector3.zero
	local count = 0
	if #candidates > 0 then
		for _, point in ipairs(candidates) do
			sum += point
			count += 1
		end
	else
		for _, hit in ipairs(hits) do
			sum += hit.point
			count += 1
		end
	end
	return count > 0 and (sum / count) or junction.center
end

local function finalizeExplicitJunctionCenters(junctions)
	for _, junction in ipairs(junctions) do
		junction.intersectionCenter = computeExplicitJunctionCenter(junction)
		for _, hit in ipairs(junction.hits or {}) do
			local refined = closestPathHit(hit.path, junction.intersectionCenter)
			if refined then
				hit.segment = refined.segment
				hit.t = refined.t
				hit.point = refined.point
				hit.distance = refined.distance
				hit.pathDistance = refined.pathDistance
				hit.lineDir = refined.lineDir
			end
		end
	end
end

local function addPortalForChain(junction, chain, boundaryPoint, outsidePoint)
	if not junction or not chain or not outsidePoint then
		return
	end

	local tangent = horizontalUnit(outsidePoint - boundaryPoint)
		or horizontalUnit(boundaryPoint - junction.center)
		or Vector3.zAxis
	local right = roadRightFromTangent(tangent)
	local halfWidth = sanitizeRoadWidth(chain.width) * 0.5
	table.insert(junction.portals, {
		junction = junction,
		chain = chain,
		boundaryPoint = boundaryPoint,
		outsidePoint = outsidePoint,
		point = boundaryPoint,
		tangent = tangent,
		halfWidth = halfWidth,
		left = boundaryPoint - right * halfWidth,
		right = boundaryPoint + right * halfWidth,
	})
	junction.chains[chain] = true
end

local function portalLineT(portal, point)
	return (point - portal.boundaryPoint):Dot(portal.tangent)
end

local function portalLinePointAtT(portal, t)
	return Vector3.new(
		portal.boundaryPoint.X + portal.tangent.X * t,
		portal.boundaryPoint.Y,
		portal.boundaryPoint.Z + portal.tangent.Z * t
	)
end

local function getJunctionMeshCenter(junction)
	return junction.intersectionCenter or junction.center
end

local function computeJunctionIntersectionCenter(junction)
	local portals = junction.portals or {}
	if #portals == 0 then
		return junction.center
	end

	local sum = Vector3.zero
	for _, portal in ipairs(portals) do
		sum += portal.corePoint or portal.boundaryPoint or portal.point
	end
	return sum / #portals
end

local function appendUniqueJunctionPoint(points, point)
	for _, existing in ipairs(points) do
		if distanceXZ(existing, point) <= 0.05 then
			return
		end
	end
	table.insert(points, point)
end

local function junctionHullCrossXZ(origin, a, b)
	return (a.X - origin.X) * (b.Z - origin.Z) - (a.Z - origin.Z) * (b.X - origin.X)
end

local function junctionConvexHullXZ(points)
	if #points < 3 then
		return points
	end

	local sorted = {}
	for _, point in ipairs(points) do
		table.insert(sorted, point)
	end
	table.sort(sorted, function(a, b)
		if math.abs(a.X - b.X) > 0.001 then
			return a.X < b.X
		end
		return a.Z < b.Z
	end)

	local lower = {}
	for _, point in ipairs(sorted) do
		while #lower >= 2 and junctionHullCrossXZ(lower[#lower - 1], lower[#lower], point) <= 0.001 do
			table.remove(lower)
		end
		table.insert(lower, point)
	end

	local upper = {}
	for i = #sorted, 1, -1 do
		local point = sorted[i]
		while #upper >= 2 and junctionHullCrossXZ(upper[#upper - 1], upper[#upper], point) <= 0.001 do
			table.remove(upper)
		end
		table.insert(upper, point)
	end

	table.remove(lower, #lower)
	table.remove(upper, #upper)
	local hull = {}
	for _, point in ipairs(lower) do
		table.insert(hull, point)
	end
	for _, point in ipairs(upper) do
		table.insert(hull, point)
	end

	if #hull < 3 then
		return points
	end
	return hull
end

local function lineIntersectionWithParametersXZ(a, dirA, b, dirB)
	local denom = crossXZ(dirA, dirB)
	if math.abs(denom) < 1e-5 then
		return nil
	end

	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local tA = (dx * dirB.Z - dz * dirB.X) / denom
	local tB = (dx * dirA.Z - dz * dirA.X) / denom
	return Vector3.new(a.X + dirA.X * tA, a.Y, a.Z + dirA.Z * tA), tA, tB
end

local function junctionCoreBoundaryLimit(junction)
	local center = getJunctionMeshCenter(junction)
	local limit = 8
	for _, portal in ipairs(junction.portals or {}) do
		local width = (portal.halfWidth or 0) * 2
		limit = math.max(
			limit,
			width * 3,
			distanceXZ(portal.boundaryPoint, center) + width * 2
		)
	end
	return limit
end

local function portalSideLine(portal, sideSign)
	local right = roadRightFromTangent(portal.tangent)
	local center = getJunctionMeshCenter(portal.junction)
	local basePoint = portalLinePointAtT(portal, portalLineT(portal, center))
	local point = basePoint + right * ((portal.halfWidth or 0) * sideSign)
	return {
		portal = portal,
		point = point,
		dir = portal.tangent,
		sideSign = sideSign,
	}
end

local function collectPortalSideLines(junction)
	local lines = {}
	for _, portal in ipairs(junction.portals or {}) do
		table.insert(lines, portalSideLine(portal, -1))
		table.insert(lines, portalSideLine(portal, 1))
	end
	return lines
end

local function sortedJunctionPortals(junction)
	local portals = {}
	for _, portal in ipairs(junction.portals or {}) do
		table.insert(portals, portal)
	end
	table.sort(portals, function(a, b)
		return math.atan2(a.tangent.Z, a.tangent.X) < math.atan2(b.tangent.Z, b.tangent.X)
	end)
	return portals
end

local function appendOrderedJunctionPoint(points, point)
	if #points == 0 or distanceXZ(points[#points], point) > 0.05 then
		table.insert(points, point)
	end
end

local function finalizeOrderedJunctionBoundary(points)
	if #points >= 2 and distanceXZ(points[1], points[#points]) <= 0.05 then
		table.remove(points, #points)
	end
	return points
end

local function junctionGapPoints(center, fromPortal, toPortal)
	local fromRight = roadRightFromTangent(fromPortal.tangent)
	local toRight = roadRightFromTangent(toPortal.tangent)
	local fromHalfWidth = fromPortal.halfWidth or 0
	local toHalfWidth = toPortal.halfWidth or 0
	local fromSide = center - fromRight * fromHalfWidth
	local toSide = center + toRight * toHalfWidth
	local maxExtension = math.max(fromHalfWidth, toHalfWidth) * 1.5 + 50

	local intersection, fromT, toT = lineIntersectionWithParametersXZ(fromSide, fromPortal.tangent, toSide, toPortal.tangent)
	if intersection and fromT >= 0 and toT >= 0 and fromT <= maxExtension and toT <= maxExtension then
		local point = Vector3.new(intersection.X, center.Y, intersection.Z)
		return point, point, { point }
	end

	local safeFromT = math.clamp(fromT or 0, 0, maxExtension)
	local safeToT = math.clamp(toT or 0, 0, maxExtension)
	local fromPoint = Vector3.new(
		fromSide.X + fromPortal.tangent.X * safeFromT,
		center.Y,
		fromSide.Z + fromPortal.tangent.Z * safeFromT
	)
	local toPoint = Vector3.new(
		toSide.X + toPortal.tangent.X * safeToT,
		center.Y,
		toSide.Z + toPortal.tangent.Z * safeToT
	)
	if distanceXZ(fromPoint, toPoint) <= 0.05 then
		local point = (fromPoint + toPoint) * 0.5
		return point, point, { point }
	end
	return fromPoint, toPoint, { fromPoint, toPoint }
end

local function buildJunctionCoreBoundary(junction)
	local portals = sortedJunctionPortals(junction)
	if #portals < 2 then
		return {}
	end

	local center = getJunctionMeshCenter(junction)
	local boundary = {}
	for _, portal in ipairs(portals) do
		portal.coreLeft = nil
		portal.coreRight = nil
	end

	for i, portal in ipairs(portals) do
		local nextPortal = portals[(i % #portals) + 1]
		local fromPoint, toPoint, points = junctionGapPoints(center, portal, nextPortal)
		portal.coreLeft = fromPoint
		nextPortal.coreRight = toPoint
		for _, point in ipairs(points) do
			appendOrderedJunctionPoint(boundary, point)
		end
	end

	if #boundary < 3 then
		local fallback = {}
		for _, portal in ipairs(portals) do
			local right = roadRightFromTangent(portal.tangent)
			appendUniqueJunctionPoint(fallback, center + right * (portal.halfWidth or 0))
			appendUniqueJunctionPoint(fallback, center - right * (portal.halfWidth or 0))
		end
		return junctionConvexHullXZ(fallback)
	end

	return finalizeOrderedJunctionBoundary(boundary)
end

local function buildJunctionSurfaceBoundary(junction)
	local boundary = {}
	for _, point in ipairs(junction.coreBoundary or {}) do
		table.insert(boundary, point)
	end
	return boundary
end

local function pointLineDistanceXZ(point, linePoint, lineDir)
	return math.abs(crossXZ(point - linePoint, lineDir))
end

local function boundaryPointOnPortalSide(boundary, portal, sideSign)
	local line = portalSideLine(portal, sideSign)
	local best = nil
	local bestT = -math.huge

	local function consider(point)
		if pointLineDistanceXZ(point, line.point, line.dir) > 0.08 then
			return
		end
		local t = portalLineT(portal, point)
		if t > bestT then
			best = Vector3.new(point.X, line.point.Y, point.Z)
			bestT = t
		end
	end

	for _, point in ipairs(boundary) do
		consider(point)
	end

	if not best and #boundary >= 2 then
		for i = 1, #boundary do
			local a = boundary[i]
			local b = boundary[(i % #boundary) + 1]
			local edge = b - a
			if edge.Magnitude > 1e-4 then
				local intersection, _, edgeT = lineIntersectionWithParametersXZ(line.point, line.dir, a, edge)
				if intersection and edgeT >= -0.001 and edgeT <= 1.001 then
					consider(intersection)
				end
			end
		end
	end

	return best
end

local function portalSideEntriesForCore(junction)
	local center = getJunctionMeshCenter(junction)
	local entries = {}
	for _, portal in ipairs(junction.portals or {}) do
		local right = roadRightFromTangent(portal.tangent)
		local centerT = portalLineT(portal, center)
		local projectedCenter = portalLinePointAtT(portal, centerT)
		table.insert(entries, {
			portal = portal,
			linePoint = portal.boundaryPoint - right * portal.halfWidth,
			sortPoint = projectedCenter - right * portal.halfWidth,
		})
		table.insert(entries, {
			portal = portal,
			linePoint = portal.boundaryPoint + right * portal.halfWidth,
			sortPoint = projectedCenter + right * portal.halfWidth,
		})
	end

	table.sort(entries, function(a, b)
		return math.atan2(a.sortPoint.Z - center.Z, a.sortPoint.X - center.X)
			< math.atan2(b.sortPoint.Z - center.Z, b.sortPoint.X - center.X)
	end)
	return entries
end

local function isCoreCornerCandidate(junction, fromEntry, toEntry, corner)
	if portalLineT(fromEntry.portal, corner) > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE then
		return false
	end
	if portalLineT(toEntry.portal, corner) > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE then
		return false
	end

	local center = getJunctionMeshCenter(junction)
	local maxDistance = junction.radius
	for _, portal in ipairs(junction.portals or {}) do
		maxDistance = math.max(maxDistance, distanceXZ(portal.boundaryPoint, center) + portal.halfWidth)
	end
	return distanceXZ(corner, center) <= math.max(maxDistance, 6)
end

local function updatePortalGeometry(junction, portal)
	if not junction.intersectionCenter then
		junction.intersectionCenter = computeJunctionIntersectionCenter(junction)
	end

	local right = roadRightFromTangent(portal.tangent)
	local center = getJunctionMeshCenter(junction)
	local coreLeft = portal.coreLeft or (center - right * portal.halfWidth)
	local coreRight = portal.coreRight or (center + right * portal.halfWidth)
	if (coreRight - coreLeft):Dot(right) < 0 then
		coreLeft, coreRight = coreRight, coreLeft
	end

	local corePoint = (coreLeft + coreRight) * 0.5
	local point = portal.boundaryPoint
	portal.corePoint = corePoint
	portal.coreLeft = coreLeft
	portal.coreRight = coreRight
	portal.point = point
	portal.left = point - right * portal.halfWidth
	portal.right = point + right * portal.halfWidth
	portal.coreT = portalLineT(portal, corePoint)
	portal.mouthT = portalLineT(portal, point)
end

local function trimChainEndpointToPortal(junction, portal)
	local samples = portal.chain.samples
	if #samples < 2 then
		return
	end

	local isStart = distanceXZ(samples[1], portal.boundaryPoint) <= distanceXZ(samples[#samples], portal.boundaryPoint)
	if isStart then
		samples[1] = portal.point
		while #samples > 2 and portalLineT(portal, samples[2]) < portal.mouthT - 0.05 do
			table.remove(samples, 2)
		end
	else
		samples[#samples] = portal.point
		while #samples > 2 and portalLineT(portal, samples[#samples - 1]) < portal.mouthT - 0.05 do
			table.remove(samples, #samples - 1)
		end
	end
end

local function finalizeJunctionPortals(junctions)
	for _, junction in ipairs(junctions) do
		junction.coreBoundary = buildJunctionCoreBoundary(junction)
		for _, portal in ipairs(junction.portals or {}) do
			updatePortalGeometry(junction, portal)
		end
		junction.surfaceBoundary = buildJunctionSurfaceBoundary(junction)
		for _, portal in ipairs(junction.portals or {}) do
			trimChainEndpointToPortal(junction, portal)
		end
	end
end

local function emitRoadRun(processedChains, sourceChain, runVertices)
	local samples = {}
	for _, vertex in ipairs(runVertices) do
		table.insert(samples, vertex.point)
	end
	if #samples < 2 or polylineLength(samples, false) <= 0.05 then
		return
	end

	local chain = copyChainWithSamples(sourceChain, samples, false)
	table.insert(processedChains, chain)

	local first = runVertices[1]
	local second = runVertices[2]
	local last = runVertices[#runVertices]
	local beforeLast = runVertices[#runVertices - 1]
	if first.junction then
		addPortalForChain(first.junction, chain, first.point, second.point)
	end
	if last.junction then
		addPortalForChain(last.junction, chain, last.point, beforeLast.point)
	end
end

local function emitExplicitRoadRun(processedChains, sourceChain, samples, startPortal, endPortal)
	if #samples < 2 or polylineLength(samples, false) <= 0.05 then
		return
	end

	local chain = copyChainWithSamples(sourceChain, samples, false)
	table.insert(processedChains, chain)

	if startPortal then
		addPortalForChain(startPortal.junction, chain, startPortal.point, samples[2] or samples[1])
	end
	if endPortal then
		addPortalForChain(endPortal.junction, chain, endPortal.point, samples[#samples - 1] or samples[#samples])
	end
end

local function portalRecordForHit(hit, distance)
	return {
		junction = hit.junction,
		point = hit.point,
		distance = distance,
	}
end

local function splitOpenPathByExplicitHits(processedChains, path, hits)
	table.sort(hits, function(a, b)
		return a.pathDistance < b.pathDistance
	end)

	local cursor = 0
	local startPortal = nil
	for _, hit in ipairs(hits) do
		local cutDistance = math.max(RoadSplineData.sanitizeJunctionRadius(hit.junction.radius), 0)
		local beforeDistance = math.max(0, hit.pathDistance - cutDistance)
		local afterDistance = math.min(path.totalLength, hit.pathDistance + cutDistance)

		if beforeDistance > cursor + 0.05 then
			emitExplicitRoadRun(
				processedChains,
				path.chain,
				collectPathSamples(path, cursor, beforeDistance),
				startPortal,
				portalRecordForHit(hit, beforeDistance)
			)
		end

		cursor = math.max(cursor, afterDistance)
		startPortal = if cursor < path.totalLength - 0.05 then portalRecordForHit(hit, cursor) else nil
	end

	if cursor < path.totalLength - 0.05 then
		emitExplicitRoadRun(processedChains, path.chain, collectPathSamples(path, cursor, path.totalLength), startPortal, nil)
	end
end

local function splitClosedPathByExplicitHits(processedChains, path, hits)
	table.sort(hits, function(a, b)
		return a.pathDistance < b.pathDistance
	end)
	if #hits == 0 then
		table.insert(processedChains, copyChainWithSamples(path.chain, path.samples, true))
		return
	end

	for i, hit in ipairs(hits) do
		local nextHit = hits[(i % #hits) + 1]
		local hitCutDistance = math.max(RoadSplineData.sanitizeJunctionRadius(hit.junction.radius), 0)
		local nextCutDistance = math.max(RoadSplineData.sanitizeJunctionRadius(nextHit.junction.radius), 0)
		local startDistance = (hit.pathDistance + hitCutDistance) % path.totalLength
		local endDistance = (nextHit.pathDistance - nextCutDistance) % path.totalLength
		local effectiveEnd = endDistance
		if effectiveEnd <= startDistance then
			effectiveEnd += path.totalLength
		end
		if effectiveEnd > startDistance + 0.05 then
			emitExplicitRoadRun(
				processedChains,
				path.chain,
				collectPathSamples(path, startDistance, effectiveEnd),
				portalRecordForHit(hit, startDistance),
				portalRecordForHit(nextHit, effectiveEnd)
			)
		end
	end
end

local function splitPathByExplicitJunctions(processedChains, path, hits)
	if not hits or #hits == 0 then
		table.insert(processedChains, copyChainWithSamples(path.chain, path.samples, path.closed))
		return
	end

	if path.closed then
		splitClosedPathByExplicitHits(processedChains, path, hits)
	else
		splitOpenPathByExplicitHits(processedChains, path, hits)
	end
end

local function appendRoadVertex(vertices, vertex)
	local previous = vertices[#vertices]
	if previous and distanceXZ(previous.point, vertex.point) <= 0.01 and previous.junction == vertex.junction then
		return
	end
	table.insert(vertices, vertex)
end

local function splitChainByExplicitJunctions(chain, junctions, processedChains)
	local closedLoop = chain.closed or sampleLoopIsClosed(chain.samples)
	local baseSamples = getUniqueRoadSamples(chain.samples, closedLoop)
	if #baseSamples < (closedLoop and 3 or 2) or #junctions == 0 then
		table.insert(processedChains, copyChainWithSamples(chain, baseSamples, closedLoop))
		return
	end

	local vertices = {}
	local segmentCount = closedLoop and #baseSamples or (#baseSamples - 1)
	appendRoadVertex(vertices, { point = baseSamples[1], junction = junctionTouchingPoint(baseSamples[1], junctions) })
	for i = 1, segmentCount do
		local nextIndex = closedLoop and ((i % #baseSamples) + 1) or (i + 1)
		local a = baseSamples[i]
		local b = baseSamples[nextIndex]
		local cuts = {}
		for _, junction in ipairs(junctions) do
			for _, t in ipairs(segmentCircleIntersections(a, b, junction.center, junction.radius)) do
				table.insert(cuts, {
					t = t,
					point = a:Lerp(b, t),
					junction = junction,
				})
			end
		end
		table.sort(cuts, function(left, right)
			return left.t < right.t
		end)
		for _, cut in ipairs(cuts) do
			local duplicate = false
			for _, vertex in ipairs(vertices) do
				if vertex.junction == cut.junction and distanceXZ(vertex.point, cut.point) <= 0.01 then
					duplicate = true
					break
				end
			end
			if not duplicate then
				appendRoadVertex(vertices, { point = cut.point, junction = cut.junction })
			end
		end
		if not closedLoop or nextIndex ~= 1 then
			appendRoadVertex(vertices, { point = b, junction = junctionTouchingPoint(b, junctions) })
		end
	end

	if #vertices < 2 then
		return
	end

	if not closedLoop then
		local run = {}
		for i = 1, #vertices - 1 do
			local outside = intervalOutsideJunctions(vertices[i].point, vertices[i + 1].point, junctions)
			if outside then
				if #run == 0 then
					table.insert(run, vertices[i])
				end
				table.insert(run, vertices[i + 1])
			elseif #run > 0 then
				emitRoadRun(processedChains, chain, run)
				run = {}
			end
		end
		if #run > 0 then
			emitRoadRun(processedChains, chain, run)
		end
		return
	end

	local intervalCount = #vertices
	local outsideIntervals = {}
	local allOutside = true
	for i = 1, intervalCount do
		local nextIndex = (i % intervalCount) + 1
		outsideIntervals[i] = intervalOutsideJunctions(vertices[i].point, vertices[nextIndex].point, junctions)
		allOutside = allOutside and outsideIntervals[i]
	end
	if allOutside then
		table.insert(processedChains, copyChainWithSamples(chain, baseSamples, true))
		return
	end

	for start = 1, intervalCount do
		local previous = start - 1
		if previous < 1 then
			previous = intervalCount
		end
		if outsideIntervals[start] and not outsideIntervals[previous] then
			local run = { vertices[start] }
			local index = start
			while outsideIntervals[index] do
				local nextIndex = (index % intervalCount) + 1
				table.insert(run, vertices[nextIndex])
				index = nextIndex
				if index == start then
					break
				end
			end
			emitRoadRun(processedChains, chain, run)
		end
	end
end

local function applyExplicitJunctionsToChains(chains, junctions)
	local processedChains = {}
	local paths = {}
	for _, chain in ipairs(chains) do
		local path = buildChainPath(chain)
		if path then
			table.insert(paths, path)
		end
	end

	local hitsByPath = collectExplicitJunctionHits(paths, junctions)
	finalizeExplicitJunctionCenters(junctions)
	for _, path in ipairs(paths) do
		splitPathByExplicitJunctions(processedChains, path, hitsByPath[path])
	end
	finalizeJunctionPortals(junctions)
	return processedChains
end

local function addRoadRibbonToMesh(state, samples, roadWidth, debugLabel)
	local sections = buildRoadCrossSections(samples, roadWidth, ROAD_MESH_THICKNESS * 0.5, debugLabel)
	if not sections then
		return 0
	end

	local rows = {}
	for i = 1, sections.rowCount do
		rows[i] = addRoadLoftRowVertices(state, sections.left[i], sections.right[i], sections.widthSegments)
	end

	local spans = 0
	for i = 1, sections.spanCount do
		local nextIndex = sections.closed and ((i % sections.rowCount) + 1) or (i + 1)
		for j = 1, sections.widthSegments do
			local v1 = rows[i][j]
			local v2 = rows[nextIndex][j]
			local v3 = rows[nextIndex][j + 1]
			local v4 = rows[i][j + 1]
			addMeshTriangle(state, v1, v2, v3)
			addMeshTriangle(state, v1, v3, v4)
		end
		spans += 1
	end
	if Config.authoredRoadDebugLogging == true and sections.roadWidth >= 96 then
		roadDebugLog("road loft %s: width=%.1f rows=%d spans=%d widthSegments=%d", tostring(debugLabel or "road"), sections.roadWidth, sections.rowCount, spans, sections.widthSegments)
	end

	return spans
end

local function normalizePositiveAngleDelta(delta)
	local result = delta
	while result <= 0 do
		result += math.pi * 2
	end
	while result > math.pi * 2 do
		result -= math.pi * 2
	end
	return result
end

local function junctionBoundaryAngle(point, junction)
	local center = getJunctionMeshCenter(junction)
	return math.atan2(point.Z - center.Z, point.X - center.X)
end

local function boundaryEntriesSharePortal(a, b)
	return a.portal ~= nil and b.portal ~= nil and a.portal == b.portal
end

local function mergeBoundaryEntryPortal(target, source)
	if not boundaryEntriesSharePortal(target, source) then
		target.portal = nil
		target.corePoint = target.point
	end
end

local function sortedJunctionBoundaryEntries(junction)
	local entries = {}
	for _, portal in ipairs(junction.portals) do
		table.insert(entries, { point = portal.left, corePoint = portal.coreLeft or portal.left, portal = portal })
		table.insert(entries, { point = portal.right, corePoint = portal.coreRight or portal.right, portal = portal })
	end
	table.sort(entries, function(a, b)
		return junctionBoundaryAngle(a.point, junction) < junctionBoundaryAngle(b.point, junction)
	end)

	local filtered = {}
	for _, entry in ipairs(entries) do
		local previous = filtered[#filtered]
		if previous and distanceXZ(previous.point, entry.point) <= 0.05 then
			mergeBoundaryEntryPortal(previous, entry)
		else
			table.insert(filtered, { point = entry.point, corePoint = entry.corePoint, portal = entry.portal })
		end
	end
	if #filtered >= 2 and distanceXZ(filtered[1].point, filtered[#filtered].point) <= 0.05 then
		mergeBoundaryEntryPortal(filtered[1], filtered[#filtered])
		table.remove(filtered, #filtered)
	end

	return filtered
end

local function addConnectorSubdivisionPoints(boundary, junction, fromPoint, toPoint, subdivisions, surfaceY)
	local center = getJunctionMeshCenter(junction)
	local fromAngle = junctionBoundaryAngle(fromPoint, junction)
	local toAngle = junctionBoundaryAngle(toPoint, junction)
	local delta = normalizePositiveAngleDelta(toAngle - fromAngle)
	if delta <= 1e-4 or delta >= math.pi * 2 - 1e-4 then
		return
	end

	local fromRadius = distanceXZ(fromPoint, center)
	local toRadius = distanceXZ(toPoint, center)
	for i = 1, subdivisions do
		local alpha = i / (subdivisions + 1)
		local angle = fromAngle + delta * alpha
		local radius = fromRadius + (toRadius - fromRadius) * alpha
		table.insert(boundary, Vector3.new(
			center.X + math.cos(angle) * radius,
			surfaceY,
			center.Z + math.sin(angle) * radius
		))
	end
end

local function appendBoundaryPoint(boundary, point)
	if #boundary == 0 or distanceXZ(boundary[#boundary], point) > 0.05 then
		table.insert(boundary, point)
	end
end

local function appendUniqueBoundaryPoint(boundary, point)
	for _, existing in ipairs(boundary) do
		if distanceXZ(existing, point) <= 0.05 then
			return
		end
	end
	table.insert(boundary, point)
end

local function hullCrossXZ(origin, a, b)
	return (a.X - origin.X) * (b.Z - origin.Z) - (a.Z - origin.Z) * (b.X - origin.X)
end

local function convexHullXZ(points)
	if #points < 3 then
		return points
	end

	local sorted = {}
	for _, point in ipairs(points) do
		table.insert(sorted, point)
	end
	table.sort(sorted, function(a, b)
		if math.abs(a.X - b.X) > 0.001 then
			return a.X < b.X
		end
		return a.Z < b.Z
	end)

	local lower = {}
	for _, point in ipairs(sorted) do
		while #lower >= 2 and hullCrossXZ(lower[#lower - 1], lower[#lower], point) <= 0.001 do
			table.remove(lower)
		end
		table.insert(lower, point)
	end

	local upper = {}
	for i = #sorted, 1, -1 do
		local point = sorted[i]
		while #upper >= 2 and hullCrossXZ(upper[#upper - 1], upper[#upper], point) <= 0.001 do
			table.remove(upper)
		end
		table.insert(upper, point)
	end

	table.remove(lower, #lower)
	table.remove(upper, #upper)
	local hull = {}
	for _, point in ipairs(lower) do
		table.insert(hull, point)
	end
	for _, point in ipairs(upper) do
		table.insert(hull, point)
	end

	if #hull < 3 then
		return points
	end
	return hull
end

local function polygonAverageCenter(boundary, fallback)
	if #boundary == 0 then
		return fallback
	end

	local sum = Vector3.zero
	for _, point in ipairs(boundary) do
		sum += point
	end
	local center = sum / #boundary
	return Vector3.new(center.X, fallback.Y, center.Z)
end

local function portalConnectorPoints(portal, surfaceY)
	local coreLeft = portal.coreLeft or portal.left
	local coreRight = portal.coreRight or portal.right
	local mouthLeft = portal.left
	local mouthRight = portal.right
	return Vector3.new(coreLeft.X, surfaceY, coreLeft.Z),
		Vector3.new(coreRight.X, surfaceY, coreRight.Z),
		Vector3.new(mouthLeft.X, surfaceY, mouthLeft.Z),
		Vector3.new(mouthRight.X, surfaceY, mouthRight.Z)
end

local function addLinearSubdivisionPoints(boundary, fromPoint, toPoint, subdivisions)
	for i = 1, subdivisions do
		appendBoundaryPoint(boundary, fromPoint:Lerp(toPoint, i / (subdivisions + 1)))
	end
end

local function isNaturalJunctionCorner(junction, fromEntry, toEntry, point)
	if not fromEntry.portal or not toEntry.portal then
		return false
	end

	local fromCorePoint = fromEntry.corePoint or fromEntry.point
	local toCorePoint = toEntry.corePoint or toEntry.point
	local fromAdvance = (point - fromCorePoint):Dot(fromEntry.portal.tangent)
	local toAdvance = (point - toCorePoint):Dot(toEntry.portal.tangent)
	if fromAdvance > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE or toAdvance > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE then
		return false
	end

	local maxDistance = math.max(
		distanceXZ(fromCorePoint, getJunctionMeshCenter(junction)) + (fromEntry.portal.halfWidth or 0),
		distanceXZ(toCorePoint, getJunctionMeshCenter(junction)) + (toEntry.portal.halfWidth or 0)
	)
	return distanceXZ(point, getJunctionMeshCenter(junction)) <= math.max(maxDistance, 6)
end

local function naturalJunctionCorner(junction, fromEntry, toEntry, surfaceY)
	if not fromEntry.portal or not toEntry.portal then
		return nil
	end

	local intersection = lineIntersectionXZ(
		fromEntry.corePoint or fromEntry.point,
		fromEntry.portal.tangent,
		toEntry.corePoint or toEntry.point,
		toEntry.portal.tangent
	)
	if not intersection then
		return nil
	end

	local point = Vector3.new(intersection.X, surfaceY, intersection.Z)
	if not isNaturalJunctionCorner(junction, fromEntry, toEntry, point) then
		return nil
	end
	return point
end

local function addConnectorBoundaryPoints(boundary, junction, fromEntry, toEntry, subdivisions, surfaceY)
	local corner = naturalJunctionCorner(junction, fromEntry, toEntry, surfaceY)
	if corner then
		addLinearSubdivisionPoints(boundary, Vector3.new(fromEntry.point.X, surfaceY, fromEntry.point.Z), corner, subdivisions)
		appendBoundaryPoint(boundary, corner)
		addLinearSubdivisionPoints(boundary, corner, Vector3.new(toEntry.point.X, surfaceY, toEntry.point.Z), subdivisions)
		return
	end

	if subdivisions > 0 then
		addConnectorSubdivisionPoints(boundary, junction, fromEntry.point, toEntry.point, subdivisions, surfaceY)
	end
end

local function getJunctionBoundary(junction, surfaceY)
	if not junction.portals or #junction.portals == 0 then
		return {}
	end

	if junction.surfaceBoundary and #junction.surfaceBoundary >= 3 then
		local boundary = {}
		for _, point in ipairs(junction.surfaceBoundary) do
			table.insert(boundary, Vector3.new(point.X, surfaceY, point.Z))
		end
		return boundary
	end

	if junction.coreBoundary and #junction.coreBoundary >= 3 then
		local boundary = {}
		for _, point in ipairs(junction.coreBoundary) do
			table.insert(boundary, Vector3.new(point.X, surfaceY, point.Z))
		end
		return boundary
	end

	local boundary = {}
	for _, portal in ipairs(junction.portals) do
		local coreLeft = portal.coreLeft or portal.left
		local coreRight = portal.coreRight or portal.right
		appendUniqueBoundaryPoint(boundary, Vector3.new(coreLeft.X, surfaceY, coreLeft.Z))
		appendUniqueBoundaryPoint(boundary, Vector3.new(coreRight.X, surfaceY, coreRight.Z))
	end
	return convexHullXZ(boundary)
end

local function addPortalConnectorToMesh(state, portal, surfaceY)
	local coreLeft, coreRight, mouthLeft, mouthRight = portalConnectorPoints(portal, surfaceY)
	if distanceXZ(coreLeft, mouthLeft) <= 0.05 and distanceXZ(coreRight, mouthRight) <= 0.05 then
		return
	end

	local coreLeftVertex = addMeshVertex(state, coreLeft)
	local mouthLeftVertex = addMeshVertex(state, mouthLeft)
	local mouthRightVertex = addMeshVertex(state, mouthRight)
	local coreRightVertex = addMeshVertex(state, coreRight)
	addMeshTriangle(state, coreLeftVertex, mouthLeftVertex, mouthRightVertex)
	addMeshTriangle(state, coreLeftVertex, mouthRightVertex, coreRightVertex)
end

local function addIntersectionPatchToMesh(state, junction)
	local fallbackCenter = getJunctionMeshCenter(junction) + Vector3.new(0, ROAD_MESH_THICKNESS * 0.5, 0)
	local boundary = getJunctionBoundary(junction, fallbackCenter.Y)
	if #boundary >= 3 then
		local center = fallbackCenter
		if not (junction.surfaceBoundary and #junction.surfaceBoundary >= 3) then
			center = polygonAverageCenter(boundary, fallbackCenter)
		end
		local centerVertex = addMeshVertex(state, center)
		local ring = {}
		for i, point in ipairs(boundary) do
			ring[i] = addMeshVertex(state, point)
		end

		for i = 1, #ring do
			addMeshTriangle(state, centerVertex, ring[(i % #ring) + 1], ring[i])
		end
	end

	for _, portal in ipairs(junction.portals or {}) do
		addPortalConnectorToMesh(state, portal, fallbackCenter.Y)
	end
end

local function addRoadCollisionSpanToMesh(state, leftA, rightA, leftB, rightB)
	if (leftB - leftA).Magnitude <= 0.05 and (rightB - rightA).Magnitude <= 0.05 then
		return 0
	end

	local bottomOffset = Vector3.new(0, -ROAD_MESH_THICKNESS, 0)
	local aTopLeft = addMeshVertex(state, leftA)
	local aTopRight = addMeshVertex(state, rightA)
	local bTopLeft = addMeshVertex(state, leftB)
	local bTopRight = addMeshVertex(state, rightB)
	local aBottomLeft = addMeshVertex(state, leftA + bottomOffset)
	local aBottomRight = addMeshVertex(state, rightA + bottomOffset)
	local bBottomLeft = addMeshVertex(state, leftB + bottomOffset)
	local bBottomRight = addMeshVertex(state, rightB + bottomOffset)

	addMeshTriangle(state, aTopLeft, bTopLeft, bTopRight)
	addMeshTriangle(state, aTopLeft, bTopRight, aTopRight)

	addMeshTriangle(state, aBottomLeft, bBottomRight, bBottomLeft)
	addMeshTriangle(state, aBottomLeft, aBottomRight, bBottomRight)

	addMeshTriangle(state, aTopLeft, aBottomLeft, bBottomLeft)
	addMeshTriangle(state, aTopLeft, bBottomLeft, bTopLeft)

	addMeshTriangle(state, aTopRight, bTopRight, bBottomRight)
	addMeshTriangle(state, aTopRight, bBottomRight, aBottomRight)

	addMeshTriangle(state, aTopLeft, aTopRight, aBottomRight)
	addMeshTriangle(state, aTopLeft, aBottomRight, aBottomLeft)

	addMeshTriangle(state, bTopLeft, bBottomRight, bTopRight)
	addMeshTriangle(state, bTopLeft, bBottomLeft, bBottomRight)

	return 1
end

local function addIntersectionCollisionPatchToMesh(state, junction)
	local meshCenter = getJunctionMeshCenter(junction)
	local topCenter = meshCenter + Vector3.new(0, ROAD_MESH_THICKNESS * 0.5, 0)
	local bottomCenter = meshCenter + Vector3.new(0, -ROAD_MESH_THICKNESS * 0.5, 0)
	local boundary = getJunctionBoundary(junction, topCenter.Y)
	if #boundary >= 3 then
		if not (junction.surfaceBoundary and #junction.surfaceBoundary >= 3) then
			topCenter = polygonAverageCenter(boundary, topCenter)
		end
		bottomCenter = Vector3.new(topCenter.X, bottomCenter.Y, topCenter.Z)

		local topCenterVertex = addMeshVertex(state, topCenter)
		local bottomCenterVertex = addMeshVertex(state, bottomCenter)
		local topRing = {}
		local bottomRing = {}

		for i, point in ipairs(boundary) do
			topRing[i] = addMeshVertex(state, point)
			bottomRing[i] = addMeshVertex(state, Vector3.new(point.X, bottomCenter.Y, point.Z))
		end

		for i = 1, #topRing do
			local nextIndex = (i % #topRing) + 1
			addMeshTriangle(state, topCenterVertex, topRing[nextIndex], topRing[i])
			addMeshTriangle(state, bottomCenterVertex, bottomRing[i], bottomRing[nextIndex])
			addMeshTriangle(state, topRing[i], bottomRing[nextIndex], bottomRing[i])
			addMeshTriangle(state, topRing[i], topRing[nextIndex], bottomRing[nextIndex])
		end
	end

	for _, portal in ipairs(junction.portals or {}) do
		local coreLeft, coreRight, mouthLeft, mouthRight = portalConnectorPoints(portal, topCenter.Y)
		addRoadCollisionSpanToMesh(state, coreLeft, coreRight, mouthLeft, mouthRight)
	end
end

local function createRuntimeNetworkMeshPart(state, targetModel, meshName)
	if state.faces == 0 then
		return false, "No mesh faces were generated"
	end

	local meshContent = Content.fromObject(state.mesh)
	local okBake, bakeResult, bakedContent = pcall(function()
		return AssetService:CreateDataModelContentAsync(meshContent)
	end)
	if okBake then
		if bakeResult ~= Enum.CreateContentResult.Success then
			return false, "CreateDataModelContentAsync failed: " .. tostring(bakeResult)
		end
		meshContent = bakedContent
	else
		if not dataModelContentWarningShown then
			dataModelContentWarningShown = true
			roadDebugLog(
				"CreateDataModelContentAsync unavailable in this Studio session; using transient runtime mesh content. First mesh=%s error=%s",
				tostring(meshName or "unnamed"),
				tostring(bakeResult)
			)
		end
	end

	local sourceMeshPart = AssetService:CreateMeshPartAsync(meshContent, {
		CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition,
	})
	if not sourceMeshPart then
		return false, "CreateMeshPartAsync returned nil"
	end

	sourceMeshPart.Name = meshName or "AuthoredRoadRuntimeMesh"
	sourceMeshPart.Anchored = true
	sourceMeshPart.Material = Enum.Material.Asphalt
	sourceMeshPart.Color = Color3.fromRGB(28, 28, 32)
	sourceMeshPart.Transparency = 1
	pcall(function()
		sourceMeshPart.DoubleSided = true
	end)
	pcall(function()
		sourceMeshPart.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
	end)
	configureRuntimePart(sourceMeshPart, true)
	sourceMeshPart:SetAttribute("DriveSurface", true)
	sourceMeshPart:SetAttribute("GeneratedBy", "Cab87RoadRuntime")
	sourceMeshPart:SetAttribute("TriangleCount", state.faces)
	sourceMeshPart.Parent = targetModel
	if not string.match(sourceMeshPart.Name, "^RoadCollisionSpan_") then
		roadDebugLog("created mesh part %s faces=%d", sourceMeshPart.Name, state.faces)
	end

	return true, sourceMeshPart
end

local function buildRoadMeshComponent(chains, junctions, targetModel, meshName)
	local state, err = newMeshState()
	if not state then
		return false, err
	end

	local spans = 0
	for _, chain in ipairs(chains) do
		spans += addRoadRibbonToMesh(state, chain.samples, chain.width, meshName .. "/" .. getChainName(chain))
	end

	for _, junction in ipairs(junctions) do
		addIntersectionPatchToMesh(state, junction)
	end

	local ok, meshPartOrErr = createRuntimeNetworkMeshPart(state, targetModel, meshName)
	if not ok then
		return false, meshPartOrErr
	end

	return true, {
		meshPart = meshPartOrErr,
		spans = spans,
		intersections = #junctions,
	}
end

local function buildRoadComponents(chains, junctions)
	local parent = {}
	for _, chain in ipairs(chains) do
		parent[chain] = chain
	end

	local function find(chain)
		local root = parent[chain]
		while root and parent[root] ~= root do
			root = parent[root]
		end
		if root and parent[chain] ~= root then
			parent[chain] = root
		end
		return root
	end

	local function union(a, b)
		local rootA = find(a)
		local rootB = find(b)
		if rootA and rootB and rootA ~= rootB then
			parent[rootB] = rootA
		end
	end

	for _, junction in ipairs(junctions) do
		local firstChain = nil
		for chain in pairs(junction.chains or {}) do
			if not firstChain then
				firstChain = chain
			else
				union(firstChain, chain)
			end
		end
	end

	local componentsByRoot = {}
	local components = {}
	local componentByChain = {}

	for _, chain in ipairs(chains) do
		local root = find(chain)
		local component = componentsByRoot[root]
		if not component then
			component = {
				chains = {},
				junctions = {},
			}
			componentsByRoot[root] = component
			table.insert(components, component)
		end
		table.insert(component.chains, chain)
		componentByChain[chain] = component
	end

	for _, junction in ipairs(junctions) do
		local component = nil
		for chain in pairs(junction.chains or {}) do
			component = componentByChain[chain]
			break
		end
		if component then
			table.insert(component.junctions, junction)
		end
	end

	return components
end

local function buildProcessedRoadNetwork(root)
	local chains = collectSplineBuildData(root)
	if #chains == 0 then
		return nil, "No authored spline chains found"
	end
	for i, chain in ipairs(chains) do
		roadDebugLog(
			"authored chain %d: name=%s samples=%d width=%.1f closed=%s",
			i,
			getChainName(chain),
			#chain.samples,
			chain.width,
			tostring(chain.closed)
		)
	end

	local junctions = collectAuthoredJunctions(root)
	chains = applyExplicitJunctionsToChains(chains, junctions)
	local components = buildRoadComponents(chains, junctions)
	local spanCount = 0
	for _, chain in ipairs(chains) do
		spanCount += math.max(#chain.samples - 1, 0)
	end
	roadDebugLog(
		"processed network: chains=%d authoredJunctions=%d components=%d spans=%d",
		#chains,
		#junctions,
		#components,
		spanCount
	)

	return {
		chains = chains,
		junctions = junctions,
		components = components,
		spans = spanCount,
	}
end

local function createReplicatedProcessedRoadData(roadNetwork, world)
	local oldData = world:FindFirstChild(RUNTIME_SPLINE_DATA_NAME)
	if oldData then
		oldData:Destroy()
	end

	local dataRoot = Instance.new("Folder")
	dataRoot.Name = RUNTIME_SPLINE_DATA_NAME
	dataRoot:SetAttribute("ProcessedRoadNetwork", true)
	dataRoot.Parent = world

	local splinesFolder = Instance.new("Folder")
	splinesFolder.Name = ROAD_EDITOR_SPLINES_NAME
	splinesFolder.Parent = dataRoot

	local junctionsFolder = Instance.new("Folder")
	junctionsFolder.Name = "Junctions"
	junctionsFolder.Parent = dataRoot

	local splineCount = 0
	local pointCount = 0
	for componentIndex, component in ipairs(roadNetwork.components or {}) do
		for _, chain in ipairs(component.chains) do
			splineCount += 1
			local splineData = Instance.new("Model")
			splineData.Name = string.format("Chain%03d", splineCount)
			splineData:SetAttribute("ClosedCurve", chain.closed == true)
			splineData:SetAttribute("SampledRoadChain", true)
			splineData:SetAttribute("ComponentId", componentIndex)
			splineData:SetAttribute(ROAD_WIDTH_ATTR, chain.width)
			splineData.Parent = splinesFolder

			local pointsData = Instance.new("Folder")
			pointsData.Name = ROAD_EDITOR_POINTS_NAME
			pointsData.Parent = splineData

			for sampleIndex, sample in ipairs(chain.samples) do
				pointCount += 1
				local pointData = Instance.new("Vector3Value")
				pointData.Name = string.format("P%04d", sampleIndex)
				pointData.Value = sample
				pointData.Parent = pointsData
			end
		end
	end

	local junctionCount = 0
	for componentIndex, component in ipairs(roadNetwork.components or {}) do
		for _, junction in ipairs(component.junctions) do
			junctionCount += 1
			local junctionCenter = junction.intersectionCenter or junction.center
			local portalAttachDistance = junction.radius
			for _, portal in ipairs(junction.portals or {}) do
				portalAttachDistance = math.max(portalAttachDistance, distanceXZ(portal.point, junctionCenter))
			end
			local junctionData = Instance.new("Vector3Value")
			junctionData.Name = string.format("J%04d", junctionCount)
			junctionData.Value = junctionCenter
			junctionData:SetAttribute("Radius", junction.radius)
			junctionData:SetAttribute(RoadSplineData.JUNCTION_CROSSWALK_LENGTH_ATTR, RoadSplineData.sanitizeJunctionCrosswalkLength(junction.crosswalkLength))
			junctionData:SetAttribute(RoadSplineData.JUNCTION_PORTAL_ATTACH_DISTANCE_ATTR, portalAttachDistance)
			junctionData:SetAttribute(RoadSplineData.JUNCTION_SUBDIVISIONS_ATTR, RoadSplineData.sanitizeJunctionSubdivisions(junction.subdivisions))
			junctionData:SetAttribute("ComponentId", componentIndex)
			junctionData.Parent = junctionsFolder
		end
	end

	dataRoot:SetAttribute("SplineCount", splineCount)
	dataRoot:SetAttribute("PointCount", pointCount)
	dataRoot:SetAttribute("JunctionCount", junctionCount)
	dataRoot:SetAttribute("ComponentCount", #(roadNetwork.components or {}))
	dataRoot:SetAttribute("SpanCount", roadNetwork.spans or 0)
	roadDebugLog(
		"replicated processed spline data: splines=%d points=%d junctions=%d components=%d spans=%d",
		splineCount,
		pointCount,
		junctionCount,
		#(roadNetwork.components or {}),
		roadNetwork.spans or 0
	)
	return dataRoot
end

local function buildRuntimeRoadNetworkMeshes(chains, junctions, targetModel)
	local components = buildRoadComponents(chains, junctions)
	local meshParts = {}
	local totalSpans = 0

	for i, component in ipairs(components) do
		local meshName = #components == 1 and "AuthoredRoadRuntimeMesh" or string.format("AuthoredRoadRuntimeMesh_%03d", i)
		local ok, infoOrErr = buildRoadMeshComponent(component.chains, component.junctions, targetModel, meshName)
		if not ok then
			return false, infoOrErr
		end

		totalSpans += infoOrErr.spans
		table.insert(meshParts, infoOrErr.meshPart)
	end

	return true, {
		meshParts = meshParts,
		spans = totalSpans,
		components = #components,
	}
end

local function buildRuntimeRoadMesh(roadNetwork, world, driveSurfaces)
	if not roadNetwork or #(roadNetwork.chains or {}) == 0 then
		return nil, 0, "No processed road chains found"
	end

	local meshModel = Instance.new("Model")
	meshModel.Name = "AuthoredRoadRuntimeMesh"
	meshModel.Parent = world

	local ok, meshInfoOrErr = pcall(function()
		local okMesh, meshInfo = buildRuntimeRoadNetworkMeshes(roadNetwork.chains, roadNetwork.junctions, meshModel)
		if not okMesh then
			error(tostring(meshInfo), 0)
		end
		return meshInfo
	end)

	if not ok then
		meshModel:Destroy()
		local message = tostring(meshInfoOrErr)
		roadDebugWarn("runtime road mesh build failed; client will rebuild visual mesh: %s", message)
		return nil, 0, message
	end

	for _, meshPart in ipairs(meshInfoOrErr.meshParts) do
		trackPart(driveSurfaces, meshPart)
	end
	roadDebugLog(
		"runtime full mesh built: meshParts=%d spans=%d components=%d",
		#meshInfoOrErr.meshParts,
		meshInfoOrErr.spans or 0,
		meshInfoOrErr.components or 0
	)

	return meshModel, #meshInfoOrErr.meshParts, nil
end

local function buildRuntimeCollisionMeshSections(roadNetwork, world, driveSurfaces)
	if not roadNetwork or #(roadNetwork.chains or {}) == 0 then
		return 0, "No processed road chains found"
	end

	local collisionModel = Instance.new("Model")
	collisionModel.Name = "AuthoredRoadCollisionMeshSections"
	collisionModel.Parent = world

	local builtCount = 0
	local ok, err = pcall(function()
		for _, chain in ipairs(roadNetwork.chains) do
			local sections = buildRoadCrossSections(chain.samples, chain.width, ROAD_MESH_THICKNESS * 0.5, "collision/" .. getChainName(chain))
			if sections then
				for i = 1, sections.spanCount do
					local nextIndex = sections.closed and ((i % sections.rowCount) + 1) or (i + 1)
					local state, stateErr = newMeshState()
					if not state then
						error(tostring(stateErr), 0)
					end

					addRoadCollisionSpanToMesh(
						state,
						sections.left[i],
						sections.right[i],
						sections.left[nextIndex],
						sections.right[nextIndex]
					)
					local okMesh, meshPartOrErr = createRuntimeNetworkMeshPart(
						state,
						collisionModel,
						string.format("RoadCollisionSpan_%04d", builtCount + 1)
					)
					if not okMesh then
						error(tostring(meshPartOrErr), 0)
					end
					trackPart(driveSurfaces, meshPartOrErr)
					builtCount += 1
				end
			end
		end

		for _, junction in ipairs(roadNetwork.junctions or {}) do
			local state, stateErr = newMeshState()
			if not state then
				error(tostring(stateErr), 0)
			end

			addIntersectionCollisionPatchToMesh(state, junction)
			if state.faces == 0 then
				continue
			end
			local okMesh, meshPartOrErr = createRuntimeNetworkMeshPart(
				state,
				collisionModel,
				string.format("RoadCollisionJunction_%04d", builtCount + 1)
			)
			if not okMesh then
				error(tostring(meshPartOrErr), 0)
			end
			trackPart(driveSurfaces, meshPartOrErr)
			builtCount += 1
		end
	end)

	if not ok then
		collisionModel:Destroy()
		roadDebugWarn("runtime collision mesh sections failed after %d sections: %s", builtCount, tostring(err))
		return 0, tostring(err)
	end

	if builtCount == 0 then
		collisionModel:Destroy()
	end
	roadDebugLog("runtime collision mesh sections built: sections=%d chains=%d junctions=%d", builtCount, #(roadNetwork.chains or {}), #(roadNetwork.junctions or {}))
	return builtCount, nil
end

local function createRoadStrip(parent, a, b, index, width, thickness, surfaceOffset, visible, collidable, prefix)
	local delta = b - a
	local len = delta.Magnitude
	if len <= 0.05 then
		return nil
	end

	local verticalOffset = Vector3.new(0, surfaceOffset - thickness * 0.5, 0)
	local mid = (a + b) * 0.5 + verticalOffset
	local part = makePart(parent, {
		Name = string.format("%s_%04d", prefix, index),
		Size = Vector3.new(width, thickness, len + Config.authoredRoadOverlap),
		CFrame = CFrame.lookAt(mid, b + verticalOffset),
		Transparency = visible and 0 or 1,
		Color = Color3.fromRGB(28, 28, 32),
		Material = Enum.Material.Asphalt,
	})
	configureRuntimePart(part, collidable)
	return part
end

local function createRoadCap(parent, position, index, width, thickness, surfaceOffset, visible, collidable, prefix)
	local cap = makePart(parent, {
		Name = string.format("%s_%04d", prefix, index),
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, width, width),
		CFrame = CFrame.new(position + Vector3.new(0, surfaceOffset - thickness * 0.5, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Transparency = visible and 0 or 1,
		Color = Color3.fromRGB(28, 28, 32),
		Material = Enum.Material.Asphalt,
	})
	configureRuntimePart(cap, collidable)
	return cap
end

local function createCollisionSegment(parent, a, b, index, width, visible)
	local thickness = math.max(Config.authoredRoadCollisionThickness, 0.05)
	local surfaceOffset = Config.authoredRoadCollisionSurfaceOffset
	local part = createRoadStrip(parent, a, b, index, width, thickness, surfaceOffset, visible, true, "AuthoredRoadCollision")
	if not part then
		return nil
	end
	part:SetAttribute("DriveSurface", true)
	return part
end

local function createCollisionCap(parent, position, index, width, visible)
	local thickness = math.max(Config.authoredRoadCollisionThickness, 0.05)
	local surfaceOffset = Config.authoredRoadCollisionSurfaceOffset
	local cap = createRoadCap(parent, position, index, width, thickness, surfaceOffset, visible, true, "AuthoredRoadCollisionCap")
	cap:SetAttribute("DriveSurface", true)
	return cap
end

local function createVisualSegment(parent, a, b, index, width)
	return createRoadStrip(parent, a, b, index, width, VISUAL_ROAD_THICKNESS, VISUAL_ROAD_SURFACE_OFFSET, true, false, "AuthoredRoadVisual")
end

local function createVisualCap(parent, position, index, width)
	return createRoadCap(parent, position, index, width, VISUAL_ROAD_THICKNESS, VISUAL_ROAD_SURFACE_OFFSET, true, false, "AuthoredRoadVisualCap")
end

local function findFirstSpawn(root)
	for _, spline in ipairs(getAuthoredSplines(root)) do
		local points = getAuthoredSplinePoints(spline)
		if #points > 0 then
			local firstPosition = RoadSplineData.getPointPosition(points[1])
			local spawnPosition = firstPosition + Vector3.new(0, Config.carRideHeight, 0)
			local spawnYaw = 0

			if #points >= 2 then
				local delta = RoadSplineData.getPointPosition(points[2]) - firstPosition
				local horizontal = Vector3.new(delta.X, 0, delta.Z)
				if horizontal.Magnitude > 0.001 then
					spawnYaw = vectorToYaw(horizontal.Unit)
				end
			end

			return {
				position = spawnPosition,
				yaw = spawnYaw,
			}
		end
	end

	return {
		position = Config.carSpawn,
		yaw = 0,
	}
end

local function getMarkerFolder(root)
	local folderName = Config.cabCompanyMarkerFolderName or "Markers"
	local folder = root and root:FindFirstChild(folderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

local function isCabCompanyMarker(part)
	if not (part and part:IsA("BasePart")) then
		return false
	end

	local markerType = part:GetAttribute("Cab87MarkerType")
	return markerType == "CabCompany" or markerType == "CabCompanyNode"
end

local function isPlayerSpawnMarker(part)
	if not (part and part:IsA("BasePart")) then
		return false
	end

	return part:GetAttribute("Cab87MarkerType") == "PlayerSpawn"
end

local function findAuthoredMarker(root, markerName, predicate)
	if not root then
		return nil
	end

	local markersFolder = getMarkerFolder(root)
	if markersFolder then
		local marker = markersFolder:FindFirstChild(markerName)
		if marker and marker:IsA("BasePart") then
			return marker
		end
	end

	local direct = root:FindFirstChild(markerName)
	if direct and direct:IsA("BasePart") then
		return direct
	end

	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") and (item.Name == markerName or predicate(item)) then
			return item
		end
	end

	return nil
end

local function findAuthoredCabCompanyMarker(root)
	return findAuthoredMarker(root, Config.cabCompanyMarkerName or "CabCompanyNode", isCabCompanyMarker)
end

local function findAuthoredPlayerSpawnMarker(root)
	return findAuthoredMarker(root, Config.cabCompanyPlayerSpawnMarkerName or "PlayerSpawnPoint", isPlayerSpawnMarker)
end

local function appendParts(target, source)
	for _, item in ipairs(source or {}) do
		table.insert(target, item)
	end
end

local function buildAuthoredCabCompany(root, world, driveSurfaces, crashObstacles)
	local marker = findAuthoredCabCompanyMarker(root)
	if not marker then
		return nil
	end

	local playerSpawnMarker = findAuthoredPlayerSpawnMarker(root)
	local result = CabCompanyWorldBuilder.create(world, Config, {
		cabSpawnPosition = marker.Position,
		cabSpawnYaw = CabCompanyWorldBuilder.yawFromCFrame(marker.CFrame),
		playerSpawnPosition = playerSpawnMarker and playerSpawnMarker.Position or nil,
		playerSpawnYaw = playerSpawnMarker and CabCompanyWorldBuilder.yawFromCFrame(playerSpawnMarker.CFrame) or nil,
		source = marker:GetFullName(),
	})

	appendParts(driveSurfaces, result.driveSurfaces)
	appendParts(crashObstacles, result.crashObstacles)
	roadDebugLog(
		"cab company marker active: marker=%s spawn=(%.1f, %.1f, %.1f)",
		marker:GetFullName(),
		result.spawnPose.position.X,
		result.spawnPose.position.Y,
		result.spawnPose.position.Z
	)

	return result.spawnPose
end

local function hideEditorRootForPlay(root)
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Transparency = 1
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
end

local function cloneRoadVisuals(root, world)
	local network = root:FindFirstChild(ROAD_EDITOR_NETWORK_NAME)
	if not (network and network:IsA("Model")) or countRoadSurfaceParts(network) == 0 then
		return nil, 0
	end

	local clone = network:Clone()
	clone.Name = "AuthoredRoadVisuals"
	removeEditorDebugVisuals(clone)
	clone.Parent = world

	for _, item in ipairs(clone:GetDescendants()) do
		if item:IsA("BasePart") then
			configureRuntimePart(item, false)
		end
	end

	return clone, countRoadSurfaceParts(clone)
end

local function buildGeneratedRoadVisuals(root, world)
	local visualModel = Instance.new("Model")
	visualModel.Name = "AuthoredRoadGeneratedVisuals"
	visualModel.Parent = world

	local segmentIndex = 0
	local capIndex = 0

	for _, spline in ipairs(getAuthoredSplines(root)) do
		local points = getAuthoredSplinePoints(spline)
		local width = getSplineRoadWidth(spline)
		if #points >= 2 then
			local samples = sampleAuthoredSpline(points, spline:GetAttribute("ClosedCurve") == true)
			for i = 1, #samples - 1 do
				segmentIndex += 1
				createVisualSegment(visualModel, samples[i], samples[i + 1], segmentIndex, width)
			end
		end

		for _, point in ipairs(points) do
			capIndex += 1
			createVisualCap(visualModel, RoadSplineData.getPointPosition(point), capIndex, width)
		end
	end

	if segmentIndex == 0 and capIndex == 0 then
		visualModel:Destroy()
		return nil, 0
	end

	return visualModel, segmentIndex + capIndex
end

local function buildCollision(root, world, driveSurfaces, visible)
	local collisionModel = Instance.new("Model")
	collisionModel.Name = "AuthoredRoadCollision"
	collisionModel.Parent = world

	local segmentIndex = 0
	local capIndex = 0

	for _, spline in ipairs(getAuthoredSplines(root)) do
		local points = getAuthoredSplinePoints(spline)
		local width = getSplineRoadWidth(spline)
		if #points >= 2 then
			local samples = sampleAuthoredSpline(points, spline:GetAttribute("ClosedCurve") == true)
			for i = 1, #samples - 1 do
				segmentIndex += 1
				local part = createCollisionSegment(collisionModel, samples[i], samples[i + 1], segmentIndex, width, visible)
				if part then
					trackPart(driveSurfaces, part)
				end
			end
		end

		for _, point in ipairs(points) do
			capIndex += 1
			trackPart(driveSurfaces, createCollisionCap(collisionModel, RoadSplineData.getPointPosition(point), capIndex, width, visible))
		end
	end

	return segmentIndex
end

local function useRoadNetworkFallback(network, driveSurfaces)
	if not (network and network:IsA("Model")) then
		return 0
	end

	local count = 0
	for _, item in ipairs(network:GetDescendants()) do
		if item:IsA("BasePart") and not hasAncestorNamed(item, ROAD_EDITOR_WIREFRAME_NAME) then
			configureRuntimePart(item, true)
			item.Transparency = 1
			item:SetAttribute("DriveSurface", true)
			trackPart(driveSurfaces, item)
			count += 1
		end
	end

	return count
end

function AuthoredRoadRuntime.getRoot()
	local root = Workspace:FindFirstChild(ROAD_EDITOR_ROOT_NAME)
	if root and root:IsA("Model") then
		roadDebugLog("found authored road root: %s", root:GetFullName())
		return root
	end

	roadDebugLog("authored road root not found: %s", ROAD_EDITOR_ROOT_NAME)
	return nil
end

function AuthoredRoadRuntime.hasRoadData(root)
	if Config.useAuthoredRoadEditorWorld ~= true or not root then
		roadDebugLog(
			"hasRoadData=false configEnabled=%s root=%s",
			tostring(Config.useAuthoredRoadEditorWorld == true),
			root and root:GetFullName() or "nil"
		)
		return false
	end

	local splineCount = 0
	local pointCount = 0
	for _, spline in ipairs(getAuthoredSplines(root)) do
		splineCount += 1
		local points = getAuthoredSplinePoints(spline)
		pointCount += #points
		if #points >= 2 then
			roadDebugLog("hasRoadData=true splines=%d points=%d firstValid=%s", splineCount, pointCount, spline.Name)
			return true
		end
	end

	local network = root:FindFirstChild(ROAD_EDITOR_NETWORK_NAME)
	if network and network:IsA("Model") then
		local surfaceParts = countRoadSurfaceParts(network)
		roadDebugLog("hasRoadData=%s splines=%d points=%d networkSurfaceParts=%d", tostring(surfaceParts > 0), splineCount, pointCount, surfaceParts)
		return surfaceParts > 0
	end

	roadDebugLog("hasRoadData=false splines=%d points=%d no network fallback", splineCount, pointCount)
	return false
end

function AuthoredRoadRuntime.createWorld(root)
	local oldWorld = Workspace:FindFirstChild(RUNTIME_WORLD_NAME)
	if oldWorld then
		oldWorld:Destroy()
	end

	local world = Instance.new("Model")
	world.Name = RUNTIME_WORLD_NAME
	world:SetAttribute("GeneratorVersion", "authored-road-editor")
	world:SetAttribute("Source", ROAD_EDITOR_ROOT_NAME)
	world.Parent = Workspace

	local driveSurfaces = {}
	local crashObstacles = {}
	local spawnPose = findFirstSpawn(root)
	local authoredCabCompanyMarker = findAuthoredCabCompanyMarker(root)
	if authoredCabCompanyMarker then
		spawnPose = {
			position = authoredCabCompanyMarker.Position,
			yaw = CabCompanyWorldBuilder.yawFromCFrame(authoredCabCompanyMarker.CFrame),
		}
	end
	local authoredSplines = getAuthoredSplines(root)
	roadDebugLog(
		"createWorld start: root=%s splines=%d editorSurfaceParts=%d spawn=(%.1f, %.1f, %.1f)",
		root and root:GetFullName() or "nil",
		#authoredSplines,
		countRoadSurfaceParts(root),
		spawnPose.position.X,
		spawnPose.position.Y,
		spawnPose.position.Z
	)
	local roadNetwork, roadNetworkErr = buildProcessedRoadNetwork(root)
	local replicatedSplineData
	if roadNetwork then
		replicatedSplineData = createReplicatedProcessedRoadData(roadNetwork, world)
	else
		roadDebugWarn("processed road network failed; falling back to raw spline data: %s", tostring(roadNetworkErr))
		replicatedSplineData = createReplicatedSplineData(root, world)
	end

	local sectionCount = 0
	local sectionErr = nil
	if roadNetwork then
		sectionCount, sectionErr = buildRuntimeCollisionMeshSections(roadNetwork, world, driveSurfaces)
	end
	local runtimeMeshCount = 0
	local runtimeMeshError = sectionErr
	if sectionCount == 0 then
		_, runtimeMeshCount, runtimeMeshError = buildRuntimeRoadMesh(roadNetwork, world, driveSurfaces)
	end

	world:SetAttribute("NeedsClientRoadMesh", true)
	world:SetAttribute("AuthoredRoadVisualSource", "ClientRuntimeMesh")
	world:SetAttribute("AuthoredRoadServerMeshError", runtimeMeshError or "")
	world:SetAttribute("AuthoredRoadSplineCount", replicatedSplineData:GetAttribute("SplineCount") or 0)
	world:SetAttribute("AuthoredRoadPointCount", replicatedSplineData:GetAttribute("PointCount") or 0)
	world:SetAttribute("AuthoredRoadJunctionCount", replicatedSplineData:GetAttribute("JunctionCount") or 0)
	world:SetAttribute("AuthoredRoadComponentCount", replicatedSplineData:GetAttribute("ComponentCount") or 0)
	world:SetAttribute("AuthoredRoadSpanCount", replicatedSplineData:GetAttribute("SpanCount") or 0)
	if sectionCount > 0 then
		world:SetAttribute("AuthoredRoadServerCollisionSource", "RuntimeMeshSections")
		world:SetAttribute("AuthoredRoadServerMeshError", "")
	elseif runtimeMeshCount > 0 then
		world:SetAttribute("AuthoredRoadServerCollisionSource", "RuntimeMesh")
	else
		world:SetAttribute("AuthoredRoadServerCollisionSource", "PrimitiveFallback")
		if sectionErr then
			world:SetAttribute("AuthoredRoadServerMeshError", tostring(runtimeMeshError or "") .. " | sections: " .. tostring(sectionErr))
		end
		local collisionSegments = buildCollision(root, world, driveSurfaces, false)
		if collisionSegments == 0 then
			useRoadNetworkFallback(root:FindFirstChild(ROAD_EDITOR_NETWORK_NAME), driveSurfaces)
		end
	end
	local cabCompanySpawnPose = buildAuthoredCabCompany(root, world, driveSurfaces, crashObstacles)
	if cabCompanySpawnPose then
		spawnPose = cabCompanySpawnPose
	end
	roadDebugLog(
		"createWorld done: collisionSource=%s sectionCount=%d runtimeMeshCount=%d driveSurfaces=%d serverMeshError=%s",
		tostring(world:GetAttribute("AuthoredRoadServerCollisionSource")),
		sectionCount,
		runtimeMeshCount,
		#driveSurfaces,
		tostring(world:GetAttribute("AuthoredRoadServerMeshError") or "")
	)
	hideEditorRootForPlay(root)

	return world, driveSurfaces, crashObstacles, spawnPose
end

return AuthoredRoadRuntime
