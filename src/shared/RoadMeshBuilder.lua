local AssetService = game:GetService("AssetService")

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
	fills = {
		name = "PolygonFillSurface",
		collisionName = "PolygonFillCollision",
		color = Color3.fromRGB(42, 155, 104),
		material = Enum.Material.SmoothPlastic,
	},
}

local MIN_PART_DIMENSION = 0.01
local DEFAULT_CHUNK_SIZE = 1024

local function colorFromHex(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end

	local hex = tostring(value or "")
	hex = string.match(hex, "^#?([%da-fA-F]+)$") or ""
	if #hex == 3 then
		hex = string.gsub(hex, ".", function(character)
			return character .. character
		end)
	end
	if #hex ~= 6 then
		return fallback
	end

	local red = tonumber(string.sub(hex, 1, 2), 16)
	local green = tonumber(string.sub(hex, 3, 4), 16)
	local blue = tonumber(string.sub(hex, 5, 6), 16)
	if not (red and green and blue) then
		return fallback
	end
	return Color3.fromRGB(red, green, blue)
end

local function newMeshState()
	local ok, editableMeshOrErr = pcall(function()
		return AssetService:CreateEditableMesh()
	end)
	if not ok or not editableMeshOrErr then
		return nil, "EditableMesh creation failed: " .. tostring(editableMeshOrErr)
	end

	return {
		mesh = editableMeshOrErr,
		faces = 0,
	}
end

local function destroyEditableMesh(editableMesh)
	pcall(function()
		editableMesh:Destroy()
	end)
end

local function addVertex(state, position)
	return state.mesh:AddVertex(position)
end

local function addTriangle(state, a, b, c)
	local va = addVertex(state, a)
	local vb = addVertex(state, b)
	local vc = addVertex(state, c)
	state.mesh:AddTriangle(va, vb, vc)
	state.faces += 1
end

local function addQuad(state, a, b, c, d)
	addTriangle(state, a, b, c)
	addTriangle(state, a, c, d)
end

local applyMeshPartOptions

local function configurePart(part, options, triangleCount)
	options = options or {}
	applyMeshPartOptions(part, options, triangleCount)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = options.castShadow == true
	return part
end

local function addTriangleWedges(parent, name, a, b, c, options)
	options = options or {}
	local ab = b - a
	local ac = c - a
	local bc = c - b
	local abd = ab:Dot(ab)
	local acd = ac:Dot(ac)
	local bcd = bc:Dot(bc)

	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end

	ab = b - a
	ac = c - a
	bc = c - b
	if ab.Magnitude <= 0.001 or ac.Magnitude <= 0.001 or bc.Magnitude <= 0.001 then
		return {}
	end

	local normal = ac:Cross(ab)
	if normal.Magnitude <= 0.001 then
		return {}
	end

	local right = normal.Unit
	local up = bc:Cross(right)
	if up.Magnitude <= 0.001 then
		return {}
	end
	up = up.Unit
	local back = bc.Unit
	local height = math.max(math.abs(ab:Dot(up)), MIN_PART_DIMENSION)
	local depthA = math.max(math.abs(ab:Dot(back)), MIN_PART_DIMENSION)
	local depthB = math.max(math.abs(ac:Dot(back)), MIN_PART_DIMENSION)
	local thickness = math.max(tonumber(options.thickness) or 0.05, 0.01)
	local parts = {}

	local wedgeA = Instance.new("WedgePart")
	wedgeA.Name = name .. "_A"
	wedgeA.Size = Vector3.new(thickness, height, depthA)
	wedgeA.CFrame = CFrame.fromMatrix((a + b) * 0.5, right, up, back)
	configurePart(wedgeA, options, 1)
	wedgeA.Parent = parent
	table.insert(parts, wedgeA)

	local wedgeB = Instance.new("WedgePart")
	wedgeB.Name = name .. "_B"
	wedgeB.Size = Vector3.new(thickness, height, depthB)
	wedgeB.CFrame = CFrame.fromMatrix((a + c) * 0.5, -right, up, -back)
	configurePart(wedgeB, options, 1)
	wedgeB.Parent = parent
	table.insert(parts, wedgeB)

	return parts
end

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
			return contentOrErr
		end
	end

	local ok, contentOrErr = pcall(function()
		return Content.fromUri("rbxassetid://" .. tostring(numericAssetId))
	end)
	if ok and contentOrErr then
		return contentOrErr
	end
	return nil, tostring(contentOrErr)
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
		meshPart.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
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
	local okPart, sourceMeshPartOrErr = pcall(function()
		return AssetService:CreateMeshPartAsync(meshContent)
	end)
	if not okPart or not sourceMeshPartOrErr then
		return nil, tostring(sourceMeshPartOrErr)
	end

	local sourceMeshPart = sourceMeshPartOrErr
	local meshPart = Instance.new("MeshPart")
	meshPart.Name = name
	meshPart.Size = sourceMeshPart.Size
	meshPart.CFrame = sourceMeshPart.CFrame
	pcall(function()
		meshPart.PivotOffset = sourceMeshPart.PivotOffset
	end)
	local okApply, applyErr = pcall(function()
		meshPart:ApplyMesh(sourceMeshPart)
	end)
	sourceMeshPart:Destroy()
	if not okApply then
		meshPart:Destroy()
		return nil, tostring(applyErr)
	end

	applyMeshPartOptions(meshPart, options, triangleCount)
	meshPart.Parent = parent
	return meshPart, nil
end

local function createMeshPartFromState(state, parent, name, options)
	options = options or {}
	if state.faces == 0 then
		return nil, "No mesh faces were generated"
	end

	local okContent, meshContentOrErr = pcall(function()
		return Content.fromObject(state.mesh)
	end)
	if not okContent or not meshContentOrErr then
		destroyEditableMesh(state.mesh)
		return nil, "Mesh content creation failed: " .. tostring(meshContentOrErr)
	end

	local meshContent = meshContentOrErr
	local meshPart, err = createMeshPartFromContent(meshContent, parent, name, options, state.faces)
	destroyEditableMesh(state.mesh)
	return meshPart, err
end

function RoadMeshBuilder.createSurfaceState(triangles)
	local state, err = newMeshState()
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
	options = options or {}
	local thickness = math.max(tonumber(options.thickness) or 0.2, 0.05)
	local surfaceOffset = tonumber(options.surfaceOffset) or 0
	local topOffset = Vector3.new(0, surfaceOffset, 0)
	local bottomOffset = Vector3.new(0, surfaceOffset - thickness, 0)

	local state, err = newMeshState()
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
	local state, err = RoadMeshBuilder.createSurfaceState(triangles)
	if not state then
		return nil, err
	end

	return createMeshPartFromState(state, parent, name, options)
end

function RoadMeshBuilder.createCollisionMesh(parent, name, triangles, options)
	options = options or {}
	local state, err = RoadMeshBuilder.createCollisionState(triangles, options)
	if not state then
		return nil, err
	end

	local collisionOptions = table.clone(options)
	collisionOptions.canCollide = true
	collisionOptions.canQuery = true
	collisionOptions.canTouch = false
	collisionOptions.transparency = 1
	collisionOptions.castShadow = false
	collisionOptions.driveSurface = true
	return createMeshPartFromState(state, parent, name, collisionOptions)
end

function RoadMeshBuilder.createMeshPartFromAssetId(parent, name, assetId, options)
	local content, err = contentFromAssetId(assetId)
	if not content then
		return nil, err
	end

	return createMeshPartFromContent(content, parent, name, options, options and options.triangleCount)
end

function RoadMeshBuilder.createPrimitiveTriangleParts(parent, namePrefix, triangles, options)
	options = options or {}
	local parts = {}
	for index, triangle in ipairs(triangles or {}) do
		local a = triangle[1]
		local b = triangle[2]
		local c = triangle[3]
		if a and b and c then
			local triangleParts = addTriangleWedges(parent, string.format("%s_%04d", namePrefix, index), a, b, c, options)
			for _, part in ipairs(triangleParts) do
				table.insert(parts, part)
			end
		end
	end
	return parts
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
	})
	if not collisionPart then
		visiblePart:Destroy()
		return nil, nil, collisionErr
	end

	return visiblePart, collisionPart, nil
