local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CarProfiles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CarProfiles"))

local CabFactory = {}
CabFactory.__index = CabFactory

local NORMAL_DRIFT_SMOKE_COLOR = ColorSequence.new(Color3.fromRGB(210, 210, 210))
local CAB_CONTROLLER_SIZE = Vector3.new(10, 2, 16)
local CAB_WHEEL_OFFSETS = {
	Vector3.new(4.4, -1.2, 5.6),
	Vector3.new(-4.4, -1.2, 5.6),
	Vector3.new(4.4, -1.2, -5.6),
	Vector3.new(-4.4, -1.2, -5.6),
}

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

local function addDriftSmoke(wheel, emitters)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriftSmokeAttachment"
	attachment.Position = Vector3.new(0, -0.8, 0)
	attachment.Parent = wheel

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DriftSmoke"
	emitter.Enabled = false
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 95
	emitter.Lifetime = NumberRange.new(0.25, 0.7)
	emitter.Speed = NumberRange.new(8, 18)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Drag = 5
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Color = NORMAL_DRIFT_SMOKE_COLOR
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1),
		NumberSequenceKeypoint.new(1, 4.5),
	})
	emitter.Parent = attachment

	table.insert(emitters, emitter)
end

local function getNumberConfig(key, fallback, configSource)
	local value = (configSource or Config)[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function getVector3Config(key, fallback, configSource)
	local value = (configSource or Config)[key]
	if typeof(value) == "Vector3" then
		return value
	end

	return fallback
end

local function createCarConfig(profileName, overrides, baseConfig, carProfiles)
	baseConfig = baseConfig or Config
	carProfiles = carProfiles or CarProfiles

	local profile = carProfiles.get(profileName or baseConfig.carDefaultProfileName)
	local carConfig = setmetatable({}, {
		__index = baseConfig,
	})

	for key, value in pairs(profile) do
		carConfig[key] = value
	end

	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			carConfig[key] = value
		end
	end

	carConfig.profileName = carConfig.profileName or profileName or baseConfig.carDefaultProfileName
	return carConfig
end

local function canUseAttributeValue(value)
	local valueType = typeof(value)
	return valueType == "boolean"
		or valueType == "number"
		or valueType == "string"
		or valueType == "Vector3"
		or valueType == "Color3"
		or valueType == "CFrame"
end

local function getAttributeSafeValue(value)
	if canUseAttributeValue(value) then
		return value
	end

	if type(value) == "table" then
		local parts = {}
		for _, item in ipairs(value) do
			if type(item) == "string" and item ~= "" then
				table.insert(parts, item)
			end
		end

		if #parts > 0 then
			return table.concat(parts, ",")
		end
	end

	return nil
end

local function setCabConfigAttributes(car, carConfig, baseConfig, carProfiles)
	baseConfig = baseConfig or Config
	carProfiles = carProfiles or CarProfiles

	local profileAttribute = baseConfig.carProfileAttribute or "Cab87CarProfile"
	local configPrefix = baseConfig.carConfigAttributePrefix or "Cab87CarConfig_"
	car:SetAttribute(profileAttribute, carConfig.profileName or baseConfig.carDefaultProfileName)

	for _, key in ipairs(carProfiles.visualAttributeKeys or {}) do
		local value = getAttributeSafeValue(carConfig[key])
		if value ~= nil then
			car:SetAttribute(configPrefix .. key, value)
		end
	end
end

local function getCabModelAssetId(configSource)
	local assetId = (configSource or Config).carModelAssetId
	if type(assetId) == "string" then
		assetId = tonumber(assetId)
	end

	if type(assetId) ~= "number" or assetId <= 0 or assetId ~= assetId then
		return nil
	end

	return math.floor(assetId)
end

local function sanitizeCabAssetVisual(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function countBaseParts(root)
	local count = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end

	return count
end

local function alignCabAssetVisualToPivot(visual, basePivot, carConfig)
	local yawOffset = math.rad(getNumberConfig("carModelAssetYawOffsetDegrees", 0, carConfig))
	visual:PivotTo(basePivot * CFrame.Angles(0, yawOffset, 0))

	if carConfig.carModelAssetGroundAlign ~= false then
		local boundsCFrame, boundsSize = visual:GetBoundingBox()
		local groundY = basePivot.Position.Y - getNumberConfig("carRideHeight", 2.3, carConfig)
		local targetCenter = Vector3.new(
			basePivot.Position.X,
			groundY + boundsSize.Y * 0.5,
			basePivot.Position.Z
		)
		visual:PivotTo(CFrame.new(targetCenter - boundsCFrame.Position) * visual:GetPivot())
	end

	local offset = getVector3Config("carModelAssetOffset", Vector3.new(0, 0, 0), carConfig)
	if offset.Magnitude > 0 then
		visual:PivotTo(visual:GetPivot() * CFrame.new(offset))
	end
end

local function alignCabAssetVisual(visual, spawnPosition, carConfig)
	alignCabAssetVisualToPivot(visual, CFrame.new(spawnPosition), carConfig)
end

local function loadCabAssetVisual(car, spawnPosition, carConfig)
	local assetId = getCabModelAssetId(carConfig)
	if not assetId then
		return nil
	end

	local ok, loadedAsset = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not loadedAsset then
		warn("[cab87] Failed to load cab model asset " .. tostring(assetId) .. "; using procedural cab.")
		return nil
	end

	local visual = Instance.new("Model")
	visual.Name = "CabAssetVisual"

	for _, child in ipairs(loadedAsset:GetChildren()) do
		child.Parent = visual
	end
	loadedAsset:Destroy()

	visual.Parent = car
	sanitizeCabAssetVisual(visual)

	local partCount = countBaseParts(visual)
	if partCount <= 0 then
		warn("[cab87] Cab model asset " .. tostring(assetId) .. " has no BaseParts; using procedural cab.")
		visual:Destroy()
		return nil
	end

	local scale = getNumberConfig("carModelAssetScale", 1, carConfig)
	if scale > 0 and math.abs(scale - 1) > 0.001 then
		local okScale, scaleError = pcall(function()
			visual:ScaleTo(scale)
		end)
		if not okScale then
			warn("[cab87] Cab model asset scale failed: " .. tostring(scaleError))
		end
	end

	alignCabAssetVisual(visual, spawnPosition, carConfig)
	visual:SetAttribute("GeneratedBy", "Cab87CabAsset")

	return visual
end

local function createDriverSeat(car, spawnPosition, hasAssetVisual, carConfig)
	local seatOffset = getVector3Config("carDriverSeatOffset", Vector3.new(0, 1.5, 1), carConfig)
	local seatYaw = math.rad(getNumberConfig("carDriverSeatYawOffsetDegrees", 180, carConfig))
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Anchored = true
	seat.Size = Vector3.new(3.5, 1, 4)
	seat.CFrame = CFrame.new(spawnPosition + seatOffset) * CFrame.Angles(0, seatYaw, 0)
	seat.Transparency = if hasAssetVisual then 1 else 0.2
	seat.Color = Color3.fromRGB(35, 35, 40)
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = car

	return seat
end

local function addAssetDriftSmokeAnchors(car, spawnPosition, emitters)
	for i, offset in ipairs(CAB_WHEEL_OFFSETS) do
		if offset.Z < 0 then
			local anchor = makePart(car, {
				Name = "DriftSmokeAnchor" .. i,
				Size = Vector3.new(0.4, 0.4, 0.4),
				Position = spawnPosition + offset,
				Transparency = 1,
				CanQuery = false,
				CanCollide = false,
				CanTouch = false,
			})
			addDriftSmoke(anchor, emitters)
		end
	end
end

local function createProceduralCabVisual(car, spawnPosition, driftEmitters)
	makePart(car, {
		Name = "Body",
		Size = CAB_CONTROLLER_SIZE,
		Position = spawnPosition,
		Color = Color3.fromRGB(255, 206, 38),
		Material = Enum.Material.SmoothPlastic,
	})

	makePart(car, {
		Name = "Roof",
		Size = Vector3.new(8, 1.5, 8),
		Position = spawnPosition + Vector3.new(0, 2, -1),
		Color = Color3.fromRGB(255, 227, 120),
		Material = Enum.Material.SmoothPlastic,
	})

	makePart(car, {
		Name = "CabSign",
		Size = Vector3.new(3.2, 0.8, 1.4),
		Position = spawnPosition + Vector3.new(0, 3.4, -1),
		Color = Color3.fromRGB(255, 245, 170),
		Material = Enum.Material.Neon,
	})

	for i, offset in ipairs(CAB_WHEEL_OFFSETS) do
		local wheel = makePart(car, {
			Name = "Wheel" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2, 1.4, 2.2),
			Position = spawnPosition + offset,
			Color = Color3.fromRGB(25, 25, 30),
			Material = Enum.Material.SmoothPlastic,
		})
		wheel.CFrame = wheel.CFrame * CFrame.Angles(0, 0, math.rad(90))

		if offset.Z < 0 then
			addDriftSmoke(wheel, driftEmitters)
		end
	end
end

local function createCab(world, spawnPose, carConfig, baseConfig, carProfiles)
	local cabConfig = carConfig or createCarConfig(nil, nil, baseConfig, carProfiles)
	local spawnPosition = (spawnPose and spawnPose.position) or cabConfig.carSpawn
	local spawnYaw = (spawnPose and spawnPose.yaw) or 0
	local car = Instance.new("Model")
	car.Name = "Cab87Taxi"
	car.Parent = world
	setCabConfigAttributes(car, cabConfig, baseConfig, carProfiles)
	local driftEmitters = {}

	local controllerRoot = makePart(car, {
		Name = "ControlRoot",
		Size = CAB_CONTROLLER_SIZE,
		Position = spawnPosition,
		Transparency = 1,
		CanQuery = false,
		CanCollide = false,
		CanTouch = false,
		Material = Enum.Material.SmoothPlastic,
	})

	local assetVisual = loadCabAssetVisual(car, spawnPosition, cabConfig)
	if assetVisual then
		addAssetDriftSmokeAnchors(car, spawnPosition, driftEmitters)
	else
		createProceduralCabVisual(car, spawnPosition, driftEmitters)
	end

	local seat = createDriverSeat(car, spawnPosition, assetVisual ~= nil, cabConfig)

	if cabConfig.drivePromptEnabled ~= false then
		local entryPrompt = Instance.new("ProximityPrompt")
		entryPrompt.Name = "DrivePrompt"
		entryPrompt.ActionText = "Drive"
		entryPrompt.ObjectText = "Cab"
		entryPrompt.KeyboardKeyCode = Enum.KeyCode.E
		entryPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		entryPrompt.HoldDuration = 0
		entryPrompt.MaxActivationDistance = 12
		entryPrompt.RequiresLineOfSight = false
		entryPrompt.Parent = seat
		entryPrompt.Triggered:Connect(function(player)
			if seat.Occupant then
				return
			end

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				seat:Sit(humanoid)
			end
		end)
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			entryPrompt.Enabled = seat.Occupant == nil
		end)
	end

	car.PrimaryPart = controllerRoot
	car:PivotTo(CFrame.new(spawnPosition) * CFrame.Angles(0, spawnYaw, 0))

	local serverPivot = Instance.new("CFrameValue")
	serverPivot.Name = cabConfig.carServerPivotValueName
	serverPivot.Value = car:GetPivot()
	serverPivot.Parent = car

	local parts = {}
	for _, item in ipairs(car:GetDescendants()) do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end

	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = part == seat
	end

	return car, seat, driftEmitters
