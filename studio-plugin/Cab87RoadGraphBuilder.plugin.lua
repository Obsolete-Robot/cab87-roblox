-- Cab87 Studio plugin: graph road importer/builder.
-- Install to:
--   %LOCALAPPDATA%\Roblox\Plugins\Cab87RoadGraphBuilder.plugin.lua

local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local StudioService = game:GetService("StudioService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ROOT_NAME = "Cab87RoadEditor"
local MARKERS_NAME = "Markers"
local MARKER_TYPE_ATTR = "Cab87MarkerType"
local CAB_COMPANY_NODE_NAME = "CabCompanyNode"
local CAB_REFUEL_NODE_NAME = "CabRefuelPoint"
local CAB_SERVICE_NODE_NAME = "CabServicePoint"
local PLAYER_SPAWN_NAME = "PlayerSpawnPoint"
local ROAD_GRAPH_SURFACES_NAME = "RoadGraphSurfaces"
local ROAD_GRAPH_COLLISION_NAME = "RoadGraphCollision"
local BAKED_RUNTIME_NAME = "RoadGraphBakedRuntime"
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
local IMPORT_PLANE_Y_SETTING = "cab87_road_graph_import_plane_y"
local IMPORT_POINT_SCALE_SETTING = "cab87_road_graph_import_point_scale"
local IMPORT_WIDTH_SCALE_SETTING = "cab87_road_graph_import_width_scale"
local MAP_ID_SETTING = "cab87_road_graph_map_id"
local DEFAULT_MAP_ID = "cab87_map"
local DEFAULT_IMPORT_SCALE = 1
local MIN_IMPORT_SCALE = 0.1
local MAX_IMPORT_SCALE = 4
local IMPORT_SCALE_STEP = 0.05

local MARKER_DESCRIPTIONS = {
	CabCompany = "Cab spawn marker",
	CabRefuel = "Free refuel marker",
	CabService = "Cab recover and garage/shop marker",
	PlayerSpawn = "Player spawn marker",
}

local BAKE_SPECS = {
	{
		key = "roadSurface",
		assetPrefix = "RoadSurface",
		triangleSet = "roadTriangles",
		partName = "RoadSurface",
		folder = "surface",
		surfaceType = "road",
		color = Color3.fromRGB(28, 28, 32),
		material = Enum.Material.Asphalt,
	},
	{
		key = "sidewalkSurface",
		assetPrefix = "SidewalkSurface",
		triangleSet = "sidewalkTriangles",
		partName = "SidewalkSurface",
		folder = "surface",
		surfaceType = "sidewalk",
		color = Color3.fromRGB(116, 116, 108),
		material = Enum.Material.Concrete,
	},
	{
		key = "crosswalkSurface",
		assetPrefix = "CrosswalkSurface",
		triangleSet = "crosswalkTriangles",
		partName = "CrosswalkSurface",
		folder = "surface",
		surfaceType = "crosswalk",
		color = Color3.fromRGB(231, 226, 204),
		material = Enum.Material.SmoothPlastic,
	},
	{
		key = "roadCollision",
		assetPrefix = "RoadCollision",
		triangleSet = "roadTriangles",
		partName = "RoadCollision",
		folder = "collision",
		surfaceType = "road",
		color = Color3.fromRGB(28, 28, 32),
		material = Enum.Material.Asphalt,
		collision = true,
	},
	{
		key = "sidewalkCollision",
		assetPrefix = "SidewalkCollision",
		triangleSet = "sidewalkTriangles",
		partName = "SidewalkCollision",
		folder = "collision",
		surfaceType = "sidewalk",
		color = Color3.fromRGB(116, 116, 108),
		material = Enum.Material.Concrete,
		collision = true,
	},
	{
		key = "crosswalkCollision",
		assetPrefix = "CrosswalkCollision",
		triangleSet = "crosswalkTriangles",
		partName = "CrosswalkCollision",
		folder = "collision",
		surfaceType = "crosswalk",
		color = Color3.fromRGB(231, 226, 204),
		material = Enum.Material.SmoothPlastic,
		collision = true,
	},
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
		local width = math.max(track.AbsoluteSize.X, 1)
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

local importPlaneY = tonumber(plugin:GetSetting(IMPORT_PLANE_Y_SETTING)) or 0
local importPointScale = sanitizeImportScale(plugin:GetSetting(IMPORT_POINT_SCALE_SETTING))
local importWidthScale = sanitizeImportScale(plugin:GetSetting(IMPORT_WIDTH_SCALE_SETTING))
local mapId = tostring(plugin:GetSetting(MAP_ID_SETTING) or DEFAULT_MAP_ID)
local importPlaneInput = makeInputRow("Import Y", tostring(importPlaneY))
local importPointScaleSlider = makeSliderRow("Point Scale", importPointScale)
local importWidthScaleSlider = makeSliderRow("Width Scale", importWidthScale)
local mapIdInput = makeInputRow("Map ID", mapId)
local importButton = makeButton("Import Graph JSON")
local bakeAssetsButton = makeButton("Bake Runtime Geometry")
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
	status.Text = tostring(message)
end

local function stripUtf8Bom(text)
	if string.byte(text, 1) == 239 and string.byte(text, 2) == 187 and string.byte(text, 3) == 191 then
		return string.sub(text, 4)
	end
	return text
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

	return require(graphDataModule), require(mesherModule), require(meshBuilderModule), nil
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

local function refreshImportScales()
	importPointScale = sanitizeImportScale(importPointScaleSlider.getValue())
	importWidthScale = sanitizeImportScale(importWidthScaleSlider.getValue())
	importPointScaleSlider.setValue(importPointScale)
	importWidthScaleSlider.setValue(importWidthScale)
	plugin:SetSetting(IMPORT_POINT_SCALE_SETTING, importPointScale)
	plugin:SetSetting(IMPORT_WIDTH_SCALE_SETTING, importWidthScale)
	return true
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

local function createFolder(parent, name)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function setBakeScaleAttributes(instance)
	if not instance then
		return
	end
	instance:SetAttribute("PointScale", importPointScale)
	instance:SetAttribute("WidthScale", importWidthScale)
end

local function assetAttr(spec, suffix)
	return spec.assetPrefix .. suffix
end

local function clearAssetManifestEntry(assets, spec)
	assets:SetAttribute(assetAttr(spec, "AssetId"), nil)
	assets:SetAttribute(assetAttr(spec, "Version"), nil)
	assets:SetAttribute(assetAttr(spec, "TriangleCount"), nil)
	assets:SetAttribute(assetAttr(spec, "BakeMode"), nil)
end

local function isAssetUploadUnavailable(message)
	local text = string.lower(tostring(message or ""))
	return string.find(text, "not available", 1, true) ~= nil
		or string.find(text, "createassetasync", 1, true) ~= nil
			and string.find(text, "not available", 1, true) ~= nil
end

local function getCreatorRequestParameters(name, description, includeName)
	local request = {}
	local creatorId = tonumber(game.CreatorId)
	if creatorId and creatorId > 0 then
		request.CreatorId = creatorId
		if game.CreatorType == Enum.CreatorType.Group then
			request.CreatorType = Enum.AssetCreatorType.Group
		else
			request.CreatorType = Enum.AssetCreatorType.User
		end
	end
	if includeName then
		request.Name = name
		request.Description = description
	end
	return request
end

local function uploadOrUpdateMeshAsset(assets, spec, editableMesh, triangleCount)
	local existingAssetId = tonumber(assets:GetAttribute(assetAttr(spec, "AssetId")))
	local assetName = string.format("cab87_%s_%s", mapId, spec.assetPrefix)
	local description = string.format("Cab87 road graph mesh %s for map %s", spec.assetPrefix, mapId)

	if existingAssetId then
		local request = getCreatorRequestParameters(assetName, description, false)
		local ok, result, versionOrErr = pcall(function()
			return AssetService:CreateAssetVersionAsync(editableMesh, Enum.AssetType.Mesh, existingAssetId, request)
		end)
		if not ok then
			return nil, "CreateAssetVersionAsync failed: " .. tostring(result)
		end
		if result ~= Enum.CreateAssetResult.Success then
			return nil, string.format("asset update failed: %s %s", tostring(result), tostring(versionOrErr))
		end

		assets:SetAttribute(assetAttr(spec, "Version"), tonumber(versionOrErr) or 0)
		assets:SetAttribute(assetAttr(spec, "TriangleCount"), triangleCount)
		assets:SetAttribute(assetAttr(spec, "BakeMode"), "updated")
		return existingAssetId, "updated", versionOrErr
	end

	local request = getCreatorRequestParameters(assetName, description, true)
	local ok, result, assetIdOrErr = pcall(function()
		return AssetService:CreateAssetAsync(editableMesh, Enum.AssetType.Mesh, request)
	end)
	if not ok then
		return nil, "CreateAssetAsync failed: " .. tostring(result)
	end
	if result ~= Enum.CreateAssetResult.Success then
		return nil, string.format("asset create failed: %s %s", tostring(result), tostring(assetIdOrErr))
	end

	assets:SetAttribute(assetAttr(spec, "AssetId"), tonumber(assetIdOrErr))
	assets:SetAttribute(assetAttr(spec, "Version"), 0)
	assets:SetAttribute(assetAttr(spec, "TriangleCount"), triangleCount)
	assets:SetAttribute(assetAttr(spec, "BakeMode"), "created")
	return tonumber(assetIdOrErr), "created", nil
end

local function createBakedPart(RoadMeshBuilder, parent, spec, assetId, triangleCount)
	local part, err = RoadMeshBuilder.createMeshPartFromAssetId(parent, spec.partName, assetId, {
		color = spec.color,
		material = spec.material,
		surfaceType = spec.surfaceType,
		generatedBy = BAKED_MESH_GENERATOR_NAME,
		canCollide = spec.collision == true,
		canQuery = spec.collision == true,
		canTouch = false,
		transparency = if spec.collision then 1 else 0,
		castShadow = false,
		driveSurface = spec.collision == true,
		triangleCount = triangleCount,
	})
	if not part then
		return nil, err
	end

	part:SetAttribute("MapId", mapId)
	part:SetAttribute("MeshAssetId", assetId)
	part:SetAttribute("BakedRoadGraphMesh", true)
	return part, nil
end

local function createBakedMinimapRoadMesh(parent, meshData, RoadMeshBuilder)
	clearChild(parent, MINIMAP_ROAD_MESH_NAME)

	local result = RoadMeshBuilder.createClassifiedChunkedSurfaceMeshes(parent, meshData, {
		meshFolderName = MINIMAP_ROAD_MESH_NAME,
		generatedBy = MINIMAP_MESH_GENERATOR_NAME,
		chunkSize = MINIMAP_MESH_CHUNK_STUDS,
		color = Color3.fromRGB(255, 255, 255),
		material = Enum.Material.SmoothPlastic,
		transparency = 1,
	})
	local folder = result.meshFolder
	if not folder then
		return nil, "minimap mesh produced no parts"
	end

	if #result.visibleParts > MINIMAP_MESH_MAX_PARTS then
		local partCount = #result.visibleParts
		folder:Destroy()
		return nil, string.format(
			"minimap mesh produced %d parts, above limit %d",
			partCount,
			MINIMAP_MESH_MAX_PARTS
		)
	end

	for _, part in ipairs(result.visibleParts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Transparency = 1
		part.Color = Color3.fromRGB(255, 255, 255)
		part.Material = Enum.Material.SmoothPlastic
		part:SetAttribute("MapId", mapId)
		part:SetAttribute("BakedRoadGraphMesh", true)
		part:SetAttribute("BakedMinimapRoadMesh", true)
		part:SetAttribute("MinimapRoadMesh", true)
	end

	folder:SetAttribute("MapId", mapId)
	folder:SetAttribute("BakedMinimapRoadMesh", true)
	folder:SetAttribute("GeneratedBy", MINIMAP_MESH_GENERATOR_NAME)
	folder:SetAttribute("Version", MINIMAP_MESH_VERSION)
	folder:SetAttribute("MeshMode", "bakedGraphSurfaces")
	folder:SetAttribute("SurfacePartCount", #result.visibleParts)
	folder:SetAttribute("ChunkSize", MINIMAP_MESH_CHUNK_STUDS)
	if #result.errors > 0 then
		return result, table.concat(result.errors, " | ")
	end
	return result, nil
end

local function createPrimitiveBakeFallback(root, meshData, RoadMeshBuilder, reason)
	clearChild(root, BAKED_RUNTIME_NAME)
	clearChild(root, BAKED_SURFACES_NAME)
	clearChild(root, BAKED_COLLISION_NAME)
	clearChild(root, MINIMAP_ROAD_MESH_NAME)

	local bakedRoot = Instance.new("Model")
	bakedRoot.Name = BAKED_RUNTIME_NAME
	bakedRoot:SetAttribute("MapId", mapId)
	bakedRoot:SetAttribute("BakedRoadGraphRuntime", true)
	bakedRoot:SetAttribute("BakeMode", "primitive")
	bakedRoot:SetAttribute("UploadReason", tostring(reason or "asset upload unavailable"))
	setBakeScaleAttributes(bakedRoot)
	bakedRoot.Parent = root

	local result = RoadMeshBuilder.createClassifiedPrimitiveMeshes(bakedRoot, meshData, {
		meshFolderName = BAKED_SURFACES_NAME,
		collisionFolderName = BAKED_COLLISION_NAME,
		generatedBy = BAKED_MESH_GENERATOR_NAME,
		collisionThickness = 0.2,
		visualThickness = 0.04,
	})

	if #result.visibleParts == 0 or #result.collisionParts == 0 then
		bakedRoot:Destroy()
		return nil, "primitive fallback produced no usable geometry"
	end

	for _, part in ipairs(result.visibleParts) do
		part:SetAttribute("MapId", mapId)
		part:SetAttribute("BakedRoadGraphMesh", true)
		part:SetAttribute("BakeMode", "primitive")
	end
	for _, part in ipairs(result.collisionParts) do
		part:SetAttribute("MapId", mapId)
		part:SetAttribute("BakedRoadGraphMesh", true)
		part:SetAttribute("BakeMode", "primitive")
		part:SetAttribute("DriveSurface", true)
	end

	local minimapResult, minimapErr = createBakedMinimapRoadMesh(bakedRoot, meshData, RoadMeshBuilder)

	local assets = getOrCreateAssetsFolder(root)
	setBakeScaleAttributes(assets)
	assets:SetAttribute("Stale", false)
	assets:SetAttribute("BakeMode", "primitive")
	assets:SetAttribute("PrimitiveFallbackReason", tostring(reason or "asset upload unavailable"))
	assets:SetAttribute("LastBakeUnix", os.time())
	assets:SetAttribute("BakedPartCount", #result.visibleParts + #result.collisionParts)
	assets:SetAttribute("MinimapPartCount", minimapResult and #minimapResult.visibleParts or 0)
	assets:SetAttribute("RoadTriangles", #(meshData.roadTriangles or {}))
	assets:SetAttribute("SidewalkTriangles", #(meshData.sidewalkTriangles or {}))
	assets:SetAttribute("CrosswalkTriangles", #(meshData.crosswalkTriangles or {}))

	clearPreviewMeshes(root)
	setStatus(string.format(
		"Asset upload API unavailable, so baked %s at %s as saved WedgePart geometry: %d visible parts, %d collision parts, %d minimap parts. No package or mesh asset IDs were uploaded. Save the place; runtime will use this persistent fallback.%s",
		BAKED_RUNTIME_NAME,
		scaleSummary(),
		#result.visibleParts,
		#result.collisionParts,
		minimapResult and #minimapResult.visibleParts or 0,
		minimapErr and ("\nMinimap warning: " .. tostring(minimapErr)) or ""
	))
	result.bakeMode = "primitive"
	return result, nil
end

local function bakeMeshAssets()
	if not refreshMapId() then
		return nil
	end
	refreshImportScales()

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

	local scaledGraph = RoadGraphData.scaleGraph(graph, {
		pointScale = importPointScale,
		widthScale = importWidthScale,
	})
	if not scaledGraph then
		setStatus("Bake failed: could not apply import scale settings.")
		return nil
	end

	local meshData = RoadGraphMesher.buildNetworkMesh(scaledGraph, scaledGraph.settings)
	local assets = getOrCreateAssetsFolder(root)
	setBakeScaleAttributes(assets)
	local oldBakedRuntime = root:FindFirstChild(BAKED_RUNTIME_NAME)
	local oldBakedSurfaces = root:FindFirstChild(BAKED_SURFACES_NAME)
	local oldBakedCollision = root:FindFirstChild(BAKED_COLLISION_NAME)
	local oldMinimapMesh = root:FindFirstChild(MINIMAP_ROAD_MESH_NAME)
	if oldBakedRuntime then
		oldBakedRuntime:Destroy()
	end
	if oldBakedSurfaces then
		oldBakedSurfaces:Destroy()
	end
	if oldBakedCollision then
		oldBakedCollision:Destroy()
	end
	if oldMinimapMesh then
		oldMinimapMesh:Destroy()
	end
	local bakedSurfaces = createFolder(root, BAKED_SURFACES_NAME)
	local bakedCollision = createFolder(root, BAKED_COLLISION_NAME)
	setBakeScaleAttributes(bakedSurfaces)
	setBakeScaleAttributes(bakedCollision)

	local created = 0
	local updated = 0
	local bakedParts = 0
	local errors = {}
	local uploadUnavailableReason = nil
	for _, spec in ipairs(BAKE_SPECS) do
		local triangles = meshData[spec.triangleSet] or {}
		if #triangles == 0 then
			clearAssetManifestEntry(assets, spec)
			continue
		end

		local state, stateErr
		if spec.collision then
			state, stateErr = RoadMeshBuilder.createCollisionState(triangles, {
				thickness = 0.2,
				surfaceOffset = 0,
			})
		else
			state, stateErr = RoadMeshBuilder.createSurfaceState(triangles)
		end

		if not state or state.faces == 0 then
			table.insert(errors, spec.assetPrefix .. ": " .. tostring(stateErr or "no faces"))
			continue
		end

		local assetId, modeOrErr = uploadOrUpdateMeshAsset(assets, spec, state.mesh, state.faces)
		if not assetId then
			if isAssetUploadUnavailable(modeOrErr) then
				uploadUnavailableReason = modeOrErr
				break
			end
			table.insert(errors, spec.assetPrefix .. ": " .. tostring(modeOrErr))
			continue
		end

		if modeOrErr == "created" then
			created += 1
		else
			updated += 1
		end

		local parent = if spec.folder == "collision" then bakedCollision else bakedSurfaces
		local part, partErr = createBakedPart(RoadMeshBuilder, parent, spec, assetId, state.faces)
		if part then
			bakedParts += 1
		else
			table.insert(errors, spec.assetPrefix .. " part: " .. tostring(partErr))
		end
	end

	if uploadUnavailableReason then
		bakedSurfaces:Destroy()
		bakedCollision:Destroy()
		return createPrimitiveBakeFallback(root, meshData, RoadMeshBuilder, uploadUnavailableReason)
	end

	if bakedParts == 0 then
		bakedSurfaces:Destroy()
		bakedCollision:Destroy()
		setStatus("Bake failed: " .. (#errors > 0 and table.concat(errors, " | ") or "no mesh parts were created"))
		return nil
	end

	local minimapResult, minimapErr = createBakedMinimapRoadMesh(root, meshData, RoadMeshBuilder)
	if minimapErr then
		table.insert(errors, "minimap: " .. tostring(minimapErr))
	end

	clearPreviewMeshes(root)
	assets:SetAttribute("Stale", false)
	assets:SetAttribute("BakeMode", "meshAsset")
	assets:SetAttribute("PrimitiveFallbackReason", nil)
	assets:SetAttribute("LastBakeUnix", os.time())
	assets:SetAttribute("BakedPartCount", bakedParts)
	assets:SetAttribute("MinimapPartCount", minimapResult and #minimapResult.visibleParts or 0)
	assets:SetAttribute("RoadTriangles", #(meshData.roadTriangles or {}))
	assets:SetAttribute("SidewalkTriangles", #(meshData.sidewalkTriangles or {}))
	assets:SetAttribute("CrosswalkTriangles", #(meshData.crosswalkTriangles or {}))

	setStatus(string.format(
		"Baked map %s at %s: %d mesh assets created, %d updated, %d asset-backed parts, %d minimap parts.%s",
		mapId,
		scaleSummary(),
		created,
		updated,
		bakedParts,
		minimapResult and #minimapResult.visibleParts or 0,
		#errors > 0 and ("\nWarnings: " .. table.concat(errors, " | ")) or ""
	))

	return {
		created = created,
		updated = updated,
		bakedParts = bakedParts,
		minimapParts = minimapResult and #minimapResult.visibleParts or 0,
		pointScale = importPointScale,
		widthScale = importWidthScale,
		bakeMode = "meshAsset",
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

	local RoadGraphData, _RoadGraphMesher, _RoadMeshBuilder, moduleErr = getSharedModules()
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
	local okBake, bakeResultOrErr = pcall(bakeMeshAssets)
	ChangeHistoryService:SetWaypoint("cab87 road graph after import")
	if not okBake then
		setStatus("Imported graph, but runtime bake failed: " .. tostring(bakeResultOrErr))
		return
	end
	if not bakeResultOrErr then
		return
	end
	if bakeResultOrErr.bakeMode == "primitive" then
		return
	end

	setStatus(string.format(
		"Imported and baked graph: %d nodes, %d edges at Y=%s, %s.",
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
importButton.MouseButton1Click:Connect(importGraphJson)
bakeAssetsButton.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 road graph before bake")
	local ok, err = pcall(bakeMeshAssets)
	ChangeHistoryService:SetWaypoint("cab87 road graph after bake")
	if not ok then
		setStatus("Bake failed: " .. tostring(err))
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