end

local function buildPrimitiveSurfacePair(meshParent, collisionParent, key, triangles, options)
	local style = DEFAULT_SURFACES[key]
	if not style or #(triangles or {}) == 0 then
		return {}, {}, nil
	end

	local surfaceType = string.gsub(key, "s$", "")
	local visibleParts = RoadMeshBuilder.createPrimitiveTriangleParts(meshParent, style.name, triangles, {
		color = style.color,
		material = style.material,
		surfaceType = surfaceType,
		generatedBy = options.generatedBy,
		canCollide = false,
		canQuery = false,
		canTouch = false,
		castShadow = false,
		thickness = options.visualThickness or 0.04,
	})

	local collisionParts = RoadMeshBuilder.createPrimitiveTriangleParts(collisionParent, style.collisionName, triangles, {
		color = style.color,
		material = style.material,
		surfaceType = surfaceType,
		generatedBy = options.generatedBy,
		canCollide = true,
		canQuery = true,
		canTouch = false,
		transparency = 1,
		castShadow = false,
		driveSurface = true,
		thickness = options.collisionThickness or 0.2,
	})

	return visibleParts, collisionParts, nil
end

local function getPolygonFillGroups(meshData)
	local groups = meshData.polygonFillGroups or {}
	if #groups > 0 then
		return groups
	end

	if #(meshData.polygonFillTriangles or {}) > 0 then
		return {
			{
				id = "polygonFill",
				color = "#10b981",
				triangles = meshData.polygonFillTriangles,
			},
		}
	end
	return {}
