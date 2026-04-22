local Remotes = {
	clientToServer = {
		driveInput = "Cab87DriveInput",
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

return Remotes
