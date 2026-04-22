local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local Remotes = require(shared:WaitForChild("Remotes"))
local GameplayStateStore = require(script.Parent.Parent:WaitForChild("GameplayStateStore"))

local FuelHudController = {}

local LOW_FUEL_RATIO = 0.2

local REASON_TEXT = {
	cooldown = "Refuel cooling down",
	invalid_station = "No refuel station",
	missing_cab = "Need an active cab",
	too_far = "Move closer to station",
	mode_mismatch = "Wrong refuel mode",
	tank_full = "Tank already full",
	insufficient_funds = "Not enough bank funds",
	missing_station = "Refuel station unavailable",
	cancelled = "Refuel cancelled",
	completed = "Refuel complete",
	started = "Refuel started",
	refueling = "Refueling",
	fuel_tick = "",
}

local function toNumber(value, fallback)
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return fallback
end

local function get2dDistance(a, b)
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return math.huge
	end
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function createUi(parentGui)
	local panel = Instance.new("Frame")
	panel.Name = "FuelPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -18, 1, -92)
	panel.Size = UDim2.fromOffset(300, 96)
	panel.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parentGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(110, 176, 255)
	panelStroke.Transparency = 0.12
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -120, 0, 16)
	title.Font = Enum.Font.GothamBold
	title.Text = "FUEL"
	title.TextColor3 = Color3.fromRGB(110, 176, 255)
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local percent = Instance.new("TextLabel")
	percent.Name = "Percent"
	percent.BackgroundTransparency = 1
	percent.Position = UDim2.new(1, -92, 0, 8)
	percent.Size = UDim2.fromOffset(78, 16)
	percent.Font = Enum.Font.GothamBold
	percent.Text = "100%"
	percent.TextColor3 = Color3.fromRGB(110, 176, 255)
	percent.TextSize = 13
	percent.TextXAlignment = Enum.TextXAlignment.Right
	percent.Parent = panel

	local barTrack = Instance.new("Frame")
	barTrack.Name = "BarTrack"
	barTrack.Position = UDim2.fromOffset(14, 28)
	barTrack.Size = UDim2.new(1, -28, 0, 8)
	barTrack.BackgroundColor3 = Color3.fromRGB(54, 58, 64)
	barTrack.BorderSizePixel = 0
	barTrack.Parent = panel

	local barTrackCorner = Instance.new("UICorner")
	barTrackCorner.CornerRadius = UDim.new(1, 0)
	barTrackCorner.Parent = barTrack

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(86, 196, 112)
	barFill.BorderSizePixel = 0
	barFill.Parent = barTrack

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(1, 0)
	barFillCorner.Parent = barFill

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(14, 40)
	status.Size = UDim2.new(1, -28, 0, 20)
	status.Font = Enum.Font.GothamSemibold
	status.Text = "Fuel nominal"
	status.TextColor3 = Color3.fromRGB(245, 245, 245)
	status.TextSize = 15
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Parent = panel

	local prompt = Instance.new("TextLabel")
	prompt.Name = "Prompt"
	prompt.BackgroundTransparency = 1
	prompt.Position = UDim2.fromOffset(14, 62)
	prompt.Size = UDim2.new(1, -28, 0, 25)
	prompt.Font = Enum.Font.GothamSemibold
	prompt.Text = ""
	prompt.TextColor3 = Color3.fromRGB(210, 213, 218)
	prompt.TextSize = 13
	prompt.TextWrapped = true
	prompt.TextXAlignment = Enum.TextXAlignment.Left
	prompt.TextYAlignment = Enum.TextYAlignment.Top
	prompt.Parent = panel

	return {
		root = panel,
		stroke = panelStroke,
		title = title,
		percent = percent,
		barFill = barFill,
		status = status,
		prompt = prompt,
	}
end

