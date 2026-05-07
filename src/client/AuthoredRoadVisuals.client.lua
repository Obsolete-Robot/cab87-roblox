local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadGraphData = require(Shared:WaitForChild("RoadGraphData"))
local RoadGraphMesher = require(Shared:WaitForChild("RoadGraphMesher"))
local RoadMeshBuilder = require(Shared:WaitForChild("RoadMeshBuilder"))

local WORLD_NAME = "Cab87World"
local CLIENT_VISUALS_NAME = "AuthoredRoadClientVisuals"
local RUNTIME_GRAPH_DATA_NAME = RoadGraphData.RUNTIME_DATA_NAME
local CLIENT_MESH_GENERATOR = "Cab87RoadGraphClientVisualMesh"
local MAX_DEBUG_PARTS = 12

local buildToken = 0
local watchedWorld = nil
local worldConnections = {}

local function disconnectWorldConnections()
	for _, connection in ipairs(worldConnections) do
		connection:Disconnect()
	end
	table.clear(worldConnections)
end

local function clearClientVisuals(world)
	local existing = world and world:FindFirstChild(CLIENT_VISUALS_NAME)
	if existing then
		existing:Destroy()
	end
end

local function warnBuild(message, ...)
	local ok, formatted = pcall(string.format, tostring(message), ...)
	warn("[cab87 road visuals] " .. (ok and formatted or tostring(message)))
end

local function debugLog(message, ...)
	if Config.authoredRoadDebugLogging ~= true then
		return
	end

	local ok, formatted = pcall(string.format, tostring(message), ...)
	print("[cab87 road visuals] " .. (ok and formatted or tostring(message)))
end

local function debugTrace(message, ...)
	local ok, formatted = pcall(string.format, tostring(message), ...)
	print("[cab87 road visuals debug] " .. (ok and formatted or tostring(message)))
end

local function countPolygonFillTriangles(meshData)
	local count = 0
	for _, fill in ipairs(meshData.polygonTriangles or meshData.polygonFills or {}) do
		count += #(fill.triangles or {})
	end
	return count
end

local function countPartsBySurfaceType(parts, surfaceType)
	local count = 0
	for _, part in ipairs(parts or {}) do
		if part:GetAttribute("SurfaceType") == surfaceType then
			count += 1
		end
	end
	return count
end

local function pointKey(point)
	return string.format("%.2f:%.2f:%.2f", point.X, point.Y, point.Z)
end

local function triangleKey(triangle)
	local keys = {
		pointKey(triangle[1]),
		pointKey(triangle[2]),
		pointKey(triangle[3]),
	}
	table.sort(keys)
	return table.concat(keys, "|")
end

local function countTrianglesMissingFromSet(sourceTriangles, subsetTriangles)
	local sourceSet = {}
	for _, triangle in ipairs(sourceTriangles or {}) do
		if triangle[1] and triangle[2] and triangle[3] then
			sourceSet[triangleKey(triangle)] = true
		end
	end

	local missing = 0
	for _, triangle in ipairs(subsetTriangles or {}) do
		if triangle[1] and triangle[2] and triangle[3] and not sourceSet[triangleKey(triangle)] then
			missing += 1
		end
	end
	return missing
end

local function triangleBounds(triangles)
	local minX = math.huge
	local minY = math.huge
	local minZ = math.huge
	local maxX = -math.huge
	local maxY = -math.huge
	local maxZ = -math.huge
	local found = false

	for _, triangle in ipairs(triangles or {}) do
		for _, point in ipairs(triangle) do
			if typeof(point) == "Vector3" then
				found = true
				minX = math.min(minX, point.X)
				minY = math.min(minY, point.Y)
				minZ = math.min(minZ, point.Z)
				maxX = math.max(maxX, point.X)
				maxY = math.max(maxY, point.Y)
				maxZ = math.max(maxZ, point.Z)
			end
		end
	end

	if not found then
		return "empty"
	end
	return string.format(
		"min=(%.1f,%.1f,%.1f) max=(%.1f,%.1f,%.1f)",
		minX,
		minY,
		minZ,
		maxX,
		maxY,
		maxZ
	)
end

