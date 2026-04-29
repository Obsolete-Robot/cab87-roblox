local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(shared:WaitForChild("Remotes"))

local ShopController = {}

local REQUEST_PROMPT_ATTRIBUTE = "Cab87CabRequestPrompt"
local REQUEST_ACTION_ATTRIBUTE = "Cab87CabRequestAction"

local REASON_LABELS = {
	unknownTaxi = "Unknown taxi",
	notOwned = "You do not own that taxi",
	equipFailed = "Could not equip taxi",
	alreadyOwned = "Already owned",
	missingPrice = "Missing price",
	insufficientFunds = "Not enough bank money",
	outOfCabCompanyZone = "Move to the cab depot marker",
	invalidPayload = "Invalid request",
}

local function formatMoney(value)
	return string.format("$%d", math.max(0, math.floor((tonumber(value) or 0) + 0.5)))
end

local function reasonText(reason)
	if type(reason) ~= "string" or reason == "" then
		return "Request failed"
	end

	return REASON_LABELS[reason] or reason
end

local function isShopPrompt(prompt)
	return prompt
		and prompt:IsA("ProximityPrompt")
		and prompt:GetAttribute(REQUEST_PROMPT_ATTRIBUTE) == true
		and prompt:GetAttribute(REQUEST_ACTION_ATTRIBUTE) == "shop"
end

local function createUi(parentGui)
	local root = Instance.new("Frame")
	root.Name = "GarageShop"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.52)
	root.Size = UDim2.fromOffset(460, 360)
	root.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = parentGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 206, 38)
	stroke.Transparency = 0.2
	stroke.Thickness = 2
	stroke.Parent = root

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -120, 0, 24)
	title.Font = Enum.Font.GothamBold
	title.Text = "Cab Garage"
	title.TextColor3 = Color3.fromRGB(255, 206, 38)
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = root

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(90, 28)
	closeButton.Position = UDim2.new(1, -104, 0, 10)
	closeButton.BackgroundColor3 = Color3.fromRGB(45, 48, 55)
	closeButton.Text = "Close"
	closeButton.Font = Enum.Font.GothamSemibold
	closeButton.TextSize = 14
	closeButton.TextColor3 = Color3.fromRGB(245, 245, 245)
	closeButton.Parent = root

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeButton

	local bankLabel = Instance.new("TextLabel")
	bankLabel.BackgroundTransparency = 1
	bankLabel.Position = UDim2.fromOffset(16, 40)
	bankLabel.Size = UDim2.new(1, -32, 0, 20)
	bankLabel.Font = Enum.Font.GothamSemibold
	bankLabel.Text = "Bank $0"
	bankLabel.TextColor3 = Color3.fromRGB(210, 213, 218)
	bankLabel.TextSize = 15
	bankLabel.TextXAlignment = Enum.TextXAlignment.Left
	bankLabel.Parent = root

	local feedbackLabel = Instance.new("TextLabel")
	feedbackLabel.BackgroundTransparency = 1
	feedbackLabel.Position = UDim2.fromOffset(16, 62)
	feedbackLabel.Size = UDim2.new(1, -32, 0, 18)
	feedbackLabel.Font = Enum.Font.GothamSemibold
	feedbackLabel.Text = ""
	feedbackLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
	feedbackLabel.TextSize = 13
	feedbackLabel.TextXAlignment = Enum.TextXAlignment.Left
	feedbackLabel.Parent = root

	local list = Instance.new("ScrollingFrame")
	list.Name = "TaxiList"
	list.Position = UDim2.fromOffset(12, 88)
	list.Size = UDim2.new(1, -24, 1, -100)
	list.BackgroundColor3 = Color3.fromRGB(22, 24, 29)
	list.BackgroundTransparency = 0.1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.Parent = root

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 8)
	listCorner.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = list

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
	end)

	return {
		root = root,
		closeButton = closeButton,
		bankLabel = bankLabel,
		feedbackLabel = feedbackLabel,
		list = list,
		layout = layout,
	}
end

