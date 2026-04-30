local MapConfig = {
	cityBlocks = 7,
	blockSize = 192,
	roadSurfaceY = 0.52,
	buildingInset = 14,
	buildingHeightMin = 25,
	buildingHeightMax = 120,

	-- Map generation V2 (chunk 1): arterial-first roads + Voronoi-style districts.
	districtCount = 9,
	districtJitter = 0.35,
	arterialRingRadiusBlocks = 4,
	arterialSpineOffsetBlocks = 3,
	secondaryRoadEveryBlocks = 3,
	secondaryRoadChance = 0.35,

	-- Authored road markers for cab spawn, free refuel, service/shop, and player spawn.
	cabCompanyCenter = Vector3.new(0, 0.52, -960),
	cabCompanyMarkerFolderName = "Markers",
	cabCompanyMarkerName = "CabCompanyNode",
	cabCompanyRefuelMarkerName = "CabRefuelPoint",
	cabCompanyServiceMarkerName = "CabServicePoint",
	cabCompanyPlayerSpawnMarkerName = "PlayerSpawnPoint",
	cabCompanyFreeRefuelOffset = Vector3.new(-50, 0, 40),
	cabCompanyCabSpawnOffset = Vector3.new(0, 0, 75),
	cabCompanyServiceOffset = Vector3.new(50, 0, 40),
	cabCompanySpawnYaw = 0,
	cabCompanyPlayerSpawnOffset = Vector3.new(-26, 1, 36),
	cabCompanyPlayerSpawnYaw = 0,
	playerUseCabCompanySpawn = false,
	cabCompanyMarkerClearRadius = 80,
	cabCompanyRequestCooldownSeconds = 0.75,
	cabCompanyZonePadding = 8,
	cabCompanyFallbackRequestRadius = 95,
	cabCompanyPromptMaxActivationDistance = 14,
}

return MapConfig
