-- Cab87 Studio plugin: graph road importer/builder.
-- Install to:
--   %LOCALAPPDATA%\Roblox\Plugins\Cab87RoadGraphBuilder.plugin.lua

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local StudioService = game:GetService("StudioService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ROOT_NAME = "Cab87RoadEditor"
local ROAD_GRAPH_NAME = "RoadGraph"
local MARKERS_NAME = "Markers"
local MARKER_TYPE_ATTR = "Cab87MarkerType"
local CAB_COMPANY_NODE_NAME = "CabCompanyNode"
local CAB_REFUEL_NODE_NAME = "CabRefuelPoint"
local CAB_SERVICE_NODE_NAME = "CabServicePoint"
local PLAYER_SPAWN_NAME = "PlayerSpawnPoint"
local ROAD_GRAPH_SURFACES_NAME = "RoadGraphSurfaces"
local ROAD_GRAPH_COLLISION_NAME = "RoadGraphCollision"
local BAKED_RUNTIME_NAME = "RoadGraphBakedRuntime"
local BAKED_RUNTIME_BUILDING_NAME = "RoadGraphBakedRuntime_Building"
local BAKED_SURFACES_NAME = "RoadGraphBakedSurfaces"
local BAKED_COLLISION_NAME = "RoadGraphBakedCollision"
local MINIMAP_ROAD_MESH_NAME = "MinimapRoadMesh"
local ASSETS_NAME = "RoadGraphAssets"
local BAKED_MESH_GENERATOR_NAME = "Cab87RoadGraphBake"
local MINIMAP_MESH_GENERATOR_NAME = "Cab87MinimapRoadMeshBake"
local MINIMAP_MESH_VERSION = 3
local MINIMAP_MESH_CHUNK_STUDS = 1024
local MINIMAP_MESH_MAX_PARTS = 256
local IMPORT_FILE_FILTER = { "json" }
local MESH_MANIFEST_SCHEMA = "cab87-road-mesh-manifest"
local MESH_MANIFEST_VERSION = 1
local IMPORT_PLANE_Y_SETTING = "cab87_road_graph_import_plane_y"
local IMPORT_POINT_SCALE_SETTING = "cab87_road_graph_import_point_scale"
local IMPORT_WIDTH_SCALE_SETTING = "cab87_road_graph_import_width_scale"
local MAP_ID_SETTING = "cab87_road_graph_map_id"
local GRAPH_COORDINATE_TRANSFORM_APPLIED_ATTR = "ImportedGlbCoordinateTransformApplied"
local GRAPH_COORDINATE_TRANSFORM_NAME_ATTR = "ImportedGlbCoordinateTransform"
local GRAPH_COORDINATE_TRANSFORM_MARKER_ATTR = "GraphCoordinateTransformApplied"
local DEFAULT_MAP_ID = "cab87_map"
local DEFAULT_IMPORT_PLANE_Y = 0.52
local DEFAULT_IMPORT_SCALE = 1
local MIN_IMPORT_SCALE = 0.1
local MAX_IMPORT_SCALE = 4
local IMPORT_SCALE_STEP = 0.01
local BAKE_CHUNK_SIZE_STUDS = 768
local BAKE_MAX_SURFACE_TRIANGLES = 6000
local BAKE_MAX_COLLISION_INPUT_TRIANGLES = 900
local COLLISION_VERTICAL_CHUNK_SIZE_ATTR = "CollisionVerticalChunkSize"
local AUTO_RELOAD_DELAY_SECONDS = 1.5
local AUTO_RELOAD_RETRY_SECONDS = 1
local AUTO_RELOAD_MAX_ATTEMPTS = 20

local MARKER_DESCRIPTIONS = {
	CabCompany = "Cab spawn marker",
	CabRefuel = "Free refuel marker",
	CabService = "Cab recover and garage/shop marker",
	PlayerSpawn = "Player spawn marker",
}

local COORDINATE_TRANSFORM_CANDIDATES = {
	{ name = "identity", xx = 1, xz = 0, zx = 0, zz = 1 },
	{ name = "rotate_90_clockwise", xx = 0, xz = 1, zx = -1, zz = 0 },
	{ name = "rotate_90_counterclockwise", xx = 0, xz = -1, zx = 1, zz = 0 },
	{ name = "rotate_180", xx = -1, xz = 0, zx = 0, zz = -1 },
	{ name = "mirror_x", xx = -1, xz = 0, zx = 0, zz = 1 },
	{ name = "mirror_z", xx = 1, xz = 0, zx = 0, zz = -1 },
	{ name = "swap_xz", xx = 0, xz = 1, zx = 1, zz = 0 },
	{ name = "swap_xz_mirror", xx = 0, xz = -1, zx = -1, zz = 0 },
}

local toolbar = plugin:CreateToolbar("Cab87")
local toggleButton = toolbar:CreateButton(
	"Road Graph Builder",
	"Import visualizer graph JSON and build road graph meshes",
	""
)
local addCabSpawnToolbarButton = toolbar:CreateButton(
	"Add Cab Spawn",
	"Place the cab spawn marker from the camera",
	""
)
local addCabRefuelToolbarButton = toolbar:CreateButton(
	"Add Refuel",
	"Place the free-refuel marker from the camera",
	""
)
local addCabServiceToolbarButton = toolbar:CreateButton(
	"Add Service",
	"Place the cab recover and garage/shop marker from the camera",
	""
)
local addPlayerSpawnToolbarButton = toolbar:CreateButton(
	"Add Player Spawn",
	"Place the player spawn marker from the camera",
	""
)
local selectCabSpawnToolbarButton = toolbar:CreateButton(
	"Select Cab Spawn",
	"Select the cab spawn marker",
	""
)

toggleButton.ClickableWhenViewportHidden = true
selectCabSpawnToolbarButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	360,
	560,
	300,
	420
)

local widget = plugin:CreateDockWidgetPluginGui("Cab87RoadGraphBuilder", widgetInfo)
widget.Title = "Cab87 Road Graph Builder"

local rootFrame = Instance.new("ScrollingFrame")
rootFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
rootFrame.BorderSizePixel = 0
rootFrame.Size = UDim2.fromScale(1, 1)
rootFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
rootFrame.CanvasSize = UDim2.fromOffset(0, 0)
rootFrame.ScrollBarThickness = 8
rootFrame.ScrollingDirection = Enum.ScrollingDirection.Y
rootFrame.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = rootFrame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = rootFrame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 32)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 220, 120)
title.Text = "Road Graph Builder"
title.Parent = rootFrame

local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, 0, 0, 82)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextColor3 = Color3.fromRGB(220, 224, 228)
status.Text = "Import road graph JSON from the intersection visualizer."
status.Parent = rootFrame

local function makeButton(text)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 34)
	button.BackgroundColor3 = Color3.fromRGB(48, 54, 64)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = Color3.fromRGB(245, 245, 245)
	button.Text = text
	button.Parent = rootFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	return button
end

local function makeInputRow(labelText, defaultText)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundTransparency = 1
	row.Parent = rootFrame

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = row

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 90, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(206, 212, 218)
	label.Text = labelText
	label.Parent = row

	local input = Instance.new("TextBox")
	input.Size = UDim2.new(1, -98, 1, 0)
	input.BackgroundColor3 = Color3.fromRGB(35, 39, 46)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Gotham
	input.TextSize = 13
	input.TextColor3 = Color3.fromRGB(245, 245, 245)
	input.Text = defaultText
	input.Parent = row

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = input
	return input
end

local function sanitizeImportScale(value)
	local text = tostring(value or "")
	text = string.gsub(text, "[xX]", "")
	local number = tonumber(text) or DEFAULT_IMPORT_SCALE
	local stepped = math.floor((math.clamp(number, MIN_IMPORT_SCALE, MAX_IMPORT_SCALE) - MIN_IMPORT_SCALE) / IMPORT_SCALE_STEP + 0.5)
		* IMPORT_SCALE_STEP
		+ MIN_IMPORT_SCALE
	return math.clamp(stepped, MIN_IMPORT_SCALE, MAX_IMPORT_SCALE)
end

local function formatImportScale(value)
	local text = string.format("%.2f", sanitizeImportScale(value))
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

