local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

if Config.useAuthoredRoadEditorWorld ~= true then
	return
end

local ROAD_EDITOR_ROOT_NAME = "Cab87RoadEditor"
local ROAD_EDITOR_SPLINES_NAME = "Splines"
local ROAD_EDITOR_POINTS_NAME = "RoadPoints"
local ROAD_WIDTH_ATTR = "RoadWidth"
local RUNTIME_WORLD_NAME = "Cab87World"
local RUNTIME_SPLINE_DATA_NAME = "AuthoredRoadSplineData"
local CLIENT_VISUALS_NAME = "AuthoredRoadClientVisuals"

local DEFAULT_AUTHORED_ROAD_WIDTH = 28
local AUTHORED_ROAD_MIN_WIDTH = 8
local AUTHORED_ROAD_MAX_WIDTH = 200
local ROAD_MESH_THICKNESS = 1.2
local ENDPOINT_WELD_DISTANCE = 22
local INTERSECTION_RADIUS_SCALE = 0.58
local INTERSECTION_BLEND_SCALE = 0.95
local INTERSECTION_MERGE_SCALE = 0.45
local INTERSECTION_RING_SEGMENTS = 28
local INTERSECTION_HEIGHT_TOLERANCE_MIN = ROAD_MESH_THICKNESS * 2
local INTERSECTION_HEIGHT_TOLERANCE_MAX = ROAD_MESH_THICKNESS * 4
local INTERSECTION_HEIGHT_TOLERANCE_WIDTH_SCALE = 0.18

local watchedWorld = nil
local watchedConnection = nil
local buildSerial = 0

local function setWorldStatus(world, status, errorMessage, parts, spans)
	if not world then
		return
	end

	world:SetAttribute("AuthoredRoadClientMeshStatus", status)
	world:SetAttribute("AuthoredRoadClientMeshError", errorMessage or "")
	world:SetAttribute("AuthoredRoadClientMeshParts", parts or 0)
	world:SetAttribute("AuthoredRoadClientMeshSpans", spans or 0)
end

