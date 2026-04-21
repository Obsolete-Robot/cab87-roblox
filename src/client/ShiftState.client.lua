local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_SHIFT_STATE_REMOTE_NAME = "Cab87ShiftStateUpdated"
local player = Players.LocalPlayer

local function getRemoteName()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	local remotesModule = shared and shared:FindFirstChild("Remotes")
	if not remotesModule then
		return DEFAULT_SHIFT_STATE_REMOTE_NAME
	end

	local ok, Remotes = pcall(require, remotesModule)
	if not ok then
		warn("[cab87] Remotes module failed to load on client; using default shift remote name: " .. tostring(Remotes))
		return DEFAULT_SHIFT_STATE_REMOTE_NAME
	end

	return Remotes.serverToClient and Remotes.serverToClient.shiftStateUpdated
		or DEFAULT_SHIFT_STATE_REMOTE_NAME
end

local function setAttributeIfPresent(name, value, expectedType)
	if type(value) == expectedType then
		player:SetAttribute(name, value)
	end
end

local function applySnapshot(_action, snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	setAttributeIfPresent("Cab87ShiftPhase", snapshot.phase, "string")
	setAttributeIfPresent("Cab87ShiftId", snapshot.shiftId, "number")
	setAttributeIfPresent("Cab87ShiftTimeRemaining", snapshot.timeRemaining, "number")
	setAttributeIfPresent("Cab87ShiftDuration", snapshot.duration, "number")
end

local remote = ReplicatedStorage:WaitForChild(getRemoteName())
remote.OnClientEvent:Connect(applySnapshot)
