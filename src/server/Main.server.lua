local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))

local function yawToForward(yaw)
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

local function yawToRight(yaw)
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
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
	emitter.Color = ColorSequence.new(Color3.fromRGB(210, 210, 210))
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

local function runCarController(car, seat, driftEmitters, driveInputRemote, driveSurfaces, crashObstacles)
	local position = Config.carSpawn
	local yaw = 0
	local velocity = Vector3.zero
	local verticalVelocity = 0
	local grounded = true
	local visualPitch = 0
	local driverInput = {}
	local smokeEnabled = false
	local lastOccupant = nil

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = driveSurfaces

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

	local function getSurfaceTarget(currentPosition)
		local origin = currentPosition + Vector3.new(0, Config.carGroundProbeHeight, 0)
		local result = Workspace:Raycast(
			origin,
			Vector3.new(0, -Config.carGroundProbeDepth, 0),
			raycastParams
		)

		if result then
			return result.Position.Y + Config.carRideHeight
		end

		return Config.roadSurfaceY + Config.carRideHeight
	end

	local function resolveBuildingCollision(previousPosition, proposedPosition, currentVelocity)
		local resolved = proposedPosition
		local resolvedVelocity = currentVelocity
		local crashed = false

		for _, obstacle in ipairs(crashObstacles) do
			local obstacleTop = obstacle.Position.Y + obstacle.Size.Y * 0.5
			if resolved.Y < obstacleTop + Config.carCrashHeightClearance then
				local halfX = obstacle.Size.X * 0.5 + Config.carCrashRadius
				local halfZ = obstacle.Size.Z * 0.5 + Config.carCrashRadius
				local deltaX = resolved.X - obstacle.Position.X
				local deltaZ = resolved.Z - obstacle.Position.Z

				if math.abs(deltaX) < halfX and math.abs(deltaZ) < halfZ then
					crashed = true

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
					if intoWall < 0 then
						local tangentVelocity = resolvedVelocity - normal * intoWall
						resolvedVelocity = tangentVelocity * Config.carCrashSlideRetain
							+ normal * (-intoWall * Config.carCrashBounce)
					else
						resolvedVelocity *= Config.carCrashSlideRetain
					end
				end
			end
		end

		if crashed then
			resolved = Vector3.new(resolved.X, math.max(resolved.Y, previousPosition.Y), resolved.Z)
		end

		return resolved, resolvedVelocity, crashed
	end

	local function setDriftSmokeEnabled(enabled)
		if smokeEnabled == enabled then
			return
		end

		smokeEnabled = enabled
		for _, emitter in ipairs(driftEmitters) do
			emitter.Enabled = enabled
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, Config.carMaxDeltaTime)

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

			if seat.Occupant then
				velocity = Vector3.zero
				position = Vector3.new(position.X, getSurfaceTarget(position), position.Z)
			end
		end

		if throttle > 0 then
			forwardSpeed = math.min(forwardSpeed + Config.carAccel * throttle * dt, Config.carMaxForward)
		elseif throttle < 0 then
			if forwardSpeed > 0 then
				forwardSpeed = math.max(forwardSpeed + Config.carBrake * throttle * dt, 0)
			else
				forwardSpeed = math.max(forwardSpeed + Config.carAccel * throttle * dt, -Config.carMaxReverse)
			end
		else
			forwardSpeed = dampToZero(forwardSpeed, Config.carDrag * dt)
		end

		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local drifting = driver ~= nil
			and input ~= nil
			and input.drift == true
			and horizontalSpeed > Config.carDriftMinSpeed

		if drifting then
			forwardSpeed = dampToZero(forwardSpeed, Config.carDriftDrag * dt)
			lateralSpeed += steer * Config.carDriftSlideForce * dt
		end

		local grip = drifting and Config.carDriftGrip or Config.carGrip
		lateralSpeed *= math.exp(-grip * dt)
		local preTurnVelocity = forward * forwardSpeed + right * lateralSpeed

		local turnSpeed = if drifting then horizontalSpeed else math.abs(forwardSpeed)
		if turnSpeed > Config.carMinTurnSpeed and math.abs(steer) > 0.01 then
			local turnScale = math.clamp(turnSpeed / Config.carMaxForward, 0.25, 1)
			local driftTurnMultiplier = drifting and Config.carDriftTurnMultiplier or 1
			yaw -= steer * Config.carTurnRate * turnScale * driftTurnMultiplier * dt
		end

		forward = yawToForward(yaw)
		right = yawToRight(yaw)

		if drifting then
			velocity = preTurnVelocity
		else
			local speed = preTurnVelocity.Magnitude
			local directionSign = if forwardSpeed < -1 then -1 else 1
			local targetVelocity = forward * speed * directionSign
			local gripBlend = 1 - math.exp(-Config.carGrip * dt)
			velocity = preTurnVelocity:Lerp(targetVelocity, gripBlend)
		end

		horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local previousPosition = position
		position += Vector3.new(velocity.X, 0, velocity.Z) * dt
		position, velocity = resolveBuildingCollision(previousPosition, position, velocity)

		local previousY = position.Y
		local targetY = getSurfaceTarget(position)
		local targetPitch = 0

		if grounded then
			if previousY - targetY > Config.carGroundSnapDistance then
				grounded = false
				verticalVelocity = math.max(verticalVelocity, 8)
			else
				position = Vector3.new(position.X, targetY, position.Z)
				local riseVelocity = (position.Y - previousY) / dt
				verticalVelocity = math.max(riseVelocity, 0)

				local speedForPitch = math.max(horizontalSpeed, 1)
				targetPitch = math.clamp(
					-math.atan2(riseVelocity, speedForPitch),
					-Config.carMaxPitch,
					Config.carMaxPitch
				)
			end
		else
			verticalVelocity -= Config.carGravity * dt
			position = Vector3.new(position.X, position.Y + verticalVelocity * dt, position.Z)

			if position.Y <= targetY and verticalVelocity <= 0 then
				position = Vector3.new(position.X, targetY, position.Z)
				verticalVelocity = 0
				grounded = true
			else
				targetPitch = math.clamp(
					-verticalVelocity / Config.carAirPitchScale,
					-Config.carMaxPitch,
					Config.carMaxPitch
				)
			end
		end

		visualPitch += (targetPitch - visualPitch) * math.clamp(Config.carPitchFollow * dt, 0, 1)
		setDriftSmokeEnabled(drifting)

		car:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(visualPitch, 0, 0))
	end)
end

local driveInputRemote = getOrCreateDriveInputRemote()
local world = MapGenerator.Generate()
local driveSurfaces, crashObstacles = collectWorldParts(world)
buildStuntFeatures(world, driveSurfaces)
local car, seat, driftEmitters = createCab(world)
runCarController(car, seat, driftEmitters, driveInputRemote, driveSurfaces, crashObstacles)
