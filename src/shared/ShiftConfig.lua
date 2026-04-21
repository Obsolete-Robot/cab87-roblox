local ShiftConfig = {
	shiftDurationSeconds = 180,
	shiftInitialPreparationSeconds = 5,
	shiftEndingSeconds = 4,
	shiftIntermissionSeconds = 20,
	shiftBroadcastIntervalSeconds = 0.5,
	shiftDebugLogging = false,
	shiftPhaseAttribute = "Cab87ShiftPhase",
	shiftIdAttribute = "Cab87ShiftId",
	shiftTimeRemainingAttribute = "Cab87ShiftTimeRemaining",
	shiftDurationAttribute = "Cab87ShiftDuration",
	shiftGrossMoneyAttribute = "Cab87ShiftGrossMoney",
	shiftPayoutSummaryEventIdAttribute = "Cab87ShiftPayoutSummaryEventId",
	shiftPayoutFareTotalsAttribute = "Cab87ShiftPayoutFareTotals",
	shiftPayoutBonusesAttribute = "Cab87ShiftPayoutBonuses",
	shiftPayoutDamagePenaltiesAttribute = "Cab87ShiftPayoutDamagePenalties",
	shiftPayoutMedallionFeeRateAttribute = "Cab87ShiftPayoutMedallionFeeRate",
	shiftPayoutMedallionFeeAmountAttribute = "Cab87ShiftPayoutMedallionFeeAmount",
	shiftPayoutNetDepositAttribute = "Cab87ShiftPayoutNetDeposit",
	shiftPayoutDismissSeconds = 10,
	shiftMedallionFeeRate = 0.2,
}

return ShiftConfig
