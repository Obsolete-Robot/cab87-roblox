local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local TAU = math.pi * 2
local UP = Vector3.new(0, 1, 0)

local activeCab = nil
local activeCabVisual = nil
local hiddenSourceVisualState = nil
local localVisualEffectMirrors = {}
local previousCameraType = nil
local previousCameraSubject = nil
local previousFieldOfView = nil
local smoothedCabPosition = nil
local visualCabCFrame = nil
local serverPivotSamples = {}
local latestServerPivotSample = nil
local cameraPosition = nil
local cameraFocus = nil
local cameraYaw = 0
local smoothedSpeed = 0
local reverseMovementTime = 0
local shakeTimeRemaining = 0
local shakeDuration = 0
local shakeIntensity = 0
local shakeSeed = 0
local HIDDEN_TRANSPARENCY_SEQUENCE = NumberSequence.new(1)

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

local function getCabServerPivotValue(cab)
	local pivotValue = cab:FindFirstChild(Config.carServerPivotValueName)
	if pivotValue and pivotValue:IsA("CFrameValue") then
		return pivotValue
	end

	return nil
end

local function getCabTargetPivot(cab)
	local pivotValue = getCabServerPivotValue(cab)
	if pivotValue then
		return pivotValue.Value
	end

	return cab:GetPivot()
end

local function getCFrameRotation(pivot)
	return pivot - pivot.Position
end

local function getCFrameRotationAngle(fromPivot, toPivot)
	local relative = fromPivot:ToObjectSpace(toPivot)
	local _, angle = relative:ToAxisAngle()
	if type(angle) ~= "number" or angle ~= angle then
		return 0
	end

	return math.abs(angle)
end

local function resetServerPivotSamples(pivot)
	local now = os.clock()
	serverPivotSamples = {
		{
			time = now,
			pivot = pivot,
		},
	}
	latestServerPivotSample = pivot
end

local function recordServerPivotSample(pivot)
	local latest = latestServerPivotSample
	if latest
		and (pivot.Position - latest.Position).Magnitude <= 0.001
		and getCFrameRotationAngle(latest, pivot) <= 0.0001
	then
		return
	end

	local now = os.clock()
	table.insert(serverPivotSamples, {
		time = now,
		pivot = pivot,
	})
	latestServerPivotSample = pivot

	while #serverPivotSamples > 8 do
		table.remove(serverPivotSamples, 1)
	end
end

local function extrapolatePivot(previousSample, latestSample, extraTime)
	local sampleDt = latestSample.time - previousSample.time
	if sampleDt <= 0.001 or extraTime <= 0 then
		return latestSample.pivot
	end

	local alpha = math.clamp(extraTime / sampleDt, 0, 1.5)
	local previousPivot = previousSample.pivot
	local latestPivot = latestSample.pivot
	local predictedPosition = latestPivot.Position
		+ (latestPivot.Position - previousPivot.Position) * alpha
	local relativeRotation = previousPivot:ToObjectSpace(latestPivot)
	local axis, angle = relativeRotation:ToAxisAngle()
	local predictedRotation = latestPivot - latestPivot.Position

	if type(angle) == "number" and angle == angle and math.abs(angle) > 0.0001 then
		predictedRotation *= CFrame.fromAxisAngle(axis, angle * alpha)
	end

	return CFrame.new(predictedPosition) * predictedRotation
end

local function getBufferedCabTargetPivot(rawPivot)
	recordServerPivotSample(rawPivot)

	local sampleCount = #serverPivotSamples
	if sampleCount < 2 then
		return rawPivot
	end

	local now = os.clock()
	local interpolationDelay = math.max(getNumberConfig("carVisualInterpolationDelay", 0.08), 0)
	local targetTime = now - interpolationDelay

	for index = 1, sampleCount - 1 do
		local fromSample = serverPivotSamples[index]
		local toSample = serverPivotSamples[index + 1]

		if targetTime >= fromSample.time and targetTime <= toSample.time then
			local sampleDuration = toSample.time - fromSample.time
			if sampleDuration <= 0.001 then
				return toSample.pivot
			end

			return fromSample.pivot:Lerp(
				toSample.pivot,
				math.clamp((targetTime - fromSample.time) / sampleDuration, 0, 1)
			)
		end
	end

	local firstSample = serverPivotSamples[1]
	if targetTime <= firstSample.time then
		return firstSample.pivot
	end

	local latestSample = serverPivotSamples[sampleCount]
	local previousSample = serverPivotSamples[sampleCount - 1]
	local maxExtrapolation = math.max(getNumberConfig("carVisualMaxExtrapolationTime", 0.10), 0)
	local extraTime = math.clamp(targetTime - latestSample.time, 0, maxExtrapolation)

	return extrapolatePivot(previousSample, latestSample, extraTime)
end

