local RunService = game:GetService("RunService")

local GameplayStateStore = require(script.Parent.Parent:WaitForChild("GameplayStateStore"))

local ShiftHudController = {}

local function formatShiftClock(seconds)
	local clamped = math.max(0, math.floor((seconds or 0) + 0.5))
	local minutes = math.floor(clamped / 60)
	local remainder = clamped % 60
	return string.format("%02d:%02d", minutes, remainder)
end

local function createUi(parentGui)
	local shiftPanel = Instance.new("Frame")
	shiftPanel.Name = "ShiftPanel"
	shiftPanel.AnchorPoint = Vector2.new(0, 1)
	shiftPanel.Position = UDim2.new(0, 18, 1, -266)
	shiftPanel.Size = UDim2.fromOffset(260, 78)
	shiftPanel.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
	shiftPanel.BackgroundTransparency = 0.12
	shiftPanel.BorderSizePixel = 0
	shiftPanel.Visible = false
	shiftPanel.Parent = parentGui

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

	return {
		root = shiftPanel,
		stroke = shiftPanelStroke,
		phase = shiftPhaseLabel,
		timer = shiftTimerLabel,
		money = shiftMoneyLabel,
		details = shiftDetailsLabel,
	}
end

function ShiftHudController.start(parentGui, cabTracker)
	local ui = createUi(parentGui)
	local lastShiftHeader = nil
	local lastShiftTimer = nil
	local lastShiftMoney = nil
	local lastShiftDetails = nil

	local connection = RunService.RenderStepped:Connect(function()
		local cab = cabTracker.getDrivenCab()
		local shiftState = GameplayStateStore.getShiftState()
		local cabState = GameplayStateStore.getCabState(cab)
		local fareState = cabState and cabState.fare or nil
		local phase = shiftState and shiftState.phase or "Preparing"
		local timeRemaining = shiftState and shiftState.timeRemaining or 0
		local shiftMoney = shiftState and shiftState.grossMoney or 0
		local bankMoney = shiftState and shiftState.bankMoney or 0

		ui.root.Visible = shiftState ~= nil or cab ~= nil

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
		local moneyText = string.format(
			"Shift $%d  •  Bank $%d",
			math.max(0, math.floor((type(shiftMoney) == "number" and shiftMoney or 0) + 0.5)),
			math.max(0, math.floor((type(bankMoney) == "number" and bankMoney or 0) + 0.5))
		)

		local activeFare = fareState and fareState.activeValue or 0
		local damagePenalty = fareState and fareState.damagePenalty or 0
		local completedFares = cabState and cabState.completedFares or 0
		local destination = cabState and cabState.destinationLabel or "No destination"
		local detailsText = string.format(
			"%s  •  Fare $%d  •  Damage -$%d  •  Fares %d",
			destination,
			math.max(0, math.floor(activeFare + 0.5)),
			math.max(0, math.floor(damagePenalty + 0.5)),
			math.max(0, math.floor(completedFares + 0.5))
		)

		if phaseText ~= lastShiftHeader then
			ui.phase.Text = phaseText
			lastShiftHeader = phaseText
		end
		if timerText ~= lastShiftTimer then
			ui.timer.Text = timerText
			lastShiftTimer = timerText
		end
		if moneyText ~= lastShiftMoney then
			ui.money.Text = moneyText
			lastShiftMoney = moneyText
		end
		if detailsText ~= lastShiftDetails then
			ui.details.Text = detailsText
			lastShiftDetails = detailsText
		end

		ui.phase.TextColor3 = phaseColor
		ui.timer.TextColor3 = phaseColor
		ui.stroke.Color = phaseColor
	end)

	return {
		destroy = function()
			connection:Disconnect()
			ui.root:Destroy()
		end,
	}
end

return ShiftHudController
