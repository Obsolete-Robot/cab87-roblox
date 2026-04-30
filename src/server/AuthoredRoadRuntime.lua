local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadGraphData = require(Shared:WaitForChild("RoadGraphData"))
local RoadGraphMesher = require(Shared:WaitForChild("RoadGraphMesher"))
local RoadSampling = require(Shared:WaitForChild("RoadSampling"))
local RoadSplineData = require(Shared:WaitForChild("RoadSplineData"))

local CabCompanyWorldBuilder = require(script.Parent:WaitForChild("CabCompanyWorldBuilder"))

local AuthoredRoadRuntime = {}

local ROAD_LOG_PREFIX = "[cab87 road graph]"
local RUNTIME_WORLD_NAME = "Cab87World"
local BAKED_RUNTIME_NAME = "RoadGraphBakedRuntime"
local BAKED_SURFACES_NAME = "RoadGraphBakedSurfaces"
local BAKED_COLLISION_NAME = "RoadGraphBakedCollision"
local LEGACY_COLLISION_NAME = "RoadNetworkCollision"
local LEGACY_RUNTIME_COLLISION_GENERATOR = "Cab87LegacyRoadRuntimeCollision"
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

local function isCabCompanyRefuelMarker(part)
	if not (part and part:IsA("BasePart")) then
		return false
	end
	local markerType = part:GetAttribute(MARKER_TYPE_ATTR)
	return markerType == "CabRefuel" or markerType == "CabRefuelPoint"
end

local function isCabCompanyServiceMarker(part)
	if not (part and part:IsA("BasePart")) then
		return false
	end
	local markerType = part:GetAttribute(MARKER_TYPE_ATTR)
	return markerType == "CabService" or markerType == "CabServicePoint"
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

local function findAuthoredCabCompanyRefuelMarker(root)
	return findAuthoredMarker(root, Config.cabCompanyRefuelMarkerName or "CabRefuelPoint", isCabCompanyRefuelMarker)
end

local function findAuthoredCabCompanyServiceMarker(root)
	return findAuthoredMarker(root, Config.cabCompanyServiceMarkerName or "CabServicePoint", isCabCompanyServiceMarker)
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

local function hideEditorRootForPlay(root, options)
	if not root then
		return
	end

	options = options or {}
	local preserveBakedGraph = options.preserveBakedGraph == true
	local bakedContainer = if preserveBakedGraph then root:FindFirstChild(BAKED_RUNTIME_NAME) or root else nil
	local bakedSurfaces = bakedContainer and bakedContainer:FindFirstChild(BAKED_SURFACES_NAME)
	local bakedCollision = bakedContainer and bakedContainer:FindFirstChild(BAKED_COLLISION_NAME)
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

local function getLegacyCollisionWidth()
	return RoadSampling.getConfiguredRoadWidth(Config)
end

local function getLegacyCollisionThickness()
	return math.max(tonumber(Config.authoredRoadCollisionThickness) or 0.2, 0.1)
end

local function getLegacyCollisionSurfaceOffset()
	return tonumber(Config.authoredRoadCollisionSurfaceOffset) or 0.6
end

local function getLegacyCollisionOverlap()
	return math.max(tonumber(Config.authoredRoadOverlap) or 1, 0)
end

local function configureLegacyCollisionPart(part)
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	part.Transparency = 1
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("DriveSurface", true)
	part:SetAttribute("GeneratedBy", LEGACY_RUNTIME_COLLISION_GENERATOR)
	return part
end

local function createLegacySegmentCollision(parent, a, b, roadWidth, index)
	local horizontal = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = horizontal.Magnitude
	if length <= 0.5 then
		return nil
	end

	local forward = horizontal.Unit
	local right = Vector3.new(forward.Z, 0, -forward.X)
	local thickness = getLegacyCollisionThickness()
	local surfaceY = ((a.Y + b.Y) * 0.5) + getLegacyCollisionSurfaceOffset()
	local center = Vector3.new((a.X + b.X) * 0.5, surfaceY - thickness * 0.5, (a.Z + b.Z) * 0.5)

	local part = Instance.new("Part")
	part.Name = string.format("RoadSegmentCollision_%04d", index)
	part.Size = Vector3.new(
		RoadSampling.sanitizeRoadWidth(roadWidth, getLegacyCollisionWidth()),
		thickness,
		length + getLegacyCollisionOverlap()
	)
	part.CFrame = CFrame.fromMatrix(center, right, Vector3.yAxis, forward)
	configureLegacyCollisionPart(part)
	part.Parent = parent
	return part
