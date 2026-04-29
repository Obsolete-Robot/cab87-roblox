-- Cab87 Studio plugin: persistent spline road editor panel.
-- Legacy reference tool. New authored road work should use
-- Cab87RoadGraphBuilder.plugin.lua with intersection-visualizer graph JSON.
-- Install to:
--   %LOCALAPPDATA%\Roblox\Plugins\Cab87RoadCurveTools.plugin.lua

local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local StudioService = game:GetService("StudioService")
local Workspace = game:GetService("Workspace")

local ROOT_NAME = "Cab87RoadEditor"
local SPLINES_NAME = "Splines"
local POINTS_NAME = "RoadPoints"
local MARKERS_NAME = "Markers"
local JUNCTIONS_NAME = "Junctions"
local MESH_NAME = "RoadMesh"
local NETWORK_NAME = "RoadNetwork"
local NETWORK_BUILD_NAME = "RoadNetwork_Building"
local ACTIVE_SPLINE_ATTR = "ActiveSpline"
local ROAD_WIDTH_ATTR = "RoadWidth"
local MARKER_TYPE_ATTR = "Cab87MarkerType"

local ROAD_WIDTH = 28
local JUNCTION_RADIUS = 22
local JUNCTION_MIN_RADIUS = 6
local JUNCTION_MAX_RADIUS = 220
local JUNCTION_RADIUS_STEP = 4
local JUNCTION_SUBDIVISIONS = 0
local JUNCTION_MIN_SUBDIVISIONS = 0
local JUNCTION_MAX_SUBDIVISIONS = 12
local JUNCTION_SUBDIVISIONS_STEP = 1
local CAB_COMPANY_NODE_NAME = "CabCompanyNode"
local CAB_COMPANY_NODE_RIDE_HEIGHT = 2.3
local ROAD_MIN_WIDTH = 8
local ROAD_MAX_WIDTH = 200
local ROAD_WIDTH_STEP = 4
local ROAD_THICKNESS = 1.2
local SAMPLE_STEP_STUDS = 8
local ROAD_OVERLAP = 1.0
local POINT_SNAP_OFFSET = 0.35
local ENDPOINT_WELD_DISTANCE = 22
local INTERSECTION_RADIUS_SCALE = 0.5
local INTERSECTION_BLEND_SCALE = 0.95
local INTERSECTION_MERGE_SCALE = 0.45
local INTERSECTION_RING_SEGMENTS = 28
local JUNCTION_VERTEX_EPSILON = 0.05
local JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE = 0.5
local ROAD_EDGE_MITER_LIMIT = 2.75
local ROAD_EDGE_SMOOTH_PASSES = 2
local ROAD_EDGE_SMOOTH_ALPHA = 0.35
local ROAD_WIDTH_TRIANGULATION_STEP = 24
local ROAD_WIDTH_MAX_INTERNAL_LOOPS = 2
local ROAD_LOFT_LENGTH_STEP = SAMPLE_STEP_STUDS
local ROAD_EDGE_CURVE_SMOOTH_STEP = math.max(1, ROAD_LOFT_LENGTH_STEP * 0.25)
local ROAD_EDGE_CURVE_FAIR_PASSES = 4
local ROAD_EDGE_CURVE_FAIR_ALPHA = 0.42
local ROAD_CURVE_EXPANSION_PASSES = 0
local ROAD_CURVE_EXPANSION_ALPHA = 0.8
local ROAD_INNER_EDGE_RADIUS_SCALE = 0.08
local INTERSECTION_HEIGHT_TOLERANCE_MIN = ROAD_THICKNESS * 2
local INTERSECTION_HEIGHT_TOLERANCE_MAX = ROAD_THICKNESS * 4
local INTERSECTION_HEIGHT_TOLERANCE_WIDTH_SCALE = 0.18
local WIRE_NAME = "WireframeDisplay"
local WIRE_THICKNESS = 0.16
local WIRE_OFFSET_Y = 0.08
local WIRE_MAX_EDGES = 6000
local ROAD_DEBUG_LOGGING = true
local ROAD_LOG_PREFIX = "[cab87 roads plugin]"
local ROAD_CURVE_JSON_VERSION = 1
local IMPORT_PLANE_Y_SETTING = "cab87_road_import_plane_y"
local IMPORT_FILE_FILTER = { "json" }
local IMPORT_PLANE_Y_MIN = -5000
local IMPORT_PLANE_Y_MAX = 5000

local AUTO_REBUILD_DELAY = 0.5
local autoRebuildEnabled = false
local autoRebuildScheduled = false
local autoRebuildSerial = 0
local autoRebuildRunning = false
local autoRebuildDueTime = 0
local autoRebuildReason = nil
local bulkImportInProgress = false
local wireframeEnabled = plugin:GetSetting("cab87_road_wireframe") == true
local importPlaneY = plugin:GetSetting(IMPORT_PLANE_Y_SETTING)
local defaultJunctionRadius = JUNCTION_RADIUS
local defaultJunctionSubdivisions = JUNCTION_SUBDIVISIONS
local lastWireframeEdges = {}

-- Keep this standalone plugin under Luau's 200-local-register limit by storing
-- helper functions in a private script environment instead of local registers.
local scriptEnvironment = getfenv(1)
setfenv(1, setmetatable({}, { __index = scriptEnvironment }))

function formatLogMessage(message, ...)
	local ok, formatted = pcall(string.format, tostring(message), ...)
	if ok then
		return formatted
	end
	return tostring(message)
end

function roadDebugLog(message, ...)
	if ROAD_DEBUG_LOGGING then
		print(ROAD_LOG_PREFIX .. " " .. formatLogMessage(message, ...))
	end
end

function roadDebugWarn(message, ...)
	warn(ROAD_LOG_PREFIX .. " " .. formatLogMessage(message, ...))
end

function sanitizeRoadWidth(value)
	local width = tonumber(value)
	if not width then
		return ROAD_WIDTH
	end
	return math.clamp(width, ROAD_MIN_WIDTH, ROAD_MAX_WIDTH)
end

function sanitizeJunctionRadius(value)
	local radius = tonumber(value)
	if not radius then
		return JUNCTION_RADIUS
	end
	return math.clamp(radius, JUNCTION_MIN_RADIUS, JUNCTION_MAX_RADIUS)
end

function sanitizeJunctionSubdivisions(value)
	local subdivisions = tonumber(value)
	if not subdivisions then
		return JUNCTION_SUBDIVISIONS
	end
	return math.clamp(math.floor(subdivisions + 0.5), JUNCTION_MIN_SUBDIVISIONS, JUNCTION_MAX_SUBDIVISIONS)
end

function sanitizeImportPlaneY(value)
	local planeY = tonumber(value)
	if not planeY then
		return 0
	end
	return math.clamp(planeY, IMPORT_PLANE_Y_MIN, IMPORT_PLANE_Y_MAX)
end

importPlaneY = sanitizeImportPlaneY(importPlaneY)

function getSplineRoadWidth(spline)
	if not spline then
		return ROAD_WIDTH
	end

	local width = sanitizeRoadWidth(spline:GetAttribute(ROAD_WIDTH_ATTR))
	if spline:GetAttribute(ROAD_WIDTH_ATTR) ~= width then
		spline:SetAttribute(ROAD_WIDTH_ATTR, width)
	end
	return width
end

function getOrCreateRoot()
	local root = Workspace:FindFirstChild(ROOT_NAME)
	if root and root:IsA("Model") then
		return root
	end
	root = Instance.new("Model")
	root.Name = ROOT_NAME
	root.Parent = Workspace
	return root
end

function getOrCreateSplinesFolder()
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

