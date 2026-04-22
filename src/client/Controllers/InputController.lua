local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local InputController = {}

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

local function isGamepadInput(input)
	return input.UserInputType == Enum.UserInputType.Gamepad1
end

function InputController.start()
	local controller = {
		connections = {},
		keyDown = {},
		gamepadSteer = 0,
		gamepadAirPitch = 0,
		gamepadAccel = 0,
		gamepadBrake = 0,
		gamepadDriftButtons = {},
		lastSentThrottle = nil,
		lastSentSteer = nil,
		lastSentDrift = nil,
		lastSentAirPitch = nil,
		sendAccumulator = 0,
		forceSendAccumulator = 0,
	}

	local driveInputRemoteName = Remotes.getClientToServerName("driveInput")
	local driveInputRemote = ReplicatedStorage:WaitForChild(driveInputRemoteName)

	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(controller.connections, connection)
		return connection
	end

	local function getKeyboardAxis(positiveKeyA, positiveKeyB, negativeKeyA, negativeKeyB)
		local positive = (controller.keyDown[positiveKeyA] or controller.keyDown[positiveKeyB]) and 1 or 0
		local negative = (controller.keyDown[negativeKeyA] or controller.keyDown[negativeKeyB]) and 1 or 0
		return positive - negative
	end

	local function isDriftHeld()
		if controller.keyDown[Enum.KeyCode.LeftShift] or controller.keyDown[Enum.KeyCode.RightShift] then
			return true
		end

		for _, isHeld in pairs(controller.gamepadDriftButtons) do
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
		local gamepadThrottle = controller.gamepadAccel - controller.gamepadBrake
		local throttle = math.clamp(keyboardThrottle + gamepadThrottle, -1, 1)
		local steer = if math.abs(controller.gamepadSteer) > 0 then controller.gamepadSteer else keyboardSteer
		local airPitch = if math.abs(controller.gamepadAirPitch) > 0 then controller.gamepadAirPitch else keyboardAirPitch

		return throttle, math.clamp(steer, -1, 1), isDriftHeld(), math.clamp(airPitch, -1, 1)
	end

	local function sendDriveState(force)
		local throttle, steer, drift, airPitch = getDriveState()
		if not force
			and throttle == controller.lastSentThrottle
			and steer == controller.lastSentSteer
			and drift == controller.lastSentDrift
			and airPitch == controller.lastSentAirPitch
		then
			return
		end

		controller.lastSentThrottle = throttle
		controller.lastSentSteer = steer
		controller.lastSentDrift = drift
		controller.lastSentAirPitch = airPitch
		driveInputRemote:FireServer("Drive", throttle, steer, drift, airPitch)
	end

	local function setGamepadDriftButton(keyCode, isHeld)
		if driftGamepadButtons[keyCode] then
			controller.gamepadDriftButtons[keyCode] = isHeld or nil
		end
	end

	local function updateGamepadAnalog(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			controller.gamepadSteer = deadzone(input.Position.X)
			controller.gamepadAirPitch = deadzone(input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			controller.gamepadAccel = math.clamp(math.abs(input.Position.Z), 0, 1)
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			controller.gamepadBrake = math.clamp(math.abs(input.Position.Z), 0, 1)
		end
	end

	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed and not isGamepadInput(input) then
			return
		end

		if driveKeys[input.KeyCode] then
			controller.keyDown[input.KeyCode] = true
		elseif isGamepadInput(input) then
			setGamepadDriftButton(input.KeyCode, true)

			if input.KeyCode == Enum.KeyCode.ButtonR2 then
				controller.gamepadAccel = 1
			elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
				controller.gamepadBrake = 1
			end
		end

		sendDriveState(false)
	end)

	connect(UserInputService.InputEnded, function(input)
		if driveKeys[input.KeyCode] then
			controller.keyDown[input.KeyCode] = nil
		elseif isGamepadInput(input) then
			setGamepadDriftButton(input.KeyCode, false)

			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				controller.gamepadSteer = 0
				controller.gamepadAirPitch = 0
			elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
				controller.gamepadAccel = 0
			elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
				controller.gamepadBrake = 0
			end
		end

		sendDriveState(false)
	end)

	connect(UserInputService.InputChanged, function(input, gameProcessed)
		if gameProcessed and not isGamepadInput(input) then
			return
		end

		if isGamepadInput(input) then
			updateGamepadAnalog(input)
			sendDriveState(false)
		end
	end)

	connect(RunService.Heartbeat, function(dt)
		controller.sendAccumulator += dt
		controller.forceSendAccumulator += dt
		if controller.sendAccumulator >= 1 / 20 then
			controller.sendAccumulator = 0
			local force = controller.forceSendAccumulator >= 0.25
			if force then
				controller.forceSendAccumulator = 0
			end
			sendDriveState(force)
		end
	end)

	function controller:destroy()
		for _, connection in ipairs(self.connections) do
			connection:Disconnect()
		end
		table.clear(self.connections)
		table.clear(self.keyDown)
		table.clear(self.gamepadDriftButtons)
	end

	return controller
end

return InputController