end

local function buildFillSurfacePair(meshParent, collisionParent, group, index, options)
	local triangles = group and group.triangles or {}
	if #(triangles or {}) == 0 then
		return nil, nil, nil
	end

	local style = DEFAULT_SURFACES.fills
	local fillId = tostring(group.id or index)
	local color = colorFromHex(group.color, style.color)
	local visiblePart, visibleErr = RoadMeshBuilder.createSurfaceMesh(
		meshParent,
		string.format("%s_%03d", style.name, index),
		triangles,
		{
			color = color,
			material = style.material,
			surfaceType = "polygonFill",
			generatedBy = options.generatedBy,
			canCollide = false,
			canQuery = false,
			canTouch = false,
			castShadow = false,
		}
	)
	if not visiblePart then
		return nil, nil, visibleErr
	end

	local collisionPart, collisionErr = RoadMeshBuilder.createCollisionMesh(
		collisionParent,
		string.format("%s_%03d", style.collisionName, index),
		triangles,
		{
			color = color,
			material = style.material,
			surfaceType = "polygonFill",
			generatedBy = options.generatedBy,
			thickness = options.collisionThickness,
			surfaceOffset = options.collisionSurfaceOffset,
		}
	)
	if not collisionPart then
		visiblePart:Destroy()
		return nil, nil, collisionErr
	end

	visiblePart:SetAttribute("PolygonFillId", fillId)
	visiblePart:SetAttribute("PolygonFillColor", tostring(group.color or ""))
	collisionPart:SetAttribute("PolygonFillId", fillId)
	collisionPart:SetAttribute("PolygonFillColor", tostring(group.color or ""))
	return visiblePart, collisionPart, nil
end

local function buildPrimitiveFillSurfacePair(meshParent, collisionParent, group, index, options)
	local triangles = group and group.triangles or {}
	if #(triangles or {}) == 0 then
		return {}, {}, nil
	end

	local style = DEFAULT_SURFACES.fills
	local fillId = tostring(group.id or index)
	local color = colorFromHex(group.color, style.color)
	local visibleParts = RoadMeshBuilder.createPrimitiveTriangleParts(
		meshParent,
		string.format("%s_%03d", style.name, index),
		triangles,
		{
			color = color,
			material = style.material,
			surfaceType = "polygonFill",
			generatedBy = options.generatedBy,
			canCollide = false,
			canQuery = false,
			canTouch = false,
			castShadow = false,
			thickness = options.visualThickness or 0.04,
		}
	)

	local collisionParts = RoadMeshBuilder.createPrimitiveTriangleParts(
		collisionParent,
		string.format("%s_%03d", style.collisionName, index),
		triangles,
		{
			color = color,
			material = style.material,
			surfaceType = "polygonFill",
			generatedBy = options.generatedBy,
			canCollide = true,
			canQuery = true,
			canTouch = false,
			transparency = 1,
			castShadow = false,
			driveSurface = true,
			thickness = options.collisionThickness or 0.2,
		}
	)

	for _, part in ipairs(visibleParts) do
		part:SetAttribute("PolygonFillId", fillId)
		part:SetAttribute("PolygonFillColor", tostring(group.color or ""))
	end
	for _, part in ipairs(collisionParts) do
		part:SetAttribute("PolygonFillId", fillId)
		part:SetAttribute("PolygonFillColor", tostring(group.color or ""))
	end
	return visibleParts, collisionParts, nil
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

