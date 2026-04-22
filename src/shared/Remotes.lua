local Remotes = {
	clientToServer = {
		driveInput = "Cab87DriveInput",
		requestCab = "Cab87RequestCab",
		debugTune = "Cab87DebugTune",
	},

	serverToClient = {
		cameraEvent = "Cab87CameraEvent",
		gameplayStateUpdated = "Cab87GameplayStateUpdated",
		shiftStateUpdated = "Cab87ShiftStateUpdated",
	},

	actions = {
		gameplaySnapshot = "Snapshot",
		gameplayCabState = "CabState",
		gameplayShiftState = "ShiftState",
		gameplayPayoutSummary = "PayoutSummary",
		shiftStateSnapshot = "Snapshot",
		shiftStateUpdated = "State",
		shiftPayoutSummary = "PayoutSummary",
	},
}

local function getRemoteName(groupName, remoteKey)
	local group = Remotes[groupName]
	if type(group) ~= "table" then
		error(("[cab87] Remotes.%s must be a table"):format(groupName), 3)
	end

	local remoteName = group[remoteKey]
	if type(remoteName) ~= "string" or remoteName == "" then
		error(("[cab87] Remotes.%s.%s must be a non-empty string"):format(groupName, tostring(remoteKey)), 3)
	end

	return remoteName
end

function Remotes.getClientToServerName(remoteKey)
	return getRemoteName("clientToServer", remoteKey)
end

function Remotes.getServerToClientName(remoteKey)
	return getRemoteName("serverToClient", remoteKey)
end

return Remotes
