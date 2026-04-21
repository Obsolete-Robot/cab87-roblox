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
}

return MapConfig
