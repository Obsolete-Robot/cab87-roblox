local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteRegistry = {}

local DEFAULT_REMOTE_NAMES = {
	driveInput = "Cab87DriveInput",
	cameraEvent = "Cab87CameraEvent",
	debugTune = "Cab87DebugTune",
	shiftStateUpdated = "Cab87ShiftStateUpdated",
}

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

local function getRemoteNames(config)
	config = config or loadSharedModule("Config") or {}
	local Remotes = loadSharedModule("Remotes") or {}
	local serverToClient = Remotes.serverToClient or {}
	local clientToServer = Remotes.clientToServer or {}

	return {
		driveInput = clientToServer.driveInput
			or config.driveInputRemoteName
			or DEFAULT_REMOTE_NAMES.driveInput,
		cameraEvent = serverToClient.cameraEvent
			or config.cameraEventRemoteName
			or DEFAULT_REMOTE_NAMES.cameraEvent,
		debugTune = clientToServer.debugTune
			or config.debugTuneRemoteName
			or DEFAULT_REMOTE_NAMES.debugTune,
		shiftStateUpdated = serverToClient.shiftStateUpdated
			or config.shiftStateRemoteName
			or DEFAULT_REMOTE_NAMES.shiftStateUpdated,
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
	local remoteNames = getRemoteNames(config)

	return {
		driveInput = getOrCreateRemoteEvent(remoteNames.driveInput),
		cameraEvent = getOrCreateRemoteEvent(remoteNames.cameraEvent),
		debugTune = if RemoteRegistry.isDebugTuningEnabled(config)
			then getOrCreateRemoteEvent(remoteNames.debugTune)
			else nil,
		shiftStateUpdated = getOrCreateRemoteEvent(remoteNames.shiftStateUpdated),
	}
end

return RemoteRegistry
