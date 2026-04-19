-- Cab87 Studio plugin: spline-based road drafting for fast traversal iteration.
-- Install by copying this file into your Roblox Plugins folder:
--   %LOCALAPPDATA%\Roblox\Plugins\Cab87RoadCurveTools.plugin.lua

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Workspace = game:GetService("Workspace")

local TOOLBAR_NAME = "cab87 roads"

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local newSplineButton = toolbar:CreateButton("New Spline", "Create/clear current road spline", "rbxasset://textures/StudioToolbox/PluginToolbar/icon_new.png")
local addPointButton = toolbar:CreateButton("Add Point", "Add control point at camera ray hit", "rbxasset://textures/StudioToolbox/PluginToolbar/icon_add.png")
local snapButton = toolbar:CreateButton("Snap Points", "Snap all points to terrain", "rbxasset://textures/StudioToolbox/PluginToolbar/icon_snap.png")
local rebuildButton = toolbar:CreateButton("Rebuild Road", "Rebuild road geometry from spline", "rbxasset://textures/StudioToolbox/PluginToolbar/icon_build.png")
local clearRoadButton = toolbar:CreateButton("Clear Road", "Delete generated road mesh", "rbxasset://textures/StudioToolbox/PluginToolbar/icon_delete.png")

newSplineButton.ClickableWhenViewportHidden = true
addPointButton.ClickableWhenViewportHidden = true
snapButton.ClickableWhenViewportHidden = true
rebuildButton.ClickableWhenViewportHidden = true
clearRoadButton.ClickableWhenViewportHidden = true

local ROOT_NAME = "Cab87RoadEditor"
local POINTS_NAME = "RoadPoints"
local MESH_NAME = "RoadMesh"

local ROAD_WIDTH = 28
local ROAD_THICKNESS = 1.2
local SAMPLE_STEP_STUDS = 10
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

local function addControlPoint(pos)
	local folder = getOrCreatePointsFolder()
	local idx = #folder:GetChildren() + 1
	local p = Instance.new("Part")
	p.Name = pointName(idx)
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(4, 4, 4)
	p.Anchored = true
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 180, 75)
	p.Position = pos
	p.Parent = folder
	return p
end

local function catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

local function sampleSpline(pointParts)
	local positions = {}
	for _, p in ipairs(pointParts) do
		table.insert(positions, p.Position)
	end

	if #positions < 2 then
		return positions
	end

	local samples = {}
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
	return samples
end

local function rebuildRoadFromPoints()
	local points = sortedPoints()
	if #points < 2 then
		warn("[cab87 roads] Need at least 2 control points")
		return
	end

	local roadModel = getOrCreateRoadModel()
	clearFolder(roadModel)

	local samples = sampleSpline(points)
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
			part.Parent = roadModel
			segments += 1
		end
	end

	print(string.format("[cab87 roads] Built %d road segments from %d control points", segments, #points))
end

local function snapPointsToTerrain()
	local points = sortedPoints()
	if #points == 0 then
		warn("[cab87 roads] No control points to snap")
		return
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

	print(string.format("[cab87 roads] Snapped %d points", changed))
end

newSplineButton.Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before new spline")
	local pointsFolder = getOrCreatePointsFolder()
	local roadModel = getOrCreateRoadModel()
	clearFolder(pointsFolder)
	clearFolder(roadModel)
	ChangeHistoryService:SetWaypoint("cab87 roads after new spline")
	print("[cab87 roads] New spline started")
end)

addPointButton.Click:Connect(function()
	local pos = raycastFromCamera(4000)
	if not pos then
		warn("[cab87 roads] Could not determine add point position")
		return
	end
	ChangeHistoryService:SetWaypoint("cab87 roads before add point")
	local p = addControlPoint(pos)
	ChangeHistoryService:SetWaypoint("cab87 roads after add point")
	print("[cab87 roads] Added point " .. p.Name)
end)

snapButton.Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before snap")
	snapPointsToTerrain()
	ChangeHistoryService:SetWaypoint("cab87 roads after snap")
end)

rebuildButton.Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before rebuild")
	rebuildRoadFromPoints()
	ChangeHistoryService:SetWaypoint("cab87 roads after rebuild")
end)

clearRoadButton.Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before clear")
	clearFolder(getOrCreateRoadModel())
	ChangeHistoryService:SetWaypoint("cab87 roads after clear")
	print("[cab87 roads] Cleared road geometry")
end)
