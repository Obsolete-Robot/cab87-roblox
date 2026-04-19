local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local TAU = math.pi * 2
local UP = Vector3.new(0, 1, 0)

local activeCab = nil
local previousCameraType = nil
local previousCameraSubject = nil
local previousFieldOfView = nil
local smoothedCabPosition = nil
local cameraPosition = nil
local cameraFocus = nil
local cameraYaw = 0
local currentDistance = 0
local currentFov = 70
local smoothedSpeed = 0
local shakeTimeRemaining = 0
local shakeDuration = 0
local shakeIntensity = 0
local shakeSeed = 0

local function getNumberConfig(key, fallback)
	local value = Config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function getCurrentCamera()
	return Workspace.CurrentCamera
end

local function getHumanoid()
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function getDrivenCab()
	local humanoid = getHumanoid()
	local seat = humanoid and humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") or seat.Name ~= "DriverSeat" then
		return nil
	end

	local cab = seat.Parent
	if not cab or not cab:IsA("Model") or cab.Name ~= "Cab87Taxi" then
		return nil
	end

	return cab
end

local function yawToForward(yaw)
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

local function vectorToYaw(vector)
	return math.atan2(vector.X, vector.Z)
end

local function shortestAngle(fromYaw, toYaw)
	return (toYaw - fromYaw + math.pi) % TAU - math.pi
end

local function getCabForward(pivot)
	local forward = pivot:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local horizontal = Vector3.new(forward.X, 0, forward.Z)
	if horizontal.Magnitude <= 0.001 then
		return yawToForward(cameraYaw)
	end

	return horizontal.Unit
end

local function getAlpha(responsiveness, dt)
	if responsiveness <= 0 then
		return 0
	end

	return 1 - math.exp(-responsiveness * dt)
end

local function getSnapOrSmoothAlpha(responsiveness, dt)
	if responsiveness <= 0 then
		return 1
	end

	return getAlpha(responsiveness, dt)
end

local function getSpeedAlpha(speed)
	local minSpeed = getNumberConfig("cameraSpeedMin", 25)
	local maxSpeed = math.max(getNumberConfig("cameraSpeedMax", 170), minSpeed + 0.001)
	return math.clamp((speed - minSpeed) / (maxSpeed - minSpeed), 0, 1)
end

local function lerpNumber(fromValue, toValue, alpha)
	return fromValue + (toValue - fromValue) * alpha
end

local function triggerCrashShake(intensity)
	if type(intensity) ~= "number" or intensity ~= intensity then
		intensity = 1
	end

	local duration = getNumberConfig("cameraCrashShakeDuration", 0.36)
	if duration <= 0 then
		return
	end

	shakeDuration = duration
	shakeTimeRemaining = math.max(shakeTimeRemaining, duration)
	shakeIntensity = math.max(shakeIntensity, math.clamp(intensity, 0, 1))
	shakeSeed += 31.415
end

local function getShakeCFrame(dt, baseCFrame)
	if shakeTimeRemaining <= 0 or shakeIntensity <= 0 then
		return baseCFrame
	end

	local duration = math.max(getNumberConfig("cameraCrashShakeDuration", shakeDuration), 0.001)
	shakeTimeRemaining = math.max(shakeTimeRemaining - dt, 0)

	local fade = math.clamp(shakeTimeRemaining / duration, 0, 1)
	local strength = shakeIntensity * fade * fade
	if strength <= 0 then
		shakeIntensity = 0
		return baseCFrame
	end

	local frequency = getNumberConfig("cameraCrashShakeFrequency", 25)
	local t = os.clock() * frequency + shakeSeed
	local distance = getNumberConfig("cameraCrashShakeDistance", 2.4) * strength
	local angle = math.rad(getNumberConfig("cameraCrashShakeAngleDegrees", 2.2)) * strength

	local offset = baseCFrame.RightVector * (math.noise(t, 0, shakeSeed) * distance)
		+ baseCFrame.UpVector * (math.noise(0, t, shakeSeed) * distance * 0.7)
		+ baseCFrame.LookVector * (math.noise(t, t, shakeSeed) * distance * 0.35)
	local rotation = CFrame.Angles(
		math.noise(t, 2, shakeSeed) * angle,
		math.noise(2, t, shakeSeed) * angle,
		math.noise(t, 4, shakeSeed) * angle
	)

	if shakeTimeRemaining <= 0 then
		shakeIntensity = 0
	end

	return (baseCFrame + offset) * rotation
end

local function restoreCamera()
	local camera = getCurrentCamera()
	local humanoid = getHumanoid()

	if camera then
		camera.CameraType = previousCameraType or Enum.CameraType.Custom

		if previousCameraSubject and previousCameraSubject.Parent then
			camera.CameraSubject = previousCameraSubject
		elseif humanoid then
			camera.CameraSubject = humanoid
		end

		if previousFieldOfView then
			camera.FieldOfView = previousFieldOfView
		end
	end

	activeCab = nil
	previousCameraType = nil
	previousCameraSubject = nil
	previousFieldOfView = nil
	smoothedCabPosition = nil
	cameraPosition = nil
	cameraFocus = nil
	smoothedSpeed = 0
	shakeTimeRemaining = 0
	shakeIntensity = 0
