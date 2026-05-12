local AssetService = game:GetService("AssetService")
local Stats = game:GetService("Stats")

local RoadMeshBuilder = {}

local DEFAULT_SURFACES = {
	roads = {
		name = "RoadSurface",
		collisionName = "RoadCollision",
		color = Color3.fromRGB(28, 28, 32),
		material = Enum.Material.Asphalt,
	},
	sidewalks = {
		name = "SidewalkSurface",
		collisionName = "SidewalkCollision",
		color = Color3.fromRGB(116, 116, 108),
		material = Enum.Material.Concrete,
	},
	crosswalks = {
		name = "CrosswalkSurface",
		collisionName = "CrosswalkCollision",
		color = Color3.fromRGB(231, 226, 204),
		material = Enum.Material.SmoothPlastic,
	},
	buildings = {
		name = "BuildingSurface",
		collisionName = "BuildingCollision",
		color = Color3.fromRGB(100, 116, 139),
		material = Enum.Material.Concrete,
	},
}

local DEFAULT_CHUNK_SIZE = 1024
local DEFAULT_POLYGON_FILL_COLOR = Color3.fromRGB(16, 185, 129)
local DEFAULT_POLYGON_FILL_MATERIAL = Enum.Material.SmoothPlastic
local MIN_TRIANGLE_AREA = 0.0001
local EPSILON = 1e-5
local VERTEX_CACHE_SCALE = 1000
local DEFAULT_MAX_SURFACE_TRIANGLES = 6000
local DEFAULT_MAX_COLLISION_INPUT_TRIANGLES = 900
local DEFAULT_COLLISION_VERTICAL_CHUNK_SIZE = 12
local BUDGET_LOG_PREFIX = "[cab87 road mesh budget]"

local MEMORY_TAGS = {
	{ key = "graphicsMeshParts", tag = Enum.DeveloperMemoryTag.GraphicsMeshParts },
	{ key = "physicsCollision", tag = Enum.DeveloperMemoryTag.PhysicsCollision },
	{ key = "instances", tag = Enum.DeveloperMemoryTag.Instances },
	{ key = "luaHeap", tag = Enum.DeveloperMemoryTag.LuaHeap },
}

local function countDictionaryKeys(dictionary)
	local count = 0
	for _ in pairs(dictionary or {}) do
		count += 1
	end
	return count
end

local function memorySnapshot()
	local snapshot = {}
	local trackingOk, trackingEnabled = pcall(function()
		return Stats.MemoryTrackingEnabled
	end)
	if trackingOk and trackingEnabled == false then
		snapshot.memoryTrackingEnabled = false
		return snapshot
	end

	local totalOk, total = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	if totalOk then
		snapshot.total = total
	end

	for _, record in ipairs(MEMORY_TAGS) do
		local ok, value = pcall(function()
			return Stats:GetMemoryUsageMbForTag(record.tag)
		end)
		if ok then
			snapshot[record.key] = value
		end
	end
	return snapshot
end

local function formatMemoryValue(value)
	if type(value) ~= "number" then
		return "n/a"
	end
	return string.format("%.2fMB", value)
end

local function formatMemoryDelta(after, before, key)
	if type(after[key]) ~= "number" or type(before[key]) ~= "number" then
		return "n/a"
	end
	local delta = after[key] - before[key]
	return string.format("%+.2fMB", delta)
end

local function formatMemorySnapshot(snapshot)
	if snapshot.memoryTrackingEnabled == false then
		return "memoryTracking=false"
	end
	return string.format(
		"total=%s graphicsMeshParts=%s physicsCollision=%s instances=%s luaHeap=%s",
		formatMemoryValue(snapshot.total),
		formatMemoryValue(snapshot.graphicsMeshParts),
		formatMemoryValue(snapshot.physicsCollision),
		formatMemoryValue(snapshot.instances),
		formatMemoryValue(snapshot.luaHeap)
	)
end

local function formatMemoryDeltaSet(after, before)
	if after.memoryTrackingEnabled == false or before.memoryTrackingEnabled == false then
		return "memoryTracking=false"
	end
	return string.format(
		"total=%s graphicsMeshParts=%s physicsCollision=%s instances=%s luaHeap=%s",
		formatMemoryDelta(after, before, "total"),
		formatMemoryDelta(after, before, "graphicsMeshParts"),
		formatMemoryDelta(after, before, "physicsCollision"),
		formatMemoryDelta(after, before, "instances"),
		formatMemoryDelta(after, before, "luaHeap")
	)
end

local function shouldLogBudget(options)
	return options and options.debugBudgetLogging == true
end

local function budgetLog(options, message, ...)
	if not shouldLogBudget(options) then
		return
	end

	local prefix = options.budgetLogPrefix or BUDGET_LOG_PREFIX
	local ok, formatted = pcall(string.format, tostring(message), ...)
	print(prefix .. " " .. (if ok then formatted else tostring(message)))
end

local function rawGeometryKb(vertexCount, faceCount)
	return ((vertexCount * 3 * 4) + (faceCount * 3 * 4)) / 1024
end

local function colorFromValue(value, defaultColor)
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" then
		local hex = string.gsub(value, "#", "")
		if #hex == 6 then
			local r = tonumber(string.sub(hex, 1, 2), 16)
			local g = tonumber(string.sub(hex, 3, 4), 16)
			local b = tonumber(string.sub(hex, 5, 6), 16)
			if r and g and b then
				return Color3.fromRGB(r, g, b)
			end
		end
	end
	return defaultColor
end

