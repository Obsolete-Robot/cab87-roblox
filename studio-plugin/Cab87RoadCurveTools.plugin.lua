-- Cab87 Studio plugin: persistent spline road editor panel.
-- Install to:
--   %LOCALAPPDATA%\Roblox\Plugins\Cab87RoadCurveTools.plugin.lua

local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local ROOT_NAME = "Cab87RoadEditor"
local POINTS_NAME = "RoadPoints"
local MESH_NAME = "RoadMesh"

local ROAD_WIDTH = 28
local ROAD_THICKNESS = 1.2
local SAMPLE_STEP_STUDS = 8
local ROAD_OVERLAP = 1.0
local POINT_SNAP_OFFSET = 0.35

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

local function getOrCreatePointsFolder()
	local root = getOrCreateRoot()
	local folder = root:FindFirstChild(POINTS_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = POINTS_NAME
	folder.Parent = root
	return folder
end

local function getOrCreateRoadModel()
	local root = getOrCreateRoot()
	local model = root:FindFirstChild(MESH_NAME)
	if model and model:IsA("Model") then
		return model
	end
	model = Instance.new("Model")
	model.Name = MESH_NAME
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

local function pointName(index)
	return string.format("P%03d", index)
end

local function renumberPoints()
	for i, p in ipairs(sortedPoints()) do
		p.Name = pointName(i)
	end
end

local function isControlPoint(inst)
	if not inst or not inst:IsA("BasePart") then
		return false
	end
	return inst.Parent == getOrCreatePointsFolder()
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

local function isClosedCurve()
	local root = getOrCreateRoot()
	return root:GetAttribute("ClosedCurve") == true
end

local function setClosedCurve(value)
	local root = getOrCreateRoot()
	root:SetAttribute("ClosedCurve", value and true or false)
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

local function buildPrimitiveRoad(samples)
	local roadModel = getOrCreateRoadModel()
	clearFolder(roadModel)

	local segments = 0
	for i = 1, #samples - 1 do
		local a = samples[i]
		local b = samples[i + 1]
		local delta = b - a
		local len = delta.Magnitude
		if len > 0.05 then
			local mid = (a + b) * 0.5 + Vector3.new(0, ROAD_THICKNESS * 0.5, 0)
			local part = Instance.new("Part")
			part.Name = string.format("Road_%04d", i)
			part.Anchored = true
			part.Material = Enum.Material.Asphalt
			part.Color = Color3.fromRGB(28, 28, 32)
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Size = Vector3.new(ROAD_WIDTH, ROAD_THICKNESS, len + ROAD_OVERLAP)
			part.CFrame = CFrame.lookAt(mid, b)
			part.Locked = true
			part.Parent = roadModel
			segments += 1
		end
	end
	return segments
end

local function buildMeshRoad(samples)
	local roadModel = getOrCreateRoadModel()
	clearFolder(roadModel)

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
	meshPart.Name = "RoadRibbonMesh"
	meshPart.Anchored = true
	meshPart.Material = Enum.Material.Asphalt
	meshPart.Color = Color3.fromRGB(28, 28, 32)
	meshPart.DoubleSided = true
	meshPart.Locked = true
	meshPart.Parent = roadModel

	return true, #samples - 1
end

local function rebuildRoadMeshPreferred()
	local points = sortedPoints()
	if #points < 2 then
		warn("[cab87 roads] Need at least 2 control points")
		return 0, "Need at least 2 points"
	end

	local samples = sampleSpline(points, isClosedCurve())
	local okMesh, info = buildMeshRoad(samples)
	if okMesh then
		print(string.format("[cab87 roads] Built mesh road from %d control points", #points))
		return info, "Mesh road built"
	end

	warn("[cab87 roads] EditableMesh build failed, falling back to primitives: " .. tostring(info))
	local segs = buildPrimitiveRoad(samples)
	print(string.format("[cab87 roads] Built %d primitive segments (fallback)", segs))
	return segs, "Fallback primitives (EditableMesh unavailable)"
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
	if not isControlPoint(target) then
		return false
	end
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
	if not isControlPoint(target) then
		return nil, nil, sortedPoints()
	end
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
	local road = getOrCreateRoadModel()
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
	local base = string.format("Points: %d | Road parts: %d | Curve: %s", points, segments, curveMode)
	if extra and #extra > 0 then
		status.Text = base .. "\n" .. extra
	else
		status.Text = base .. "\nTip: Select Nearest + Y buttons makes fast flatten/slope edits."
	end
end

local btnNew = makeButton("New Spline")
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

local function refreshCurveModeButton()
	btnCloseCurve.Text = isClosedCurve() and "Curve Mode: Closed" or "Curve Mode: Open"
end

btnNew.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before new spline")
	clearFolder(getOrCreatePointsFolder())
	clearFolder(getOrCreateRoadModel())
	setClosedCurve(false)
	ChangeHistoryService:SetWaypoint("cab87 roads after new spline")
	refreshCurveModeButton()
	updateStatus("Started new spline")
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
	clearFolder(getOrCreateRoadModel())
	ChangeHistoryService:SetWaypoint("cab87 roads after clear")
	updateStatus("Cleared road geometry")
end)

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

Selection.SelectionChanged:Connect(function()
	updateStatus(nil)
end)

refreshCurveModeButton()
updateStatus("Panel stays open while you iterate")