end

local function createLegacyJunctionCollision(parent, junction, roadWidth, index)
	local radius = math.max(tonumber(junction.radius) or 0, RoadSampling.sanitizeRoadWidth(roadWidth, getLegacyCollisionWidth()) * 0.5)
	if radius <= 0.5 then
		return nil
	end

	local thickness = getLegacyCollisionThickness()
	local center = junction.center + Vector3.new(0, getLegacyCollisionSurfaceOffset() - thickness * 0.5, 0)
	local part = Instance.new("Part")
	part.Name = string.format("RoadJunctionCollision_%04d", index)
	part.Size = Vector3.new(radius * 2, thickness, radius * 2)
	part.CFrame = CFrame.new(center)
	configureLegacyCollisionPart(part)
	part.Parent = parent
	return part
end

local function createLegacyCurveCollision(world, dataRoot)
	local collisionFolder = Instance.new("Folder")
	collisionFolder.Name = LEGACY_COLLISION_NAME
	collisionFolder.Parent = world

	local collisionParts = {}
	local defaultRoadWidth = getLegacyCollisionWidth()
	local segmentIndex = 0
	local chains = RoadSplineData.collectSampledChains(dataRoot, {
		defaultRoadWidth = defaultRoadWidth,
		sampleStep = tonumber(Config.authoredRoadSampleStepStuds) or 8,
	})

	for _, chain in ipairs(chains) do
		local samples = chain.samples or {}
		for index = 1, #samples - 1 do
			segmentIndex += 1
			local part = createLegacySegmentCollision(collisionFolder, samples[index], samples[index + 1], chain.width, segmentIndex)
			if part then
				table.insert(collisionParts, part)
			end
		end

		if chain.closed and #samples >= 3 and not RoadSampling.sampleLoopIsClosed(samples) then
			segmentIndex += 1
			local part = createLegacySegmentCollision(collisionFolder, samples[#samples], samples[1], chain.width, segmentIndex)
			if part then
				table.insert(collisionParts, part)
			end
		end
	end

	for index, junction in ipairs(RoadSplineData.collectJunctions(dataRoot, {
		defaultRadius = defaultRoadWidth * 0.5,
		minRadius = 0,
	})) do
		local part = createLegacyJunctionCollision(collisionFolder, junction, defaultRoadWidth, index)
		if part then
			table.insert(collisionParts, part)
		end
	end

	if #collisionParts == 0 then
		collisionFolder:Destroy()
		return nil, {}
	end

	collisionFolder:SetAttribute("GeneratedBy", LEGACY_RUNTIME_COLLISION_GENERATOR)
	collisionFolder:SetAttribute("CollisionPartCount", #collisionParts)
	return collisionFolder, collisionParts
end

local function projectCabSpawnToDriveSurface(position, driveSurfaces)
	if typeof(position) ~= "Vector3" or #driveSurfaces == 0 then
		return position
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = driveSurfaces

	local probeHeight = math.max((Config.carGroundProbeHeight or 90) + (Config.carRideHeight or 2.3), 40)
	local probeDepth = math.max((Config.carGroundProbeDepth or 220) + probeHeight, 120)
	local result = Workspace:Raycast(
		position + Vector3.new(0, probeHeight, 0),
		Vector3.new(0, -probeDepth, 0),
		raycastParams
	)
	if result then
		return Vector3.new(position.X, result.Position.Y + (Config.carRideHeight or 2.3), position.Z)
	end

	return position
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

local function buildAuthoredCabCompany(root, world, driveSurfaces, crashObstacles, source)
	local marker = findAuthoredCabCompanyMarker(root)
	if not marker then
		return nil
	end

	local playerSpawnMarker = findAuthoredPlayerSpawnMarker(root)
	local refuelMarker = findAuthoredCabCompanyRefuelMarker(root)
	local serviceMarker = findAuthoredCabCompanyServiceMarker(root)
	local cabSpawnPosition = projectCabSpawnToDriveSurface(marker.Position, driveSurfaces)
	local result = CabCompanyWorldBuilder.create(world, Config, {
		cabSpawnPosition = cabSpawnPosition,
		cabSpawnYaw = CabCompanyWorldBuilder.yawFromCFrame(marker.CFrame),
		playerSpawnPosition = playerSpawnMarker and playerSpawnMarker.Position or nil,
		playerSpawnYaw = playerSpawnMarker and CabCompanyWorldBuilder.yawFromCFrame(playerSpawnMarker.CFrame) or nil,
		refuelPosition = refuelMarker and refuelMarker.Position or nil,
		refuelYaw = refuelMarker and CabCompanyWorldBuilder.yawFromCFrame(refuelMarker.CFrame) or nil,
		servicePosition = serviceMarker and serviceMarker.Position or nil,
		serviceYaw = serviceMarker and CabCompanyWorldBuilder.yawFromCFrame(serviceMarker.CFrame) or nil,
		source = source or "AuthoredRoadGraph",
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

local function hasLegacyCurveRoadData(root)
	if not root then
		return false
	end

	local network = root:FindFirstChild(RoadSplineData.NETWORK_NAME)
	if network and network:IsA("Model") then
		local parts = {}
		collectBaseParts(network, parts)
		if #parts > 0 then
			return true
		end
	end

	return #RoadSplineData.collectSplineRecords(root, { minPoints = 2 }) > 0
end

local function hasLegacyCurveMesh(root)
	if not root then
		return false
	end

	local network = root:FindFirstChild(RoadSplineData.NETWORK_NAME)
	if not (network and network:IsA("Model")) then
		return false
	end

	local parts = {}
	collectBaseParts(network, parts)
	return #parts > 0
end

local function copyLegacyCurveData(root, world)
	local dataRoot = Instance.new("Folder")
	dataRoot.Name = RoadSplineData.RUNTIME_DATA_NAME
	dataRoot.Parent = world

	for _, name in ipairs({
		RoadSplineData.SPLINES_NAME,
		RoadSplineData.JUNCTIONS_NAME,
		RoadSplineData.POINTS_NAME,
	}) do
		local source = root:FindFirstChild(name)
		if source then
			local clone = source:Clone()
			clone.Parent = dataRoot
		end
	end

	for _, descendant in ipairs(dataRoot:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Transparency = 1
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		end
	end

	return dataRoot
end

local function useLegacyCurveMeshes(root, world, dataRoot)
	local sourceNetwork = root:FindFirstChild(RoadSplineData.NETWORK_NAME)
	if not (sourceNetwork and sourceNetwork:IsA("Model")) then
		return nil
	end

	local runtimeNetwork = sourceNetwork:Clone()
	runtimeNetwork.Name = RoadSplineData.NETWORK_NAME
	runtimeNetwork.Parent = world

	local roadParts = {}
	collectBaseParts(runtimeNetwork, roadParts)
	if #roadParts == 0 then
		runtimeNetwork:Destroy()
		return nil
	end

	for _, part in ipairs(roadParts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end

	local collisionFolder, collisionParts = createLegacyCurveCollision(world, dataRoot)
	if #collisionParts == 0 then
		roadDebugWarn("legacy curve collision generation produced no parts; falling back to RoadNetwork MeshPart collision")
		for _, part in ipairs(roadParts) do
			part.CanCollide = true
			part.CanQuery = true
			part:SetAttribute("DriveSurface", true)
		end
		collisionParts = roadParts
	end

	return {
		meshFolder = runtimeNetwork,
		collisionFolder = collisionFolder,
		visibleParts = roadParts,
		collisionParts = collisionParts,
		driveSurfaces = collisionParts,
		errors = {},
		source = if collisionFolder then "legacy-curve-runtime-collision" else "legacy-curve-mesh-collision",
	}
end

local function getLegacyCurveSpawnPose(root)
	local marker = findAuthoredCabCompanyMarker(root)
	if marker then
		return {
			position = marker.Position,
			yaw = CabCompanyWorldBuilder.yawFromCFrame(marker.CFrame),
		}
	end

	local records = RoadSplineData.collectSplineRecords(root, { minPoints = 2 })
	local firstRecord = records[1]
	local firstPosition = firstRecord and firstRecord.positions and firstRecord.positions[1]
	if firstPosition then
		local secondPosition = firstRecord.positions[2]
		return {
			position = firstPosition + Vector3.new(0, Config.carRideHeight or 2.3, 0),
			yaw = secondPosition and yawFromVector(secondPosition - firstPosition) or 0,
		}
	end

	return {
		position = Config.carSpawn,
		yaw = 0,
	}
end

local function createLegacyCurveWorld(root)
	local oldWorld = Workspace:FindFirstChild(RUNTIME_WORLD_NAME)
	if oldWorld then
		oldWorld:Destroy()
	end

	local world = Instance.new("Model")
	world.Name = RUNTIME_WORLD_NAME
	world:SetAttribute("GeneratorVersion", "curve-editor-v1")
	world:SetAttribute("Source", RoadSplineData.EDITOR_ROOT_NAME)
	world:SetAttribute("NeedsClientRoadMesh", false)
	world.Parent = Workspace

	local runtimeData = copyLegacyCurveData(root, world)
	local meshBuild = useLegacyCurveMeshes(root, world, runtimeData)
	if not meshBuild then
		world:Destroy()
		error("Cab87RoadEditor has curve data but no RoadNetwork mesh. Click Rebuild Road (Mesh) in the curve plugin before Play.", 0)
	end

	local driveSurfaces = {}
	local crashObstacles = {}
	appendAll(driveSurfaces, meshBuild.driveSurfaces)

	local spawnPose = getLegacyCurveSpawnPose(root)
	local cabCompanySpawnPose = buildAuthoredCabCompany(root, world, driveSurfaces, crashObstacles, "AuthoredCurveRoad")
	if cabCompanySpawnPose then
		spawnPose = cabCompanySpawnPose
	end

	local splineRecords = RoadSplineData.collectSplineRecords(runtimeData, { minPoints = 2 })
	world:SetAttribute("AuthoredRoadFormat", "CurveSpline")
	world:SetAttribute("AuthoredRoadSplineCount", #splineRecords)
	world:SetAttribute("AuthoredRoadMeshSource", meshBuild.source or "legacy-curve")
	world:SetAttribute("AuthoredRoadServerCollisionSource", meshBuild.collisionFolder and LEGACY_COLLISION_NAME or RoadSplineData.NETWORK_NAME)
	world:SetAttribute("AuthoredRoadCollisionPartCount", #(meshBuild.collisionParts or {}))
	world:SetAttribute("AuthoredRoadServerMeshError", "")

	roadDebugLog(
		"legacy curve world built: splines=%d driveSurfaces=%d spawn=(%.1f, %.1f, %.1f) forward=(%.2f, %.2f, %.2f)",
		#splineRecords,
		#driveSurfaces,
		spawnPose.position.X,
		spawnPose.position.Y,
		spawnPose.position.Z,
		yawToForward(spawnPose.yaw).X,
		yawToForward(spawnPose.yaw).Y,
		yawToForward(spawnPose.yaw).Z
	)

	hideEditorRootForPlay(root, { preserveBakedGraph = false })
	return world, driveSurfaces, crashObstacles, spawnPose
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
	return RoadGraphData.hasGraph(root) or hasLegacyCurveRoadData(root)
end

function AuthoredRoadRuntime.createWorld(root)
	if hasLegacyCurveMesh(root) then
		return createLegacyCurveWorld(root)
	end

	local graph = RoadGraphData.collectGraph(root, Config)
	if not graph then
		return createLegacyCurveWorld(root)
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

	hideEditorRootForPlay(root, { preserveBakedGraph = true })
	return world, driveSurfaces, crashObstacles, spawnPose
end

return AuthoredRoadRuntime
