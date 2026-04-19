local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local AuthoredRoadRuntime = require(script.Parent:WaitForChild("AuthoredRoadRuntime"))
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))

local NORMAL_DRIFT_SMOKE_COLOR = ColorSequence.new(Color3.fromRGB(210, 210, 210))
local BOOST_DRIFT_SMOKE_COLOR = ColorSequence.new(Color3.fromRGB(65, 185, 255))

local function yawToForward(yaw)
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

local function yawToRight(yaw)
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
end

local function vectorToYaw(vector)
	return math.atan2(vector.X, vector.Z)
end

local function getAngleDelta(fromAngle, toAngle)
	return math.atan2(math.sin(toAngle - fromAngle), math.cos(toAngle - fromAngle))
end

local function moveAngleToward(fromAngle, toAngle, maxDelta)
	local delta = getAngleDelta(fromAngle, toAngle)
	return fromAngle + math.clamp(delta, -maxDelta, maxDelta)
end

local function getOrCreateDriveInputRemote()
	local remote = ReplicatedStorage:FindFirstChild(Config.driveInputRemoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = Config.driveInputRemoteName
		remote.Parent = ReplicatedStorage
	end

	return remote
end

local function getOrCreateCameraEventRemote()
	local remote = ReplicatedStorage:FindFirstChild(Config.cameraEventRemoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = Config.cameraEventRemoteName
		remote.Parent = ReplicatedStorage
	end

	return remote
end

local function isDebugTuningEnabled()
	return Config.debugPanelEnabled == true
		and (not Config.debugPanelStudioOnly or RunService:IsStudio())
end

local function getOrCreateDebugTuneRemote()
	if not isDebugTuningEnabled() then
		return nil
	end

	local remote = ReplicatedStorage:FindFirstChild(Config.debugTuneRemoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = Config.debugTuneRemoteName
		remote.Parent = ReplicatedStorage
	end

	return remote
end

local function normalizeTuningValue(value, property)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end

	local minValue = property.min
	local maxValue = property.max
	if type(minValue) ~= "number" or type(maxValue) ~= "number" then
		return nil
	end

	if maxValue < minValue then
		maxValue = minValue
	end

	value = math.clamp(value, minValue, maxValue)

	if type(property.step) == "number" and property.step > 0 then
		value = minValue + math.floor((value - minValue) / property.step + 0.5) * property.step
		value = math.clamp(value, minValue, maxValue)
	end

	return value
end

local function runDebugTuning(debugTuneRemote)
	if not debugTuneRemote then
		return
	end

	local propertiesByKey = {}
	local defaultValues = {}

	for _, property in ipairs(Config.debugTuningProperties or {}) do
		if type(property) == "table" and type(property.key) == "string" then
			local currentValue = Config[property.key]
			if type(currentValue) == "number" and normalizeTuningValue(currentValue, property) ~= nil then
				propertiesByKey[property.key] = property
				defaultValues[property.key] = currentValue
			end
		end
	end

	local function getSnapshot()
		local snapshot = {}
		for key in pairs(propertiesByKey) do
			snapshot[key] = Config[key]
		end
		return snapshot
	end

	debugTuneRemote.OnServerEvent:Connect(function(_player, action, key, value)
		if action == "Snapshot" then
			debugTuneRemote:FireClient(_player, "Snapshot", getSnapshot())
			return
		end

		if action == "ResetAll" then
			for resetKey, defaultValue in pairs(defaultValues) do
				Config[resetKey] = defaultValue
			end
			debugTuneRemote:FireAllClients("Snapshot", getSnapshot())
			return
		end

		if type(key) ~= "string" then
			return
		end

		local property = propertiesByKey[key]
		if not property then
			return
		end

		if action == "Reset" then
			Config[key] = defaultValues[key]
			debugTuneRemote:FireAllClients("Set", key, Config[key])
		elseif action == "Set" then
			local normalizedValue = normalizeTuningValue(value, property)
			if normalizedValue == nil then
				return
			end

			Config[key] = normalizedValue
			debugTuneRemote:FireAllClients("Set", key, normalizedValue)
		end
	end)
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

local function trackPart(list, part)
	table.insert(list, part)
	return part
end

local function makeRamp(parent, basePosition, yaw)
	local pitch = math.atan2(Config.rampHeight, Config.rampRun)
	local slopeLength = math.sqrt(Config.rampRun * Config.rampRun + Config.rampHeight * Config.rampHeight)
	local forward = yawToForward(yaw)
	local centerXZ = basePosition + forward * (Config.rampRun * 0.5)
	local centerY = Config.roadSurfaceY - (Config.rampThickness * 0.5 * math.cos(pitch))
		+ Config.rampHeight * 0.5

	return makePart(parent, {
		Name = "JumpRamp",
		Size = Vector3.new(Config.rampWidth, Config.rampThickness, slopeLength),
		CFrame = CFrame.new(Vector3.new(centerXZ.X, centerY, centerXZ.Z))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(-pitch, 0, 0),
		Color = Color3.fromRGB(238, 177, 46),
		Material = Enum.Material.Metal,
	})
end

local function makeLandingPlatform(parent, basePosition, yaw)
	local forward = yawToForward(yaw)
	local centerXZ = basePosition + forward * (Config.rampRun + Config.stuntPlatformGap)
	local thickness = 2
	local topY = Config.roadSurfaceY + Config.stuntPlatformHeight

	return makePart(parent, {
		Name = "LandingPad",
		Size = Vector3.new(Config.stuntPlatformWidth, thickness, Config.stuntPlatformLength),
		CFrame = CFrame.new(Vector3.new(centerXZ.X, topY - thickness * 0.5, centerXZ.Z))
			* CFrame.Angles(0, yaw, 0),
		Color = Color3.fromRGB(67, 78, 89),
		Material = Enum.Material.Concrete,
	})
end

local function buildStuntFeatures(world, driveSurfaces)
	local laneOffset = Config.roadWidth * 0.25
	local features = {
		{ base = Vector3.new(-laneOffset, 0, -Config.blockSize * 2), yaw = 0 },
		{ base = Vector3.new(laneOffset, 0, Config.blockSize * 2), yaw = math.pi },
		{ base = Vector3.new(-Config.blockSize * 2, 0, laneOffset), yaw = math.pi * 0.5 },
		{ base = Vector3.new(Config.blockSize * 2, 0, -laneOffset), yaw = -math.pi * 0.5 },
	}

	for _, feature in ipairs(features) do
		trackPart(driveSurfaces, makeRamp(world, feature.base, feature.yaw))
		trackPart(driveSurfaces, makeLandingPlatform(world, feature.base, feature.yaw))
	end
end

local function collectWorldParts(world)
	local driveSurfaces = {}
	local crashObstacles = {}

	for _, item in ipairs(world:GetDescendants()) do
		if item:IsA("BasePart") then
			if item:GetAttribute("DriveSurface") == true
				or item.Name == "Ground"
				or item.Name == "Road_NS"
				or item.Name == "Road_EW"
			then
				table.insert(driveSurfaces, item)
			elseif item.Name == "Building" then
				table.insert(crashObstacles, item)
			end
		end
	end

	return driveSurfaces, crashObstacles
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

local function createCab(world, spawnPose)
	local spawnPosition = (spawnPose and spawnPose.position) or Config.carSpawn
	local spawnYaw = (spawnPose and spawnPose.yaw) or 0
	local car = Instance.new("Model")
	car.Name = "Cab87Taxi"
	car.Parent = world
	local driftEmitters = {}

	local body = makePart(car, {
		Name = "Body",
		Size = Vector3.new(10, 2, 16),
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

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Anchored = true
	seat.Size = Vector3.new(3.5, 1, 4)
	seat.CFrame = CFrame.new(spawnPosition + Vector3.new(0, 1.5, 1))
		* CFrame.Angles(0, math.rad(180), 0)
	seat.Transparency = 0.2
	seat.Color = Color3.fromRGB(35, 35, 40)
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = car

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

	makePart(car, {
		Name = "CabSign",
		Size = Vector3.new(3.2, 0.8, 1.4),
		Position = spawnPosition + Vector3.new(0, 3.4, -1),
		Color = Color3.fromRGB(255, 245, 170),
		Material = Enum.Material.Neon,
	})

	local wheelOffsets = {
		Vector3.new(4.4, -1.2, 5.6),
		Vector3.new(-4.4, -1.2, 5.6),
		Vector3.new(4.4, -1.2, -5.6),
		Vector3.new(-4.4, -1.2, -5.6),
	}

	for i, offset in ipairs(wheelOffsets) do
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

	car.PrimaryPart = body
	car:PivotTo(CFrame.new(spawnPosition) * CFrame.Angles(0, spawnYaw, 0))

	local serverPivot = Instance.new("CFrameValue")
	serverPivot.Name = Config.carServerPivotValueName
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

local function runCarController(car, seat, driftEmitters, driveInputRemote, cameraEventRemote, driveSurfaces, crashObstacles, spawnPose)
	local defaultSpawnPose = spawnPose or {
		position = Config.carSpawn,
		yaw = 0,
	}
	local position = defaultSpawnPose.position
	local yaw = defaultSpawnPose.yaw
	local velocity = Vector3.zero
	local verticalVelocity = 0
	local grounded = true
	local visualPitch = 0
	local visualRoll = 0
	local visualDriveRoll = 0
	local visualDriftRoll = 0
	local airPitchVelocity = 0
	local airRollVelocity = 0
	local reverseHoldTime = 0
	local driftChargeTime = 0
	local driftBoostReady = false
	local driftInputWasHeld = false
	local boostTimer = 0
	local boostVisualPulse = 0
	local landingVisualPulse = 0
	local elapsedTime = 0
	local fallResetCooldown = 0
	local pendingFallResetPose = nil
	local safeGroundHistory = {}
	local driverInput = {}
	local smokeState = "off"
	local lastOccupant = nil
	local hiddenCharacterState = nil
	local crashShakeCooldown = 0

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = driveSurfaces
	local serverPivotValue = car:FindFirstChild(Config.carServerPivotValueName)
	if serverPivotValue and not serverPivotValue:IsA("CFrameValue") then
		serverPivotValue:Destroy()
		serverPivotValue = nil
	end

	if not serverPivotValue then
		serverPivotValue = Instance.new("CFrameValue")
		serverPivotValue.Name = Config.carServerPivotValueName
		serverPivotValue.Parent = car
	end
	car:SetAttribute(Config.carVisualDriftingAttribute, false)
	car:SetAttribute(Config.carVisualDriftBoostReadyAttribute, false)
	car:SetAttribute(Config.carVisualBoostPulseAttribute, boostVisualPulse)
	car:SetAttribute(Config.carVisualLandingPulseAttribute, landingVisualPulse)
	car:SetAttribute(Config.carVisualLandingSpeedAttribute, 0)
	car:SetAttribute(Config.carSpeedAttribute, 0)
	car:SetAttribute("Cab87LastResetReason", "")
	car:SetAttribute("Cab87LastResetY", position.Y)
	car:SetAttribute("Cab87GroundContacts", 0)
	car:SetAttribute("Cab87Grounded", grounded)
	car:SetAttribute("Cab87HasDriver", false)

	local function triggerBoostFeedback(player)
		if Config.carBoostWheelieDuration > 0 and Config.carBoostWheelieDegrees > 0 then
			boostVisualPulse += 1
			car:SetAttribute(Config.carVisualBoostPulseAttribute, boostVisualPulse)
		end

		if player and cameraEventRemote and Config.cameraBoostShakeIntensity > 0 then
			cameraEventRemote:FireClient(player, "Shake", Config.cameraBoostShakeIntensity)
		end
	end

	local function triggerCrashFeedback(player, impactSpeed)
		if not player or not cameraEventRemote or crashShakeCooldown > 0 then
			return
		end

		local minShakeSpeed = Config.cameraCrashShakeMinSpeed
		local maxShakeSpeed = math.max(Config.cameraCrashShakeMaxSpeed, minShakeSpeed + 0.001)
		local intensity = math.clamp((impactSpeed - minShakeSpeed) / (maxShakeSpeed - minShakeSpeed), 0, 1)

		if intensity > 0 then
			cameraEventRemote:FireClient(player, "Crash", math.max(intensity, 0.22))
			crashShakeCooldown = math.max(Config.cameraCrashShakeCooldown, 0)
		end
	end

	local function hideCharacterVisualInstance(instance, state)
		if state.instances[instance] then
			return
		end

		if instance:IsA("BasePart") or instance:IsA("Decal") or instance:IsA("Texture") then
			state.instances[instance] = {
				transparency = instance.Transparency,
			}
			instance.Transparency = 1
		elseif instance:IsA("ParticleEmitter")
			or instance:IsA("Trail")
			or instance:IsA("Beam")
			or instance:IsA("BillboardGui")
			or instance:IsA("SurfaceGui")
		then
			state.instances[instance] = {
				enabled = instance.Enabled,
			}
			instance.Enabled = false
		end
	end

	local function restoreHiddenCharacter()
		if not hiddenCharacterState then
			return
		end

		if hiddenCharacterState.descendantAddedConnection then
			hiddenCharacterState.descendantAddedConnection:Disconnect()
		end

		for instance, originalState in pairs(hiddenCharacterState.instances) do
			if instance.Parent then
				if originalState.transparency ~= nil then
					instance.Transparency = originalState.transparency
				end

				if originalState.enabled ~= nil then
					instance.Enabled = originalState.enabled
				end
			end
		end

		local humanoid = hiddenCharacterState.humanoid
		if humanoid and humanoid.Parent then
			humanoid.DisplayDistanceType = hiddenCharacterState.displayDistanceType
			humanoid.HealthDisplayType = hiddenCharacterState.healthDisplayType
		end

		hiddenCharacterState = nil
	end

	local function hideDriverCharacter(humanoid)
		restoreHiddenCharacter()

		local character = humanoid and humanoid.Parent
		if not character then
			return
		end

		local state = {
			humanoid = humanoid,
			displayDistanceType = humanoid.DisplayDistanceType,
			healthDisplayType = humanoid.HealthDisplayType,
			instances = {},
			descendantAddedConnection = nil,
		}
		hiddenCharacterState = state

		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

		for _, descendant in ipairs(character:GetDescendants()) do
			hideCharacterVisualInstance(descendant, state)
		end

		state.descendantAddedConnection = character.DescendantAdded:Connect(function(descendant)
			hideCharacterVisualInstance(descendant, state)
		end)
	end

	driveInputRemote.OnServerEvent:Connect(function(player, action, throttle, steer, drift, airPitch)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= seat.Occupant then
			return
		end

		if action == "Drive" then
			if type(throttle) ~= "number" or type(steer) ~= "number" or type(drift) ~= "boolean" then
				return
			end

			if type(airPitch) ~= "number" then
				airPitch = 0
			end

			driverInput[player] = {
				throttle = math.clamp(throttle, -1, 1),
				steer = math.clamp(steer, -1, 1),
				drift = drift,
				airPitch = math.clamp(airPitch, -1, 1),
			}
		elseif action == "Drift" and type(throttle) == "boolean" then
			local input = driverInput[player] or {
				throttle = 0,
				steer = 0,
				drift = false,
				airPitch = 0,
			}
			input.drift = throttle
			driverInput[player] = input
		end
	end)

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant then
			hideDriverCharacter(occupant)
		else
			driverInput = {}
			restoreHiddenCharacter()
		end
	end)

	local function dampToZero(value, amount)
		if math.abs(value) <= amount then
			return 0
		end
		return value - math.sign(value) * amount
	end

	local function dampVectorMagnitude(vector, amount)
		local magnitude = vector.Magnitude
		if magnitude <= amount then
			return Vector3.zero
		end

		return vector.Unit * (magnitude - amount)
	end

	local function limitHorizontalSpeed(vector, maxSpeed)
		local horizontal = Vector3.new(vector.X, 0, vector.Z)
		local speed = horizontal.Magnitude
		if speed <= maxSpeed then
			return vector
		end

		local limited = horizontal.Unit * maxSpeed
		return Vector3.new(limited.X, vector.Y, limited.Z)
	end

	local function getHorizontalUnit(vector)
		local horizontal = Vector3.new(vector.X, 0, vector.Z)
		if horizontal.Magnitude <= 0.001 then
			return nil
		end

		return horizontal.Unit
	end

	local function getSurfaceSample(samplePosition)
		local origin = samplePosition + Vector3.new(0, Config.carGroundProbeHeight, 0)
		local result = Workspace:Raycast(
			origin,
			Vector3.new(0, -Config.carGroundProbeDepth, 0),
			raycastParams
		)

		if result then
			return {
				surfaceY = result.Position.Y,
				height = result.Position.Y + Config.carRideHeight,
				instance = result.Instance,
				normal = result.Normal,
			}
		end

		return nil
	end

	local function getGroundAnglesFromNormal(normal, currentYaw)
		local normalY = math.max(normal.Y, 0.001)
		local forward = yawToForward(currentYaw)
		local right = yawToRight(currentYaw)
		local maxPitch = math.rad(Config.carMaxPitchDegrees)
		local maxRoll = math.rad(Config.carGroundMaxRollDegrees)

		return math.clamp(math.atan2(normal:Dot(forward), normalY), -maxPitch, maxPitch),
			math.clamp(math.atan2(-normal:Dot(right), normalY), -maxRoll, maxRoll)
	end

	local function getGroundTargetYForPose(groundProfile, targetPitch, targetRoll)
		if not groundProfile then
			return nil
		end

		local samples = groundProfile.samples
		if not samples or #samples == 0 then
			return nil
		end

		local rotation = CFrame.Angles(targetPitch, 0, targetRoll)
		local targetY = -math.huge

		for _, sample in ipairs(samples) do
			local contactOffset = rotation:VectorToWorldSpace(Vector3.new(
				sample.localX,
				-Config.carRideHeight,
				sample.localZ
			))
			targetY = math.max(targetY, sample.surfaceY - contactOffset.Y)
		end

		return targetY
	end

	local function getGroundTargetYWithCurrentPose(groundProfile, targetPitch, targetRoll)
		local targetY = getGroundTargetYForPose(groundProfile, targetPitch, targetRoll)
		local currentPoseY = getGroundTargetYForPose(groundProfile, visualPitch, visualRoll)

		if targetY and currentPoseY then
			return math.max(targetY, currentPoseY)
		end

		return targetY or currentPoseY
	end

	local function getGroundProfile(currentPosition, currentYaw)
		local forward = yawToForward(currentYaw)
		local right = yawToRight(currentYaw)
		local halfWidth = Config.carGroundProbeHalfWidth
		local halfLength = Config.carGroundProbeHalfLength
		local totalHeight = 0
		local contactCount = 0
		local frontTotal = 0
		local frontCount = 0
		local rearTotal = 0
		local rearCount = 0
		local leftTotal = 0
		local leftCount = 0
		local rightTotal = 0
		local rightCount = 0
		local highestSample = nil
		local normalTotal = Vector3.zero
		local normalCount = 0
		local samples = {}

		local function addSample(localX, localZ)
			local samplePosition = currentPosition + right * localX + forward * localZ
			local sample = getSurfaceSample(Vector3.new(samplePosition.X, currentPosition.Y, samplePosition.Z))
			if not sample then
				return
			end

			table.insert(samples, {
				localX = localX,
				localZ = localZ,
				surfaceY = sample.surfaceY,
				height = sample.height,
				instance = sample.instance,
				normal = sample.normal,
			})

			local sampleHeight = sample.height
			totalHeight += sampleHeight
			contactCount += 1
			if not highestSample or sampleHeight > highestSample.height then
				highestSample = sample
			end

			if sample.normal.Y > 0.1 then
				normalTotal += sample.normal
				normalCount += 1
			end

			if localZ >= 0 then
				frontTotal += sampleHeight
				frontCount += 1
			else
				rearTotal += sampleHeight
				rearCount += 1
			end

			if localX >= 0 then
				rightTotal += sampleHeight
				rightCount += 1
			else
				leftTotal += sampleHeight
				leftCount += 1
			end
		end

		addSample(halfWidth, halfLength)
		addSample(-halfWidth, halfLength)
		addSample(halfWidth, -halfLength)
		addSample(-halfWidth, -halfLength)

		if contactCount == 0 then
			return nil
		end

		local normalPitch = 0
		local normalRoll = 0
		if normalCount > 0 and normalTotal.Magnitude > 0.001 then
			normalPitch, normalRoll = getGroundAnglesFromNormal(normalTotal.Unit, currentYaw)
		end

		local targetPitch = 0
		if frontCount > 0 and rearCount > 0 and halfLength > 0 then
			local frontAverage = frontTotal / frontCount
			local rearAverage = rearTotal / rearCount
			local maxPitch = math.rad(Config.carMaxPitchDegrees)
			targetPitch = math.clamp(
				-math.atan2(frontAverage - rearAverage, halfLength * 2),
				-maxPitch,
				maxPitch
			)
		else
			targetPitch = normalPitch
		end

		local targetRoll = 0
		if rightCount > 0 and leftCount > 0 and halfWidth > 0 then
			local rightAverage = rightTotal / rightCount
			local leftAverage = leftTotal / leftCount
			local maxRoll = math.rad(Config.carGroundMaxRollDegrees)
			targetRoll = math.clamp(
				math.atan2(rightAverage - leftAverage, halfWidth * 2),
				-maxRoll,
				maxRoll
			)
		else
			targetRoll = normalRoll
		end

		local profile = {
			targetPitch = targetPitch,
			targetRoll = targetRoll,
			contacts = contactCount,
			highestSample = highestSample,
			samples = samples,
			stepY = totalHeight / contactCount,
		}
		profile.targetY = getGroundTargetYForPose(profile, targetPitch, targetRoll)
			or profile.stepY

		return profile
	end

	local function getFallbackSurfaceTarget(currentPosition, currentYaw)
		local groundProfile = getGroundProfile(currentPosition, currentYaw)
		if groundProfile then
			return groundProfile.targetY
		end

		return Config.roadSurfaceY + Config.carRideHeight
	end

	local function getWallScrapeVelocity(tangentVelocity, normal, speed)
		local tangentSpeed = tangentVelocity.Magnitude
		if tangentSpeed <= 0.001 then
			return Vector3.zero, nil
		end

		local deflectAngle = math.rad(Config.carWallScrapeDeflectAngleDegrees)
		local tangentDirection = tangentVelocity.Unit
		local scrapeDirection = tangentDirection * math.cos(deflectAngle) + normal * math.sin(deflectAngle)
		if scrapeDirection.Magnitude <= 0.001 then
			scrapeDirection = tangentDirection
		else
			scrapeDirection = scrapeDirection.Unit
		end

		local deflectedSpeed = tangentSpeed
		if deflectAngle > 0 then
			deflectedSpeed = math.min(speed, tangentSpeed / math.max(math.cos(deflectAngle), 0.001))
		end

		return scrapeDirection * deflectedSpeed * Config.carWallScrapeSpeedRetain, scrapeDirection
	end

	local function getGroundStepCollisionNormal(groundProfile, currentVelocity, currentYaw)
		local velocityDirection = getHorizontalUnit(currentVelocity)
		local sample = groundProfile and groundProfile.highestSample
		local instance = sample and sample.instance

		if instance and instance.Name == "JumpRamp" then
			local rampForward = getHorizontalUnit(instance.CFrame.LookVector)
			if rampForward and velocityDirection then
				local approachDot = velocityDirection:Dot(rampForward)
				if math.abs(approachDot) > 0.35 then
					return if approachDot < 0 then rampForward else -rampForward
				end
			end
		end

		return velocityDirection and -velocityDirection or -yawToForward(currentYaw)
	end

	local function getGroundStepCrashVelocity(currentVelocity, normal)
		local intoWall = currentVelocity:Dot(normal)
		if intoWall >= 0 then
			return currentVelocity
		end

		local tangentVelocity = currentVelocity - normal * intoWall
		return tangentVelocity * Config.carCrashSlideRetain
			+ normal * (-intoWall * Config.carCrashBounce)
	end

	local function resolveBuildingCollision(previousPosition, proposedPosition, currentVelocity)
		local resolved = proposedPosition
		local resolvedVelocity = currentVelocity
		local hardCrashed = false
		local scrapeDirection = nil

		for _, obstacle in ipairs(crashObstacles) do
			local obstacleTop = obstacle.Position.Y + obstacle.Size.Y * 0.5
			if resolved.Y < obstacleTop + Config.carCrashHeightClearance then
				local halfX = obstacle.Size.X * 0.5 + Config.carCrashRadius
				local halfZ = obstacle.Size.Z * 0.5 + Config.carCrashRadius
				local deltaX = resolved.X - obstacle.Position.X
				local deltaZ = resolved.Z - obstacle.Position.Z

				if math.abs(deltaX) < halfX and math.abs(deltaZ) < halfZ then
					local pushX = halfX - math.abs(deltaX)
					local pushZ = halfZ - math.abs(deltaZ)
					local normal

					if pushX < pushZ then
						local side = if deltaX >= 0 then 1 else -1
						normal = Vector3.new(side, 0, 0)
						resolved = Vector3.new(obstacle.Position.X + side * halfX, resolved.Y, resolved.Z)
					else
						local side = if deltaZ >= 0 then 1 else -1
						normal = Vector3.new(0, 0, side)
						resolved = Vector3.new(resolved.X, resolved.Y, obstacle.Position.Z + side * halfZ)
					end

					local intoWall = resolvedVelocity:Dot(normal)
					local tangentVelocity = resolvedVelocity - normal * intoWall
					local tangentSpeed = tangentVelocity.Magnitude
					local speed = resolvedVelocity.Magnitude
					local maxScrapeImpact = speed * math.sin(math.rad(Config.carWallScrapeMaxAngleDegrees))

					if intoWall < 0 then
						local normalImpact = -intoWall
						local canScrape = speed >= Config.carWallScrapeMinSpeed
							and tangentSpeed > 0.001
							and normalImpact <= maxScrapeImpact

						if canScrape then
							resolvedVelocity, scrapeDirection = getWallScrapeVelocity(tangentVelocity, normal, speed)
						else
							hardCrashed = true
							resolvedVelocity = tangentVelocity * Config.carCrashSlideRetain
								+ normal * (normalImpact * Config.carCrashBounce)
						end
					else
						if tangentSpeed > Config.carWallScrapeMinSpeed then
							_, scrapeDirection = getWallScrapeVelocity(tangentVelocity, normal, speed)
						end
					end
				end
			end
		end

		if hardCrashed or scrapeDirection then
			resolved = Vector3.new(resolved.X, math.max(resolved.Y, previousPosition.Y), resolved.Z)
		end

		return resolved, resolvedVelocity, hardCrashed, scrapeDirection
	end

	local function setDriftSmokeState(nextState)
		if smokeState == nextState then
			return
		end

		smokeState = nextState
		for _, emitter in ipairs(driftEmitters) do
			emitter.Enabled = nextState ~= "off"
			if nextState == "boost" then
				emitter.Color = BOOST_DRIFT_SMOKE_COLOR
				emitter.Rate = 145
			else
				emitter.Color = NORMAL_DRIFT_SMOKE_COLOR
				emitter.Rate = 95
			end
		end
	end

	local function triggerLandingBounce(landingSpeed)
		local maxOffset = math.max(Config.carLandingBounceMaxOffset, 0)
		local impulse = math.max(Config.carLandingBounceImpulse, 0)
		if maxOffset <= 0 or impulse <= 0 then
			return
		end

		local minSpeed = math.max(Config.carLandingBounceMinSpeed, 0)
		local maxSpeed = math.max(Config.carLandingBounceMaxSpeed, minSpeed + 0.001)
		local bounceAlpha = math.clamp((landingSpeed - minSpeed) / (maxSpeed - minSpeed), 0, 1)
		if bounceAlpha <= 0 then
			return
		end

		landingVisualPulse += 1
		car:SetAttribute(Config.carVisualLandingSpeedAttribute, landingSpeed)
		car:SetAttribute(Config.carVisualLandingPulseAttribute, landingVisualPulse)
	end

	local function trimSafeGroundHistory()
		local historyWindow = math.max(Config.carFallResetLookbackTime + 2, 3)
		local oldestAllowedTime = elapsedTime - historyWindow
		while #safeGroundHistory > 0 and safeGroundHistory[1].time < oldestAllowedTime do
			table.remove(safeGroundHistory, 1)
		end
	end

	local function recordSafeGroundPose(groundProfile)
		if not groundProfile or groundProfile.contacts < Config.carFallResetMinGroundContacts then
			return
		end

		table.insert(safeGroundHistory, {
			time = elapsedTime,
			position = position,
			yaw = yaw,
		})
		trimSafeGroundHistory()
	end

	local function getFallbackResetPose()
		local resetPosition = defaultSpawnPose.position
		local resetYaw = defaultSpawnPose.yaw
		return {
			position = Vector3.new(resetPosition.X, getFallbackSurfaceTarget(resetPosition, resetYaw), resetPosition.Z),
			yaw = resetYaw,
		}
	end

	local function getSafeFallResetPose()
		local targetTime = elapsedTime - Config.carFallResetLookbackTime
		local selectedPose = nil

		for index = #safeGroundHistory, 1, -1 do
			local pose = safeGroundHistory[index]
			if pose.time <= targetTime then
				selectedPose = pose
				break
			end
		end

		return selectedPose or safeGroundHistory[1] or safeGroundHistory[#safeGroundHistory] or getFallbackResetPose()
	end

	local function resetCabAfterFall()
		local resetPose = pendingFallResetPose or getSafeFallResetPose()
		local resetYaw = resetPose.yaw + math.rad(Config.carFallResetTurnaroundDegrees)
		local resetPosition = resetPose.position
		local resetY = getFallbackSurfaceTarget(resetPosition, resetYaw)

		position = Vector3.new(resetPosition.X, resetY, resetPosition.Z)
		yaw = resetYaw
		velocity = Vector3.zero
		verticalVelocity = 0
		grounded = true
		visualPitch = 0
		visualRoll = 0
		visualDriveRoll = 0
		visualDriftRoll = 0
		airPitchVelocity = 0
		airRollVelocity = 0
		reverseHoldTime = 0
		driftChargeTime = 0
		driftBoostReady = false
		driftInputWasHeld = false
		boostTimer = 0
		pendingFallResetPose = nil
		fallResetCooldown = math.max(Config.carFallResetCooldown, 0)
		safeGroundHistory = {
			{
				time = elapsedTime,
				position = position,
				yaw = yaw,
			},
		}
		setDriftSmokeState("off")
		car:SetAttribute("Cab87LastResetReason", "Fall")
		car:SetAttribute("Cab87LastResetY", position.Y)
	end

	RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, Config.carMaxDeltaTime)
		elapsedTime += dt
		fallResetCooldown = math.max(fallResetCooldown - dt, 0)
		crashShakeCooldown = math.max(crashShakeCooldown - dt, 0)

		local forward = yawToForward(yaw)
		local right = yawToRight(yaw)
		local forwardSpeed = velocity:Dot(forward)
		local lateralSpeed = velocity:Dot(right)

		local driverCharacter = seat.Occupant and seat.Occupant.Parent
		local driver = driverCharacter and Players:GetPlayerFromCharacter(driverCharacter)
		local input = driver and driverInput[driver]
		local throttle = input and input.throttle or seat.ThrottleFloat
		local steer = input and input.steer or seat.SteerFloat
		local airPitchInput = input and input.airPitch or 0

		if seat.Occupant ~= lastOccupant then
			lastOccupant = seat.Occupant
			car:SetAttribute("Cab87HasDriver", seat.Occupant ~= nil)
			grounded = true
			verticalVelocity = 0
			visualPitch = 0
			visualRoll = 0
			visualDriveRoll = 0
			visualDriftRoll = 0
			airPitchVelocity = 0
			airRollVelocity = 0
			reverseHoldTime = 0
			driftChargeTime = 0
			driftBoostReady = false
			driftInputWasHeld = false
			boostTimer = 0
			fallResetCooldown = 0
			pendingFallResetPose = nil
			safeGroundHistory = {}

			if seat.Occupant then
				velocity = Vector3.zero
				position = Vector3.new(position.X, getFallbackSurfaceTarget(position, yaw), position.Z)
				table.insert(safeGroundHistory, {
					time = elapsedTime,
					position = position,
					yaw = yaw,
				})
			end
		end

		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local canDrive = grounded
		local driftHeld = canDrive and driver ~= nil and input ~= nil and input.drift == true
		local releasedDrift = canDrive and driftInputWasHeld and not driftHeld
		local boostTriggered = false

		if releasedDrift and driftBoostReady then
			boostTimer = math.max(boostTimer, Config.carDriftBoostDuration)
			boostTriggered = true
			triggerBoostFeedback(driver)
		end

		if not driftHeld then
			driftChargeTime = 0
			driftBoostReady = false
		end

		local drifting = canDrive and driftHeld
			and horizontalSpeed > Config.carDriftMinSpeed

		if canDrive then
			local accel = drifting and Config.carAccel * Config.carDriftAccelMultiplier or Config.carAccel
			local waitingToReverse = false
			local boostMaxSpeed = math.max(Config.carMaxForward, Config.carDriftBoostMaxSpeed)

			if drifting then
				driftChargeTime += dt
				local withinBoostWindow = Config.carDriftBoostWindow <= 0
					or driftChargeTime <= Config.carDriftBoostChargeTime + Config.carDriftBoostWindow
				driftBoostReady = driftChargeTime >= Config.carDriftBoostChargeTime
					and withinBoostWindow
			elseif driftHeld then
				driftChargeTime = 0
				driftBoostReady = false
			end

			if throttle > 0 then
				reverseHoldTime = 0
				forwardSpeed = math.min(forwardSpeed + accel * throttle * dt, boostTimer > 0 and boostMaxSpeed or Config.carMaxForward)
			elseif throttle < 0 then
				if forwardSpeed > Config.carReverseStopSpeed then
					reverseHoldTime = 0
					forwardSpeed = math.max(forwardSpeed + Config.carBrake * throttle * dt, 0)
				else
					reverseHoldTime += dt

					if forwardSpeed > -Config.carReverseStopSpeed
						and reverseHoldTime < Config.carReverseDelay
					then
						waitingToReverse = true
						forwardSpeed = 0
						lateralSpeed = dampToZero(lateralSpeed, Config.carBrake * dt)
					else
						forwardSpeed = math.max(forwardSpeed + accel * throttle * dt, -Config.carMaxReverse)
					end
				end
			else
				reverseHoldTime = 0
				forwardSpeed = dampToZero(forwardSpeed, Config.carDrag * dt)
			end

			if drifting then
				forwardSpeed = dampToZero(forwardSpeed, Config.carDriftDrag * dt)
				lateralSpeed += steer * Config.carDriftSlideForce * dt
			end

			if boostTriggered then
				forwardSpeed = math.min(math.max(forwardSpeed, 0) + Config.carDriftBoostImpulse, boostMaxSpeed)
			end

			if boostTimer > 0 then
				forwardSpeed = math.min(forwardSpeed + Config.carDriftBoostAccel * dt, boostMaxSpeed)
				boostTimer = math.max(boostTimer - dt, 0)
			end

			local grip = drifting and Config.carDriftGrip or Config.carGrip
			lateralSpeed *= math.exp(-grip * dt)
			local preTurnVelocity = forward * forwardSpeed + right * lateralSpeed
			if drifting then
				preTurnVelocity = dampVectorMagnitude(preTurnVelocity, Config.carDriftDecel * dt)
			end

			local turnSpeed = if drifting then horizontalSpeed else math.abs(forwardSpeed)
			if turnSpeed > Config.carMinTurnSpeed and math.abs(steer) > 0.01 then
				local maxTurnSpeed = math.max(Config.carMaxForward, Config.carMinTurnSpeed + 0.001)
				local turnSpeedAlpha = math.clamp(
					(turnSpeed - Config.carMinTurnSpeed) / (maxTurnSpeed - Config.carMinTurnSpeed),
					0,
					1
				)
				local turnScale = Config.carTurnSpeedAtMinSpeed
					+ (Config.carTurnSpeedAtMaxSpeed - Config.carTurnSpeedAtMinSpeed) * turnSpeedAlpha
				local driftRotationSensitivity = drifting and Config.carDriftRotationSensitivity or 1
				yaw -= steer * Config.carTurnRate * turnScale * driftRotationSensitivity * dt
			end

			forward = yawToForward(yaw)
			right = yawToRight(yaw)

			if waitingToReverse or drifting then
				velocity = preTurnVelocity
			else
				local speed = preTurnVelocity.Magnitude
				local directionSign = if forwardSpeed < -1 then -1 else 1
				local targetVelocity = forward * speed * directionSign
				local gripBlend = 1 - math.exp(-Config.carGrip * dt)
				velocity = preTurnVelocity:Lerp(targetVelocity, gripBlend)
			end

			if boostTimer > 0 or boostTriggered then
				velocity = limitHorizontalSpeed(velocity, boostMaxSpeed)
			end
		else
			reverseHoldTime = 0
			boostTimer = math.max(boostTimer - dt, 0)
		end

		horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local previousPosition = position
		position += Vector3.new(velocity.X, 0, velocity.Z) * dt
		local impactSpeed = horizontalSpeed
		local crashed
		local wallScrapeDirection
		position, velocity, crashed, wallScrapeDirection = resolveBuildingCollision(previousPosition, position, velocity)

		if wallScrapeDirection then
			local targetYaw = vectorToYaw(wallScrapeDirection)
			if math.cos(getAngleDelta(yaw, targetYaw)) < 0 then
				targetYaw += math.pi
			end
			yaw = moveAngleToward(yaw, targetYaw, Config.carWallScrapeYawRate * dt)
		end

		if crashed then
			triggerCrashFeedback(driver, impactSpeed)
		end

		local previousY = position.Y
		local groundProfile = getGroundProfile(position, yaw)
		car:SetAttribute("Cab87GroundContacts", groundProfile and groundProfile.contacts or 0)
		car:SetAttribute("Cab87Grounded", grounded)
		local targetPitch = groundProfile and groundProfile.targetPitch or 0
		local targetRoll = groundProfile and groundProfile.targetRoll or 0
		local targetY = groundProfile and getGroundTargetYWithCurrentPose(groundProfile, targetPitch, targetRoll)
			or previousY
		local stepY = groundProfile and groundProfile.stepY or targetY

		if grounded then
			local stepUp = stepY - previousY
			if not groundProfile or previousY - targetY > Config.carGroundSnapDistance then
				pendingFallResetPose = getSafeFallResetPose()
				grounded = false
				verticalVelocity = math.max(verticalVelocity, 8)
				targetPitch = visualPitch
				targetRoll = visualRoll
			elseif stepUp > Config.carGroundMaxStepUp then
				local normal = getGroundStepCollisionNormal(groundProfile, velocity, yaw)
				position = previousPosition
				velocity = getGroundStepCrashVelocity(velocity, normal)
				verticalVelocity = 0
				boostTimer = 0
				targetPitch = visualPitch
				targetRoll = visualRoll
				triggerCrashFeedback(driver, impactSpeed)
			else
				position = Vector3.new(position.X, targetY, position.Z)
				local riseVelocity = (position.Y - previousY) / dt
				verticalVelocity = math.max(riseVelocity, 0)
				airPitchVelocity = 0
				airRollVelocity = 0
				pendingFallResetPose = nil
				recordSafeGroundPose(groundProfile)
			end
		else
			local gravity = if verticalVelocity > 0 then Config.carGravityUp else Config.carGravityDown
			local maxPitch = math.rad(Config.carMaxPitchDegrees)
			local pitchGravityAlpha = if maxPitch > 0
				then math.clamp(visualPitch / maxPitch, -1, 1)
				else 0
			if pitchGravityAlpha < 0 then
				gravity *= 1 + (Config.carAirPitchUpGravityMultiplier - 1) * -pitchGravityAlpha
			elseif pitchGravityAlpha > 0 then
				gravity *= 1 + (Config.carAirPitchDownGravityMultiplier - 1) * pitchGravityAlpha
			end

			verticalVelocity -= gravity * dt
			position = Vector3.new(position.X, position.Y + verticalVelocity * dt, position.Z)

			if groundProfile and position.Y <= targetY and verticalVelocity <= 0 then
				local landingSpeed = -verticalVelocity
				position = Vector3.new(position.X, targetY, position.Z)
				verticalVelocity = 0
				grounded = true
				triggerLandingBounce(landingSpeed)
				airPitchVelocity = 0
				airRollVelocity = 0
				pendingFallResetPose = nil
				recordSafeGroundPose(groundProfile)

				local maxBoostAlignment = math.rad(Config.carLandingBoostAlignDegrees)
				local pitchError = math.abs(visualPitch - targetPitch)
				local rollError = math.abs((visualRoll + visualDriveRoll + visualDriftRoll) - targetRoll)
				if Config.carLandingBoostImpulse > 0
					and pitchError <= maxBoostAlignment
					and rollError <= maxBoostAlignment
				then
					local landingBoostMaxSpeed = math.max(Config.carMaxForward, Config.carLandingBoostMaxSpeed)
					velocity = limitHorizontalSpeed(
						velocity + forward * Config.carLandingBoostImpulse,
						landingBoostMaxSpeed
					)
					triggerBoostFeedback(driver)
				end

				if driver and cameraEventRemote and crashShakeCooldown <= 0 then
					local minLandingSpeed = Config.cameraLandingShakeMinSpeed
					local maxLandingSpeed = math.max(Config.cameraLandingShakeMaxSpeed, minLandingSpeed + 0.001)
					local intensity = math.clamp(
						(landingSpeed - minLandingSpeed) / (maxLandingSpeed - minLandingSpeed),
						0,
						1
					)

					if intensity > 0 then
						cameraEventRemote:FireClient(driver, "Land", math.max(intensity, 0.18))
						crashShakeCooldown = math.max(Config.cameraCrashShakeCooldown, 0)
					end
				end
			else
				local maxRoll = math.rad(Config.carGroundMaxRollDegrees)
				local airResponse = math.clamp(Config.carAirRotationFollow * dt, 0, 1)
				local targetPitchVelocity = airPitchInput * math.rad(Config.carAirPitchInputDegrees)
				local targetRollVelocity = steer * math.rad(Config.carAirRollInputDegrees)
				if math.abs(airPitchInput) > 0.01 then
					airPitchVelocity += (targetPitchVelocity - airPitchVelocity) * airResponse
				else
					airPitchVelocity = 0
				end
				if math.abs(steer) > 0.01 then
					airRollVelocity += (targetRollVelocity - airRollVelocity) * airResponse
				else
					airRollVelocity = 0
				end
				targetPitch = math.clamp(visualPitch + airPitchVelocity * dt, -maxPitch, maxPitch)
				targetRoll = math.clamp(visualRoll + airRollVelocity * dt, -maxRoll, maxRoll)
			end
		end

		if fallResetCooldown <= 0 and position.Y < Config.carFallResetY then
			resetCabAfterFall()
			horizontalSpeed = 0
			driftHeld = false
			drifting = false
			targetPitch = 0
			targetRoll = 0
		end

		if grounded then
			visualPitch += (targetPitch - visualPitch) * math.clamp(Config.carPitchFollow * dt, 0, 1)
			visualRoll += (targetRoll - visualRoll) * math.clamp(Config.carRollFollow * dt, 0, 1)
		else
			visualPitch = targetPitch
			visualRoll = targetRoll
		end

		local targetDriveRoll = 0
		if grounded and canDrive and not drifting and math.abs(steer) > 0.01 then
			local fullLeanSpeed = math.max(Config.carDriveLeanFullSpeed, Config.carDriveLeanMinSpeed + 0.001)
			local leanSpeedAlpha = math.clamp(
				(horizontalSpeed - Config.carDriveLeanMinSpeed) / (fullLeanSpeed - Config.carDriveLeanMinSpeed),
				0,
				1
			)
			targetDriveRoll = steer * math.rad(Config.carDriveLeanDegrees) * leanSpeedAlpha
		end
		if grounded then
			visualDriveRoll += (targetDriveRoll - visualDriveRoll) * math.clamp(Config.carDriveLeanFollow * dt, 0, 1)
		else
			visualDriveRoll = 0
		end

		local targetDriftRoll = 0
		if grounded and drifting and math.abs(steer) > 0.01 then
			local fullLeanSpeed = math.max(Config.carDriftLeanFullSpeed, Config.carDriftMinSpeed + 0.001)
			local leanSpeedAlpha = math.clamp(
				(horizontalSpeed - Config.carDriftMinSpeed) / (fullLeanSpeed - Config.carDriftMinSpeed),
				0,
				1
			)
			targetDriftRoll = steer * math.rad(Config.carDriftLeanDegrees) * leanSpeedAlpha
		end
		if grounded then
			visualDriftRoll += (targetDriftRoll - visualDriftRoll) * math.clamp(Config.carDriftLeanFollow * dt, 0, 1)
		else
			visualDriftRoll = 0
		end

		if drifting then
			setDriftSmokeState(driftBoostReady and "boost" or "normal")
		else
			setDriftSmokeState("off")
		end
		car:SetAttribute(Config.carVisualDriftingAttribute, drifting)
		car:SetAttribute(Config.carVisualDriftBoostReadyAttribute, driftBoostReady)
		car:SetAttribute(Config.carSpeedAttribute, math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z))

		driftInputWasHeld = driftHeld

		local networkPivot = CFrame.new(position)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(visualPitch, 0, visualRoll)
		serverPivotValue.Value = networkPivot
		car:PivotTo(networkPivot)
	end)
end

local driveInputRemote = getOrCreateDriveInputRemote()
local cameraEventRemote = getOrCreateCameraEventRemote()
local debugTuneRemote = getOrCreateDebugTuneRemote()
runDebugTuning(debugTuneRemote)

local authoredRoadRoot = AuthoredRoadRuntime.getRoot()
local world
local driveSurfaces
local crashObstacles
local spawnPose

local function createGeneratedWorld()
	world = MapGenerator.Generate()
	driveSurfaces, crashObstacles = collectWorldParts(world)
	buildStuntFeatures(world, driveSurfaces)
	spawnPose = {
		position = Config.carSpawn,
		yaw = 0,
	}
end

local okHasAuthoredRoad, hasAuthoredRoad = pcall(function()
	return AuthoredRoadRuntime.hasRoadData(authoredRoadRoot)
end)
if not okHasAuthoredRoad then
	warn("[cab87] Authored road data check failed; using generated map: " .. tostring(hasAuthoredRoad))
	hasAuthoredRoad = false
end

if hasAuthoredRoad then
	local okWorld, authoredWorld, authoredDriveSurfaces, authoredCrashObstacles, authoredSpawnPose = pcall(function()
		return AuthoredRoadRuntime.createWorld(authoredRoadRoot)
	end)
	if okWorld and authoredWorld then
		world = authoredWorld
		driveSurfaces = authoredDriveSurfaces
		crashObstacles = authoredCrashObstacles
		spawnPose = authoredSpawnPose
	else
		warn("[cab87] Authored road world failed; using generated map so the taxi can spawn: " .. tostring(authoredWorld))
		createGeneratedWorld()
	end
else
	createGeneratedWorld()
end

local car, seat, driftEmitters = createCab(world, spawnPose)
runCarController(car, seat, driftEmitters, driveInputRemote, cameraEventRemote, driveSurfaces, crashObstacles, spawnPose)
