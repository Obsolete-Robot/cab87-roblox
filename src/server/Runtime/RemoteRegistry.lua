local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteRegistry = {}

local function loadSharedModule(moduleName)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild(moduleName)
	if not module then
		return nil
	end

	local ok, result = pcall(require, module)
	if not ok then
		warn("[cab87] " .. moduleName .. " module failed to load: " .. tostring(result))
		return nil
	end

	return result
end

local function getRemoteNames()
	local Remotes = loadSharedModule("Remotes")
	if type(Remotes) ~= "table" then
		error("[cab87] Remotes module is required to register remote events")
	end

	return {
		driveInput = Remotes.getClientToServerName("driveInput"),
		cameraEvent = Remotes.getServerToClientName("cameraEvent"),
		debugTune = Remotes.getClientToServerName("debugTune"),
		gameplayStateUpdated = Remotes.getServerToClientName("gameplayStateUpdated"),
		shiftStateUpdated = Remotes.getServerToClientName("shiftStateUpdated"),
	}
end

local function getOrCreateRemoteEvent(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end

	return remote
end

function RemoteRegistry.isDebugTuningEnabled(config)
	config = config or loadSharedModule("Config") or {}
	return config.debugPanelEnabled == true
		and (not config.debugPanelStudioOnly or RunService:IsStudio())
end

function RemoteRegistry.ensure(options)
	options = options or {}
	local config = options.config or loadSharedModule("Config") or {}
	local remoteNames = getRemoteNames()

	return {
		driveInput = getOrCreateRemoteEvent(remoteNames.driveInput),
		cameraEvent = getOrCreateRemoteEvent(remoteNames.cameraEvent),
		debugTune = if RemoteRegistry.isDebugTuningEnabled(config)
			then getOrCreateRemoteEvent(remoteNames.debugTune)
			else nil,
		gameplayStateUpdated = getOrCreateRemoteEvent(remoteNames.gameplayStateUpdated),
		shiftStateUpdated = getOrCreateRemoteEvent(remoteNames.shiftStateUpdated),
	}
end

return RemoteRegistry
