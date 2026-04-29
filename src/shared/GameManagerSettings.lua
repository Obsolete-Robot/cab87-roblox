local GameManagerSettings = {}

GameManagerSettings.managerName = "Cab87Manager"
GameManagerSettings.runtimeSettingsName = "Cab87RuntimeSettings"

local ATTRIBUTE_DEFINITIONS = {
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

local definitionsByKey = {}
local defaults = {}

for _, definition in ipairs(ATTRIBUTE_DEFINITIONS) do
	definitionsByKey[definition.key] = definition
	defaults[definition.key] = definition.default
end

local function normalizeValue(definition, value)
	if definition.kind == "boolean" then
		if type(value) == "boolean" then
			return value
		end
		if type(value) == "string" then
			local normalized = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
			if normalized == "false" or normalized == "off" or normalized == "no" or normalized == "0" then
				return false
			end
			if normalized == "true" or normalized == "on" or normalized == "yes" or normalized == "1" then
				return true
			end
		end
		if type(value) == "number" then
			return value ~= 0
		end

		return definition.default
	end

	if definition.kind == "enum" then
		if type(value) == "string" and definition.values[value] == true then
			return value
		end

		return definition.default
	end

	return definition.default
end

local function readValue(source, key)
	if typeof(source) == "Instance" then
		return source:GetAttribute(key)
	end

	if type(source) == "table" then
		return source[key]
	end

	return nil
end

function GameManagerSettings.getAttributeDefinitions()
	return ATTRIBUTE_DEFINITIONS
end

function GameManagerSettings.getDefaultSnapshot()
	return table.clone(defaults)
end

function GameManagerSettings.normalizeSnapshot(source)
	local snapshot = {}

	for _, definition in ipairs(ATTRIBUTE_DEFINITIONS) do
		snapshot[definition.key] = normalizeValue(definition, readValue(source, definition.key))
	end

	return snapshot
end

function GameManagerSettings.applyAttributes(instance, source)
	local snapshot = GameManagerSettings.normalizeSnapshot(source)

	for _, definition in ipairs(ATTRIBUTE_DEFINITIONS) do
		instance:SetAttribute(definition.key, snapshot[definition.key])
	end

	return snapshot
end

function GameManagerSettings.getManager(workspaceService)
	local manager = workspaceService and workspaceService:FindFirstChild(GameManagerSettings.managerName)
	if manager then
		return manager
	end

	return nil
end

function GameManagerSettings.readWorkspaceSettings(workspaceService)
	return GameManagerSettings.normalizeSnapshot(GameManagerSettings.getManager(workspaceService))
end

function GameManagerSettings.ensureRuntimeSettings(parent, source)
	local runtimeSettings = parent:FindFirstChild(GameManagerSettings.runtimeSettingsName)
	if runtimeSettings and not runtimeSettings:IsA("Configuration") then
		runtimeSettings:Destroy()
		runtimeSettings = nil
	end

	local shouldParent = false
	if not runtimeSettings then
		runtimeSettings = Instance.new("Configuration")
		runtimeSettings.Name = GameManagerSettings.runtimeSettingsName
		shouldParent = true
	end

	runtimeSettings:SetAttribute("GeneratedBy", "Cab87GameManager")
	local snapshot = GameManagerSettings.applyAttributes(runtimeSettings, source)
	if shouldParent then
		runtimeSettings.Parent = parent
	end

	return runtimeSettings, snapshot
end

function GameManagerSettings.readRuntimeSettings(parent)
	local runtimeSettings = parent and parent:FindFirstChild(GameManagerSettings.runtimeSettingsName)
	if runtimeSettings and runtimeSettings:IsA("Configuration") then
		return GameManagerSettings.normalizeSnapshot(runtimeSettings)
	end

	return GameManagerSettings.getDefaultSnapshot()
end

function GameManagerSettings.isEnabled(settings, key)
	local definition = definitionsByKey[key]
	if not definition or definition.kind ~= "boolean" then
		return false
	end

	return normalizeValue(definition, settings and settings[key]) == true
end

function GameManagerSettings.getCabVisualStyle(settings)
	return normalizeValue(definitionsByKey.CabVisualStyle, settings and settings.CabVisualStyle)
end

return GameManagerSettings