function getOrCreateMarkersFolder()
	local root = getOrCreateRoot()
	local folder = root:FindFirstChild(MARKERS_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = MARKERS_NAME
	folder.Parent = root
	return folder
end

function getOrCreateJunctionsFolder()
	local root = getOrCreateRoot()
	local folder = root:FindFirstChild(JUNCTIONS_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = JUNCTIONS_NAME
	folder.Parent = root
	return folder
end

function getSplineFromControlPoint(inst)
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

function ensureSplineChildren(spline)
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

function sortedSplines()
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

function nextSplineName()
	local maxN = 0
	for _, spline in ipairs(sortedSplines()) do
		local n = tonumber(string.match(spline.Name, "^Spline(%d+)$"))
		if n and n > maxN then
			maxN = n
		end
	end
	return string.format("Spline%03d", maxN + 1)
end

function createSpline(name)
	local spline = Instance.new("Model")
	spline.Name = name or nextSplineName()
	spline.Parent = getOrCreateSplinesFolder()
	ensureSplineChildren(spline)
	return spline
end

function getActiveSpline()
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

function setActiveSpline(spline)
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

function createAndActivateSpline()
	local spline = createSpline()
	setActiveSpline(spline)
	return spline
end

function cycleActiveSpline(direction)
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

function getOrCreatePointsFolder()
	local points = ensureSplineChildren(getActiveSpline())
	return points
end

function getOrCreateRoadModel()
	local _, road = ensureSplineChildren(getActiveSpline())
	return road
end

function getOrCreateNetworkModel()
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

function createTemporaryNetworkModel()
	local root = getOrCreateRoot()
	local oldTemp = root:FindFirstChild(NETWORK_BUILD_NAME)
	if oldTemp then
		oldTemp:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = NETWORK_BUILD_NAME
	model.Parent = root
	return model
end

function clearFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

function sortedPoints()
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

function sortedPointsInSpline(spline)
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

function pointName(index)
	return string.format("P%03d", index)
end

function createControlPointPart(parent, name, pos)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(4.5, 4.5, 4.5)
	p.Anchored = true
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 180, 75)
	p.Position = pos
	p.Locked = false
	p.Parent = parent
	return p
end

function junctionName(index)
	return string.format("J%03d", index)
end

function sortedJunctions()
	local folder = getOrCreateJunctionsFolder()
	local junctions = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(junctions, child)
		end
	end
	table.sort(junctions, function(a, b)
		return a.Name < b.Name
	end)
	return junctions
end

function createJunctionPart(parent, name, pos, radius, subdivisions)
	radius = sanitizeJunctionRadius(radius)
	subdivisions = sanitizeJunctionSubdivisions(subdivisions)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(math.max(radius * 0.35, 5), math.max(radius * 0.35, 5), math.max(radius * 0.35, 5))
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(45, 210, 190)
	part.Transparency = 0.12
	part.Position = pos
	part.Locked = false
	part:SetAttribute("Radius", radius)
	part:SetAttribute("Subdivisions", subdivisions)
	part:SetAttribute(MARKER_TYPE_ATTR, "RoadJunction")
	part.Parent = parent
	return part
end

function addJunction(pos, radius, subdivisions)
	local folder = getOrCreateJunctionsFolder()
	return createJunctionPart(folder, junctionName(#sortedJunctions() + 1), pos, radius, subdivisions)
end

local positionHasConnectedControlPoint

function addConnectedJunction(pos, radius, subdivisions)
	radius = sanitizeJunctionRadius(radius)
	if not positionHasConnectedControlPoint(pos, radius) then
		return nil, "Junctions must overlap an existing curve point with a connected road segment"
	end
	return addJunction(pos, radius, subdivisions), nil
end

function getSelectedJunction()
	local selection = Selection:Get()
	if #selection == 0 then
		return nil
	end
	local selected = selection[1]
	if selected and selected:IsA("BasePart") and selected.Parent == getOrCreateJunctionsFolder() then
		return selected
	end
	return nil
end

function getActiveJunctionRadius()
	local selected = getSelectedJunction()
	if selected then
		return sanitizeJunctionRadius(selected:GetAttribute("Radius"))
	end
	return defaultJunctionRadius
end

function getActiveJunctionSubdivisions()
	local selected = getSelectedJunction()
	if selected then
		return sanitizeJunctionSubdivisions(selected:GetAttribute("Subdivisions"))
	end
	return defaultJunctionSubdivisions
end

function renumberPoints()
	for i, p in ipairs(sortedPoints()) do
		p.Name = pointName(i)
	end
end

function isControlPoint(inst)
	return getSplineFromControlPoint(inst) ~= nil
end

function raycastFromCamera(maxDistance)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * (maxDistance or 4000)
	local root = getOrCreateRoot()
	local exclude = {}
	for _, name in ipairs({
		MARKERS_NAME,
		SPLINES_NAME,
		POINTS_NAME,
		JUNCTIONS_NAME,
		WIRE_NAME,
		NETWORK_BUILD_NAME,
	}) do
		local child = root:FindFirstChild(name)
		if child then
			table.insert(exclude, child)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = false

	local hit = Workspace:Raycast(origin, direction, params)
	if hit then
		return hit.Position
	end

	return origin + camera.CFrame.LookVector * 120
end

function yawFromCFrame(cframe)
	local look = cframe.LookVector
	local horizontal = Vector3.new(look.X, 0, look.Z)
	if horizontal.Magnitude <= 0.001 then
		return 0
	end

	local unit = horizontal.Unit
	return math.atan2(unit.X, unit.Z)
end

function yawFromCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0
	end

	return yawFromCFrame(camera.CFrame)
end

function setCabCompanyNode(position, yaw)
	local markersFolder = getOrCreateMarkersFolder()
	local node = markersFolder:FindFirstChild(CAB_COMPANY_NODE_NAME)
	if node and not node:IsA("Part") then
		node:Destroy()
		node = nil
	end
	if not node then
		node = Instance.new("Part")
		node.Name = CAB_COMPANY_NODE_NAME
		node.Parent = markersFolder
	end

	node.Anchored = true
	node.CanCollide = false
	node.CanTouch = false
	node.CanQuery = true
	node.Size = Vector3.new(10, 2, 10)
	node.Color = Color3.fromRGB(90, 255, 150)
	node.Material = Enum.Material.Neon
	node.Transparency = 0.15
	node.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0)
	node:SetAttribute(MARKER_TYPE_ATTR, "CabCompany")
	node:SetAttribute("Cab87MarkerDescription", "Cab spawn pivot and cab company origin")
	return node
end

function setCabCompanyNodeFromCamera()
	local hitPosition = raycastFromCamera(4000)
	if not hitPosition then
		return nil
	end

	return setCabCompanyNode(hitPosition + Vector3.new(0, CAB_COMPANY_NODE_RIDE_HEIGHT, 0), yawFromCamera())
end

function selectCabCompanyNode()
	local markersFolder = getOrCreateMarkersFolder()
	local node = markersFolder:FindFirstChild(CAB_COMPANY_NODE_NAME)
	if node and node:IsA("BasePart") then
		Selection:Set({ node })
		return true
	end

	return false
end

function nearestPointToCameraRay()
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

function addControlPoint(pos)
	local folder = getOrCreatePointsFolder()
	local idx = #folder:GetChildren() + 1
	return createControlPointPart(folder, pointName(idx), pos)
end

function isClosedSpline(spline)
	return spline and spline:GetAttribute("ClosedCurve") == true
end

function isClosedCurve()
	local spline = getActiveSpline()
	return isClosedSpline(spline)
end

function setClosedCurve(value)
	local spline = getActiveSpline()
	spline:SetAttribute("ClosedCurve", value and true or false)
end

function getActiveRoadWidth()
	return getSplineRoadWidth(getActiveSpline())
end

function setActiveRoadWidth(value)
	local spline = getActiveSpline()
	local width = sanitizeRoadWidth(value)
	spline:SetAttribute(ROAD_WIDTH_ATTR, width)
	return width
end

function clearAllSplines()
	clearFolder(getOrCreateSplinesFolder())
	getOrCreateRoot():SetAttribute(ACTIVE_SPLINE_ATTR, nil)
end

function createImportedSpline(data)
	local spline = createSpline()
	local pointsFolder = ensureSplineChildren(spline)

	spline:SetAttribute("ClosedCurve", data.closed == true)
	spline:SetAttribute(ROAD_WIDTH_ATTR, sanitizeRoadWidth(data.width))

	for index, position in ipairs(data.points) do
		createControlPointPart(pointsFolder, pointName(index), position)
	end

	return spline
end

function formatRoadWidth(width)
	width = sanitizeRoadWidth(width)
	local rounded = math.floor(width + 0.5)
	if math.abs(width - rounded) < 0.01 then
		return tostring(rounded)
	end
	return string.format("%.1f", width)
end

function formatJunctionRadius(radius)
	radius = sanitizeJunctionRadius(radius)
	local rounded = math.floor(radius + 0.5)
	if math.abs(radius - rounded) < 0.01 then
		return tostring(rounded)
	end
	return string.format("%.1f", radius)
end

function formatJunctionSubdivisions(subdivisions)
	return tostring(sanitizeJunctionSubdivisions(subdivisions))
end

function formatImportPlaneY(value)
	value = sanitizeImportPlaneY(value)
	local rounded = math.floor(value + 0.5)
	if math.abs(value - rounded) < 0.01 then
		return tostring(rounded)
	end
	return string.format("%.2f", value)
end

function stripUtf8Bom(text)
	if string.byte(text, 1) == 239 and string.byte(text, 2) == 187 and string.byte(text, 3) == 191 then
		return string.sub(text, 4)
	end
	return text
end

function readImportedFileContents(file)
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

function shouldMirrorImportedX(payload)
	return tonumber(payload.version) == 2
end

function importedCurvePointToRoblox(pointData, planeY, mirrorX)
	local x = tonumber(pointData.x)
	local y = tonumber(pointData.y) or 0
	local z = tonumber(pointData.z)
	if not (x and z) then
		return nil
	end
	if mirrorX then
		x = -x
	end
	return Vector3.new(x, planeY + y, z)
end

function parseImportedCurveJson(contents, planeY)
	local ok, payloadOrErr = pcall(function()
		return HttpService:JSONDecode(contents)
	end)
	if not ok then
		return nil, nil, "JSON decode failed: " .. tostring(payloadOrErr)
	end

	local payload = payloadOrErr
	if type(payload) ~= "table" then
		return nil, nil, "Curve JSON root must be an object"
	end

	local version = payload.version
	if version ~= nil and tonumber(version) ~= ROAD_CURVE_JSON_VERSION and tonumber(version) ~= 2 then
		return nil, nil, string.format("Unsupported curve JSON version %s", tostring(version))
	end

	local splines = payload.splines
	if type(splines) ~= "table" then
		return nil, nil, "Curve JSON must include a splines array"
	end

	local imported = {}
	local summary = {
		sourceSplineCount = 0,
		importedSplineCount = 0,
		skippedSplineCount = 0,
		importedPointCount = 0,
		skippedPointCount = 0,
		importedJunctionCount = 0,
		skippedJunctionCount = 0,
		importedJunctions = {},
		mirroredX = shouldMirrorImportedX(payload),
	}

	for _, splineData in ipairs(splines) do
		summary.sourceSplineCount += 1

		local importedPoints = {}
		if type(splineData) == "table" and type(splineData.points) == "table" then
			for _, pointData in ipairs(splineData.points) do
				if type(pointData) == "table" then
					local point = importedCurvePointToRoblox(pointData, planeY, summary.mirroredX)
					if point then
						table.insert(importedPoints, point)
					else
						summary.skippedPointCount += 1
					end
				else
					summary.skippedPointCount += 1
				end
			end
		end

		if #importedPoints >= 2 then
			table.insert(imported, {
				width = sanitizeRoadWidth(type(splineData) == "table" and splineData.width or nil),
				closed = type(splineData) == "table" and splineData.closed == true and #importedPoints >= 3 or false,
				points = importedPoints,
			})
			summary.importedSplineCount += 1
			summary.importedPointCount += #importedPoints
		else
			summary.skippedSplineCount += 1
		end
	end

	if type(payload.junctions) == "table" then
		for _, junctionData in ipairs(payload.junctions) do
			if type(junctionData) == "table" then
				local position = importedCurvePointToRoblox(junctionData, planeY, summary.mirroredX)
				if position then
					table.insert(summary.importedJunctions, {
						position = position,
						radius = sanitizeJunctionRadius(junctionData.radius),
						subdivisions = sanitizeJunctionSubdivisions(junctionData.subdivisions),
					})
					summary.importedJunctionCount += 1
				else
					summary.skippedJunctionCount += 1
				end
			else
				summary.skippedJunctionCount += 1
			end
		end
	end

	if #imported == 0 then
		return nil, summary, "Curve JSON did not contain any valid splines with at least 2 points"
	end

	return imported, summary, nil
end

function catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

function sampleSpline(pointParts, closedCurve)
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

function buildPrimitiveRoad(samples, targetModel, namePrefix, roadWidth)
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

function distanceXZ(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function allControlPoints()
	local points = {}
	for _, spline in ipairs(sortedSplines()) do
		for _, point in ipairs(sortedPointsInSpline(spline)) do
			table.insert(points, point)
		end
	end
	return points
end

function collectControlPointsInJunctionPosition(center, radius)
	local records = {}
	for _, point in ipairs(allControlPoints()) do
		if distanceXZ(point.Position, center) <= radius + 0.001 then
			table.insert(records, point)
		end
	end
	return records
end

positionHasConnectedControlPoint = function(center, radius)
	for _, point in ipairs(collectControlPointsInJunctionPosition(center, radius)) do
		local spline = getSplineFromControlPoint(point)
		if spline and #sortedPointsInSpline(spline) >= 2 then
			return true
		end
	end
	return false
end

function heightConnectTolerance(widthA, widthB)
	local width = math.min(sanitizeRoadWidth(widthA), sanitizeRoadWidth(widthB))
	return math.clamp(
		width * INTERSECTION_HEIGHT_TOLERANCE_WIDTH_SCALE,
		INTERSECTION_HEIGHT_TOLERANCE_MIN,
		INTERSECTION_HEIGHT_TOLERANCE_MAX
	)
end

function positionsConnectIn3D(a, b, widthA, widthB)
	return math.abs(a.Y - b.Y) <= heightConnectTolerance(widthA, widthB)
end

function lerpNumber(a, b, alpha)
	return a + (b - a) * alpha
end

function getOrCreateWireframeFolder(network)
	local folder = network:FindFirstChild(WIRE_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = WIRE_NAME
	folder.Parent = network
	return folder
end

function clearWireframe()
	local network = getOrCreateNetworkModel()
	local folder = network:FindFirstChild(WIRE_NAME)
	if folder then
		folder:Destroy()
	end
end

function createWireSegment(parent, a, b, index)
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

function refreshWireframe()
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

function newMeshState()
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

function addMeshVertex(state, pos)
	local vertex = state.mesh:AddVertex(pos)
	state.vertexPositions[vertex] = pos
	return vertex
end

function recordMeshEdge(state, a, b)
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

function addMeshTriangle(state, a, b, c)
	state.mesh:AddTriangle(a, b, c)
	recordMeshEdge(state, a, b)
	recordMeshEdge(state, b, c)
	recordMeshEdge(state, c, a)
	state.faces += 1
end

function sampleLoopIsClosed(samples)
	if #samples < 3 then
		return false
	end
	return distanceXZ(samples[1], samples[#samples]) <= 0.05 and math.abs(samples[1].Y - samples[#samples].Y) <= 0.05
end

function roadRightFromTangent(tangent)
	local right = Vector3.yAxis:Cross(tangent)
	if right.Magnitude < 1e-4 then
		return Vector3.xAxis
	end
	return right.Unit
end

function horizontalUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-4 then
		return nil
	end
	return flat.Unit
end

function crossXZ(a, b)
	return a.X * b.Z - a.Z * b.X
end

function lineIntersectionXZ(a, dirA, b, dirB)
	local denom = crossXZ(dirA, dirB)
	if math.abs(denom) < 1e-5 then
		return nil
	end

	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local t = (dx * dirB.Z - dz * dirB.X) / denom
	return Vector3.new(a.X + dirA.X * t, a.Y, a.Z + dirA.Z * t)
end

function circleCenterXZ(a, b, c)
	local ax = a.X
	local az = a.Z
	local bx = b.X
	local bz = b.Z
	local cx = c.X
	local cz = c.Z
	local denom = 2 * (ax * (bz - cz) + bx * (cz - az) + cx * (az - bz))
	if math.abs(denom) < 1e-4 then
		return nil
	end

	local a2 = ax * ax + az * az
	local b2 = bx * bx + bz * bz
	local c2 = cx * cx + cz * cz
	local ux = (a2 * (bz - cz) + b2 * (cz - az) + c2 * (az - bz)) / denom
	local uz = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / denom
	return Vector3.new(ux, b.Y, uz)
end

function expandCentersForRoadWidth(centers, roadWidth, closedLoop)
	local edgeCount = #centers
	local halfWidth = roadWidth * 0.5
	local targetRadius = halfWidth + math.max(6, roadWidth * ROAD_INNER_EDGE_RADIUS_SCALE)
	local expansionCount = 0
	local maxPush = 0
	local minRadius = math.huge

	for _ = 1, ROAD_CURVE_EXPANSION_PASSES do
		local nextCenters = {}
		for i = 1, edgeCount do
			nextCenters[i] = centers[i]
		end

		for i = 1, edgeCount do
			if closedLoop or (i > 1 and i < edgeCount) then
				local prevIndex = i - 1
				if prevIndex < 1 then
					prevIndex = edgeCount
				end
				local nextIndex = i + 1
				if nextIndex > edgeCount then
					nextIndex = 1
				end

				local circleCenter = circleCenterXZ(centers[prevIndex], centers[i], centers[nextIndex])
				if circleCenter then
					local inward = horizontalUnit(circleCenter - centers[i])
					if inward then
						local radius = distanceXZ(circleCenter, centers[i])
						minRadius = math.min(minRadius, radius)
						if radius < targetRadius then
							local push = (targetRadius - radius) * ROAD_CURVE_EXPANSION_ALPHA
							nextCenters[i] = centers[i] - inward * push
							expansionCount += 1
							maxPush = math.max(maxPush, push)
						end
					end
				end
			end
		end

		centers = nextCenters
	end

	return centers, expansionCount, maxPush, minRadius
end

function offsetEdgePoint(center, prevDir, prevRight, nextDir, nextRight, sideSign, halfWidth)
	local prevOffset = center + prevRight * (sideSign * halfWidth)
	local nextOffset = center + nextRight * (sideSign * halfWidth)
	local intersection = lineIntersectionXZ(prevOffset, prevDir, nextOffset, nextDir)
	local maxMiterDistance = halfWidth * ROAD_EDGE_MITER_LIMIT
	if intersection then
		local fromCenter = Vector3.new(intersection.X - center.X, 0, intersection.Z - center.Z)
		if fromCenter.Magnitude > 1e-4 then
			if fromCenter.Magnitude <= maxMiterDistance then
				return Vector3.new(intersection.X, center.Y, intersection.Z)
			end
			local clamped = center + fromCenter.Unit * maxMiterDistance
			return Vector3.new(clamped.X, center.Y, clamped.Z), "clamped"
		end
	end

	local averagedRight = prevRight + nextRight
	if averagedRight.Magnitude < 1e-4 then
		averagedRight = nextRight
	end
	local fallback = center + averagedRight.Unit * (sideSign * halfWidth)
	return Vector3.new(fallback.X, center.Y, fallback.Z), "fallback"
end

function buildRoadEdgePairs(samples, roadWidth, surfaceYOffset, debugLabel)
	if #samples < 2 then
		return nil, nil
	end

	roadWidth = sanitizeRoadWidth(roadWidth)
	local closedLoop = sampleLoopIsClosed(samples)
	local sampleCount = #samples
	local edgeCount = closedLoop and sampleCount - 1 or sampleCount
	if edgeCount < 2 then
		return nil, nil
	end

	local halfWidth = roadWidth * 0.5
	local centers = {}
	for i = 1, edgeCount do
		centers[i] = samples[i] + Vector3.new(0, surfaceYOffset, 0)
	end
	local centerExpansionCount
	local maxCenterPush
	local minCurveRadius
	centers, centerExpansionCount, maxCenterPush, minCurveRadius = expandCentersForRoadWidth(centers, roadWidth, closedLoop)

	local segmentCount = closedLoop and edgeCount or edgeCount - 1
	local segmentDirs = {}
	local segmentRights = {}
	local fallbackDir = Vector3.new(0, 0, 1)
	for i = 1, segmentCount do
		local nextIndex = closedLoop and ((i % edgeCount) + 1) or (i + 1)
		local dir = horizontalUnit(centers[nextIndex] - centers[i]) or fallbackDir
		segmentDirs[i] = dir
		segmentRights[i] = roadRightFromTangent(dir)
		fallbackDir = dir
	end

	local leftPositions = {}
	local rightPositions = {}
	local miterClampCount = 0
	local miterFallbackCount = 0
	for i = 1, edgeCount do
		local center = centers[i]
		if not closedLoop and i == 1 then
			local right = segmentRights[1]
			leftPositions[i] = center - right * halfWidth
			rightPositions[i] = center + right * halfWidth
		elseif not closedLoop and i == edgeCount then
			local right = segmentRights[segmentCount]
			leftPositions[i] = center - right * halfWidth
			rightPositions[i] = center + right * halfWidth
		else
			local prevSegment = i - 1
			if prevSegment < 1 then
				prevSegment = segmentCount
			end
			local nextSegment = i
			if nextSegment > segmentCount then
				nextSegment = 1
			end

			local leftStatus
			leftPositions[i], leftStatus = offsetEdgePoint(
				center,
				segmentDirs[prevSegment],
				segmentRights[prevSegment],
				segmentDirs[nextSegment],
				segmentRights[nextSegment],
				-1,
				halfWidth
			)
			local rightStatus
			rightPositions[i], rightStatus = offsetEdgePoint(
				center,
				segmentDirs[prevSegment],
				segmentRights[prevSegment],
				segmentDirs[nextSegment],
				segmentRights[nextSegment],
				1,
				halfWidth
			)
			if leftStatus == "clamped" then
				miterClampCount += 1
			elseif leftStatus == "fallback" then
				miterFallbackCount += 1
			end
			if rightStatus == "clamped" then
				miterClampCount += 1
			elseif rightStatus == "fallback" then
				miterFallbackCount += 1
			end
		end
	end

	local function correctPairWidth(index)
		local center = centers[index]
		local mid = (leftPositions[index] + rightPositions[index]) * 0.5
		local lateral = horizontalUnit(rightPositions[index] - leftPositions[index])
		if not lateral then
			local segmentIndex = math.min(index, segmentCount)
			lateral = segmentRights[segmentIndex] or Vector3.xAxis
		end

		leftPositions[index] = Vector3.new(mid.X, center.Y, mid.Z) - lateral * halfWidth
		rightPositions[index] = Vector3.new(mid.X, center.Y, mid.Z) + lateral * halfWidth
	end

	for i = 1, edgeCount do
		correctPairWidth(i)
	end

	for _ = 1, ROAD_EDGE_SMOOTH_PASSES do
		local nextLeft = {}
		local nextRight = {}
		for i = 1, edgeCount do
			if closedLoop or (i > 1 and i < edgeCount) then
				local prevIndex = i - 1
				if prevIndex < 1 then
					prevIndex = edgeCount
				end
				local nextIndex = i + 1
				if nextIndex > edgeCount then
					nextIndex = 1
				end

				local leftAverage = (leftPositions[prevIndex] + leftPositions[nextIndex]) * 0.5
				local rightAverage = (rightPositions[prevIndex] + rightPositions[nextIndex]) * 0.5
				nextLeft[i] = leftPositions[i]:Lerp(Vector3.new(leftAverage.X, centers[i].Y, leftAverage.Z), ROAD_EDGE_SMOOTH_ALPHA)
				nextRight[i] = rightPositions[i]:Lerp(Vector3.new(rightAverage.X, centers[i].Y, rightAverage.Z), ROAD_EDGE_SMOOTH_ALPHA)
			else
				nextLeft[i] = leftPositions[i]
				nextRight[i] = rightPositions[i]
			end
		end

		leftPositions = nextLeft
		rightPositions = nextRight
		for i = 1, edgeCount do
			correctPairWidth(i)
		end
	end

	if closedLoop then
		leftPositions[sampleCount] = leftPositions[1]
		rightPositions[sampleCount] = rightPositions[1]
	end

	local collapsedSpans = 0
	local tightSpans = 0
	local minLeftStep = math.huge
	local minRightStep = math.huge
	for i = 1, edgeCount - 1 do
		local sampleStep = (samples[i + 1] - samples[i]).Magnitude
		local leftStep = (leftPositions[i + 1] - leftPositions[i]).Magnitude
		local rightStep = (rightPositions[i + 1] - rightPositions[i]).Magnitude
		minLeftStep = math.min(minLeftStep, leftStep)
		minRightStep = math.min(minRightStep, rightStep)
		if sampleStep > 1 and math.min(leftStep, rightStep) < 0.5 then
			collapsedSpans += 1
		end
		if roadWidth > sampleStep * 2 then
			tightSpans += 1
		end
	end

	if closedLoop and edgeCount > 2 then
		local sampleStep = (samples[1] - samples[edgeCount]).Magnitude
		local leftStep = (leftPositions[1] - leftPositions[edgeCount]).Magnitude
		local rightStep = (rightPositions[1] - rightPositions[edgeCount]).Magnitude
		minLeftStep = math.min(minLeftStep, leftStep)
		minRightStep = math.min(minRightStep, rightStep)
		if sampleStep > 1 and math.min(leftStep, rightStep) < 0.5 then
			collapsedSpans += 1
		end
		if roadWidth > sampleStep * 2 then
			tightSpans += 1
		end
	end

	if centerExpansionCount > 0 or miterClampCount > 0 or miterFallbackCount > 0 or collapsedSpans > 0 or tightSpans > 0 then
		local label = debugLabel or "road"
		local message = "edge remesh diagnostics %s: width=%.1f samples=%d closed=%s centerExpansions=%d maxCenterPush=%.2f minCurveRadius=%.2f miterClamps=%d fallbacks=%d collapsedSpans=%d tightSpans=%d minLeftStep=%.2f minRightStep=%.2f"
		if collapsedSpans > 0 then
			roadDebugWarn(
				message,
				label,
				roadWidth,
				#samples,
				tostring(closedLoop),
				centerExpansionCount,
				maxCenterPush,
				minCurveRadius == math.huge and 0 or minCurveRadius,
				miterClampCount,
				miterFallbackCount,
				collapsedSpans,
				tightSpans,
				minLeftStep == math.huge and 0 or minLeftStep,
				minRightStep == math.huge and 0 or minRightStep
			)
		else
			roadDebugLog(
				message,
				label,
				roadWidth,
				#samples,
				tostring(closedLoop),
				centerExpansionCount,
				maxCenterPush,
				minCurveRadius == math.huge and 0 or minCurveRadius,
				miterClampCount,
				miterFallbackCount,
				collapsedSpans,
				tightSpans,
				minLeftStep == math.huge and 0 or minLeftStep,
				minRightStep == math.huge and 0 or minRightStep
			)
		end
	end

	return leftPositions, rightPositions
end

function angleFromHorizontal(vector)
	return math.atan2(vector.Z, vector.X)
end

function vectorFromHorizontalAngle(angle)
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

function shortestAngleDelta(fromAngle, toAngle)
	return math.atan2(math.sin(toAngle - fromAngle), math.cos(toAngle - fromAngle))
end

function addRoadTurnSectorToMesh(state, center, fromVector, toVector, radius)
	local fromUnit = horizontalUnit(fromVector)
	local toUnit = horizontalUnit(toVector)
	if not fromUnit or not toUnit then
		return 0
	end

	local fromAngle = angleFromHorizontal(fromUnit)
	local delta = shortestAngleDelta(fromAngle, angleFromHorizontal(toUnit))
	if math.abs(delta) < math.rad(1) then
		return 0
	end

	local steps = math.max(1, math.ceil(math.abs(delta) / math.rad(12)))
	local centerVertex = addMeshVertex(state, center)
	local previousVertex = addMeshVertex(state, center + vectorFromHorizontalAngle(fromAngle) * radius)
	local triangles = 0
	for step = 1, steps do
		local angle = fromAngle + delta * (step / steps)
		local currentVertex = addMeshVertex(state, center + vectorFromHorizontalAngle(angle) * radius)
		if delta > 0 then
			addMeshTriangle(state, centerVertex, currentVertex, previousVertex)
		else
			addMeshTriangle(state, centerVertex, previousVertex, currentVertex)
		end
		previousVertex = currentVertex
		triangles += 1
	end
	return triangles
end

function addRoadLoftRowVertices(state, left, right, widthSegments)
	local row = {}
	for j = 0, widthSegments do
		row[j + 1] = addMeshVertex(state, left:Lerp(right, j / widthSegments))
	end
	return row
end

function getRoadSampleTangent(samples, index, edgeCount, closedLoop, fallbackDir)
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

function polylineLength(points, closedLoop)
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

function samplePolylineAtFraction(points, closedLoop, fraction)
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

function sampleSmoothedCurveControls(points, closedLoop, sampleStep)
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

function resamplePolylineControls(points, closedLoop, targetCount)
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

function fairEdgeCurveControls(points, closedLoop, sampleStep)
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

function getUniqueRoadSamples(samples, closedLoop)
	local unique = {}
	for _, sample in ipairs(samples) do
		table.insert(unique, sample)
	end
	if closedLoop and #unique > 1 and distanceXZ(unique[1], unique[#unique]) <= 0.05 then
		table.remove(unique, #unique)
	end
	return unique
end

function buildRoadCrossSections(samples, roadWidth, surfaceYOffset, debugLabel)
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

	if roadWidth >= 96 and ROAD_DEBUG_LOGGING then
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

function addRoadRibbonToMesh(state, samples, roadWidth, debugLabel)
	local sections = buildRoadCrossSections(samples, roadWidth, ROAD_THICKNESS * 0.5, debugLabel)
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
	if ROAD_DEBUG_LOGGING and sections.roadWidth >= 96 then
		roadDebugLog("road loft %s: width=%.1f rows=%d spans=%d widthSegments=%d", tostring(debugLabel or "road"), sections.roadWidth, sections.rowCount, spans, sections.widthSegments)
	end

	return spans
end

function normalizePositiveAngleDelta(delta)
	local result = delta
	while result <= 0 do
		result += math.pi * 2
	end
	while result > math.pi * 2 do
		result -= math.pi * 2
	end
	return result
end

local getJunctionMeshCenter

function junctionBoundaryAngle(point, junction)
	local center = getJunctionMeshCenter(junction)
	return math.atan2(point.Z - center.Z, point.X - center.X)
end

function boundaryEntriesSharePortal(a, b)
	return a.portal ~= nil and b.portal ~= nil and a.portal == b.portal
end

function mergeBoundaryEntryPortal(target, source)
	if not boundaryEntriesSharePortal(target, source) then
		target.portal = nil
		target.corePoint = target.point
	end
end

function sortedJunctionBoundaryEntries(junction)
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

function addConnectorSubdivisionPoints(boundary, junction, fromPoint, toPoint, subdivisions, surfaceY)
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

function appendBoundaryPoint(boundary, point)
	if #boundary == 0 or distanceXZ(boundary[#boundary], point) > 0.05 then
		table.insert(boundary, point)
	end
end

function appendUniqueBoundaryPoint(boundary, point)
	for _, existing in ipairs(boundary) do
		if distanceXZ(existing, point) <= 0.05 then
			return
		end
	end
	table.insert(boundary, point)
end

function hullCrossXZ(origin, a, b)
	return (a.X - origin.X) * (b.Z - origin.Z) - (a.Z - origin.Z) * (b.X - origin.X)
end

function convexHullXZ(points)
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

function polygonAverageCenter(boundary, fallback)
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

function portalConnectorPoints(portal, surfaceY)
	local coreLeft = portal.coreLeft or portal.left
	local coreRight = portal.coreRight or portal.right
	local mouthLeft = portal.left
	local mouthRight = portal.right
	return Vector3.new(coreLeft.X, surfaceY, coreLeft.Z),
		Vector3.new(coreRight.X, surfaceY, coreRight.Z),
		Vector3.new(mouthLeft.X, surfaceY, mouthLeft.Z),
		Vector3.new(mouthRight.X, surfaceY, mouthRight.Z)
end

function addLinearSubdivisionPoints(boundary, fromPoint, toPoint, subdivisions)
	for i = 1, subdivisions do
		appendBoundaryPoint(boundary, fromPoint:Lerp(toPoint, i / (subdivisions + 1)))
	end
end

function isNaturalJunctionCorner(junction, fromEntry, toEntry, point)
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
	return distanceXZ(point, getJunctionMeshCenter(junction)) <= math.max(maxDistance, JUNCTION_MIN_RADIUS)
end

function naturalJunctionCorner(junction, fromEntry, toEntry, surfaceY)
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

function addConnectorBoundaryPoints(boundary, junction, fromEntry, toEntry, subdivisions, surfaceY)
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

function buildJunctionBoundary(junction, surfaceY)
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

function addPortalConnectorToMesh(state, portal, surfaceY)
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

function addIntersectionPatchToMesh(state, junction)
	if not junction.portals or #junction.portals == 0 then
		return
	end

	local fallbackCenter = getJunctionMeshCenter(junction) + Vector3.new(0, ROAD_THICKNESS * 0.5, 0)
	local boundary = buildJunctionBoundary(junction, fallbackCenter.Y)
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

function createNetworkMeshPart(state, targetModel, meshName)
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

function collectSplineBuildData()
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

function collectAuthoredJunctions()
	local junctions = {}
	for _, junctionPart in ipairs(sortedJunctions()) do
		local radius = sanitizeJunctionRadius(junctionPart:GetAttribute("Radius"))
		local subdivisions = sanitizeJunctionSubdivisions(junctionPart:GetAttribute("Subdivisions"))
		junctionPart:SetAttribute("Radius", radius)
		junctionPart:SetAttribute("Subdivisions", subdivisions)
		table.insert(junctions, {
			instance = junctionPart,
			name = junctionPart.Name,
			center = junctionPart.Position,
			radius = radius,
			blendRadius = radius,
			subdivisions = subdivisions,
			portals = {},
			chains = {},
		})
	end
	return junctions
end

function segmentCircleIntersections(a, b, center, radius)
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

function interpolateSegmentPoint(a, b, t)
	return a:Lerp(b, t)
end

function junctionContainingPoint(point, junctions)
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

function junctionTouchingPoint(point, junctions)
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

function intervalOutsideJunctions(a, b, junctions)
	return junctionContainingPoint(a:Lerp(b, 0.5), junctions) == nil
end

function copyChainWithSamples(sourceChain, samples, closed)
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

function closestPointOnSegmentXZ(a, b, point)
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

function buildChainPath(chain)
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

function pathSegmentInfo(path, segmentIndex)
	local samples = path.samples
	local nextIndex = segmentIndex + 1
	if nextIndex > #samples then
		nextIndex = 1
	end
	local startDistance = path.distances[segmentIndex]
	local endDistance = if path.closed and segmentIndex == #samples then path.totalLength else path.distances[nextIndex]
	return samples[segmentIndex], samples[nextIndex], startDistance, endDistance
end

function pathPointAtDistance(path, distance)
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

function collectPathSamples(path, startDistance, endDistance)
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

function pathDistanceForSegment(path, segmentIndex, t)
	local _, _, startDistance, endDistance = pathSegmentInfo(path, segmentIndex)
	return startDistance + (endDistance - startDistance) * t
end

function closestPathHit(path, point)
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

function collectExplicitJunctionHits(paths, junctions)
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

function computeExplicitJunctionCenter(junction)
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

function finalizeExplicitJunctionCenters(junctions)
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

function getJunctionCutDistanceFallback(hit)
	local width = hit and hit.chain and hit.chain.width or ROAD_WIDTH
	return sanitizeRoadWidth(width) * 0.5 + 30
end

function assignExplicitJunctionCutDistances(junction)
	local roads = {}
	for hitIndex, hit in ipairs(junction.hits or {}) do
		local path = hit.path
		local lineDir = horizontalUnit(hit.lineDir or Vector3.zAxis) or Vector3.zAxis
		hit.beforeRoadId = string.format("%d:before", hitIndex)
		hit.afterRoadId = string.format("%d:after", hitIndex)
		hit.hasBeforeRoad = path and (path.closed or hit.pathDistance > 0.05) or false
		hit.hasAfterRoad = path and (path.closed or hit.pathDistance < path.totalLength - 0.05) or false

		if hit.hasBeforeRoad then
			table.insert(roads, {
				id = hit.beforeRoadId,
				direction = -lineDir,
				width = hit.chain and hit.chain.width or ROAD_WIDTH,
			})
		end
		if hit.hasAfterRoad then
			table.insert(roads, {
				id = hit.afterRoadId,
				direction = lineDir,
				width = hit.chain and hit.chain.width or ROAD_WIDTH,
			})
		end
	end

	local geometry = calculateSimplifiedIntersectionGeometry(junction.intersectionCenter or junction.center, roads)
	junction.cutGeometry = geometry
	for _, hit in ipairs(junction.hits or {}) do
		local fallback = getJunctionCutDistanceFallback(hit)
		hit.beforeCutDistance = hit.hasBeforeRoad and (geometry.roadCutDistances[hit.beforeRoadId] or fallback) or 0
		hit.afterCutDistance = hit.hasAfterRoad and (geometry.roadCutDistances[hit.afterRoadId] or fallback) or 0
	end
end

function addPortalForChain(junction, chain, boundaryPoint, outsidePoint)
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

function closestSampleIndex(samples, point)
	local bestIndex = nil
	local bestDistance = math.huge
	for index, sample in ipairs(samples or {}) do
		local d = distanceXZ(sample, point)
		if d < bestDistance then
			bestIndex = index
			bestDistance = d
		end
	end
	return bestIndex, bestDistance
end

function rememberPortalKey(portalKeys, chain, boundaryIndex, outsideIndex)
	local chainKeys = portalKeys[chain]
	if not chainKeys then
		chainKeys = {}
		portalKeys[chain] = chainKeys
	end

	local key = tostring(boundaryIndex) .. ":" .. tostring(outsideIndex)
	if chainKeys[key] then
		return false
	end
	chainKeys[key] = true
	return true
end

function addMemberPortalForSample(portalKeys, junction, chain, boundaryIndex, outsideIndex)
	local samples = chain and chain.samples
	if not samples then
		return
	end

	local boundaryPoint = samples[boundaryIndex]
	local outsidePoint = samples[outsideIndex]
	if not boundaryPoint or not outsidePoint or distanceXZ(boundaryPoint, outsidePoint) <= 0.05 then
		return
	end

	if not rememberPortalKey(portalKeys, chain, boundaryIndex, outsideIndex) then
		return
	end

	addPortalForChain(junction, chain, boundaryPoint, outsidePoint)
end

function addMemberPortalsAroundSample(portalKeys, junction, chain, sampleIndex)
	local samples = chain and chain.samples
	if not samples or #samples < 2 or not sampleIndex then
		return
	end

	if chain.closed and #samples > 2 and (sampleIndex == 1 or sampleIndex == #samples) then
		addMemberPortalForSample(portalKeys, junction, chain, 1, 2)
		addMemberPortalForSample(portalKeys, junction, chain, 1, #samples - 1)
	elseif sampleIndex <= 1 then
		addMemberPortalForSample(portalKeys, junction, chain, 1, 2)
	elseif sampleIndex >= #samples then
		addMemberPortalForSample(portalKeys, junction, chain, #samples, #samples - 1)
	else
		addMemberPortalForSample(portalKeys, junction, chain, sampleIndex, sampleIndex - 1)
		addMemberPortalForSample(portalKeys, junction, chain, sampleIndex, sampleIndex + 1)
	end
end

function attachMemberJunctionPortals(junctions)
	for _, junction in ipairs(junctions or {}) do
		junction.portals = {}
		junction.chains = junction.chains or {}
		local portalKeys = {}
		for _, member in ipairs(junction.members or {}) do
			local chain = member.chain
			if chain and chain.samples then
				junction.chains[chain] = true
				local sampleIndex = member.index
				if sampleIndex and (not chain.samples[sampleIndex] or distanceXZ(chain.samples[sampleIndex], junction.center) > 0.1) then
					sampleIndex = nil
				end
				if not sampleIndex then
					sampleIndex = closestSampleIndex(chain.samples, junction.center)
				end
				addMemberPortalsAroundSample(portalKeys, junction, chain, sampleIndex)
			end
		end
	end
end

function portalLineT(portal, point)
	return (point - portal.boundaryPoint):Dot(portal.tangent)
end

function portalLinePointAtT(portal, t)
	return Vector3.new(
		portal.boundaryPoint.X + portal.tangent.X * t,
		portal.boundaryPoint.Y,
		portal.boundaryPoint.Z + portal.tangent.Z * t
	)
end

function getJunctionMeshCenter(junction)
	return junction.intersectionCenter or junction.center
end

function computeJunctionIntersectionCenter(junction)
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

function appendUniqueJunctionPoint(points, point)
	for _, existing in ipairs(points) do
		if distanceXZ(existing, point) <= 0.05 then
			return
		end
	end
	table.insert(points, point)
end

function junctionHullCrossXZ(origin, a, b)
	return (a.X - origin.X) * (b.Z - origin.Z) - (a.Z - origin.Z) * (b.X - origin.X)
end

function junctionConvexHullXZ(points)
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

function lineIntersectionWithParametersXZ(a, dirA, b, dirB)
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

function calculateSimplifiedIntersectionGeometry(center, roads)
	local sortedRoads = {}
	for index, road in ipairs(roads or {}) do
		local directionSource = road.direction
		if not directionSource and road.endPoint then
			directionSource = road.endPoint - center
		end
		local direction = horizontalUnit(directionSource or Vector3.zero)
		if direction then
			local copied = {}
			for key, value in pairs(road) do
				copied[key] = value
			end
			copied.id = copied.id or tostring(index)
			copied.width = sanitizeRoadWidth(copied.width)
			copied.halfWidth = copied.width * 0.5
			copied.direction = direction
			copied.angle = math.atan2(direction.Z, direction.X)
			table.insert(sortedRoads, copied)
		end
	end

	table.sort(sortedRoads, function(a, b)
		return a.angle < b.angle
	end)

	local vertices = {}
	local hubPolygon = {}
	local roadPolygons = {}
	local corners = {}
	if #sortedRoads < 2 then
		return {
			vertices = vertices,
			hubPolygon = hubPolygon,
			sortedRoads = sortedRoads,
			roadCutDistances = {},
			corners = corners,
			roadPolygons = roadPolygons,
		}
	end

	for index, road in ipairs(sortedRoads) do
		local nextRoad = sortedRoads[(index % #sortedRoads) + 1]
		local side = roadRightFromTangent(road.direction)
		local nextSide = roadRightFromTangent(nextRoad.direction)
		local halfWidth = road.halfWidth
		local nextHalfWidth = nextRoad.halfWidth
		local endPoint = road.endPoint or (center + road.direction * math.max(road.width, halfWidth + 30))

		table.insert(vertices, Vector3.new(
			endPoint.X + side.X * halfWidth,
			center.Y,
			endPoint.Z + side.Z * halfWidth
		))
		table.insert(vertices, Vector3.new(
			endPoint.X - side.X * halfWidth,
			center.Y,
			endPoint.Z - side.Z * halfWidth
		))

		local fromSide = Vector3.new(center.X - side.X * halfWidth, center.Y, center.Z - side.Z * halfWidth)
		local toSide = Vector3.new(center.X + nextSide.X * nextHalfWidth, center.Y, center.Z + nextSide.Z * nextHalfWidth)
		local intersection, fromT, toT = lineIntersectionWithParametersXZ(fromSide, road.direction, toSide, nextRoad.direction)
		local maxExtension = math.max(halfWidth, nextHalfWidth) * 1.5 + 50
		local points = {}

		if intersection then
			if fromT > maxExtension or toT > maxExtension or fromT < -halfWidth or toT < -nextHalfWidth then
				local safeFromT = math.clamp(fromT, 0, maxExtension)
				local safeToT = math.clamp(toT, 0, maxExtension)
				table.insert(points, Vector3.new(
					fromSide.X + road.direction.X * safeFromT,
					center.Y,
					fromSide.Z + road.direction.Z * safeFromT
				))
				table.insert(points, Vector3.new(
					toSide.X + nextRoad.direction.X * safeToT,
					center.Y,
					toSide.Z + nextRoad.direction.Z * safeToT
				))
			else
				table.insert(points, Vector3.new(intersection.X, center.Y, intersection.Z))
			end
		else
			table.insert(points, fromSide)
			table.insert(points, toSide)
		end

		corners[index] = points
	end

	for _, points in ipairs(corners) do
		for _, point in ipairs(points) do
			table.insert(hubPolygon, point)
		end
	end

	local roadCutDistances = {}
	for index, road in ipairs(sortedRoads) do
		local previousIndex = index - 1
		if previousIndex < 1 then
			previousIndex = #sortedRoads
		end

		local previousCorner = corners[previousIndex] or {}
		local currentCorner = corners[index] or {}
		if #previousCorner > 0 and #currentCorner > 0 then
			local baseLeft = previousCorner[#previousCorner]
			local baseRight = currentCorner[1]
			local side = roadRightFromTangent(road.direction)
			local endPoint = road.endPoint or (center + road.direction * math.max(road.width, road.halfWidth + 30))
			local endLeft = Vector3.new(
				endPoint.X + side.X * road.halfWidth,
				center.Y,
				endPoint.Z + side.Z * road.halfWidth
			)
			local endRight = Vector3.new(
				endPoint.X - side.X * road.halfWidth,
				center.Y,
				endPoint.Z - side.Z * road.halfWidth
			)

			table.insert(roadPolygons, {
				id = road.id,
				road = road,
				baseLeft = baseLeft,
				baseRight = baseRight,
				polygon = {
					baseLeft,
					baseRight,
					endRight,
					endLeft,
				},
			})

			for _, point in ipairs(previousCorner) do
				table.insert(vertices, point)
			end
			table.insert(vertices, endLeft)
			table.insert(vertices, endRight)
		end

		local maxProjection = 0
		for _, point in ipairs(previousCorner) do
			maxProjection = math.max(maxProjection, (point - center):Dot(road.direction))
		end
		for _, point in ipairs(currentCorner) do
			maxProjection = math.max(maxProjection, (point - center):Dot(road.direction))
		end

		roadCutDistances[road.id] = math.max(maxProjection, road.halfWidth) + 30
	end

	return {
		vertices = vertices,
		hubPolygon = hubPolygon,
		sortedRoads = sortedRoads,
		roadCutDistances = roadCutDistances,
		corners = corners,
		roadPolygons = roadPolygons,
	}
end

function junctionCoreBoundaryLimit(junction)
	local center = getJunctionMeshCenter(junction)
	local limit = JUNCTION_MIN_RADIUS
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

function portalSideLine(portal, sideSign)
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

function collectPortalSideLines(junction)
	local lines = {}
	for _, portal in ipairs(junction.portals or {}) do
		table.insert(lines, portalSideLine(portal, -1))
		table.insert(lines, portalSideLine(portal, 1))
	end
	return lines
end

function sortedJunctionPortals(junction)
	local portals = {}
	for _, portal in ipairs(junction.portals or {}) do
		table.insert(portals, portal)
	end
	table.sort(portals, function(a, b)
		return math.atan2(a.tangent.Z, a.tangent.X) < math.atan2(b.tangent.Z, b.tangent.X)
	end)
	return portals
end

function appendOrderedJunctionPoint(points, point)
	if #points == 0 or distanceXZ(points[#points], point) > 0.05 then
		table.insert(points, point)
	end
end

function finalizeOrderedJunctionBoundary(points)
	if #points >= 2 and distanceXZ(points[1], points[#points]) <= 0.05 then
		table.remove(points, #points)
	end
	return points
end

function junctionGapPoints(center, fromPortal, toPortal)
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

function buildJunctionCoreBoundary(junction)
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

function buildJunctionSurfaceBoundary(junction)
	local boundary = {}
	for _, point in ipairs(junction.coreBoundary or {}) do
		table.insert(boundary, point)
	end
	return boundary
end

function pointLineDistanceXZ(point, linePoint, lineDir)
	return math.abs(crossXZ(point - linePoint, lineDir))
end

function boundaryPointOnPortalSide(boundary, portal, sideSign)
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

function portalSideEntriesForCore(junction)
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

function isCoreCornerCandidate(junction, fromEntry, toEntry, corner)
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
	return distanceXZ(corner, center) <= math.max(maxDistance, JUNCTION_MIN_RADIUS)
end

function updatePortalGeometry(junction, portal)
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

function trimChainEndpointToPortal(junction, portal)
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

function applySimplifiedJunctionGeometry(junction)
	local portals = junction.portals or {}
	if #portals < 2 then
		return false
	end

	local roads = {}
	for index, portal in ipairs(portals) do
		table.insert(roads, {
			id = tostring(index),
			direction = portal.tangent,
			endPoint = portal.boundaryPoint or portal.point,
			width = (portal.halfWidth or 0) * 2,
			portal = portal,
		})
	end

	local geometry = calculateSimplifiedIntersectionGeometry(getJunctionMeshCenter(junction), roads)
	local hubPolygon = geometry.hubPolygon or {}
	if #hubPolygon < 3 then
		return false
	end

	local roadPolygonsById = {}
	for _, roadPolygon in ipairs(geometry.roadPolygons or {}) do
		roadPolygonsById[roadPolygon.id] = roadPolygon
	end
	for _, road in ipairs(geometry.sortedRoads) do
		local portal = road.portal
		local roadPolygon = roadPolygonsById[road.id]
		if portal and roadPolygon then
			portal.coreLeft = roadPolygon.baseLeft
			portal.coreRight = roadPolygon.baseRight
		end
	end

	junction.coreBoundary = {}
	junction.surfaceBoundary = {}
	for _, point in ipairs(hubPolygon) do
		table.insert(junction.coreBoundary, point)
		table.insert(junction.surfaceBoundary, point)
	end
	junction.intersectionGeometry = geometry
	return true
end

function finalizeJunctionPortals(junctions)
	for _, junction in ipairs(junctions) do
		local hasSimplifiedGeometry = applySimplifiedJunctionGeometry(junction)
		if not hasSimplifiedGeometry then
			junction.coreBoundary = buildJunctionCoreBoundary(junction)
		end
		for _, portal in ipairs(junction.portals or {}) do
			updatePortalGeometry(junction, portal)
		end
		if not hasSimplifiedGeometry then
			junction.surfaceBoundary = buildJunctionSurfaceBoundary(junction)
		end
		for _, portal in ipairs(junction.portals or {}) do
			trimChainEndpointToPortal(junction, portal)
		end
	end
end

function finalizeAutomaticJunctionPortals(junctions)
	for _, junction in ipairs(junctions) do
		local hasSimplifiedGeometry = applySimplifiedJunctionGeometry(junction)
		if not hasSimplifiedGeometry then
			junction.coreBoundary = buildJunctionCoreBoundary(junction)
		end
		for _, portal in ipairs(junction.portals or {}) do
			updatePortalGeometry(junction, portal)
		end
		if not hasSimplifiedGeometry then
			junction.surfaceBoundary = buildJunctionSurfaceBoundary(junction)
		end
	end
end

function emitRoadRun(processedChains, sourceChain, runVertices)
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

function emitExplicitRoadRun(processedChains, sourceChain, samples, startPortal, endPortal)
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

function portalRecordForHit(hit, distance)
	return {
		junction = hit.junction,
		point = hit.point,
		distance = distance,
	}
end

function splitOpenPathByExplicitHits(processedChains, path, hits)
	table.sort(hits, function(a, b)
		return a.pathDistance < b.pathDistance
	end)

	local cursor = 0
	local startPortal = nil
	for _, hit in ipairs(hits) do
		local beforeDistance = math.max(0, hit.pathDistance - math.max(hit.beforeCutDistance or 0, 0))
		local afterDistance = math.min(path.totalLength, hit.pathDistance + math.max(hit.afterCutDistance or 0, 0))

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

function splitClosedPathByExplicitHits(processedChains, path, hits)
	table.sort(hits, function(a, b)
		return a.pathDistance < b.pathDistance
	end)
	if #hits == 0 then
		table.insert(processedChains, copyChainWithSamples(path.chain, path.samples, true))
		return
	end

	for i, hit in ipairs(hits) do
		local nextHit = hits[(i % #hits) + 1]
		local hitCutDistance = math.max(hit.afterCutDistance or 0, 0)
		local nextCutDistance = math.max(nextHit.beforeCutDistance or 0, 0)
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

function splitPathByExplicitJunctions(processedChains, path, hits)
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

function appendRoadVertex(vertices, vertex)
	local previous = vertices[#vertices]
	if previous and distanceXZ(previous.point, vertex.point) <= 0.01 and previous.junction == vertex.junction then
		return
	end
	table.insert(vertices, vertex)
end

function splitChainByExplicitJunctions(chain, junctions, processedChains)
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
					point = interpolateSegmentPoint(a, b, t),
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

function applyExplicitJunctionsToChains(chains, junctions)
	local processedChains = {}
	for _, junction in ipairs(junctions) do
		junction.portals = {}
		junction.chains = {}
		junction.intersectionCenter = junction.center
	end
	for _, chain in ipairs(chains) do
		splitChainByExplicitJunctions(chain, junctions, processedChains)
	end
	finalizeJunctionPortals(junctions)
	return processedChains
end

function maxRoadWidthForMembers(members)
	local width = nil
	for _, member in ipairs(members) do
		if member.chain then
			width = math.max(width or 0, sanitizeRoadWidth(member.chain.width))
		end
	end
	return width or ROAD_WIDTH
end

function collectEndpointJunctions(chains)
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

function segmentIntersection2D(a, b, c, d)
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

function collectCrossIntersections(chains)
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

function mergeJunctions(rawJunctions)
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
		local radius = math.max(cluster.width * INTERSECTION_RADIUS_SCALE, ENDPOINT_WELD_DISTANCE * 0.5 + 1)
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

function addInsertForChain(insertsByChain, chain, segment, t, pos)
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

function applyJunctionsToChains(chains, junctions)
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

function buildRoadMeshComponent(chains, junctions, targetModel, meshName)
	local state, err = newMeshState()
	if not state then
		return false, err
	end

	local spans = 0
	for _, chain in ipairs(chains) do
		spans += addRoadRibbonToMesh(state, chain.samples, chain.width, meshName .. "/" .. chain.spline.Name)
	end

	for _, junction in ipairs(junctions) do
		addIntersectionPatchToMesh(state, junction)
	end

	local ok, meshPartOrErr = createNetworkMeshPart(state, targetModel, meshName)
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

function buildRoadComponents(chains, junctions)
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

function collectAutomaticJunctions(chains)
	local rawJunctions = collectEndpointJunctions(chains)
	for _, junction in ipairs(collectCrossIntersections(chains)) do
		table.insert(rawJunctions, junction)
	end

	local junctions = mergeJunctions(rawJunctions)
	for index, junction in ipairs(junctions) do
		junction.name = string.format("AutoJunction%04d", index)
		junction.automatic = true
	end
	return junctions
end

function authoredJunctionSuppressionRadius(junction)
	local center = junction.intersectionCenter or junction.center
	local radius = junction.radius or 0
	for _, portal in ipairs(junction.portals or {}) do
		local point = portal.boundaryPoint or portal.point or center
		radius = math.max(radius, distanceXZ(point, center) + (portal.halfWidth or 0))
	end
	return radius
end

function mergeAuthoredAndAutomaticJunctions(authoredJunctions, automaticJunctions)
	local junctions = {}
	for _, junction in ipairs(authoredJunctions or {}) do
		table.insert(junctions, junction)
	end

	for _, automatic in ipairs(automaticJunctions or {}) do
		local duplicate = false
		for _, authored in ipairs(authoredJunctions or {}) do
			local duplicateDistance = math.max(
				(automatic.width or ROAD_WIDTH) * 0.5,
				automatic.radius or 0,
				authoredJunctionSuppressionRadius(authored)
			)
			if distanceXZ(automatic.center, authored.center) <= duplicateDistance then
				duplicate = true
				break
			end
		end
		if not duplicate then
			table.insert(junctions, automatic)
		end
	end

	return junctions
end

function buildRoadNetworkMeshes(chains, junctions, targetModel)
	local components = buildRoadComponents(chains, junctions)
	local totalSpans = 0
	local totalIntersections = 0
	local allEdges = {}
	local meshParts = {}

	for i, component in ipairs(components) do
		local meshName = #components == 1 and "RoadNetworkMesh" or string.format("RoadNetworkMesh_%03d", i)
		local ok, infoOrErr = buildRoadMeshComponent(component.chains, component.junctions, targetModel, meshName)
		if not ok then
			return false, infoOrErr
		end

		totalSpans += infoOrErr.spans
		totalIntersections += infoOrErr.intersections
		table.insert(meshParts, infoOrErr.meshPart)
		for _, edge in ipairs(infoOrErr.edges) do
			table.insert(allEdges, edge)
		end
	end

	return true, {
		spans = totalSpans,
		intersections = totalIntersections,
		edges = allEdges,
		meshParts = meshParts,
		components = #components,
	}
end

function clearPerSplineRoadMeshes()
	for _, spline in ipairs(sortedSplines()) do
		local road = spline:FindFirstChild(MESH_NAME)
		if road and road:IsA("Model") then
			clearFolder(road)
		end
	end
end

function rebuildRoadMeshPreferred()
	local chains = collectSplineBuildData()
	if #chains == 0 then
		roadDebugWarn("Need at least one spline with 2+ points")
		return 0, "Need at least one spline with 2+ points"
	end
	for i, chain in ipairs(chains) do
		roadDebugLog(
			"rebuild chain %d: name=%s samples=%d width=%.1f closed=%s",
			i,
			chain.spline.Name,
			#chain.samples,
			chain.width,
			tostring(chain.closed)
		)
	end

	local tempNetwork = createTemporaryNetworkModel()

	local authoredJunctions = collectAuthoredJunctions()
	chains = applyExplicitJunctionsToChains(chains, authoredJunctions)
	local automaticJunctions = collectAutomaticJunctions(chains)
	local junctions = mergeAuthoredAndAutomaticJunctions(authoredJunctions, automaticJunctions)
	automaticJunctions = {}
	for index = #authoredJunctions + 1, #junctions do
		table.insert(automaticJunctions, junctions[index])
	end
	applyJunctionsToChains(chains, automaticJunctions)
	attachMemberJunctionPortals(automaticJunctions)
	finalizeAutomaticJunctionPortals(automaticJunctions)
	roadDebugLog(
		"rebuild junctions: authored=%d automatic=%d active=%d processedChains=%d",
		#authoredJunctions,
		#automaticJunctions,
		#junctions,
		#chains
	)

	local okMesh, meshInfo = buildRoadNetworkMeshes(chains, junctions, tempNetwork)
	local totalSpans = 0
	local intersectionCount = #junctions
	local meshCount = 0
	local usedFallback = false

	if okMesh then
		totalSpans = meshInfo.spans
		intersectionCount = meshInfo.intersections
		meshCount = meshInfo.components
		lastWireframeEdges = meshInfo.edges
	else
		usedFallback = true
		lastWireframeEdges = {}
		roadDebugWarn("Unified mesh build failed: %s", tostring(meshInfo))
		clearFolder(tempNetwork)
		for _, chain in ipairs(chains) do
			local meshName = string.format("Road_%s", chain.spline.Name)
			totalSpans += buildPrimitiveRoad(chain.samples, tempNetwork, meshName, chain.width)
		end
	end

	if totalSpans <= 0 then
		tempNetwork:Destroy()
		return 0, "Road rebuild produced no spans; keeping previous mesh"
	end

	local network = getOrCreateNetworkModel()
	clearFolder(network)
	clearPerSplineRoadMeshes()
	for _, child in ipairs(tempNetwork:GetChildren()) do
		child.Parent = network
	end
	tempNetwork:Destroy()

	local wireCount = refreshWireframe()
	local wireNote = wireframeEnabled and string.format(", %d wire edges", wireCount) or ""
	local meshNote = okMesh and string.format(", %d mesh parts", meshCount) or ""
	local note = string.format("Network rebuilt: %d splines%s, %d spans, %d intersections%s%s", #chains, meshNote, totalSpans, intersectionCount, wireNote, usedFallback and " (primitive fallback used)" or "")
	roadDebugLog(note)
	return totalSpans, note
end

function snapPointsToTerrain()
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

function removeLastPoint()
	local points = sortedPoints()
	if #points == 0 then
		return false
	end
	points[#points]:Destroy()
	renumberPoints()
	return true
end

function removeSelectedPoint()
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

function selectedPointWithIndex()
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

function setSelectedPointY(mode)
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

function countSegments()
	local road = getOrCreateNetworkModel()
	local n = 0
	for _, child in ipairs(road:GetChildren()) do
		if child:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

function shouldRestoreRoadMesh()
	local road = getOrCreateNetworkModel()
	local surfaceCount = 0
	local hasGeneratedMeshPart = false
	for _, child in ipairs(road:GetChildren()) do
		if child:IsA("BasePart") then
			surfaceCount += 1
			if child:IsA("MeshPart") and child:GetAttribute("GeneratedBy") == "Cab87RoadEditor" then
				hasGeneratedMeshPart = true
			end
		end
	end

	return surfaceCount == 0 or hasGeneratedMeshPart
end

-- UI
function initPlugin()
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

function makeButton(text)
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

function makeControlRow()
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

function makeInlineButton(parent, text, width)
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

function makeInlineLabel(parent, text, width)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, width, 1, 0)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(200, 200, 205)
	label.Font = Enum.Font.GothamSemibold
	label.TextSize = 12
	label.Text = text
	label.Parent = parent
	return label
end

function makeTextBox(parent, placeholder)
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
title.Text = "Spline track editor (Legacy)"
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

function updateStatus(extra)
	local points = #sortedPoints()
	local segments = countSegments()
	local curveMode = isClosedCurve() and "Closed" or "Open"
	local wireMode = wireframeEnabled and "On" or "Off"
	local active = getActiveSpline()
	local width = formatRoadWidth(getSplineRoadWidth(active))
	local splineCount = #sortedSplines()
	local junctionCount = #sortedJunctions()
	local base = string.format("Spline: %s (%d total) | Width: %s | Points: %d | Junctions: %d | Road parts: %d | Curve: %s | Wire: %s", active.Name, splineCount, width, points, junctionCount, segments, curveMode, wireMode)
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
local junctionRadiusRow = makeControlRow()
local btnJunctionRadiusDown = makeInlineButton(junctionRadiusRow, "-4", 42)
local junctionRadiusInput = makeTextBox(junctionRadiusRow, "Junction radius")
local btnJunctionRadiusUp = makeInlineButton(junctionRadiusRow, "+4", 42)
local junctionSubdivisionsRow = makeControlRow()
local btnJunctionSubdivisionsDown = makeInlineButton(junctionSubdivisionsRow, "-1", 42)
local junctionSubdivisionsInput = makeTextBox(junctionSubdivisionsRow, "Junction subdivisions")
local btnJunctionSubdivisionsUp = makeInlineButton(junctionSubdivisionsRow, "+1", 42)
local importPlaneRow = makeControlRow()
local _importPlaneLabel = makeInlineLabel(importPlaneRow, "Import Y", 72)
local importPlaneInput = makeTextBox(importPlaneRow, "Plane Y")
local btnImportAppend = makeButton("Import Curve JSON (Append)")
local btnImportReplace = makeButton("Import Curve JSON (Replace)")
local btnAddJunctionCamera = makeButton("Add Junction (Camera Hit)")
local btnAddJunctionSelected = makeButton("Add Junction (From Selection)")
local btnDeleteJunction = makeButton("Delete Selected Junction")
local btnAddCamera = makeButton("Add Point (Camera Hit)")
local btnAddSelected = makeButton("Add Point (From Selection)")
local btnSetCabCompany = makeButton("Set Cab Company Node (Camera)")
local btnSelectCabCompany = makeButton("Select Cab Company Node")
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

function refreshCurveModeButton()
	btnCloseCurve.Text = isClosedCurve() and "Curve Mode: Closed" or "Curve Mode: Open"
end

function refreshAutoRebuildButton()
	btnAutoRebuild.Text = autoRebuildEnabled and "Auto Rebuild: On" or "Auto Rebuild: Off"
end

function refreshWireframeButton()
	btnWireframe.Text = wireframeEnabled and "Wireframe Mesh: On" or "Wireframe Mesh: Off"
end

function refreshRoadWidthInput()
	widthInput.Text = formatRoadWidth(getActiveRoadWidth())
end

function refreshJunctionRadiusInput()
	junctionRadiusInput.Text = formatJunctionRadius(getActiveJunctionRadius())
end

function refreshJunctionSubdivisionsInput()
	junctionSubdivisionsInput.Text = formatJunctionSubdivisions(getActiveJunctionSubdivisions())
end

function refreshImportPlaneInput()
	importPlaneInput.Text = formatImportPlaneY(importPlaneY)
end

local scheduleAutoRebuild

function updateActiveRoadWidth(value, reason)
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

function updateSelectedJunctionRadius(value, reason)
	local junction = getSelectedJunction()
	local radius = tonumber(value)
	if not radius then
		refreshJunctionRadiusInput()
		updateStatus("Enter a numeric junction radius")
		return
	end

	radius = sanitizeJunctionRadius(radius)
	if junction then
		ChangeHistoryService:SetWaypoint("cab87 roads before junction radius change")
		junction:SetAttribute("Radius", radius)
		local displaySize = math.max(radius * 0.35, 5)
		junction.Size = Vector3.new(displaySize, displaySize, displaySize)
		ChangeHistoryService:SetWaypoint("cab87 roads after junction radius change")
		scheduleAutoRebuild(reason or "junction-radius-changed")
		updateStatus(string.format("Set %s radius to %s studs", junction.Name, formatJunctionRadius(radius)))
	else
		defaultJunctionRadius = radius
		updateStatus(string.format("Default junction radius set to %s studs", formatJunctionRadius(radius)))
	end
	refreshJunctionRadiusInput()
end

function updateSelectedJunctionSubdivisions(value, reason)
	local junction = getSelectedJunction()
	local subdivisions = tonumber(value)
	if not subdivisions then
		refreshJunctionSubdivisionsInput()
		updateStatus("Enter a numeric junction subdivision count")
		return
	end

	subdivisions = sanitizeJunctionSubdivisions(subdivisions)
	if junction then
		ChangeHistoryService:SetWaypoint("cab87 roads before junction subdivisions change")
		junction:SetAttribute("Subdivisions", subdivisions)
		ChangeHistoryService:SetWaypoint("cab87 roads after junction subdivisions change")
		scheduleAutoRebuild(reason or "junction-subdivisions-changed")
		updateStatus(string.format("Set %s subdivisions to %s", junction.Name, formatJunctionSubdivisions(subdivisions)))
	else
		defaultJunctionSubdivisions = subdivisions
		updateStatus(string.format("Default junction subdivisions set to %s", formatJunctionSubdivisions(subdivisions)))
	end
	refreshJunctionSubdivisionsInput()
end

function updateImportPlaneY(value)
	local planeY = tonumber(value)
	if not planeY then
		refreshImportPlaneInput()
		updateStatus("Enter a numeric import plane Y")
		return
	end

	importPlaneY = sanitizeImportPlaneY(planeY)
	plugin:SetSetting(IMPORT_PLANE_Y_SETTING, importPlaneY)
	refreshImportPlaneInput()
	updateStatus(string.format("Import plane Y set to %s studs", formatImportPlaneY(importPlaneY)))
end

function runAutoRoadRebuild(reason)
	if autoRebuildRunning then
		scheduleAutoRebuild(reason or "queued")
		return
	end

	autoRebuildRunning = true
	local ok, segs, note = pcall(rebuildRoadMeshPreferred)
	autoRebuildRunning = false
	if not ok then
		local message = tostring(segs)
		roadDebugWarn("Auto rebuild failed (%s); previous mesh was kept: %s", tostring(reason), message)
		updateStatus("Auto rebuild failed; previous road mesh was kept")
		return
	end

	updateStatus(string.format("Auto rebuilt (%d spans). %s", segs, note or ""))
	roadDebugLog("Auto rebuild (%s): %d spans", tostring(reason), segs)
end

local pointWatchers = {}
local junctionLastPositions = {}

function disconnectPointWatcher(point)
	local conns = pointWatchers[point]
	if not conns then
		return
	end
	for _, conn in ipairs(conns) do
		conn:Disconnect()
	end
	pointWatchers[point] = nil
	junctionLastPositions[point] = nil
end

function moveGroupedControlPointsWithJunction(junction)
	local previousPosition = junctionLastPositions[junction]
	if not previousPosition then
		junctionLastPositions[junction] = junction.Position
		return
	end

	local currentPosition = junction.Position
	local delta = currentPosition - previousPosition
	if delta.Magnitude <= 1e-4 then
		junctionLastPositions[junction] = currentPosition
		return
	end

	local radius = sanitizeJunctionRadius(junction:GetAttribute("Radius"))
	local groupedPoints = collectControlPointsInJunctionPosition(previousPosition, radius)
	for _, point in ipairs(groupedPoints) do
		point.Position += delta
	end
	junctionLastPositions[junction] = currentPosition
end

function scheduleAutoRebuild(reason)
	if bulkImportInProgress or not autoRebuildEnabled then
		return
	end
	autoRebuildSerial += 1
	autoRebuildReason = reason
	autoRebuildDueTime = os.clock() + AUTO_REBUILD_DELAY
	if autoRebuildScheduled then
		return
	end
	autoRebuildScheduled = true
	task.spawn(function()
		local observedSerial = autoRebuildSerial
		while autoRebuildEnabled do
			local waitTime = autoRebuildDueTime - os.clock()
			if waitTime <= 0 then
				break
			end
			task.wait(waitTime)
			observedSerial = autoRebuildSerial
		end
		autoRebuildScheduled = false
		if not autoRebuildEnabled then
			return
		end
		if observedSerial ~= autoRebuildSerial then
			scheduleAutoRebuild(autoRebuildReason or reason)
			return
		end
		runAutoRoadRebuild(autoRebuildReason or reason)
	end)
end

function refreshPointWatchers()
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
	for _, junction in ipairs(sortedJunctions()) do
		alive[junction] = true
		if not pointWatchers[junction] then
			junctionLastPositions[junction] = junction.Position
			pointWatchers[junction] = {
				junction:GetPropertyChangedSignal("Position"):Connect(function()
					moveGroupedControlPointsWithJunction(junction)
					scheduleAutoRebuild("junction-moved")
				end),
				junction:GetAttributeChangedSignal("Radius"):Connect(function()
					scheduleAutoRebuild("junction-radius-changed")
				end),
				junction:GetAttributeChangedSignal("Subdivisions"):Connect(function()
					scheduleAutoRebuild("junction-subdivisions-changed")
				end),
				junction.AncestryChanged:Connect(function(_, parent)
					if parent == nil then
						disconnectPointWatcher(junction)
					end
				end),
			}
		end
	end

	for p in pairs(pointWatchers) do
		if not alive[p] then
			disconnectPointWatcher(p)
		end
	end
end

function applyImportedCurves(importedSplines, replaceExisting, importedJunctions)
	local created = {}
	local previousBulkImport = bulkImportInProgress
	bulkImportInProgress = true

	local ok, rebuildSegmentsOrErr, rebuildNote = pcall(function()
		if replaceExisting then
			clearAllSplines()
			clearFolder(getOrCreateNetworkModel())
			clearFolder(getOrCreateJunctionsFolder())
			lastWireframeEdges = {}
		end

		for _, data in ipairs(importedSplines) do
			table.insert(created, createImportedSpline(data))
		end
		for _, junctionData in ipairs(importedJunctions or {}) do
			addJunction(junctionData.position, junctionData.radius, junctionData.subdivisions)
		end

		if #created == 0 then
			error("No imported splines were created", 0)
		end

		setActiveSpline(created[1])
		return rebuildRoadMeshPreferred()
	end)

	bulkImportInProgress = previousBulkImport
	refreshPointWatchers()
	refreshCurveModeButton()
	refreshRoadWidthInput()
	refreshImportPlaneInput()

	if not ok then
		error(rebuildSegmentsOrErr, 0)
	end

	return {
		splineCount = #created,
		rebuildSegments = rebuildSegmentsOrErr,
		rebuildNote = rebuildNote,
	}
end

function importCurveJson(replaceExisting)
	local okFile, fileOrErr = pcall(function()
		return StudioService:PromptImportFileAsync(IMPORT_FILE_FILTER)
	end)
	if not okFile then
		updateStatus("Import failed to open file picker: " .. tostring(fileOrErr))
		return
	end

	local file = fileOrErr
	if not file then
		updateStatus("Curve import canceled")
		return
	end

	local contents, readErr = readImportedFileContents(file)
	if not contents then
		updateStatus("Curve import failed: " .. tostring(readErr))
		return
	end

	local importedSplines, summary, parseErr = parseImportedCurveJson(contents, importPlaneY)
	if not importedSplines then
		updateStatus("Curve import failed: " .. tostring(parseErr))
		return
	end

	ChangeHistoryService:SetWaypoint("cab87 roads before curve json import")
	local okImport, resultOrErr = pcall(function()
		return applyImportedCurves(importedSplines, replaceExisting, summary.importedJunctions)
	end)
	if not okImport then
		updateStatus("Curve import failed: " .. tostring(resultOrErr))
		return
	end
	ChangeHistoryService:SetWaypoint("cab87 roads after curve json import")

	local result = resultOrErr
	local action = replaceExisting and "Replaced" or "Appended"
	local skippedNote = summary.skippedSplineCount > 0 and string.format(" Skipped %d invalid spline(s).", summary.skippedSplineCount) or ""
	local mirrorNote = summary.mirroredX and " Mirrored editor X to Studio coordinates." or ""
	updateStatus(string.format(
		"%s %d spline(s), %d point(s), %d junction(s) at Y=%s. %s%s%s",
		action,
		result.splineCount,
		summary.importedPointCount,
		summary.importedJunctionCount,
		formatImportPlaneY(importPlaneY),
		result.rebuildNote or string.format("Rebuilt road (%d spans).", result.rebuildSegments or 0),
		skippedNote,
		mirrorNote
	))
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

btnJunctionRadiusDown.MouseButton1Click:Connect(function()
	updateSelectedJunctionRadius(getActiveJunctionRadius() - JUNCTION_RADIUS_STEP, "junction-radius-changed")
end)

btnJunctionRadiusUp.MouseButton1Click:Connect(function()
	updateSelectedJunctionRadius(getActiveJunctionRadius() + JUNCTION_RADIUS_STEP, "junction-radius-changed")
end)

junctionRadiusInput.FocusLost:Connect(function()
	updateSelectedJunctionRadius(junctionRadiusInput.Text, "junction-radius-changed")
end)

btnJunctionSubdivisionsDown.MouseButton1Click:Connect(function()
	updateSelectedJunctionSubdivisions(getActiveJunctionSubdivisions() - JUNCTION_SUBDIVISIONS_STEP, "junction-subdivisions-changed")
end)

btnJunctionSubdivisionsUp.MouseButton1Click:Connect(function()
	updateSelectedJunctionSubdivisions(getActiveJunctionSubdivisions() + JUNCTION_SUBDIVISIONS_STEP, "junction-subdivisions-changed")
end)

junctionSubdivisionsInput.FocusLost:Connect(function()
	updateSelectedJunctionSubdivisions(junctionSubdivisionsInput.Text, "junction-subdivisions-changed")
end)

importPlaneInput.FocusLost:Connect(function()
	updateImportPlaneY(importPlaneInput.Text)
end)

btnImportAppend.MouseButton1Click:Connect(function()
	importCurveJson(false)
end)

btnImportReplace.MouseButton1Click:Connect(function()
	importCurveJson(true)
end)

btnAddJunctionCamera.MouseButton1Click:Connect(function()
	local pos = raycastFromCamera(4000)
	if not pos then
		updateStatus("Could not raycast junction from camera")
		return
	end
	ChangeHistoryService:SetWaypoint("cab87 roads before add junction camera")
	local junction, err = addConnectedJunction(pos, sanitizeJunctionRadius(junctionRadiusInput.Text), sanitizeJunctionSubdivisions(junctionSubdivisionsInput.Text))
	if not junction then
		updateStatus(err or "Could not add junction")
		return
	end
	ChangeHistoryService:SetWaypoint("cab87 roads after add junction camera")
	Selection:Set({ junction })
	refreshJunctionRadiusInput()
	refreshJunctionSubdivisionsInput()
	scheduleAutoRebuild("junction-added")
	updateStatus("Added " .. junction.Name)
end)

btnAddJunctionSelected.MouseButton1Click:Connect(function()
	local sel = Selection:Get()
	if #sel == 0 or not sel[1]:IsA("BasePart") then
		updateStatus("Select a part first to add a junction at its position")
		return
	end
	ChangeHistoryService:SetWaypoint("cab87 roads before add junction selection")
	local junction, err = addConnectedJunction(sel[1].Position, sanitizeJunctionRadius(junctionRadiusInput.Text), sanitizeJunctionSubdivisions(junctionSubdivisionsInput.Text))
	if not junction then
		updateStatus(err or "Could not add junction")
		return
	end
	ChangeHistoryService:SetWaypoint("cab87 roads after add junction selection")
	Selection:Set({ junction })
	refreshJunctionRadiusInput()
	refreshJunctionSubdivisionsInput()
	scheduleAutoRebuild("junction-added")
	updateStatus("Added " .. junction.Name .. " from selection")
end)

btnDeleteJunction.MouseButton1Click:Connect(function()
	local junction = getSelectedJunction()
	if not junction then
		updateStatus("Select a junction first")
		return
	end
	ChangeHistoryService:SetWaypoint("cab87 roads before delete junction")
	local name = junction.Name
	junction:Destroy()
	ChangeHistoryService:SetWaypoint("cab87 roads after delete junction")
	refreshJunctionRadiusInput()
	refreshJunctionSubdivisionsInput()
	scheduleAutoRebuild("junction-deleted")
	updateStatus("Deleted " .. name)
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

btnSetCabCompany.MouseButton1Click:Connect(function()
	ChangeHistoryService:SetWaypoint("cab87 roads before cab company node")
	local node = setCabCompanyNodeFromCamera()
	ChangeHistoryService:SetWaypoint("cab87 roads after cab company node")
	if not node then
		updateStatus("Could not raycast cab company node from camera")
		return
	end

	Selection:Set({ node })
	updateStatus("Cab company node set; cab spawns here in Play")
end)

btnSelectCabCompany.MouseButton1Click:Connect(function()
	if selectCabCompanyNode() then
		updateStatus("Selected cab company node")
	else
		updateStatus("No cab company node yet")
	end
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
	if bulkImportInProgress then
		return
	end
	local sel = Selection:Get()
	if #sel > 0 then
		local spline = getSplineFromControlPoint(sel[1])
		if spline then
			setActiveSpline(spline)
			refreshCurveModeButton()
			refreshRoadWidthInput()
			refreshPointWatchers()
		elseif getSelectedJunction() then
			refreshJunctionRadiusInput()
			refreshJunctionSubdivisionsInput()
		end
	end
	updateStatus(nil)
end)

local splinesFolder = getOrCreateSplinesFolder()
splinesFolder.DescendantAdded:Connect(function(inst)
	if bulkImportInProgress then
		return
	end
	if isControlPoint(inst) then
		refreshPointWatchers()
		scheduleAutoRebuild("point-added")
		updateStatus(nil)
	end
end)
splinesFolder.DescendantRemoving:Connect(function(inst)
	if bulkImportInProgress then
		return
	end
	if isControlPoint(inst) then
		refreshPointWatchers()
		scheduleAutoRebuild("point-removed")
		updateStatus(nil)
	end
end)

local junctionsFolder = getOrCreateJunctionsFolder()
junctionsFolder.ChildAdded:Connect(function(inst)
	if bulkImportInProgress then
		return
	end
	if inst:IsA("BasePart") then
		refreshPointWatchers()
		scheduleAutoRebuild("junction-added")
		updateStatus(nil)
	end
end)
junctionsFolder.ChildRemoved:Connect(function(inst)
	if bulkImportInProgress then
		return
	end
	if inst:IsA("BasePart") then
		refreshPointWatchers()
		scheduleAutoRebuild("junction-removed")
		updateStatus(nil)
	end
end)

function restoreMissingRoadMesh()
	if not shouldRestoreRoadMesh() then
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
refreshJunctionRadiusInput()
refreshJunctionSubdivisionsInput()
refreshImportPlaneInput()
refreshAutoRebuildButton()
refreshWireframeButton()
updateStatus("Panel stays open while you iterate")
task.defer(restoreMissingRoadMesh)
end

initPlugin()