local function makeSliderRow(labelText, defaultValue)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 52)
	row.BackgroundTransparency = 1
	row.Parent = rootFrame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 90, 0, 24)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(206, 212, 218)
	label.Text = labelText
	label.Parent = row

	local input = Instance.new("TextBox")
	input.Position = UDim2.new(1, -58, 0, 0)
	input.Size = UDim2.new(0, 58, 0, 24)
	input.BackgroundColor3 = Color3.fromRGB(35, 39, 46)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Gotham
	input.TextSize = 12
	input.TextColor3 = Color3.fromRGB(245, 245, 245)
	input.Parent = row

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 6)
	inputCorner.Parent = input

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 98, 0, 34)
	track.Size = UDim2.new(1, -106, 0, 8)
	track.BackgroundColor3 = Color3.fromRGB(35, 39, 46)
	track.BorderSizePixel = 0
	track.Active = true
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 190, 86)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local knob = Instance.new("TextButton")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(16, 16)
	knob.BackgroundColor3 = Color3.fromRGB(255, 230, 160)
	knob.BorderSizePixel = 0
	knob.Active = true
	knob.AutoButtonColor = false
	knob.Text = ""
	knob.Parent = track

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local slider = {}
	local currentValue = sanitizeImportScale(defaultValue)

	local function ratioFor(value)
		return (sanitizeImportScale(value) - MIN_IMPORT_SCALE) / (MAX_IMPORT_SCALE - MIN_IMPORT_SCALE)
	end

	local function setValue(value)
		currentValue = sanitizeImportScale(value)
		local ratio = ratioFor(currentValue)
		input.Text = formatImportScale(currentValue)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knob.Position = UDim2.new(ratio, 0, 0.5, 0)
	end

	local function setFromInputPosition(inputObject)
		local width = track.AbsoluteSize.X
		if width <= 1 then
			width = math.max(row.AbsoluteSize.X - 106, 0)
		end
		if width <= 1 then
			return
		end
		local ratio = math.clamp((inputObject.Position.X - track.AbsolutePosition.X) / width, 0, 1)
		setValue(MIN_IMPORT_SCALE + ratio * (MAX_IMPORT_SCALE - MIN_IMPORT_SCALE))
	end

	local dragging = false
	local function beginDrag(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromInputPosition(inputObject)
		end
	end

	track.InputBegan:Connect(beginDrag)
	knob.InputBegan:Connect(beginDrag)
	UserInputService.InputChanged:Connect(function(inputObject)
		if dragging and (inputObject.UserInputType == Enum.UserInputType.MouseMovement or inputObject.UserInputType == Enum.UserInputType.Touch) then
			setFromInputPosition(inputObject)
		end
	end)
	UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	input.FocusLost:Connect(function()
		setValue(input.Text)
	end)

	function slider.getValue()
		setValue(input.Text)
		return currentValue
	end

	function slider.setValue(value)
		setValue(value)
	end

	setValue(currentValue)
	return slider
end

local importPlaneY = tonumber(plugin:GetSetting(IMPORT_PLANE_Y_SETTING)) or DEFAULT_IMPORT_PLANE_Y
local importPointScale = sanitizeImportScale(plugin:GetSetting(IMPORT_POINT_SCALE_SETTING))
local importWidthScale = sanitizeImportScale(plugin:GetSetting(IMPORT_WIDTH_SCALE_SETTING))
local mapId = tostring(plugin:GetSetting(MAP_ID_SETTING) or DEFAULT_MAP_ID)
local importPlaneInput = makeInputRow("Import Y", tostring(importPlaneY))
local importPointScaleSlider = makeSliderRow("Point Scale", importPointScale)
local importWidthScaleSlider = makeSliderRow("Width Scale", importWidthScale)
local mapIdInput = makeInputRow("Map ID", mapId)
local importButton = makeButton("Import Graph JSON")
local bakeAssetsButton = makeButton("Bake Runtime Geometry")
local adoptImportedMeshButton = makeButton("Adopt Imported GLB Mesh")
local forkMapButton = makeButton("Fork As New Map")
local clearAllButton = makeButton("Clear All Road Data")
local setCabSpawnButton = makeButton("Set Cab Spawn From Camera")
local setCabRefuelButton = makeButton("Set Refuel From Camera")
local setCabServiceButton = makeButton("Set Service From Camera")
local setPlayerSpawnButton = makeButton("Set Player Spawn From Camera")
local selectCabSpawnButton = makeButton("Select Cab Spawn")
local selectCabRefuelButton = makeButton("Select Refuel")
local selectCabServiceButton = makeButton("Select Service")
local selectPlayerSpawnButton = makeButton("Select Player Spawn")

local function setStatus(message)
	local text = tostring(message)
	status.Text = text
	local lower = string.lower(text)
	if string.find(lower, "fail", 1, true) or string.find(lower, "error", 1, true) or string.find(lower, "missing", 1, true) then
		warn("[cab87 road graph builder] " .. text)
	else
		print("[cab87 road graph builder] " .. text)
	end
end

local function stripUtf8Bom(text)
	if string.byte(text, 1) == 239 and string.byte(text, 2) == 187 and string.byte(text, 3) == 191 then
		return string.sub(text, 4)
	end
	return text
end

local function requireFreshModule(moduleScript)
	local clone = moduleScript:Clone()
	clone.Name = moduleScript.Name .. "_PluginFreshRequire"
	clone.Parent = moduleScript.Parent
	local ok, result = pcall(require, clone)
	clone:Destroy()
	return ok, result
end

local function getGraphDataModule()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if not shared then
		return nil, "ReplicatedStorage.Shared was not found. Start Rojo sync before using this plugin."
	end

	local graphDataModule = shared:FindFirstChild("RoadGraphData")
	if not graphDataModule then
		return nil, "Shared RoadGraphData module is missing. Start Rojo sync or rebuild the place from source."
	end

	local okGraphData, graphDataOrErr = requireFreshModule(graphDataModule)
	if not okGraphData then
		return nil, "RoadGraphData failed to load: " .. tostring(graphDataOrErr)
	end
	return graphDataOrErr, nil
end

local function getSharedModules()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if not shared then
		return nil, nil, nil, "ReplicatedStorage.Shared was not found. Start Rojo sync before using this plugin."
	end

	local graphDataModule = shared:FindFirstChild("RoadGraphData")
	local mesherModule = shared:FindFirstChild("RoadGraphMesher")
	local meshBuilderModule = shared:FindFirstChild("RoadMeshBuilder")
	if not (graphDataModule and mesherModule and meshBuilderModule) then
		return nil, nil, nil, "Shared road graph modules are missing. Start Rojo sync or rebuild the place from source."
	end

	local okGraphData, graphDataOrErr = requireFreshModule(graphDataModule)
	if not okGraphData then
		return nil, nil, nil, "RoadGraphData failed to load: " .. tostring(graphDataOrErr)
	end
	local okMesher, mesherOrErr = requireFreshModule(mesherModule)
	if not okMesher then
		return nil, nil, nil, "RoadGraphMesher failed to load: " .. tostring(mesherOrErr)
	end
	local okMeshBuilder, meshBuilderOrErr = requireFreshModule(meshBuilderModule)
	if not okMeshBuilder then
		return nil, nil, nil, "RoadMeshBuilder failed to load: " .. tostring(meshBuilderOrErr)
	end

	return graphDataOrErr, mesherOrErr, meshBuilderOrErr, nil
end

local function getOrCreateRoot()
	local root = Workspace:FindFirstChild(ROOT_NAME)
	if root and not root:IsA("Model") then
		root:Destroy()
		root = nil
	end
	if not root then
		root = Instance.new("Model")
		root.Name = ROOT_NAME
		root.Parent = Workspace
	end
	return root
end

local function getOrCreateMarkersFolder()
	local root = getOrCreateRoot()
	local folder = root:FindFirstChild(MARKERS_NAME)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = MARKERS_NAME
		folder.Parent = root
	end
	return folder
end

local function readImportedFileContents(file)
	if not file then
		return nil, "No file selected"
	end

	local ok, contentsOrErr = pcall(function()
		return file:GetBinaryContents()
	end)
	if not ok then
		return nil, tostring(contentsOrErr)
	end
	if type(contentsOrErr) ~= "string" or contentsOrErr == "" then
		return nil, "Imported file was empty"
	end
	return stripUtf8Bom(contentsOrErr)
end

local function refreshImportPlane()
	local planeY = tonumber(importPlaneInput.Text)
	if not planeY then
		importPlaneInput.Text = tostring(importPlaneY)
		setStatus("Import Y must be numeric.")
		return false
	end

	importPlaneY = math.clamp(planeY, -5000, 5000)
	importPlaneInput.Text = tostring(importPlaneY)
	plugin:SetSetting(IMPORT_PLANE_Y_SETTING, importPlaneY)
	return true
end

local function findDefaultBaseplate()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") and baseplate.Size.X >= 512 and baseplate.Size.Z >= 512 then
		return baseplate
	end
	return nil
end

local function keepGraphAboveDefaultBaseplate()
	if math.abs(importPlaneY) > 0.001 or not findDefaultBaseplate() then
		return
	end

	importPlaneY = DEFAULT_IMPORT_PLANE_Y
	importPlaneInput.Text = tostring(importPlaneY)
	plugin:SetSetting(IMPORT_PLANE_Y_SETTING, importPlaneY)
end

local function hideDefaultBaseplate()
	local baseplate = findDefaultBaseplate()
	if not baseplate then
		return
	end

	baseplate:SetAttribute("Cab87HiddenByRoadGraphBuilder", true)
	baseplate.Transparency = 1
	baseplate.CanCollide = false
	baseplate.CanTouch = false
	baseplate.CanQuery = false
end

local function refreshImportScales()
	importPointScale = sanitizeImportScale(importPointScaleSlider.getValue())
	importWidthScale = sanitizeImportScale(importWidthScaleSlider.getValue())
	importPointScaleSlider.setValue(importPointScale)
	importWidthScaleSlider.setValue(importWidthScale)
	plugin:SetSetting(IMPORT_POINT_SCALE_SETTING, importPointScale)
	plugin:SetSetting(IMPORT_WIDTH_SCALE_SETTING, importWidthScale)
	return true
end

local function applyImportScales(pointScale, widthScale)
	importPointScale = sanitizeImportScale(pointScale)
	importWidthScale = sanitizeImportScale(widthScale)
	importPointScaleSlider.setValue(importPointScale)
	importWidthScaleSlider.setValue(importWidthScale)
	plugin:SetSetting(IMPORT_POINT_SCALE_SETTING, importPointScale)
	plugin:SetSetting(IMPORT_WIDTH_SCALE_SETTING, importWidthScale)
end

local function applyGraphImportScales(graph)
	if not graph then
		return
	end
	applyImportScales(graph.importPointScale or importPointScale, graph.importWidthScale or importWidthScale)
end

local function scaleSummary()
	return string.format("point scale=%sx, width scale=%sx", formatImportScale(importPointScale), formatImportScale(importWidthScale))
end

local function sanitizeMapId(value)
	local text = tostring(value or "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.gsub(text, "[^%w_%-]", "_")
	text = string.gsub(text, "_+", "_")
	if text == "" then
		text = DEFAULT_MAP_ID
	end
	return text
end

local function refreshMapId()
	mapId = sanitizeMapId(mapIdInput.Text)
	mapIdInput.Text = mapId
	plugin:SetSetting(MAP_ID_SETTING, mapId)
	return true
end

local function clearChild(root, name)
	local child = root and root:FindFirstChild(name)
	if child then
		child:Destroy()
	end
end

local function createFolder(parent, name)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function hasAncestor(instance, ancestor)
	local current = instance
	while current do
		if current == ancestor then
			return true
		end
		current = current.Parent
	end
	return false
end

local function getOrCreateAssetsFolder(root)
	local assets = root:FindFirstChild(ASSETS_NAME)
	if assets and not assets:IsA("Folder") then
		assets:Destroy()
		assets = nil
	end
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = ASSETS_NAME
		assets.Parent = root
	end
	assets:SetAttribute("Schema", "cab87-road-graph-assets")
	assets:SetAttribute("Version", 1)
	assets:SetAttribute("MapId", mapId)
	return assets
end

local function markBakedAssetsStale(root, reason)
	if not root then
		return
	end

	local assets = root:FindFirstChild(ASSETS_NAME)
	if assets and assets:IsA("Folder") then
		assets:SetAttribute("Stale", true)
		assets:SetAttribute("StaleReason", reason or "graph changed")
	end
	clearChild(root, BAKED_RUNTIME_NAME)
	clearChild(root, BAKED_SURFACES_NAME)
	clearChild(root, BAKED_COLLISION_NAME)
	clearChild(root, MINIMAP_ROAD_MESH_NAME)
end

local function clearPreviewMeshes(root)
	clearChild(root, ROAD_GRAPH_SURFACES_NAME)
	clearChild(root, ROAD_GRAPH_COLLISION_NAME)
end

local function hideStaleEditorGeometry(root, visibleSurfaceFolder)
	if not root then
		return 0
	end

	local markersFolder = root:FindFirstChild(MARKERS_NAME)
	local hiddenParts = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if visibleSurfaceFolder and hasAncestor(descendant, visibleSurfaceFolder) then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
			elseif markersFolder and hasAncestor(descendant, markersFolder) then
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = true
			else
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Transparency = 1
				descendant:SetAttribute("Cab87HiddenByRoadGraphBuilder", true)
				hiddenParts += 1
			end
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			if not (markersFolder and hasAncestor(descendant, markersFolder)) then
				descendant.Enabled = false
			end
		end
	end
	return hiddenParts
end

local function setBakeScaleAttributes(instance)
	if not instance then
		return
	end
	instance:SetAttribute("PointScale", importPointScale)
	instance:SetAttribute("WidthScale", importWidthScale)
end

local function setGraphScaleAttributes(root)
	local graphFolder = root and root:FindFirstChild(ROAD_GRAPH_NAME)
	if not graphFolder or not graphFolder:IsA("Folder") then
		return
	end
	graphFolder:SetAttribute("ImportPointScale", importPointScale)
	graphFolder:SetAttribute("ImportWidthScale", importWidthScale)
end

local function countPolygonFillTriangles(meshData)
	local count = 0
	for _, fill in ipairs(meshData.polygonFills or meshData.polygonTriangles or {}) do
		count += #(fill.triangles or {})
	end
	return count
end

local function colorFromHex(value, fallback)
	if type(value) ~= "string" then
		return fallback
	end

	local hex = string.gsub(value, "#", "")
	if #hex ~= 6 then
		return fallback
	end

	local r = tonumber(string.sub(hex, 1, 2), 16)
	local g = tonumber(string.sub(hex, 3, 4), 16)
	local b = tonumber(string.sub(hex, 5, 6), 16)
	if not (r and g and b) then
		return fallback
	end

	return Color3.fromRGB(r, g, b)
end

local function enumByName(enumType, value, fallback)
	if type(value) ~= "string" or value == "" then
		return fallback
	end

	local ok, item = pcall(function()
		return enumType[value]
	end)
	if ok and item then
		return item
	end
	return fallback
end

local function normalizeMeshName(value)
	local text = string.lower(tostring(value or ""))
	return string.gsub(text, "[^%w]", "")
end

local function collectMeshParts(instance, target)
	if not instance then
		return
	end
	if instance:IsA("MeshPart") then
		table.insert(target, instance)
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("MeshPart") then
			table.insert(target, descendant)
		end
	end
end

local function getImportOriginModel(instance)
	if not instance then
		return nil
	end
	if instance:IsA("Model") and instance.Name ~= ROOT_NAME then
		return instance
	end

	local current = instance.Parent
	local candidate = nil
	while current and current ~= Workspace do
		if current:IsA("Model") and current.Name ~= ROOT_NAME then
			candidate = current
		end
		current = current.Parent
	end
	return candidate
end

local function selectedImportedMeshParts()
	local selected = Selection:Get()
	local parts = {}
	local seen = {}
	local rootModels = {}
	local firstRootModel = nil
	local rootModelCount = 0

	for _, instance in ipairs(selected) do
		local rootModel = getImportOriginModel(instance)
		if rootModel and not rootModels[rootModel] then
			rootModels[rootModel] = true
			rootModelCount += 1
			if not firstRootModel then
				firstRootModel = rootModel
			end
		end

		local collected = {}
		collectMeshParts(instance, collected)
		for _, part in ipairs(collected) do
			if not seen[part] then
				seen[part] = true
				table.insert(parts, part)
			end
		end
	end

	local importOriginCFrame = CFrame.new()
	local importOriginName = "world origin"
	if rootModelCount == 1 and firstRootModel then
		importOriginCFrame = firstRootModel:GetPivot()
		importOriginName = firstRootModel:GetFullName()
	elseif rootModelCount > 1 then
		importOriginName = "multiple selected roots"
	end

	return parts, importOriginCFrame, importOriginName, rootModelCount
end

local function indexMeshPartsByName(parts)
	local exact = {}
	local normalized = {}

	for _, part in ipairs(parts or {}) do
		exact[part.Name] = exact[part.Name] or {}
		table.insert(exact[part.Name], part)

		local normalizedName = normalizeMeshName(part.Name)
		normalized[normalizedName] = normalized[normalizedName] or {}
		table.insert(normalized[normalizedName], part)
	end

	return exact, normalized
end

local function takeFirstUnused(candidates, usedParts)
	for _, part in ipairs(candidates or {}) do
		if not usedParts[part] then
			usedParts[part] = true
			return part
		end
	end
	return nil
end

local function findManifestPart(chunk, exactParts, normalizedParts, allParts, usedParts)
	local targetName = tostring(chunk.name or "")
	local part = takeFirstUnused(exactParts[targetName], usedParts)
	if part then
		return part
	end

	local normalizedTarget = normalizeMeshName(targetName)
	part = takeFirstUnused(normalizedParts[normalizedTarget], usedParts)
	if part then
		return part
	end

	for _, candidate in ipairs(allParts or {}) do
		if not usedParts[candidate] then
			local candidateName = normalizeMeshName(candidate.Name)
			if string.sub(candidateName, 1, #normalizedTarget) == normalizedTarget then
				usedParts[candidate] = true
				return candidate
			end
		end
	end

	return nil
end

local function decodeMeshManifest(contents)
	local ok, manifestOrErr = pcall(function()
		return HttpService:JSONDecode(contents)
	end)
	if not ok or type(manifestOrErr) ~= "table" then
		return nil, "manifest JSON decode failed: " .. tostring(manifestOrErr)
	end

	local manifest = manifestOrErr
	if manifest.schema ~= MESH_MANIFEST_SCHEMA then
		return nil, "unsupported manifest schema: " .. tostring(manifest.schema)
	end
	if tonumber(manifest.version) ~= MESH_MANIFEST_VERSION then
		return nil, "unsupported manifest version: " .. tostring(manifest.version)
	end
	if type(manifest.chunks) ~= "table" or #manifest.chunks == 0 then
		return nil, "manifest had no chunks"
	end
	return manifest, nil
end

local function manifestSetting(manifest, key)
	local settings = manifest and manifest.settings
	if type(settings) ~= "table" then
		return nil
	end
	return settings[key]
end

local function finiteNumber(value)
	local number = tonumber(value)
	if number and number == number and number ~= math.huge and number ~= -math.huge then
		return number
	end
	return nil
end

local function manifestBoundsCenter(chunk)
	local bounds = type(chunk) == "table" and chunk.bounds
	if type(bounds) ~= "table" then
		return nil
	end

	local min = bounds.min
	local max = bounds.max
	if type(min) ~= "table" or type(max) ~= "table" then
		return nil
	end

	local minX = finiteNumber(min.x)
	local minY = finiteNumber(min.y)
	local minZ = finiteNumber(min.z)
	local maxX = finiteNumber(max.x)
	local maxY = finiteNumber(max.y)
	local maxZ = finiteNumber(max.z)
	if not (minX and minY and minZ and maxX and maxY and maxZ) then
		return nil
	end

	return Vector3.new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
end

local function coordinateTransformPosition(position, transform)
	if typeof(position) ~= "Vector3" or not transform then
		return position
	end

	local x = transform.xx * position.X + transform.xz * position.Z + transform.offsetX
	local z = transform.zx * position.X + transform.zz * position.Z + transform.offsetZ
	return Vector3.new(x, position.Y, z)
end

local function coordinateTransformDirection(direction, transform)
	if typeof(direction) ~= "Vector3" or not transform then
		return direction
	end

	local transformed = Vector3.new(
		transform.xx * direction.X + transform.xz * direction.Z,
		0,
		transform.zx * direction.X + transform.zz * direction.Z
	)
	if transformed.Magnitude <= 0.001 then
		return Vector3.new(0, 0, 1)
	end
	return transformed.Unit
end

local function coordinateTransformCFrame(cframe, transform)
	if typeof(cframe) ~= "CFrame" or not transform then
		return cframe
	end

	local position = coordinateTransformPosition(cframe.Position, transform)
	local look = coordinateTransformDirection(cframe.LookVector, transform)
	return CFrame.lookAt(position, position + look)
end

local function isCoordinateTransformNoop(transform)
	if not transform then
		return true
	end
	return transform.xx == 1
		and transform.xz == 0
		and transform.zx == 0
		and transform.zz == 1
		and math.abs(transform.offsetX or 0) <= 0.01
		and math.abs(transform.offsetZ or 0) <= 0.01
end

local function setCoordinateTransformAttributes(instance, transform)
	if not (instance and transform) then
		return
	end

	instance:SetAttribute(GRAPH_COORDINATE_TRANSFORM_NAME_ATTR, tostring(transform.name or "unknown"))
	instance:SetAttribute("ImportedGlbCoordinateTransformError", finiteNumber(transform.error) or 0)
	instance:SetAttribute("ImportedGlbCoordinateTransformSamples", finiteNumber(transform.sampleCount) or 0)
	instance:SetAttribute("ImportedGlbCoordinateOffsetX", finiteNumber(transform.offsetX) or 0)
	instance:SetAttribute("ImportedGlbCoordinateOffsetZ", finiteNumber(transform.offsetZ) or 0)
	instance:SetAttribute("ImportedGlbCoordinateXX", finiteNumber(transform.xx) or 1)
	instance:SetAttribute("ImportedGlbCoordinateXZ", finiteNumber(transform.xz) or 0)
	instance:SetAttribute("ImportedGlbCoordinateZX", finiteNumber(transform.zx) or 0)
	instance:SetAttribute("ImportedGlbCoordinateZZ", finiteNumber(transform.zz) or 1)
end

local function coordinateTransformSummary(transform)
	if not transform then
		return "unknown coordinate transform"
	end
	return string.format(
		"%s offset=(%.2f, %.2f), error=%.3f, samples=%d",
		tostring(transform.name or "unknown"),
		finiteNumber(transform.offsetX) or 0,
		finiteNumber(transform.offsetZ) or 0,
		finiteNumber(transform.error) or 0,
		math.floor(finiteNumber(transform.sampleCount) or 0)
	)
end

local function firstListValues(values, maxCount)
	local result = {}
	for index = 1, math.min(#values, maxCount) do
		table.insert(result, tostring(values[index]))
	end
	return result
end

local function promptMeshManifest()
	local okFile, fileOrErr = pcall(function()
		return StudioService:PromptImportFileAsync(IMPORT_FILE_FILTER)
	end)
	if not okFile then
		return nil, "manifest import failed to open file picker: " .. tostring(fileOrErr)
	end
	if not fileOrErr then
		return nil, "manifest import canceled"
	end

	local contents, readErr = readImportedFileContents(fileOrErr)
	if not contents then
		return nil, tostring(readErr)
	end
	return decodeMeshManifest(contents)
end

local function applyManifestPartOptions(part, chunk, mapIdValue, manifest)
	local kind = tostring(chunk.kind or "surface")
	local isCollision = kind == "collision"
	local collisionVerticalChunkSize = tonumber(manifestSetting(manifest, "collisionVerticalChunkSize"))

	part.Name = tostring(chunk.name or part.Name)
	part.Anchored = true
	part.CanCollide = chunk.canCollide == true
	part.CanQuery = chunk.canQuery == true
	part.CanTouch = chunk.canTouch == true
	part.CastShadow = chunk.castShadow == true
	part.Transparency = tonumber(chunk.transparency) or (if isCollision then 1 else 0)
	part.Color = colorFromHex(chunk.color, if isCollision then Color3.fromRGB(56, 189, 248) else Color3.fromRGB(28, 28, 32))
	part.Material = enumByName(Enum.Material, chunk.material, Enum.Material.Asphalt)
	pcall(function()
		part.DoubleSided = true
	end)
	pcall(function()
		part.CollisionFidelity = enumByName(
			Enum.CollisionFidelity,
			chunk.collisionFidelity,
			if isCollision then Enum.CollisionFidelity.PreciseConvexDecomposition else Enum.CollisionFidelity.Box
		)
	end)

	part:SetAttribute("MapId", mapIdValue)
	part:SetAttribute("BakedRoadGraphMesh", true)
	part:SetAttribute("BakeMode", "importedGlbManifest")
	part:SetAttribute("MeshMode", "importedGlbManifest")
	part:SetAttribute("MeshContentMode", "importedAsset")
	part:SetAttribute("GeneratedBy", BAKED_MESH_GENERATOR_NAME)
	part:SetAttribute("ManifestChunkName", tostring(chunk.name or part.Name))
	part:SetAttribute("ManifestLayer", tostring(chunk.layer or ""))
	part:SetAttribute("SurfaceType", tostring(chunk.surfaceType or ""))
	part:SetAttribute("TriangleCount", tonumber(chunk.triangleCount) or nil)
	part:SetAttribute("InputTriangleCount", tonumber(chunk.inputTriangleCount) or nil)
	part:SetAttribute("MeshChunkKey", tostring(chunk.chunkKey or ""))
	part:SetAttribute("MeshChunkY", tonumber(chunk.chunkY) or nil)
	part:SetAttribute("MeshBatchIndex", tonumber(chunk.batchIndex) or nil)

	if isCollision or chunk.driveSurface == true then
		part:SetAttribute("DriveSurface", true)
	end
	if isCollision and collisionVerticalChunkSize and collisionVerticalChunkSize > 0 then
		part:SetAttribute(COLLISION_VERTICAL_CHUNK_SIZE_ATTR, collisionVerticalChunkSize)
	end
	if tostring(chunk.surfaceType or "") == "polygonFill" then
		part:SetAttribute("BakedPolygonFillMesh", true)
	end
end

local function normalizeImportedCFrame(cframe, importOriginCFrame)
	local pointScale = importPointScale
	local planeY = importPlaneY
	local localCFrame = if importOriginCFrame then importOriginCFrame:ToObjectSpace(cframe) else cframe
	local position = localCFrame.Position
	local rotation = localCFrame - position
	return CFrame.new(
		position.X * pointScale,
		planeY + position.Y * pointScale,
		position.Z * pointScale
	) * rotation
end

local function setImportOriginAttributes(instance, importOriginCFrame)
	if not importOriginCFrame then
		return
	end
	instance:SetAttribute("ImportOriginX", importOriginCFrame.Position.X)
	instance:SetAttribute("ImportOriginY", importOriginCFrame.Position.Y)
	instance:SetAttribute("ImportOriginZ", importOriginCFrame.Position.Z)
end

local function importedLocalPosition(part, importOriginCFrame)
	local cframe = if importOriginCFrame then importOriginCFrame:ToObjectSpace(part.CFrame) else part.CFrame
	return cframe.Position
end

local function inferImportedCoordinateTransform(matches, importOriginCFrame)
	local samples = {}
	for _, match in ipairs(matches or {}) do
		local part = match.part
		local manifestCenter = manifestBoundsCenter(match.chunk)
		if part and part:IsA("BasePart") and manifestCenter then
			table.insert(samples, {
				expected = manifestCenter,
				imported = importedLocalPosition(part, importOriginCFrame),
			})
		end
	end

	if #samples < 2 then
		local identity = table.clone(COORDINATE_TRANSFORM_CANDIDATES[1])
		local sample = samples[1]
		identity.offsetX = if sample then sample.imported.X - sample.expected.X else 0
		identity.offsetZ = if sample then sample.imported.Z - sample.expected.Z else 0
		identity.error = 0
		identity.sampleCount = #samples
		return identity
	end

	local best = nil
	local evaluated = {}
	for _, candidate in ipairs(COORDINATE_TRANSFORM_CANDIDATES) do
		local sumOffsetX = 0
		local sumOffsetZ = 0
		for _, sample in ipairs(samples) do
			local expected = sample.expected
			local transformedX = candidate.xx * expected.X + candidate.xz * expected.Z
			local transformedZ = candidate.zx * expected.X + candidate.zz * expected.Z
			sumOffsetX += sample.imported.X - transformedX
			sumOffsetZ += sample.imported.Z - transformedZ
		end

		local offsetX = sumOffsetX / #samples
		local offsetZ = sumOffsetZ / #samples
		local squaredError = 0
		for _, sample in ipairs(samples) do
			local expected = sample.expected
			local transformedX = candidate.xx * expected.X + candidate.xz * expected.Z + offsetX
			local transformedZ = candidate.zx * expected.X + candidate.zz * expected.Z + offsetZ
			local dx = sample.imported.X - transformedX
			local dz = sample.imported.Z - transformedZ
			squaredError += dx * dx + dz * dz
		end

		local transform = {
			name = candidate.name,
			xx = candidate.xx,
			xz = candidate.xz,
			zx = candidate.zx,
			zz = candidate.zz,
			offsetX = offsetX,
			offsetZ = offsetZ,
			error = math.sqrt(squaredError / #samples),
			sampleCount = #samples,
		}
		table.insert(evaluated, transform)

		if not best or transform.error < best.error - 0.001 then
			best = transform
		end
	end
	table.sort(evaluated, function(a, b)
		return a.error < b.error
	end)
	for index = 1, math.min(#evaluated, 8) do
		local transform = evaluated[index]
		print("[cab87 road graph builder] coordinate transform candidate " .. tostring(index) .. ": " .. coordinateTransformSummary(transform))
	end

	return best
end

local function applyImportedMeshTransform(part, importOriginCFrame)
	if part:GetAttribute("ImportTransformApplied") == true then
		return
	end

	part.Size *= importPointScale
	part.CFrame = normalizeImportedCFrame(part.CFrame, importOriginCFrame)
	part:SetAttribute("ImportTransformApplied", true)
	part:SetAttribute("ImportPlaneY", importPlaneY)
	part:SetAttribute("ImportPointScale", importPointScale)
	setImportOriginAttributes(part, importOriginCFrame)
end

local function getSelectedPartsBounds(parts)
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = Vector3.new(-math.huge, -math.huge, -math.huge)
	local hasPart = false

	for _, part in ipairs(parts or {}) do
		if part and part:IsA("BasePart") then
			hasPart = true
			local radius = part.Size.Magnitude * 0.5
			local position = part.Position
			min = Vector3.new(
				math.min(min.X, position.X - radius),
				math.min(min.Y, position.Y - radius),
				math.min(min.Z, position.Z - radius)
			)
			max = Vector3.new(
				math.max(max.X, position.X + radius),
				math.max(max.Y, position.Y + radius),
				math.max(max.Z, position.Z + radius)
			)
		end
	end

	if not hasPart then
		return nil
	end

	return {
		min = min,
		max = max,
	}
end

local function boundsContainsPosition(bounds, position, padding)
	if not bounds or typeof(position) ~= "Vector3" then
		return false
	end
	padding = tonumber(padding) or 0
	return position.X >= bounds.min.X - padding
		and position.X <= bounds.max.X + padding
		and position.Y >= bounds.min.Y - padding
		and position.Y <= bounds.max.Y + padding
		and position.Z >= bounds.min.Z - padding
		and position.Z <= bounds.max.Z + padding
end

local function normalizeMarkersInImportedBounds(root, importOriginCFrame, sourceBounds)
	local markersFolder = root and root:FindFirstChild(MARKERS_NAME)
	if not (markersFolder and markersFolder:IsA("Folder")) then
		return 0
	end

	local transformed = 0
	local markerPadding = 250
	for _, descendant in ipairs(markersFolder:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant:GetAttribute("ImportTransformApplied") ~= true
			and boundsContainsPosition(sourceBounds, descendant.Position, markerPadding)
		then
			descendant.CFrame = normalizeImportedCFrame(descendant.CFrame, importOriginCFrame)
			descendant:SetAttribute("ImportTransformApplied", true)
			descendant:SetAttribute("ImportPlaneY", importPlaneY)
			descendant:SetAttribute("ImportPointScale", importPointScale)
			setImportOriginAttributes(descendant, importOriginCFrame)
			transformed += 1
		end
	end

	return transformed
end

local function transformGraphCoordinateMarkers(root, transform)
	if isCoordinateTransformNoop(transform) then
		return 0
	end

	local markersFolder = root and root:FindFirstChild(MARKERS_NAME)
	if not (markersFolder and markersFolder:IsA("Folder")) then
		return 0
	end

	local transformed = 0
	for _, descendant in ipairs(markersFolder:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant:GetAttribute("ImportTransformApplied") ~= true
			and descendant:GetAttribute(GRAPH_COORDINATE_TRANSFORM_MARKER_ATTR) ~= true
		then
			descendant.CFrame = coordinateTransformCFrame(descendant.CFrame, transform)
			descendant:SetAttribute(GRAPH_COORDINATE_TRANSFORM_MARKER_ATTR, true)
			setCoordinateTransformAttributes(descendant, transform)
			transformed += 1
		end
	end

	return transformed
end

local function transformGraphToImportedCoordinates(root, RoadGraphData, transform)
	local graphFolder = root and root:FindFirstChild(ROAD_GRAPH_NAME)
	if not (graphFolder and graphFolder:IsA("Folder")) then
		return 0, "missing"
	end
	if graphFolder:GetAttribute(GRAPH_COORDINATE_TRANSFORM_APPLIED_ATTR) == true then
		return 0, "already"
	end

	if isCoordinateTransformNoop(transform) then
		graphFolder:SetAttribute(GRAPH_COORDINATE_TRANSFORM_APPLIED_ATTR, true)
		setCoordinateTransformAttributes(graphFolder, transform)
		return 0, "identity"
	end

	local graph = RoadGraphData.collectGraph(root)
	if not graph then
		return 0, "missing"
	end

	local transformedPoints = 0
	for _, node in ipairs(graph.nodes or {}) do
		if typeof(node.point) == "Vector3" then
			node.point = coordinateTransformPosition(node.point, transform)
			transformedPoints += 1
		end
	end
	for _, edge in ipairs(graph.edges or {}) do
		for index, point in ipairs(edge.points or {}) do
			if typeof(point) == "Vector3" then
				edge.points[index] = coordinateTransformPosition(point, transform)
				transformedPoints += 1
			end
		end
	end

	graphFolder = RoadGraphData.writeGraph(root, graph)
	graphFolder:SetAttribute(GRAPH_COORDINATE_TRANSFORM_APPLIED_ATTR, true)
	setCoordinateTransformAttributes(graphFolder, transform)
	return transformedPoints, "applied"
end

local function cloneMinimapPart(sourcePart, parent, mapIdValue)
	local clone = sourcePart:Clone()
	clone.Name = sourcePart.Name
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.CastShadow = false
	clone.Transparency = 1
	clone:SetAttribute("MapId", mapIdValue)
	clone:SetAttribute("BakedRoadGraphMesh", true)
	clone:SetAttribute("BakedMinimapRoadMesh", true)
	clone:SetAttribute("MinimapRoadMesh", true)
	clone:SetAttribute("GeneratedBy", MINIMAP_MESH_GENERATOR_NAME)
	clone.Parent = parent
	return clone
end

local isPlayRunning

local function adoptImportedMeshFromManifest()
	if isPlayRunning() then
		setStatus("Adopt skipped: stop Play before adopting imported road meshes.")
		return nil
	end
	if not refreshMapId() then
		return nil
	end
	if not refreshImportPlane() then
		return nil
	end
	refreshImportScales()

	local root = Workspace:FindFirstChild(ROOT_NAME)
	if not (root and root:IsA("Model")) then
		setStatus("Adopt skipped: import the road graph JSON first so Cab87RoadEditor/RoadGraph exists.")
		return nil
	end
	local RoadGraphData, graphDataErr = getGraphDataModule()
	if graphDataErr then
		setStatus("Adopt skipped: " .. tostring(graphDataErr))
		return nil
	end
	if not RoadGraphData.hasGraph(root) then
		setStatus("Adopt skipped: import the matching road graph JSON before adopting the GLB mesh.")
		return nil
	end

	local selectedParts, importOriginCFrame, importOriginName, rootModelCount = selectedImportedMeshParts()
	if #selectedParts == 0 then
		setStatus("Select the imported GLB model or its MeshParts before adopting.")
		return nil
	end
	if rootModelCount ~= 1 then
		setStatus("Adopt skipped: select the single imported GLB model so the map can be zeroed from its import pivot.")
		return nil
	end

	setStatus("Choose the Roblox mesh manifest exported with the GLB...")
	local manifest, manifestErr = promptMeshManifest()
	if not manifest then
		setStatus("Adopt failed: " .. tostring(manifestErr))
		return nil
	end

	local exactParts, normalizedParts = indexMeshPartsByName(selectedParts)
	local usedParts = {}
	local matches = {}
	local missing = {}

	for _, chunk in ipairs(manifest.chunks or {}) do
		local part = findManifestPart(chunk, exactParts, normalizedParts, selectedParts, usedParts)
		if part then
			table.insert(matches, { chunk = chunk, part = part })
		else
			table.insert(missing, tostring(chunk.name or "?"))
		end
	end

	if #missing > 0 then
		setStatus(string.format(
			"Adopt failed: selected import is missing %d manifest chunks. First missing: %s",
			#missing,
			table.concat(firstListValues(missing, 5), ", ")
		))
		return nil
	end

	local coordinateTransform = inferImportedCoordinateTransform(matches, importOriginCFrame)

	ChangeHistoryService:SetWaypoint("cab87 road graph before imported mesh adopt")
	local transformedGraphPoints, graphTransformStatus = transformGraphToImportedCoordinates(root, RoadGraphData, coordinateTransform)
	local importedMarkerBounds = getSelectedPartsBounds(selectedParts)
	local transformedImportedMarkers = normalizeMarkersInImportedBounds(root, importOriginCFrame, importedMarkerBounds)
	local transformedGraphMarkers = if graphTransformStatus == "applied"
		then transformGraphCoordinateMarkers(root, coordinateTransform)
		else 0
	local transformedMarkers = transformedImportedMarkers + transformedGraphMarkers
	clearChild(root, BAKED_RUNTIME_BUILDING_NAME)

	local bakedRoot = Instance.new("Model")
	bakedRoot.Name = BAKED_RUNTIME_BUILDING_NAME
	bakedRoot:SetAttribute("MapId", mapId)
	bakedRoot:SetAttribute("BakedRoadGraphRuntime", true)
	bakedRoot:SetAttribute("BakeMode", "importedGlbManifest")
	bakedRoot:SetAttribute("MeshManifestSchema", manifest.schema)
	bakedRoot:SetAttribute("MeshManifestVersion", manifest.version)
	setBakeScaleAttributes(bakedRoot)
	setCoordinateTransformAttributes(bakedRoot, coordinateTransform)
	bakedRoot.Parent = root

	local surfacesFolder = createFolder(bakedRoot, BAKED_SURFACES_NAME)
	surfacesFolder:SetAttribute("MapId", mapId)
	surfacesFolder:SetAttribute("GeneratedBy", BAKED_MESH_GENERATOR_NAME)
	surfacesFolder:SetAttribute("MeshMode", "importedGlbManifest")

	local collisionFolder = createFolder(bakedRoot, BAKED_COLLISION_NAME)
	collisionFolder:SetAttribute("MapId", mapId)
	collisionFolder:SetAttribute("GeneratedBy", BAKED_MESH_GENERATOR_NAME)
	collisionFolder:SetAttribute("MeshMode", "importedGlbManifest")
	collisionFolder:SetAttribute(
		COLLISION_VERTICAL_CHUNK_SIZE_ATTR,
		tonumber(manifestSetting(manifest, "collisionVerticalChunkSize")) or nil
	)

	local minimapFolder = createFolder(bakedRoot, MINIMAP_ROAD_MESH_NAME)
	minimapFolder:SetAttribute("MapId", mapId)
	minimapFolder:SetAttribute("BakedMinimapRoadMesh", true)
	minimapFolder:SetAttribute("GeneratedBy", MINIMAP_MESH_GENERATOR_NAME)
	minimapFolder:SetAttribute("Version", MINIMAP_MESH_VERSION)
	minimapFolder:SetAttribute("MeshMode", "importedGlbManifest")
	minimapFolder:SetAttribute("ChunkSize", tonumber(manifestSetting(manifest, "chunkSize")) or nil)

	local surfaceParts = 0
	local collisionParts = 0
	local minimapParts = 0
	local totalTriangles = 0
	local roadTriangles = 0
	local sidewalkTriangles = 0
	local crosswalkTriangles = 0
	local polygonFillTriangles = 0

	for _, match in ipairs(matches) do
		local chunk = match.chunk
		local part = match.part
		local isCollision = tostring(chunk.kind or "surface") == "collision"
		applyImportedMeshTransform(part, importOriginCFrame)
		applyManifestPartOptions(part, chunk, mapId, manifest)
		part.Parent = if isCollision then collisionFolder else surfacesFolder

		local triangleCount = tonumber(chunk.triangleCount) or 0
		totalTriangles += triangleCount
		if isCollision then
			collisionParts += 1
		else
			surfaceParts += 1
			local surfaceType = tostring(chunk.surfaceType or "")
			if surfaceType == "road" then
				roadTriangles += triangleCount
			elseif surfaceType == "sidewalk" then
				sidewalkTriangles += triangleCount
			elseif surfaceType == "crosswalk" then
				crosswalkTriangles += triangleCount
			elseif surfaceType == "polygonFill" then
				polygonFillTriangles += triangleCount
			end
			if surfaceType == "road" or surfaceType == "crosswalk" then
				cloneMinimapPart(part, minimapFolder, mapId)
				minimapParts += 1
			end
		end
	end

	if collisionParts == 0 then
		bakedRoot:Destroy()
		setStatus("Adopt failed: manifest did not provide collision chunks.")
		return nil
	end

	hideDefaultBaseplate()
	clearChild(root, BAKED_RUNTIME_NAME)
	clearChild(root, BAKED_SURFACES_NAME)
	clearChild(root, BAKED_COLLISION_NAME)
	clearChild(root, MINIMAP_ROAD_MESH_NAME)
	clearChild(root, ASSETS_NAME)
	clearPreviewMeshes(root)
	bakedRoot.Name = BAKED_RUNTIME_NAME

	local assets = getOrCreateAssetsFolder(root)
	setBakeScaleAttributes(assets)
	assets:SetAttribute("Stale", false)
	assets:SetAttribute("BakeMode", "importedGlbManifest")
	assets:SetAttribute("LastBakeUnix", os.time())
	assets:SetAttribute("BakedPartCount", surfaceParts + collisionParts + minimapParts)
	assets:SetAttribute("PreviewPartCount", surfaceParts)
	assets:SetAttribute("CollisionPartCount", collisionParts)
	assets:SetAttribute("MinimapPartCount", minimapParts)
	assets:SetAttribute("RoadTriangles", roadTriangles)
	assets:SetAttribute("SidewalkTriangles", sidewalkTriangles)
	assets:SetAttribute("CrosswalkTriangles", crosswalkTriangles)
	assets:SetAttribute("PolygonFillTriangles", polygonFillTriangles)
	assets:SetAttribute("ManifestChunkCount", #(manifest.chunks or {}))
	assets:SetAttribute("ManifestTriangleCount", totalTriangles)
	assets:SetAttribute("ChunkSize", tonumber(manifestSetting(manifest, "chunkSize")) or nil)
	assets:SetAttribute("MaxSurfaceTriangles", tonumber(manifestSetting(manifest, "maxSurfaceTriangles")) or nil)
	assets:SetAttribute("MaxCollisionInputTriangles", tonumber(manifestSetting(manifest, "maxCollisionInputTriangles")) or nil)
	assets:SetAttribute(
		COLLISION_VERTICAL_CHUNK_SIZE_ATTR,
		tonumber(manifestSetting(manifest, "collisionVerticalChunkSize")) or nil
	)
	assets:SetAttribute("ImportOriginModel", tostring(importOriginName or ""))
	assets:SetAttribute("TransformedMarkerCount", transformedMarkers)
	assets:SetAttribute("TransformedImportedMarkerCount", transformedImportedMarkers)
	assets:SetAttribute("TransformedGraphMarkerCount", transformedGraphMarkers)
	assets:SetAttribute("TransformedGraphPointCount", transformedGraphPoints)
	assets:SetAttribute("GraphCoordinateTransformStatus", tostring(graphTransformStatus or ""))
	setCoordinateTransformAttributes(assets, coordinateTransform)
	if importOriginCFrame then
		assets:SetAttribute("ImportOriginX", importOriginCFrame.Position.X)
		assets:SetAttribute("ImportOriginY", importOriginCFrame.Position.Y)
		assets:SetAttribute("ImportOriginZ", importOriginCFrame.Position.Z)
	end

	surfacesFolder:SetAttribute("SurfacePartCount", surfaceParts)
	collisionFolder:SetAttribute("CollisionPartCount", collisionParts)
	minimapFolder:SetAttribute("SurfacePartCount", minimapParts)

	Selection:Set({ bakedRoot })
	ChangeHistoryService:SetWaypoint("cab87 road graph after imported mesh adopt")
	setStatus(string.format(
		"Adopted imported GLB mesh for map %s: %d surface parts, %d collision parts, %d minimap parts, %d transformed markers. Graph transform: %s (%s, %d graph points).",
		mapId,
		surfaceParts,
		collisionParts,
		minimapParts,
		transformedMarkers,
		coordinateTransformSummary(coordinateTransform),
		tostring(graphTransformStatus or "unknown"),
		transformedGraphPoints
	))

	return {
		surfaceParts = surfaceParts,
		collisionParts = collisionParts,
		minimapParts = minimapParts,
		graphTransformStatus = graphTransformStatus,
		transformedGraphPoints = transformedGraphPoints,
	}
end

function isPlayRunning()
	local ok, running = pcall(function()
		return RunService:IsRunning()
	end)
	return ok and running == true
end

local function bakeMeshAssets()
	if isPlayRunning() then
		setStatus("Bake skipped: stop Play before rebuilding editor preview meshes.")
		return nil
	end
	if not refreshMapId() then
		return nil
	end
	refreshImportScales()
	keepGraphAboveDefaultBaseplate()
	setStatus("Building optimized road graph preview MeshParts...")

	local RoadGraphData, RoadGraphMesher, RoadMeshBuilder, moduleErr = getSharedModules()
	if moduleErr then
		setStatus(moduleErr)
		return nil
	end

	local root = getOrCreateRoot()
	local graph = RoadGraphData.collectGraph(root)
	if not graph then
		setStatus("No valid RoadGraph found: import graph JSON first.")
		return nil
	end
	setGraphScaleAttributes(root)

	local scaledGraph = RoadGraphData.scaleGraph(graph, {
		pointScale = importPointScale,
		widthScale = importWidthScale,
	})
	if not scaledGraph then
		setStatus("Bake failed: could not apply import scale settings.")
		return nil
	end

	local meshData = RoadGraphMesher.buildNetworkMesh(scaledGraph, scaledGraph.settings)
	local errors = {}

	clearChild(root, BAKED_RUNTIME_BUILDING_NAME)

	local bakedRoot = Instance.new("Model")
	bakedRoot.Name = BAKED_RUNTIME_BUILDING_NAME
	bakedRoot:SetAttribute("MapId", mapId)
	bakedRoot:SetAttribute("BakedRoadGraphRuntime", true)
	bakedRoot:SetAttribute("BakeMode", "editorPreviewEditableMesh")
	setBakeScaleAttributes(bakedRoot)
	bakedRoot.Parent = root

	local surfaceResult = RoadMeshBuilder.createClassifiedCompactSurfaceMeshes(bakedRoot, meshData, {
		meshFolderName = BAKED_SURFACES_NAME,
		generatedBy = BAKED_MESH_GENERATOR_NAME,
	})
	for _, err in ipairs(surfaceResult.errors or {}) do
		table.insert(errors, "preview: " .. tostring(err))
	end
	if surfaceResult.meshFolder then
		surfaceResult.meshFolder:SetAttribute("MapId", mapId)
		surfaceResult.meshFolder:SetAttribute("GeneratedBy", BAKED_MESH_GENERATOR_NAME)
		surfaceResult.meshFolder:SetAttribute("MeshMode", "editorPreviewCompactSurface")
		surfaceResult.meshFolder:SetAttribute("SurfacePartCount", #surfaceResult.visibleParts)
	end

	local minimapResult = RoadMeshBuilder.createClassifiedChunkedSurfaceMeshes(bakedRoot, meshData, {
		meshFolderName = MINIMAP_ROAD_MESH_NAME,
		generatedBy = MINIMAP_MESH_GENERATOR_NAME,
		chunkSize = MINIMAP_MESH_CHUNK_STUDS,
		color = Color3.fromRGB(255, 255, 255),
		material = Enum.Material.SmoothPlastic,
		transparency = 1,
	})
	for _, err in ipairs(minimapResult.errors or {}) do
		table.insert(errors, "minimap: " .. tostring(err))
	end
	if minimapResult and minimapResult.meshFolder then
		minimapResult.meshFolder:SetAttribute("MapId", mapId)
		minimapResult.meshFolder:SetAttribute("BakedMinimapRoadMesh", true)
		minimapResult.meshFolder:SetAttribute("GeneratedBy", MINIMAP_MESH_GENERATOR_NAME)
		minimapResult.meshFolder:SetAttribute("Version", MINIMAP_MESH_VERSION)
		minimapResult.meshFolder:SetAttribute("MeshMode", "editorPreviewEditableMesh")
		minimapResult.meshFolder:SetAttribute("SurfacePartCount", #minimapResult.visibleParts)
		minimapResult.meshFolder:SetAttribute("ChunkSize", MINIMAP_MESH_CHUNK_STUDS)
		for _, part in ipairs(minimapResult.visibleParts) do
			part:SetAttribute("MapId", mapId)
			part:SetAttribute("BakedRoadGraphMesh", true)
			part:SetAttribute("BakedMinimapRoadMesh", true)
			part:SetAttribute("MinimapRoadMesh", true)
		end
	end

	local result = {
		meshFolder = surfaceResult.meshFolder,
		visibleParts = surfaceResult.visibleParts or {},
		errors = errors,
	}

	if #result.visibleParts == 0 or not minimapResult or #(minimapResult.visibleParts or {}) == 0 then
		bakedRoot:Destroy()
		local reason = #errors > 0 and table.concat(errors, " | ") or "no optimized preview/minimap mesh parts were created"
		setStatus("Bake failed: " .. reason .. ". Previous baked preview was kept.")
		return nil
	end

	hideDefaultBaseplate()
	for _, part in ipairs(result.visibleParts) do
		part:SetAttribute("MapId", mapId)
		part:SetAttribute("BakedRoadGraphMesh", true)
		part:SetAttribute("BakeMode", "editorPreviewEditableMesh")
		if part:GetAttribute("SurfaceType") == "polygonFill" then
			part:SetAttribute("BakedPolygonFillMesh", true)
		end
	end

	local hiddenEditorParts = hideStaleEditorGeometry(root, result.meshFolder)
	clearChild(root, BAKED_RUNTIME_NAME)
	clearChild(root, BAKED_SURFACES_NAME)
	clearChild(root, BAKED_COLLISION_NAME)
	clearChild(root, MINIMAP_ROAD_MESH_NAME)
	clearChild(root, ASSETS_NAME)
	bakedRoot.Name = BAKED_RUNTIME_NAME

	local assets = getOrCreateAssetsFolder(root)
	setBakeScaleAttributes(assets)
	clearPreviewMeshes(root)
	assets:SetAttribute("Stale", false)
	assets:SetAttribute("BakeMode", "editorPreviewEditableMesh")
	assets:SetAttribute("LastBakeUnix", os.time())
	assets:SetAttribute("BakedPartCount", #result.visibleParts + (minimapResult and #minimapResult.visibleParts or 0))
	assets:SetAttribute("PreviewPartCount", #result.visibleParts)
	assets:SetAttribute("MinimapPartCount", minimapResult and #minimapResult.visibleParts or 0)
	assets:SetAttribute("RoadTriangles", #(meshData.roadTriangles or {}))
	assets:SetAttribute("SidewalkTriangles", #(meshData.sidewalkTriangles or {}))
	assets:SetAttribute("CrosswalkTriangles", #(meshData.crosswalkTriangles or {}))
	assets:SetAttribute("PolygonFillTriangles", countPolygonFillTriangles(meshData))
	assets:SetAttribute("ChunkSize", BAKE_CHUNK_SIZE_STUDS)
	assets:SetAttribute("MaxSurfaceTriangles", BAKE_MAX_SURFACE_TRIANGLES)
	assets:SetAttribute("MaxCollisionInputTriangles", BAKE_MAX_COLLISION_INPUT_TRIANGLES)
	assets:SetAttribute("HiddenEditorPreviewPartCount", hiddenEditorParts)

	setStatus(string.format(
		"Built map %s at %s: %d optimized preview MeshParts, %d minimap parts, hid %d stale editor parts. Play regenerates runtime collision from RoadGraph data.%s",
		mapId,
		scaleSummary(),
		#result.visibleParts,
		minimapResult and #minimapResult.visibleParts or 0,
		hiddenEditorParts,
		#errors > 0 and ("\nWarnings: " .. table.concat(errors, " | ")) or ""
	))
	Selection:Set({ bakedRoot })

	return {
		bakedParts = #result.visibleParts,
		minimapParts = minimapResult and #minimapResult.visibleParts or 0,
		pointScale = importPointScale,
		widthScale = importWidthScale,
		bakeMode = "editorPreviewEditableMesh",
		errors = errors,
	}
end

local function forkAsNewMap()
	local root = getOrCreateRoot()
	local baseMapId = sanitizeMapId(mapIdInput.Text)
	local forkedMapId = string.format("%s_%d", baseMapId, os.time())
	mapIdInput.Text = forkedMapId
	refreshMapId()

	clearChild(root, ASSETS_NAME)
	clearChild(root, BAKED_RUNTIME_NAME)
	clearChild(root, BAKED_SURFACES_NAME)
	clearChild(root, BAKED_COLLISION_NAME)
	clearChild(root, MINIMAP_ROAD_MESH_NAME)
	setStatus("Forked graph as new map ID " .. mapId .. ". Bake Runtime Geometry will create separate baked output for this map.")
end

local function clearAuthoredRoadEditorRoot()
	local root = getOrCreateRoot()
	for _, child in ipairs(root:GetChildren()) do
		child:Destroy()
	end
	for attributeName in pairs(root:GetAttributes()) do
		root:SetAttribute(attributeName, nil)
	end
	Selection:Set({ root })
	setStatus("Cleared all authored road data. Import graph or curve JSON and bake when ready.")
end

local function importGraphJson()
	if not refreshImportPlane() then
		return
	end
	refreshImportScales()
	keepGraphAboveDefaultBaseplate()
	setStatus("Importing road graph JSON...")

	local RoadGraphData, moduleErr = getGraphDataModule()
	if moduleErr then
		setStatus(moduleErr)
		return
	end

	local okFile, fileOrErr = pcall(function()
		return StudioService:PromptImportFileAsync(IMPORT_FILE_FILTER)
	end)
	if not okFile then
		setStatus("Import failed to open file picker: " .. tostring(fileOrErr))
		return
	end
	if not fileOrErr then
		setStatus("Graph import canceled.")
		return
	end

	local contents, readErr = readImportedFileContents(fileOrErr)
	if not contents then
		setStatus("Graph import failed: " .. tostring(readErr))
		return
	end

	local graph, parseErr = RoadGraphData.decodeJson(contents, {
		planeY = importPlaneY,
	})
	if not graph then
		setStatus("Graph import failed: " .. tostring(parseErr))
		return
	end
	graph.importPointScale = importPointScale
	graph.importWidthScale = importWidthScale

	ChangeHistoryService:SetWaypoint("cab87 road graph before import")
	local root = getOrCreateRoot()
	RoadGraphData.writeGraph(root, graph)
	markBakedAssetsStale(root, "graph imported")
	ChangeHistoryService:SetWaypoint("cab87 road graph after import")
	setStatus(string.format(
		"Imported graph data: %d nodes, %d edges at Y=%s, %s. Import the exported GLB, select it, then click Adopt Imported GLB Mesh.",
		#graph.nodes,
		#graph.edges,
		tostring(importPlaneY),
		scaleSummary()
	))
end

local function raycastFromCamera(maxDistance)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, 0
	end

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * (maxDistance or 4000)
	local root = getOrCreateRoot()
	local exclude = {}
	for _, name in ipairs({
		MARKERS_NAME,
		"Splines",
		"RoadPoints",
		"Junctions",
		"WireframeDisplay",
		"RoadGraph",
		ASSETS_NAME,
	}) do
		local child = root:FindFirstChild(name)
		if child then
			table.insert(exclude, child)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(origin, direction, params)
	local yaw = math.atan2(camera.CFrame.LookVector.X, camera.CFrame.LookVector.Z)
	if result then
		return result.Position, yaw
	end
	return origin + direction.Unit * 100, yaw
end

local function setMarker(name, markerType, position, yaw, color)
	local markersFolder = getOrCreateMarkersFolder()
	local marker = markersFolder:FindFirstChild(name)
	if marker and not marker:IsA("Part") then
		marker:Destroy()
		marker = nil
	end
	if not marker then
		marker = Instance.new("Part")
		marker.Name = name
		marker.Parent = markersFolder
	end

	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = true
	marker.Size = Vector3.new(10, 2, 10)
	marker.Color = color
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.15
	marker.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0)
	marker:SetAttribute(MARKER_TYPE_ATTR, markerType)
	marker:SetAttribute("Cab87MarkerDescription", MARKER_DESCRIPTIONS[markerType] or markerType)
	return marker
end

local function setMarkerFromCamera(name, markerType, color, yOffset)
	local hitPosition, yaw = raycastFromCamera(4000)
	if not hitPosition then
		setStatus("No camera hit was available for marker placement.")
		return
	end

	ChangeHistoryService:SetWaypoint("cab87 road graph before marker")
	local marker = setMarker(name, markerType, hitPosition + Vector3.new(0, yOffset or 0, 0), yaw, color)
	Selection:Set({ marker })
	ChangeHistoryService:SetWaypoint("cab87 road graph after marker")
	setStatus("Set marker: " .. name)
end

local function selectMarker(name)
	local folder = getOrCreateMarkersFolder()
	local marker = folder:FindFirstChild(name)
	if marker and marker:IsA("BasePart") then
		Selection:Set({ marker })
		setStatus("Selected marker: " .. name)
	else
		setStatus("Marker not found: " .. name)
	end
end

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
end)

importPlaneInput.FocusLost:Connect(refreshImportPlane)
mapIdInput.FocusLost:Connect(refreshMapId)
importButton.MouseButton1Click:Connect(function()
	local ok, err = pcall(importGraphJson)
	if not ok then
		setStatus("Import failed: " .. tostring(err))
	end
end)
bakeAssetsButton.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 road graph before bake")
	local ok, err = pcall(bakeMeshAssets)
	ChangeHistoryService:SetWaypoint("cab87 road graph after bake")
	if not ok then
		setStatus("Bake failed: " .. tostring(err))
	end
end)
adoptImportedMeshButton.MouseButton1Click:Connect(function()
	local ok, err = pcall(adoptImportedMeshFromManifest)
	if not ok then
		setStatus("Adopt failed: " .. tostring(err))
	end
end)
forkMapButton.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 road graph before fork")
	forkAsNewMap()
	ChangeHistoryService:SetWaypoint("cab87 road graph after fork")
end)
clearAllButton.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 road graph before clear all")
	clearAuthoredRoadEditorRoot()
	ChangeHistoryService:SetWaypoint("cab87 road graph after clear all")
end)
setCabSpawnButton.MouseButton1Click:Connect(function()
	setMarkerFromCamera(CAB_COMPANY_NODE_NAME, "CabCompany", Color3.fromRGB(90, 255, 150), 2.3)
end)
addCabSpawnToolbarButton.Click:Connect(function()
	setMarkerFromCamera(CAB_COMPANY_NODE_NAME, "CabCompany", Color3.fromRGB(90, 255, 150), 2.3)
end)
setCabRefuelButton.MouseButton1Click:Connect(function()
	setMarkerFromCamera(CAB_REFUEL_NODE_NAME, "CabRefuel", Color3.fromRGB(95, 255, 160), 0.35)
end)
addCabRefuelToolbarButton.Click:Connect(function()
	setMarkerFromCamera(CAB_REFUEL_NODE_NAME, "CabRefuel", Color3.fromRGB(95, 255, 160), 0.35)
end)
setCabServiceButton.MouseButton1Click:Connect(function()
	setMarkerFromCamera(CAB_SERVICE_NODE_NAME, "CabService", Color3.fromRGB(116, 209, 255), 0.35)
end)
addCabServiceToolbarButton.Click:Connect(function()
	setMarkerFromCamera(CAB_SERVICE_NODE_NAME, "CabService", Color3.fromRGB(116, 209, 255), 0.35)
end)
addPlayerSpawnToolbarButton.Click:Connect(function()
	setMarkerFromCamera(PLAYER_SPAWN_NAME, "PlayerSpawn", Color3.fromRGB(115, 214, 255), 0)
end)
setPlayerSpawnButton.MouseButton1Click:Connect(function()
	setMarkerFromCamera(PLAYER_SPAWN_NAME, "PlayerSpawn", Color3.fromRGB(115, 214, 255), 0)
end)
selectCabSpawnButton.MouseButton1Click:Connect(function()
	selectMarker(CAB_COMPANY_NODE_NAME)
end)
selectCabSpawnToolbarButton.Click:Connect(function()
	selectMarker(CAB_COMPANY_NODE_NAME)
end)
selectCabRefuelButton.MouseButton1Click:Connect(function()
	selectMarker(CAB_REFUEL_NODE_NAME)
end)
selectCabServiceButton.MouseButton1Click:Connect(function()
	selectMarker(CAB_SERVICE_NODE_NAME)
end)
selectPlayerSpawnButton.MouseButton1Click:Connect(function()
	selectMarker(PLAYER_SPAWN_NAME)
end)

local function autoReloadPreviewMeshes()
	task.wait(AUTO_RELOAD_DELAY_SECONDS)
	if isPlayRunning() then
		return
	end

	for attempt = 1, AUTO_RELOAD_MAX_ATTEMPTS do
		if isPlayRunning() then
			return
		end

		local root = Workspace:FindFirstChild(ROOT_NAME)
		local graphFolder = root and root:FindFirstChild(ROAD_GRAPH_NAME)
		if not graphFolder then
			return
		end
		local assets = root:FindFirstChild(ASSETS_NAME)
		if assets and assets:GetAttribute("BakeMode") == "importedGlbManifest" and assets:GetAttribute("Stale") ~= true then
			setStatus("Loaded imported GLB road mesh bake. Runtime will use the adopted MeshParts.")
			return
		end

		local RoadGraphData, _RoadGraphMesher, _RoadMeshBuilder, moduleErr = getSharedModules()
		if not moduleErr then
			local graph = RoadGraphData.collectGraph(root)
			if not graph then
				return
			end

			applyGraphImportScales(graph)
			setStatus("Reloading road graph preview mesh from saved graph...")
			if isPlayRunning() then
				return
			end
			local ok, resultOrErr = pcall(bakeMeshAssets)
			if not ok then
				setStatus("Auto preview reload failed: " .. tostring(resultOrErr))
			elseif resultOrErr then
				setStatus(string.format(
					"Reloaded road graph preview mesh: %d optimized preview MeshParts at %s.",
					resultOrErr.bakedParts or 0,
					scaleSummary()
				))
			end
			return
		end

		if attempt == AUTO_RELOAD_MAX_ATTEMPTS then
			setStatus("Auto preview reload skipped: " .. tostring(moduleErr))
			return
		end
		task.wait(AUTO_RELOAD_RETRY_SECONDS)
	end
end

task.defer(autoReloadPreviewMeshes)
