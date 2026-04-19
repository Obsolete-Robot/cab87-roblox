-- Cab87 Studio plugin: persistent spline road editor panel.
-- Install to:
--   %LOCALAPPDATA%\Roblox\Plugins\Cab87RoadCurveTools.plugin.lua

local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local ROOT_NAME = "Cab87RoadEditor"
local SPLINES_NAME = "Splines"
local POINTS_NAME = "RoadPoints"
local MESH_NAME = "RoadMesh"
local NETWORK_NAME = "RoadNetwork"
local ACTIVE_SPLINE_ATTR = "ActiveSpline"
local ROAD_WIDTH_ATTR = "RoadWidth"

local ROAD_WIDTH = 28
local ROAD_MIN_WIDTH = 8
local ROAD_MAX_WIDTH = 96
local ROAD_WIDTH_STEP = 4
local ROAD_THICKNESS = 1.2
local SAMPLE_STEP_STUDS = 8
local ROAD_OVERLAP = 1.0
local POINT_SNAP_OFFSET = 0.35
local ENDPOINT_WELD_DISTANCE = 22
local INTERSECTION_RADIUS_SCALE = 0.58
local INTERSECTION_BLEND_SCALE = 0.95
local INTERSECTION_MERGE_SCALE = 0.45
local INTERSECTION_RING_SEGMENTS = 28
local INTERSECTION_HEIGHT_TOLERANCE_MIN = ROAD_THICKNESS * 2
local INTERSECTION_HEIGHT_TOLERANCE_MAX = ROAD_THICKNESS * 4
local INTERSECTION_HEIGHT_TOLERANCE_WIDTH_SCALE = 0.18
local WIRE_NAME = "WireframeDisplay"
local WIRE_THICKNESS = 0.16
local WIRE_OFFSET_Y = 0.08
local WIRE_MAX_EDGES = 6000

local AUTO_REBUILD_DELAY = 0.12
local autoRebuildEnabled = false
local autoRebuildScheduled = false
local wireframeEnabled = plugin:GetSetting("cab87_road_wireframe") == true
local lastWireframeEdges = {}

local function sanitizeRoadWidth(value)
	local width = tonumber(value)
	if not width then
		return ROAD_WIDTH
	end
	return math.clamp(width, ROAD_MIN_WIDTH, ROAD_MAX_WIDTH)
end

local function getSplineRoadWidth(spline)
	if not spline then
		return ROAD_WIDTH
	end

	local width = sanitizeRoadWidth(spline:GetAttribute(ROAD_WIDTH_ATTR))
	if spline:GetAttribute(ROAD_WIDTH_ATTR) ~= width then
		spline:SetAttribute(ROAD_WIDTH_ATTR, width)
	end
	return width
end

local function getOrCreateRoot()
	local root = Workspace:FindFirstChild(ROOT_NAME)
	if root and root:IsA("Model") then
		return root
	end
	root = Instance.new("Model")
	root.Name = ROOT_NAME
	root.Parent = Workspace
	return root
end

