local domainConfigs = {
	{ name = "MapConfig", values = require(script.Parent.MapConfig) },
	{ name = "RoadConfig", values = require(script.Parent.RoadConfig) },
	{ name = "VehicleConfig", values = require(script.Parent.VehicleConfig) },
	{ name = "PassengerConfig", values = require(script.Parent.PassengerConfig) },
	{ name = "FareConfig", values = require(script.Parent.FareConfig) },
	{ name = "ShiftConfig", values = require(script.Parent.ShiftConfig) },
	{ name = "GameplayStateConfig", values = require(script.Parent.GameplayStateConfig) },
	{ name = "RemoteConfig", values = require(script.Parent.RemoteConfig) },
	{ name = "CameraConfig", values = require(script.Parent.CameraConfig) },
	{ name = "MinimapConfig", values = require(script.Parent.MinimapConfig) },
	{ name = "DebugTuningConfig", values = require(script.Parent.DebugTuningConfig) },
	{ name = "StuntConfig", values = require(script.Parent.StuntConfig) },
}

local Config = {}

for _, domainConfig in ipairs(domainConfigs) do
	for key, value in pairs(domainConfig.values) do
		if Config[key] ~= nil then
			error(
				string.format("Duplicate config key %q while merging %s", key, domainConfig.name),
				2
			)
		end

		Config[key] = value
	end
end

return Config