function FuelHudController.start(parentGui, cabTracker)
	local ui = createUi(parentGui)
	local requestRefuelRemote = ReplicatedStorage:WaitForChild(Remotes.getClientToServerName("requestRefuel"), 10)
	local fuelStateRemote = ReplicatedStorage:WaitForChild(Remotes.getServerToClientName("fuelStateUpdated"), 10)

	local controller = {
		connections = {},
		fuelState = nil,
		lastReasonTime = 0,
		lastReasonText = "",
		promptStation = nil,
		lastRefuelRequestAt = 0,
	}

	local function setPromptStation(cab, fuel, capacity)
		controller.promptStation = nil
		if not cab then
			return
		end
		local primary = cab.PrimaryPart or cab:FindFirstChildWhichIsA("BasePart")
		if not primary then
			return
		end

		local stations = Config.fuelStations or {}
		local nearest = nil
		local nearestDistance = math.huge
		for _, station in ipairs(stations) do
			if type(station) == "table" and type(station.id) == "string" and typeof(station.position) == "Vector3" then
				local radius = station.kind == "cab_company" and toNumber(Config.fuelCabCompanyStationRadius, 34)
					or toNumber(Config.fuelRefuelStationRadius, 28)
				local distance = get2dDistance(primary.Position, station.position)
				if distance <= math.max(radius, 1) and distance < nearestDistance then
					nearest = station
					nearestDistance = distance
				end
			end
		end

		if nearest then
			local missing = math.max(capacity - fuel, 0)
			if missing <= 0.01 then
				controller.promptStation = {
					text = string.format("%s: tank full", nearest.name or nearest.id),
				}
				return
			end

			if nearest.kind == "cab_company" then
				controller.promptStation = {
					stationId = nearest.id,
					mode = "cab_company",
					text = string.format("%s: press R for free refuel (slow)", nearest.name or "Cab Company"),
				}
				return
			end

			local estimatedPrice = math.max(math.floor(missing * toNumber(Config.fuelPaidPricePerUnit, 2) + 0.5), 0)
			local shiftState = GameplayStateStore.getShiftState()
			local bankMoney = shiftState and toNumber(shiftState.bankMoney, 0) or 0
			if estimatedPrice <= bankMoney then
				controller.promptStation = {
					stationId = nearest.id,
					mode = "paid",
					text = string.format("%s: press R to refuel ($%d)", nearest.name or "Gas Station", estimatedPrice),
				}
			else
				controller.promptStation = {
					text = string.format("%s: need $%d in bank to refuel", nearest.name or "Gas Station", estimatedPrice),
				}
			end
		end
	end

	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(controller.connections, connection)
		return connection
	end

	if fuelStateRemote and fuelStateRemote:IsA("RemoteEvent") then
		connect(fuelStateRemote.OnClientEvent, function(payload)
			if type(payload) ~= "table" then
				return
			end
			controller.fuelState = payload
			local reason = payload.reason
			if type(reason) == "string" and reason ~= "" and reason ~= "fuel_tick" then
				controller.lastReasonTime = os.clock()
				controller.lastReasonText = REASON_TEXT[reason] or reason
			end
		end)
	end

	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed or input.KeyCode ~= Enum.KeyCode.R then
			return
		end
		if not controller.promptStation or not controller.promptStation.stationId then
			return
		end
		if not (requestRefuelRemote and requestRefuelRemote:IsA("RemoteEvent")) then
			return
		end

		local now = os.clock()
		if now - controller.lastRefuelRequestAt < 0.35 then
			return
		end
		controller.lastRefuelRequestAt = now
		requestRefuelRemote:FireServer(controller.promptStation.stationId, controller.promptStation.mode)
	end)

	connect(RunService.RenderStepped, function()
		local cab = cabTracker.getDrivenCab()
		local state = controller.fuelState
		ui.root.Visible = cab ~= nil or state ~= nil
		if not ui.root.Visible then
			return
		end

		local fuel = state and toNumber(state.fuel, nil) or nil
		local capacity = state and toNumber(state.capacity, nil) or nil
		if cab then
			fuel = fuel or toNumber(cab:GetAttribute(Config.carFuelAmountAttribute or "Cab87FuelAmount"), nil)
			capacity = capacity or toNumber(cab:GetAttribute(Config.carFuelCapacityAttribute or "Cab87FuelCapacity"), nil)
		end
		fuel = fuel or 0
		capacity = math.max(capacity or toNumber(Config.fuelCapacity, 100), 1)
		local ratio = math.clamp(fuel / capacity, 0, 1)

		local strokeColor = Color3.fromRGB(110, 176, 255)
		local fillColor = Color3.fromRGB(86, 196, 112)
		local statusText = "Fuel nominal"

		local fuelStateName = state and state.state or nil
		local reasonFresh = (os.clock() - controller.lastReasonTime) <= 2.5
		if fuelStateName == "starting" or fuelStateName == "refueling" then
			local progress = nil
			local startedAt = state and toNumber(state.startedAt, nil)
			local completeAt = state and toNumber(state.completeAt, nil)
			local serverTime = state and toNumber(state.serverTime, nil)
			if startedAt and completeAt and serverTime and completeAt > startedAt then
				progress = math.clamp((serverTime - startedAt) / (completeAt - startedAt), 0, 1)
			end
			if progress then
				statusText = string.format("Refueling... %d%%", math.floor(progress * 100 + 0.5))
			else
				statusText = "Refueling..."
			end
			strokeColor = Color3.fromRGB(110, 176, 255)
			fillColor = Color3.fromRGB(110, 176, 255)
		elseif ratio <= 0.001 then
			statusText = "OUT OF GAS"
			strokeColor = Color3.fromRGB(255, 92, 92)
			fillColor = Color3.fromRGB(255, 92, 92)
		elseif ratio <= LOW_FUEL_RATIO then
			statusText = "Low fuel"
			strokeColor = Color3.fromRGB(255, 152, 58)
			fillColor = Color3.fromRGB(255, 152, 58)
		end

		if reasonFresh and controller.lastReasonText ~= "" then
			statusText = controller.lastReasonText
		end

		setPromptStation(cab, fuel, capacity)
		local promptText = ""
		if controller.promptStation then
			promptText = controller.promptStation.text or ""
		end
		if fuelStateName == "starting" or fuelStateName == "refueling" then
			promptText = "Stay within the refuel zone"
		end

		ui.percent.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
		ui.barFill.Size = UDim2.fromScale(ratio, 1)
		ui.status.Text = statusText
		ui.prompt.Text = promptText
		ui.stroke.Color = strokeColor
		ui.title.TextColor3 = strokeColor
		ui.percent.TextColor3 = strokeColor
		ui.barFill.BackgroundColor3 = fillColor
	end)

	function controller:destroy()
		for _, connection in ipairs(self.connections) do
			connection:Disconnect()
		end
		table.clear(self.connections)
		ui.root:Destroy()
	end

	return controller
end

return FuelHudController