local function newMeshState(options)
	local before = if shouldLogBudget(options) then memorySnapshot() else nil
	local ok, editableMeshOrErr = pcall(function()
		return AssetService:CreateEditableMesh()
	end)
	if not ok or not editableMeshOrErr then
		if before then
			budgetLog(
				options,
				"editableMeshCreateFailed name=%s kind=%s inputTriangles=%s memory={%s} remainingEditableBudget=unavailable",
				tostring(options.meshName or "?"),
				tostring(options.meshKind or "?"),
				tostring(options.inputTriangles or "?"),
				formatMemorySnapshot(before)
			)
		end
		return nil, "EditableMesh creation failed: " .. tostring(editableMeshOrErr)
	end

	return {
		mesh = editableMeshOrErr,
		options = options or {},
		faces = 0,
		skippedFaces = 0,
		flippedFaces = 0,
		normalErrors = 0,
		errors = {},
		vertexIds = {},
		normalIds = {},
	}
end

local function destroyEditableMesh(editableMesh)
	pcall(function()
		editableMesh:Destroy()
	end)
end

local retainedEditableMeshes = {}

local function retainEditableMesh(meshPart, editableMesh)
	if not (meshPart and editableMesh) then
		return
	end

	retainedEditableMeshes[meshPart] = editableMesh
	meshPart.Destroying:Connect(function()
		local retainedMesh = retainedEditableMeshes[meshPart]
		retainedEditableMeshes[meshPart] = nil
		if retainedMesh then
			destroyEditableMesh(retainedMesh)
		end
	end)
end

local function recordMeshError(state, message)
	state.skippedFaces += 1
	if #state.errors < 6 then
		table.insert(state.errors, tostring(message))
	end
end

local function quantizeCoordinate(value)
	if value >= 0 then
		return math.floor(value * VERTEX_CACHE_SCALE + 0.5)
	end
	return math.ceil(value * VERTEX_CACHE_SCALE - 0.5)
end

local function vertexKey(position)
	return tostring(quantizeCoordinate(position.X))
		.. ":"
		.. tostring(quantizeCoordinate(position.Y))
		.. ":"
		.. tostring(quantizeCoordinate(position.Z))
end

local function getVertexId(state, position)
	local key = vertexKey(position)
	local vertexId = state.vertexIds[key]
	if vertexId then
		return vertexId
	end

	vertexId = state.mesh:AddVertex(position)
	state.vertexIds[key] = vertexId
	return vertexId
end

local function normalKey(normal)
	local unit = normal.Unit
	return tostring(quantizeCoordinate(unit.X))
		.. ":"
		.. tostring(quantizeCoordinate(unit.Y))
		.. ":"
		.. tostring(quantizeCoordinate(unit.Z))
end

local function getNormalId(state, normal)
	local key = normalKey(normal)
	local normalId = state.normalIds[key]
	if normalId then
		return normalId
	end

	normalId = state.mesh:AddNormal(normal.Unit)
	state.normalIds[key] = normalId
	return normalId
end

local function setFaceNormal(state, faceId, normal)
	if state.options.useFaceNormals ~= true or not faceId then
		return
	end

	if normal.Magnitude <= MIN_TRIANGLE_AREA then
		return
	end

	local ok = pcall(function()
		local normalId = getNormalId(state, normal)
		state.mesh:SetFaceNormals(faceId, { normalId, normalId, normalId })
	end)
	if not ok then
		state.normalErrors += 1
	end
end

local function addTriangle(state, a, b, c)
	if not (typeof(a) == "Vector3" and typeof(b) == "Vector3" and typeof(c) == "Vector3") then
		recordMeshError(state, "triangle had non-Vector3 points")
		return false
	end

	local normal = (b - a):Cross(c - a)
	if normal.Magnitude <= MIN_TRIANGLE_AREA then
		recordMeshError(state, "triangle was degenerate")
		return false
	end

	if state.options.forceUpNormals == true and normal.Y < -EPSILON then
		b, c = c, b
		normal = (b - a):Cross(c - a)
		state.flippedFaces += 1
	end

	local ok, err = pcall(function()
		local va = getVertexId(state, a)
		local vb = getVertexId(state, b)
		local vc = getVertexId(state, c)
		local faceId = state.mesh:AddTriangle(va, vb, vc)
		setFaceNormal(state, faceId, normal)
	end)
	if not ok then
		recordMeshError(state, err)
		return false
	end

	state.faces += 1
	return true
end

local function addQuad(state, a, b, c, d)
	addTriangle(state, a, b, c)
	addTriangle(state, a, c, d)
end

local applyMeshPartOptions

local function contentFromAssetId(assetId)
	local numericAssetId = tonumber(assetId)
	if not numericAssetId then
		return nil, "Mesh asset id must be numeric"
	end

	if type(Content.fromAssetId) == "function" then
		local ok, contentOrErr = pcall(function()
			return Content.fromAssetId(numericAssetId)
		end)
		if ok and contentOrErr then
			return contentOrErr, nil
		end
	end

	local ok, contentOrErr = pcall(function()
		return Content.fromUri("rbxassetid://" .. tostring(numericAssetId))
	end)
	if ok and contentOrErr then
		return contentOrErr, nil
	end
	return nil, tostring(contentOrErr)
end

local function createLiveMeshContent(editableMesh)
	local okObjectContent, objectContentOrErr = pcall(function()
		return Content.fromObject(editableMesh)
	end)
	if not okObjectContent or not objectContentOrErr then
		return nil, "Mesh object content creation failed: " .. tostring(objectContentOrErr)
	end
	return objectContentOrErr, nil
end

function applyMeshPartOptions(meshPart, options, triangleCount)
	options = options or {}
	meshPart.Anchored = true
	meshPart.CanCollide = options.canCollide == true
	meshPart.CanQuery = options.canQuery == true
	meshPart.CanTouch = options.canTouch == true
	meshPart.CastShadow = options.castShadow == true
	meshPart.Transparency = options.transparency or 0
	meshPart.Color = options.color or Color3.fromRGB(28, 28, 32)
	meshPart.Material = options.material or Enum.Material.Asphalt
	pcall(function()
		meshPart.DoubleSided = true
	end)
	pcall(function()
		meshPart.CollisionFidelity = options.collisionFidelity or Enum.CollisionFidelity.Default
	end)
	meshPart:SetAttribute("GeneratedBy", options.generatedBy or "Cab87RoadGraph")
	if triangleCount then
		meshPart:SetAttribute("TriangleCount", triangleCount)
	end
	if options.surfaceType then
		meshPart:SetAttribute("SurfaceType", options.surfaceType)
	end
	if options.driveSurface == true then
		meshPart:SetAttribute("DriveSurface", true)
	end
