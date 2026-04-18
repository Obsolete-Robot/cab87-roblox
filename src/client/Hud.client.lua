local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local driveInputRemote = ReplicatedStorage:WaitForChild(Config.driveInputRemoteName)

local keyDown = {}
local gamepadSteer = 0
local gamepadAccel = 0
local gamepadBrake = 0
local gamepadDriftButtons = {}
local lastSentThrottle = nil
local lastSentSteer = nil
local lastSentDrift = nil
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
	local gamepadThrottle = gamepadAccel - gamepadBrake
	local throttle = math.clamp(keyboardThrottle + gamepadThrottle, -1, 1)
	local steer = math.abs(gamepadSteer) > 0 and gamepadSteer or keyboardSteer

	return throttle, math.clamp(steer, -1, 1), isDriftHeld()
end

local function sendDriveState(force)
	local throttle, steer, drift = getDriveState()
	if not force
		and throttle == lastSentThrottle
		and steer == lastSentSteer
		and drift == lastSentDrift
	then
		return
	end

	lastSentThrottle = throttle
	lastSentSteer = steer
	lastSentDrift = drift
	driveInputRemote:FireServer("Drive", throttle, steer, drift)
end

local function setGamepadDriftButton(keyCode, isHeld)
	if driftGamepadButtons[keyCode] then
		gamepadDriftButtons[keyCode] = isHeld or nil
	end
end

local function updateGamepadAnalog(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		gamepadSteer = deadzone(input.Position.X)
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
