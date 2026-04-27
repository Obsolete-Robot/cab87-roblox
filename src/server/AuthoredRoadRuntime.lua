local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadGraphData = require(Shared:WaitForChild("RoadGraphData"))
local RoadGraphMesher = require(Shared:WaitForChild("RoadGraphMesher"))

local CabCompanyWorldBuilder = require(script.Parent:WaitForChild("CabCompanyWorldBuilder"))

local AuthoredRoadRuntime = {}

local ROAD_LOG_PREFIX = "[cab87 road graph]"
local RUNTIME_WORLD_NAME = "Cab87World"
local BAKED_RUNTIME_NAME = "RoadGraphBakedRuntime"
local BAKED_SURFACES_NAME = "RoadGraphBakedSurfaces"
local BAKED_COLLISION_NAME = "RoadGraphBakedCollision"
local MARKER_TYPE_ATTR = "Cab87MarkerType"

local function roadDebugLog(message, ...)
	if Config.authoredRoadDebugLogging == true then
		local ok, formatted = pcall(string.format, tostring(message), ...)
		print(ROAD_LOG_PREFIX .. " " .. (ok and formatted or tostring(message)))
	end
end

local function roadDebugWarn(message, ...)
	local ok, formatted = pcall(string.format, tostring(message), ...)
	warn(ROAD_LOG_PREFIX .. " " .. (ok and formatted or tostring(message)))
end

local function yawToForward(yaw)
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

local function yawFromVector(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return 0
	end
	local unit = horizontal.Unit
	return math.atan2(unit.X, unit.Z)
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
	local markerType = part:GetAttribute(MARKER_TYPE_ATTR)
	return markerType == "CabCompany" or markerType == "CabCompanyNode"
end

local function isPlayerSpawnMarker(part)
	if not (part and part:IsA("BasePart")) then
		return false
	end
	return part:GetAttribute(MARKER_TYPE_ATTR) == "PlayerSpawn"
end

local function findAuthoredMarker(root, markerName, predicate)
	local markersFolder = getMarkerFolder(root)
	if not markersFolder then
		return nil
	end

	local named = markersFolder:FindFirstChild(markerName)
	if named and predicate(named) then
		return named
	end

	for _, child in ipairs(markersFolder:GetChildren()) do
		if predicate(child) then
			return child
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

local function getGraphSpawnPose(graph)
	local firstEdge = graph.edges and graph.edges[1]
	local nodeLookup = graph.nodeLookup or {}
	local firstNode = firstEdge and nodeLookup[firstEdge.source] or graph.nodes[1]
	local spawnPosition = firstNode and firstNode.point or Config.carSpawn
	local yaw = 0

	if firstEdge then
		local nextPoint = firstEdge.points and firstEdge.points[1]
		if not nextPoint and firstEdge.target and nodeLookup[firstEdge.target] then
			nextPoint = nodeLookup[firstEdge.target].point
		end
		if nextPoint then
			yaw = yawFromVector(nextPoint - spawnPosition)
		end
	end

	return {
		position = spawnPosition + Vector3.new(0, Config.carRideHeight or 2.3, 0),
		yaw = yaw,
	}
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

local function hideEditorRootForPlay(root)
	if not root then
		return
	end

	local bakedContainer = root:FindFirstChild(BAKED_RUNTIME_NAME) or root
	local bakedSurfaces = bakedContainer:FindFirstChild(BAKED_SURFACES_NAME)
	local bakedCollision = bakedContainer:FindFirstChild(BAKED_COLLISION_NAME)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if bakedSurfaces and hasAncestor(descendant, bakedSurfaces) then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
			elseif bakedCollision and hasAncestor(descendant, bakedCollision) then
				descendant.Anchored = true
				descendant.CanCollide = true
				descendant.CanTouch = false
				descendant.CanQuery = true
				descendant.Transparency = 1
				descendant:SetAttribute("DriveSurface", true)
			else
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Transparency = 1
			end
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		end
	end
	root:SetAttribute("HiddenForPlay", true)
end

local function appendAll(target, source)
	for _, item in ipairs(source or {}) do
		table.insert(target, item)
	end
end

local function collectBaseParts(root, target)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(target, descendant)
		end
	end
end

local function useBakedGraphMeshes(root)
	local bakedContainer = root:FindFirstChild(BAKED_RUNTIME_NAME) or root
	local sourceMeshFolder = bakedContainer:FindFirstChild(BAKED_SURFACES_NAME)
	local sourceCollisionFolder = bakedContainer:FindFirstChild(BAKED_COLLISION_NAME)
	if not (sourceMeshFolder and sourceCollisionFolder) then
		return nil
	end

	local visibleParts = {}
	local collisionParts = {}
	collectBaseParts(sourceMeshFolder, visibleParts)
	collectBaseParts(sourceCollisionFolder, collisionParts)
	if #visibleParts == 0 or #collisionParts == 0 then
		return nil
	end

	for _, part in ipairs(visibleParts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end

	for _, part in ipairs(collisionParts) do
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		part.Transparency = 1
		part:SetAttribute("DriveSurface", true)
	end

	return {
		meshFolder = sourceMeshFolder,
		collisionFolder = sourceCollisionFolder,
		visibleParts = visibleParts,
		collisionParts = collisionParts,
		driveSurfaces = collisionParts,
		errors = {},
		source = "baked",
	}
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
		source = "AuthoredRoadGraph",
		extraDriveSurfaces = driveSurfaces,
		extraCrashObstacles = crashObstacles,
	})

	table.clear(driveSurfaces)
	table.clear(crashObstacles)
	appendAll(driveSurfaces, result.driveSurfaces)
	appendAll(crashObstacles, result.crashObstacles)
	return result.spawnPose
