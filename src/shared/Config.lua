local roadSurfaceY = 0.52
local carRideHeight = 2.3

local Config = {
	cityBlocks = 7,
	blockSize = 192,
	roadWidth = 108,
	roadSurfaceY = roadSurfaceY,
	buildingInset = 14,
	buildingHeightMin = 25,
	buildingHeightMax = 120,

	carRideHeight = carRideHeight,
	carSpawn = Vector3.new(0, roadSurfaceY + carRideHeight, 0),
	carAccel = 95,
	carBrake = 130,
	carDrag = 42,
	carMaxForward = 170,
	carMaxReverse = 55,
	carTurnRate = 2.5,
	carMinTurnSpeed = 8,
	carGrip = 14,
	carDriftGrip = 0.12,
	carDriftDrag = 6,
	carDriftTurnMultiplier = 2.45,
	carDriftSlideForce = 20,
	carDriftMinSpeed = 35,
	carCrashRadius = 7.5,
	carCrashHeightClearance = 3,
	carCrashBounce = 0.18,
	carCrashSlideRetain = 0.35,
	carGravity = 145,
	carGroundSnapDistance = 3.5,
	carGroundProbeHeight = 90,
	carGroundProbeDepth = 220,
	carMaxDeltaTime = 1 / 20,
	carPitchFollow = 8,
	carAirPitchScale = 220,
	carMaxPitch = math.rad(24),

	driveInputRemoteName = "Cab87DriveInput",

	rampRun = 64,
	rampHeight = 18,
	rampWidth = 44,
	rampThickness = 2,
	stuntPlatformHeight = 3,
	stuntPlatformLength = 100,
	stuntPlatformWidth = 56,
	stuntPlatformGap = 80,
}

return Config
