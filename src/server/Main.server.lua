local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
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
			if item.Name == "Ground" or item.Name == "Road_NS" or item.Name == "Road_EW" then
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

local function createCab(world)
	local car = Instance.new("Model")
	car.Name = "Cab87Taxi"
	car.Parent = world
	local driftEmitters = {}

	local body = makePart(car, {
		Name = "Body",
		Size = Vector3.new(10, 2, 16),
		Position = Config.carSpawn,
		Color = Color3.fromRGB(255, 206, 38),
		Material = Enum.Material.SmoothPlastic,
	})

	makePart(car, {
		Name = "Roof",
		Size = Vector3.new(8, 1.5, 8),
		Position = Config.carSpawn + Vector3.new(0, 2, -1),
		Color = Color3.fromRGB(255, 227, 120),
		Material = Enum.Material.SmoothPlastic,
	})

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Anchored = true
	seat.Size = Vector3.new(3.5, 1, 4)
	seat.CFrame = CFrame.new(Config.carSpawn + Vector3.new(0, 1.5, 1))
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
		Position = Config.carSpawn + Vector3.new(0, 3.4, -1),
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
			Position = Config.carSpawn + offset,
			Color = Color3.fromRGB(25, 25, 30),
			Material = Enum.Material.SmoothPlastic,
		})
		wheel.CFrame = wheel.CFrame * CFrame.Angles(0, 0, math.rad(90))

		if offset.Z < 0 then
			addDriftSmoke(wheel, driftEmitters)
		end
	end

	car.PrimaryPart = body
	car:PivotTo(CFrame.new(Config.carSpawn))

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