local function formatTriangle(triangle)
	if not (triangle and triangle[1] and triangle[2] and triangle[3]) then
		return "nil"
	end
	return string.format(
		"(%.1f,%.1f,%.1f) | (%.1f,%.1f,%.1f) | (%.1f,%.1f,%.1f)",
		triangle[1].X,
		triangle[1].Y,
		triangle[1].Z,
		triangle[2].X,
		triangle[2].Y,
		triangle[2].Z,
		triangle[3].X,
		triangle[3].Y,
		triangle[3].Z
	)
end

local function tracePart(part, index)
	debugTrace(
		"part[%d]: name=%s surfaceType=%s triangles=%s skipped=%s contentMode=%s roadEdgeTris=%s roadHubTris=%s parent=%s",
		index,
		part.Name,
		tostring(part:GetAttribute("SurfaceType")),
		tostring(part:GetAttribute("TriangleCount")),
		tostring(part:GetAttribute("SkippedTriangleCount")),
		tostring(part:GetAttribute("MeshContentMode")),
		tostring(part:GetAttribute("RoadEdgeTriangles")),
		tostring(part:GetAttribute("RoadHubTriangles")),
		part.Parent and part.Parent.Name or "nil"
	)
end

local function buildClientVisuals(world)
	buildToken += 1
	local token = buildToken
	if not (world and world:IsA("Model")) then
		return
	end

	task.spawn(function()
		local graphRoot = world:FindFirstChild(RUNTIME_GRAPH_DATA_NAME) or world:WaitForChild(RUNTIME_GRAPH_DATA_NAME, 30)
		if token ~= buildToken or not (graphRoot and graphRoot.Parent == world) then
			return
		end

		local graph = RoadGraphData.collectGraph(world, Config)
		if token ~= buildToken or not graph then
			return
		end
		debugTrace(
			"collected runtime graph: nodes=%d edges=%d polygonFills=%d serverRoadTris=%s serverRoadEdgeTris=%s serverRoadHubTris=%s serverPolygonFillTris=%s",
			#(graph.nodes or {}),
			#(graph.edges or {}),
			#(graph.polygonFills or {}),
			tostring(world:GetAttribute("AuthoredRoadRoadTriangles")),
			tostring(world:GetAttribute("AuthoredRoadRoadEdgeTriangles")),
			tostring(world:GetAttribute("AuthoredRoadRoadHubTriangles")),
			tostring(world:GetAttribute("AuthoredRoadPolygonFillTriangles"))
		)

		clearClientVisuals(world)

		local okMesh, meshDataOrErr = pcall(function()
			return RoadGraphMesher.buildNetworkMesh(graph, graph.settings)
		end)
		if token ~= buildToken then
			return
		end
		if not okMesh or not meshDataOrErr then
			warnBuild("mesh generation failed: %s", tostring(meshDataOrErr))
			return
		end

		local missingHubTriangles = countTrianglesMissingFromSet(
			meshDataOrErr.roadTriangles or {},
			meshDataOrErr.roadHubTriangles or {}
		)
		debugTrace(
			"mesh data: roadTris=%d roadEdgeTris=%d roadHubTris=%d hubMissingFromRoad=%d sidewalkTris=%d crosswalkTris=%d polygonFillTris=%d roadBounds=%s hubBounds=%s firstHub=%s",
			#(meshDataOrErr.roadTriangles or {}),
			#(meshDataOrErr.roadEdgeTriangles or {}),
			#(meshDataOrErr.roadHubTriangles or {}),
			missingHubTriangles,
			#(meshDataOrErr.sidewalkTriangles or {}),
			#(meshDataOrErr.crosswalkTriangles or {}),
			countPolygonFillTriangles(meshDataOrErr),
			triangleBounds(meshDataOrErr.roadTriangles),
			triangleBounds(meshDataOrErr.roadHubTriangles),
			formatTriangle((meshDataOrErr.roadHubTriangles or {})[1])
		)

		local okBuild, resultOrErr = pcall(function()
			return RoadMeshBuilder.createClassifiedCompactSurfaceMeshes(world, meshDataOrErr, {
				meshFolderName = CLIENT_VISUALS_NAME,
				generatedBy = CLIENT_MESH_GENERATOR,
				canCollide = false,
				canQuery = false,
				canTouch = false,
			})
		end)
		if token ~= buildToken then
			return
		end
		if not okBuild or not resultOrErr then
			warnBuild("surface build failed: %s", tostring(resultOrErr))
			return
		end
		debugTrace(
			"surface build returned: visibleParts=%d errors=%d",
			#(resultOrErr.visibleParts or {}),
			#(resultOrErr.errors or {})
		)

		local result = resultOrErr
		if result.meshFolder then
			result.meshFolder:SetAttribute("GeneratedBy", CLIENT_MESH_GENERATOR)
			result.meshFolder:SetAttribute("ClientRoadVisuals", true)
			result.meshFolder:SetAttribute("MeshMode", "clientRuntimeEditableMesh")
			result.meshFolder:SetAttribute("SurfacePartCount", #result.visibleParts)
			result.meshFolder:SetAttribute("RoadEdgeTriangles", #(meshDataOrErr.roadEdgeTriangles or {}))
			result.meshFolder:SetAttribute("RoadHubTriangles", #(meshDataOrErr.roadHubTriangles or {}))
			result.meshFolder:SetAttribute("RoadTriangles", #(meshDataOrErr.roadTriangles or {}))
			result.meshFolder:SetAttribute("SidewalkTriangles", #(meshDataOrErr.sidewalkTriangles or {}))
			result.meshFolder:SetAttribute("CrosswalkTriangles", #(meshDataOrErr.crosswalkTriangles or {}))
			result.meshFolder:SetAttribute("PolygonFillTriangles", countPolygonFillTriangles(meshDataOrErr))
		end

		for _, part in ipairs(result.visibleParts or {}) do
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part:SetAttribute("ClientRoadVisual", true)
			part:SetAttribute("BakeMode", "clientRuntimeEditableMesh")
			if part:GetAttribute("SurfaceType") == "polygonFill" then
				part:SetAttribute("BakedPolygonFillMesh", true)
			end
		end

		for index, part in ipairs(result.visibleParts or {}) do
			if index <= MAX_DEBUG_PARTS then
				tracePart(part, index)
			end
		end

		if #result.visibleParts == 0 then
			warnBuild("no visible road MeshParts were generated")
		end
		debugLog(
			"built client visual mesh: parts=%d roadParts=%d sidewalkParts=%d crosswalkParts=%d polygonFillParts=%d roadTris=%d roadEdgeTris=%d roadHubTris=%d sidewalkTris=%d crosswalkTris=%d polygonFillTris=%d",
			#result.visibleParts,
			countPartsBySurfaceType(result.visibleParts, "road"),
			countPartsBySurfaceType(result.visibleParts, "sidewalk"),
			countPartsBySurfaceType(result.visibleParts, "crosswalk"),
			countPartsBySurfaceType(result.visibleParts, "polygonFill"),
			#(meshDataOrErr.roadTriangles or {}),
			#(meshDataOrErr.roadEdgeTriangles or {}),
			#(meshDataOrErr.roadHubTriangles or {}),
			#(meshDataOrErr.sidewalkTriangles or {}),
			#(meshDataOrErr.crosswalkTriangles or {}),
			countPolygonFillTriangles(meshDataOrErr)
		)
		if #(result.errors or {}) > 0 then
			warnBuild("some surfaces were skipped: %s", table.concat(result.errors, " | "))
		end
	end)
end

local function watchWorld(world)
	if watchedWorld == world then
		return
	end

	buildToken += 1
	disconnectWorldConnections()
	if watchedWorld then
		clearClientVisuals(watchedWorld)
	end
	watchedWorld = if world and world:IsA("Model") then world else nil

	if not watchedWorld then
		return
	end

	table.insert(worldConnections, watchedWorld.ChildAdded:Connect(function(child)
		if child.Name == RUNTIME_GRAPH_DATA_NAME then
			buildClientVisuals(watchedWorld)
		end
	end))
	table.insert(worldConnections, watchedWorld.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			watchWorld(nil)
		end
	end))

	buildClientVisuals(watchedWorld)
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == WORLD_NAME and child:IsA("Model") then
		watchWorld(child)
	end
end)

local existingWorld = Workspace:FindFirstChild(WORLD_NAME)
if existingWorld and existingWorld:IsA("Model") then
	watchWorld(existingWorld)
end