end

local function startCamera(cab)
	local camera = getCurrentCamera()
	if not camera then
		return
	end

	local pivot = cab:GetPivot()
	local cabPosition = pivot.Position
	local cabForward = getCabForward(pivot)

	activeCab = cab
	previousCameraType = camera.CameraType
	previousCameraSubject = camera.CameraSubject
	previousFieldOfView = camera.FieldOfView
	smoothedCabPosition = cabPosition
	cameraPosition = nil
	cameraFocus = nil
	cameraYaw = vectorToYaw(cabForward)
	currentDistance = getNumberConfig("cameraBaseDistance", 34)
	currentFov = getNumberConfig("cameraBaseFov", 70)
	smoothedSpeed = 0
	shakeTimeRemaining = 0
	shakeIntensity = 0

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = currentFov
end

local function updateActiveCamera(dt)
	local camera = getCurrentCamera()
	if not camera or not activeCab or not activeCab.Parent then
		restoreCamera()
		return
	end

	dt = math.min(dt, getNumberConfig("cameraMaxDeltaTime", 1 / 20))
	if dt <= 0 then
		return
	end

	local pivot = activeCab:GetPivot()
	local replicatedCabPosition = pivot.Position

	if not smoothedCabPosition then
		smoothedCabPosition = replicatedCabPosition
	end

	local previousSmoothedCabPosition = smoothedCabPosition
	smoothedCabPosition = smoothedCabPosition:Lerp(
		replicatedCabPosition,
		getSnapOrSmoothAlpha(getNumberConfig("cameraTargetResponsiveness", 18), dt)
	)

	local smoothedDelta = smoothedCabPosition - previousSmoothedCabPosition
	local horizontalDelta = Vector3.new(smoothedDelta.X, 0, smoothedDelta.Z)

	local rawSpeed = horizontalDelta.Magnitude / dt
	local speedAlpha = getAlpha(10, dt)
	smoothedSpeed = lerpNumber(smoothedSpeed, rawSpeed, speedAlpha)

	local cabForward = getCabForward(pivot)
	local targetForward = cabForward
	if rawSpeed >= getNumberConfig("cameraMovementDirectionMinSpeed", 6) and horizontalDelta.Magnitude > 0.001 then
		targetForward = horizontalDelta.Unit
	end

	local targetYaw = vectorToYaw(targetForward)
	cameraYaw += shortestAngle(cameraYaw, targetYaw) * getAlpha(getNumberConfig("cameraYawResponsiveness", 4), dt)

	local forward = yawToForward(cameraYaw)
	local speedBlend = getSpeedAlpha(smoothedSpeed)
	local baseDistance = getNumberConfig("cameraBaseDistance", 34)
	local fastDistance = getNumberConfig("cameraFastDistance", 48)
	local targetDistance = lerpNumber(baseDistance, fastDistance, speedBlend)
	local targetFov = lerpNumber(
		getNumberConfig("cameraBaseFov", 70),
		getNumberConfig("cameraFastFov", 86),
		speedBlend
	)

	currentDistance = lerpNumber(
		currentDistance,
		targetDistance,
		getAlpha(getNumberConfig("cameraDistanceResponsiveness", 7), dt)
	)
	currentFov = lerpNumber(
		currentFov,
		targetFov,
		getAlpha(getNumberConfig("cameraFovResponsiveness", 6), dt)
	)

	local lookAhead = getNumberConfig("cameraLookAheadDistance", 8)
		+ getNumberConfig("cameraSpeedLookAheadDistance", 16) * speedBlend
	local desiredFocus = smoothedCabPosition
		+ UP * getNumberConfig("cameraLookHeight", 4.5)
		+ forward * lookAhead
	local desiredPosition = smoothedCabPosition
		+ UP * getNumberConfig("cameraHeight", 13)
		- forward * currentDistance

	local positionAlpha = getAlpha(getNumberConfig("cameraPositionResponsiveness", 9), dt)
	if not cameraPosition then
		cameraPosition = desiredPosition
	else
		cameraPosition = cameraPosition:Lerp(desiredPosition, positionAlpha)
	end

	if not cameraFocus then
		cameraFocus = desiredFocus
	else
		cameraFocus = cameraFocus:Lerp(desiredFocus, positionAlpha)
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = currentFov

	local baseCFrame = CFrame.lookAt(cameraPosition, cameraFocus, UP)
	camera.CFrame = getShakeCFrame(dt, baseCFrame)
end

task.spawn(function()
	local cameraEventRemote = ReplicatedStorage:WaitForChild(Config.cameraEventRemoteName, 10)
	if cameraEventRemote and cameraEventRemote:IsA("RemoteEvent") then
		cameraEventRemote.OnClientEvent:Connect(function(action, intensity)
			if action == "Crash" and activeCab then
				triggerCrashShake(intensity)
			end
		end)
	end
end)

RunService:BindToRenderStep("Cab87CameraController", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local drivenCab = getDrivenCab()
	if drivenCab ~= activeCab then
		if activeCab then
			restoreCamera()
		end

		if drivenCab then
			startCamera(drivenCab)
		end
	end

	if activeCab then
		updateActiveCamera(dt)
	end
end)
