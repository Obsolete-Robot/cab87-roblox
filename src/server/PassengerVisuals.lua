local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PassengerVisuals = {}

local PASSENGER_BASE_TRANSPARENCY_ATTR = "Cab87BaseTransparency"
local PASSENGER_BASE_HEIGHT = 4.1
local PASSENGER_BASE_LEG_HEIGHT = 1.55
local PASSENGER_BASE_TORSO_Y = 2.1
local PASSENGER_BASE_RUN_BOB_HEIGHT = 0.16
local PASSENGER_COLORS = {
	Color3.fromRGB(49, 151, 255),
	Color3.fromRGB(255, 122, 65),
	Color3.fromRGB(181, 92, 255),
	Color3.fromRGB(70, 210, 135),
	Color3.fromRGB(255, 216, 84),
	Color3.fromRGB(245, 82, 117),
}

local function getConfigNumber(key, fallback)
	local value = Config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function getConfigColor(key, fallback)
	local value = Config[key]
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local function getPassengerModelScale()
	local height = math.max(getConfigNumber("passengerModelHeight", 5.5), 0.1)
	return height / PASSENGER_BASE_HEIGHT
end

local function setPartRuntimeDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function makePart(parent, props)
	local part = Instance.new("Part")
	setPartRuntimeDefaults(part)
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local function destroyInstance(instance)
	if instance and instance.Parent then
		instance:Destroy()
	end
end

local function getVisibleTarget(target)
	if type(target) == "table" then
		return target.model
	end

	return target
end

local function createCircleMarker(parent, name, position, radius, color)
	local marker = Instance.new("Model")
	marker.Name = name
	marker:SetAttribute("Radius", radius)
	marker:SetAttribute("GeneratedBy", "Cab87PassengerService")
	marker.Parent = parent

	local segments = math.max(12, math.floor(getConfigNumber("passengerMarkerSegments", 28)))
	local thickness = math.max(getConfigNumber("passengerMarkerThickness", 0.35), 0.05)
	local transparency = math.clamp(getConfigNumber("passengerMarkerTransparency", 0.12), 0, 1)
	local heightOffset = getConfigNumber("passengerMarkerHeightOffset", 0.25)
	local segmentLength = (2 * math.pi * radius / segments) * 0.92
	local y = position.Y + heightOffset

	for i = 1, segments do
		local angle = ((i - 1) / segments) * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local segmentPosition = Vector3.new(position.X, y, position.Z) + radial * radius
		local segment = makePart(marker, {
			Name = string.format("Segment_%02d", i),
			Size = Vector3.new(thickness, 0.12, segmentLength),
			CFrame = CFrame.lookAt(segmentPosition, segmentPosition + tangent),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = transparency,
		})
		segment:SetAttribute(PASSENGER_BASE_TRANSPARENCY_ATTR, transparency)
	end

	return marker
end

function PassengerVisuals.recreateFolder(parent, name)
	local oldFolder = parent:FindFirstChild(name)
	if oldFolder then
		oldFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function PassengerVisuals.createStop(parent, id, position)
	local part = makePart(parent, {
		Name = string.format("PassengerStop_%03d", id),
		Size = Vector3.new(2, 0.2, 2),
		Position = position,
		Transparency = 1,
		Color = Color3.fromRGB(255, 255, 255),
	})
	part:SetAttribute("PassengerStopId", id)
	part:SetAttribute("GeneratedBy", "Cab87PassengerService")
	return part
end