end

local function createMeshPartFromContent(meshContent, parent, name, options, triangleCount)
	options = options or {}
	local createOptions = {
		CollisionFidelity = options.collisionFidelity or Enum.CollisionFidelity.Default,
		RenderFidelity = options.renderFidelity or Enum.RenderFidelity.Automatic,
	}

	local okPart, meshPartOrErr = pcall(function()
		return AssetService:CreateMeshPartAsync(meshContent, createOptions)
	end)
	if not okPart or not meshPartOrErr then
		return nil, tostring(meshPartOrErr)
	end

	local meshPart = meshPartOrErr
	meshPart.Name = name
	applyMeshPartOptions(meshPart, options, triangleCount)
	meshPart.Parent = parent
	return meshPart, nil
end

local function createMeshPartFromState(state, parent, name, options)
	options = options or {}
	local before = if shouldLogBudget(options) then memorySnapshot() else nil
	if state.faces == 0 then
		local detail = if #state.errors > 0 then ": " .. table.concat(state.errors, " | ") else ""
		destroyEditableMesh(state.mesh)
		if before then
			budgetLog(
				options,
				"meshDiscarded name=%s kind=%s inputTriangles=%s editableFaces=0 memory={%s} remainingEditableBudget=unavailable",
				tostring(name),
				tostring(options.meshKind or "?"),
				tostring(options.inputTriangles or "?"),
				formatMemorySnapshot(before)
			)
		end
		return nil, "No mesh faces were generated" .. detail
	end

	local meshContent, contentErr = createLiveMeshContent(state.mesh)
	if not meshContent then
		destroyEditableMesh(state.mesh)
		return nil, contentErr
	end

	local meshPart, err = createMeshPartFromContent(meshContent, parent, name, options, state.faces)
	if meshPart then
		retainEditableMesh(meshPart, state.mesh)
		local vertexCount = countDictionaryKeys(state.vertexIds)
		local normalCount = countDictionaryKeys(state.normalIds)
		meshPart:SetAttribute("EditableMeshVertexCount", vertexCount)
		if normalCount > 0 then
			meshPart:SetAttribute("EditableMeshNormalCount", normalCount)
		end
		meshPart:SetAttribute("EditableMeshFaceCount", state.faces)
		meshPart:SetAttribute("EditableMeshBudgetRemaining", "unavailable")
		if state.skippedFaces > 0 then
			meshPart:SetAttribute("SkippedTriangleCount", state.skippedFaces)
			if #state.errors > 0 then
				meshPart:SetAttribute("SkippedTriangleReason", table.concat(state.errors, " | "))
			end
		end
		if state.flippedFaces > 0 then
			meshPart:SetAttribute("FlippedTriangleCount", state.flippedFaces)
		end
		if state.normalErrors > 0 then
			meshPart:SetAttribute("FaceNormalErrorCount", state.normalErrors)
		end
		meshPart:SetAttribute("MeshContentMode", "liveEditableObject")
		if before then
			local after = memorySnapshot()
			budgetLog(
				options,
				"meshPartCreated name=%s kind=%s surfaceType=%s inputTriangles=%s editableFaces=%d uniqueVertices=%d uniqueNormals=%d rawGeometry=%.1fKB skipped=%d flipped=%d normalErrors=%d memoryBefore={%s} memoryAfter={%s} memoryDelta={%s} remainingEditableBudget=unavailable",
				tostring(name),
				tostring(options.meshKind or "?"),
				tostring(options.surfaceType or "?"),
				tostring(options.inputTriangles or "?"),
				state.faces,
				vertexCount,
				normalCount,
				rawGeometryKb(vertexCount, state.faces),
				state.skippedFaces,
				state.flippedFaces,
				state.normalErrors,
				formatMemorySnapshot(before),
				formatMemorySnapshot(after),
				formatMemoryDeltaSet(after, before)
			)
		end
		return meshPart, nil
	end

	destroyEditableMesh(state.mesh)
	if before then
		local after = memorySnapshot()
		budgetLog(
			options,
			"meshPartCreateFailed name=%s kind=%s surfaceType=%s inputTriangles=%s editableFaces=%d memoryBefore={%s} memoryAfter={%s} memoryDelta={%s} remainingEditableBudget=unavailable error=%s",
			tostring(name),
			tostring(options.meshKind or "?"),
			tostring(options.surfaceType or "?"),
			tostring(options.inputTriangles or "?"),
			state.faces,
			formatMemorySnapshot(before),
			formatMemorySnapshot(after),
			formatMemoryDeltaSet(after, before),
			tostring(err)
		)
	end
	return nil, err
end

function RoadMeshBuilder.createMeshPartFromAssetId(parent, name, assetId, options)
	local meshContent, contentErr = contentFromAssetId(assetId)
	if not meshContent then
		return nil, contentErr
	end

	local meshPart, err = createMeshPartFromContent(meshContent, parent, name, options, options and options.triangleCount)
	if meshPart then
		meshPart:SetAttribute("MeshAssetId", tonumber(assetId) or tostring(assetId))
		meshPart:SetAttribute("MeshContentMode", "asset")
	end
	return meshPart, err
end

function RoadMeshBuilder.destroyState(state)
	if state and state.mesh then
		destroyEditableMesh(state.mesh)
		state.mesh = nil
	end
end

