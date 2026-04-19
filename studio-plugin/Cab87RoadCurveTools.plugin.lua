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

local ROAD_WIDTH = 28
local ROAD_THICKNESS = 1.2
local SAMPLE_STEP_STUDS = 8
local ROAD_OVERLAP = 1.0
local POINT_SNAP_OFFSET = 0.35
local ENDPOINT_WELD_DISTANCE = 22

local AUTO_REBUILD_DELAY = 0.12
local autoRebuildEnabled = false
local autoRebuildScheduled = false

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

local function buildPrimitiveRoad(samples, targetModel, namePrefix)
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
			part.Size = Vector3.new(ROAD_WIDTH, ROAD_THICKNESS, len + ROAD_OVERLAP)
			part.CFrame = CFrame.lookAt(mid, b)
			part.Locked = true
			part.Parent = targetModel
			segments += 1
		end
	end
	return segments
end

local function buildMeshRoad(samples, targetModel, meshName)
	local editableMesh = AssetService:CreateEditableMesh()
	if not editableMesh then
		return false, "EditableMesh creation failed"
	end

	local leftVerts = {}
	local rightVerts = {}

	for i = 1, #samples do
		local prev = samples[math.max(1, i - 1)]
		local nextp = samples[math.min(#samples, i + 1)]
		local tangent = (nextp - prev)
		if tangent.Magnitude < 1e-4 then
			tangent = Vector3.new(0, 0, 1)
		else
			tangent = tangent.Unit
		end

		local right = tangent:Cross(Vector3.yAxis)
		if right.Magnitude < 1e-4 then
			right = Vector3.xAxis
		else
			right = right.Unit
		end

		local center = samples[i] + Vector3.new(0, ROAD_THICKNESS * 0.5, 0)
		local leftPos = center - right * (ROAD_WIDTH * 0.5)
		local rightPos = center + right * (ROAD_WIDTH * 0.5)

		leftVerts[i] = editableMesh:AddVertex(leftPos)
		rightVerts[i] = editableMesh:AddVertex(rightPos)
	end

	for i = 1, #samples - 1 do
		local l1 = leftVerts[i]
		local r1 = rightVerts[i]
		local l2 = leftVerts[i + 1]
		local r2 = rightVerts[i + 1]

		editableMesh:AddTriangle(l1, l2, r2)
		editableMesh:AddTriangle(l1, r2, r1)
	end

	local meshContent = Content.fromObject(editableMesh)
	local okCreate, meshPartOrErr = pcall(function()
		return AssetService:CreateMeshPartAsync(meshContent)
	end)
	if not okCreate then
		return false, tostring(meshPartOrErr)
	end

	local meshPart = meshPartOrErr
	meshPart.Name = meshName or "RoadRibbonMesh"
	meshPart.Anchored = true
	meshPart.Material = Enum.Material.Asphalt
	meshPart.Color = Color3.fromRGB(28, 28, 32)
	meshPart.DoubleSided = true
	meshPart.Locked = true
	meshPart.Parent = targetModel

	return true, #samples - 1
end

local function distanceXZ(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function dedupeJunctionPoint(points, p, threshold)
	for i = 1, #points do
		if distanceXZ(points[i], p) <= threshold then
			points[i] = (points[i] + p) * 0.5
			return
		end
	end
	table.insert(points, p)
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
			})
		end
	end
	return chains
end

local function weldEndpointJunctions(chains)
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
		for _, cluster in ipairs(clusters) do
			if distanceXZ(cluster.center, endpoint.pos) <= ENDPOINT_WELD_DISTANCE then
				table.insert(cluster.members, endpoint)
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
			table.insert(clusters, { center = endpoint.pos, members = { endpoint } })
		end
	end

	local junctions = {}
	for _, cluster in ipairs(clusters) do
		if #cluster.members >= 2 then
			local center = cluster.center
			for _, m in ipairs(cluster.members) do
				m.chain.samples[m.index] = center
			end
			dedupeJunctionPoint(junctions, center, ROAD_WIDTH * 0.35)
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

	if t <= 0 or t >= 1 or u <= 0 or u >= 1 then
		return nil
	end

	return Vector2.new(p.X + r.X * t, p.Y + r.Y * t)
end

local function collectCrossIntersections(chains)
	local points = {}
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
					local hit2 = segmentIntersection2D(a1, a2, b1, b2)
					if hit2 then
						local y = (a1.Y + a2.Y + b1.Y + b2.Y) * 0.25
						dedupeJunctionPoint(points, Vector3.new(hit2.X, y, hit2.Y), ROAD_WIDTH * 0.45)
					end
				end
			end
		end
	end
	return points
end

local function createIntersectionCaps(targetModel, points)
	local caps = 0
	for i, p in ipairs(points) do
		local cap = Instance.new("Part")
		cap.Name = string.format("Intersection_%03d", i)
		cap.Shape = Enum.PartType.Cylinder
		cap.Anchored = true
		cap.Material = Enum.Material.Asphalt
		cap.Color = Color3.fromRGB(28, 28, 32)
		cap.Size = Vector3.new(ROAD_THICKNESS, ROAD_WIDTH * 1.15, ROAD_WIDTH * 1.15)
		cap.CFrame = CFrame.new(p + Vector3.new(0, ROAD_THICKNESS * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		cap.Locked = true
		cap.Parent = targetModel
		caps += 1
	end
	return caps
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

	local endpointJunctions = weldEndpointJunctions(chains)
	local crossJunctions = collectCrossIntersections(chains)

	local totalSpans = 0
	local usedFallback = false

	for _, chain in ipairs(chains) do
		local meshName = string.format("Road_%s", chain.spline.Name)
		local okMesh, info = buildMeshRoad(chain.samples, network, meshName)
		if okMesh then
			totalSpans += info
		else
			usedFallback = true
			warn("[cab87 roads] Mesh build failed for " .. chain.spline.Name .. ": " .. tostring(info))
			totalSpans += buildPrimitiveRoad(chain.samples, network, meshName)
		end
	end

	local junctionPoints = {}
	for _, p in ipairs(endpointJunctions) do
		dedupeJunctionPoint(junctionPoints, p, ROAD_WIDTH * 0.35)
	end
	for _, p in ipairs(crossJunctions) do
		dedupeJunctionPoint(junctionPoints, p, ROAD_WIDTH * 0.35)
	end
	local capCount = createIntersectionCaps(network, junctionPoints)

	local note = string.format("Network rebuilt: %d splines, %d spans, %d intersections%s", #chains, totalSpans, capCount, usedFallback and " (primitive fallback used)" or "")
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
	520,
	280,
	360
)

local widget = plugin:CreateDockWidgetPluginGui("Cab87RoadCurveEditorWidget", widgetInfo)
widget.Title = "Cab87 Road Editor"
widget.Enabled = true

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
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
status.Size = UDim2.new(1, 0, 0, 52)
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
	local active = getActiveSpline()
	local splineCount = #sortedSplines()
	local base = string.format("Spline: %s (%d total) | Points: %d | Road parts: %d | Curve: %s", active.Name, splineCount, points, segments, curveMode)
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
local btnClear = makeButton("Clear Road")
local btnAutoRebuild = makeButton("Auto Rebuild: Off")

local function refreshCurveModeButton()
	btnCloseCurve.Text = isClosedCurve() and "Curve Mode: Closed" or "Curve Mode: Open"
end

local function refreshAutoRebuildButton()
	btnAutoRebuild.Text = autoRebuildEnabled and "Auto Rebuild: On" or "Auto Rebuild: Off"
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

local function scheduleAutoRebuild(reason)
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
	refreshPointWatchers()
	updateStatus("Started " .. spline.Name)
end)

btnPrevSpline.MouseButton1Click:Connect(function()
	local spline = cycleActiveSpline(-1)
	refreshCurveModeButton()
	refreshPointWatchers()
	updateStatus("Active spline: " .. spline.Name)
end)

btnNextSpline.MouseButton1Click:Connect(function()
	local spline = cycleActiveSpline(1)
	refreshCurveModeButton()
	refreshPointWatchers()
	updateStatus("Active spline: " .. spline.Name)
end)

btnCloseCurve.MouseButton1Click:Connect(function()
	setClosedCurve(not isClosedCurve())
	refreshCurveModeButton()
	updateStatus(isClosedCurve() and "Curve set to closed loop" or "Curve set to open")
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

btnClear.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before clear")
	clearFolder(getOrCreateNetworkModel())
	clearPerSplineRoadMeshes()
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

refreshPointWatchers()
refreshCurveModeButton()
refreshAutoRebuildButton()
updateStatus("Panel stays open while you iterate")