function PassengerVisuals.createPassenger(parent, passengerId, position, rng)
	rng = rng or Random.new()

	local model = Instance.new("Model")
	model.Name = string.format("Passenger_%03d", passengerId)
	model:SetAttribute("PassengerId", passengerId)
	model:SetAttribute("GeneratedBy", "Cab87PassengerService")
	model.Parent = parent

	local shirtColor = PASSENGER_COLORS[((passengerId - 1) % #PASSENGER_COLORS) + 1]
	local pantsColor = Color3.fromRGB(
		rng:NextInteger(35, 80),
		rng:NextInteger(40, 90),
		rng:NextInteger(45, 100)
	)
	local scale = getPassengerModelScale()
	local torsoY = PASSENGER_BASE_TORSO_Y * scale
	local runBobHeight = PASSENGER_BASE_RUN_BOB_HEIGHT * scale
	local legHalfHeight = PASSENGER_BASE_LEG_HEIGHT * scale * 0.5
	local groundLift = PASSENGER_BASE_LEG_HEIGHT
		* scale
		* math.clamp(getConfigNumber("passengerGroundLiftLegFraction", 0.5), -0.5, 1.5)

	model:SetAttribute("PassengerHeight", PASSENGER_BASE_HEIGHT * scale)
	model:SetAttribute("PassengerGroundLift", groundLift)
	model:SetAttribute("PassengerScale", scale)

	local torso = makePart(model, {
		Name = "Torso",
		Size = Vector3.new(1.7, 2.2, 0.85) * scale,
		Position = position + Vector3.new(0, torsoY, 0),
		Color = shirtColor,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.1, 1.1, 1.1) * scale,
		Position = position + Vector3.new(0, 3.55, 0) * scale,
		Color = Color3.fromRGB(232, 184, 142),
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "LeftLeg",
		Size = Vector3.new(0.65, PASSENGER_BASE_LEG_HEIGHT, 0.65) * scale,
		Position = position + Vector3.new(-0.42 * scale, legHalfHeight, 0),
		Color = pantsColor,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "RightLeg",
		Size = Vector3.new(0.65, PASSENGER_BASE_LEG_HEIGHT, 0.65) * scale,
		Position = position + Vector3.new(0.42 * scale, legHalfHeight, 0),
		Color = pantsColor,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "LeftArm",
		Size = Vector3.new(0.45, 1.75, 0.45) * scale,
		Position = position + Vector3.new(-1.08, 2.05, 0) * scale,
		Color = shirtColor,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(model, {
		Name = "RightArm",
		Size = Vector3.new(0.45, 1.75, 0.45) * scale,
		Position = position + Vector3.new(1.08, 2.05, 0) * scale,
		Color = shirtColor,
		Material = Enum.Material.SmoothPlastic,
	})

	model.PrimaryPart = torso

	return {
		model = model,
		torsoY = torsoY,
		runBobHeight = runBobHeight,
		groundLift = groundLift,
		pickupMarker = nil,
		deliveryMarker = nil,
	}
end

function PassengerVisuals.setPassengerStops(visual, pickupStopId, targetStopId)
	if not visual or not visual.model then
		return
	end

	visual.model:SetAttribute("PickupStopId", pickupStopId)
	visual.model:SetAttribute("TargetStopId", targetStopId)
	visual.model:SetAttribute("Diving", false)
end

function PassengerVisuals.createPickupMarker(visual, parent, passengerId, stop, radius)
	local marker = createCircleMarker(
		parent,
		string.format("PickupCircle_%03d", passengerId),
		stop.position,
		radius,
		getConfigColor("passengerPickupColor", Color3.fromRGB(70, 255, 120))
	)
	marker:SetAttribute("PassengerId", passengerId)
	marker:SetAttribute("PickupStopId", stop.id)
	visual.pickupMarker = marker
	return marker
end

function PassengerVisuals.createDeliveryMarker(visual, parent, passengerId, stop, radius)
	local marker = createCircleMarker(
		parent,
		string.format("DeliveryCircle_%03d", passengerId),
		stop.position,
		radius,
		getConfigColor("passengerDeliveryColor", Color3.fromRGB(255, 70, 55))
	)
	marker:SetAttribute("PassengerId", passengerId)
	marker:SetAttribute("TargetStopId", stop.id)
	visual.deliveryMarker = marker
	return marker
end

function PassengerVisuals.setVisible(target, visible)
	local model = getVisibleTarget(target)
	if not model then
		return
	end

	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			local baseTransparency = item:GetAttribute(PASSENGER_BASE_TRANSPARENCY_ATTR)
			if type(baseTransparency) ~= "number" then
				baseTransparency = item.Transparency
				item:SetAttribute(PASSENGER_BASE_TRANSPARENCY_ATTR, baseTransparency)
			end

			item.Transparency = if visible then baseTransparency else 1
		elseif item:IsA("BillboardGui") or item:IsA("SurfaceGui") then
			item.Enabled = visible
		end
	end

	model:SetAttribute("Visible", visible)
end

function PassengerVisuals.setPassengerVisible(visual, visible)
	PassengerVisuals.setVisible(visual, visible)
end

function PassengerVisuals.setPickupVisible(visual, visible)
	PassengerVisuals.setVisible(visual and visual.pickupMarker, visible)
end

function PassengerVisuals.setDeliveryVisible(visual, visible)
	PassengerVisuals.setVisible(visual and visual.deliveryMarker, visible)
end

function PassengerVisuals.setDiving(visual, diving, targetPosition)
	if not visual or not visual.model then
		return
	end

	visual.model:SetAttribute("Diving", diving)
	if targetPosition then
		visual.model:SetAttribute("DiveTarget", targetPosition)
	end
end

function PassengerVisuals.setParent(visual, parent)
	if visual and visual.model then
		visual.model.Parent = parent
	end
end

function PassengerVisuals.setPose(visual, groundPosition, lookAt, moving, runPhase, pose)
	if not visual or not visual.model then
		return
	end

	local runBobHeight = visual.runBobHeight or PASSENGER_BASE_RUN_BOB_HEIGHT
	local runBob = if moving then math.abs(math.sin(runPhase or 0)) * runBobHeight else 0
	local heightOffset = (pose and pose.heightOffset) or 0
	local torsoY = visual.torsoY or PASSENGER_BASE_TORSO_Y
	local groundLift = visual.groundLift or 0
	local torsoPosition = groundPosition + Vector3.new(0, groundLift + torsoY + runBob + heightOffset, 0)
	local lookDirection = lookAt and Vector3.new(lookAt.X - groundPosition.X, 0, lookAt.Z - groundPosition.Z) or Vector3.zero
	local pivot

	if lookDirection.Magnitude > 0.001 then
		pivot = CFrame.lookAt(torsoPosition, torsoPosition + lookDirection.Unit)
	else
		pivot = CFrame.new(torsoPosition)
	end

	local pitchRadians = (pose and pose.pitchRadians) or 0
	local rollRadians = (pose and pose.rollRadians) or 0
	if math.abs(pitchRadians) > 0.001 or math.abs(rollRadians) > 0.001 then
		pivot *= CFrame.Angles(pitchRadians, 0, rollRadians)
	end

	visual.model:PivotTo(pivot)
end

function PassengerVisuals.destroyMarkers(visual)
	if not visual then
		return
	end

	destroyInstance(visual.pickupMarker)
	destroyInstance(visual.deliveryMarker)
	visual.pickupMarker = nil
	visual.deliveryMarker = nil
end

function PassengerVisuals.destroyPassengerModel(visual)
	if not visual then
		return
	end

	destroyInstance(visual.model)
	visual.model = nil
end

function PassengerVisuals.destroyPassenger(visual)
	PassengerVisuals.destroyPassengerModel(visual)
	PassengerVisuals.destroyMarkers(visual)
end

return PassengerVisuals