local function getOrCreateSplinesFolder()
	local root = getOrCreateRoot()
	local folder = root:FindFirstChild(SPLINES_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = SPLINES_NAME
	folder.Parent = root
	return folder
end

local function getSplineFromControlPoint(inst)
	if not inst or not inst:IsA("BasePart") then
		return nil
	end
	local pointsFolder = inst.Parent
	if not pointsFolder or pointsFolder.Name ~= POINTS_NAME then
		return nil
	end
	local spline = pointsFolder.Parent
	if spline and spline:IsA("Model") and spline.Parent == getOrCreateSplinesFolder() then
		return spline
	end
	return nil
end

local function ensureSplineChildren(spline)
	local points = spline:FindFirstChild(POINTS_NAME)
	if not (points and points:IsA("Folder")) then
		points = Instance.new("Folder")
		points.Name = POINTS_NAME
		points.Parent = spline
	end

	local road = spline:FindFirstChild(MESH_NAME)
	if not (road and road:IsA("Model")) then
		road = Instance.new("Model")
		road.Name = MESH_NAME
		road.Parent = spline
	end

	if spline:GetAttribute("ClosedCurve") == nil then
		spline:SetAttribute("ClosedCurve", false)
	end
	getSplineRoadWidth(spline)

	return points, road
end

local function sortedSplines()
	local splines = {}
	for _, child in ipairs(getOrCreateSplinesFolder():GetChildren()) do
		if child:IsA("Model") then
			table.insert(splines, child)
		end
	end
	table.sort(splines, function(a, b)
		return a.Name < b.Name
	end)
	return splines
end

local function nextSplineName()
	local maxN = 0
	for _, spline in ipairs(sortedSplines()) do
		local n = tonumber(string.match(spline.Name, "^Spline(%d+)$"))
		if n and n > maxN then
			maxN = n
		end
	end
	return string.format("Spline%03d", maxN + 1)
end

local function createSpline(name)
	local spline = Instance.new("Model")
	spline.Name = name or nextSplineName()
	spline.Parent = getOrCreateSplinesFolder()
	ensureSplineChildren(spline)
	return spline
end

local function getActiveSpline()
	local root = getOrCreateRoot()
	local splinesFolder = getOrCreateSplinesFolder()

	-- One-time migration from older single-spline layout.
	if #splinesFolder:GetChildren() == 0 then
		local legacyPoints = root:FindFirstChild(POINTS_NAME)
		local legacyRoad = root:FindFirstChild(MESH_NAME)
		if (legacyPoints and legacyPoints:IsA("Folder")) or (legacyRoad and legacyRoad:IsA("Model")) then
			local migrated = createSpline("Spline001")
			if legacyPoints and legacyPoints:IsA("Folder") then
				legacyPoints.Parent = migrated
			end
			if legacyRoad and legacyRoad:IsA("Model") then
				legacyRoad.Parent = migrated
			end
			ensureSplineChildren(migrated)
			root:SetAttribute(ACTIVE_SPLINE_ATTR, migrated.Name)
		end
	end

	local activeName = root:GetAttribute(ACTIVE_SPLINE_ATTR)
	if activeName then
		local s = splinesFolder:FindFirstChild(activeName)
		if s and s:IsA("Model") then
			ensureSplineChildren(s)
			return s
		end
	end

	local existing = sortedSplines()
	local spline = existing[1] or createSpline()
	root:SetAttribute(ACTIVE_SPLINE_ATTR, spline.Name)
	return spline
end

local function setActiveSpline(spline)
	if not (spline and spline:IsA("Model")) then
		return nil
	end
	if spline.Parent ~= getOrCreateSplinesFolder() then
		return nil
	end
	getOrCreateRoot():SetAttribute(ACTIVE_SPLINE_ATTR, spline.Name)
	ensureSplineChildren(spline)
	return spline
end

local function createAndActivateSpline()
	local spline = createSpline()
	setActiveSpline(spline)
	return spline
end

local function cycleActiveSpline(direction)
	local splines = sortedSplines()
	if #splines == 0 then
		local created = createAndActivateSpline()
		return created
	end

	local active = getActiveSpline()
	local idx = 1
	for i, s in ipairs(splines) do
		if s == active then
			idx = i
			break
		end
	end

	local nextIdx = ((idx - 1 + direction) % #splines) + 1
	setActiveSpline(splines[nextIdx])
	return splines[nextIdx]
end

local function getOrCreatePointsFolder()
	local points = ensureSplineChildren(getActiveSpline())
	return points
end

local function getOrCreateRoadModel()
	local _, road = ensureSplineChildren(getActiveSpline())
	return road
end

local function getOrCreateNetworkModel()
	local root = getOrCreateRoot()
	local model = root:FindFirstChild(NETWORK_NAME)
	if model and model:IsA("Model") then
		return model
	end
	model = Instance.new("Model")
	model.Name = NETWORK_NAME
	model.Parent = root
	return model
end

local function clearFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

local function sortedPoints()
	local folder = getOrCreatePointsFolder()
	local points = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)
	return points
end

local function sortedPointsInSpline(spline)
	local pointsFolder = spline:FindFirstChild(POINTS_NAME)
	if not (pointsFolder and pointsFolder:IsA("Folder")) then
		return {}
	end
	local points = {}
	for _, child in ipairs(pointsFolder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)
	return points
end

local function pointName(index)
	return string.format("P%03d", index)
end

local function renumberPoints()
	for i, p in ipairs(sortedPoints()) do
		p.Name = pointName(i)
	end
end

local function isControlPoint(inst)
	return getSplineFromControlPoint(inst) ~= nil
end

local function raycastFromCamera(maxDistance)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * (maxDistance or 4000)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { getOrCreateRoot() }
	params.IgnoreWater = false

	local hit = Workspace:Raycast(origin, direction, params)
	if hit then
		return hit.Position
	end

	return origin + camera.CFrame.LookVector * 120
end

local function nearestPointToCameraRay()
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local origin = camera.CFrame.Position
	local dir = camera.CFrame.LookVector

	local best, bestDist = nil, math.huge
	for _, p in ipairs(sortedPoints()) do
		local toPoint = p.Position - origin
		local along = toPoint:Dot(dir)
		if along > 0 then
			local perp = (toPoint - dir * along).Magnitude
			if perp < bestDist then
				best = p
				bestDist = perp
			end
		end
	end
	return best
end

local function addControlPoint(pos)
	local folder = getOrCreatePointsFolder()
	local idx = #folder:GetChildren() + 1
	local p = Instance.new("Part")
	p.Name = pointName(idx)
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(4.5, 4.5, 4.5)
	p.Anchored = true
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 180, 75)
	p.Position = pos
	p.Locked = false
	p.Parent = folder
	return p
end

local function isClosedSpline(spline)
	return spline and spline:GetAttribute("ClosedCurve") == true
end

local function isClosedCurve()
	local spline = getActiveSpline()
	return isClosedSpline(spline)
end

local function setClosedCurve(value)
	local spline = getActiveSpline()
	spline:SetAttribute("ClosedCurve", value and true or false)
end

local function getActiveRoadWidth()
	return getSplineRoadWidth(getActiveSpline())
end

local function setActiveRoadWidth(value)
	local spline = getActiveSpline()
	local width = sanitizeRoadWidth(value)
	spline:SetAttribute(ROAD_WIDTH_ATTR, width)
	return width
end

local function formatRoadWidth(width)
	width = sanitizeRoadWidth(width)
	local rounded = math.floor(width + 0.5)
	if math.abs(width - rounded) < 0.01 then
		return tostring(rounded)
	end
	return string.format("%.1f", width)
end

local function catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

