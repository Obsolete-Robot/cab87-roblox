local AssetService = game:GetService("AssetService")
local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local AuthoredRoadRuntime = {}

local ROAD_EDITOR_ROOT_NAME = "Cab87RoadEditor"
local ROAD_EDITOR_SPLINES_NAME = "Splines"
local ROAD_EDITOR_POINTS_NAME = "RoadPoints"
local ROAD_EDITOR_NETWORK_NAME = "RoadNetwork"
local ROAD_EDITOR_WIREFRAME_NAME = "WireframeDisplay"
local ROAD_WIDTH_ATTR = "RoadWidth"
local RUNTIME_WORLD_NAME = "Cab87World"
local RUNTIME_SPLINE_DATA_NAME = "AuthoredRoadSplineData"
local DEFAULT_AUTHORED_ROAD_WIDTH = 28
local AUTHORED_ROAD_MIN_WIDTH = 8
local AUTHORED_ROAD_MAX_WIDTH = 200
local VISUAL_ROAD_THICKNESS = 0.35
local VISUAL_ROAD_SURFACE_OFFSET = 0.72
local ROAD_MESH_THICKNESS = 1.2
local ENDPOINT_WELD_DISTANCE = 22
local INTERSECTION_RADIUS_SCALE = 0.5
local INTERSECTION_BLEND_SCALE = 0.95
local INTERSECTION_MERGE_SCALE = 0.45
local INTERSECTION_RING_SEGMENTS = 28
local ROAD_WIDTH_TRIANGULATION_STEP = 24
local ROAD_WIDTH_MAX_INTERNAL_LOOPS = 2
local ROAD_LOFT_LENGTH_STEP = Config.authoredRoadSampleStepStuds or 8
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

local function getAuthoredSplines(root)
	local splinesFolder = root and root:FindFirstChild(ROAD_EDITOR_SPLINES_NAME)
	if splinesFolder and splinesFolder:IsA("Folder") then
		return sortedChildren(splinesFolder, "Model")
	end

	local legacyPoints = root and root:FindFirstChild(ROAD_EDITOR_POINTS_NAME)
	if legacyPoints and legacyPoints:IsA("Folder") then
		return { root }
	end

	return {}
end

local function getAuthoredSplinePoints(spline)
	local pointsFolder = spline and spline:FindFirstChild(ROAD_EDITOR_POINTS_NAME)
	if not (pointsFolder and pointsFolder:IsA("Folder")) then
		return {}
	end

	return sortedChildren(pointsFolder, "BasePart")
end

local getSplineRoadWidth

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
				pointData.Value = point.Position
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

local function sanitizeRoadWidth(value)
	local width = tonumber(value) or DEFAULT_AUTHORED_ROAD_WIDTH
	return math.clamp(width, AUTHORED_ROAD_MIN_WIDTH, AUTHORED_ROAD_MAX_WIDTH)
end

function getSplineRoadWidth(spline)
	local configuredDefault = tonumber(Config.authoredRoadCollisionWidth) or DEFAULT_AUTHORED_ROAD_WIDTH
	return sanitizeRoadWidth(tonumber(spline and spline:GetAttribute(ROAD_WIDTH_ATTR)) or configuredDefault)
end

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

local function catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

