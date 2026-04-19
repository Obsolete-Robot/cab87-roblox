local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local MapGenerator = {}

local WORLD_NAME = "Cab87World"

local function mergedConfig(overrides)
	local out = {}
	for key, value in pairs(Config) do
		out[key] = value
	end
	if overrides then
		for key, value in pairs(overrides) do
			out[key] = value
		end
	end
	return out
end

local function makePart(parent, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local function clamp(n, lo, hi)
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end

local function colorJitter(color, rng, amount)
	local scale = 1 + rng:NextNumber(-amount, amount)
	return Color3.new(
		clamp(color.R * scale, 0, 1),
		clamp(color.G * scale, 0, 1),
		clamp(color.B * scale, 0, 1)
	)
end

local function districtPalette(i, count)
	local hue = ((i - 1) / math.max(count, 1)) % 1
	return Color3.fromHSV(hue, 0.45, 0.90)
end

local function districtCenters(cfg, rng, extent)
	local count = math.max(1, cfg.districtCount or 8)
	local n = math.max(1, math.ceil(math.sqrt(count)))
	local cell = (extent * 2) / n
	local jitter = clamp(cfg.districtJitter or 0.35, 0, 1)
	local centers = {}

	for ix = 0, n - 1 do
		for iz = 0, n - 1 do
			if #centers >= count then
				break
			end
			local baseX = -extent + (ix + 0.5) * cell
			local baseZ = -extent + (iz + 0.5) * cell
			local jx = (rng:NextNumber() - 0.5) * cell * jitter * 2
			local jz = (rng:NextNumber() - 0.5) * cell * jitter * 2
			table.insert(centers, Vector2.new(
				clamp(baseX + jx, -extent, extent),
				clamp(baseZ + jz, -extent, extent)
			))
		end
	end

	while #centers < count do
		table.insert(centers, Vector2.new(
			rng:NextNumber(-extent, extent),
			rng:NextNumber(-extent, extent)
		))
	end

	return centers
end

local function nearestDistrict(point, centers)
	local best = 1
	local bestDist = math.huge
	for i, c in ipairs(centers) do
		local dx = point.X - c.X
		local dz = point.Z - c.Y
		local d2 = dx * dx + dz * dz
		if d2 < bestDist then
			bestDist = d2
			best = i
		end
	end
	return best
end

local function roadKey(axis, pos)
	return axis .. ":" .. string.format("%.3f", pos)
end

local function isTooClose(values, pos, minGap)
	for _, v in ipairs(values) do
		if math.abs(v - pos) < minGap then
			return true
		end
	end
	return false
end

local function addRoad(roads, axis, pos, extent, minGap)
	if math.abs(pos) > extent + 0.001 then
		return false
	end
	local key = roadKey(axis, pos)
	if roads.lookup[key] then
		return false
	end

	local bucket = axis == "v" and roads.vertical or roads.horizontal
	if minGap and isTooClose(bucket, pos, minGap) then
		return false
	end

	roads.lookup[key] = true
	table.insert(bucket, pos)
	return true
end

local function buildRoadNetwork(cfg, rng, extent)
	local roads = {
		vertical = {},
		horizontal = {},
		lookup = {},
	}

	local block = cfg.blockSize
	local ringBlocks = math.max(1, cfg.arterialRingRadiusBlocks or (cfg.cityBlocks - 2))
	local ring = clamp(ringBlocks * block, block, extent)
	local spineOffset = clamp((cfg.arterialSpineOffsetBlocks or 3) * block, block, extent - block)
	local minGap = block * 0.6

	-- Arterial skeleton first: central cross + offset spines + ring.
	for _, x in ipairs({0, spineOffset, -spineOffset, ring, -ring}) do
		addRoad(roads, "v", x, extent)
	end
	for _, z in ipairs({0, spineOffset, -spineOffset, ring, -ring}) do
		addRoad(roads, "h", z, extent)
	end

	-- Secondary roads: fewer, less regular than V1 grid.
	local every = math.max(1, cfg.secondaryRoadEveryBlocks or 3)
	local chance = clamp(cfg.secondaryRoadChance or 0.35, 0, 1)
	for i = -cfg.cityBlocks, cfg.cityBlocks do
		if i % every == 0 then
			local p = i * block
			local nearArterial = (math.abs(math.abs(p) - ring) < 1) or (math.abs(math.abs(p) - spineOffset) < 1) or (math.abs(p) < 1)
			if (not nearArterial) and rng:NextNumber() <= chance then
				addRoad(roads, "v", p, extent, minGap)
			end
			if (not nearArterial) and rng:NextNumber() <= chance then
				addRoad(roads, "h", p, extent, minGap)
			end
		end
	end

	table.sort(roads.vertical)
	table.sort(roads.horizontal)
	return roads
end

local function placeRoadParts(parent, cfg, roads, extent)
	local totalLen = extent * 2 + cfg.blockSize
	local y = cfg.roadSurfaceY or 0

	for _, x in ipairs(roads.vertical) do
		makePart(parent, {
			Name = "Road_NS",
			Size = Vector3.new(cfg.roadWidth, 1, totalLen),
			Position = Vector3.new(x, y, 0),
			Color = Color3.fromRGB(30, 30, 35),
			Material = Enum.Material.Asphalt,
		})
	end

	for _, z in ipairs(roads.horizontal) do
		makePart(parent, {
			Name = "Road_EW",
			Size = Vector3.new(totalLen, 1, cfg.roadWidth),
			Position = Vector3.new(0, y, z),
			Color = Color3.fromRGB(30, 30, 35),
			Material = Enum.Material.Asphalt,
		})
	end
end

local function withBounds(sortedRoads, extent)
	local out = {-extent}
	for _, v in ipairs(sortedRoads) do
		if v > -extent and v < extent then
			table.insert(out, v)
		end
	end
	table.insert(out, extent)
	table.sort(out)
	return out
end

function MapGenerator.Clear()
	local old = Workspace:FindFirstChild(WORLD_NAME)
	if old then
		old:Destroy()
	end
end

function MapGenerator.Generate(overrides)
	local cfg = mergedConfig(overrides)
	local seed = cfg.seed or os.time()
	local rng = Random.new(seed)

	MapGenerator.Clear()

	local world = Instance.new("Model")
	world.Name = WORLD_NAME
	world:SetAttribute("GeneratorVersion", "v2-chunk1.1")
	world:SetAttribute("Seed", seed)
	world.Parent = Workspace

	local roadsFolder = Instance.new("Folder")
	roadsFolder.Name = "Roads"
	roadsFolder.Parent = world

	local buildingsFolder = Instance.new("Folder")
	buildingsFolder.Name = "Buildings"
	buildingsFolder.Parent = world

	local blockSpan = cfg.cityBlocks * cfg.blockSize
	local extent = blockSpan
	local worldSize = blockSpan * 2

	makePart(world, {
		Name = "Ground",
		Size = Vector3.new(worldSize + 300, 2, worldSize + 300),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(44, 92, 52),
		Material = Enum.Material.Grass,
	})

	local roads = buildRoadNetwork(cfg, rng, extent)
	placeRoadParts(roadsFolder, cfg, roads, extent)

	local centers = districtCenters(cfg, rng, extent)
	local districtColors = {}
	for i = 1, #centers do
		districtColors[i] = districtPalette(i, #centers)
	end

	local xBands = withBounds(roads.vertical, extent)
	local zBands = withBounds(roads.horizontal, extent)

	for xi = 1, #xBands - 1 do
		for zi = 1, #zBands - 1 do
			local xA = xBands[xi]
			local xB = xBands[xi + 1]
			local zA = zBands[zi]
			local zB = zBands[zi + 1]

			local spanX = xB - xA
			local spanZ = zB - zA
			local width = spanX - cfg.roadWidth - cfg.buildingInset
			local depth = spanZ - cfg.roadWidth - cfg.buildingInset

			if width > 8 and depth > 8 then
				local center = Vector3.new((xA + xB) * 0.5, 0, (zA + zB) * 0.5)
				local districtId = nearestDistrict(center, centers)
				local baseColor = districtColors[districtId]
				local height = rng:NextNumber(cfg.buildingHeightMin, cfg.buildingHeightMax)

				local part = makePart(buildingsFolder, {
					Name = "Building",
					Size = Vector3.new(width, height, depth),
					Position = center + Vector3.new(0, height * 0.5, 0),
					Color = colorJitter(baseColor, rng, 0.18),
					Material = Enum.Material.Concrete,
				})
				part:SetAttribute("District", districtId)
			end
		end
	end

	return world, cfg
end

function MapGenerator.Regenerate(overrides)
	return MapGenerator.Generate(overrides)
end

return MapGenerator
