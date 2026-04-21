local CarProfiles = {}

CarProfiles.PlayerTaxi = {
	profileName = "PlayerTaxi",
	driverMode = "Player",
	drivePromptEnabled = true,

	carModelAssetId = 75097386419105,
	carModelAssetScale = 1,
	carModelAssetYawOffsetDegrees = 0,
	carModelAssetGroundAlign = true,
	carModelAssetOffset = Vector3.new(0, 0, 0),
	carDriverSeatOffset = Vector3.new(0, 1.5, 1),
	carDriverSeatYawOffsetDegrees = 180,

	carVisualPolishEnabled = true,
	carVisualBodySpringEnabled = true,
	carVisualLeanEnabled = true,
	carVisualBoostWheelieEnabled = true,
	carVisualLandingBounceEnabled = true,
	carVisualWheelRotationEnabled = true,
	carVisualWheelRadius = 0,
}

CarProfiles.BackgroundTaxi = {
	profileName = "BackgroundTaxi",
	driverMode = "AI",
	drivePromptEnabled = false,

	carModelAssetId = 75097386419105,
	carModelAssetScale = 1,
	carModelAssetYawOffsetDegrees = 0,
	carModelAssetGroundAlign = true,
	carModelAssetOffset = Vector3.new(0, 0, 0),
	carDriverSeatOffset = Vector3.new(0, 1.5, 1),
	carDriverSeatYawOffsetDegrees = 180,

	carMaxForward = 62,
	carMaxReverse = 0,
	carAccel = 55,
	carBrake = 55,
	carTurnRate = 1.35,
	carGrip = 4,
	carCrashBounce = 0.25,

	carVisualPolishEnabled = false,
	carVisualBodySpringEnabled = false,
	carVisualLeanEnabled = false,
	carVisualBoostWheelieEnabled = false,
	carVisualLandingBounceEnabled = false,
	carVisualWheelRotationEnabled = false,
	carVisualWheelRadius = 0,
}

CarProfiles.visualAttributeKeys = {
	"carVisualPolishEnabled",
	"carVisualBodySpringEnabled",
	"carVisualLeanEnabled",
	"carVisualBoostWheelieEnabled",
	"carVisualLandingBounceEnabled",
	"carVisualWheelRotationEnabled",
	"carVisualBodyNodeName",
	"carVisualWheelNodeNames",
	"carVisualWheelSpinAxis",
	"carVisualWheelSpinDirection",
	"carVisualWheelRadius",
}

function CarProfiles.get(profileName)
	local profile = CarProfiles[profileName]
	if type(profile) == "table" then
		return profile
	end

	return CarProfiles.PlayerTaxi
end

return CarProfiles
