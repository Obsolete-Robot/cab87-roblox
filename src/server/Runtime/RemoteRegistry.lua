local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteRegistry = {}

local DEFAULT_SHIFT_STATE_REMOTE_NAME = "Cab87ShiftStateUpdated"

local function getRemoteNames()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local remotesModule = shared and shared:FindFirstChild("Remotes")
	if not remotesModule then
		return {
			shiftStateUpdated = DEFAULT_SHIFT_STATE_REMOTE_NAME,
		}
	end

	local ok, Remotes = pcall(require, remotesModule)
	if not ok then
		warn("[cab87] Remotes module failed to load; using default remote names: " .. tostring(Remotes))
		return {
			shiftStateUpdated = DEFAULT_SHIFT_STATE_REMOTE_NAME,
		}
	end

	return {
		shiftStateUpdated = Remotes.serverToClient and Remotes.serverToClient.shiftStateUpdated
			or DEFAULT_SHIFT_STATE_REMOTE_NAME,
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

function RemoteRegistry.ensure()
	local remoteNames = getRemoteNames()
	return {
		shiftStateUpdated = getOrCreateRemoteEvent(remoteNames.shiftStateUpdated),
	}
end

return RemoteRegistry
