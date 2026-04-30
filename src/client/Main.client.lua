local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local controllersFolder = script.Parent:WaitForChild("Controllers")
local shared = ReplicatedStorage:WaitForChild("Shared")

local DebugTuningPanel = require(controllersFolder:WaitForChild("DebugTuningPanel"))
local CabCompanyController = require(controllersFolder:WaitForChild("CabCompanyController"))
local DrivenCabTracker = require(controllersFolder:WaitForChild("DrivenCabTracker"))
local FareHudController = require(controllersFolder:WaitForChild("FareHudController"))
local FuelHudController = require(controllersFolder:WaitForChild("FuelHudController"))
local InputController = require(controllersFolder:WaitForChild("InputController"))
local PayoutSummaryController = require(controllersFolder:WaitForChild("PayoutSummaryController"))
local ShiftHudController = require(controllersFolder:WaitForChild("ShiftHudController"))
local ShopController = require(controllersFolder:WaitForChild("ShopController"))
local SpeedometerController = require(controllersFolder:WaitForChild("SpeedometerController"))
local GameManagerSettings = require(shared:WaitForChild("GameManagerSettings"))
local MinimapController = require(script.Parent:WaitForChild("MinimapController"))

local runtimeSettings = ReplicatedStorage:WaitForChild(GameManagerSettings.runtimeSettingsName, 10)
local gameSettings = if runtimeSettings
	then GameManagerSettings.normalizeSnapshot(runtimeSettings)
	else GameManagerSettings.getDefaultSnapshot()

local gui = Instance.new("ScreenGui")
gui.Name = "Cab87Hud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

if GameManagerSettings.isEnabled(gameSettings, "UiControlsHintEnabled") then
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
end

local controllers = {}

local function startController(controllerModule, ...)
	local controller = controllerModule.start(...)
	if controller then
		table.insert(controllers, controller)
	end
end

startController(InputController)
startController(CabCompanyController)

if GameManagerSettings.isEnabled(gameSettings, "UiGpsWindowEnabled") then
	startController(MinimapController, gui, DrivenCabTracker)
end
if GameManagerSettings.isEnabled(gameSettings, "UiSpeedometerEnabled") then
	startController(SpeedometerController, gui, DrivenCabTracker)
end
if GameManagerSettings.isEnabled(gameSettings, "PassengersEnabled")
	and GameManagerSettings.isEnabled(gameSettings, "UiFarePanelEnabled")
then
	startController(FareHudController, gui, DrivenCabTracker)
end
if GameManagerSettings.isEnabled(gameSettings, "UiFuelPanelEnabled") then
	startController(FuelHudController, gui, DrivenCabTracker)
end
if GameManagerSettings.isEnabled(gameSettings, "ShiftEnabled")
	and GameManagerSettings.isEnabled(gameSettings, "UiShiftPanelEnabled")
then
	startController(ShiftHudController, gui, DrivenCabTracker)
end
if GameManagerSettings.isEnabled(gameSettings, "UiGarageShopEnabled") then
	startController(ShopController, gui)
end
if GameManagerSettings.isEnabled(gameSettings, "ShiftEnabled")
	and GameManagerSettings.isEnabled(gameSettings, "UiPayoutSummaryEnabled")
then
	startController(PayoutSummaryController, gui)
end
if GameManagerSettings.isEnabled(gameSettings, "UiDebugTuningEnabled") then
	startController(DebugTuningPanel, gui)
end

script.Destroying:Connect(function()
	for _, controller in ipairs(controllers) do
		if type(controller.destroy) == "function" then
			controller:destroy()
		end
	end
	table.clear(controllers)

	if gui then
		gui:Destroy()
	end
end)