end

local function setCabConfigAttribute(car, key, value, configSource)
	if not car then
		return
	end

	local safeValue = getAttributeSafeValue(value)
	if safeValue ~= nil then
		local configPrefix = (configSource or Config).carConfigAttributePrefix or "Cab87CarConfig_"
		car:SetAttribute(configPrefix .. key, safeValue)
	end
end

local function applyCabModelAssetScale(car, carConfig)
	if not car or not car.Parent then
		return
	end

	local visual = car:FindFirstChild("CabAssetVisual")
	if not (visual and visual:IsA("Model")) then
		return
	end

	local scale = math.max(getNumberConfig("carModelAssetScale", 1, carConfig), 0.05)
	local okScale, scaleError = pcall(function()
		visual:ScaleTo(scale)
	end)
	if not okScale then
		warn("[cab87] Live cab model asset scale failed: " .. tostring(scaleError))
		return
	end

	alignCabAssetVisualToPivot(visual, car:GetPivot(), carConfig)
	setCabConfigAttribute(car, "carModelAssetScale", scale, carConfig)
end


function CabFactory.new(options)
	options = options or {}

	return setmetatable({
		config = options.config or Config,
		carProfiles = options.carProfiles or CarProfiles,
	}, CabFactory)
end

function CabFactory:createConfig(profileName, overrides)
	return createCarConfig(profileName or self.config.carDefaultProfileName, overrides, self.config, self.carProfiles)
end

function CabFactory:createCab(world, spawnPose, carConfig)
	return createCab(world, spawnPose, carConfig or self:createConfig(), self.config, self.carProfiles)
end

function CabFactory:applyLiveConfig(car, carConfig, key, value)
	if carConfig then
		carConfig[key] = value
	end

	if key == "carModelAssetScale" then
		applyCabModelAssetScale(car, carConfig or self.config)
	end
end

return CabFactory
