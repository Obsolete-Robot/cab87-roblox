-- Cab87 Studio plugin: creates the editable per-place game manager node.
-- Install to:
--   %LOCALAPPDATA%\Roblox\Plugins\Cab87ManagerTools.plugin.lua

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local TOOLBAR_NAME = "Cab87"
local MANAGER_NAME = "Cab87Manager"
local BUTTON_ICON = "rbxasset://textures/StudioToolbox/PluginToolbar/icon_settings.png"

local FALLBACK_DEFINITIONS = {
	{ key = "PassengersEnabled", kind = "boolean", default = true },
	{ key = "ShiftEnabled", kind = "boolean", default = true },
	{ key = "ProceduralWorldEnabled", kind = "boolean", default = true },
	{ key = "CabVisualStyle", kind = "enum", default = "Asset", options = { "Asset", "Blocky" }, values = { Asset = true, Blocky = true } },
	{ key = "UiGpsWindowEnabled", kind = "boolean", default = true },
	{ key = "UiShiftPanelEnabled", kind = "boolean", default = true },
	{ key = "UiFarePanelEnabled", kind = "boolean", default = true },
	{ key = "UiFuelPanelEnabled", kind = "boolean", default = true },
	{ key = "UiSpeedometerEnabled", kind = "boolean", default = true },
	{ key = "UiControlsHintEnabled", kind = "boolean", default = true },
	{ key = "UiGarageShopEnabled", kind = "boolean", default = true },
	{ key = "UiPayoutSummaryEnabled", kind = "boolean", default = true },
	{ key = "UiDebugTuningEnabled", kind = "boolean", default = true },
}

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local addManagerButton = toolbar:CreateButton(
	"Add Manager",
	"Create or select the Cab87Manager game settings node",
	BUTTON_ICON
)
addManagerButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	340,
	520,
	300,
	360
)

local widget = plugin:CreateDockWidgetPluginGui("Cab87ManagerTools", widgetInfo)
widget.Title = "Cab87 Manager"

local rootFrame = Instance.new("ScrollingFrame")
rootFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
rootFrame.BorderSizePixel = 0
rootFrame.Size = UDim2.fromScale(1, 1)
rootFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
rootFrame.CanvasSize = UDim2.fromOffset(0, 0)
rootFrame.ScrollBarThickness = 8
rootFrame.ScrollingDirection = Enum.ScrollingDirection.Y
rootFrame.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = rootFrame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = rootFrame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 28)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 220, 120)
title.Text = "Cab87 Manager"
title.Parent = rootFrame

local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, 0, 0, 36)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextColor3 = Color3.fromRGB(220, 224, 228)
status.Text = "Create or select Cab87Manager, then edit its attributes here."
status.Parent = rootFrame

local controls = {}
local dropdowns = {}
local activeManager = nil
local managerAttributeConnection = nil

local LABELS = {
	PassengersEnabled = "Passengers",
	ShiftEnabled = "Shift",
	ProceduralWorldEnabled = "Procedural World",
	CabVisualStyle = "Cab Visual Style",
	UiGpsWindowEnabled = "GPS Window",
	UiShiftPanelEnabled = "Shift Panel",
	UiFarePanelEnabled = "Fare Panel",
	UiFuelPanelEnabled = "Fuel Panel",
	UiSpeedometerEnabled = "Speedometer",
	UiControlsHintEnabled = "Controls Hint",
	UiGarageShopEnabled = "Garage Shop",
	UiPayoutSummaryEnabled = "Payout Summary",
	UiDebugTuningEnabled = "Debug Tuning",
}

local ENUM_HELP = {
	Asset = "current visual cab",
	Blocky = "original prototype cab",
}

local function setStatus(message)
	status.Text = tostring(message)
end

local function styleButton(button)
	button.BackgroundColor3 = Color3.fromRGB(48, 54, 64)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = Color3.fromRGB(245, 245, 245)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	return button
end

local function makeLabel(parent, text)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.52, -4, 0, 32)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(206, 212, 218)
	label.Text = text
	label.Parent = parent
	return label
end

local function requireFresh(moduleScript)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end

	local clone = moduleScript:Clone()
	clone.Name = moduleScript.Name .. "_PluginFreshRequire"
	clone.Parent = moduleScript.Parent
	local ok, result = pcall(require, clone)
	clone:Destroy()
	if ok then
		return result
	end

	warn("[cab87] Failed to require GameManagerSettings: " .. tostring(result))
	return nil
end

local function getAttributeDefinitions()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local settingsModule = shared and shared:FindFirstChild("GameManagerSettings")
	local settings = requireFresh(settingsModule)
	if type(settings) == "table" and type(settings.getAttributeDefinitions) == "function" then
		return settings.getAttributeDefinitions()
	end

	return FALLBACK_DEFINITIONS
end

local function normalizeAttribute(definition, value)
	if definition.kind == "boolean" then
		if type(value) == "boolean" then
			return value
		end

		return definition.default
	end

	if definition.kind == "enum" then
		if type(value) == "string" and definition.values and definition.values[value] == true then
			return value
		end

		return definition.default
	end

	return definition.default
end

local function getOrCreateManager()
	local manager = Workspace:FindFirstChild(MANAGER_NAME)
	if manager and not manager:IsA("Configuration") then
		manager:Destroy()
		manager = nil
	end

	if not manager then
		manager = Instance.new("Configuration")
		manager.Name = MANAGER_NAME
		manager.Parent = Workspace
	end

	return manager
end

local function ensureManagerAttributes(manager)
	for _, definition in ipairs(getAttributeDefinitions()) do
		manager:SetAttribute(definition.key, normalizeAttribute(definition, manager:GetAttribute(definition.key)))
	end
	manager:SetAttribute("GeneratedBy", "Cab87ManagerTools")
	manager:SetAttribute("Cab87ManagerVersion", 1)
	return manager
