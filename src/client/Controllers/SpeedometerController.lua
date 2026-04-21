local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SpeedometerController = {}

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

local function getAlpha(responsiveness, dt)
	if responsiveness <= 0 then
		return 1
	end

	return 1 - math.exp(-responsiveness * dt)
end

local function getSpeedometerMaxSpeed()
	return math.max(
		type(Config.carMaxForward) == "number" and Config.carMaxForward or 0,
		type(Config.carDriftBoostMaxSpeed) == "number" and Config.carDriftBoostMaxSpeed or 0,
		type(Config.carLandingBoostMaxSpeed) == "number" and Config.carLandingBoostMaxSpeed or 0,
		1
	)
end

local function createUi(parentGui)
	local speedometer = Instance.new("Frame")
	speedometer.Name = "Speedometer"
	speedometer.AnchorPoint = Vector2.new(0, 1)
	speedometer.Position = UDim2.new(0, 18, 1, -88)
	speedometer.Size = UDim2.fromOffset(174, 84)
	speedometer.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
	speedometer.BackgroundTransparency = 0.12
	speedometer.BorderSizePixel = 0
	speedometer.Visible = false
	speedometer.Parent = parentGui

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

	return {
		root = speedometer,
		value = speedValue,
		barFill = speedBarFill,
	}
end

function SpeedometerController.start(parentGui, cabTracker)
	local ui = createUi(parentGui)
	local displayedSpeed = 0
	local lastSpeedText = nil
	local lastSpeedCab = nil

	local connection = RunService.RenderStepped:Connect(function(dt)
		local cab = cabTracker.getDrivenCab()
		if cab ~= lastSpeedCab then
			lastSpeedCab = cab
			displayedSpeed = 0
			lastSpeedText = nil
		end

		ui.root.Visible = cab ~= nil
		if not cab then
			ui.barFill.Size = UDim2.fromScale(0, 1)
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
			ui.value.Text = speedText
			lastSpeedText = speedText
		end

		ui.barFill.Size = UDim2.fromScale(math.clamp(displayedSpeed / getSpeedometerMaxSpeed(), 0, 1), 1)
	end)

	return {
		destroy = function()
			connection:Disconnect()
			ui.root:Destroy()
		end,
	}
end

return SpeedometerController
