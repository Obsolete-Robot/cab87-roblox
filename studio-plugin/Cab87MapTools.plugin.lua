-- Cab87 Studio plugin: one-click map generation in edit mode.
-- Install by copying this file into your Roblox Plugins folder:
--   %LOCALAPPDATA%\Roblox\Plugins\Cab87MapTools.plugin.lua

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TOOLBAR_NAME = "cab87"
local BUTTON_ICON = "rbxasset://textures/StudioToolbox/PluginToolbar/icon_build.png"

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local generateButton = toolbar:CreateButton(
	"Generate Map",
	"Regenerate cab87 map in edit mode",
	BUTTON_ICON
)
local clearButton = toolbar:CreateButton(
	"Clear Map",
	"Clear generated cab87 world",
	"rbxasset://textures/StudioToolbox/PluginToolbar/icon_delete.png"
)

generateButton.ClickableWhenViewportHidden = true
clearButton.ClickableWhenViewportHidden = true

local function requireFresh(moduleScript)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil, "target is not a ModuleScript"
	end

	-- Require cache can hold stale module state in plugin context.
	-- Clone-and-require forces a fresh load of latest synced source.
	local clone = moduleScript:Clone()
	clone.Name = moduleScript.Name .. "_PluginFreshRequire"
	clone.Parent = moduleScript.Parent
	local ok, result = pcall(require, clone)
	clone:Destroy()
	if not ok then
		return nil, result
	end
	return result, nil
end

local function getMapGenerator()
	local folder = ServerScriptService:FindFirstChild("cab87")
	if not folder then
		warn("[cab87] Could not find ServerScriptService/cab87. Is Rojo connected?")
		return nil
	end

	local moduleScript = folder:FindFirstChild("MapGenerator")
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn("[cab87] Could not find ServerScriptService/cab87/MapGenerator")
		return nil
	end

	local mod, err = requireFresh(moduleScript)
	if not mod then
		warn("[cab87] Failed to require MapGenerator: " .. tostring(err))
		return nil
	end

	return mod
end

local function defaultOverrides()
	local seed = tonumber(plugin:GetSetting("cab87_seed"))
	if not seed then
		seed = math.floor(DateTime.now().UnixTimestampMillis % 2147483647)
	end

	local overrides = {
		seed = seed,
	}

	-- Optional convenience: read defaults from shared config if present.
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if sharedFolder then
		local cfgModule = sharedFolder:FindFirstChild("Config")
		if cfgModule and cfgModule:IsA("ModuleScript") then
			local cfg = requireFresh(cfgModule)
			if type(cfg) == "table" then
				overrides.cityBlocks = cfg.cityBlocks
				overrides.roadWidth = cfg.roadWidth
			end
		end
	end

	return overrides
end

local function regenerateMap()
	local mapGen = getMapGenerator()
	if not mapGen then
		return
	end

	if type(mapGen.Regenerate) ~= "function" then
		warn("[cab87] MapGenerator does not export Regenerate(overrides)")
		return
	end

	local overrides = defaultOverrides()
	plugin:SetSetting("cab87_seed", overrides.seed + 1)

	ChangeHistoryService:SetWaypoint("cab87 Before Regenerate")
	local ok, err = pcall(function()
		mapGen.Regenerate(overrides)
	end)
	ChangeHistoryService:SetWaypoint("cab87 After Regenerate")

	if not ok then
		warn("[cab87] Regenerate failed: " .. tostring(err))
		return
	end

	local world = workspace:FindFirstChild("Cab87World")
	local version = world and world:GetAttribute("GeneratorVersion") or "unknown"
	print(string.format("[cab87] Map regenerated (seed=%s, version=%s)", tostring(overrides.seed), tostring(version)))
end

local function clearMap()
	local mapGen = getMapGenerator()
	if not mapGen then
		return
	end

	if type(mapGen.Clear) ~= "function" then
		warn("[cab87] MapGenerator does not export Clear()")
		return
	end

	ChangeHistoryService:SetWaypoint("cab87 Before Clear")
	local ok, err = pcall(function()
		mapGen.Clear()
	end)
	ChangeHistoryService:SetWaypoint("cab87 After Clear")

	if not ok then
		warn("[cab87] Clear failed: " .. tostring(err))
		return
	end

	print("[cab87] Map cleared")
end

generateButton.Click:Connect(regenerateMap)
clearButton.Click:Connect(clearMap)
