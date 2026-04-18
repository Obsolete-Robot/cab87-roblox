local Players = game:GetService("Players")

local player = Players.LocalPlayer
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
label.Font = Enum.Font.GothamBold
label.Text = "CAB87 ROBLOX  |  Drive: W/S or Up/Down  |  Steer: A/D or Left/Right"
label.Parent = gui