local function hideEditorDebugGeometry()
	local editorRoot = Workspace:FindFirstChild(ROAD_EDITOR_ROOT_NAME)
	if not editorRoot then
		return
	end

	for _, item in ipairs(editorRoot:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Transparency = 1
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
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

local function sanitizeRoadWidth(value)
	local width = tonumber(value) or DEFAULT_AUTHORED_ROAD_WIDTH
	return math.clamp(width, AUTHORED_ROAD_MIN_WIDTH, AUTHORED_ROAD_MAX_WIDTH)
end

local function getSplineRoadWidth(spline)
	local configuredDefault = tonumber(Config.authoredRoadCollisionWidth) or DEFAULT_AUTHORED_ROAD_WIDTH
	return sanitizeRoadWidth(tonumber(spline and spline:GetAttribute(ROAD_WIDTH_ATTR)) or configuredDefault)
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

	local points = {}
	for _, child in ipairs(pointsFolder:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Vector3Value") then
			table.insert(points, child)
		end
	end

	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)

	return points
end

local function getPointPosition(point)
	if point:IsA("BasePart") then
		return point.Position
	end
	return point.Value
end

local function catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

local function sampleAuthoredSpline(points, closedCurve)
	local positions = {}
	for _, point in ipairs(points) do
		table.insert(positions, getPointPosition(point))
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
			local samples
			if spline:GetAttribute("SampledRoadChain") == true then
				samples = {}
				for _, point in ipairs(points) do
					table.insert(samples, getPointPosition(point))
				end
			else
				samples = sampleAuthoredSpline(points, closed)
			end
			table.insert(chains, {
				samples = samples,
				closed = closed,
				width = getSplineRoadWidth(spline),
				componentId = tonumber(spline:GetAttribute("ComponentId")) or 1,
			})
		end
	end
	return chains
end

local function collectProcessedJunctions(root)
	local junctionsFolder = root and root:FindFirstChild("Junctions")
	if not (junctionsFolder and junctionsFolder:IsA("Folder")) then
		return {}
	end

	local junctions = {}
	local children = sortedChildren(junctionsFolder, "Vector3Value")
	for _, junctionData in ipairs(children) do
		table.insert(junctions, {
			center = junctionData.Value,
			radius = tonumber(junctionData:GetAttribute("Radius")) or DEFAULT_AUTHORED_ROAD_WIDTH * INTERSECTION_RADIUS_SCALE,
			componentId = tonumber(junctionData:GetAttribute("ComponentId")) or 1,
			members = {},
			chains = {},
		})
	end
	return junctions
end

local function buildProcessedComponents(chains, junctions)
	local byId = {}
	local components = {}

	local function getComponent(componentId)
		local id = componentId or 1
		local component = byId[id]
		if not component then
			component = {
				id = id,
				chains = {},
				junctions = {},
			}
			byId[id] = component
			table.insert(components, component)
		end
		return component
	end

	for _, chain in ipairs(chains) do
		table.insert(getComponent(chain.componentId).chains, chain)
	end

	for _, junction in ipairs(junctions) do
		table.insert(getComponent(junction.componentId).junctions, junction)
	end

	table.sort(components, function(a, b)
		return a.id < b.id
	end)
	return components
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
	return t, u
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
					local aT, bT = segmentIntersection2D(a1, a2, b1, b2)
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
			table.insert(clusters, { center = junction.center, members = members, width = junctionWidth })
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

local function applyJunctionsToChains(chains, junctions)
	local insertsByChain = {}
	for _, junction in ipairs(junctions) do
		for _, member in ipairs(junction.members) do
			if member.index then
				member.chain.samples[member.index] = junction.center
			elseif member.segment and member.t then
				local inserts = insertsByChain[member.chain]
				if not inserts then
					inserts = {}
					insertsByChain[member.chain] = inserts
				end
				table.insert(inserts, { segment = member.segment, t = member.t, pos = junction.center })
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

				chain.samples[i] = Vector3.new(sample.X, sample.Y + (bestJunction.center.Y - sample.Y) * alpha, sample.Z)
			end
		end

		if chain.closed and #chain.samples > 2 then
			chain.samples[#chain.samples] = chain.samples[1]
		end
	end
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
		if index == 1 or index == count then
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

local function newMeshState()
	local editableMesh = AssetService:CreateEditableMesh()
	if not editableMesh then
		error("EditableMesh creation returned nil", 0)
	end
	return {
		mesh = editableMesh,
		faces = 0,
	}
end

local function addMeshVertex(state, pos)
	return state.mesh:AddVertex(pos)
end

local function addMeshTriangle(state, a, b, c)
	state.mesh:AddTriangle(a, b, c)
	state.faces += 1
end

local function addRoadRibbonToMesh(state, samples, roadWidth)
	if #samples < 2 then
		return 0
	end

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
			local center = samples[i] + Vector3.new(0, ROAD_MESH_THICKNESS * 0.5, 0)
			leftVerts[i] = addMeshVertex(state, center - right * (roadWidth * 0.5))
			rightVerts[i] = addMeshVertex(state, center + right * (roadWidth * 0.5))
		end
	end

	local spans = 0
	for i = 1, count - 1 do
		if (samples[i + 1] - samples[i]).Magnitude > 0.05 then
			addMeshTriangle(state, leftVerts[i], leftVerts[i + 1], rightVerts[i + 1])
			addMeshTriangle(state, leftVerts[i], rightVerts[i + 1], rightVerts[i])
			spans += 1
		end
	end
	return spans
end

local function addIntersectionDiskToMesh(state, junction)
	local center = junction.center + Vector3.new(0, ROAD_MESH_THICKNESS * 0.5, 0)
	local centerVertex = addMeshVertex(state, center)
	local ring = {}
	for i = 1, INTERSECTION_RING_SEGMENTS do
		local theta = ((i - 1) / INTERSECTION_RING_SEGMENTS) * math.pi * 2
		ring[i] = addMeshVertex(state, center + Vector3.new(math.cos(theta) * junction.radius, 0, math.sin(theta) * junction.radius))
	end

	for i = 1, INTERSECTION_RING_SEGMENTS do
		addMeshTriangle(state, centerVertex, ring[i], ring[(i % INTERSECTION_RING_SEGMENTS) + 1])
	end
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
			component = { chains = {}, junctions = {} }
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

local function createMeshPartFromState(state, parent, name)
	local meshContent = Content.fromObject(state.mesh)
	local okBake, bakeResult, bakedContent = pcall(function()
		return AssetService:CreateDataModelContentAsync(meshContent)
	end)
	if okBake and bakeResult == Enum.CreateContentResult.Success then
		meshContent = bakedContent
	end

	local meshPart = AssetService:CreateMeshPartAsync(meshContent, {
		CollisionFidelity = Enum.CollisionFidelity.Box,
	})
	meshPart.Name = name
	meshPart.Anchored = true
	meshPart.CanCollide = false
	meshPart.CanQuery = false
	meshPart.CanTouch = false
	meshPart.Material = Enum.Material.Asphalt
	meshPart.Color = Color3.fromRGB(28, 28, 32)
	pcall(function()
		meshPart.DoubleSided = true
	end)
	meshPart:SetAttribute("GeneratedBy", "Cab87RoadClientVisual")
	meshPart:SetAttribute("TriangleCount", state.faces)
	meshPart.Parent = parent
	return meshPart
end

local function buildClientRoadMesh(root, world)
	local chains = collectSplineBuildData(root)
	if #chains == 0 then
		error("No authored spline chains found", 0)
	end

	local processedRoadNetwork = root:GetAttribute("ProcessedRoadNetwork") == true
	local junctions
	if processedRoadNetwork then
		junctions = collectProcessedJunctions(root)
	else
		local rawJunctions = collectEndpointJunctions(chains)
		for _, junction in ipairs(collectCrossIntersections(chains)) do
			table.insert(rawJunctions, junction)
		end

		junctions = mergeJunctions(rawJunctions)
		applyJunctionsToChains(chains, junctions)
	end

	local oldVisuals = world:FindFirstChild(CLIENT_VISUALS_NAME)
	if oldVisuals then
		oldVisuals:Destroy()
	end

	local visualModel = Instance.new("Model")
	visualModel.Name = CLIENT_VISUALS_NAME
	visualModel.Parent = world

	local totalSpans = 0
	local meshParts = 0
	local components = if processedRoadNetwork then buildProcessedComponents(chains, junctions) else buildRoadComponents(chains, junctions)
	for i, component in ipairs(components) do
		local state = newMeshState()
		for _, chain in ipairs(component.chains) do
			totalSpans += addRoadRibbonToMesh(state, chain.samples, chain.width)
		end
		for _, junction in ipairs(component.junctions) do
			addIntersectionDiskToMesh(state, junction)
		end

		if state.faces > 0 then
			local name = string.format("AuthoredRoadClientMesh_%03d", i)
			createMeshPartFromState(state, visualModel, name)
			meshParts += 1
		end
	end

	if meshParts == 0 then
		visualModel:Destroy()
		error("No client road mesh faces were generated", 0)
	end

	return meshParts, totalSpans
end

local function buildForWorld(world)
	if not world or not world.Parent then
		return
	end

	hideEditorDebugGeometry()

	if world:GetAttribute("NeedsClientRoadMesh") ~= true then
		local oldVisuals = world:FindFirstChild(CLIENT_VISUALS_NAME)
		if oldVisuals then
			oldVisuals:Destroy()
		end
		setWorldStatus(world, "SkippedServerMesh", "", 0, 0)
		return
	end

	local root = world:FindFirstChild(RUNTIME_SPLINE_DATA_NAME)
		or world:WaitForChild(RUNTIME_SPLINE_DATA_NAME, 5)
		or Workspace:FindFirstChild(ROAD_EDITOR_ROOT_NAME)
		or Workspace:WaitForChild(ROAD_EDITOR_ROOT_NAME, 5)
	if not (root and (root:IsA("Model") or root:IsA("Folder"))) then
		setWorldStatus(world, "MissingSplineData", RUNTIME_SPLINE_DATA_NAME .. " was not replicated to the client", 0, 0)
		return
	end

	local ok, meshPartsOrErr, spans = pcall(function()
		return buildClientRoadMesh(root, world)
	end)
	if ok then
		setWorldStatus(world, "Built", "", meshPartsOrErr, spans)
	else
		local message = tostring(meshPartsOrErr)
		warn("[cab87 roads] Client road mesh build failed: " .. message)
		setWorldStatus(world, "Failed", message, 0, 0)
	end
end

local function scheduleBuild()
	buildSerial += 1
	local serial = buildSerial
	task.delay(0.25, function()
		if serial ~= buildSerial then
			return
		end

		local world = Workspace:FindFirstChild(RUNTIME_WORLD_NAME)
		if world and world:IsA("Model") then
			buildForWorld(world)
		end
	end)
end

local function watchWorld(world)
	if watchedConnection then
		watchedConnection:Disconnect()
		watchedConnection = nil
	end
	watchedWorld = world

	if watchedWorld then
		watchedConnection = watchedWorld:GetAttributeChangedSignal("NeedsClientRoadMesh"):Connect(scheduleBuild)
	end
	scheduleBuild()
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == RUNTIME_WORLD_NAME and child:IsA("Model") then
		watchWorld(child)
	end
end)

local existingWorld = Workspace:FindFirstChild(RUNTIME_WORLD_NAME)
if existingWorld and existingWorld:IsA("Model") then
	watchWorld(existingWorld)
end