end

local function buildGraphMeshes(root, world, graph)
	local meshData = RoadGraphMesher.buildNetworkMesh(graph, graph.settings)

	local bakedMeshResult = useBakedGraphMeshes(root)
	if bakedMeshResult then
		roadDebugLog(
			"using baked graph meshes: visibleParts=%d collisionParts=%d",
			#bakedMeshResult.visibleParts,
			#bakedMeshResult.collisionParts
		)
		return meshData, bakedMeshResult
	end

	error("Baked road graph geometry was not found. Click Bake Runtime Geometry in the Road Graph Builder plugin before Play.", 0)
end

function AuthoredRoadRuntime.getRoot()
	local root = Workspace:FindFirstChild(RoadGraphData.EDITOR_ROOT_NAME)
	if root and root:IsA("Model") then
		roadDebugLog("found authored road root: %s", root:GetFullName())
		return root
	end

	roadDebugLog("authored road root not found: %s", RoadGraphData.EDITOR_ROOT_NAME)
	return nil
end

function AuthoredRoadRuntime.hasRoadData(root)
	if Config.useAuthoredRoadEditorWorld ~= true or not root then
		return false
	end
	return RoadGraphData.hasGraph(root)
end

function AuthoredRoadRuntime.createWorld(root)
	local graph = RoadGraphData.collectGraph(root, Config)
	if not graph then
		error("Cab87RoadEditor does not contain valid RoadGraph data", 0)
	end

	local oldWorld = Workspace:FindFirstChild(RUNTIME_WORLD_NAME)
	if oldWorld then
		oldWorld:Destroy()
	end

	local world = Instance.new("Model")
	world.Name = RUNTIME_WORLD_NAME
	world:SetAttribute("GeneratorVersion", "road-graph-v1")
	world:SetAttribute("Source", RoadGraphData.EDITOR_ROOT_NAME)
	world:SetAttribute("NeedsClientRoadMesh", false)
	world.Parent = Workspace

	RoadGraphData.writeGraph(world, graph, RoadGraphData.RUNTIME_DATA_NAME)

	local meshData, meshBuild = buildGraphMeshes(root, world, graph)
	local driveSurfaces = {}
	local crashObstacles = {}
	appendAll(driveSurfaces, meshBuild.driveSurfaces)

	local spawnPose = getGraphSpawnPose(graph)
	local authoredCabCompanyMarker = findAuthoredCabCompanyMarker(root)
	if authoredCabCompanyMarker then
		spawnPose = {
			position = authoredCabCompanyMarker.Position,
			yaw = CabCompanyWorldBuilder.yawFromCFrame(authoredCabCompanyMarker.CFrame),
		}
	end

	local cabCompanySpawnPose = buildAuthoredCabCompany(root, world, driveSurfaces, crashObstacles)
	if cabCompanySpawnPose then
		spawnPose = cabCompanySpawnPose
	end

	world:SetAttribute("AuthoredRoadFormat", "RoadGraph")
	world:SetAttribute("AuthoredRoadNodeCount", #(graph.nodes or {}))
	world:SetAttribute("AuthoredRoadEdgeCount", #(graph.edges or {}))
	world:SetAttribute("AuthoredRoadRoadTriangles", #(meshData.roadTriangles or {}))
	world:SetAttribute("AuthoredRoadSidewalkTriangles", #(meshData.sidewalkTriangles or {}))
	world:SetAttribute("AuthoredRoadCrosswalkTriangles", #(meshData.crosswalkTriangles or {}))
	world:SetAttribute("AuthoredRoadMeshSource", meshBuild.source or "runtime")
	world:SetAttribute("AuthoredRoadServerCollisionSource", BAKED_COLLISION_NAME)
	world:SetAttribute("AuthoredRoadServerMeshError", "")

	roadDebugLog(
		"road graph world built: nodes=%d edges=%d roadTris=%d sidewalkTris=%d crosswalkTris=%d driveSurfaces=%d spawn=(%.1f, %.1f, %.1f) forward=(%.2f, %.2f, %.2f)",
		#(graph.nodes or {}),
		#(graph.edges or {}),
		#(meshData.roadTriangles or {}),
		#(meshData.sidewalkTriangles or {}),
		#(meshData.crosswalkTriangles or {}),
		#driveSurfaces,
		spawnPose.position.X,
		spawnPose.position.Y,
		spawnPose.position.Z,
		yawToForward(spawnPose.yaw).X,
		yawToForward(spawnPose.yaw).Y,
		yawToForward(spawnPose.yaw).Z
	)

	if #meshBuild.errors > 0 then
		roadDebugWarn("some road graph surfaces were skipped: %s", table.concat(meshBuild.errors, " | "))
	end

	hideEditorRootForPlay(root)
	return world, driveSurfaces, crashObstacles, spawnPose
end

return AuthoredRoadRuntime