local function sampleAuthoredSpline(points, closedCurve)
	local positions = {}
	for _, point in ipairs(points) do
		table.insert(positions, point.Position)
	end

	if #positions < 2 then
		return positions
	end

	if closedCurve and #positions < 3 then
		closedCurve = false
	end

	local samples = {}
	local sampleStep = math.max(Config.authoredRoadSampleStepStuds, 1)
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
				table.insert(samples, catmullRom(p0, p1, p2, p3, s / subdivisions))
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
				table.insert(samples, catmullRom(p0, p1, p2, p3, s / subdivisions))
			end
		end

		table.insert(samples, positions[#positions])
	end

	return samples
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

local function distanceXZ(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
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
	local chains = {}
	for _, spline in ipairs(getAuthoredSplines(root)) do
		local points = getAuthoredSplinePoints(spline)
		if #points >= 2 then
			local closed = spline:GetAttribute("ClosedCurve") == true
			table.insert(chains, {
				spline = spline,
				points = points,
				samples = sampleAuthoredSpline(points, closed),
				closed = closed,
				width = getSplineRoadWidth(spline),
			})
		end
	end
	return chains
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

local function sampleLoopIsClosed(samples)
	if #samples < 3 then
		return false
	end
	return distanceXZ(samples[1], samples[#samples]) <= 0.05 and math.abs(samples[1].Y - samples[#samples].Y) <= 0.05
end

local function roadRightFromTangent(tangent)
	local right = Vector3.yAxis:Cross(tangent)
	if right.Magnitude < 1e-4 then
		return Vector3.xAxis
	end
	return right.Unit
end

local function horizontalUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-4 then
		return nil
	end
	return flat.Unit
end

local function addRoadLoftRowVertices(state, left, right, widthSegments)
	local row = {}
	for j = 0, widthSegments do
		row[j + 1] = addMeshVertex(state, left:Lerp(right, j / widthSegments))
	end
	return row
end

local function getRoadSampleTangent(samples, index, edgeCount, closedLoop, fallbackDir)
	if closedLoop then
		local prevIndex = index - 1
		if prevIndex < 1 then
			prevIndex = edgeCount
		end
		local nextIndex = index + 1
		if nextIndex > edgeCount then
			nextIndex = 1
		end
		local prevDir = horizontalUnit(samples[index] - samples[prevIndex])
		local nextDir = horizontalUnit(samples[nextIndex] - samples[index])
		if prevDir and nextDir then
			local combined = prevDir + nextDir
			if combined.Magnitude > 1e-4 then
				return combined.Unit
			end
		end
		return nextDir or prevDir or fallbackDir
	end

	if index == 1 then
		return horizontalUnit(samples[2] - samples[1]) or fallbackDir
	elseif index == edgeCount then
		return horizontalUnit(samples[edgeCount] - samples[edgeCount - 1]) or fallbackDir
	end

	local prevDir = horizontalUnit(samples[index] - samples[index - 1])
	local nextDir = horizontalUnit(samples[index + 1] - samples[index])
	if prevDir and nextDir then
		local combined = prevDir + nextDir
		if combined.Magnitude > 1e-4 then
			return combined.Unit
		end
	end
	return nextDir or prevDir or fallbackDir
end

local function polylineLength(points, closedLoop)
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

local function samplePolylineAtFraction(points, closedLoop, fraction)
	local count = #points
	if count == 0 then
		return Vector3.zero
	elseif count == 1 then
		return points[1]
	end

	local totalLength = polylineLength(points, closedLoop)
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

local function buildRoadCrossSections(samples, roadWidth, surfaceYOffset, debugLabel)
	if #samples < 2 then
		return nil
	end

	roadWidth = sanitizeRoadWidth(roadWidth)
	local closedLoop = sampleLoopIsClosed(samples)
	local edgeCount = closedLoop and #samples - 1 or #samples
	if edgeCount < 2 then
		return nil
	end

	local halfWidth = roadWidth * 0.5
	local widthSegments = math.min(ROAD_WIDTH_MAX_INTERNAL_LOOPS + 1, math.max(1, math.ceil(roadWidth / ROAD_WIDTH_TRIANGULATION_STEP)))
	local centerControls = {}
	local leftControls = {}
	local rightControls = {}
	local rights = {}
	local fallbackDir = Vector3.new(0, 0, 1)
	local rightFlips = 0

	for i = 1, edgeCount do
		local tangent = getRoadSampleTangent(samples, i, edgeCount, closedLoop, fallbackDir)
		fallbackDir = tangent or fallbackDir
		local right = roadRightFromTangent(fallbackDir)
		if i > 1 and rights[i - 1] and right:Dot(rights[i - 1]) < 0 then
			right = -right
			rightFlips += 1
		end
		local center = samples[i] + Vector3.new(0, surfaceYOffset, 0)
		centerControls[i] = center
		rights[i] = right
		leftControls[i] = center - right * halfWidth
		rightControls[i] = center + right * halfWidth
	end

	local centerLength = polylineLength(centerControls, closedLoop)
	local leftLength = polylineLength(leftControls, closedLoop)
	local rightLength = polylineLength(rightControls, closedLoop)
	local desiredRowCount
	if closedLoop then
		desiredRowCount = math.max(3, edgeCount, math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP))
	else
		desiredRowCount = math.max(2, edgeCount, math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP) + 1)
	end
	local minEdgeStep = math.max(2, roadWidth * 0.02)
	local shortestCurveLength = math.min(centerLength, leftLength, rightLength)
	local edgeLimitedRowCount = desiredRowCount
	if shortestCurveLength > 1e-4 then
		if closedLoop then
			edgeLimitedRowCount = math.max(3, math.floor(shortestCurveLength / minEdgeStep))
		else
			edgeLimitedRowCount = math.max(2, math.floor(shortestCurveLength / minEdgeStep) + 1)
		end
	end
	local rowCount = math.min(desiredRowCount, edgeLimitedRowCount)

	local spanCount = closedLoop and rowCount or rowCount - 1
	local centers = {}
	local leftPositions = {}
	local rightPositions = {}
	for i = 1, rowCount do
		local fraction
		if closedLoop then
			fraction = (i - 1) / rowCount
		else
			fraction = rowCount > 1 and ((i - 1) / (rowCount - 1)) or 0
		end
		centers[i] = samplePolylineAtFraction(centerControls, closedLoop, fraction)
		leftPositions[i] = samplePolylineAtFraction(leftControls, closedLoop, fraction)
		rightPositions[i] = samplePolylineAtFraction(rightControls, closedLoop, fraction)
	end

	local collapsedSpans = 0
	local tightSpans = 0
	local minCenterStep = math.huge
	local minLeftStep = math.huge
	local minRightStep = math.huge
	local minLoftWidth = math.huge
	local maxLoftWidth = 0
	local pinchedRows = 0
	for i = 1, rowCount do
		local loftWidth = (rightPositions[i] - leftPositions[i]).Magnitude
		minLoftWidth = math.min(minLoftWidth, loftWidth)
		maxLoftWidth = math.max(maxLoftWidth, loftWidth)
		if loftWidth < roadWidth * 0.35 then
			pinchedRows += 1
		end
	end
	for i = 1, spanCount do
		local nextIndex = closedLoop and ((i % rowCount) + 1) or (i + 1)
		local centerStep = (centers[nextIndex] - centers[i]).Magnitude
		local leftStep = (leftPositions[nextIndex] - leftPositions[i]).Magnitude
		local rightStep = (rightPositions[nextIndex] - rightPositions[i]).Magnitude
		minCenterStep = math.min(minCenterStep, centerStep)
		minLeftStep = math.min(minLeftStep, leftStep)
		minRightStep = math.min(minRightStep, rightStep)
		if centerStep > 1 and math.min(leftStep, rightStep) < 0.5 then
			collapsedSpans += 1
		end
		if roadWidth > centerStep * 2 then
			tightSpans += 1
		end
	end

	if (collapsedSpans > 0 or pinchedRows > 0 or rightFlips > 0 or roadWidth >= 96) and Config.authoredRoadDebugLogging == true then
		roadDebugLog(
			"road loft diagnostics %s: width=%.1f samples=%d rows=%d closed=%s spans=%d tightSpans=%d collapsedSpans=%d pinchedRows=%d rightFlips=%d centerLen=%.1f leftLen=%.1f rightLen=%.1f minLoftWidth=%.2f maxLoftWidth=%.2f minCenterStep=%.2f minLeftStep=%.2f minRightStep=%.2f widthSegments=%d",
			tostring(debugLabel or "road"),
			roadWidth,
			#samples,
			rowCount,
			tostring(closedLoop),
			spanCount,
			tightSpans,
			collapsedSpans,
			pinchedRows,
			rightFlips,
			centerLength,
			leftLength,
			rightLength,
			minLoftWidth == math.huge and 0 or minLoftWidth,
			maxLoftWidth,
			minCenterStep == math.huge and 0 or minCenterStep,
			minLeftStep == math.huge and 0 or minLeftStep,
			minRightStep == math.huge and 0 or minRightStep,
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

local function addIntersectionDiskToMesh(state, junction)
	local center = junction.center + Vector3.new(0, ROAD_MESH_THICKNESS * 0.5, 0)
	local centerVertex = addMeshVertex(state, center)
	local ring = {}

	for i = 1, INTERSECTION_RING_SEGMENTS do
		local theta = ((i - 1) / INTERSECTION_RING_SEGMENTS) * math.pi * 2
		local pos = center + Vector3.new(math.cos(theta) * junction.radius, 0, math.sin(theta) * junction.radius)
		ring[i] = addMeshVertex(state, pos)
	end

	for i = 1, INTERSECTION_RING_SEGMENTS do
		local nextIndex = (i % INTERSECTION_RING_SEGMENTS) + 1
		addMeshTriangle(state, centerVertex, ring[nextIndex], ring[i])
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

local function addIntersectionCollisionDiskToMesh(state, junction)
	local topCenter = junction.center + Vector3.new(0, ROAD_MESH_THICKNESS * 0.5, 0)
	local bottomCenter = junction.center + Vector3.new(0, -ROAD_MESH_THICKNESS * 0.5, 0)
	local topCenterVertex = addMeshVertex(state, topCenter)
	local bottomCenterVertex = addMeshVertex(state, bottomCenter)
	local topRing = {}
	local bottomRing = {}

	for i = 1, INTERSECTION_RING_SEGMENTS do
		local theta = ((i - 1) / INTERSECTION_RING_SEGMENTS) * math.pi * 2
		local radial = Vector3.new(math.cos(theta) * junction.radius, 0, math.sin(theta) * junction.radius)
		topRing[i] = addMeshVertex(state, topCenter + radial)
		bottomRing[i] = addMeshVertex(state, bottomCenter + radial)
	end

	for i = 1, INTERSECTION_RING_SEGMENTS do
		local nextIndex = (i % INTERSECTION_RING_SEGMENTS) + 1
		addMeshTriangle(state, topCenterVertex, topRing[nextIndex], topRing[i])
		addMeshTriangle(state, bottomCenterVertex, bottomRing[i], bottomRing[nextIndex])
		addMeshTriangle(state, topRing[i], bottomRing[nextIndex], bottomRing[i])
		addMeshTriangle(state, topRing[i], topRing[nextIndex], bottomRing[nextIndex])
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
		addIntersectionDiskToMesh(state, junction)
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

	local rawJunctions = collectEndpointJunctions(chains)
	local crossJunctions = collectCrossIntersections(chains)
	for _, junction in ipairs(crossJunctions) do
		table.insert(rawJunctions, junction)
	end

	local junctions = mergeJunctions(rawJunctions)
	applyJunctionsToChains(chains, junctions)
	local components = buildRoadComponents(chains, junctions)
	local spanCount = 0
	for _, chain in ipairs(chains) do
		spanCount += math.max(#chain.samples - 1, 0)
	end
	roadDebugLog(
		"processed network: chains=%d rawJunctions=%d mergedJunctions=%d components=%d spans=%d",
		#chains,
		#rawJunctions,
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
			splineData:SetAttribute("ClosedCurve", false)
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
			local junctionData = Instance.new("Vector3Value")
			junctionData.Name = string.format("J%04d", junctionCount)
			junctionData.Value = junction.center
			junctionData:SetAttribute("Radius", junction.radius)
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

			addIntersectionCollisionDiskToMesh(state, junction)
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
			local spawnPosition = points[1].Position + Vector3.new(0, Config.carRideHeight, 0)
			local spawnYaw = 0

			if #points >= 2 then
				local delta = points[2].Position - points[1].Position
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
			createVisualCap(visualModel, point.Position, capIndex, width)
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
			trackPart(driveSurfaces, createCollisionCap(collisionModel, point.Position, capIndex, width, visible))
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
