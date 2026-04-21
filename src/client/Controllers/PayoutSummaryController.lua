local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameplayStateStore = require(script.Parent.Parent:WaitForChild("GameplayStateStore"))

local PayoutSummaryController = {}

local function getAlpha(responsiveness, dt)
	if responsiveness <= 0 then
		return 1
	end

	return 1 - math.exp(-responsiveness * dt)
end

local function createUi(parentGui)
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
	payoutPanel.Parent = parentGui

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

	return {
		root = payoutPanel,
		breakdown = payoutBreakdown,
		dismiss = payoutDismiss,
	}
end

function PayoutSummaryController.start(parentGui)
	local ui = createUi(parentGui)
	local state = {
		eventId = 0,
		visible = false,
		dismissAt = 0,
		displayGross = 0,
		displayNet = 0,
		target = nil,
	}

	local function hide()
		state.visible = false
		ui.root.Visible = false
	end

	local function showSummary(summary)
		if type(summary) ~= "table" or type(summary.eventId) ~= "number" or summary.eventId <= state.eventId then
			return
		end

		state.eventId = summary.eventId
		state.target = {
			fareTotals = math.max(summary.fareTotals or 0, 0),
			bonuses = math.max(summary.bonuses or 0, 0),
			damagePenalties = math.max(summary.damagePenalties or 0, 0),
			medallionFeeRate = math.max(summary.medallionFeeRate or 0, 0),
			medallionFeeAmount = math.max(summary.medallionFeeAmount or 0, 0),
			netDeposit = math.max(summary.netDeposit or 0, 0),
			grossEarnings = math.max(summary.grossEarnings or 0, 0),
		}
		state.displayGross = 0
		state.displayNet = 0
		state.visible = true
		state.dismissAt = os.clock() + math.max(Config.shiftPayoutDismissSeconds or 10, 3)
		ui.root.Visible = true
	end

	local storeDisconnect = GameplayStateStore.onChanged(function(kind, payload)
		if kind == "payoutSummary" then
			showSummary(payload)
		end
	end)
	showSummary(GameplayStateStore.getPayoutSummary())

	local renderConnection = RunService.RenderStepped:Connect(function(dt)
		if not state.visible or not state.target then
			return
		end

		if os.clock() >= state.dismissAt then
			hide()
			return
		end

		local alpha = getAlpha(6, math.min(dt, 0.1))
		state.displayGross += (state.target.grossEarnings - state.displayGross) * alpha
		state.displayNet += (state.target.netDeposit - state.displayNet) * alpha

		local grossDisplay = math.floor(state.displayGross + 0.5)
		local netDisplay = math.floor(state.displayNet + 0.5)
		local feeRatePercent = math.floor(state.target.medallionFeeRate * 100 + 0.5)

		ui.breakdown.Text = string.format(
			"Gross shift earnings:  $%d\nFare totals:            $%d\nBonuses:                +$%d\nDamage penalties:       -$%d\nMedallion fee (%d%%):    -$%d\n\nNet bank deposit:       $%d",
			grossDisplay,
			math.floor(state.target.fareTotals + 0.5),
			math.floor(state.target.bonuses + 0.5),
			math.floor(state.target.damagePenalties + 0.5),
			feeRatePercent,
			math.floor(state.target.medallionFeeAmount + 0.5),
			netDisplay
		)

		local remaining = math.max(0, math.ceil(state.dismissAt - os.clock()))
		ui.dismiss.Text = string.format("Press Enter / Space / A to continue (%ds)", remaining)
	end)

	local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not state.visible then
			return
		end

		if input.KeyCode == Enum.KeyCode.Return
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			hide()
		end
	end)

	return {
		destroy = function()
			storeDisconnect()
			renderConnection:Disconnect()
			inputConnection:Disconnect()
			ui.root:Destroy()
		end,
	}
end

return PayoutSummaryController
