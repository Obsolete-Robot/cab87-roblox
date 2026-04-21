local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MinimapController = require(script.Parent:WaitForChild("MinimapController"))
local driveInputRemote = ReplicatedStorage:WaitForChild(Config.driveInputRemoteName)

local keyDown = {}
local gamepadSteer = 0
local gamepadAirPitch = 0
local gamepadAccel = 0
local gamepadBrake = 0
local gamepadDriftButtons = {}
local lastSentThrottle = nil
local lastSentSteer = nil
local lastSentDrift = nil
local lastSentAirPitch = nil
local sendAccumulator = 0
local forceSendAccumulator = 0

local driveKeys = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
}

local driftGamepadButtons = {
	[Enum.KeyCode.ButtonB] = true,
	[Enum.KeyCode.ButtonX] = true,
	[Enum.KeyCode.ButtonL1] = true,
}

local function deadzone(value)
	if math.abs(value) < 0.12 then
		return 0
	end

	return value
end

local function getKeyboardAxis(positiveKeyA, positiveKeyB, negativeKeyA, negativeKeyB)
	local positive = (keyDown[positiveKeyA] or keyDown[positiveKeyB]) and 1 or 0
	local negative = (keyDown[negativeKeyA] or keyDown[negativeKeyB]) and 1 or 0
	return positive - negative
end

local function isGamepadInput(input)
	return input.UserInputType == Enum.UserInputType.Gamepad1
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

local function getNumberAttribute(instance, attributeName)
	if not instance or type(attributeName) ~= "string" then
		return nil
	end

	local value = instance:GetAttribute(attributeName)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end

	return value
end

local function getStringAttribute(instance, attributeName)
	if not instance or type(attributeName) ~= "string" then
		return nil
	end

	local value = instance:GetAttribute(attributeName)
	if type(value) ~= "string" then
		return nil
	end

	return value
end

local function getAlpha(responsiveness, dt)
	if responsiveness <= 0 then
		return 1
	end

	return 1 - math.exp(-responsiveness * dt)
end

local function isDriftHeld()
	if keyDown[Enum.KeyCode.LeftShift] or keyDown[Enum.KeyCode.RightShift] then
		return true
	end

	for _, isHeld in pairs(gamepadDriftButtons) do
		if isHeld then
			return true
		end
	end

	return false
end

local function getDriveState()
	local keyboardThrottle = getKeyboardAxis(Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.S, Enum.KeyCode.Down)
	local keyboardSteer = getKeyboardAxis(Enum.KeyCode.D, Enum.KeyCode.Right, Enum.KeyCode.A, Enum.KeyCode.Left)
	local keyboardAirPitch = getKeyboardAxis(Enum.KeyCode.Up, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Down)
	local gamepadThrottle = gamepadAccel - gamepadBrake
	local throttle = math.clamp(keyboardThrottle + gamepadThrottle, -1, 1)
	local steer = math.abs(gamepadSteer) > 0 and gamepadSteer or keyboardSteer
	local airPitch = if math.abs(gamepadAirPitch) > 0 then gamepadAirPitch else keyboardAirPitch

	return throttle, math.clamp(steer, -1, 1), isDriftHeld(), math.clamp(airPitch, -1, 1)
end

local function sendDriveState(force)
	local throttle, steer, drift, airPitch = getDriveState()
	if not force
		and throttle == lastSentThrottle
		and steer == lastSentSteer
		and drift == lastSentDrift
		and airPitch == lastSentAirPitch
	then
		return
	end

	lastSentThrottle = throttle
	lastSentSteer = steer
	lastSentDrift = drift
	lastSentAirPitch = airPitch
	driveInputRemote:FireServer("Drive", throttle, steer, drift, airPitch)
end

local function setGamepadDriftButton(keyCode, isHeld)
	if driftGamepadButtons[keyCode] then
		gamepadDriftButtons[keyCode] = isHeld or nil
	end
end

local function updateGamepadAnalog(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		gamepadSteer = deadzone(input.Position.X)
		gamepadAirPitch = deadzone(input.Position.Y)
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		gamepadAccel = math.clamp(math.abs(input.Position.Z), 0, 1)
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		gamepadBrake = math.clamp(math.abs(input.Position.Z), 0, 1)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed and not isGamepadInput(input) then
		return
	end

	if driveKeys[input.KeyCode] then
		keyDown[input.KeyCode] = true
	elseif isGamepadInput(input) then
		setGamepadDriftButton(input.KeyCode, true)

		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			gamepadAccel = 1
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			gamepadBrake = 1
		end
	end

	sendDriveState(false)
end)