local function getDescendantKey(root, descendant)
	local segments = {}
	local current = descendant

	while current and current ~= root do
		table.insert(segments, 1, current.Name .. ":" .. current.ClassName)
		current = current.Parent
	end

	return table.concat(segments, "/")
end

local function buildDescendantLookup(root)
	local lookup = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		lookup[getDescendantKey(root, descendant)] = descendant
	end

	return lookup
end

local function hideSourceCabVisuals(cab)
	local state = {}

	for _, descendant in ipairs(cab:GetDescendants()) do
		if descendant:IsA("BasePart") then
			state[descendant] = {
				property = "LocalTransparencyModifier",
				value = descendant.LocalTransparencyModifier,
			}
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			state[descendant] = {
				property = "Transparency",
				value = descendant.Transparency,
			}
			descendant.Transparency = 1
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			state[descendant] = {
				property = "Transparency",
				value = descendant.Transparency,
			}
			descendant.Transparency = HIDDEN_TRANSPARENCY_SEQUENCE
		end
	end

	return state
end

local function restoreSourceCabVisuals()
	if not hiddenSourceVisualState then
		return
	end

	for instance, state in pairs(hiddenSourceVisualState) do
		if instance.Parent then
			instance[state.property] = state.value
		end
	end

	hiddenSourceVisualState = nil
end

local function mirrorLocalVisualEffects()
	for _, mirror in ipairs(localVisualEffectMirrors) do
		local source = mirror.source
		local target = mirror.target
		if source.Parent and target.Parent then
			target.Enabled = source.Enabled
			target.Color = source.Color
			target.Rate = source.Rate
			target.Transparency = mirror.transparency
		end
	end
end

local function destroyLocalCabVisual()
	restoreSourceCabVisuals()

	if activeCabVisual then
		activeCabVisual:Destroy()
		activeCabVisual = nil
	end

	localVisualEffectMirrors = {}
end

local function createLocalCabVisual(cab, pivot)
	destroyLocalCabVisual()

	local wasArchivable = cab.Archivable
	cab.Archivable = true
	local ok, visual = pcall(function()
		return cab:Clone()
	end)
	cab.Archivable = wasArchivable

	if not ok or not visual then
		return nil
	end

	visual.Name = "Cab87TaxiLocalVisual"

	local cloneLookup = buildDescendantLookup(visual)
	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("ProximityPrompt")
			or descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("JointInstance")
			or descendant:IsA("Constraint")
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	for _, source in ipairs(cab:GetDescendants()) do
		if source:IsA("ParticleEmitter") then
			local target = cloneLookup[getDescendantKey(cab, source)]
			if target and target:IsA("ParticleEmitter") then
				table.insert(localVisualEffectMirrors, {
					source = source,
					target = target,
					transparency = target.Transparency,
				})
			end
		end
	end

	visual:PivotTo(pivot)
	visual.Parent = getCurrentCamera() or Workspace
	activeCabVisual = visual
	hiddenSourceVisualState = hideSourceCabVisuals(cab)
	mirrorLocalVisualEffects()

	return visual
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

local function easeInOutQuad(alpha)
	alpha = math.clamp(alpha, 0, 1)
	if alpha < 0.5 then
		return 2 * alpha * alpha
	end

	local inverse = -2 * alpha + 2
	return 1 - inverse * inverse * 0.5
end

local function getSpeedBlend(speed)
	local minSpeed = getNumberConfig("cameraMinSpeed", 25)
	local maxSpeed = math.max(getNumberConfig("cameraMaxSpeed", 170), minSpeed + 0.001)
	return easeInOutQuad((speed - minSpeed) / (maxSpeed - minSpeed))
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
	local cab = activeCab

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

	if cab and cab.Parent then
		destroyLocalCabVisual()
		cab:PivotTo(getCabTargetPivot(cab))
	end

	activeCab = nil
	destroyLocalCabVisual()
	previousCameraType = nil
	previousCameraSubject = nil
	previousFieldOfView = nil
	smoothedCabPosition = nil
	visualCabCFrame = nil
	serverPivotSamples = {}
	latestServerPivotSample = nil
	cameraPosition = nil
	cameraFocus = nil
	smoothedSpeed = 0
	reverseMovementTime = 0
	shakeTimeRemaining = 0
	shakeIntensity = 0
end

local function startCamera(cab)
	local camera = getCurrentCamera()
	if not camera then
		return
	end

	local pivot = getCabTargetPivot(cab)
	local cabPosition = pivot.Position
	local cabForward = getCabForward(pivot)

	activeCab = cab
	previousCameraType = camera.CameraType
	previousCameraSubject = camera.CameraSubject
	previousFieldOfView = camera.FieldOfView
	smoothedCabPosition = cabPosition
	visualCabCFrame = pivot
	resetServerPivotSamples(pivot)
	cameraPosition = nil
	cameraFocus = nil
	cameraYaw = vectorToYaw(cabForward)
	smoothedSpeed = 0
	reverseMovementTime = 0
	shakeTimeRemaining = 0
	shakeIntensity = 0

	createLocalCabVisual(cab, pivot)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = getNumberConfig("cameraMinFov", 70)
