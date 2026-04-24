local RoadSampling = require(script.Parent:WaitForChild("RoadSampling"))

local RoadSplineData = {}

RoadSplineData.EDITOR_ROOT_NAME = "Cab87RoadEditor"
RoadSplineData.SPLINES_NAME = "Splines"
RoadSplineData.POINTS_NAME = "RoadPoints"
RoadSplineData.NETWORK_NAME = "RoadNetwork"
RoadSplineData.WIREFRAME_NAME = "WireframeDisplay"
RoadSplineData.RUNTIME_DATA_NAME = "AuthoredRoadSplineData"
RoadSplineData.JUNCTIONS_NAME = "Junctions"
RoadSplineData.ROAD_WIDTH_ATTR = RoadSampling.ROAD_WIDTH_ATTR
RoadSplineData.JUNCTION_SUBDIVISIONS_ATTR = "Subdivisions"
RoadSplineData.JUNCTION_CROSSWALK_LENGTH_ATTR = "CrosswalkLength"
RoadSplineData.JUNCTION_PORTAL_ATTACH_DISTANCE_ATTR = "PortalAttachDistance"

local JUNCTION_SUBDIVISIONS_DEFAULT = 0
local JUNCTION_SUBDIVISIONS_MIN = 0
local JUNCTION_SUBDIVISIONS_MAX = 12
local JUNCTION_CROSSWALK_LENGTH_DEFAULT = 8
local JUNCTION_CROSSWALK_LENGTH_MIN = 0
local JUNCTION_CROSSWALK_LENGTH_MAX = 80

function RoadSplineData.sanitizeJunctionSubdivisions(value)
	local subdivisions = tonumber(value)
	if not subdivisions then
		return JUNCTION_SUBDIVISIONS_DEFAULT
	end
	return math.clamp(math.floor(subdivisions + 0.5), JUNCTION_SUBDIVISIONS_MIN, JUNCTION_SUBDIVISIONS_MAX)
end

function RoadSplineData.sanitizeJunctionCrosswalkLength(value)
	local length = tonumber(value)
	if not length then
		return JUNCTION_CROSSWALK_LENGTH_DEFAULT
	end
	return math.clamp(length, JUNCTION_CROSSWALK_LENGTH_MIN, JUNCTION_CROSSWALK_LENGTH_MAX)
end

function RoadSplineData.sortedChildren(parent, className)
	local children = {}
	if not parent then
		return children
	end

	for _, child in ipairs(parent:GetChildren()) do
		if not className or child:IsA(className) then
			table.insert(children, child)
		end
	end

	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)

	return children
end

function RoadSplineData.getDataRoot(world)
	return world and world:FindFirstChild(RoadSplineData.RUNTIME_DATA_NAME)
end

function RoadSplineData.getSplines(root)
	local splinesFolder = root and root:FindFirstChild(RoadSplineData.SPLINES_NAME)
	if splinesFolder and splinesFolder:IsA("Folder") then
		return RoadSplineData.sortedChildren(splinesFolder, "Model")
	end

	local legacyPoints = root and root:FindFirstChild(RoadSplineData.POINTS_NAME)
	if legacyPoints and legacyPoints:IsA("Folder") then
		return { root }
	end

	return {}
end

function RoadSplineData.getSplinePoints(spline)
	local pointsFolder = spline and spline:FindFirstChild(RoadSplineData.POINTS_NAME)
	if not (pointsFolder and pointsFolder:IsA("Folder")) then
		return {}
	end

	local points = {}
	for _, child in ipairs(pointsFolder:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Vector3Value") then
			table.insert(points, child)
		end
	end

	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)

	return points
end

function RoadSplineData.getPointPosition(point)
	if not point then
		return nil
	end

	if point:IsA("BasePart") then
		return point.Position
	elseif point:IsA("Vector3Value") then
		return point.Value
	end

	return nil
end

function RoadSplineData.getPointPositions(points)
	local positions = {}
	for _, point in ipairs(points) do
		local position = RoadSplineData.getPointPosition(point)
		if position then
			table.insert(positions, position)
		end
	end
	return positions
end

function RoadSplineData.collectSplineRecords(root, options)
	options = options or {}
	local defaultWidth = options.defaultRoadWidth
	local minPoints = options.minPoints or 2
	local records = {}

	for _, spline in ipairs(RoadSplineData.getSplines(root)) do
		local points = RoadSplineData.getSplinePoints(spline)
		local positions = RoadSplineData.getPointPositions(points)
		if #positions >= minPoints then
			table.insert(records, {
				spline = spline,
				name = spline.Name,
				points = points,
				positions = positions,
				closed = spline:GetAttribute("ClosedCurve") == true,
				sampled = spline:GetAttribute("SampledRoadChain") == true,
				width = RoadSampling.getSplineRoadWidth(spline, defaultWidth),
				componentId = tonumber(spline:GetAttribute("ComponentId")) or 1,
			})
		end
	end

	return records
end

function RoadSplineData.collectSampledChains(root, options)
	options = options or {}
	local sampleStep = options.sampleStep or 8
	local preserveSampledChains = options.preserveSampledChains ~= false
	local chains = {}

	for _, record in ipairs(RoadSplineData.collectSplineRecords(root, options)) do
		local samples
		if preserveSampledChains and record.sampled then
			samples = {}
			for _, position in ipairs(record.positions) do
				table.insert(samples, position)
			end
		else
			samples = RoadSampling.samplePositions(record.positions, record.closed, sampleStep)
		end

		table.insert(chains, {
			spline = record.spline,
			name = record.name,
			points = record.points,
			positions = record.positions,
			samples = samples,
			closed = record.closed,
			sampled = record.sampled,
			width = record.width,
			componentId = record.componentId,
		})
	end

	return chains
end

function RoadSplineData.collectJunctions(root, options)
	options = options or {}
	local junctionsFolder = root and root:FindFirstChild(RoadSplineData.JUNCTIONS_NAME)
	if not (junctionsFolder and junctionsFolder:IsA("Folder")) then
		return {}
	end

	local defaultRadius = tonumber(options.defaultRadius) or RoadSampling.DEFAULT_ROAD_WIDTH * 0.5
	local minRadius = tonumber(options.minRadius) or 0
	local junctions = {}
	for _, junctionData in ipairs(RoadSplineData.sortedChildren(junctionsFolder)) do
		local center = nil
		if junctionData:IsA("Vector3Value") then
			center = junctionData.Value
		elseif junctionData:IsA("BasePart") then
			center = junctionData.Position
		end

		if center then
			local radius = math.max(tonumber(junctionData:GetAttribute("Radius")) or defaultRadius, minRadius)
			local subdivisions = RoadSplineData.sanitizeJunctionSubdivisions(junctionData:GetAttribute(RoadSplineData.JUNCTION_SUBDIVISIONS_ATTR))
			local crosswalkLength = RoadSplineData.sanitizeJunctionCrosswalkLength(junctionData:GetAttribute(RoadSplineData.JUNCTION_CROSSWALK_LENGTH_ATTR))
			table.insert(junctions, {
				instance = junctionData,
				name = junctionData.Name,
				center = center,
				radius = radius,
				crosswalkLength = crosswalkLength,
				subdivisions = subdivisions,
				componentId = tonumber(junctionData:GetAttribute("ComponentId")) or 1,
				portalAttachDistance = tonumber(junctionData:GetAttribute(RoadSplineData.JUNCTION_PORTAL_ATTACH_DISTANCE_ATTR)),
				members = {},
				chains = {},
			})
		end
	end
	return junctions
end

return RoadSplineData