local function clearList(ui)
	for _, child in ipairs(ui.list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function buildRow(ui, entry, vehicleInventoryActionRemote)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 64)
	row.BackgroundColor3 = Color3.fromRGB(31, 34, 40)
	row.BorderSizePixel = 0
	row.Parent = ui.list

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(10, 8)
	name.Size = UDim2.new(1, -170, 0, 20)
	name.Font = Enum.Font.GothamBold
	name.Text = entry.displayName or entry.id
	name.TextColor3 = Color3.fromRGB(245, 245, 245)
	name.TextSize = 14
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(10, 32)
	status.Size = UDim2.new(1, -170, 0, 20)
	status.Font = Enum.Font.GothamSemibold
	status.TextSize = 12
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = row

	local actionButton = Instance.new("TextButton")
	actionButton.Size = UDim2.fromOffset(140, 36)
	actionButton.Position = UDim2.new(1, -148, 0.5, -18)
	actionButton.Font = Enum.Font.GothamSemibold
	actionButton.TextSize = 14
	actionButton.Parent = row

	local actionCorner = Instance.new("UICorner")
	actionCorner.CornerRadius = UDim.new(0, 6)
	actionCorner.Parent = actionButton

	if entry.equipped then
		status.Text = "Owned • Equipped"
		status.TextColor3 = Color3.fromRGB(124, 222, 132)
		actionButton.Text = "Equipped"
		actionButton.BackgroundColor3 = Color3.fromRGB(45, 74, 49)
		actionButton.TextColor3 = Color3.fromRGB(204, 255, 210)
		actionButton.AutoButtonColor = false
		actionButton.Active = false
	elseif entry.owned then
		status.Text = "Owned"
		status.TextColor3 = Color3.fromRGB(156, 214, 255)
		actionButton.Text = "Equip"
		actionButton.BackgroundColor3 = Color3.fromRGB(35, 97, 152)
		actionButton.TextColor3 = Color3.fromRGB(235, 244, 255)
		actionButton.MouseButton1Click:Connect(function()
			vehicleInventoryActionRemote:FireServer({ action = "equip", taxiId = entry.id })
		end)
	else
		status.Text = string.format("Locked • %s", formatMoney(entry.unlockPrice or 0))
		status.TextColor3 = if entry.affordable then Color3.fromRGB(255, 206, 38) else Color3.fromRGB(255, 153, 153)
		actionButton.Text = if entry.affordable then "Buy" else "Too Expensive"
		actionButton.BackgroundColor3 = if entry.affordable then Color3.fromRGB(120, 86, 18) else Color3.fromRGB(80, 42, 42)
		actionButton.TextColor3 = Color3.fromRGB(245, 245, 245)
		actionButton.Active = entry.affordable == true
		actionButton.AutoButtonColor = entry.affordable == true
		if entry.affordable then
			actionButton.MouseButton1Click:Connect(function()
				vehicleInventoryActionRemote:FireServer({ action = "purchase", taxiId = entry.id })
			end)
		end
	end
end

function ShopController.start(parentGui)
	local vehicleInventoryActionRemote = ReplicatedStorage:WaitForChild(Remotes.getClientToServerName("vehicleInventoryAction"), 10)
	local vehicleInventoryUpdatedRemote = ReplicatedStorage:WaitForChild(Remotes.getServerToClientName("vehicleInventoryUpdated"), 10)
	if not (vehicleInventoryActionRemote and vehicleInventoryActionRemote:IsA("RemoteEvent")) then
		warn("[cab87] Vehicle inventory action remote unavailable")
		return nil
	end
	if not (vehicleInventoryUpdatedRemote and vehicleInventoryUpdatedRemote:IsA("RemoteEvent")) then
		warn("[cab87] Vehicle inventory update remote unavailable")
		return nil
	end

	local ui = createUi(parentGui)
	local connections = {}

	local function openShop()
		ui.root.Visible = true
		vehicleInventoryActionRemote:FireServer({ action = "snapshot" })
	end

	local function closeShop()
		ui.root.Visible = false
		ui.feedbackLabel.Text = ""
	end

	table.insert(connections, ui.closeButton.MouseButton1Click:Connect(closeShop))
	table.insert(connections, ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if not isShopPrompt(prompt) then
			return
		end
		openShop()
	end))
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and ui.root.Visible then
			closeShop()
		end
	end))

	table.insert(connections, vehicleInventoryUpdatedRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end

		local snapshot = payload.snapshot
		if type(snapshot) == "table" then
			ui.bankLabel.Text = string.format("Bank %s", formatMoney(snapshot.bankMoney))
			clearList(ui)
			local catalog = snapshot.catalog
			if type(catalog) == "table" then
				for _, entry in ipairs(catalog) do
					if type(entry) == "table" and type(entry.id) == "string" then
						buildRow(ui, entry, vehicleInventoryActionRemote)
					end
				end
			end
		end

		if payload.ok == true then
			if payload.action == "purchase" then
				ui.feedbackLabel.Text = "Purchase complete"
				ui.feedbackLabel.TextColor3 = Color3.fromRGB(124, 222, 132)
			elseif payload.action == "equip" then
				ui.feedbackLabel.Text = "Taxi equipped"
				ui.feedbackLabel.TextColor3 = Color3.fromRGB(124, 222, 132)
			elseif payload.action == "snapshot" then
				ui.feedbackLabel.Text = ""
			end
		elseif payload.ok == false then
			ui.feedbackLabel.Text = reasonText(payload.reason)
			ui.feedbackLabel.TextColor3 = Color3.fromRGB(255, 153, 153)
		end
	end))

	return {
		destroy = function()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			table.clear(connections)
			ui.root:Destroy()
		end,
	}
end

return ShopController