function RoadMeshBuilder.createSurfaceState(triangles, options)
	options = table.clone(options or {})
	if options.forceUpNormals == nil then
		options.forceUpNormals = true
	end
	if options.useFaceNormals == nil then
		options.useFaceNormals = true
	end

	local state, err = newMeshState(options)
	if not state then
		return nil, err
	end

	for _, triangle in ipairs(triangles or {}) do
		if triangle[1] and triangle[2] and triangle[3] then
			addTriangle(state, triangle[1], triangle[2], triangle[3])
		end
	end

	return state, nil
end

function RoadMeshBuilder.createCollisionState(triangles, options)
	options = table.clone(options or {})
	local thickness = math.max(tonumber(options.thickness) or 0.2, 0.05)
	local surfaceOffset = tonumber(options.surfaceOffset) or 0
	local topOffset = Vector3.new(0, surfaceOffset, 0)
	local bottomOffset = Vector3.new(0, surfaceOffset - thickness, 0)

	local state, err = newMeshState(options)
	if not state then
		return nil, err
	end

	for _, triangle in ipairs(triangles or {}) do
		local a = triangle[1]
		local b = triangle[2]
		local c = triangle[3]
		if a and b and c then
			local at = a + topOffset
			local bt = b + topOffset
			local ct = c + topOffset
			local ab = a + bottomOffset
			local bb = b + bottomOffset
			local cb = c + bottomOffset

			addTriangle(state, at, bt, ct)
			addTriangle(state, ab, cb, bb)
			addQuad(state, at, ab, bb, bt)
			addQuad(state, bt, bb, cb, ct)
			addQuad(state, ct, cb, ab, at)
		end
	end

	return state, nil
end

function RoadMeshBuilder.createSurfaceMesh(parent, name, triangles, options)
	local surfaceOptions = table.clone(options or {})
	surfaceOptions.meshName = name
	surfaceOptions.meshKind = surfaceOptions.meshKind or "surface"
	surfaceOptions.inputTriangles = #(triangles or {})
	local state, err = RoadMeshBuilder.createSurfaceState(triangles, surfaceOptions)
	if not state then
		return nil, err
	end

	surfaceOptions.collisionFidelity = surfaceOptions.collisionFidelity or Enum.CollisionFidelity.Box
	return createMeshPartFromState(state, parent, name, surfaceOptions)
end

function RoadMeshBuilder.createCollisionMesh(parent, name, triangles, options)
	local collisionOptions = table.clone(options or {})
	collisionOptions.meshName = name
	collisionOptions.meshKind = collisionOptions.meshKind or "collision"
	collisionOptions.inputTriangles = #(triangles or {})
	local state, err = RoadMeshBuilder.createCollisionState(triangles, collisionOptions)
	if not state then
		return nil, err
	end

	collisionOptions.canCollide = true
	collisionOptions.canQuery = true
	collisionOptions.canTouch = false
	collisionOptions.transparency = 1
	collisionOptions.castShadow = false
	collisionOptions.driveSurface = if collisionOptions.driveSurface == false then false else true
	collisionOptions.collisionFidelity = collisionOptions.collisionFidelity
		or Enum.CollisionFidelity.PreciseConvexDecomposition
	return createMeshPartFromState(state, parent, name, collisionOptions)
end

local function recreateFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function buildSurfacePair(meshParent, collisionParent, key, triangles, options)
	local style = DEFAULT_SURFACES[key]
	if not style or #(triangles or {}) == 0 then
		return nil, nil, nil
	end

	local surfaceType = string.gsub(key, "s$", "")
	local visiblePart, visibleErr = RoadMeshBuilder.createSurfaceMesh(meshParent, style.name, triangles, {
		color = style.color,
		material = style.material,
		surfaceType = surfaceType,
		generatedBy = options.generatedBy,
		canCollide = false,
		canQuery = false,
		canTouch = false,
	})
	if not visiblePart then
		return nil, nil, visibleErr
	end

	local collisionPart, collisionErr = RoadMeshBuilder.createCollisionMesh(collisionParent, style.collisionName, triangles, {
		color = style.color,
		material = style.material,
		surfaceType = surfaceType,
		generatedBy = options.generatedBy,
		thickness = options.collisionThickness,
		surfaceOffset = options.collisionSurfaceOffset,
		driveSurface = key ~= "buildings",
	})
	if not collisionPart then
		visiblePart:Destroy()
		return nil, nil, collisionErr
	end
	if key == "buildings" then
		collisionPart:SetAttribute("CrashObstacle", true)
	end

	return visiblePart, collisionPart, nil
end

local function getPolygonFillGroups(meshData)
	return meshData.polygonFills or meshData.polygonTriangles or {}
end

local function polygonFillName(prefix, fill, index)
	local id = tostring(fill.id or index)
	id = string.gsub(id, "[^%w_%-]", "_")
	return string.format("%s_%03d_%s", prefix, index, id)
end

local function buildPolygonFillSurfaceMeshes(meshParent, fillGroups, options)
	options = options or {}
	local parts = {}
	local errors = {}
	local prefix = options.namePrefix or "PolygonFillSurface"

	for index, fill in ipairs(fillGroups or {}) do
		local triangles = fill.triangles or {}
		if #triangles > 0 then
			local part, err = RoadMeshBuilder.createSurfaceMesh(meshParent, polygonFillName(prefix, fill, index), triangles, {
				color = colorFromValue(fill.color, options.color or DEFAULT_POLYGON_FILL_COLOR),
				material = options.material or DEFAULT_POLYGON_FILL_MATERIAL,
				surfaceType = options.surfaceType or "polygonFill",
				generatedBy = options.generatedBy,
				canCollide = false,
				canQuery = false,
				canTouch = false,
				castShadow = false,
				transparency = options.transparency,
			})
			if part then
				part:SetAttribute("PolygonFillId", tostring(fill.id or index))
				table.insert(parts, part)
			elseif err then
				table.insert(errors, string.format("polygonFill[%s]: %s", tostring(fill.id or index), tostring(err)))
			end
		end
	end

	return parts, if #errors > 0 then table.concat(errors, " | ") else nil