local function bucketTrianglesByCenter(triangles, chunkSize)
	local buckets = {}
	local keys = {}

	for _, triangle in ipairs(triangles or {}) do
		local center = triangleCenter(triangle)
		if center then
			local chunkX = math.floor(center.X / chunkSize)
			local chunkZ = math.floor(center.Z / chunkSize)
			local key = tostring(chunkX) .. ":" .. tostring(chunkZ)
			local bucket = buckets[key]
			if not bucket then
				bucket = {
					chunkX = chunkX,
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
			return left.chunkZ < right.chunkZ
		end
		return left.chunkX < right.chunkX
	end)

	return buckets, keys
end

local function buildChunkedSurface(meshParent, key, triangles, options)
	local style = DEFAULT_SURFACES[key]
	if not style or #(triangles or {}) == 0 then
		return {}, nil
	end

	local surfaceType = string.gsub(key, "s$", "")
	local chunkSize = math.max(tonumber(options.chunkSize) or DEFAULT_CHUNK_SIZE, 128)
	local buckets, keys = bucketTrianglesByCenter(triangles, chunkSize)
	local parts = {}
	local errors = {}

	for chunkIndex, bucketKey in ipairs(keys) do
		local bucket = buckets[bucketKey]
		local meshPart, err = RoadMeshBuilder.createSurfaceMesh(
			meshParent,
			string.format("%s_%03d", style.name, chunkIndex),
			bucket.triangles,
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
			table.insert(parts, meshPart)
		elseif err then
			table.insert(errors, string.format("%s[%s]: %s", key, bucketKey, tostring(err)))
		end
	end

	if #errors > 0 then
		return parts, table.concat(errors, " | ")
	end
	return parts, nil
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
	}

	for key, triangles in pairs(surfaceSets) do
		local visiblePart, collisionPart, err = buildSurfacePair(meshFolder, collisionFolder, key, triangles, options)
		if visiblePart and collisionPart then
			table.insert(result.visibleParts, visiblePart)
			table.insert(result.collisionParts, collisionPart)
			table.insert(result.driveSurfaces, collisionPart)
		elseif err then
			table.insert(result.errors, string.format("%s: %s", key, tostring(err)))
		end
	end

	for index, group in ipairs(getPolygonFillGroups(meshData)) do
		local visiblePart, collisionPart, err = buildFillSurfacePair(meshFolder, collisionFolder, group, index, options)
		if visiblePart and collisionPart then
			table.insert(result.visibleParts, visiblePart)
			table.insert(result.collisionParts, collisionPart)
			table.insert(result.driveSurfaces, collisionPart)
		elseif err then
			table.insert(result.errors, string.format("polygonFill[%s]: %s", tostring(group.id or index), tostring(err)))
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
		fills = meshData.polygonFillTriangles,
	}
	local surfaceKeys = options.surfaceKeys or { "roads", "sidewalks", "crosswalks" }

	for _, key in ipairs(surfaceKeys) do
		local visibleParts, err = buildChunkedSurface(meshFolder, key, trianglesByKey[key], options)
		if err then
			table.insert(result.errors, err)
		end
		for _, part in ipairs(visibleParts) do
			table.insert(result.visibleParts, part)
		end
	end

	if #result.visibleParts == 0 then
		meshFolder:Destroy()
		result.meshFolder = nil
	end

	return result
end

function RoadMeshBuilder.createClassifiedPrimitiveMeshes(parent, meshData, options)
	options = options or {}
	local meshFolder = recreateFolder(parent, options.meshFolderName or "RoadGraphBakedSurfaces")
	local collisionFolder = recreateFolder(parent, options.collisionFolderName or "RoadGraphBakedCollision")

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
	}

	for key, triangles in pairs(surfaceSets) do
		local visibleParts, collisionParts, err = buildPrimitiveSurfacePair(meshFolder, collisionFolder, key, triangles, options)
		if err then
			table.insert(result.errors, string.format("%s: %s", key, tostring(err)))
		end
		for _, part in ipairs(visibleParts) do
			table.insert(result.visibleParts, part)
		end
		for _, part in ipairs(collisionParts) do
			table.insert(result.collisionParts, part)
			table.insert(result.driveSurfaces, part)
		end
	end

	for index, group in ipairs(getPolygonFillGroups(meshData)) do
		local visibleParts, collisionParts, err = buildPrimitiveFillSurfacePair(meshFolder, collisionFolder, group, index, options)
		if err then
			table.insert(result.errors, string.format("polygonFill[%s]: %s", tostring(group.id or index), tostring(err)))
		end
		for _, part in ipairs(visibleParts) do
			table.insert(result.visibleParts, part)
		end
		for _, part in ipairs(collisionParts) do
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

return RoadMeshBuilder
