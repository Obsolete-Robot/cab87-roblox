local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local DebugTuningPanel = {}

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
	carModelAssetScale = true,
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

function DebugTuningPanel.start(parentGui)
	if not isDebugPanelAvailable() then
		return nil
	end

	local debugTuneRemoteName = Remotes.clientToServer and Remotes.clientToServer.debugTune
		or "Cab87DebugTune"
	local debugTuneRemote = ReplicatedStorage:WaitForChild(debugTuneRemoteName, 10)
	if not debugTuneRemote or not debugTuneRemote:IsA("RemoteEvent") then
		return nil
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
		return nil
	end

	local connections = {}
	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(connections, connection)
		return connection
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
	toggle.Parent = parentGui

	local panel = Instance.new("Frame")
	panel.Name = "DebugPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 58)
	panel.Size = UDim2.fromOffset(380, 520)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
	panel.BackgroundTransparency = 0.04
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parentGui

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

		connect(list:GetPropertyChangedSignal("AbsoluteContentSize"), updateCanvasSize)
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

			connect(tabButton.MouseButton1Click, function()
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

		connect(track.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				beginSlider(rowState, input)
			end
		end)

		connect(knob.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				beginSlider(rowState, input)
			end
		end)

		connect(valueBox.FocusLost, function()
			local value = tonumber(valueBox.Text)
			if value then
				requestDebugValue(property, value)
			else
				updateRow(rowState)
			end
		end)

		connect(reset.MouseButton1Click, function()
			debugTuneRemote:FireServer("Reset", property.key)
		end)
	end

	for _, tabName in ipairs(tabNames) do
		local scroll = scrollsByTab[tabName]
		for index, property in ipairs(propertiesByTab[tabName]) do
			buildRow(property, index, scroll)
		end
	end

	connect(toggle.MouseButton1Click, function()
		panel.Visible = not panel.Visible
	end)

	connect(copyButton.MouseButton1Click, function()
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

	connect(resetAll.MouseButton1Click, function()
		debugTuneRemote:FireServer("ResetAll")
	end)

	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.F4 then
			panel.Visible = not panel.Visible
		end
	end)

	connect(UserInputService.InputChanged, function(input)
		if not activeSlider then
			return
		end

		if input == activeSlider.input or input.UserInputType == Enum.UserInputType.MouseMovement then
			updateSlider(activeSlider.rowState, input.Position.X)
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if not activeSlider then
			return
		end

		if input == activeSlider.input or input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeSlider = nil
		end
	end)

	connect(debugTuneRemote.OnClientEvent, function(action, key, value)
		if action == "Set" then
			setDebugValue(key, value)
		elseif action == "Snapshot" and type(key) == "table" then
			for snapshotKey, snapshotValue in pairs(key) do
				setDebugValue(snapshotKey, snapshotValue)
			end
		end
	end)

	debugTuneRemote:FireServer("Snapshot")

	return {
		destroy = function()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			table.clear(connections)
			toggle:Destroy()
			panel:Destroy()
		end,
	}
end

return DebugTuningPanel