end

local function triangleCenter(triangle)
	local a = triangle and triangle[1]
	local b = triangle and triangle[2]
	local c = triangle and triangle[3]
	if not (a and b and c) then
		return nil
	end

	return (a + b + c) / 3
end

local function getCollisionVerticalChunkSize(options)
	local value = tonumber(options and (options.collisionVerticalChunkSize or options.verticalChunkSize))
	if value and value > 0 then
		return value
	end
	return DEFAULT_COLLISION_VERTICAL_CHUNK_SIZE
end

local function bucketTrianglesByCenter(triangles, chunkSize, verticalChunkSize)
	local buckets = {}
	local keys = {}
	local sanitizedVerticalChunkSize = tonumber(verticalChunkSize)
	local useVerticalChunk = sanitizedVerticalChunkSize and sanitizedVerticalChunkSize > 0

	for _, triangle in ipairs(triangles or {}) do
		local center = triangleCenter(triangle)
		if center then
			local chunkX = math.floor(center.X / chunkSize)
			local chunkY = nil
			if useVerticalChunk then
				chunkY = math.floor(center.Y / sanitizedVerticalChunkSize)
			end
			local chunkZ = math.floor(center.Z / chunkSize)
			local key = if chunkY == nil
				then tostring(chunkX) .. ":" .. tostring(chunkZ)
				else tostring(chunkX) .. ":" .. tostring(chunkY) .. ":" .. tostring(chunkZ)
			local bucket = buckets[key]
			if not bucket then
				bucket = {
					chunkX = chunkX,
					chunkY = chunkY,
					chunkZ = chunkZ,
					triangles = {},
				}
				buckets[key] = bucket
				table.insert(keys, key)
			end
			table.insert(bucket.triangles, triangle)
		end
	end

	table.sort(keys, function(a, b)
		local left = buckets[a]
		local right = buckets[b]
		if left.chunkX == right.chunkX then
			local leftY = left.chunkY or 0
			local rightY = right.chunkY or 0
			if leftY ~= rightY then
				return leftY < rightY
			end
			return left.chunkZ < right.chunkZ
		end
		return left.chunkX < right.chunkX
	end)

	return buckets, keys
end