local function sampleSpline(pointParts, closedCurve)
	local positions = {}
	for _, p in ipairs(pointParts) do
		table.insert(positions, p.Position)
	end

	if #positions < 2 then
		return positions
	end

	if closedCurve and #positions < 3 then
		closedCurve = false
	end

	local samples = {}
	if closedCurve then
		local count = #positions
		for i = 1, count do
			local p0 = positions[((i - 2) % count) + 1]
			local p1 = positions[i]
			local p2 = positions[(i % count) + 1]
			local p3 = positions[((i + 1) % count) + 1]

			local segmentLen = (p2 - p1).Magnitude
			local subdivisions = math.max(2, math.floor(segmentLen / SAMPLE_STEP_STUDS))
			for s = 0, subdivisions - 1 do
				local t = s / subdivisions
				table.insert(samples, catmullRom(p0, p1, p2, p3, t))
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
			local subdivisions = math.max(2, math.floor(segmentLen / SAMPLE_STEP_STUDS))
			for s = 0, subdivisions - 1 do
				local t = s / subdivisions
				table.insert(samples, catmullRom(p0, p1, p2, p3, t))
			end
		end
		table.insert(samples, positions[#positions])
	end
	return samples
end

local function buildPrimitiveRoad(samples, targetModel, namePrefix, roadWidth)
	roadWidth = sanitizeRoadWidth(roadWidth)
	local segments = 0
	for i = 1, #samples - 1 do
		local a = samples[i]
		local b = samples[i + 1]
		local delta = b - a
		local len = delta.Magnitude
		if len > 0.05 then
			local mid = (a + b) * 0.5 + Vector3.new(0, ROAD_THICKNESS * 0.5, 0)
			local part = Instance.new("Part")
			part.Name = string.format("%s_%04d", namePrefix or "Road", i)
			part.Anchored = true
			part.Material = Enum.Material.Asphalt
			part.Color = Color3.fromRGB(28, 28, 32)
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Size = Vector3.new(roadWidth, ROAD_THICKNESS, len + ROAD_OVERLAP)
			part.CFrame = CFrame.lookAt(mid, b)
			part.Locked = true
			part.Parent = targetModel
			segments += 1
		end
	end
	return segments
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
	return (a - b).Magnitude <= heightConnectTolerance(widthA, widthB)
end

local function lerpNumber(a, b, alpha)
	return a + (b - a) * alpha
end

local function getOrCreateWireframeFolder(network)
	local folder = network:FindFirstChild(WIRE_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = WIRE_NAME
	folder.Parent = network
	return folder
end

local function clearWireframe()
	local network = getOrCreateNetworkModel()
	local folder = network:FindFirstChild(WIRE_NAME)
	if folder then
		folder:Destroy()
	end
end

local function createWireSegment(parent, a, b, index)
	local startPos = a + Vector3.new(0, WIRE_OFFSET_Y, 0)
	local endPos = b + Vector3.new(0, WIRE_OFFSET_Y, 0)
	local delta = endPos - startPos
	local len = delta.Magnitude
	if len < 0.05 then
		return false
	end

	local part = Instance.new("Part")
	part.Name = string.format("Wire_%04d", index)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(0, 220, 255)
	part.Transparency = 0.12
	part.Size = Vector3.new(WIRE_THICKNESS, WIRE_THICKNESS, len)
	part.CFrame = CFrame.lookAt((startPos + endPos) * 0.5, endPos)
	part.Locked = true
	part.Parent = parent
	return true
end

local function refreshWireframe()
	clearWireframe()
	if not wireframeEnabled then
		return 0
	end

	local network = getOrCreateNetworkModel()
	local folder = getOrCreateWireframeFolder(network)
	local drawn = 0
	local maxEdges = math.min(#lastWireframeEdges, WIRE_MAX_EDGES)
	for i = 1, maxEdges do
		local edge = lastWireframeEdges[i]
		if createWireSegment(folder, edge[1], edge[2], i) then
			drawn += 1
		end
	end
	return drawn
end

local function newMeshState()
	local editableMesh = AssetService:CreateEditableMesh()
	if not editableMesh then
		return nil, "EditableMesh creation failed"
	end

	return {
		mesh = editableMesh,
		vertexPositions = {},
		edgeKeys = {},
		edges = {},
		faces = 0,
	}
end

local function addMeshVertex(state, pos)
	local vertex = state.mesh:AddVertex(pos)
	state.vertexPositions[vertex] = pos
	return vertex
end

local function recordMeshEdge(state, a, b)
	local aKey = tostring(a)
	local bKey = tostring(b)
	if bKey < aKey then
		aKey, bKey = bKey, aKey
	end
	local key = aKey .. "|" .. bKey
	if state.edgeKeys[key] then
		return
	end

	local aPos = state.vertexPositions[a]
	local bPos = state.vertexPositions[b]
	if not aPos or not bPos then
		return
	end

	state.edgeKeys[key] = true
	table.insert(state.edges, { aPos, bPos })
end

local function addMeshTriangle(state, a, b, c)
	state.mesh:AddTriangle(a, b, c)
	recordMeshEdge(state, a, b)
	recordMeshEdge(state, b, c)
	recordMeshEdge(state, c, a)
	state.faces += 1
end

local function sampleLoopIsClosed(samples)
	if #samples < 3 then
		return false
	end
	return distanceXZ(samples[1], samples[#samples]) <= 0.05 and math.abs(samples[1].Y - samples[#samples].Y) <= 0.05
end

local function tangentForSample(samples, index, closedLoop)
	local count = #samples
	local prev
	local nextp
	if closedLoop then
		if index == 1 then
			prev = samples[count - 1]
			nextp = samples[2]
		elseif index == count then
			prev = samples[count - 1]
			nextp = samples[2]
		else
			prev = samples[index - 1]
			nextp = samples[index + 1]
		end
	else
		prev = samples[math.max(1, index - 1)]
		nextp = samples[math.min(count, index + 1)]
	end

	local tangent = nextp - prev
	if tangent.Magnitude < 1e-4 then
		return Vector3.new(0, 0, 1)
	end
	return tangent.Unit
end

local function roadRightFromTangent(tangent)
	local right = tangent:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		return Vector3.xAxis
	end
	return right.Unit
end

local function addRoadRibbonToMesh(state, samples, roadWidth)
	if #samples < 2 then
		return 0
	end

	roadWidth = sanitizeRoadWidth(roadWidth)
	local closedLoop = sampleLoopIsClosed(samples)
	local leftVerts = {}
	local rightVerts = {}
	local count = #samples

	for i = 1, count do
		if closedLoop and i == count then
			leftVerts[i] = leftVerts[1]
			rightVerts[i] = rightVerts[1]
		else
			local tangent = tangentForSample(samples, i, closedLoop)
			local right = roadRightFromTangent(tangent)
			local center = samples[i] + Vector3.new(0, ROAD_THICKNESS * 0.5, 0)
			local leftPos = center - right * (roadWidth * 0.5)
			local rightPos = center + right * (roadWidth * 0.5)

			leftVerts[i] = addMeshVertex(state, leftPos)
			rightVerts[i] = addMeshVertex(state, rightPos)
		end
	end

	local spans = 0
	for i = 1, count - 1 do
		if (samples[i + 1] - samples[i]).Magnitude > 0.05 then
			local l1 = leftVerts[i]
			local r1 = rightVerts[i]
			local l2 = leftVerts[i + 1]
			local r2 = rightVerts[i + 1]

			addMeshTriangle(state, l1, l2, r2)
			addMeshTriangle(state, l1, r2, r1)
			spans += 1
		end
	end

	return spans
end

local function addIntersectionDiskToMesh(state, junction)
	local center = junction.center + Vector3.new(0, ROAD_THICKNESS * 0.5, 0)
	local centerVertex = addMeshVertex(state, center)
	local ring = {}

	for i = 1, INTERSECTION_RING_SEGMENTS do
		local theta = ((i - 1) / INTERSECTION_RING_SEGMENTS) * math.pi * 2
		local pos = center + Vector3.new(math.cos(theta) * junction.radius, 0, math.sin(theta) * junction.radius)
		ring[i] = addMeshVertex(state, pos)
	end

	for i = 1, INTERSECTION_RING_SEGMENTS do
		local nextIndex = (i % INTERSECTION_RING_SEGMENTS) + 1
		addMeshTriangle(state, centerVertex, ring[i], ring[nextIndex])
	end
end

local function createNetworkMeshPart(state, targetModel, meshName)
	if state.faces == 0 then
		return false, "No mesh faces were generated"
	end

	local meshContent = Content.fromObject(state.mesh)
	local okCreate, sourceMeshPartOrErr = pcall(function()
		return AssetService:CreateMeshPartAsync(meshContent)
	end)
	if not okCreate then
		return false, tostring(sourceMeshPartOrErr)
	end

	local sourceMeshPart = sourceMeshPartOrErr
	local meshPart = Instance.new("MeshPart")
	meshPart.Name = meshName or "RoadNetworkMesh"
	meshPart.Size = sourceMeshPart.Size
	meshPart.CFrame = sourceMeshPart.CFrame
	pcall(function()
		meshPart.PivotOffset = sourceMeshPart.PivotOffset
	end)
	meshPart.Anchored = true
	meshPart.Material = Enum.Material.Asphalt
	meshPart.Color = Color3.fromRGB(28, 28, 32)
	meshPart.DoubleSided = true
	meshPart.Locked = true
	meshPart.Parent = targetModel
	local okApply, applyErr = pcall(function()
		meshPart:ApplyMesh(sourceMeshPart)
	end)
	sourceMeshPart:Destroy()
	if not okApply then
		meshPart:Destroy()
		return false, tostring(applyErr)
	end

	pcall(function()
		meshPart.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
	end)
	meshPart:SetAttribute("GeneratedBy", "Cab87RoadEditor")
	meshPart:SetAttribute("TriangleCount", state.faces)

	return true, meshPart
end

local function collectSplineBuildData()
	local chains = {}
	for _, spline in ipairs(sortedSplines()) do
		local points = sortedPointsInSpline(spline)
		if #points >= 2 then
			local closed = isClosedSpline(spline)
			local samples = sampleSpline(points, closed)
			table.insert(chains, {
				spline = spline,
				points = points,
				samples = samples,
				closed = closed,
				width = getSplineRoadWidth(spline),
			})
		end
	end
	return chains
end

local function maxRoadWidthForMembers(members)
	local width = nil
	for _, member in ipairs(members) do
		if member.chain then
			width = math.max(width or 0, sanitizeRoadWidth(member.chain.width))
		end
	end
	return width or ROAD_WIDTH
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
		local endpointWidth = sanitizeRoadWidth(endpoint.chain.width)
		for _, cluster in ipairs(clusters) do
			local weldDistance = math.max(ENDPOINT_WELD_DISTANCE, math.max(cluster.width, endpointWidth) * 0.8)
			if distanceXZ(cluster.center, endpoint.pos) <= weldDistance and positionsConnectIn3D(cluster.center, endpoint.pos, cluster.width, endpointWidth) then
				table.insert(cluster.members, endpoint)
				cluster.width = math.max(cluster.width, endpointWidth)
				local sum = Vector3.zero
				for _, m in ipairs(cluster.members) do
					sum += m.pos
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
					local hit2, aT, bT = segmentIntersection2D(a1, a2, b1, b2)
					if hit2 then
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
				if not junction.chains or not junction.chains[chain] then
					continue
				end
				local d = distanceXZ(sample, junction.center)
				local blendRadius = junction.blendRadius or (junction.radius + 0.05)
				if d <= blendRadius and d < bestDistance then
					bestDistance = d
					bestJunction = junction
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
					lerpNumber(sample.Y, bestJunction.center.Y, alpha),
					sample.Z
				)
			end
		end

		if chain.closed and #chain.samples > 2 then
			chain.samples[#chain.samples] = chain.samples[1]
		end
	end
end

local function buildUnifiedRoadMesh(chains, junctions, targetModel)
	local state, err = newMeshState()
	if not state then
		return false, err
	end

	local spans = 0
	for _, chain in ipairs(chains) do
		spans += addRoadRibbonToMesh(state, chain.samples, chain.width)
	end

	for _, junction in ipairs(junctions) do
		addIntersectionDiskToMesh(state, junction)
	end

	local ok, meshPartOrErr = createNetworkMeshPart(state, targetModel, "RoadNetworkMesh")
	if not ok then
		return false, meshPartOrErr
	end

	return true, {
		spans = spans,
		intersections = #junctions,
		edges = state.edges,
		meshPart = meshPartOrErr,
	}
end

local function clearPerSplineRoadMeshes()
	for _, spline in ipairs(sortedSplines()) do
		local road = spline:FindFirstChild(MESH_NAME)
		if road and road:IsA("Model") then
			clearFolder(road)
		end
	end
end

local function rebuildRoadMeshPreferred()
	local chains = collectSplineBuildData()
	if #chains == 0 then
		warn("[cab87 roads] Need at least one spline with 2+ points")
		return 0, "Need at least one spline with 2+ points"
	end

	local network = getOrCreateNetworkModel()
	clearFolder(network)
	clearPerSplineRoadMeshes()

	local rawJunctions = collectEndpointJunctions(chains)
	local crossJunctions = collectCrossIntersections(chains)
	for _, junction in ipairs(crossJunctions) do
		table.insert(rawJunctions, junction)
	end

	local junctions = mergeJunctions(rawJunctions)
	applyJunctionsToChains(chains, junctions)

	local okMesh, meshInfo = buildUnifiedRoadMesh(chains, junctions, network)
	local totalSpans = 0
	local intersectionCount = #junctions
	local usedFallback = false

	if okMesh then
		totalSpans = meshInfo.spans
		lastWireframeEdges = meshInfo.edges
	else
		usedFallback = true
		lastWireframeEdges = {}
		warn("[cab87 roads] Unified mesh build failed: " .. tostring(meshInfo))
		for _, chain in ipairs(chains) do
			local meshName = string.format("Road_%s", chain.spline.Name)
			totalSpans += buildPrimitiveRoad(chain.samples, network, meshName, chain.width)
		end
	end

	local wireCount = refreshWireframe()
	local wireNote = wireframeEnabled and string.format(", %d wire edges", wireCount) or ""
	local note = string.format("Network rebuilt: %d splines, %d spans, %d intersections%s%s", #chains, totalSpans, intersectionCount, wireNote, usedFallback and " (primitive fallback used)" or "")
	print("[cab87 roads] " .. note)
	return totalSpans, note
end

local function snapPointsToTerrain()
	local points = sortedPoints()
	if #points == 0 then
		warn("[cab87 roads] No control points to snap")
		return 0
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { getOrCreateRoot() }
	params.IgnoreWater = false

	local changed = 0
	for _, p in ipairs(points) do
		local origin = p.Position + Vector3.new(0, 2000, 0)
		local ray = Vector3.new(0, -5000, 0)
		local hit = Workspace:Raycast(origin, ray, params)
		if hit then
			p.Position = Vector3.new(p.Position.X, hit.Position.Y + POINT_SNAP_OFFSET, p.Position.Z)
			changed += 1
		end
	end
	return changed
end

local function removeLastPoint()
	local points = sortedPoints()
	if #points == 0 then
		return false
	end
	points[#points]:Destroy()
	renumberPoints()
	return true
end

local function removeSelectedPoint()
	local selection = Selection:Get()
	if #selection == 0 then
		return false
	end
	local target = selection[1]
	local spline = getSplineFromControlPoint(target)
	if not spline then
		return false
	end
	setActiveSpline(spline)
	target:Destroy()
	renumberPoints()
	return true
end

local function selectedPointWithIndex()
	local selection = Selection:Get()
	if #selection == 0 then
		return nil, nil, sortedPoints()
	end
	local target = selection[1]
	local spline = getSplineFromControlPoint(target)
	if not spline then
		return nil, nil, sortedPoints()
	end
	setActiveSpline(spline)
	local points = sortedPoints()
	for i, p in ipairs(points) do
		if p == target then
			return p, i, points
		end
	end
	return nil, nil, points
end

local function setSelectedPointY(mode)
	local selected, idx, points = selectedPointWithIndex()
	if not selected then
		return false, "Select a control point first"
	end

	local prev = points[idx - 1]
	local nextp = points[idx + 1]
	local y

	if mode == "prev" then
		if not prev then
			return false, "No previous point"
		end
		y = prev.Position.Y
	elseif mode == "next" then
		if not nextp then
			return false, "No next point"
		end
		y = nextp.Position.Y
	elseif mode == "avg" then
		if prev and nextp then
			y = (prev.Position.Y + nextp.Position.Y) * 0.5
		elseif prev then
			y = prev.Position.Y
		elseif nextp then
			y = nextp.Position.Y
		else
			return false, "Need at least one neighbor point"
		end
	else
		return false, "Unknown Y snap mode"
	end

	selected.Position = Vector3.new(selected.Position.X, y, selected.Position.Z)
	return true, string.format("Set %s Y to %.2f", selected.Name, y)
end

local function countSegments()
	local road = getOrCreateNetworkModel()
	local n = 0
	for _, child in ipairs(road:GetChildren()) do
		if child:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- UI
local toolbar = plugin:CreateToolbar("cab87 roads")
local toggleButton = toolbar:CreateButton("Road Editor", "Toggle road editor panel", "rbxasset://textures/StudioToolbox/PluginToolbar/icon_advanced.png")
toggleButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	true,
	true,
	340,
	680,
	280,
	460
)

local widget = plugin:CreateDockWidgetPluginGui("Cab87RoadCurveEditorWidget", widgetInfo)
widget.Title = "Cab87 Road Editor"
widget.Enabled = true

local root = Instance.new("ScrollingFrame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.CanvasSize = UDim2.fromOffset(0, 0)
root.AutomaticCanvasSize = Enum.AutomaticSize.Y
root.ScrollBarThickness = 6
root.Parent = widget

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = root

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.Padding = UDim.new(0, 6)
list.Parent = root

local function makeButton(text)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 30)
	b.BackgroundColor3 = Color3.fromRGB(42, 42, 48)
	b.TextColor3 = Color3.fromRGB(240, 240, 240)
	b.Font = Enum.Font.GothamSemibold
	b.TextSize = 13
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = root
	return b
end

local function makeControlRow()
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundTransparency = 1
	row.Parent = root

	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.Padding = UDim.new(0, 6)
	rowList.Parent = row

	return row
end

local function makeInlineButton(parent, text, width)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, width, 1, 0)
	b.BackgroundColor3 = Color3.fromRGB(42, 42, 48)
	b.TextColor3 = Color3.fromRGB(240, 240, 240)
	b.Font = Enum.Font.GothamSemibold
	b.TextSize = 13
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	return b
end

local function makeTextBox(parent, placeholder)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -96, 1, 0)
	box.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	box.TextColor3 = Color3.fromRGB(245, 245, 245)
	box.PlaceholderColor3 = Color3.fromRGB(150, 150, 155)
	box.Font = Enum.Font.GothamSemibold
	box.TextSize = 13
	box.Text = ""
	box.PlaceholderText = placeholder or ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.Parent = parent
	return box
end

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Spline track editor"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(255, 220, 120)
title.Parent = root

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, 0, 0, 64)
status.BackgroundTransparency = 1
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(200, 200, 205)
status.Parent = root

local function updateStatus(extra)
	local points = #sortedPoints()
	local segments = countSegments()
	local curveMode = isClosedCurve() and "Closed" or "Open"
	local wireMode = wireframeEnabled and "On" or "Off"
	local active = getActiveSpline()
	local width = formatRoadWidth(getSplineRoadWidth(active))
	local splineCount = #sortedSplines()
	local base = string.format("Spline: %s (%d total) | Width: %s | Points: %d | Road parts: %d | Curve: %s | Wire: %s", active.Name, splineCount, width, points, segments, curveMode, wireMode)
	if extra and #extra > 0 then
		status.Text = base .. "\n" .. extra
	else
		status.Text = base .. "\nTip: Select Nearest + Y buttons makes fast flatten/slope edits."
	end
end

local btnNew = makeButton("New Spline")
local btnPrevSpline = makeButton("Prev Spline")
local btnNextSpline = makeButton("Next Spline")
local btnCloseCurve = makeButton("Curve Mode: Open")
local widthRow = makeControlRow()
local btnWidthDown = makeInlineButton(widthRow, "-4", 42)
local widthInput = makeTextBox(widthRow, "Road width")
local btnWidthUp = makeInlineButton(widthRow, "+4", 42)
local btnAddCamera = makeButton("Add Point (Camera Hit)")
local btnAddSelected = makeButton("Add Point (From Selection)")
local btnSelectNearest = makeButton("Select Nearest Point (Camera)")
local btnYPrev = makeButton("Set Selected Y = Prev")
local btnYNext = makeButton("Set Selected Y = Next")
local btnYAvg = makeButton("Set Selected Y = Avg")
local btnRemoveSel = makeButton("Remove Selected Point")
local btnRemoveLast = makeButton("Remove Last Point")
local btnSnap = makeButton("Snap Points To Terrain")
local btnRebuild = makeButton("Rebuild Road (Mesh)")
local btnWireframe = makeButton("Wireframe Mesh: Off")
local btnClear = makeButton("Clear Road")
local btnAutoRebuild = makeButton("Auto Rebuild: Off")

local function refreshCurveModeButton()
	btnCloseCurve.Text = isClosedCurve() and "Curve Mode: Closed" or "Curve Mode: Open"
end

local function refreshAutoRebuildButton()
	btnAutoRebuild.Text = autoRebuildEnabled and "Auto Rebuild: On" or "Auto Rebuild: Off"
end

local function refreshWireframeButton()
	btnWireframe.Text = wireframeEnabled and "Wireframe Mesh: On" or "Wireframe Mesh: Off"
end

local function refreshRoadWidthInput()
	widthInput.Text = formatRoadWidth(getActiveRoadWidth())
end

local scheduleAutoRebuild

local function updateActiveRoadWidth(value, reason)
	local width = tonumber(value)
	if not width then
		refreshRoadWidthInput()
		updateStatus("Enter a numeric road width")
		return
	end

	width = sanitizeRoadWidth(width)
	if math.abs(width - getActiveRoadWidth()) < 0.01 then
		refreshRoadWidthInput()
		return
	end

	ChangeHistoryService:SetWaypoint("cab87 roads before width change")
	width = setActiveRoadWidth(width)
	ChangeHistoryService:SetWaypoint("cab87 roads after width change")
	refreshRoadWidthInput()
	scheduleAutoRebuild(reason or "road-width-changed")
	updateStatus(string.format("Set %s width to %s studs", getActiveSpline().Name, formatRoadWidth(width)))
end

local pointWatchers = {}

local function disconnectPointWatcher(point)
	local conns = pointWatchers[point]
	if not conns then
		return
	end
	for _, conn in ipairs(conns) do
		conn:Disconnect()
	end
	pointWatchers[point] = nil
end

function scheduleAutoRebuild(reason)
	if not autoRebuildEnabled then
		return
	end
	if autoRebuildScheduled then
		return
	end
	autoRebuildScheduled = true
	task.delay(AUTO_REBUILD_DELAY, function()
		autoRebuildScheduled = false
		if not autoRebuildEnabled then
			return
		end
		local segs, note = rebuildRoadMeshPreferred()
		updateStatus(string.format("Auto rebuilt (%d spans). %s", segs, note or ""))
		print(string.format("[cab87 roads] Auto rebuild (%s): %d spans", tostring(reason), segs))
	end)
end

local function refreshPointWatchers()
	local alive = {}
	for _, spline in ipairs(sortedSplines()) do
		for _, p in ipairs(sortedPointsInSpline(spline)) do
			alive[p] = true
			if not pointWatchers[p] then
				pointWatchers[p] = {
					p:GetPropertyChangedSignal("Position"):Connect(function()
						scheduleAutoRebuild("point-moved")
					end),
					p.AncestryChanged:Connect(function(_, parent)
						if parent == nil then
							disconnectPointWatcher(p)
						end
					end),
				}
			end
		end
	end

	for p in pairs(pointWatchers) do
		if not alive[p] then
			disconnectPointWatcher(p)
		end
	end
end

btnNew.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before new spline")
	local spline = createAndActivateSpline()
	ChangeHistoryService:SetWaypoint("cab87 roads after new spline")
	refreshCurveModeButton()
	refreshRoadWidthInput()
	refreshPointWatchers()
	updateStatus("Started " .. spline.Name)
end)

btnPrevSpline.MouseButton1Click:Connect(function()
	local spline = cycleActiveSpline(-1)
	refreshCurveModeButton()
	refreshRoadWidthInput()
	refreshPointWatchers()
	updateStatus("Active spline: " .. spline.Name)
end)

btnNextSpline.MouseButton1Click:Connect(function()
	local spline = cycleActiveSpline(1)
	refreshCurveModeButton()
	refreshRoadWidthInput()
	refreshPointWatchers()
	updateStatus("Active spline: " .. spline.Name)
end)

btnCloseCurve.MouseButton1Click:Connect(function()
	setClosedCurve(not isClosedCurve())
	refreshCurveModeButton()
	scheduleAutoRebuild("curve-mode-toggled")
	updateStatus(isClosedCurve() and "Curve set to closed loop" or "Curve set to open")
end)

btnWidthDown.MouseButton1Click:Connect(function()
	updateActiveRoadWidth(getActiveRoadWidth() - ROAD_WIDTH_STEP, "road-width-changed")
end)

btnWidthUp.MouseButton1Click:Connect(function()
	updateActiveRoadWidth(getActiveRoadWidth() + ROAD_WIDTH_STEP, "road-width-changed")
end)

widthInput.FocusLost:Connect(function()
	updateActiveRoadWidth(widthInput.Text, "road-width-changed")
end)

btnAddCamera.MouseButton1Click:Connect(function()
	local pos = raycastFromCamera(4000)
	if not pos then
		updateStatus("Could not raycast from camera")
		return
	end
	ChangeHistoryService:SetWaypoint("cab87 roads before add point camera")
	local p = addControlPoint(pos)
	ChangeHistoryService:SetWaypoint("cab87 roads after add point camera")
	Selection:Set({ p })
	refreshPointWatchers()
	scheduleAutoRebuild("point-added")
	updateStatus("Added " .. p.Name)
end)

btnAddSelected.MouseButton1Click:Connect(function()
	local sel = Selection:Get()
	if #sel == 0 or not sel[1]:IsA("BasePart") then
		updateStatus("Select a part first to add a point at its position")
		return
	end
	ChangeHistoryService:SetWaypoint("cab87 roads before add point selection")
	local p = addControlPoint(sel[1].Position)
	ChangeHistoryService:SetWaypoint("cab87 roads after add point selection")
	Selection:Set({ p })
	refreshPointWatchers()
	scheduleAutoRebuild("point-added")
	updateStatus("Added " .. p.Name .. " from selection")
end)

btnSelectNearest.MouseButton1Click:Connect(function()
	local p = nearestPointToCameraRay()
	if not p then
		updateStatus("No points found in front of camera")
		return
	end
	Selection:Set({ p })
	updateStatus("Selected " .. p.Name)
end)

btnYPrev.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before y=prev")
	local ok, msg = setSelectedPointY("prev")
	ChangeHistoryService:SetWaypoint("cab87 roads after y=prev")
	if ok then
		updateStatus(msg)
	else
		updateStatus(msg)
	end
end)

btnYNext.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before y=next")
	local ok, msg = setSelectedPointY("next")
	ChangeHistoryService:SetWaypoint("cab87 roads after y=next")
	if ok then
		updateStatus(msg)
	else
		updateStatus(msg)
	end
end)

btnYAvg.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before y=avg")
	local ok, msg = setSelectedPointY("avg")
	ChangeHistoryService:SetWaypoint("cab87 roads after y=avg")
	if ok then
		updateStatus(msg)
	else
		updateStatus(msg)
	end
end)

