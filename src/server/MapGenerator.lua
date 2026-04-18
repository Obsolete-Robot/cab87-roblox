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
	world.Parent = Workspace

	local blockSpan = cfg.cityBlocks * cfg.blockSize
	local worldSize = blockSpan * 2

	makePart(world, {
		Name = "Ground",
		Size = Vector3.new(worldSize + 300, 2, worldSize + 300),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(44, 92, 52),
		Material = Enum.Material.Grass,
	})

	for i = -cfg.cityBlocks, cfg.cityBlocks do
		local x = i * cfg.blockSize
		makePart(world, {
			Name = "Road_NS",
			Size = Vector3.new(cfg.roadWidth, 1, worldSize + cfg.blockSize),
			Position = Vector3.new(x, 0.02, 0),
			Color = Color3.fromRGB(30, 30, 35),
			Material = Enum.Material.Asphalt,
		})

		local z = i * cfg.blockSize
		makePart(world, {
			Name = "Road_EW",
			Size = Vector3.new(worldSize + cfg.blockSize, 1, cfg.roadWidth),
			Position = Vector3.new(0, 0.02, z),
			Color = Color3.fromRGB(30, 30, 35),
			Material = Enum.Material.Asphalt,
		})
	end

	for gx = -cfg.cityBlocks, cfg.cityBlocks - 1 do
		for gz = -cfg.cityBlocks, cfg.cityBlocks - 1 do
			local center = Vector3.new((gx + 0.5) * cfg.blockSize, 0, (gz + 0.5) * cfg.blockSize)
			local width = cfg.blockSize - cfg.roadWidth - cfg.buildingInset
			local depth = cfg.blockSize - cfg.roadWidth - cfg.buildingInset
			local height = rng:NextNumber(cfg.buildingHeightMin, cfg.buildingHeightMax)

			makePart(world, {
				Name = "Building",
				Size = Vector3.new(width, height, depth),
				Position = center + Vector3.new(0, height * 0.5, 0),
				Color = Color3.fromRGB(
					rng:NextInteger(80, 210),
					rng:NextInteger(80, 210),
					rng:NextInteger(80, 210)
				),
				Material = Enum.Material.Concrete,
			})
		end
	end

	return world, cfg
end

function MapGenerator.Regenerate(overrides)
	return MapGenerator.Generate(overrides)
end

return MapGenerator