end

local function getEnumOptions(definition)
	if type(definition.options) == "table" and #definition.options > 0 then
		return definition.options
	end

	local options = {}
	for value in pairs(definition.values or {}) do
		table.insert(options, value)
	end
	table.sort(options)
	return options
end

local function refreshControls()
	local manager = activeManager
	if not (manager and manager.Parent and manager:IsA("Configuration")) then
		manager = Workspace:FindFirstChild(MANAGER_NAME)
		if not (manager and manager:IsA("Configuration")) then
			setStatus("Click Add Manager to create Cab87Manager.")
			return
		end
	end

	for _, definition in ipairs(getAttributeDefinitions()) do
		local control = controls[definition.key]
		if control then
			local value = normalizeAttribute(definition, manager:GetAttribute(definition.key))
			if definition.kind == "boolean" then
				control.Text = value and "On" or "Off"
				control.BackgroundColor3 = value and Color3.fromRGB(49, 116, 76) or Color3.fromRGB(108, 58, 58)
			elseif definition.kind == "enum" then
				control.Text = tostring(value) .. "  v"
			end
		end
	end

	setStatus("Editing Workspace." .. MANAGER_NAME .. ".")
end

local function watchManager(manager)
	if managerAttributeConnection then
		managerAttributeConnection:Disconnect()
		managerAttributeConnection = nil
	end

	activeManager = manager
	if manager then
		managerAttributeConnection = manager.AttributeChanged:Connect(refreshControls)
	end
	refreshControls()
end

local function closeOtherDropdowns(openDropdown)
	for _, dropdown in ipairs(dropdowns) do
		if dropdown ~= openDropdown then
			dropdown.AutomaticSize = Enum.AutomaticSize.None
			dropdown.Visible = false
		end
	end
end

local function setManagerValue(definition, value)
	ChangeHistoryService:SetWaypoint("cab87 Before Manager Change")
	local manager = ensureManagerAttributes(getOrCreateManager())
	manager:SetAttribute(definition.key, normalizeAttribute(definition, value))
	Selection:Set({ manager })
	watchManager(manager)
	ChangeHistoryService:SetWaypoint("cab87 After Manager Change")
end

local function makeControlRow(definition)
	local row = Instance.new("Frame")
	row.Name = definition.key .. "Row"
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Size = UDim2.new(1, 0, 0, 0)
	row.BackgroundTransparency = 1
	row.Parent = rootFrame

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 4)
	rowLayout.Parent = row

	local top = Instance.new("Frame")
	top.Name = "Top"
	top.Size = UDim2.new(1, 0, 0, 32)
	top.BackgroundTransparency = 1
	top.Parent = row

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topLayout.Padding = UDim.new(0, 8)
	topLayout.Parent = top

	makeLabel(top, LABELS[definition.key] or definition.key)

	local button = styleButton(Instance.new("TextButton"))
	button.Size = UDim2.new(0.48, -4, 0, 32)
	button.Parent = top
	controls[definition.key] = button

	if definition.kind == "boolean" then
		button.MouseButton1Click:Connect(function()
			local manager = ensureManagerAttributes(getOrCreateManager())
			local current = normalizeAttribute(definition, manager:GetAttribute(definition.key))
			setManagerValue(definition, not current)
		end)
	elseif definition.kind == "enum" then
		local dropdown = Instance.new("Frame")
		dropdown.Name = definition.key .. "Dropdown"
		dropdown.AutomaticSize = Enum.AutomaticSize.None
		dropdown.Size = UDim2.new(1, 0, 0, 0)
		dropdown.BackgroundTransparency = 1
		dropdown.Visible = false
		dropdown.Parent = row
		table.insert(dropdowns, dropdown)

		local dropdownLayout = Instance.new("UIListLayout")
		dropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
		dropdownLayout.Padding = UDim.new(0, 4)
		dropdownLayout.Parent = dropdown

		for _, option in ipairs(getEnumOptions(definition)) do
			local optionButton = styleButton(Instance.new("TextButton"))
			optionButton.Size = UDim2.new(1, 0, 0, 30)
			optionButton.Text = ENUM_HELP[option] and string.format("%s - %s", option, ENUM_HELP[option]) or option
			optionButton.Parent = dropdown
			optionButton.MouseButton1Click:Connect(function()
				dropdown.AutomaticSize = Enum.AutomaticSize.None
				dropdown.Visible = false
				setManagerValue(definition, option)
			end)
		end

		button.MouseButton1Click:Connect(function()
			local nextVisible = not dropdown.Visible
			closeOtherDropdowns(dropdown)
			dropdown.AutomaticSize = nextVisible and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
			dropdown.Visible = nextVisible
		end)
	end
end

local function buildControls()
	for _, definition in ipairs(getAttributeDefinitions()) do
		makeControlRow(definition)
	end
	refreshControls()
end

local function addManager()
	ChangeHistoryService:SetWaypoint("cab87 Before Add Manager")

	local manager = ensureManagerAttributes(getOrCreateManager())

	Selection:Set({ manager })
	widget.Enabled = true
	watchManager(manager)
	ChangeHistoryService:SetWaypoint("cab87 After Add Manager")
	print("[cab87] Cab87Manager is ready in Workspace")
end

addManagerButton.Click:Connect(addManager)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if widget.Enabled then
		local manager = Workspace:FindFirstChild(MANAGER_NAME)
		if manager and manager:IsA("Configuration") then
			watchManager(manager)
		else
			refreshControls()
		end
	end
end)

buildControls()
