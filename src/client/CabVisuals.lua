local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Easing = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Easing"))

local CabVisuals = {}

local TAU = math.pi * 2
local HIDDEN_TRANSPARENCY_SEQUENCE = NumberSequence.new(1)

local function getNumberConfig(key, fallback)
	local value = Config[key]
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function shortestAngle(fromYaw, toYaw)
	return (toYaw - fromYaw + math.pi) % TAU - math.pi
end

local function vectorToYaw(vector)
	return math.atan2(vector.X, vector.Z)
end

local function flattenUnit(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return nil
	end

	return horizontal.Unit
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

local function getNumberAttribute(instance, attributeName)
	if type(attributeName) ~= "string" then
		return nil
	end

	local value = instance:GetAttribute(attributeName)
	if type(value) == "number" and value == value then
		return value
	end

	return nil
end

function CabVisuals.getCabPivotValue(cab)
	local pivotValue = cab:FindFirstChild(Config.carServerPivotValueName)
	if pivotValue and pivotValue:IsA("CFrameValue") then
		return pivotValue
	end

	return nil
end

function CabVisuals.getCabTargetPivot(cab)
	local pivotValue = CabVisuals.getCabPivotValue(cab)
	if pivotValue then
		return pivotValue.Value
	end

	return cab:GetPivot()
end

local CabVisual = {}
CabVisual.__index = CabVisual

function CabVisual.new(cab, options)
	local self = setmetatable({}, CabVisual)
	self.cab = cab
	self.parent = options and options.parent or Workspace.CurrentCamera or Workspace
	self.sourceState = nil
	self.visual = nil
	self.effectMirrors = {}
	self.serverPivotSamples = {}
	self.latestServerPivotSample = nil
	self.smoothedPosition = nil
	self.visualCFrame = nil
	self.previousYaw = nil
	self.visualDriveRoll = 0
	self.visualDriftRoll = 0
	self.visualBoostPitch = 0
	self.visualBounceOffset = 0
	self.visualBounceVelocity = 0
	self.boostWheelieTimer = 0
	self.boostWheelieReturnTimer = 0
	self.boostWheelieReturnStartPitch = 0
	self.lastBoostPulse = getNumberAttribute(cab, Config.carVisualBoostPulseAttribute)
	self.lastLandingPulse = getNumberAttribute(cab, Config.carVisualLandingPulseAttribute)

	self:reset(CabVisuals.getCabTargetPivot(cab))
	self:createVisual()

	return self
end

function CabVisual:setParent(parent)
	self.parent = parent or Workspace.CurrentCamera or Workspace
	if self.visual and self.visual.Parent ~= self.parent then
		self.visual.Parent = self.parent
	end
end

function CabVisual:reset(pivot)
	local now = os.clock()
	self.serverPivotSamples = {
		{
			time = now,
			pivot = pivot,
		},
	}
	self.latestServerPivotSample = pivot
	self.smoothedPosition = pivot.Position
	self.visualCFrame = pivot
	self.previousYaw = vectorToYaw(pivot.LookVector)
	self.visualDriveRoll = 0
	self.visualDriftRoll = 0
	self.visualBoostPitch = 0
	self.visualBounceOffset = 0
	self.visualBounceVelocity = 0
	self.boostWheelieTimer = 0
	self.boostWheelieReturnTimer = 0
	self.boostWheelieReturnStartPitch = 0
	self.lastBoostPulse = getNumberAttribute(self.cab, Config.carVisualBoostPulseAttribute)
	self.lastLandingPulse = getNumberAttribute(self.cab, Config.carVisualLandingPulseAttribute)
end

function CabVisual:hideSourceVisuals()
	local state = {}

	for _, descendant in ipairs(self.cab:GetDescendants()) do
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

	self.sourceState = state
end

function CabVisual:restoreSourceVisuals()
	if not self.sourceState then
		return
	end

	for instance, state in pairs(self.sourceState) do
		if instance.Parent then
			instance[state.property] = state.value
		end
	end

	self.sourceState = nil
end

function CabVisual:createVisual()
	self:restoreSourceVisuals()
	self:destroyVisualOnly()

	local wasArchivable = self.cab.Archivable
	self.cab.Archivable = true
	local ok, visual = pcall(function()
		return self.cab:Clone()
	end)
	self.cab.Archivable = wasArchivable

	if not ok or not visual then
		return
	end

	visual.Name = self.cab.Name .. "LocalVisual"
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

	for _, source in ipairs(self.cab:GetDescendants()) do
		if source:IsA("ParticleEmitter") then
			local target = cloneLookup[getDescendantKey(self.cab, source)]
			if target and target:IsA("ParticleEmitter") then
				table.insert(self.effectMirrors, {
					source = source,
					target = target,
					transparency = target.Transparency,
				})
			end
		end
	end

	visual:PivotTo(self.visualCFrame or CabVisuals.getCabTargetPivot(self.cab))
	visual.Parent = self.parent
	self.visual = visual
	self:hideSourceVisuals()
	self:mirrorEffects()
end

function CabVisual:destroyVisualOnly()
	if self.visual then
		self.visual:Destroy()
		self.visual = nil
	end

	self.effectMirrors = {}
end

function CabVisual:destroy()
	self:restoreSourceVisuals()
	self:destroyVisualOnly()
end

function CabVisual:mirrorEffects()
	for _, mirror in ipairs(self.effectMirrors) do
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

function CabVisual:recordServerPivotSample(pivot)
	local latest = self.latestServerPivotSample
	if latest
		and (pivot.Position - latest.Position).Magnitude <= 0.001
		and getCFrameRotationAngle(latest, pivot) <= 0.0001
	then
		return
	end

	local now = os.clock()
	table.insert(self.serverPivotSamples, {
		time = now,
		pivot = pivot,
	})
	self.latestServerPivotSample = pivot

	while #self.serverPivotSamples > 8 do
		table.remove(self.serverPivotSamples, 1)
	end
end

function CabVisual:extrapolatePivot(previousSample, latestSample, extraTime)
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

function CabVisual:getBufferedPivot(rawPivot)
	self:recordServerPivotSample(rawPivot)

	local sampleCount = #self.serverPivotSamples
	if sampleCount < 2 then
		return rawPivot
	end

	local now = os.clock()
	local interpolationDelay = math.max(getNumberConfig("carVisualInterpolationDelay", 0.08), 0)
	local targetTime = now - interpolationDelay

	for index = 1, sampleCount - 1 do
		local fromSample = self.serverPivotSamples[index]
		local toSample = self.serverPivotSamples[index + 1]

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

	local firstSample = self.serverPivotSamples[1]
	if targetTime <= firstSample.time then
		return firstSample.pivot
	end

	local latestSample = self.serverPivotSamples[sampleCount]
	local previousSample = self.serverPivotSamples[sampleCount - 1]
	local maxExtrapolation = math.max(getNumberConfig("carVisualMaxExtrapolationTime", 0.10), 0)
	local extraTime = math.clamp(targetTime - latestSample.time, 0, maxExtrapolation)

	return self:extrapolatePivot(previousSample, latestSample, extraTime)
end

function CabVisual:startBoostWheelie()
	if getNumberConfig("carBoostWheelieDuration", 0) <= 0
		or getNumberConfig("carBoostWheelieDegrees", 0) <= 0
	then
		return
	end

	self.boostWheelieTimer = math.max(self.boostWheelieTimer, getNumberConfig("carBoostWheelieDuration", 1))
	self.boostWheelieReturnTimer = 0
	self.boostWheelieReturnStartPitch = 0
end

function CabVisual:startBoostWheelieReturn()
	self.boostWheelieTimer = 0
	self.boostWheelieReturnStartPitch = self.visualBoostPitch
	self.boostWheelieReturnTimer = math.max(getNumberConfig("carBoostWheelieReturnDuration", 0.5), 0)

	if self.boostWheelieReturnTimer <= 0 or math.abs(self.boostWheelieReturnStartPitch) <= 0.001 then
		self.boostWheelieReturnTimer = 0
		self.boostWheelieReturnStartPitch = 0
	end
end

function CabVisual:triggerLandingBounce(landingSpeed)
	local maxOffset = math.max(getNumberConfig("carLandingBounceMaxOffset", 0), 0)
	local impulse = math.max(getNumberConfig("carLandingBounceImpulse", 0), 0)
	if maxOffset <= 0 or impulse <= 0 then
		return
	end

	local minSpeed = math.max(getNumberConfig("carLandingBounceMinSpeed", 0), 0)
	local maxSpeed = math.max(getNumberConfig("carLandingBounceMaxSpeed", minSpeed + 0.001), minSpeed + 0.001)
	local bounceAlpha = math.clamp((landingSpeed - minSpeed) / (maxSpeed - minSpeed), 0, 1)
	if bounceAlpha <= 0 then
		return
	end

	self.visualBounceVelocity = math.min(self.visualBounceVelocity, -impulse * bounceAlpha)
end

function CabVisual:updatePulses()
	local boostPulse = getNumberAttribute(self.cab, Config.carVisualBoostPulseAttribute)
	if boostPulse ~= self.lastBoostPulse then
		if self.lastBoostPulse ~= nil then
			self:startBoostWheelie()
		end
		self.lastBoostPulse = boostPulse
	end

	local landingPulse = getNumberAttribute(self.cab, Config.carVisualLandingPulseAttribute)
	if landingPulse ~= self.lastLandingPulse then
		if self.lastLandingPulse ~= nil then
			self:triggerLandingBounce(getNumberAttribute(self.cab, Config.carVisualLandingSpeedAttribute) or 0)
		end
		self.lastLandingPulse = landingPulse
	end
end

function CabVisual:updateBoostWheelie(dt)
	local targetBoostPitch = 0

	if self.boostWheelieTimer > 0 then
		targetBoostPitch = -math.rad(getNumberConfig("carBoostWheelieDegrees", 0))
		self.boostWheelieTimer = math.max(self.boostWheelieTimer - dt, 0)

		if self.boostWheelieTimer <= 0 then
			self:startBoostWheelieReturn()
		end
	elseif self.boostWheelieReturnTimer > 0 then
		local returnDuration = math.max(getNumberConfig("carBoostWheelieReturnDuration", 0.5), 0.001)
		local returnProgress = 1 - math.clamp(self.boostWheelieReturnTimer / returnDuration, 0, 1)
		local returnAlpha = Easing.OutBack(returnProgress)
		targetBoostPitch = self.boostWheelieReturnStartPitch * (1 - returnAlpha)
		self.boostWheelieReturnTimer = math.max(self.boostWheelieReturnTimer - dt, 0)

		if self.boostWheelieReturnTimer <= 0 then
			targetBoostPitch = 0
			self.boostWheelieReturnStartPitch = 0
		end
	end

	if targetBoostPitch < 0 and math.abs(targetBoostPitch) > math.abs(self.visualBoostPitch) then
		self.visualBoostPitch += (targetBoostPitch - self.visualBoostPitch)
			* math.clamp(getNumberConfig("carBoostWheelieFollow", 16) * dt, 0, 1)
	else
		self.visualBoostPitch = targetBoostPitch
	end
end

function CabVisual:updateLandingBounce(dt)
	local spring = math.max(getNumberConfig("carLandingBounceSpring", 0), 0)
	local damping = math.max(getNumberConfig("carLandingBounceDamping", 0), 0)
	local maxOffset = math.max(getNumberConfig("carLandingBounceMaxOffset", 0), 0)
	if maxOffset <= 0 or spring <= 0 then
		self.visualBounceOffset = 0
		self.visualBounceVelocity = 0
		return
	end

	self.visualBounceVelocity += (-self.visualBounceOffset * spring - self.visualBounceVelocity * damping) * dt
	self.visualBounceOffset += self.visualBounceVelocity * dt

	if self.visualBounceOffset < -maxOffset then
		self.visualBounceOffset = -maxOffset
		self.visualBounceVelocity = math.max(self.visualBounceVelocity, 0)
	elseif self.visualBounceOffset > maxOffset then
		self.visualBounceOffset = maxOffset
		self.visualBounceVelocity = math.min(self.visualBounceVelocity, 0)
	end

	if math.abs(self.visualBounceOffset) < 0.001 and math.abs(self.visualBounceVelocity) < 0.001 then
		self.visualBounceOffset = 0
		self.visualBounceVelocity = 0
	end
end

function CabVisual:updateLean(bufferedPivot, previousPosition, dt)
	local currentYaw = vectorToYaw(bufferedPivot.LookVector)
	local yawRate = 0
	if self.previousYaw and dt > 0 then
		yawRate = shortestAngle(self.previousYaw, currentYaw) / dt
	end
	self.previousYaw = currentYaw

	local horizontalDelta = self.smoothedPosition - previousPosition
	local horizontalSpeed = Vector3.new(horizontalDelta.X, 0, horizontalDelta.Z).Magnitude / math.max(dt, 0.001)
	local movementDirection = flattenUnit(horizontalDelta)
	local right = flattenUnit(bufferedPivot.RightVector)
	local lateralSign = 0
	if movementDirection and right then
		lateralSign = math.clamp(movementDirection:Dot(right), -1, 1)
	end

	local drifting = self.cab:GetAttribute(Config.carVisualDriftingAttribute) == true
	local targetDriveRoll = 0
	local targetDriftRoll = 0

	if drifting then
		local fullLeanSpeed = math.max(getNumberConfig("carDriftLeanFullSpeed", 96), getNumberConfig("carDriftMinSpeed", 35) + 0.001)
		local leanSpeedAlpha = math.clamp(
			(horizontalSpeed - getNumberConfig("carDriftMinSpeed", 35)) / (fullLeanSpeed - getNumberConfig("carDriftMinSpeed", 35)),
			0,
			1
		)
		local driftSign = if math.abs(lateralSign) > 0.05 then lateralSign else math.clamp(-yawRate / 2.5, -1, 1)
		targetDriftRoll = driftSign * math.rad(getNumberConfig("carDriftLeanDegrees", 16)) * leanSpeedAlpha
	else
		local minSpeed = getNumberConfig("carDriveLeanMinSpeed", 8)
		local fullLeanSpeed = math.max(getNumberConfig("carDriveLeanFullSpeed", 106), minSpeed + 0.001)
		local leanSpeedAlpha = math.clamp((horizontalSpeed - minSpeed) / (fullLeanSpeed - minSpeed), 0, 1)
		targetDriveRoll = math.clamp(-yawRate / 2.5, -1, 1)
			* math.rad(getNumberConfig("carDriveLeanDegrees", 8))
			* leanSpeedAlpha
	end

	self.visualDriveRoll += (targetDriveRoll - self.visualDriveRoll)
		* math.clamp(getNumberConfig("carDriveLeanFollow", 8) * dt, 0, 1)
	self.visualDriftRoll += (targetDriftRoll - self.visualDriftRoll)
		* math.clamp(getNumberConfig("carDriftLeanFollow", 9) * dt, 0, 1)
end

function CabVisual:updatePolish(bufferedPivot, previousPosition, dt)
	self:updatePulses()
	self:updateLean(bufferedPivot, previousPosition, dt)
	self:updateBoostWheelie(dt)
	self:updateLandingBounce(dt)
end

function CabVisual:getPolishedCFrame(bufferedPivot)
	local wheeliePivotOffset = Vector3.new(0, -getNumberConfig("carRideHeight", 2.3), -5.6)
	local wheeliePivot = CFrame.new(wheeliePivotOffset)
		* CFrame.Angles(self.visualBoostPitch, 0, 0)
		* CFrame.new(wheeliePivotOffset * -1)
	local dynamicRoll = self.visualDriveRoll + self.visualDriftRoll

	return CFrame.new(self.smoothedPosition + Vector3.new(0, self.visualBounceOffset, 0))
		* getCFrameRotation(bufferedPivot)
		* CFrame.Angles(0, 0, dynamicRoll)
		* wheeliePivot
end

function CabVisual:update(rawPivot, dt)
	if not self.cab.Parent then
		self:destroy()
		return nil
	end

	dt = math.min(dt, getNumberConfig("cameraMaxDeltaTime", 1 / 20))
	if dt <= 0 then
		dt = 1 / 60
	end

	if not self.visual or not self.visual.Parent then
		self:createVisual()
	end

	local bufferedPivot = self:getBufferedPivot(rawPivot)
	if not self.smoothedPosition then
		self.smoothedPosition = bufferedPivot.Position
	end

	local previousPosition = self.smoothedPosition
	local snapDistance = getNumberConfig("carVisualSnapDistance", 45)
	local snapped = (bufferedPivot.Position - self.smoothedPosition).Magnitude > snapDistance

	if snapped then
		self.smoothedPosition = bufferedPivot.Position
	else
		self.smoothedPosition = self.smoothedPosition:Lerp(
			bufferedPivot.Position,
			getSnapOrSmoothAlpha(getNumberConfig("cameraTargetResponsiveness", 18), dt)
		)
	end

	self:updatePolish(bufferedPivot, previousPosition, dt)
	self.visualCFrame = self:getPolishedCFrame(bufferedPivot)

	if self.visual then
		self.visual:PivotTo(self.visualCFrame)
		self:mirrorEffects()
	end

	return {
		basePivot = bufferedPivot,
		visualCFrame = self.visualCFrame,
		position = self.smoothedPosition,
		previousPosition = previousPosition,
		snapped = snapped,
	}
end

function CabVisuals.new(cab, options)
	return CabVisual.new(cab, options)
end

return CabVisuals
