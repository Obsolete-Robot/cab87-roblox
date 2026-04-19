local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local AuthoredRoadRuntime = {}

local ROAD_EDITOR_ROOT_NAME = "Cab87RoadEditor"
local ROAD_EDITOR_SPLINES_NAME = "Splines"
local ROAD_EDITOR_POINTS_NAME = "RoadPoints"
local ROAD_EDITOR_NETWORK_NAME = "RoadNetwork"
local ROAD_EDITOR_WIREFRAME_NAME = "WireframeDisplay"
local RUNTIME_WORLD_NAME = "Cab87World"

local function vectorToYaw(vector)
	return math.atan2(vector.X, vector.Z)
end

local function makePart(parent, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local function sortedChildren(parent, className)
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

local function getAuthoredSplines(root)
	local splinesFolder = root and root:FindFirstChild(ROAD_EDITOR_SPLINES_NAME)
	if splinesFolder and splinesFolder:IsA("Folder") then
		return sortedChildren(splinesFolder, "Model")
	end

	local legacyPoints = root and root:FindFirstChild(ROAD_EDITOR_POINTS_NAME)
	if legacyPoints and legacyPoints:IsA("Folder") then
		return { root }
	end

	return {}
end

local function getAuthoredSplinePoints(spline)
	local pointsFolder = spline and spline:FindFirstChild(ROAD_EDITOR_POINTS_NAME)
	if not (pointsFolder and pointsFolder:IsA("Folder")) then
		return {}
	end

	return sortedChildren(pointsFolder, "BasePart")
end

local function hasAncestorNamed(instance, ancestorName)
	local current = instance.Parent
	while current do
		if current.Name == ancestorName then
			return true
		end
		current = current.Parent
	end

	return false
end

local function countRoadSurfaceParts(root)
	local count = 0
	if not root then
		return count
	end

	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") and not hasAncestorNamed(item, ROAD_EDITOR_WIREFRAME_NAME) then
			count += 1
		end
	end

	return count
end

local function removeEditorDebugVisuals(root)
	if not root then
		return
	end

	for _, item in ipairs(root:GetDescendants()) do
		if item.Name == ROAD_EDITOR_WIREFRAME_NAME then
			item:Destroy()
		end
	end
end

local function catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

local function sampleAuthoredSpline(points, closedCurve)
	local positions = {}
	for _, point in ipairs(points) do
		table.insert(positions, point.Position)
	end

	if #positions < 2 then
		return positions
	end

	if closedCurve and #positions < 3 then
		closedCurve = false
	end

	local samples = {}
	local sampleStep = math.max(Config.authoredRoadSampleStepStuds, 1)
	if closedCurve then
		local count = #positions
		for i = 1, count do
			local p0 = positions[((i - 2) % count) + 1]
			local p1 = positions[i]
			local p2 = positions[(i % count) + 1]
			local p3 = positions[((i + 1) % count) + 1]
			local segmentLen = (p2 - p1).Magnitude
			local subdivisions = math.max(2, math.floor(segmentLen / sampleStep))

			for s = 0, subdivisions - 1 do
				table.insert(samples, catmullRom(p0, p1, p2, p3, s / subdivisions))
			end
		end

		if #samples > 1 then
			table.insert(samples, samples[1])
		end
	else
		for i = 1, #positions - 1 do
			local p0 = positions[math.max(1, i - 1)]
			local p1 = positions[i]
			local p2 = positions[i + 1]
			local p3 = positions[math.min(#positions, i + 2)]
			local segmentLen = (p2 - p1).Magnitude
			local subdivisions = math.max(2, math.floor(segmentLen / sampleStep))

			for s = 0, subdivisions - 1 do
				table.insert(samples, catmullRom(p0, p1, p2, p3, s / subdivisions))
			end
		end

		table.insert(samples, positions[#positions])
	end

	return samples
end

local function configureRuntimePart(part, canQuery)
	part.Anchored = true
	part.CanCollide = canQuery
	part.CanQuery = canQuery
	part.CanTouch = false
end

local function trackPart(list, part)
	table.insert(list, part)
	return part
end

local function createCollisionSegment(parent, a, b, index, visible)
	local delta = b - a
	local len = delta.Magnitude
	if len <= 0.05 then
		return nil
	end

	local thickness = math.max(Config.authoredRoadCollisionThickness, 0.05)
	local surfaceOffset = Config.authoredRoadCollisionSurfaceOffset
	local verticalOffset = Vector3.new(0, surfaceOffset - thickness * 0.5, 0)
	local mid = (a + b) * 0.5 + verticalOffset
	local part = makePart(parent, {
		Name = string.format("AuthoredRoadCollision_%04d", index),
		Size = Vector3.new(Config.authoredRoadCollisionWidth, thickness, len + Config.authoredRoadOverlap),
		CFrame = CFrame.lookAt(mid, b + verticalOffset),
		Transparency = visible and 0 or 1,
		Color = Color3.fromRGB(28, 28, 32),
		Material = Enum.Material.Asphalt,
	})
	configureRuntimePart(part, true)
	part:SetAttribute("DriveSurface", true)
	return part
end

local function createCollisionCap(parent, position, index, visible)
	local thickness = math.max(Config.authoredRoadCollisionThickness, 0.05)
	local surfaceOffset = Config.authoredRoadCollisionSurfaceOffset
	local cap = makePart(parent, {
		Name = string.format("AuthoredRoadCollisionCap_%04d", index),
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, Config.authoredRoadCollisionWidth, Config.authoredRoadCollisionWidth),
		CFrame = CFrame.new(position + Vector3.new(0, surfaceOffset - thickness * 0.5, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Transparency = visible and 0 or 1,
		Color = Color3.fromRGB(28, 28, 32),
		Material = Enum.Material.Asphalt,
	})
	configureRuntimePart(cap, true)
	cap:SetAttribute("DriveSurface", true)
	return cap
end

local function findFirstSpawn(root)
	for _, spline in ipairs(getAuthoredSplines(root)) do
		local points = getAuthoredSplinePoints(spline)
		if #points > 0 then
			local spawnPosition = points[1].Position + Vector3.new(0, Config.carRideHeight, 0)
			local spawnYaw = 0

			if #points >= 2 then
				local delta = points[2].Position - points[1].Position
				local horizontal = Vector3.new(delta.X, 0, delta.Z)
				if horizontal.Magnitude > 0.001 then
					spawnYaw = vectorToYaw(horizontal.Unit)
				end
			end

			return {
				position = spawnPosition,
				yaw = spawnYaw,
			}
		end
	end

	return {
		position = Config.carSpawn,
		yaw = 0,
	}
end

local function hideEditorRootForPlay(root)
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Transparency = 1
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
end

local function cloneRoadVisuals(root, world)
	local network = root:FindFirstChild(ROAD_EDITOR_NETWORK_NAME)
	if not (network and network:IsA("Model")) or countRoadSurfaceParts(network) == 0 then
		return nil, 0
	end

	local clone = network:Clone()
	clone.Name = "AuthoredRoadVisuals"
	removeEditorDebugVisuals(clone)
	clone.Parent = world

	for _, item in ipairs(clone:GetDescendants()) do
		if item:IsA("BasePart") then
			configureRuntimePart(item, false)
		end
	end

	return clone, countRoadSurfaceParts(clone)
end

local function buildCollision(root, world, driveSurfaces, visible)
	local collisionModel = Instance.new("Model")
	collisionModel.Name = "AuthoredRoadCollision"
	collisionModel.Parent = world

	local segmentIndex = 0
	local capIndex = 0

	for _, spline in ipairs(getAuthoredSplines(root)) do
		local points = getAuthoredSplinePoints(spline)
		if #points >= 2 then
			local samples = sampleAuthoredSpline(points, spline:GetAttribute("ClosedCurve") == true)
			for i = 1, #samples - 1 do
				segmentIndex += 1
				local part = createCollisionSegment(collisionModel, samples[i], samples[i + 1], segmentIndex, visible)
				if part then
					trackPart(driveSurfaces, part)
				end
			end
		end

		for _, point in ipairs(points) do
			capIndex += 1
			trackPart(driveSurfaces, createCollisionCap(collisionModel, point.Position, capIndex, visible))
		end
	end

	return segmentIndex
end

local function useRoadNetworkFallback(network, driveSurfaces)
	if not (network and network:IsA("Model")) then
		return 0
	end

	local count = 0
	for _, item in ipairs(network:GetDescendants()) do
		if item:IsA("BasePart") and not hasAncestorNamed(item, ROAD_EDITOR_WIREFRAME_NAME) then
			configureRuntimePart(item, true)
			item:SetAttribute("DriveSurface", true)
			trackPart(driveSurfaces, item)
			count += 1
		end
	end

	return count
end

function AuthoredRoadRuntime.getRoot()
	local root = Workspace:FindFirstChild(ROAD_EDITOR_ROOT_NAME)
	if root and root:IsA("Model") then
		return root
	end

	return nil
end

function AuthoredRoadRuntime.hasRoadData(root)
	if Config.useAuthoredRoadEditorWorld ~= true or not root then
		return false
	end

	for _, spline in ipairs(getAuthoredSplines(root)) do
		if #getAuthoredSplinePoints(spline) >= 2 then
			return true
		end
	end

	local network = root:FindFirstChild(ROAD_EDITOR_NETWORK_NAME)
	if network and network:IsA("Model") then
		return countRoadSurfaceParts(network) > 0
	end

	return false
end

function AuthoredRoadRuntime.createWorld(root)
	local oldWorld = Workspace:FindFirstChild(RUNTIME_WORLD_NAME)
	if oldWorld then
		oldWorld:Destroy()
	end

	local world = Instance.new("Model")
	world.Name = RUNTIME_WORLD_NAME
	world:SetAttribute("GeneratorVersion", "authored-road-editor")
	world:SetAttribute("Source", ROAD_EDITOR_ROOT_NAME)
	world.Parent = Workspace

	local driveSurfaces = {}
	local crashObstacles = {}
	local spawnPose = findFirstSpawn(root)

	local visualClone, visualPartCount = cloneRoadVisuals(root, world)
	local collisionSegments = buildCollision(root, world, driveSurfaces, false)
	if collisionSegments == 0 then
		useRoadNetworkFallback(visualClone or root:FindFirstChild(ROAD_EDITOR_NETWORK_NAME), driveSurfaces)
	end
	hideEditorRootForPlay(root)

	return world, driveSurfaces, crashObstacles, spawnPose
end

return AuthoredRoadRuntime