local function triangleBatches(triangles, maxTriangles)
	local batches = {}
	maxTriangles = math.max(math.floor(tonumber(maxTriangles) or #triangles), 1)
	for startIndex = 1, #triangles, maxTriangles do
		local batch = {}
		local endIndex = math.min(startIndex + maxTriangles - 1, #triangles)
		for index = startIndex, endIndex do
			table.insert(batch, triangles[index])
		end
		table.insert(batches, batch)
	end
	return batches
end

local function chunkName(baseName, chunkIndex, batchIndex)
	if batchIndex and batchIndex > 1 then
		return string.format("%s_%03d_%02d", baseName, chunkIndex, batchIndex)
	end
	return string.format("%s_%03d", baseName, chunkIndex)
end

local function buildChunkedSurface(meshParent, key, triangles, options)
	local style = DEFAULT_SURFACES[key]
	if not style or #(triangles or {}) == 0 then
		return {}, nil
	end

	local surfaceType = string.gsub(key, "s$", "")
	local chunkSize = math.max(tonumber(options.chunkSize) or DEFAULT_CHUNK_SIZE, 128)
	local maxTriangles = math.max(
		math.floor(tonumber(options.maxSurfaceTriangles) or DEFAULT_MAX_SURFACE_TRIANGLES),
		1
	)
	local buckets, keys = bucketTrianglesByCenter(triangles, chunkSize)
	local parts = {}
	local errors = {}

	for chunkIndex, bucketKey in ipairs(keys) do
		local bucket = buckets[bucketKey]
		for batchIndex, batch in ipairs(triangleBatches(bucket.triangles, maxTriangles)) do
			local meshPart, err = RoadMeshBuilder.createSurfaceMesh(
				meshParent,
				chunkName(style.name, chunkIndex, batchIndex),
				batch,
				{
					color = options.color or style.color,
					material = options.material or style.material,
					surfaceType = surfaceType,
					generatedBy = options.generatedBy,
					canCollide = false,
					canQuery = false,
					canTouch = false,
					castShadow = false,
					transparency = options.transparency,
				}
			)
			if meshPart then
				meshPart:SetAttribute("MeshChunkKey", bucketKey)
				meshPart:SetAttribute("MeshChunkSize", chunkSize)
				meshPart:SetAttribute("MeshBatchIndex", batchIndex)
				table.insert(parts, meshPart)
			elseif err then
				table.insert(errors, string.format("%s[%s/%d]: %s", key, bucketKey, batchIndex, tostring(err)))
			end
		end
	end

	if #errors > 0 then
		return parts, table.concat(errors, " | ")
	end
	return parts, nil
end

local function buildChunkedCollision(collisionParent, key, triangles, options)
	local style = DEFAULT_SURFACES[key]
	if not style or #(triangles or {}) == 0 then
		return {}, nil
	end

	local surfaceType = string.gsub(key, "s$", "")
	local chunkSize = math.max(tonumber(options.chunkSize) or DEFAULT_CHUNK_SIZE, 128)
	local verticalChunkSize = getCollisionVerticalChunkSize(options)
	local maxTriangles = math.max(
		math.floor(tonumber(options.maxCollisionInputTriangles) or DEFAULT_MAX_COLLISION_INPUT_TRIANGLES),
		1
	)
	local buckets, keys = bucketTrianglesByCenter(triangles, chunkSize, verticalChunkSize)
	local parts = {}
	local errors = {}

	for chunkIndex, bucketKey in ipairs(keys) do
		local bucket = buckets[bucketKey]
		for batchIndex, batch in ipairs(triangleBatches(bucket.triangles, maxTriangles)) do
			local collisionPart, err = RoadMeshBuilder.createCollisionMesh(
				collisionParent,
				chunkName(style.collisionName, chunkIndex, batchIndex),
				batch,
				{
					color = style.color,
					material = style.material,
					surfaceType = surfaceType,
					generatedBy = options.generatedBy,
					thickness = options.collisionThickness,
					surfaceOffset = options.collisionSurfaceOffset,
					driveSurface = key ~= "buildings",
				}
			)
			if collisionPart then
				if key == "buildings" then
					collisionPart:SetAttribute("CrashObstacle", true)
				end
				collisionPart:SetAttribute("MeshChunkKey", bucketKey)
				collisionPart:SetAttribute("MeshChunkSize", chunkSize)
				collisionPart:SetAttribute("MeshChunkY", bucket.chunkY)
				collisionPart:SetAttribute("CollisionVerticalChunkSize", verticalChunkSize)
				collisionPart:SetAttribute("MeshBatchIndex", batchIndex)
				table.insert(parts, collisionPart)
			elseif err then
				table.insert(errors, string.format("%s collision[%s/%d]: %s", key, bucketKey, batchIndex, tostring(err)))
			end
		end
	end

	if #errors > 0 then
		return parts, table.concat(errors, " | ")
	end
	return parts, nil
end

local function buildChunkedPolygonFillSurfaceMeshes(meshParent, fillGroups, options)
	options = options or {}
	local parts = {}
	local errors = {}
	local prefix = options.namePrefix or "PolygonFillSurface"
	local maxTriangles = math.max(
		math.floor(tonumber(options.maxSurfaceTriangles) or DEFAULT_MAX_SURFACE_TRIANGLES),
		1
	)

	for fillIndex, fill in ipairs(fillGroups or {}) do
		local triangles = fill.triangles or {}
		if #triangles > 0 then
			for batchIndex, batch in ipairs(triangleBatches(triangles, maxTriangles)) do
				local part, err = RoadMeshBuilder.createSurfaceMesh(
					meshParent,
					chunkName(polygonFillName(prefix, fill, fillIndex), fillIndex, batchIndex),
					batch,
					{
						color = colorFromValue(fill.color, options.color or DEFAULT_POLYGON_FILL_COLOR),
						material = options.material or DEFAULT_POLYGON_FILL_MATERIAL,
						surfaceType = options.surfaceType or "polygonFill",
						generatedBy = options.generatedBy,
						canCollide = false,
						canQuery = false,
						canTouch = false,
						castShadow = false,
						transparency = options.transparency,
					}
				)
				if part then
					part:SetAttribute("PolygonFillId", tostring(fill.id or fillIndex))
					part:SetAttribute("MeshBatchIndex", batchIndex)
					table.insert(parts, part)
				elseif err then
					table.insert(
						errors,
						string.format("polygonFill[%s/%d]: %s", tostring(fill.id or fillIndex), batchIndex, tostring(err))
					)
				end
			end
		end
	end

	if #errors > 0 then
		return parts, table.concat(errors, " | ")
	end
	return parts, nil
end

local function buildChunkedPolygonFillCollisionMeshes(collisionParent, fillGroups, options)
	options = options or {}
	local parts = {}
	local errors = {}
	local prefix = options.collisionNamePrefix or "PolygonFillCollision"
	local chunkSize = math.max(tonumber(options.chunkSize) or DEFAULT_CHUNK_SIZE, 128)
	local verticalChunkSize = getCollisionVerticalChunkSize(options)
	local maxTriangles = math.max(
		math.floor(tonumber(options.maxCollisionInputTriangles) or DEFAULT_MAX_COLLISION_INPUT_TRIANGLES),
		1
	)

	for fillIndex, fill in ipairs(fillGroups or {}) do
		local triangles = fill.triangles or {}
		if #triangles > 0 then
			local buckets, keys = bucketTrianglesByCenter(triangles, chunkSize, verticalChunkSize)
			for chunkIndex, bucketKey in ipairs(keys) do
				local bucket = buckets[bucketKey]
				for batchIndex, batch in ipairs(triangleBatches(bucket.triangles, maxTriangles)) do
					local part, err = RoadMeshBuilder.createCollisionMesh(
						collisionParent,
						chunkName(polygonFillName(prefix, fill, fillIndex), chunkIndex, batchIndex),
						batch,
						{
							color = colorFromValue(fill.color, options.color or DEFAULT_POLYGON_FILL_COLOR),
							material = options.material or DEFAULT_POLYGON_FILL_MATERIAL,
							surfaceType = options.surfaceType or "polygonFill",
							generatedBy = options.generatedBy,
							thickness = options.collisionThickness,
							surfaceOffset = options.collisionSurfaceOffset,
						}
					)
					if part then
						part:SetAttribute("PolygonFillId", tostring(fill.id or fillIndex))
						part:SetAttribute("MeshChunkKey", bucketKey)
						part:SetAttribute("MeshChunkSize", chunkSize)
						part:SetAttribute("MeshChunkY", bucket.chunkY)
						part:SetAttribute("CollisionVerticalChunkSize", verticalChunkSize)
						part:SetAttribute("MeshBatchIndex", batchIndex)
						table.insert(parts, part)
					elseif err then
						table.insert(
							errors,
							string.format(
								"polygonFill collision[%s/%s/%d]: %s",
								tostring(fill.id or fillIndex),
								bucketKey,
								batchIndex,
								tostring(err)
							)
						)
					end
				end
			end
		end
	end

	if #errors > 0 then
		return parts, table.concat(errors, " | ")
	end
	return parts, nil
end

local function collectPolygonFillTriangles(fillGroups)
	local triangles = {}
	local firstFill = nil

	for _, fill in ipairs(fillGroups or {}) do
		local fillTriangles = fill.triangles or {}
		if #fillTriangles > 0 and not firstFill then
			firstFill = fill
		end
		for _, triangle in ipairs(fillTriangles) do
			table.insert(triangles, triangle)
		end
	end

	return triangles, firstFill
end

function RoadMeshBuilder.createClassifiedMeshes(parent, meshData, options)
	options = options or {}
	local meshFolder = recreateFolder(parent, options.meshFolderName or "RoadGraphSurfaces")
	local collisionFolder = recreateFolder(parent, options.collisionFolderName or "RoadGraphCollision")

	local result = {
		meshFolder = meshFolder,
		collisionFolder = collisionFolder,
		visibleParts = {},
		collisionParts = {},
		driveSurfaces = {},
		errors = {},
	}

	local surfaceSets = {
		roads = meshData.roadTriangles,
		sidewalks = meshData.sidewalkTriangles,
		crosswalks = meshData.crosswalkTriangles,
		buildings = meshData.buildingTriangles,
	}

	for key, triangles in pairs(surfaceSets) do
		local visiblePart, collisionPart, err = buildSurfacePair(meshFolder, collisionFolder, key, triangles, options)
		if visiblePart and collisionPart then
			table.insert(result.visibleParts, visiblePart)
			table.insert(result.collisionParts, collisionPart)
			if key == "buildings" then
				collisionPart:SetAttribute("CrashObstacle", true)
			else
				table.insert(result.driveSurfaces, collisionPart)
			end
		elseif err then
			table.insert(result.errors, string.format("%s: %s", key, tostring(err)))
		end
	end

	local fillParts, fillErr = buildPolygonFillSurfaceMeshes(meshFolder, getPolygonFillGroups(meshData), options)
	if fillErr then
		table.insert(result.errors, fillErr)
	end
	for _, part in ipairs(fillParts) do
		table.insert(result.visibleParts, part)
	end

	if options.includePolygonFillCollision ~= false then
		local fillCollisionParts, fillCollisionErr = buildChunkedPolygonFillCollisionMeshes(
			collisionFolder,
			getPolygonFillGroups(meshData),
			options
		)
		if fillCollisionErr then
			table.insert(result.errors, fillCollisionErr)
		end
		for _, part in ipairs(fillCollisionParts) do
			table.insert(result.collisionParts, part)
			table.insert(result.driveSurfaces, part)
		end
	end

	if #result.visibleParts == 0 then
		meshFolder:Destroy()
	end
	if #result.collisionParts == 0 then
		collisionFolder:Destroy()
	end

	return result
end

function RoadMeshBuilder.createClassifiedCompactSurfaceMeshes(parent, meshData, options)
	options = options or {}
	local meshFolder = recreateFolder(parent, options.meshFolderName or "RoadGraphSurfaces")

	local result = {
		meshFolder = meshFolder,
		visibleParts = {},
		errors = {},
	}

	local surfaceSets = {
		{ key = "roads", triangles = meshData.roadTriangles, surfaceType = "road" },
		{ key = "sidewalks", triangles = meshData.sidewalkTriangles },
		{ key = "crosswalks", triangles = meshData.crosswalkTriangles },
		{ key = "buildings", triangles = meshData.buildingTriangles },
	}

	for _, set in ipairs(surfaceSets) do
		local style = DEFAULT_SURFACES[set.key]
		local triangles = set.triangles or {}
		if style and #triangles > 0 then
			local surfaceType = set.surfaceType or string.gsub(set.key, "s$", "")
			local part, err = RoadMeshBuilder.createSurfaceMesh(meshFolder, style.name, triangles, {
				color = style.color,
				material = style.material,
				surfaceType = surfaceType,
				generatedBy = options.generatedBy,
				canCollide = false,
				canQuery = false,
				canTouch = false,
				castShadow = false,
				transparency = options.transparency,
			})
			if part then
				part:SetAttribute("MeshMode", "compactSurface")
				if set.key == "roads" then
					part:SetAttribute("RoadEdgeTriangles", #(meshData.roadEdgeTriangles or {}))
					part:SetAttribute("RoadHubTriangles", #(meshData.roadHubTriangles or {}))
				end
				table.insert(result.visibleParts, part)
			elseif err then
				table.insert(result.errors, string.format("%s: %s", set.key, tostring(err)))
			end
		end
	end

	local fillTriangles, firstFill = collectPolygonFillTriangles(getPolygonFillGroups(meshData))
	if #fillTriangles > 0 then
		local part, err = RoadMeshBuilder.createSurfaceMesh(meshFolder, options.polygonFillName or "PolygonFillSurface", fillTriangles, {
			color = colorFromValue(firstFill and firstFill.color, options.color or DEFAULT_POLYGON_FILL_COLOR),
			material = options.material or DEFAULT_POLYGON_FILL_MATERIAL,
			surfaceType = options.surfaceType or "polygonFill",
			generatedBy = options.generatedBy,
			canCollide = false,
			canQuery = false,
			canTouch = false,
			castShadow = false,
			transparency = options.transparency,
		})
		if part then
			part:SetAttribute("MeshMode", "compactSurface")
			part:SetAttribute("PolygonFillCount", #(getPolygonFillGroups(meshData) or {}))
			table.insert(result.visibleParts, part)
		elseif err then
			table.insert(result.errors, "polygonFill: " .. tostring(err))
		end
	end

	if #result.visibleParts == 0 then
		meshFolder:Destroy()
		result.meshFolder = nil
	end

	return result
end

function RoadMeshBuilder.createClassifiedChunkedMeshes(parent, meshData, options)
	options = options or {}
	local meshFolder = recreateFolder(parent, options.meshFolderName or "RoadGraphSurfaces")
	local collisionFolder = recreateFolder(parent, options.collisionFolderName or "RoadGraphCollision")

	local result = {
		meshFolder = meshFolder,
		collisionFolder = collisionFolder,
		visibleParts = {},
		collisionParts = {},
		driveSurfaces = {},
		errors = {},
	}

	local trianglesByKey = {
		roads = meshData.roadTriangles,
		sidewalks = meshData.sidewalkTriangles,
		crosswalks = meshData.crosswalkTriangles,
		buildings = meshData.buildingTriangles,
	}
	local surfaceKeys = options.surfaceKeys or { "roads", "sidewalks", "crosswalks", "buildings" }

	for _, key in ipairs(surfaceKeys) do
		local visibleParts, visibleErr = buildChunkedSurface(meshFolder, key, trianglesByKey[key], options)
		if visibleErr then
			table.insert(result.errors, visibleErr)
		end
		for _, part in ipairs(visibleParts) do
			table.insert(result.visibleParts, part)
		end

		local collisionParts, collisionErr = buildChunkedCollision(collisionFolder, key, trianglesByKey[key], options)
		if collisionErr then
			table.insert(result.errors, collisionErr)
		end
		for _, part in ipairs(collisionParts) do
			table.insert(result.collisionParts, part)
			if key == "buildings" then
				part:SetAttribute("CrashObstacle", true)
			else
				table.insert(result.driveSurfaces, part)
			end
		end
	end

	if options.includePolygonFillCollision ~= false then
		local fillCollisionParts, fillCollisionErr = buildChunkedPolygonFillCollisionMeshes(
			collisionFolder,
			getPolygonFillGroups(meshData),
			options
		)
		if fillCollisionErr then
			table.insert(result.errors, fillCollisionErr)
		end
		for _, part in ipairs(fillCollisionParts) do
			table.insert(result.collisionParts, part)
			table.insert(result.driveSurfaces, part)
		end
	end

	local fillParts, fillErr = buildChunkedPolygonFillSurfaceMeshes(meshFolder, getPolygonFillGroups(meshData), options)
	if fillErr then
		table.insert(result.errors, fillErr)
	end
	for _, part in ipairs(fillParts) do
		table.insert(result.visibleParts, part)
	end

	if #result.visibleParts == 0 then
		meshFolder:Destroy()
		result.meshFolder = nil
	end
	if #result.collisionParts == 0 then
		collisionFolder:Destroy()
		result.collisionFolder = nil
	end

	return result
end

function RoadMeshBuilder.createClassifiedChunkedSurfaceMeshes(parent, meshData, options)
	options = options or {}
	local meshFolder = recreateFolder(parent, options.meshFolderName or "RoadGraphSurfaces")

	local result = {
		meshFolder = meshFolder,
		visibleParts = {},
		errors = {},
	}

	local trianglesByKey = {
		roads = meshData.roadTriangles,
		sidewalks = meshData.sidewalkTriangles,
		crosswalks = meshData.crosswalkTriangles,
		buildings = meshData.buildingTriangles,
	}
	local surfaceKeys = options.surfaceKeys or { "roads", "sidewalks", "crosswalks", "buildings" }

	for _, key in ipairs(surfaceKeys) do
		local visibleParts, err = buildChunkedSurface(meshFolder, key, trianglesByKey[key], options)
		if err then
			table.insert(result.errors, err)
		end
		for _, part in ipairs(visibleParts) do
			table.insert(result.visibleParts, part)
		end
	end

	local fillParts, fillErr = buildChunkedPolygonFillSurfaceMeshes(meshFolder, getPolygonFillGroups(meshData), options)
	if fillErr then
		table.insert(result.errors, fillErr)
	end
	for _, part in ipairs(fillParts) do
		table.insert(result.visibleParts, part)
	end

	if #result.visibleParts == 0 then
		meshFolder:Destroy()
		result.meshFolder = nil
	end

	return result
end

function RoadMeshBuilder.createClassifiedChunkedCollisionMeshes(parent, meshData, options)
	options = options or {}
	local collisionFolder = recreateFolder(parent, options.collisionFolderName or "RoadGraphCollision")

	local result = {
		collisionFolder = collisionFolder,
		collisionParts = {},
		driveSurfaces = {},
		errors = {},
	}

	local trianglesByKey = {
		roads = meshData.roadTriangles,
		sidewalks = meshData.sidewalkTriangles,
		crosswalks = meshData.crosswalkTriangles,
		buildings = meshData.buildingTriangles,
	}
	local surfaceKeys = options.surfaceKeys or { "roads", "sidewalks", "crosswalks", "buildings" }

	for _, key in ipairs(surfaceKeys) do
		local collisionParts, err = buildChunkedCollision(collisionFolder, key, trianglesByKey[key], options)
		if err then
			table.insert(result.errors, err)
		end
		for _, part in ipairs(collisionParts) do
			table.insert(result.collisionParts, part)
			if key == "buildings" then
				part:SetAttribute("CrashObstacle", true)
			else
				table.insert(result.driveSurfaces, part)
			end
		end
	end

	if options.includePolygonFillCollision ~= false then
		local fillCollisionParts, fillCollisionErr = buildChunkedPolygonFillCollisionMeshes(
			collisionFolder,
			getPolygonFillGroups(meshData),
			options
		)
		if fillCollisionErr then
			table.insert(result.errors, fillCollisionErr)
		end
		for _, part in ipairs(fillCollisionParts) do
			table.insert(result.collisionParts, part)
			table.insert(result.driveSurfaces, part)
		end
	end

	if #result.collisionParts == 0 then
		collisionFolder:Destroy()
		result.collisionFolder = nil
	end

	return result
end

function RoadMeshBuilder.createPolygonFillSurfaceMeshes(parent, meshData, options)
	return buildPolygonFillSurfaceMeshes(parent, getPolygonFillGroups(meshData), options)
end

return RoadMeshBuilder