btnRemoveSel.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before remove selected")
	local ok = removeSelectedPoint()
	ChangeHistoryService:SetWaypoint("cab87 roads after remove selected")
	if ok then
		refreshPointWatchers()
		scheduleAutoRebuild("point-removed")
		updateStatus("Removed selected point")
	else
		updateStatus("Select a control point to remove")
	end
end)

btnRemoveLast.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before remove last")
	local ok = removeLastPoint()
	ChangeHistoryService:SetWaypoint("cab87 roads after remove last")
	if ok then
		refreshPointWatchers()
		scheduleAutoRebuild("point-removed")
		updateStatus("Removed last point")
	else
		updateStatus("No points to remove")
	end
end)

btnSnap.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before snap")
	local n = snapPointsToTerrain()
	ChangeHistoryService:SetWaypoint("cab87 roads after snap")
	updateStatus(string.format("Snapped %d points", n))
end)

btnRebuild.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before rebuild")
	local segs, note = rebuildRoadMeshPreferred()
	ChangeHistoryService:SetWaypoint("cab87 roads after rebuild")
	updateStatus(string.format("Rebuilt road (%d spans). %s", segs, note or ""))
end)

btnWireframe.MouseButton1Click:Connect(function()
	wireframeEnabled = not wireframeEnabled
	plugin:SetSetting("cab87_road_wireframe", wireframeEnabled)
	refreshWireframeButton()

	local drawn = refreshWireframe()
	if wireframeEnabled then
		if drawn > 0 then
			updateStatus(string.format("Wireframe enabled (%d edges)", drawn))
		else
			updateStatus("Wireframe enabled; rebuild road to draw mesh edges")
		end
	else
		updateStatus("Wireframe disabled")
	end
end)