UserInputService.InputEnded:Connect(function(input)
	if driveKeys[input.KeyCode] then
		keyDown[input.KeyCode] = nil
	elseif isGamepadInput(input) then
		setGamepadDriftButton(input.KeyCode, false)

		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			gamepadSteer = 0
			gamepadAirPitch = 0
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			gamepadAccel = 0
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			gamepadBrake = 0
		end
	end

	sendDriveState(false)
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed and not isGamepadInput(input) then
		return
	end

	if isGamepadInput(input) then
		updateGamepadAnalog(input)
		sendDriveState(false)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	sendAccumulator += dt
	forceSendAccumulator += dt
	if sendAccumulator >= 1 / 20 then
		sendAccumulator = 0
		local force = forceSendAccumulator >= 0.25
		if force then
			forceSendAccumulator = 0
		end
		sendDriveState(force)
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "Cab87Hud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

MinimapController.start(gui, getDrivenCab)

local label = Instance.new("TextLabel")
label.Name = "Hint"
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.fromScale(0.5, 0.97)
label.Size = UDim2.fromOffset(620, 48)
label.BackgroundTransparency = 0.3
label.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
label.TextColor3 = Color3.fromRGB(245, 245, 245)
label.TextStrokeTransparency = 0.75
label.TextScaled = true
label.TextWrapped = true
label.Font = Enum.Font.GothamBold
label.Text = "Enter: E / Triangle  |  Drive: W/S + A/D or PS5 R2/L2 + Left Stick  |  Drift: Shift / Circle / Square / L1"
label.Parent = gui

local speedometer = Instance.new("Frame")
speedometer.Name = "Speedometer"
speedometer.AnchorPoint = Vector2.new(0, 1)
speedometer.Position = UDim2.new(0, 18, 1, -88)
speedometer.Size = UDim2.fromOffset(174, 84)
speedometer.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
speedometer.BackgroundTransparency = 0.12
speedometer.BorderSizePixel = 0
speedometer.Visible = false
speedometer.Parent = gui

local speedometerCorner = Instance.new("UICorner")
speedometerCorner.CornerRadius = UDim.new(0, 8)
speedometerCorner.Parent = speedometer

local speedometerStroke = Instance.new("UIStroke")
speedometerStroke.Color = Color3.fromRGB(255, 206, 38)
speedometerStroke.Transparency = 0.15
speedometerStroke.Thickness = 2
speedometerStroke.Parent = speedometer

local speedTitle = Instance.new("TextLabel")
speedTitle.Name = "Title"
speedTitle.BackgroundTransparency = 1
speedTitle.Position = UDim2.fromOffset(14, 8)
speedTitle.Size = UDim2.new(1, -28, 0, 16)
speedTitle.Font = Enum.Font.GothamBold
speedTitle.Text = "SPEED"
speedTitle.TextColor3 = Color3.fromRGB(255, 206, 38)
speedTitle.TextSize = 13
speedTitle.TextXAlignment = Enum.TextXAlignment.Left
speedTitle.Parent = speedometer

local speedValue = Instance.new("TextLabel")
speedValue.Name = "Value"
speedValue.BackgroundTransparency = 1
speedValue.Position = UDim2.fromOffset(13, 24)
speedValue.Size = UDim2.fromOffset(102, 42)
speedValue.Font = Enum.Font.GothamBold
speedValue.Text = "000"
speedValue.TextColor3 = Color3.fromRGB(245, 245, 245)
speedValue.TextSize = 38
speedValue.TextXAlignment = Enum.TextXAlignment.Left
speedValue.TextYAlignment = Enum.TextYAlignment.Bottom
speedValue.Parent = speedometer

local speedUnit = Instance.new("TextLabel")
speedUnit.Name = "Unit"
speedUnit.BackgroundTransparency = 1
speedUnit.Position = UDim2.fromOffset(111, 45)
speedUnit.Size = UDim2.fromOffset(48, 18)
speedUnit.Font = Enum.Font.GothamSemibold
speedUnit.Text = "stud/s"
speedUnit.TextColor3 = Color3.fromRGB(210, 213, 218)
speedUnit.TextSize = 12
speedUnit.TextXAlignment = Enum.TextXAlignment.Left
speedUnit.Parent = speedometer

local speedBarTrack = Instance.new("Frame")
speedBarTrack.Name = "BarTrack"
speedBarTrack.Position = UDim2.fromOffset(14, 70)
speedBarTrack.Size = UDim2.new(1, -28, 0, 5)
speedBarTrack.BackgroundColor3 = Color3.fromRGB(54, 58, 64)
speedBarTrack.BorderSizePixel = 0
speedBarTrack.Parent = speedometer

local speedBarTrackCorner = Instance.new("UICorner")
speedBarTrackCorner.CornerRadius = UDim.new(1, 0)
speedBarTrackCorner.Parent = speedBarTrack

local speedBarFill = Instance.new("Frame")
speedBarFill.Name = "Fill"
speedBarFill.Size = UDim2.fromScale(0, 1)
speedBarFill.BackgroundColor3 = Color3.fromRGB(255, 206, 38)
speedBarFill.BorderSizePixel = 0
speedBarFill.Parent = speedBarTrack

local speedBarFillCorner = Instance.new("UICorner")
speedBarFillCorner.CornerRadius = UDim.new(1, 0)
speedBarFillCorner.Parent = speedBarFill

local farePanel = Instance.new("Frame")
farePanel.Name = "FarePanel"
farePanel.AnchorPoint = Vector2.new(0, 1)
farePanel.Position = UDim2.new(0, 18, 1, -182)
farePanel.Size = UDim2.fromOffset(260, 78)
farePanel.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
farePanel.BackgroundTransparency = 0.12
farePanel.BorderSizePixel = 0
farePanel.Visible = false
farePanel.Parent = gui

local farePanelCorner = Instance.new("UICorner")
farePanelCorner.CornerRadius = UDim.new(0, 8)
farePanelCorner.Parent = farePanel

local farePanelStroke = Instance.new("UIStroke")
farePanelStroke.Color = Config.passengerPickupColor
farePanelStroke.Transparency = 0.12
farePanelStroke.Thickness = 2
farePanelStroke.Parent = farePanel

local fareMode = Instance.new("TextLabel")
fareMode.Name = "Mode"
fareMode.BackgroundTransparency = 1
fareMode.Position = UDim2.fromOffset(14, 8)
fareMode.Size = UDim2.new(1, -108, 0, 18)
fareMode.Font = Enum.Font.GothamBold
fareMode.Text = "PICKUP"
fareMode.TextColor3 = Config.passengerPickupColor
fareMode.TextSize = 14
fareMode.TextXAlignment = Enum.TextXAlignment.Left
fareMode.Parent = farePanel

local fareDistance = Instance.new("TextLabel")
fareDistance.Name = "Distance"
fareDistance.BackgroundTransparency = 1
fareDistance.Position = UDim2.new(1, -92, 0, 8)
fareDistance.Size = UDim2.fromOffset(78, 18)
fareDistance.Font = Enum.Font.GothamBold
fareDistance.Text = "0 st"
fareDistance.TextColor3 = Config.passengerPickupColor
fareDistance.TextSize = 14
fareDistance.TextXAlignment = Enum.TextXAlignment.Right
fareDistance.Parent = farePanel

local fareStatus = Instance.new("TextLabel")
fareStatus.Name = "Status"
fareStatus.BackgroundTransparency = 1
fareStatus.Position = UDim2.fromOffset(14, 30)
fareStatus.Size = UDim2.new(1, -28, 0, 22)
fareStatus.Font = Enum.Font.GothamSemibold
fareStatus.Text = "Find a pickup"
fareStatus.TextColor3 = Color3.fromRGB(245, 245, 245)
fareStatus.TextSize = 16
fareStatus.TextWrapped = true
fareStatus.TextXAlignment = Enum.TextXAlignment.Left
fareStatus.Parent = farePanel

local fareCompleted = Instance.new("TextLabel")
fareCompleted.Name = "Completed"
fareCompleted.BackgroundTransparency = 1
fareCompleted.Position = UDim2.fromOffset(14, 55)
fareCompleted.Size = UDim2.new(1, -28, 0, 16)
fareCompleted.Font = Enum.Font.GothamSemibold
fareCompleted.Text = "FARES 0"
fareCompleted.TextColor3 = Color3.fromRGB(210, 213, 218)
fareCompleted.TextSize = 12
fareCompleted.TextXAlignment = Enum.TextXAlignment.Left
fareCompleted.Parent = farePanel

local shiftPanel = Instance.new("Frame")
shiftPanel.Name = "ShiftPanel"
shiftPanel.AnchorPoint = Vector2.new(0, 1)
shiftPanel.Position = UDim2.new(0, 18, 1, -266)
shiftPanel.Size = UDim2.fromOffset(260, 78)
shiftPanel.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
shiftPanel.BackgroundTransparency = 0.12
shiftPanel.BorderSizePixel = 0
shiftPanel.Visible = false
shiftPanel.Parent = gui

local shiftPanelCorner = Instance.new("UICorner")
shiftPanelCorner.CornerRadius = UDim.new(0, 8)
shiftPanelCorner.Parent = shiftPanel

local shiftPanelStroke = Instance.new("UIStroke")
shiftPanelStroke.Color = Color3.fromRGB(255, 206, 38)
shiftPanelStroke.Transparency = 0.12
shiftPanelStroke.Thickness = 2
shiftPanelStroke.Parent = shiftPanel

local shiftPhaseLabel = Instance.new("TextLabel")
shiftPhaseLabel.Name = "Phase"
shiftPhaseLabel.BackgroundTransparency = 1
shiftPhaseLabel.Position = UDim2.fromOffset(14, 8)
shiftPhaseLabel.Size = UDim2.new(1, -112, 0, 18)
shiftPhaseLabel.Font = Enum.Font.GothamBold
shiftPhaseLabel.Text = "SHIFT"
shiftPhaseLabel.TextColor3 = Color3.fromRGB(255, 206, 38)
shiftPhaseLabel.TextSize = 14
shiftPhaseLabel.TextXAlignment = Enum.TextXAlignment.Left
shiftPhaseLabel.Parent = shiftPanel

local shiftTimerLabel = Instance.new("TextLabel")
shiftTimerLabel.Name = "Timer"
shiftTimerLabel.BackgroundTransparency = 1
shiftTimerLabel.Position = UDim2.new(1, -92, 0, 8)
shiftTimerLabel.Size = UDim2.fromOffset(78, 18)
shiftTimerLabel.Font = Enum.Font.GothamBold
shiftTimerLabel.Text = "00:00"
shiftTimerLabel.TextColor3 = Color3.fromRGB(255, 206, 38)
shiftTimerLabel.TextSize = 14
shiftTimerLabel.TextXAlignment = Enum.TextXAlignment.Right
shiftTimerLabel.Parent = shiftPanel

local shiftMoneyLabel = Instance.new("TextLabel")
shiftMoneyLabel.Name = "Money"
shiftMoneyLabel.BackgroundTransparency = 1
shiftMoneyLabel.Position = UDim2.fromOffset(14, 29)
shiftMoneyLabel.Size = UDim2.new(1, -28, 0, 20)
shiftMoneyLabel.Font = Enum.Font.GothamSemibold
shiftMoneyLabel.Text = "Shift $0"
shiftMoneyLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
shiftMoneyLabel.TextSize = 16
shiftMoneyLabel.TextXAlignment = Enum.TextXAlignment.Left
shiftMoneyLabel.Parent = shiftPanel

local shiftDetailsLabel = Instance.new("TextLabel")
shiftDetailsLabel.Name = "Details"
shiftDetailsLabel.BackgroundTransparency = 1
shiftDetailsLabel.Position = UDim2.fromOffset(14, 52)
shiftDetailsLabel.Size = UDim2.new(1, -28, 0, 16)
shiftDetailsLabel.Font = Enum.Font.GothamSemibold
shiftDetailsLabel.Text = "Fare $0  •  Damage -$0  •  Fares 0"
shiftDetailsLabel.TextColor3 = Color3.fromRGB(210, 213, 218)
shiftDetailsLabel.TextSize = 12
shiftDetailsLabel.TextXAlignment = Enum.TextXAlignment.Left
shiftDetailsLabel.TextTruncate = Enum.TextTruncate.AtEnd
shiftDetailsLabel.Parent = shiftPanel

local payoutPanel = Instance.new("Frame")
payoutPanel.Name = "PayoutPanel"
payoutPanel.AnchorPoint = Vector2.new(0.5, 0.5)
payoutPanel.Position = UDim2.fromScale(0.5, 0.5)
payoutPanel.Size = UDim2.fromOffset(480, 300)
payoutPanel.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
payoutPanel.BackgroundTransparency = 0.08
payoutPanel.BorderSizePixel = 0
payoutPanel.Visible = false
payoutPanel.ZIndex = 20
payoutPanel.Parent = gui

local payoutPanelCorner = Instance.new("UICorner")
payoutPanelCorner.CornerRadius = UDim.new(0, 10)
payoutPanelCorner.Parent = payoutPanel

local payoutPanelStroke = Instance.new("UIStroke")
payoutPanelStroke.Color = Color3.fromRGB(255, 206, 38)
payoutPanelStroke.Transparency = 0.08
payoutPanelStroke.Thickness = 2
payoutPanelStroke.Parent = payoutPanel

local payoutTitle = Instance.new("TextLabel")
payoutTitle.BackgroundTransparency = 1
payoutTitle.Position = UDim2.fromOffset(20, 16)
payoutTitle.Size = UDim2.new(1, -40, 0, 28)
payoutTitle.Font = Enum.Font.GothamBold
payoutTitle.Text = "END OF SHIFT PAYOUT"
payoutTitle.TextColor3 = Color3.fromRGB(255, 206, 38)
payoutTitle.TextSize = 22
payoutTitle.TextXAlignment = Enum.TextXAlignment.Left
payoutTitle.ZIndex = 21
payoutTitle.Parent = payoutPanel

local payoutBreakdown = Instance.new("TextLabel")
payoutBreakdown.BackgroundTransparency = 1
payoutBreakdown.Position = UDim2.fromOffset(20, 58)
payoutBreakdown.Size = UDim2.new(1, -40, 0, 186)
payoutBreakdown.Font = Enum.Font.GothamSemibold
payoutBreakdown.TextColor3 = Color3.fromRGB(240, 243, 247)
payoutBreakdown.TextSize = 20
payoutBreakdown.TextXAlignment = Enum.TextXAlignment.Left
payoutBreakdown.TextYAlignment = Enum.TextYAlignment.Top
payoutBreakdown.TextWrapped = true
payoutBreakdown.Text = ""
payoutBreakdown.ZIndex = 21
payoutBreakdown.Parent = payoutPanel

local payoutDismiss = Instance.new("TextLabel")
payoutDismiss.BackgroundTransparency = 1
payoutDismiss.Position = UDim2.new(0, 20, 1, -34)
payoutDismiss.Size = UDim2.new(1, -40, 0, 20)
payoutDismiss.Font = Enum.Font.Gotham
payoutDismiss.Text = "Press Enter / Space / A to continue"
payoutDismiss.TextColor3 = Color3.fromRGB(190, 196, 203)
payoutDismiss.TextSize = 14
payoutDismiss.TextXAlignment = Enum.TextXAlignment.Left
payoutDismiss.ZIndex = 21
payoutDismiss.Parent = payoutPanel

local displayedSpeed = 0
local lastSpeedText = nil
local lastSpeedCab = nil
local lastFareMode = nil
local lastFareStatus = nil
local lastFareDistance = nil
local lastFareCompleted = nil
local lastFareSummary = nil
local lastShiftHeader = nil
local lastShiftTimer = nil
local lastShiftMoney = nil
local lastShiftDetails = nil
local payoutSummaryState = {
	eventId = 0,
	visible = false,
	dismissAt = 0,
	displayGross = 0,
	displayNet = 0,
	target = nil,
}

local function formatShiftClock(seconds)
	local clamped = math.max(0, math.floor((seconds or 0) + 0.5))
	local minutes = math.floor(clamped / 60)
	local remainder = clamped % 60
	return string.format("%02d:%02d", minutes, remainder)
end

local function getSpeedometerMaxSpeed()
	return math.max(
		type(Config.carMaxForward) == "number" and Config.carMaxForward or 0,
		type(Config.carDriftBoostMaxSpeed) == "number" and Config.carDriftBoostMaxSpeed or 0,
		type(Config.carLandingBoostMaxSpeed) == "number" and Config.carLandingBoostMaxSpeed or 0,
		1
	)
end

local function updateSpeedometer(dt)
	local cab = getDrivenCab()
	if cab ~= lastSpeedCab then
		lastSpeedCab = cab
		displayedSpeed = 0
		lastSpeedText = nil
	end

	speedometer.Visible = cab ~= nil
	if not cab then
		speedBarFill.Size = UDim2.fromScale(0, 1)
		return
	end

	local targetSpeed = getNumberAttribute(cab, Config.carSpeedAttribute) or 0
	local alpha = getAlpha(16, math.min(dt, 0.1))
	displayedSpeed += (targetSpeed - displayedSpeed) * alpha

	if displayedSpeed < 0.5 and targetSpeed < 0.5 then
		displayedSpeed = 0
	end

	local speedText = string.format("%03d", math.floor(displayedSpeed + 0.5))
	if speedText ~= lastSpeedText then
		speedValue.Text = speedText
		lastSpeedText = speedText
	end

	speedBarFill.Size = UDim2.fromScale(math.clamp(displayedSpeed / getSpeedometerMaxSpeed(), 0, 1), 1)
end

local function updateFarePanel()
	local cab = getDrivenCab()
	farePanel.Visible = cab ~= nil
	if not cab then
		return
	end

	local mode = getStringAttribute(cab, Config.passengerFareModeAttribute) or "pickup"
	local status = getStringAttribute(cab, Config.passengerFareStatusAttribute) or "Find a pickup"
	local distance = getNumberAttribute(cab, Config.passengerFareDistanceAttribute) or 0
	local completed = getNumberAttribute(cab, Config.passengerFareCompletedAttribute) or 0
	local fareEstimate = getNumberAttribute(cab, Config.passengerFareEstimateAttribute) or 0
	local fareActiveValue = getNumberAttribute(cab, Config.passengerFareActiveValueAttribute) or 0
	local farePayout = getNumberAttribute(cab, Config.passengerFarePayoutAttribute) or 0
	local fareResultStatus = getStringAttribute(cab, Config.passengerFareResultStatusAttribute) or "idle"
	local fareDamageCollisions = getNumberAttribute(cab, Config.passengerFareDamageCollisionsAttribute) or 0
	local fareDamagePoints = getNumberAttribute(cab, Config.passengerFareDamagePointsAttribute) or 0
	local modeText = "PICKUP"
	local modeColor = Config.passengerPickupColor

	if mode == "delivery" then
		modeText = "DELIVER"
		modeColor = Config.passengerDeliveryColor
	elseif mode == "boarding" then
		modeText = "BOARDING"
		modeColor = Color3.fromRGB(255, 206, 38)
	end

	if modeText ~= lastFareMode then
		fareMode.Text = modeText
		lastFareMode = modeText
	end

	if status ~= lastFareStatus then
		fareStatus.Text = status
		lastFareStatus = status
	end

	local roundedDistance = math.max(0, math.floor(distance + 0.5))
	if roundedDistance ~= lastFareDistance then
		fareDistance.Text = string.format("%d st", roundedDistance)
		lastFareDistance = roundedDistance
	end

	local roundedCompleted = math.max(0, math.floor(completed + 0.5))
	local roundedEstimate = math.max(0, math.floor(fareEstimate + 0.5))
	local roundedActiveValue = math.max(0, math.floor(fareActiveValue + 0.5))
	local roundedPayout = math.max(0, math.floor(farePayout + 0.5))
	local roundedDamageCollisions = math.max(0, math.floor(fareDamageCollisions + 0.5))
	local roundedDamagePoints = math.max(0, math.floor(fareDamagePoints + 0.5))
	local summary = string.format("FARES %d  •  EST $%d", roundedCompleted, roundedEstimate)
	if mode == "delivery" then
		summary = string.format(
			"FARES %d  •  ACTIVE $%d  •  DMG %d (%d)",
			roundedCompleted,
			roundedActiveValue,
			roundedDamagePoints,
			roundedDamageCollisions
		)
	end
	if fareResultStatus == "completed" then
		summary = string.format("FARES %d  •  LAST +$%d", roundedCompleted, roundedPayout)
	elseif fareResultStatus == "failed" then
		summary = string.format("FARES %d  •  LAST FAILED", roundedCompleted)
	end

	if summary ~= lastFareSummary or roundedCompleted ~= lastFareCompleted then
		fareCompleted.Text = summary
		lastFareSummary = summary
		lastFareCompleted = roundedCompleted
	end

	fareMode.TextColor3 = modeColor
	fareDistance.TextColor3 = modeColor
	farePanelStroke.Color = modeColor
end

local function updateShiftPanel()
	local phaseRaw = player:GetAttribute(Config.shiftPhaseAttribute)
	local phase = type(phaseRaw) == "string" and phaseRaw or "Preparing"
	local timeRemaining = player:GetAttribute(Config.shiftTimeRemainingAttribute)
	local shiftMoney = player:GetAttribute(Config.shiftGrossMoneyAttribute)
	local cab = getDrivenCab()

	shiftPanel.Visible = type(phaseRaw) == "string" or cab ~= nil

	local phaseText = string.upper(phase)
	local phaseColor = Color3.fromRGB(255, 206, 38)
	if phase == "Active" then
		phaseColor = Color3.fromRGB(90, 220, 124)
	elseif phase == "Ending" then
		phaseColor = Color3.fromRGB(255, 152, 58)
	elseif phase == "Intermission" then
		phaseColor = Color3.fromRGB(110, 176, 255)
	end

	local timerText = formatShiftClock(type(timeRemaining) == "number" and timeRemaining or 0)
	local moneyText = string.format("Shift $%d", math.max(0, math.floor((type(shiftMoney) == "number" and shiftMoney or 0) + 0.5)))

	local activeFare = cab and (getNumberAttribute(cab, Config.passengerFareActiveValueAttribute) or 0) or 0
	local damagePenalty = cab and (getNumberAttribute(cab, Config.passengerFareDamagePenaltyAttribute) or 0) or 0
	local completedFares = cab and (getNumberAttribute(cab, Config.passengerFareCompletedAttribute) or 0) or 0
	local destination = cab and (getStringAttribute(cab, Config.passengerDestinationAttribute) or "No destination")
		or "No destination"
	local detailsText = string.format(
		"%s  •  Fare $%d  •  Damage -$%d  •  Fares %d",
		destination,
		math.max(0, math.floor(activeFare + 0.5)),
		math.max(0, math.floor(damagePenalty + 0.5)),
		math.max(0, math.floor(completedFares + 0.5))
	)

	if phaseText ~= lastShiftHeader then
		shiftPhaseLabel.Text = phaseText
		lastShiftHeader = phaseText
	end
	if timerText ~= lastShiftTimer then
		shiftTimerLabel.Text = timerText
		lastShiftTimer = timerText
	end
	if moneyText ~= lastShiftMoney then
		shiftMoneyLabel.Text = moneyText
		lastShiftMoney = moneyText
	end
	if detailsText ~= lastShiftDetails then
		shiftDetailsLabel.Text = detailsText
		lastShiftDetails = detailsText
	end

	shiftPhaseLabel.TextColor3 = phaseColor
	shiftTimerLabel.TextColor3 = phaseColor
	shiftPanelStroke.Color = phaseColor
end

local function hidePayoutPanel()
	payoutSummaryState.visible = false
	payoutPanel.Visible = false
end

local function updatePayoutPanel(dt)
	local eventId = player:GetAttribute(Config.shiftPayoutSummaryEventIdAttribute)
	if type(eventId) == "number" and eventId > payoutSummaryState.eventId then
		payoutSummaryState.eventId = eventId
		payoutSummaryState.target = {
			fareTotals = math.max(player:GetAttribute(Config.shiftPayoutFareTotalsAttribute) or 0, 0),
			bonuses = math.max(player:GetAttribute(Config.shiftPayoutBonusesAttribute) or 0, 0),
			damagePenalties = math.max(player:GetAttribute(Config.shiftPayoutDamagePenaltiesAttribute) or 0, 0),
			medallionFeeRate = math.max(player:GetAttribute(Config.shiftPayoutMedallionFeeRateAttribute) or 0, 0),
			medallionFeeAmount = math.max(player:GetAttribute(Config.shiftPayoutMedallionFeeAmountAttribute) or 0, 0),
			netDeposit = math.max(player:GetAttribute(Config.shiftPayoutNetDepositAttribute) or 0, 0),
			grossEarnings = math.max(player:GetAttribute(Config.shiftGrossMoneyAttribute) or 0, 0),
		}
		payoutSummaryState.displayGross = 0
		payoutSummaryState.displayNet = 0
		payoutSummaryState.visible = true
		payoutSummaryState.dismissAt = os.clock() + math.max(Config.shiftPayoutDismissSeconds or 10, 3)
		payoutPanel.Visible = true
	end

	if not payoutSummaryState.visible or not payoutSummaryState.target then
		return
	end

	if os.clock() >= payoutSummaryState.dismissAt then
		hidePayoutPanel()
		return
	end

	local alpha = getAlpha(6, math.min(dt, 0.1))
	payoutSummaryState.displayGross += (payoutSummaryState.target.grossEarnings - payoutSummaryState.displayGross) * alpha
	payoutSummaryState.displayNet += (payoutSummaryState.target.netDeposit - payoutSummaryState.displayNet) * alpha

	local grossDisplay = math.floor(payoutSummaryState.displayGross + 0.5)
	local netDisplay = math.floor(payoutSummaryState.displayNet + 0.5)
	local feeRatePercent = math.floor(payoutSummaryState.target.medallionFeeRate * 100 + 0.5)

	payoutBreakdown.Text = string.format(
		"Gross shift earnings:  $%d\nFare totals:            $%d\nBonuses:                +$%d\nDamage penalties:       -$%d\nMedallion fee (%d%%):    -$%d\n\nNet bank deposit:       $%d",
		grossDisplay,
		math.floor(payoutSummaryState.target.fareTotals + 0.5),
		math.floor(payoutSummaryState.target.bonuses + 0.5),
		math.floor(payoutSummaryState.target.damagePenalties + 0.5),
		feeRatePercent,
		math.floor(payoutSummaryState.target.medallionFeeAmount + 0.5),
		netDisplay
	)

	local remaining = math.max(0, math.ceil(payoutSummaryState.dismissAt - os.clock()))
	payoutDismiss.Text = string.format("Press Enter / Space / A to continue (%ds)", remaining)
end

RunService.RenderStepped:Connect(function(dt)
	updateSpeedometer(dt)
	updateFarePanel()
	updateShiftPanel()
	updatePayoutPanel(dt)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not payoutSummaryState.visible then
		return
	end

	if input.KeyCode == Enum.KeyCode.Return
		or input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.ButtonA
	then
		hidePayoutPanel()
	end
end)

local function isDebugPanelAvailable()
	return Config.debugPanelEnabled == true
		and (not Config.debugPanelStudioOnly or RunService:IsStudio())
end

local function normalizeDebugValue(value, property)
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

local function formatDebugValue(value, property)
	local step = property.step
	if type(step) == "number" then
		if step >= 1 then
			return string.format("%.0f", value)
		elseif step >= 0.1 then
			return string.format("%.1f", value)
		elseif step >= 0.01 then
			return string.format("%.2f", value)
		end
	end

	return string.format("%.3f", value)
end

local cabVisualDebugProperties = {
	carVisualResponsiveness = true,
	carVisualSnapDistance = true,
	carVisualInterpolationDelay = true,
	carVisualMaxExtrapolationTime = true,
	carPitchFollow = true,
	carRollFollow = true,
	carMaxPitchDegrees = true,
	carGroundMaxRollDegrees = true,
	carDriftLeanDegrees = true,
	carDriftLeanFullSpeed = true,
	carDriftLeanFollow = true,
	carDriveLeanDegrees = true,
	carDriveLeanMinSpeed = true,
	carDriveLeanFullSpeed = true,
	carDriveLeanFollow = true,
	carBoostWheelieDegrees = true,
	carBoostWheelieDuration = true,
	carBoostWheelieReturnDuration = true,
	carBoostWheelieFollow = true,
	carLandingBounceMinSpeed = true,
	carLandingBounceMaxSpeed = true,
	carLandingBounceImpulse = true,
	carLandingBounceSpring = true,
	carLandingBounceDamping = true,
	carLandingBounceMaxOffset = true,
}

local function getDebugPropertyTab(property)
	if string.sub(property.key, 1, 6) == "camera" then
		return "Camera"
	end

	if string.sub(property.key, 1, 9) == "passenger" then
		return "Passengers"
	end

	if cabVisualDebugProperties[property.key] then
		return "Visual"
	end

	return "Cab"
end

local function createDebugPanel()
	if not isDebugPanelAvailable() then
		return
	end

	local debugTuneRemote = ReplicatedStorage:WaitForChild(Config.debugTuneRemoteName, 10)
	if not debugTuneRemote or not debugTuneRemote:IsA("RemoteEvent") then
		return
	end

	local properties = {}
	for _, property in ipairs(Config.debugTuningProperties or {}) do
		if type(property) == "table"
			and type(property.key) == "string"
			and type(property.label) == "string"
			and type(Config[property.key]) == "number"
			and normalizeDebugValue(Config[property.key], property) ~= nil
		then
			table.insert(properties, property)
		end
	end

	if #properties == 0 then
		return
	end

	local tabNames = { "Cab", "Visual", "Passengers", "Camera" }
	local propertiesByTab = {
		Cab = {},
		Visual = {},
		Passengers = {},
		Camera = {},
	}

	for _, property in ipairs(properties) do
		table.insert(propertiesByTab[getDebugPropertyTab(property)], property)
	end

	local debugValues = {}
	local rowsByKey = {}
	local activeSlider = nil
	local activeTab = "Cab"
	local scrollsByTab = {}
	local tabButtons = {}
	local tabPadding = 8
	local visibleTabCount = 0

	for _, tabName in ipairs(tabNames) do
		if #propertiesByTab[tabName] > 0 then
			visibleTabCount += 1
			if #propertiesByTab[activeTab] == 0 then
				activeTab = tabName
			end
		end
	end

	local toggle = Instance.new("TextButton")
	toggle.Name = "DebugToggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -16, 0, 16)
	toggle.Size = UDim2.fromOffset(92, 34)
	toggle.BackgroundColor3 = Color3.fromRGB(255, 206, 38)
	toggle.BorderSizePixel = 0
	toggle.TextColor3 = Color3.fromRGB(20, 20, 24)
	toggle.TextSize = 16
	toggle.Font = Enum.Font.GothamBold
	toggle.Text = "Tune"
	toggle.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "DebugPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 58)
	panel.Size = UDim2.fromOffset(380, 520)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
	panel.BackgroundTransparency = 0.04
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(80, 84, 92)
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 10)
	title.Size = UDim2.new(1, -216, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.Text = "Debug Tuning"
	title.TextColor3 = Color3.fromRGB(245, 245, 245)
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local copyButton = Instance.new("TextButton")
	copyButton.Name = "CopyTab"
	copyButton.AnchorPoint = Vector2.new(1, 0)
	copyButton.Position = UDim2.new(1, -104, 0, 10)
	copyButton.Size = UDim2.fromOffset(86, 28)
	copyButton.BackgroundColor3 = Color3.fromRGB(45, 49, 56)
	copyButton.BorderSizePixel = 0
	copyButton.Font = Enum.Font.GothamBold
	copyButton.Text = "Copy"
	copyButton.TextColor3 = Color3.fromRGB(245, 245, 245)
	copyButton.TextSize = 13
	copyButton.Parent = panel

	local copyCorner = Instance.new("UICorner")
	copyCorner.CornerRadius = UDim.new(0, 6)
	copyCorner.Parent = copyButton

	local resetAll = Instance.new("TextButton")
	resetAll.Name = "ResetAll"
	resetAll.AnchorPoint = Vector2.new(1, 0)
	resetAll.Position = UDim2.new(1, -12, 0, 10)
	resetAll.Size = UDim2.fromOffset(80, 28)
	resetAll.BackgroundColor3 = Color3.fromRGB(45, 49, 56)
	resetAll.BorderSizePixel = 0
	resetAll.Font = Enum.Font.GothamBold
	resetAll.Text = "Reset"
	resetAll.TextColor3 = Color3.fromRGB(245, 245, 245)
	resetAll.TextSize = 13
	resetAll.Parent = panel

	local resetAllCorner = Instance.new("UICorner")
	resetAllCorner.CornerRadius = UDim.new(0, 6)
	resetAllCorner.Parent = resetAll

	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.Position = UDim2.fromOffset(10, 48)
	tabBar.Size = UDim2.new(1, -20, 0, 30)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, tabPadding)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local copyBox = Instance.new("TextBox")
	copyBox.Name = "CopyText"
	copyBox.Position = UDim2.new(0, 10, 1, -106)
	copyBox.Size = UDim2.new(1, -20, 0, 96)
	copyBox.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
	copyBox.BorderSizePixel = 0
	copyBox.ClearTextOnFocus = false
	copyBox.Font = Enum.Font.Code
	copyBox.MultiLine = true
	copyBox.Text = ""
	copyBox.TextColor3 = Color3.fromRGB(235, 236, 238)
	copyBox.TextEditable = true
	copyBox.TextSize = 12
	copyBox.TextXAlignment = Enum.TextXAlignment.Left
	copyBox.TextYAlignment = Enum.TextYAlignment.Top
	copyBox.Visible = false
	copyBox.Parent = panel

	local copyBoxCorner = Instance.new("UICorner")
	copyBoxCorner.CornerRadius = UDim.new(0, 6)
	copyBoxCorner.Parent = copyBox

	local function setCopyBoxVisible(visible)
		copyBox.Visible = visible
		local bottomOffset = if visible then 204 else 98
		for _, scroll in pairs(scrollsByTab) do
			scroll.Size = UDim2.new(1, -20, 1, -bottomOffset)
		end
	end

	for _, tabName in ipairs(tabNames) do
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = tabName .. "TuningRows"
		scroll.Position = UDim2.fromOffset(10, 88)
		scroll.Size = UDim2.new(1, -20, 1, -98)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 6
		scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 206, 38)
		scroll.ScrollBarImageTransparency = 0.12
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.CanvasSize = UDim2.fromOffset(0, 0)
		scroll.Visible = tabName == activeTab
		scroll.Parent = panel
		scrollsByTab[tabName] = scroll

		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 8)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = scroll

		local function updateCanvasSize()
			scroll.CanvasSize = UDim2.fromOffset(0, list.AbsoluteContentSize.Y + 8)
		end

		list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
		task.defer(updateCanvasSize)
	end

	local function setActiveTab(tabName)
		activeTab = tabName
		copyButton.Text = "Copy " .. activeTab
		setCopyBoxVisible(false)

		for _, scroll in pairs(scrollsByTab) do
			scroll.Visible = false
		end

		local activeScroll = scrollsByTab[activeTab]
		if activeScroll then
			activeScroll.Visible = true
		end

		for buttonTabName, tabButton in pairs(tabButtons) do
			local isActive = buttonTabName == activeTab
			tabButton.BackgroundColor3 = if isActive
				then Color3.fromRGB(255, 206, 38)
				else Color3.fromRGB(45, 49, 56)
			tabButton.TextColor3 = if isActive
				then Color3.fromRGB(20, 20, 24)
				else Color3.fromRGB(245, 245, 245)
		end
	end

	for index, tabName in ipairs(tabNames) do
		if #propertiesByTab[tabName] > 0 then
			local tabButton = Instance.new("TextButton")
			tabButton.Name = tabName .. "Tab"
			tabButton.LayoutOrder = index
			tabButton.Size = UDim2.new(
				1 / visibleTabCount,
				-tabPadding * (visibleTabCount - 1) / visibleTabCount,
				1,
				0
			)
			tabButton.BackgroundColor3 = Color3.fromRGB(45, 49, 56)
			tabButton.BorderSizePixel = 0
			tabButton.Font = Enum.Font.GothamBold
			tabButton.Text = tabName
			tabButton.TextColor3 = Color3.fromRGB(245, 245, 245)
			tabButton.TextSize = 13
			tabButton.Parent = tabBar
			tabButtons[tabName] = tabButton

			local tabCorner = Instance.new("UICorner")
			tabCorner.CornerRadius = UDim.new(0, 6)
			tabCorner.Parent = tabButton

			tabButton.MouseButton1Click:Connect(function()
				setActiveTab(tabName)
			end)
		end
	end

	setActiveTab(activeTab)

	local function updateRow(rowState)
		local property = rowState.property
		local value = debugValues[property.key]
		if type(value) ~= "number" then
			value = normalizeDebugValue(Config[property.key], property) or property.min or 0
			debugValues[property.key] = value
		end

		if not rowState.valueBox:IsFocused() then
			rowState.valueBox.Text = formatDebugValue(value, property)
		end

		local minValue = property.min
		local maxValue = property.max
		local alpha = 0
		if maxValue > minValue then
			alpha = math.clamp((value - minValue) / (maxValue - minValue), 0, 1)
		end

		rowState.fill.Size = UDim2.fromScale(alpha, 1)
		rowState.knob.Position = UDim2.new(alpha, 0, 0.5, 0)
	end

	local function setDebugValue(key, value)
		local rowState = rowsByKey[key]
		if not rowState then
			return
		end

		local normalizedValue = normalizeDebugValue(value, rowState.property)
		if normalizedValue == nil then
			updateRow(rowState)
			return
		end

		debugValues[key] = normalizedValue
		Config[key] = normalizedValue
		updateRow(rowState)
	end

	local function buildTabCopyText(tabName)
		local lines = { string.format("-- Cab87 %s tuning", tabName) }
		for _, property in ipairs(propertiesByTab[tabName] or {}) do
			local value = debugValues[property.key]
			if type(value) ~= "number" then
				value = normalizeDebugValue(Config[property.key], property) or property.min or 0
			end

			table.insert(lines, string.format("%s = %s,", property.key, formatDebugValue(value, property)))
		end

		return table.concat(lines, "\n")
	end

	local function trySetClipboard(text)
		local ok = pcall(function()
			GuiService:SetClipboard(text)
		end)

		return ok
	end

	local copyStatusVersion = 0
	local function showCopyStatus(text)
		copyStatusVersion += 1
		local version = copyStatusVersion
		copyButton.Text = text

		task.delay(1.4, function()
			if copyButton.Parent and copyStatusVersion == version then
				copyButton.Text = "Copy " .. activeTab
			end
		end)
	end

	local function selectCopyText(text)
		copyBox.Text = text
		setCopyBoxVisible(true)
		copyBox:CaptureFocus()

		task.defer(function()
			copyBox.SelectionStart = 1
			copyBox.CursorPosition = #copyBox.Text + 1
		end)
	end

	local function requestDebugValue(property, value)
		local normalizedValue = normalizeDebugValue(value, property)
		if normalizedValue == nil then
			return
		end

		setDebugValue(property.key, normalizedValue)
		debugTuneRemote:FireServer("Set", property.key, normalizedValue)
	end

	local function updateSlider(rowState, screenX)
		local property = rowState.property
		local track = rowState.track
		local trackWidth = math.max(track.AbsoluteSize.X, 1)
		local alpha = math.clamp((screenX - track.AbsolutePosition.X) / trackWidth, 0, 1)
		local value = property.min + (property.max - property.min) * alpha
		requestDebugValue(property, value)
	end

	local function beginSlider(rowState, input)
		activeSlider = {
			rowState = rowState,
			input = input,
		}
		updateSlider(rowState, input.Position.X)
	end

	local function buildRow(property, index, parent)
		local row = Instance.new("Frame")
		row.Name = property.key
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -8, 0, 68)
		row.BackgroundColor3 = Color3.fromRGB(30, 33, 38)
		row.BorderSizePixel = 0
		row.Parent = parent

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local name = Instance.new("TextLabel")
		name.Name = "Name"
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(10, 7)
		name.Size = UDim2.new(1, -136, 0, 22)
		name.Font = Enum.Font.GothamSemibold
		name.Text = property.label
		name.TextColor3 = Color3.fromRGB(235, 236, 238)
		name.TextSize = 14
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = row

		local reset = Instance.new("TextButton")
		reset.Name = "Reset"
		reset.AnchorPoint = Vector2.new(1, 0)
		reset.Position = UDim2.new(1, -10, 0, 7)
		reset.Size = UDim2.fromOffset(52, 24)
		reset.BackgroundColor3 = Color3.fromRGB(48, 52, 60)
		reset.BorderSizePixel = 0
		reset.Font = Enum.Font.GothamBold
		reset.Text = "Reset"
		reset.TextColor3 = Color3.fromRGB(235, 236, 238)
		reset.TextSize = 11
		reset.Parent = row

		local resetCorner = Instance.new("UICorner")
		resetCorner.CornerRadius = UDim.new(0, 5)
		resetCorner.Parent = reset

		local valueBox = Instance.new("TextBox")
		valueBox.Name = "Value"
		valueBox.AnchorPoint = Vector2.new(1, 0)
		valueBox.Position = UDim2.new(1, -68, 0, 7)
		valueBox.Size = UDim2.fromOffset(62, 24)
		valueBox.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
		valueBox.BorderSizePixel = 0
		valueBox.ClearTextOnFocus = false
		valueBox.Font = Enum.Font.GothamMedium
		valueBox.TextColor3 = Color3.fromRGB(255, 206, 38)
		valueBox.TextSize = 12
		valueBox.TextXAlignment = Enum.TextXAlignment.Center
		valueBox.Parent = row

		local valueCorner = Instance.new("UICorner")
		valueCorner.CornerRadius = UDim.new(0, 5)
		valueCorner.Parent = valueBox

		local track = Instance.new("Frame")
		track.Name = "Slider"
		track.Active = true
		track.Position = UDim2.fromOffset(10, 43)
		track.Size = UDim2.new(1, -20, 0, 10)
		track.BackgroundColor3 = Color3.fromRGB(58, 63, 72)
		track.BorderSizePixel = 0
		track.Parent = row

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = track

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = Color3.fromRGB(255, 206, 38)
		fill.BorderSizePixel = 0
		fill.Parent = track

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill

		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.Active = true
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Position = UDim2.fromScale(0, 0.5)
		knob.Size = UDim2.fromOffset(16, 22)
		knob.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
		knob.BorderSizePixel = 0
		knob.Parent = track

		local knobCorner = Instance.new("UICorner")
		knobCorner.CornerRadius = UDim.new(0, 5)
		knobCorner.Parent = knob

		local rowState = {
			property = property,
			track = track,
			fill = fill,
			knob = knob,
			valueBox = valueBox,
		}

		rowsByKey[property.key] = rowState
		debugValues[property.key] = normalizeDebugValue(Config[property.key], property) or property.min or 0
		updateRow(rowState)

		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				beginSlider(rowState, input)
			end
		end)

		knob.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				beginSlider(rowState, input)
			end
		end)

		valueBox.FocusLost:Connect(function()
			local value = tonumber(valueBox.Text)
			if value then
				requestDebugValue(property, value)
			else
				updateRow(rowState)
			end
		end)

		reset.MouseButton1Click:Connect(function()
			debugTuneRemote:FireServer("Reset", property.key)
		end)
	end

	for _, tabName in ipairs(tabNames) do
		local scroll = scrollsByTab[tabName]
		for index, property in ipairs(propertiesByTab[tabName]) do
			buildRow(property, index, scroll)
		end
	end

	toggle.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)

	copyButton.MouseButton1Click:Connect(function()
		local copyText = buildTabCopyText(activeTab)
		copyBox.Text = copyText

		if trySetClipboard(copyText) then
			setCopyBoxVisible(false)
			showCopyStatus("Copied")
		else
			selectCopyText(copyText)
			showCopyStatus("Selected")
		end
	end)

	resetAll.MouseButton1Click:Connect(function()
		debugTuneRemote:FireServer("ResetAll")
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.F4 then
			panel.Visible = not panel.Visible
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not activeSlider then
			return
		end

		if input == activeSlider.input or input.UserInputType == Enum.UserInputType.MouseMovement then
			updateSlider(activeSlider.rowState, input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not activeSlider then
			return
		end

		if input == activeSlider.input or input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeSlider = nil
		end
	end)

	debugTuneRemote.OnClientEvent:Connect(function(action, key, value)
		if action == "Set" then
			setDebugValue(key, value)
		elseif action == "Snapshot" and type(key) == "table" then
			for snapshotKey, snapshotValue in pairs(key) do
				setDebugValue(snapshotKey, snapshotValue)
			end
		end
	end)

	debugTuneRemote:FireServer("Snapshot")
end

createDebugPanel()