local function runCarController(car, seat, driftEmitters, driveInputRemote, cameraEventRemote, driveSurfaces, crashObstacles)
	local position = Config.carSpawn
	local yaw = 0
	local velocity = Vector3.zero
	local verticalVelocity = 0
	local grounded = true
	local visualPitch = 0
	local visualRoll = 0
	local visualDriftRoll = 0
	local visualBoostPitch = 0
	local airPitchVelocity = 0
	local airRollVelocity = 0
	local reverseHoldTime = 0
	local driftChargeTime = 0
	local driftBoostReady = false
	local driftInputWasHeld = false
	local boostTimer = 0
	local boostWheelieTimer = 0
	local driverInput = {}
	local smokeState = "off"
	local lastOccupant = nil
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

	local function triggerBoostFeedback(player)
		if Config.carBoostWheelieDuration > 0 and Config.carBoostWheelieDegrees > 0 then
			boostWheelieTimer = math.max(boostWheelieTimer, Config.carBoostWheelieDuration)
		end

		if player and cameraEventRemote and Config.cameraBoostShakeIntensity > 0 then
			cameraEventRemote:FireClient(player, "Shake", Config.cameraBoostShakeIntensity)
		end
	end

	driveInputRemote.OnServerEvent:Connect(function(player, action, throttle, steer, drift)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= seat.Occupant then
			return
		end

		if action == "Drive" then
			if type(throttle) ~= "number" or type(steer) ~= "number" or type(drift) ~= "boolean" then
				return
			end

			driverInput[player] = {
				throttle = math.clamp(throttle, -1, 1),
				steer = math.clamp(steer, -1, 1),
				drift = drift,
			}
		elseif action == "Drift" and type(throttle) == "boolean" then
			local input = driverInput[player] or {
				throttle = 0,
				steer = 0,
				drift = false,
			}
			input.drift = throttle
			driverInput[player] = input
		end
	end)

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not seat.Occupant then
			driverInput = {}
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

	local function getSurfaceSample(samplePosition)
		local origin = samplePosition + Vector3.new(0, Config.carGroundProbeHeight, 0)
		local result = Workspace:Raycast(
			origin,
			Vector3.new(0, -Config.carGroundProbeDepth, 0),
			raycastParams
		)

		if result then
			return result.Position.Y + Config.carRideHeight
		end

		return nil
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

		local function addSample(localX, localZ)
			local samplePosition = currentPosition + right * localX + forward * localZ
			local sampleHeight = getSurfaceSample(Vector3.new(samplePosition.X, currentPosition.Y, samplePosition.Z))
			if not sampleHeight then
				return
			end

			totalHeight += sampleHeight
			contactCount += 1

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
		end

		return {
			targetY = totalHeight / contactCount,
			targetPitch = targetPitch,
			targetRoll = targetRoll,
			contacts = contactCount,
		}
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

	RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, Config.carMaxDeltaTime)
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

		if seat.Occupant ~= lastOccupant then
			lastOccupant = seat.Occupant
			grounded = true
			verticalVelocity = 0
			visualPitch = 0
			visualRoll = 0
			visualDriftRoll = 0
			visualBoostPitch = 0
			airPitchVelocity = 0
			airRollVelocity = 0
			reverseHoldTime = 0
			driftChargeTime = 0
			driftBoostReady = false
			driftInputWasHeld = false
			boostTimer = 0
			boostWheelieTimer = 0

			if seat.Occupant then
				velocity = Vector3.zero
				position = Vector3.new(position.X, getFallbackSurfaceTarget(position, yaw), position.Z)
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

		if crashed and driver and cameraEventRemote and crashShakeCooldown <= 0 then
			local minShakeSpeed = Config.cameraCrashShakeMinSpeed
			local maxShakeSpeed = math.max(Config.cameraCrashShakeMaxSpeed, minShakeSpeed + 0.001)
			local intensity = math.clamp((impactSpeed - minShakeSpeed) / (maxShakeSpeed - minShakeSpeed), 0, 1)

			if intensity > 0 then
				cameraEventRemote:FireClient(driver, "Crash", math.max(intensity, 0.22))
				crashShakeCooldown = math.max(Config.cameraCrashShakeCooldown, 0)
			end
		end

		local previousY = position.Y
		local groundProfile = getGroundProfile(position, yaw)
		local targetY = groundProfile and groundProfile.targetY or previousY
		local targetPitch = 0
		local targetRoll = 0

		if grounded then
			if not groundProfile or previousY - targetY > Config.carGroundSnapDistance then
				grounded = false
				verticalVelocity = math.max(verticalVelocity, 8)
				targetPitch = visualPitch
				targetRoll = visualRoll
			else
				position = Vector3.new(position.X, targetY, position.Z)
				local riseVelocity = (position.Y - previousY) / dt
				verticalVelocity = math.max(riseVelocity, 0)
				airPitchVelocity = 0
				airRollVelocity = 0
				targetPitch = groundProfile.targetPitch
				targetRoll = groundProfile.targetRoll
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
				airPitchVelocity = 0
				airRollVelocity = 0
				targetPitch = groundProfile.targetPitch
				targetRoll = groundProfile.targetRoll

				local maxBoostAlignment = math.rad(Config.carLandingBoostAlignDegrees)
				local pitchError = math.abs(visualPitch - targetPitch)
				local rollError = math.abs((visualRoll + visualDriftRoll) - targetRoll)
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
				local targetPitchVelocity = -throttle * math.rad(Config.carAirPitchInputDegrees)
				local targetRollVelocity = steer * math.rad(Config.carAirRollInputDegrees)
				airPitchVelocity += (targetPitchVelocity - airPitchVelocity) * airResponse
				airRollVelocity += (targetRollVelocity - airRollVelocity) * airResponse
				targetPitch = math.clamp(visualPitch + airPitchVelocity * dt, -maxPitch, maxPitch)
				targetRoll = math.clamp(visualRoll + airRollVelocity * dt, -maxRoll, maxRoll)
			end
		end

		if grounded then
			visualPitch += (targetPitch - visualPitch) * math.clamp(Config.carPitchFollow * dt, 0, 1)
			visualRoll += (targetRoll - visualRoll) * math.clamp(Config.carRollFollow * dt, 0, 1)
		else
			visualPitch = targetPitch
			visualRoll = targetRoll
		end
		local targetDriftRoll = 0
		if drifting and math.abs(steer) > 0.01 then
			local fullLeanSpeed = math.max(Config.carDriftLeanFullSpeed, Config.carDriftMinSpeed + 0.001)
			local leanSpeedAlpha = math.clamp(
				(horizontalSpeed - Config.carDriftMinSpeed) / (fullLeanSpeed - Config.carDriftMinSpeed),
				0,
				1
			)
			targetDriftRoll = steer * math.rad(Config.carDriftLeanDegrees) * leanSpeedAlpha
		end
		visualDriftRoll += (targetDriftRoll - visualDriftRoll) * math.clamp(Config.carDriftLeanFollow * dt, 0, 1)

		local targetBoostPitch = 0
		if boostWheelieTimer > 0 then
			local wheelieDuration = math.max(Config.carBoostWheelieDuration, 0.001)
			local wheelieAlpha = math.clamp(boostWheelieTimer / wheelieDuration, 0, 1)
			targetBoostPitch = -math.rad(Config.carBoostWheelieDegrees) * wheelieAlpha
			boostWheelieTimer = math.max(boostWheelieTimer - dt, 0)
		end
		visualBoostPitch += (targetBoostPitch - visualBoostPitch) * math.clamp(Config.carBoostWheelieFollow * dt, 0, 1)

		if drifting then
			setDriftSmokeState(driftBoostReady and "boost" or "normal")
		else
			setDriftSmokeState("off")
		end

		driftInputWasHeld = driftHeld

		local targetPivot = CFrame.new(position)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(visualPitch + visualBoostPitch, 0, visualRoll + visualDriftRoll)
		serverPivotValue.Value = targetPivot
		car:PivotTo(targetPivot)
	end)
end

local driveInputRemote = getOrCreateDriveInputRemote()
local cameraEventRemote = getOrCreateCameraEventRemote()
local debugTuneRemote = getOrCreateDebugTuneRemote()
runDebugTuning(debugTuneRemote)

local world = MapGenerator.Generate()
local driveSurfaces, crashObstacles = collectWorldParts(world)
buildStuntFeatures(world, driveSurfaces)
local car, seat, driftEmitters = createCab(world)
runCarController(car, seat, driftEmitters, driveInputRemote, cameraEventRemote, driveSurfaces, crashObstacles)