btnClear.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before clear")
	clearFolder(getOrCreateNetworkModel())
	clearPerSplineRoadMeshes()
	lastWireframeEdges = {}
	ChangeHistoryService:SetWaypoint("cab87 roads after clear")
	updateStatus("Cleared road geometry")
end)

btnAutoRebuild.MouseButton1Click:Connect(function()
	autoRebuildEnabled = not autoRebuildEnabled
	refreshAutoRebuildButton()
	if autoRebuildEnabled then
		scheduleAutoRebuild("toggle-on")
		updateStatus("Auto rebuild enabled")
	else
		updateStatus("Auto rebuild disabled")
	end
end)

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

Selection.SelectionChanged:Connect(function()
	local sel = Selection:Get()
	if #sel > 0 then
		local spline = getSplineFromControlPoint(sel[1])
		if spline then
			setActiveSpline(spline)
			refreshCurveModeButton()
			refreshRoadWidthInput()
			refreshPointWatchers()
		end
	end
	updateStatus(nil)
end)

local splinesFolder = getOrCreateSplinesFolder()
splinesFolder.DescendantAdded:Connect(function(inst)
	if isControlPoint(inst) then
		refreshPointWatchers()
		scheduleAutoRebuild("point-added")
		updateStatus(nil)
	end
end)
splinesFolder.DescendantRemoving:Connect(function(inst)
	if isControlPoint(inst) then
		refreshPointWatchers()
		scheduleAutoRebuild("point-removed")
		updateStatus(nil)
	end
end)

local function restoreMissingRoadMesh()
	if countSegments() > 0 then
		return
	end

	if #collectSplineBuildData() == 0 then
		return
	end

	local segs, note = rebuildRoadMeshPreferred()
	updateStatus(string.format("Restored road mesh (%d spans). %s", segs, note or ""))
end

refreshPointWatchers()
refreshCurveModeButton()
refreshRoadWidthInput()
refreshAutoRebuildButton()
refreshWireframeButton()
updateStatus("Panel stays open while you iterate")
task.defer(restoreMissingRoadMesh)
