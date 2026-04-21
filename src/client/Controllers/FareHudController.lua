local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local FareHudController = {}

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

local function createUi(parentGui)
	local farePanel = Instance.new("Frame")
	farePanel.Name = "FarePanel"
	farePanel.AnchorPoint = Vector2.new(0, 1)
	farePanel.Position = UDim2.new(0, 18, 1, -182)
	farePanel.Size = UDim2.fromOffset(260, 78)
	farePanel.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
	farePanel.BackgroundTransparency = 0.12
	farePanel.BorderSizePixel = 0
	farePanel.Visible = false
	farePanel.Parent = parentGui

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

	return {
		root = farePanel,
		stroke = farePanelStroke,
		mode = fareMode,
		distance = fareDistance,
		status = fareStatus,
		completed = fareCompleted,
	}
end

function FareHudController.start(parentGui, cabTracker)
	local ui = createUi(parentGui)
	local lastFareMode = nil
	local lastFareStatus = nil
	local lastFareDistance = nil
	local lastFareCompleted = nil
	local lastFareSummary = nil

	local connection = RunService.RenderStepped:Connect(function()
		local cab = cabTracker.getDrivenCab()
		ui.root.Visible = cab ~= nil
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
			ui.mode.Text = modeText
			lastFareMode = modeText
		end

		if status ~= lastFareStatus then
			ui.status.Text = status
			lastFareStatus = status
		end

		local roundedDistance = math.max(0, math.floor(distance + 0.5))
		if roundedDistance ~= lastFareDistance then
			ui.distance.Text = string.format("%d st", roundedDistance)
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
			ui.completed.Text = summary
			lastFareSummary = summary
			lastFareCompleted = roundedCompleted
		end

		ui.mode.TextColor3 = modeColor
		ui.distance.TextColor3 = modeColor
		ui.stroke.Color = modeColor
	end)

	return {
		destroy = function()
			connection:Disconnect()
			ui.root:Destroy()
		end,
	}
end

return FareHudController
