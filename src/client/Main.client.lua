local Players = game:GetService("Players")

local player = Players.LocalPlayer
local controllersFolder = script.Parent:WaitForChild("Controllers")

local DebugTuningPanel = require(controllersFolder:WaitForChild("DebugTuningPanel"))
local CabCompanyController = require(controllersFolder:WaitForChild("CabCompanyController"))
local DrivenCabTracker = require(controllersFolder:WaitForChild("DrivenCabTracker"))
local FareHudController = require(controllersFolder:WaitForChild("FareHudController"))
local InputController = require(controllersFolder:WaitForChild("InputController"))
local PayoutSummaryController = require(controllersFolder:WaitForChild("PayoutSummaryController"))
local ShiftHudController = require(controllersFolder:WaitForChild("ShiftHudController"))
local SpeedometerController = require(controllersFolder:WaitForChild("SpeedometerController"))
local MinimapController = require(script.Parent:WaitForChild("MinimapController"))

local gui = Instance.new("ScreenGui")
gui.Name = "Cab87Hud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

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

local controllers = {}

local function startController(controllerModule, ...)
	local controller = controllerModule.start(...)
	if controller then
		table.insert(controllers, controller)
	end
end

startController(InputController)
startController(CabCompanyController)
startController(MinimapController, gui, DrivenCabTracker)
startController(SpeedometerController, gui, DrivenCabTracker)
startController(FareHudController, gui, DrivenCabTracker)
startController(ShiftHudController, gui, DrivenCabTracker)
startController(PayoutSummaryController, gui)
startController(DebugTuningPanel, gui)

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