end

local function updateCabVisual(cab, targetPivot, visualPosition, forceSnap, dt)
	if not visualCabCFrame or forceSnap then
		visualCabCFrame = CFrame.new(visualPosition) * getCFrameRotation(targetPivot)
	else
		local visualRotation = getCFrameRotation(visualCabCFrame):Lerp(
			getCFrameRotation(targetPivot),
			getSnapOrSmoothAlpha(getNumberConfig("carVisualResponsiveness", 26), dt)
		)
		visualCabCFrame = CFrame.new(visualPosition) * visualRotation
	end

	if activeCabVisual and not activeCabVisual.Parent then
		destroyLocalCabVisual()
	end

	if activeCabVisual then
		activeCabVisual:PivotTo(visualCabCFrame)
		mirrorLocalVisualEffects()
	else
		cab:PivotTo(visualCabCFrame)
	end
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

	local rawPivot = getCabTargetPivot(activeCab)
	local pivot = getBufferedCabTargetPivot(rawPivot)
	local replicatedCabPosition = pivot.Position

	if not smoothedCabPosition then
		smoothedCabPosition = replicatedCabPosition
	end

	local previousSmoothedCabPosition = smoothedCabPosition
	local snapDistance = getNumberConfig("carVisualSnapDistance", 45)
	local forceVisualSnap = (replicatedCabPosition - smoothedCabPosition).Magnitude > snapDistance
	if forceVisualSnap then
		smoothedCabPosition = replicatedCabPosition
		previousSmoothedCabPosition = smoothedCabPosition
		cameraPosition = nil
		cameraFocus = nil
	else
		smoothedCabPosition = smoothedCabPosition:Lerp(
			replicatedCabPosition,
			getSnapOrSmoothAlpha(getNumberConfig("cameraTargetResponsiveness", 18), dt)
		)
	end

	updateCabVisual(activeCab, pivot, smoothedCabPosition, forceVisualSnap, dt)

	local smoothedDelta = smoothedCabPosition - previousSmoothedCabPosition
	local horizontalDelta = Vector3.new(smoothedDelta.X, 0, smoothedDelta.Z)

	local rawSpeed = horizontalDelta.Magnitude / dt
	local speedAlpha = getAlpha(10, dt)
	smoothedSpeed = lerpNumber(smoothedSpeed, rawSpeed, speedAlpha)

	local cabForward = getCabForward(pivot)
	local targetForward = cabForward
	if rawSpeed >= getNumberConfig("cameraMovementDirectionMinSpeed", 6) and horizontalDelta.Magnitude > 0.001 then
		local movementForward = horizontalDelta.Unit
		local movingBackward = movementForward:Dot(cabForward) < -0.35

		if movingBackward then
			reverseMovementTime += dt

			if reverseMovementTime >= getNumberConfig("cameraReverseLookDelay", 0.6) then
				targetForward = movementForward
			end
		else
			reverseMovementTime = 0
			targetForward = movementForward
		end
	else
		reverseMovementTime = 0
	end

	local targetYaw = vectorToYaw(targetForward)
	cameraYaw += shortestAngle(cameraYaw, targetYaw) * getAlpha(getNumberConfig("cameraYawResponsiveness", 4), dt)

	local forward = yawToForward(cameraYaw)
	local speedBlend = getSpeedBlend(smoothedSpeed)
	local targetDistance = lerpNumber(
		getNumberConfig("cameraMinDistance", 34),
		getNumberConfig("cameraMaxDistance", 48),
		speedBlend
	)
	local targetFov = lerpNumber(
		getNumberConfig("cameraMinFov", 70),
		getNumberConfig("cameraMaxFov", 86),
		speedBlend
	)
	local targetHeight = lerpNumber(
		getNumberConfig("cameraMinHeight", 13),
		getNumberConfig("cameraMaxHeight", 13),
		speedBlend
	)

	local lookAhead = getNumberConfig("cameraLookAheadDistance", 8)
	local desiredFocus = smoothedCabPosition
		+ UP * getNumberConfig("cameraLookHeight", 4.5)
		+ forward * lookAhead
	local desiredPosition = smoothedCabPosition
		+ UP * targetHeight
		- forward * targetDistance

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
	camera.FieldOfView = targetFov

	local baseCFrame = CFrame.lookAt(cameraPosition, cameraFocus, UP)
	camera.CFrame = getShakeCFrame(dt, baseCFrame)
end

task.spawn(function()
	local cameraEventRemote = ReplicatedStorage:WaitForChild(Config.cameraEventRemoteName, 10)
	if cameraEventRemote and cameraEventRemote:IsA("RemoteEvent") then
		cameraEventRemote.OnClientEvent:Connect(function(action, intensity)
			if (action == "Crash" or action == "Land" or action == "Shake") and activeCab then
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
