local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoadSampling = require(Shared:WaitForChild("RoadSampling"))
local RoadSplineData = require(Shared:WaitForChild("RoadSplineData"))

if Config.useAuthoredRoadEditorWorld ~= true then
	return
end

local ROAD_EDITOR_ROOT_NAME = RoadSplineData.EDITOR_ROOT_NAME
local ROAD_EDITOR_SPLINES_NAME = RoadSplineData.SPLINES_NAME
local ROAD_EDITOR_POINTS_NAME = RoadSplineData.POINTS_NAME
local ROAD_WIDTH_ATTR = RoadSplineData.ROAD_WIDTH_ATTR
local RUNTIME_WORLD_NAME = "Cab87World"
local RUNTIME_SPLINE_DATA_NAME = RoadSplineData.RUNTIME_DATA_NAME
local CLIENT_VISUALS_NAME = "AuthoredRoadClientVisuals"

local DEFAULT_AUTHORED_ROAD_WIDTH = RoadSampling.DEFAULT_ROAD_WIDTH
local ROAD_MESH_THICKNESS = 1.2
local ENDPOINT_WELD_DISTANCE = 22
local INTERSECTION_RADIUS_SCALE = 0.5
local INTERSECTION_BLEND_SCALE = 0.95
local INTERSECTION_MERGE_SCALE = 0.45
local INTERSECTION_RING_SEGMENTS = 28
local JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE = 0.5
local ROAD_EDGE_MITER_LIMIT = 2.75
local ROAD_EDGE_SMOOTH_PASSES = 2
local ROAD_EDGE_SMOOTH_ALPHA = 0.35
local ROAD_WIDTH_TRIANGULATION_STEP = 24
local ROAD_WIDTH_MAX_INTERNAL_LOOPS = 2
local ROAD_LOFT_LENGTH_STEP = Config.authoredRoadSampleStepStuds or 8
local ROAD_EDGE_CURVE_SMOOTH_STEP = math.max(1, ROAD_LOFT_LENGTH_STEP * 0.25)
local ROAD_EDGE_CURVE_FAIR_PASSES = 4
local ROAD_EDGE_CURVE_FAIR_ALPHA = 0.42
local ROAD_CURVE_EXPANSION_PASSES = 0
local ROAD_CURVE_EXPANSION_ALPHA = 0.8
local ROAD_INNER_EDGE_RADIUS_SCALE = 0.08
local INTERSECTION_HEIGHT_TOLERANCE_MIN = ROAD_MESH_THICKNESS * 2
local INTERSECTION_HEIGHT_TOLERANCE_MAX = ROAD_MESH_THICKNESS * 4
local INTERSECTION_HEIGHT_TOLERANCE_WIDTH_SCALE = 0.18
local ROAD_LOG_PREFIX = "[cab87 roads client]"

local function formatLogMessage(message, ...)
	local ok, formatted = pcall(string.format, tostring(message), ...)
	if ok then
		return formatted
	end
	return tostring(message)
end

local function roadDebugLog(message, ...)
	if Config.authoredRoadDebugLogging == true then
		print(ROAD_LOG_PREFIX .. " " .. formatLogMessage(message, ...))
	end
end

local function roadDebugWarn(message, ...)
	warn(ROAD_LOG_PREFIX .. " " .. formatLogMessage(message, ...))
end

local dataModelContentWarningShown = false
local watchedWorld = nil
local watchedAttributeConnection = nil
local watchedChildConnection = nil
local buildSerial = 0

local function setWorldStatus(world, status, errorMessage, parts, spans)
	if not world then
		return
	end

	world:SetAttribute("AuthoredRoadClientMeshStatus", status)
	world:SetAttribute("AuthoredRoadClientMeshError", errorMessage or "")
	world:SetAttribute("AuthoredRoadClientMeshParts", parts or 0)
	world:SetAttribute("AuthoredRoadClientMeshSpans", spans or 0)
end

local function hideEditorDebugGeometry()
	local editorRoot = Workspace:FindFirstChild(ROAD_EDITOR_ROOT_NAME)
	if not editorRoot then
		return
	end

	for _, item in ipairs(editorRoot:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Transparency = 1
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
end

local sanitizeRoadWidth = RoadSampling.sanitizeRoadWidth
local distanceXZ = RoadSampling.distanceXZ
local horizontalUnit = RoadSampling.horizontalUnit
local catmullRom = RoadSampling.catmullRom
local sampleLoopIsClosed = RoadSampling.sampleLoopIsClosed
local getRoadSampleTangent = RoadSampling.getRoadSampleTangent
local polylineLength = RoadSampling.polylineLength
local samplePolylineAtFraction = RoadSampling.samplePolylineAtFraction
local roadRightFromTangent

local function crossXZ(a, b)
	return a.X * b.Z - a.Z * b.X
end

local function heightConnectTolerance(widthA, widthB)
	local width = math.min(sanitizeRoadWidth(widthA), sanitizeRoadWidth(widthB))
	return math.clamp(
		width * INTERSECTION_HEIGHT_TOLERANCE_WIDTH_SCALE,
		INTERSECTION_HEIGHT_TOLERANCE_MIN,
		INTERSECTION_HEIGHT_TOLERANCE_MAX
	)
end

local function positionsConnectIn3D(a, b, widthA, widthB)
	return math.abs(a.Y - b.Y) <= heightConnectTolerance(widthA, widthB)
end

local function collectSplineBuildData(root)
	return RoadSplineData.collectSampledChains(root, {
		defaultRoadWidth = RoadSampling.getConfiguredRoadWidth(Config),
		sampleStep = Config.authoredRoadSampleStepStuds,
	})
end

local function getChainName(chain, fallback)
	return (chain and chain.name) or fallback or "unknown"
end

local function collectProcessedJunctions(root)
	return RoadSplineData.collectJunctions(root, {
		defaultRadius = DEFAULT_AUTHORED_ROAD_WIDTH * INTERSECTION_RADIUS_SCALE,
	})
end

local function addPortalForChain(junction, chain, boundaryPoint, outsidePoint)
	if not junction or not chain or not outsidePoint then
		return
	end

	local tangent = horizontalUnit(outsidePoint - boundaryPoint)
		or horizontalUnit(boundaryPoint - junction.center)
		or Vector3.zAxis
	local right = roadRightFromTangent(tangent)
	local halfWidth = sanitizeRoadWidth(chain.width) * 0.5
	table.insert(junction.portals, {
		junction = junction,
		chain = chain,
		boundaryPoint = boundaryPoint,
		outsidePoint = outsidePoint,
		point = boundaryPoint,
		tangent = tangent,
		halfWidth = halfWidth,
		left = boundaryPoint - right * halfWidth,
		right = boundaryPoint + right * halfWidth,
	})
	junction.chains[chain] = true
end

local function portalLineT(portal, point)
	return (point - portal.boundaryPoint):Dot(portal.tangent)
end

local function portalLinePointAtT(portal, t)
	return Vector3.new(
		portal.boundaryPoint.X + portal.tangent.X * t,
		portal.boundaryPoint.Y,
		portal.boundaryPoint.Z + portal.tangent.Z * t
	)
end

local function getJunctionMeshCenter(junction)
	return junction.intersectionCenter or junction.center
end

local function computeJunctionIntersectionCenter(junction)
	local portals = junction.portals or {}
	if #portals == 0 then
		return junction.center
	end

	local sum = Vector3.zero
	for _, portal in ipairs(portals) do
		sum += portal.corePoint or portal.boundaryPoint or portal.point
	end
	return sum / #portals
end

local function appendUniqueJunctionPoint(points, point)
	for _, existing in ipairs(points) do
		if distanceXZ(existing, point) <= 0.05 then
			return
		end
	end
	table.insert(points, point)
end

local function junctionHullCrossXZ(origin, a, b)
	return (a.X - origin.X) * (b.Z - origin.Z) - (a.Z - origin.Z) * (b.X - origin.X)
end

local function junctionConvexHullXZ(points)
	if #points < 3 then
		return points
	end

	local sorted = {}
	for _, point in ipairs(points) do
		table.insert(sorted, point)
	end
	table.sort(sorted, function(a, b)
		if math.abs(a.X - b.X) > 0.001 then
			return a.X < b.X
		end
		return a.Z < b.Z
	end)

	local lower = {}
	for _, point in ipairs(sorted) do
		while #lower >= 2 and junctionHullCrossXZ(lower[#lower - 1], lower[#lower], point) <= 0.001 do
			table.remove(lower)
		end
		table.insert(lower, point)
	end

	local upper = {}
	for i = #sorted, 1, -1 do
		local point = sorted[i]
		while #upper >= 2 and junctionHullCrossXZ(upper[#upper - 1], upper[#upper], point) <= 0.001 do
			table.remove(upper)
		end
		table.insert(upper, point)
	end

	table.remove(lower, #lower)
	table.remove(upper, #upper)
	local hull = {}
	for _, point in ipairs(lower) do
		table.insert(hull, point)
	end
	for _, point in ipairs(upper) do
		table.insert(hull, point)
	end

	if #hull < 3 then
		return points
	end
	return hull
end

local function lineIntersectionWithParametersXZ(a, dirA, b, dirB)
	local denom = crossXZ(dirA, dirB)
	if math.abs(denom) < 1e-5 then
		return nil
	end

	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local tA = (dx * dirB.Z - dz * dirB.X) / denom
	local tB = (dx * dirA.Z - dz * dirA.X) / denom
	return Vector3.new(a.X + dirA.X * tA, a.Y, a.Z + dirA.Z * tA), tA, tB
end

local function junctionCoreBoundaryLimit(junction)
	local center = getJunctionMeshCenter(junction)
	local limit = 8
	for _, portal in ipairs(junction.portals or {}) do
		local width = (portal.halfWidth or 0) * 2
		limit = math.max(
			limit,
			width * 3,
			distanceXZ(portal.boundaryPoint, center) + width * 2
		)
	end
	return limit
end

local function portalSideLine(portal, sideSign)
	local right = roadRightFromTangent(portal.tangent)
	local center = getJunctionMeshCenter(portal.junction)
	local basePoint = portalLinePointAtT(portal, portalLineT(portal, center))
	local point = basePoint + right * ((portal.halfWidth or 0) * sideSign)
	return {
		portal = portal,
		point = point,
		dir = portal.tangent,
		sideSign = sideSign,
	}
end

local function collectPortalSideLines(junction)
	local lines = {}
	for _, portal in ipairs(junction.portals or {}) do
		table.insert(lines, portalSideLine(portal, -1))
		table.insert(lines, portalSideLine(portal, 1))
	end
	return lines
end

local function sortedJunctionPortals(junction)
	local portals = {}
	for _, portal in ipairs(junction.portals or {}) do
		table.insert(portals, portal)
	end
	table.sort(portals, function(a, b)
		return math.atan2(a.tangent.Z, a.tangent.X) < math.atan2(b.tangent.Z, b.tangent.X)
	end)
	return portals
end

local function appendOrderedJunctionPoint(points, point)
	if #points == 0 or distanceXZ(points[#points], point) > 0.05 then
		table.insert(points, point)
	end
end

local function finalizeOrderedJunctionBoundary(points)
	if #points >= 2 and distanceXZ(points[1], points[#points]) <= 0.05 then
		table.remove(points, #points)
	end
	return points
end

local function junctionGapPoints(center, fromPortal, toPortal)
	local fromRight = roadRightFromTangent(fromPortal.tangent)
	local toRight = roadRightFromTangent(toPortal.tangent)
	local fromHalfWidth = fromPortal.halfWidth or 0
	local toHalfWidth = toPortal.halfWidth or 0
	local fromSide = center - fromRight * fromHalfWidth
	local toSide = center + toRight * toHalfWidth
	local maxExtension = math.max(fromHalfWidth, toHalfWidth) * 1.5 + 50

	local intersection, fromT, toT = lineIntersectionWithParametersXZ(fromSide, fromPortal.tangent, toSide, toPortal.tangent)
	if intersection and fromT >= 0 and toT >= 0 and fromT <= maxExtension and toT <= maxExtension then
		local point = Vector3.new(intersection.X, center.Y, intersection.Z)
		return point, point, { point }
	end

	local safeFromT = math.clamp(fromT or 0, 0, maxExtension)
	local safeToT = math.clamp(toT or 0, 0, maxExtension)
	local fromPoint = Vector3.new(
		fromSide.X + fromPortal.tangent.X * safeFromT,
		center.Y,
		fromSide.Z + fromPortal.tangent.Z * safeFromT
	)
	local toPoint = Vector3.new(
		toSide.X + toPortal.tangent.X * safeToT,
		center.Y,
		toSide.Z + toPortal.tangent.Z * safeToT
	)
	if distanceXZ(fromPoint, toPoint) <= 0.05 then
		local point = (fromPoint + toPoint) * 0.5
		return point, point, { point }
	end
	return fromPoint, toPoint, { fromPoint, toPoint }
end

local function buildJunctionCoreBoundary(junction)
	local portals = sortedJunctionPortals(junction)
	if #portals < 2 then
		return {}
	end

	local center = getJunctionMeshCenter(junction)
	local boundary = {}
	for _, portal in ipairs(portals) do
		portal.coreLeft = nil
		portal.coreRight = nil
	end

	for i, portal in ipairs(portals) do
		local nextPortal = portals[(i % #portals) + 1]
		local fromPoint, toPoint, points = junctionGapPoints(center, portal, nextPortal)
		portal.coreLeft = fromPoint
		nextPortal.coreRight = toPoint
		for _, point in ipairs(points) do
			appendOrderedJunctionPoint(boundary, point)
		end
	end

	if #boundary < 3 then
		local fallback = {}
		for _, portal in ipairs(portals) do
			local right = roadRightFromTangent(portal.tangent)
			appendUniqueJunctionPoint(fallback, center + right * (portal.halfWidth or 0))
			appendUniqueJunctionPoint(fallback, center - right * (portal.halfWidth or 0))
		end
		return junctionConvexHullXZ(fallback)
	end

	return finalizeOrderedJunctionBoundary(boundary)
end

local function buildJunctionSurfaceBoundary(junction)
	local boundary = {}
	for _, point in ipairs(junction.coreBoundary or {}) do
		table.insert(boundary, point)
	end
	return boundary
end

local function pointLineDistanceXZ(point, linePoint, lineDir)
	return math.abs(crossXZ(point - linePoint, lineDir))
end

local function boundaryPointOnPortalSide(boundary, portal, sideSign)
	local line = portalSideLine(portal, sideSign)
	local best = nil
	local bestT = -math.huge

	local function consider(point)
		if pointLineDistanceXZ(point, line.point, line.dir) > 0.08 then
			return
		end
		local t = portalLineT(portal, point)
		if t > bestT then
			best = Vector3.new(point.X, line.point.Y, point.Z)
			bestT = t
		end
	end

	for _, point in ipairs(boundary) do
		consider(point)
	end

	if not best and #boundary >= 2 then
		for i = 1, #boundary do
			local a = boundary[i]
			local b = boundary[(i % #boundary) + 1]
			local edge = b - a
			if edge.Magnitude > 1e-4 then
				local intersection, _, edgeT = lineIntersectionWithParametersXZ(line.point, line.dir, a, edge)
				if intersection and edgeT >= -0.001 and edgeT <= 1.001 then
					consider(intersection)
				end
			end
		end
	end

	return best
end

local function annotateProcessedPortalCore(junction, portal)
	local corePoint = portal.point
	local right = roadRightFromTangent(portal.tangent)
	portal.boundaryPoint = corePoint
	portal.corePoint = corePoint
	portal.coreLeft = corePoint - right * portal.halfWidth
	portal.coreRight = corePoint + right * portal.halfWidth
	portal.coreT = 0
	portal.mouthT = 0
end

local function updateProcessedPortalCoreGeometry(junction, portal)
	local right = roadRightFromTangent(portal.tangent)
	local center = getJunctionMeshCenter(junction)
	local coreLeft = portal.coreLeft or (center - right * portal.halfWidth)
	local coreRight = portal.coreRight or (center + right * portal.halfWidth)
	if (coreRight - coreLeft):Dot(right) < 0 then
		coreLeft, coreRight = coreRight, coreLeft
	end

	portal.coreLeft = coreLeft
	portal.coreRight = coreRight
	portal.corePoint = (coreLeft + coreRight) * 0.5
	portal.coreT = portalLineT(portal, portal.corePoint)
	portal.mouthT = portalLineT(portal, portal.point)
end

local function attachProcessedChainEndpointsToJunctions(chains, junctions)
	for _, junction in ipairs(junctions) do
		junction.portals = {}
		junction.chains = {}
	end

	for _, chain in ipairs(chains) do
		if #chain.samples >= 2 then
			local first = chain.samples[1]
			local second = chain.samples[2]
			local last = chain.samples[#chain.samples]
			local beforeLast = chain.samples[#chain.samples - 1]
			for _, junction in ipairs(junctions) do
				local tolerance = math.max(1, chain.width * 0.08)
				local attachDistance = math.max(
					junction.radius,
					tonumber(junction.portalAttachDistance) or 0,
					junction.radius
						+ RoadSplineData.sanitizeJunctionCrosswalkLength(junction.crosswalkLength)
						+ sanitizeRoadWidth(chain.width)
				) + tolerance
				if chain.componentId == junction.componentId and distanceXZ(first, junction.center) <= attachDistance then
					addPortalForChain(junction, chain, first, second)
				end
				if chain.componentId == junction.componentId and distanceXZ(last, junction.center) <= attachDistance then
					addPortalForChain(junction, chain, last, beforeLast)
				end
			end
		end
	end

	for _, junction in ipairs(junctions) do
		for _, portal in ipairs(junction.portals or {}) do
			annotateProcessedPortalCore(junction, portal)
		end
		junction.intersectionCenter = junction.center
		junction.coreBoundary = buildJunctionCoreBoundary(junction)
		for _, portal in ipairs(junction.portals or {}) do
			updateProcessedPortalCoreGeometry(junction, portal)
		end
		junction.surfaceBoundary = buildJunctionSurfaceBoundary(junction)
	end
end

local function buildProcessedComponents(chains, junctions)
	local byId = {}
	local components = {}

	local function getComponent(componentId)
		local id = componentId or 1
		local component = byId[id]
		if not component then
			component = {
				id = id,
				chains = {},
				junctions = {},
			}
			byId[id] = component
			table.insert(components, component)
		end
		return component
	end

	for _, chain in ipairs(chains) do
		table.insert(getComponent(chain.componentId).chains, chain)
	end

	for _, junction in ipairs(junctions) do
		table.insert(getComponent(junction.componentId).junctions, junction)
	end

	table.sort(components, function(a, b)
		return a.id < b.id
	end)
	return components
end

local function maxRoadWidthForMembers(members)
	local width = nil
	for _, member in ipairs(members) do
		if member.chain then
			width = math.max(width or 0, member.chain.width)
		end
	end
	return width or DEFAULT_AUTHORED_ROAD_WIDTH
end

local function collectEndpointJunctions(chains)
	local endpoints = {}
	for _, chain in ipairs(chains) do
		if not chain.closed and #chain.samples >= 2 then
			table.insert(endpoints, { chain = chain, index = 1, pos = chain.samples[1] })
			table.insert(endpoints, { chain = chain, index = #chain.samples, pos = chain.samples[#chain.samples] })
		end
	end

	local clusters = {}
	for _, endpoint in ipairs(endpoints) do
		local placed = false
		local endpointWidth = endpoint.chain.width
		for _, cluster in ipairs(clusters) do
			local weldDistance = math.max(ENDPOINT_WELD_DISTANCE, math.max(cluster.width, endpointWidth) * 0.8)
			if distanceXZ(cluster.center, endpoint.pos) <= weldDistance and positionsConnectIn3D(cluster.center, endpoint.pos, cluster.width, endpointWidth) then
				table.insert(cluster.members, endpoint)
				cluster.width = math.max(cluster.width, endpointWidth)
				local sum = Vector3.zero
				for _, member in ipairs(cluster.members) do
					sum += member.pos
				end
				cluster.center = sum / #cluster.members
				placed = true
				break
			end
		end
		if not placed then
			table.insert(clusters, { center = endpoint.pos, members = { endpoint }, width = endpointWidth })
		end
	end

	local junctions = {}
	for _, cluster in ipairs(clusters) do
		if #cluster.members >= 2 then
			table.insert(junctions, {
				center = cluster.center,
				members = cluster.members,
			})
		end
	end
	return junctions
end

local function segmentIntersection2D(a, b, c, d)
	local function cross2(u, v)
		return u.X * v.Y - u.Y * v.X
	end

	local p = Vector2.new(a.X, a.Z)
	local r = Vector2.new(b.X - a.X, b.Z - a.Z)
	local q = Vector2.new(c.X, c.Z)
	local s = Vector2.new(d.X - c.X, d.Z - c.Z)
	local denom = cross2(r, s)
	if math.abs(denom) < 1e-6 then
		return nil
	end

	local qp = q - p
	local t = cross2(qp, s) / denom
	local u = cross2(qp, r) / denom
	local endpointEpsilon = 1e-4
	if t < -endpointEpsilon or t > 1 + endpointEpsilon or u < -endpointEpsilon or u > 1 + endpointEpsilon then
		return nil
	end

	t = math.clamp(t, 0, 1)
	u = math.clamp(u, 0, 1)
	return t, u
end

local function collectCrossIntersections(chains)
	local junctions = {}
	for i = 1, #chains do
		local aChain = chains[i]
		for j = i + 1, #chains do
			local bChain = chains[j]
			for ai = 1, #aChain.samples - 1 do
				local a1 = aChain.samples[ai]
				local a2 = aChain.samples[ai + 1]
				for bi = 1, #bChain.samples - 1 do
					local b1 = bChain.samples[bi]
					local b2 = bChain.samples[bi + 1]
					local aT, bT = segmentIntersection2D(a1, a2, b1, b2)
					if aT and bT then
						local aPos = a1 + (a2 - a1) * aT
						local bPos = b1 + (b2 - b1) * bT
						if positionsConnectIn3D(aPos, bPos, aChain.width, bChain.width) then
							local pos = (aPos + bPos) * 0.5
							table.insert(junctions, {
								center = pos,
								members = {
									{ chain = aChain, segment = ai, t = aT, pos = pos },
									{ chain = bChain, segment = bi, t = bT, pos = pos },
								},
							})
						end
					end
				end
			end
		end
	end
	return junctions
end

local function mergeJunctions(rawJunctions)
	local clusters = {}
	for _, junction in ipairs(rawJunctions) do
		local placed = false
		local junctionWidth = maxRoadWidthForMembers(junction.members)
		for _, cluster in ipairs(clusters) do
			local mergeDistance = math.max(cluster.width, junctionWidth) * INTERSECTION_MERGE_SCALE
			if distanceXZ(cluster.center, junction.center) <= mergeDistance and positionsConnectIn3D(cluster.center, junction.center, cluster.width, junctionWidth) then
				for _, member in ipairs(junction.members) do
					table.insert(cluster.members, member)
				end
				cluster.width = math.max(cluster.width, junctionWidth)
				local sum = Vector3.zero
				for _, member in ipairs(cluster.members) do
					sum += member.pos or junction.center
				end
				cluster.center = sum / #cluster.members
				placed = true
				break
			end
		end
		if not placed then
			local members = {}
			for _, member in ipairs(junction.members) do
				table.insert(members, member)
			end
			table.insert(clusters, { center = junction.center, members = members, width = junctionWidth })
		end
	end

	local junctions = {}
	for _, cluster in ipairs(clusters) do
		local radius = cluster.width * INTERSECTION_RADIUS_SCALE
		local blendRadius = math.max(cluster.width * INTERSECTION_BLEND_SCALE, radius + 0.05)
		local chainLookup = {}
		for _, member in ipairs(cluster.members) do
			if member.chain then
				chainLookup[member.chain] = true
			end
		end
		table.insert(junctions, {
			center = cluster.center,
			members = cluster.members,
			chains = chainLookup,
			width = cluster.width,
			radius = radius,
			blendRadius = blendRadius,
		})
	end
	return junctions
end

local function applyJunctionsToChains(chains, junctions)
	local insertsByChain = {}
	for _, junction in ipairs(junctions) do
		for _, member in ipairs(junction.members) do
			if member.index then
				member.chain.samples[member.index] = junction.center
			elseif member.segment and member.t then
				local inserts = insertsByChain[member.chain]
				if not inserts then
					inserts = {}
					insertsByChain[member.chain] = inserts
				end
				table.insert(inserts, { segment = member.segment, t = member.t, pos = junction.center })
			end
		end
	end

	for chain, inserts in pairs(insertsByChain) do
		table.sort(inserts, function(a, b)
			if a.segment == b.segment then
				return a.t > b.t
			end
			return a.segment > b.segment
		end)

		for _, insert in ipairs(inserts) do
			local before = chain.samples[insert.segment]
			local after = chain.samples[insert.segment + 1]
			if before and after and distanceXZ(before, insert.pos) > 0.05 and distanceXZ(after, insert.pos) > 0.05 then
				table.insert(chain.samples, insert.segment + 1, insert.pos)
			end
		end
	end

	for _, chain in ipairs(chains) do
		for i, sample in ipairs(chain.samples) do
			local bestJunction = nil
			local bestDistance = math.huge
			for _, junction in ipairs(junctions) do
				if junction.chains and junction.chains[chain] then
					local d = distanceXZ(sample, junction.center)
					local blendRadius = junction.blendRadius or (junction.radius + 0.05)
					if d <= blendRadius and d < bestDistance then
						bestDistance = d
						bestJunction = junction
					end
				end
			end

			if bestJunction then
				local alpha
				if bestDistance <= bestJunction.radius then
					alpha = 1
				else
					local blendRadius = bestJunction.blendRadius or (bestJunction.radius + 0.05)
					alpha = 1 - ((bestDistance - bestJunction.radius) / math.max(blendRadius - bestJunction.radius, 0.001))
					alpha = math.clamp(alpha, 0, 1)
				end

				chain.samples[i] = Vector3.new(sample.X, sample.Y + (bestJunction.center.Y - sample.Y) * alpha, sample.Z)
			end
		end

		if chain.closed and #chain.samples > 2 then
			chain.samples[#chain.samples] = chain.samples[1]
		end
	end
end

function roadRightFromTangent(tangent)
	local right = Vector3.yAxis:Cross(tangent)
	if right.Magnitude < 1e-4 then
		return Vector3.xAxis
	end
	return right.Unit
end

local function lineIntersectionXZ(a, dirA, b, dirB)
	local denom = crossXZ(dirA, dirB)
	if math.abs(denom) < 1e-5 then
		return nil
	end

	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local t = (dx * dirB.Z - dz * dirB.X) / denom
	return Vector3.new(a.X + dirA.X * t, a.Y, a.Z + dirA.Z * t)
end

local function circleCenterXZ(a, b, c)
	local ax = a.X
	local az = a.Z
	local bx = b.X
	local bz = b.Z
	local cx = c.X
	local cz = c.Z
	local denom = 2 * (ax * (bz - cz) + bx * (cz - az) + cx * (az - bz))
	if math.abs(denom) < 1e-4 then
		return nil
	end

	local a2 = ax * ax + az * az
	local b2 = bx * bx + bz * bz
	local c2 = cx * cx + cz * cz
	local ux = (a2 * (bz - cz) + b2 * (cz - az) + c2 * (az - bz)) / denom
	local uz = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / denom
	return Vector3.new(ux, b.Y, uz)
end

local function expandCentersForRoadWidth(centers, roadWidth, closedLoop)
	local edgeCount = #centers
	local halfWidth = roadWidth * 0.5
	local targetRadius = halfWidth + math.max(6, roadWidth * ROAD_INNER_EDGE_RADIUS_SCALE)
	local expansionCount = 0
	local maxPush = 0
	local minRadius = math.huge

	for _ = 1, ROAD_CURVE_EXPANSION_PASSES do
		local nextCenters = {}
		for i = 1, edgeCount do
			nextCenters[i] = centers[i]
		end

		for i = 1, edgeCount do
			if closedLoop or (i > 1 and i < edgeCount) then
				local prevIndex = i - 1
				if prevIndex < 1 then
					prevIndex = edgeCount
				end
				local nextIndex = i + 1
				if nextIndex > edgeCount then
					nextIndex = 1
				end

				local circleCenter = circleCenterXZ(centers[prevIndex], centers[i], centers[nextIndex])
				if circleCenter then
					local inward = horizontalUnit(circleCenter - centers[i])
					if inward then
						local radius = distanceXZ(circleCenter, centers[i])
						minRadius = math.min(minRadius, radius)
						if radius < targetRadius then
							local push = (targetRadius - radius) * ROAD_CURVE_EXPANSION_ALPHA
							nextCenters[i] = centers[i] - inward * push
							expansionCount += 1
							maxPush = math.max(maxPush, push)
						end
					end
				end
			end
		end

		centers = nextCenters
	end

	return centers, expansionCount, maxPush, minRadius
end

local function offsetEdgePoint(center, prevDir, prevRight, nextDir, nextRight, sideSign, halfWidth)
	local prevOffset = center + prevRight * (sideSign * halfWidth)
	local nextOffset = center + nextRight * (sideSign * halfWidth)
	local intersection = lineIntersectionXZ(prevOffset, prevDir, nextOffset, nextDir)
	local maxMiterDistance = halfWidth * ROAD_EDGE_MITER_LIMIT
	if intersection then
		local fromCenter = Vector3.new(intersection.X - center.X, 0, intersection.Z - center.Z)
		if fromCenter.Magnitude > 1e-4 then
			if fromCenter.Magnitude <= maxMiterDistance then
				return Vector3.new(intersection.X, center.Y, intersection.Z)
			end
			local clamped = center + fromCenter.Unit * maxMiterDistance
			return Vector3.new(clamped.X, center.Y, clamped.Z), "clamped"
		end
	end

	local averagedRight = prevRight + nextRight
	if averagedRight.Magnitude < 1e-4 then
		averagedRight = nextRight
	end
	local fallback = center + averagedRight.Unit * (sideSign * halfWidth)
	return Vector3.new(fallback.X, center.Y, fallback.Z), "fallback"
end

local function buildRoadEdgePairs(samples, roadWidth, surfaceYOffset, debugLabel)
	if #samples < 2 then
		return nil, nil
	end

	roadWidth = sanitizeRoadWidth(roadWidth)
	local closedLoop = sampleLoopIsClosed(samples)
	local sampleCount = #samples
	local edgeCount = closedLoop and sampleCount - 1 or sampleCount
	if edgeCount < 2 then
		return nil, nil
	end

	local halfWidth = roadWidth * 0.5
	local centers = {}
	for i = 1, edgeCount do
		centers[i] = samples[i] + Vector3.new(0, surfaceYOffset, 0)
	end
	local centerExpansionCount
	local maxCenterPush
	local minCurveRadius
	centers, centerExpansionCount, maxCenterPush, minCurveRadius = expandCentersForRoadWidth(centers, roadWidth, closedLoop)

	local segmentCount = closedLoop and edgeCount or edgeCount - 1
	local segmentDirs = {}
	local segmentRights = {}
	local fallbackDir = Vector3.new(0, 0, 1)
	for i = 1, segmentCount do
		local nextIndex = closedLoop and ((i % edgeCount) + 1) or (i + 1)
		local dir = horizontalUnit(centers[nextIndex] - centers[i]) or fallbackDir
		segmentDirs[i] = dir
		segmentRights[i] = roadRightFromTangent(dir)
		fallbackDir = dir
	end

	local leftPositions = {}
	local rightPositions = {}
	local miterClampCount = 0
	local miterFallbackCount = 0
	for i = 1, edgeCount do
		local center = centers[i]
		if not closedLoop and i == 1 then
			local right = segmentRights[1]
			leftPositions[i] = center - right * halfWidth
			rightPositions[i] = center + right * halfWidth
		elseif not closedLoop and i == edgeCount then
			local right = segmentRights[segmentCount]
			leftPositions[i] = center - right * halfWidth
			rightPositions[i] = center + right * halfWidth
		else
			local prevSegment = i - 1
			if prevSegment < 1 then
				prevSegment = segmentCount
			end
			local nextSegment = i
			if nextSegment > segmentCount then
				nextSegment = 1
			end

			local leftStatus
			leftPositions[i], leftStatus = offsetEdgePoint(
				center,
				segmentDirs[prevSegment],
				segmentRights[prevSegment],
				segmentDirs[nextSegment],
				segmentRights[nextSegment],
				-1,
				halfWidth
			)
			local rightStatus
			rightPositions[i], rightStatus = offsetEdgePoint(
				center,
				segmentDirs[prevSegment],
				segmentRights[prevSegment],
				segmentDirs[nextSegment],
				segmentRights[nextSegment],
				1,
				halfWidth
			)
			if leftStatus == "clamped" then
				miterClampCount += 1
			elseif leftStatus == "fallback" then
				miterFallbackCount += 1
			end
			if rightStatus == "clamped" then
				miterClampCount += 1
			elseif rightStatus == "fallback" then
				miterFallbackCount += 1
			end
		end
	end

	local function correctPairWidth(index)
		local center = centers[index]
		local mid = (leftPositions[index] + rightPositions[index]) * 0.5
		local lateral = horizontalUnit(rightPositions[index] - leftPositions[index])
		if not lateral then
			local segmentIndex = math.min(index, segmentCount)
			lateral = segmentRights[segmentIndex] or Vector3.xAxis
		end

		leftPositions[index] = Vector3.new(mid.X, center.Y, mid.Z) - lateral * halfWidth
		rightPositions[index] = Vector3.new(mid.X, center.Y, mid.Z) + lateral * halfWidth
	end

	for i = 1, edgeCount do
		correctPairWidth(i)
	end

	for _ = 1, ROAD_EDGE_SMOOTH_PASSES do
		local nextLeft = {}
		local nextRight = {}
		for i = 1, edgeCount do
			if closedLoop or (i > 1 and i < edgeCount) then
				local prevIndex = i - 1
				if prevIndex < 1 then
					prevIndex = edgeCount
				end
				local nextIndex = i + 1
				if nextIndex > edgeCount then
					nextIndex = 1
				end

				local leftAverage = (leftPositions[prevIndex] + leftPositions[nextIndex]) * 0.5
				local rightAverage = (rightPositions[prevIndex] + rightPositions[nextIndex]) * 0.5
				nextLeft[i] = leftPositions[i]:Lerp(Vector3.new(leftAverage.X, centers[i].Y, leftAverage.Z), ROAD_EDGE_SMOOTH_ALPHA)
				nextRight[i] = rightPositions[i]:Lerp(Vector3.new(rightAverage.X, centers[i].Y, rightAverage.Z), ROAD_EDGE_SMOOTH_ALPHA)
			else
				nextLeft[i] = leftPositions[i]
				nextRight[i] = rightPositions[i]
			end
		end

		leftPositions = nextLeft
		rightPositions = nextRight
		for i = 1, edgeCount do
			correctPairWidth(i)
		end
	end

	if closedLoop then
		leftPositions[sampleCount] = leftPositions[1]
		rightPositions[sampleCount] = rightPositions[1]
	end

	local collapsedSpans = 0
	local tightSpans = 0
	local minLeftStep = math.huge
	local minRightStep = math.huge
	for i = 1, edgeCount - 1 do
		local sampleStep = (samples[i + 1] - samples[i]).Magnitude
		local leftStep = (leftPositions[i + 1] - leftPositions[i]).Magnitude
		local rightStep = (rightPositions[i + 1] - rightPositions[i]).Magnitude
		minLeftStep = math.min(minLeftStep, leftStep)
		minRightStep = math.min(minRightStep, rightStep)
		if sampleStep > 1 and math.min(leftStep, rightStep) < 0.5 then
			collapsedSpans += 1
		end
		if roadWidth > sampleStep * 2 then
			tightSpans += 1
		end
	end

	if closedLoop and edgeCount > 2 then
		local sampleStep = (samples[1] - samples[edgeCount]).Magnitude
		local leftStep = (leftPositions[1] - leftPositions[edgeCount]).Magnitude
		local rightStep = (rightPositions[1] - rightPositions[edgeCount]).Magnitude
		minLeftStep = math.min(minLeftStep, leftStep)
		minRightStep = math.min(minRightStep, rightStep)
		if sampleStep > 1 and math.min(leftStep, rightStep) < 0.5 then
			collapsedSpans += 1
		end
		if roadWidth > sampleStep * 2 then
			tightSpans += 1
		end
	end

	if centerExpansionCount > 0 or miterClampCount > 0 or miterFallbackCount > 0 or collapsedSpans > 0 or tightSpans > 0 then
		local label = debugLabel or "road"
		local message = "edge remesh diagnostics %s: width=%.1f samples=%d closed=%s centerExpansions=%d maxCenterPush=%.2f minCurveRadius=%.2f miterClamps=%d fallbacks=%d collapsedSpans=%d tightSpans=%d minLeftStep=%.2f minRightStep=%.2f"
		if collapsedSpans > 0 then
			roadDebugWarn(
				message,
				label,
				roadWidth,
				#samples,
				tostring(closedLoop),
				centerExpansionCount,
				maxCenterPush,
				minCurveRadius == math.huge and 0 or minCurveRadius,
				miterClampCount,
				miterFallbackCount,
				collapsedSpans,
				tightSpans,
				minLeftStep == math.huge and 0 or minLeftStep,
				minRightStep == math.huge and 0 or minRightStep
			)
		else
			roadDebugLog(
				message,
				label,
				roadWidth,
				#samples,
				tostring(closedLoop),
				centerExpansionCount,
				maxCenterPush,
				minCurveRadius == math.huge and 0 or minCurveRadius,
				miterClampCount,
				miterFallbackCount,
				collapsedSpans,
				tightSpans,
				minLeftStep == math.huge and 0 or minLeftStep,
				minRightStep == math.huge and 0 or minRightStep
			)
		end
	end

	return leftPositions, rightPositions
end

local function angleFromHorizontal(vector)
	return math.atan2(vector.Z, vector.X)
end

local function vectorFromHorizontalAngle(angle)
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function shortestAngleDelta(fromAngle, toAngle)
	return math.atan2(math.sin(toAngle - fromAngle), math.cos(toAngle - fromAngle))
end

local function addRoadTurnSectorToMesh(state, center, fromVector, toVector, radius)
	local fromUnit = horizontalUnit(fromVector)
	local toUnit = horizontalUnit(toVector)
	if not fromUnit or not toUnit then
		return 0
	end

	local fromAngle = angleFromHorizontal(fromUnit)
	local delta = shortestAngleDelta(fromAngle, angleFromHorizontal(toUnit))
	if math.abs(delta) < math.rad(1) then
		return 0
	end

	local steps = math.max(1, math.ceil(math.abs(delta) / math.rad(12)))
	local centerVertex = addMeshVertex(state, center)
	local previousVertex = addMeshVertex(state, center + vectorFromHorizontalAngle(fromAngle) * radius)
	local triangles = 0
	for step = 1, steps do
		local angle = fromAngle + delta * (step / steps)
		local currentVertex = addMeshVertex(state, center + vectorFromHorizontalAngle(angle) * radius)
		if delta > 0 then
			addMeshTriangle(state, centerVertex, currentVertex, previousVertex)
		else
			addMeshTriangle(state, centerVertex, previousVertex, currentVertex)
		end
		previousVertex = currentVertex
		triangles += 1
	end
	return triangles
end

local function addRoadRowVertices(state, center, right, roadWidth, widthSegments)
	local row = {}
	local left = center - right * (roadWidth * 0.5)
	local rightEdge = center + right * (roadWidth * 0.5)
	for j = 0, widthSegments do
		row[j + 1] = addMeshVertex(state, left:Lerp(rightEdge, j / widthSegments))
	end
	return row
end

local function newMeshState()
	local editableMesh = AssetService:CreateEditableMesh()
	if not editableMesh then
		error("EditableMesh creation returned nil", 0)
	end
	return {
		mesh = editableMesh,
		faces = 0,
	}
end

local function addMeshVertex(state, pos)
	return state.mesh:AddVertex(pos)
end

local function addMeshTriangle(state, a, b, c)
	state.mesh:AddTriangle(a, b, c)
	state.faces += 1
end

local function sampleSmoothedCurveControls(points, closedLoop, sampleStep)
	local count = #points
	if count < 3 then
		return points
	end

	local smoothed = {}
	local function appendPoint(point)
		local last = smoothed[#smoothed]
		if not last or (point - last).Magnitude > 1e-4 then
			table.insert(smoothed, point)
		end
	end

	local segmentCount = closedLoop and count or count - 1
	for i = 1, segmentCount do
		local p0
		local p1
		local p2
		local p3
		if closedLoop then
			p0 = points[((i - 2) % count) + 1]
			p1 = points[i]
			p2 = points[(i % count) + 1]
			p3 = points[((i + 1) % count) + 1]
		else
			p0 = points[math.max(1, i - 1)]
			p1 = points[i]
			p2 = points[i + 1]
			p3 = points[math.min(count, i + 2)]
		end

		local segmentLength = (p2 - p1).Magnitude
		local subdivisions = math.max(2, math.ceil(segmentLength / sampleStep))
		for s = 0, subdivisions - 1 do
			appendPoint(catmullRom(p0, p1, p2, p3, s / subdivisions))
		end
	end

	if not closedLoop then
		appendPoint(points[count])
	end

	return #smoothed >= count and smoothed or points
end

local function resamplePolylineControls(points, closedLoop, targetCount)
	targetCount = math.floor(targetCount)
	if targetCount <= 0 or #points == 0 then
		return {}
	elseif #points == 1 then
		return { points[1] }
	end

	targetCount = math.max(closedLoop and 3 or 2, targetCount)
	local resampled = {}
	for i = 1, targetCount do
		local fraction
		if closedLoop then
			fraction = (i - 1) / targetCount
		else
			fraction = targetCount > 1 and ((i - 1) / (targetCount - 1)) or 0
		end
		resampled[i] = samplePolylineAtFraction(points, closedLoop, fraction)
	end
	return resampled
end

local function fairEdgeCurveControls(points, closedLoop, sampleStep)
	local length = polylineLength(points, closedLoop)
	local targetCount
	if length > 1e-4 then
		targetCount = closedLoop and math.ceil(length / sampleStep) or (math.ceil(length / sampleStep) + 1)
		targetCount = math.max(#points, targetCount)
	else
		targetCount = #points
	end

	local relaxed = resamplePolylineControls(points, closedLoop, targetCount)
	for _ = 1, ROAD_EDGE_CURVE_FAIR_PASSES do
		local count = #relaxed
		if count < 3 then
			return relaxed
		end

		local nextPoints = {}
		for i = 1, count do
			if closedLoop or (i > 1 and i < count) then
				local prevIndex = i - 1
				if prevIndex < 1 then
					prevIndex = count
				end
				local nextIndex = i + 1
				if nextIndex > count then
					nextIndex = 1
				end

				local average = (relaxed[prevIndex] + relaxed[nextIndex]) * 0.5
				nextPoints[i] = relaxed[i]:Lerp(average, ROAD_EDGE_CURVE_FAIR_ALPHA)
			else
				nextPoints[i] = relaxed[i]
			end
		end
		relaxed = resamplePolylineControls(nextPoints, closedLoop, targetCount)
	end

	return sampleSmoothedCurveControls(relaxed, closedLoop, sampleStep)
end

local function getUniqueRoadSamples(samples, closedLoop)
	local unique = {}
	for _, sample in ipairs(samples) do
		table.insert(unique, sample)
	end
	if closedLoop and #unique > 1 and distanceXZ(unique[1], unique[#unique]) <= 0.05 then
		table.remove(unique, #unique)
	end
	return unique
end

local function buildRoadCrossSections(samples, roadWidth, surfaceYOffset, debugLabel)
	if #samples < 2 then
		return nil
	end

	roadWidth = sanitizeRoadWidth(roadWidth)
	local closedLoop = sampleLoopIsClosed(samples)
	local centerControls = getUniqueRoadSamples(samples, closedLoop)
	if #centerControls < (closedLoop and 3 or 2) then
		return nil
	end

	local centerLength = polylineLength(centerControls, closedLoop)
	if centerLength <= 1e-4 then
		return nil
	end

	local halfWidth = roadWidth * 0.5
	local widthSegments = math.min(ROAD_WIDTH_MAX_INTERNAL_LOOPS + 1, math.max(1, math.ceil(roadWidth / ROAD_WIDTH_TRIANGULATION_STEP)))
	local rowCount
	if closedLoop then
		rowCount = math.max(3, #centerControls, math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP))
	else
		rowCount = math.max(2, #centerControls, math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP) + 1)
	end
	local spanCount = closedLoop and rowCount or rowCount - 1
	local centers = {}
	local leftPositions = {}
	local rightPositions = {}
	local rights = {}
	local fallbackDir = Vector3.new(0, 0, 1)

	for i = 1, rowCount do
		local fraction = closedLoop and ((i - 1) / rowCount) or (rowCount > 1 and ((i - 1) / (rowCount - 1)) or 0)
		centers[i] = samplePolylineAtFraction(centerControls, closedLoop, fraction) + Vector3.new(0, surfaceYOffset, 0)
	end

	for i = 1, rowCount do
		local tangent
		if closedLoop then
			local prevIndex = i - 1
			if prevIndex < 1 then
				prevIndex = rowCount
			end
			local nextIndex = i + 1
			if nextIndex > rowCount then
				nextIndex = 1
			end
			tangent = horizontalUnit(centers[nextIndex] - centers[prevIndex])
		elseif i == 1 then
			tangent = horizontalUnit(centers[2] - centers[1])
		elseif i == rowCount then
			tangent = horizontalUnit(centers[rowCount] - centers[rowCount - 1])
		else
			tangent = horizontalUnit(centers[i + 1] - centers[i - 1])
		end

		fallbackDir = tangent or fallbackDir
		local right = roadRightFromTangent(fallbackDir)
		if i > 1 and rights[i - 1] and right:Dot(rights[i - 1]) < 0 then
			right = -right
		end
		rights[i] = right
		leftPositions[i] = centers[i] - right * halfWidth
		rightPositions[i] = centers[i] + right * halfWidth
	end

	if Config.authoredRoadDebugLogging == true and roadWidth >= 96 then
		roadDebugLog(
			"road loft %s: width=%.1f samples=%d rows=%d closed=%s spans=%d centerLen=%.1f widthSegments=%d",
			tostring(debugLabel or "road"),
			roadWidth,
			#samples,
			rowCount,
			tostring(closedLoop),
			spanCount,
			centerLength,
			widthSegments
		)
	end

	return {
		roadWidth = roadWidth,
		closed = closedLoop,
		rowCount = rowCount,
		spanCount = spanCount,
		widthSegments = widthSegments,
		centers = centers,
		left = leftPositions,
		right = rightPositions,
	}
end

local function addRoadLoftRowVertices(state, left, right, widthSegments)
	local row = {}
	for j = 0, widthSegments do
		row[j + 1] = addMeshVertex(state, left:Lerp(right, j / widthSegments))
	end
	return row
end

local function addRoadRibbonToMesh(state, samples, roadWidth, debugLabel)
	local sections = buildRoadCrossSections(samples, roadWidth, ROAD_MESH_THICKNESS * 0.5, debugLabel)
	if not sections then
		return 0
	end

	local rows = {}
	for i = 1, sections.rowCount do
		rows[i] = addRoadLoftRowVertices(state, sections.left[i], sections.right[i], sections.widthSegments)
	end

	local spans = 0
	for i = 1, sections.spanCount do
		local nextIndex = sections.closed and ((i % sections.rowCount) + 1) or (i + 1)
		for j = 1, sections.widthSegments do
			local v1 = rows[i][j]
			local v2 = rows[nextIndex][j]
			local v3 = rows[nextIndex][j + 1]
			local v4 = rows[i][j + 1]
			addMeshTriangle(state, v1, v2, v3)
			addMeshTriangle(state, v1, v3, v4)
		end
		spans += 1
	end
	if Config.authoredRoadDebugLogging == true and sections.roadWidth >= 96 then
		roadDebugLog("road loft %s: width=%.1f rows=%d spans=%d widthSegments=%d", tostring(debugLabel or "road"), sections.roadWidth, sections.rowCount, spans, sections.widthSegments)
	end
	return spans
end

local function normalizePositiveAngleDelta(delta)
	local result = delta
	while result <= 0 do
		result += math.pi * 2
	end
	while result > math.pi * 2 do
		result -= math.pi * 2
	end
	return result
end

local function junctionBoundaryAngle(point, junction)
	local center = getJunctionMeshCenter(junction)
	return math.atan2(point.Z - center.Z, point.X - center.X)
end

local function boundaryEntriesSharePortal(a, b)
	return a.portal ~= nil and b.portal ~= nil and a.portal == b.portal
end

local function mergeBoundaryEntryPortal(target, source)
	if not boundaryEntriesSharePortal(target, source) then
		target.portal = nil
		target.corePoint = target.point
	end
end

local function sortedJunctionBoundaryEntries(junction)
	local entries = {}
	for _, portal in ipairs(junction.portals) do
		table.insert(entries, { point = portal.left, corePoint = portal.coreLeft or portal.left, portal = portal })
		table.insert(entries, { point = portal.right, corePoint = portal.coreRight or portal.right, portal = portal })
	end
	table.sort(entries, function(a, b)
		return junctionBoundaryAngle(a.point, junction) < junctionBoundaryAngle(b.point, junction)
	end)

	local filtered = {}
	for _, entry in ipairs(entries) do
		local previous = filtered[#filtered]
		if previous and distanceXZ(previous.point, entry.point) <= 0.05 then
			mergeBoundaryEntryPortal(previous, entry)
		else
			table.insert(filtered, { point = entry.point, corePoint = entry.corePoint, portal = entry.portal })
		end
	end
	if #filtered >= 2 and distanceXZ(filtered[1].point, filtered[#filtered].point) <= 0.05 then
		mergeBoundaryEntryPortal(filtered[1], filtered[#filtered])
		table.remove(filtered, #filtered)
	end

	return filtered
end

local function addConnectorSubdivisionPoints(boundary, junction, fromPoint, toPoint, subdivisions, surfaceY)
	local center = getJunctionMeshCenter(junction)
	local fromAngle = junctionBoundaryAngle(fromPoint, junction)
	local toAngle = junctionBoundaryAngle(toPoint, junction)
	local delta = normalizePositiveAngleDelta(toAngle - fromAngle)
	if delta <= 1e-4 or delta >= math.pi * 2 - 1e-4 then
		return
	end

	local fromRadius = distanceXZ(fromPoint, center)
	local toRadius = distanceXZ(toPoint, center)
	for i = 1, subdivisions do
		local alpha = i / (subdivisions + 1)
		local angle = fromAngle + delta * alpha
		local radius = fromRadius + (toRadius - fromRadius) * alpha
		table.insert(boundary, Vector3.new(
			center.X + math.cos(angle) * radius,
			surfaceY,
			center.Z + math.sin(angle) * radius
		))
	end
end

local function appendBoundaryPoint(boundary, point)
	if #boundary == 0 or distanceXZ(boundary[#boundary], point) > 0.05 then
		table.insert(boundary, point)
	end
end

local function appendUniqueBoundaryPoint(boundary, point)
	for _, existing in ipairs(boundary) do
		if distanceXZ(existing, point) <= 0.05 then
			return
		end
	end
	table.insert(boundary, point)
end

local function hullCrossXZ(origin, a, b)
	return (a.X - origin.X) * (b.Z - origin.Z) - (a.Z - origin.Z) * (b.X - origin.X)
end

local function convexHullXZ(points)
	if #points < 3 then
		return points
	end

	local sorted = {}
	for _, point in ipairs(points) do
		table.insert(sorted, point)
	end
	table.sort(sorted, function(a, b)
		if math.abs(a.X - b.X) > 0.001 then
			return a.X < b.X
		end
		return a.Z < b.Z
	end)

	local lower = {}
	for _, point in ipairs(sorted) do
		while #lower >= 2 and hullCrossXZ(lower[#lower - 1], lower[#lower], point) <= 0.001 do
			table.remove(lower)
		end
		table.insert(lower, point)
	end

	local upper = {}
	for i = #sorted, 1, -1 do
		local point = sorted[i]
		while #upper >= 2 and hullCrossXZ(upper[#upper - 1], upper[#upper], point) <= 0.001 do
			table.remove(upper)
		end
		table.insert(upper, point)
	end

	table.remove(lower, #lower)
	table.remove(upper, #upper)
	local hull = {}
	for _, point in ipairs(lower) do
		table.insert(hull, point)
	end
	for _, point in ipairs(upper) do
		table.insert(hull, point)
	end

	if #hull < 3 then
		return points
	end
	return hull
end

local function polygonAverageCenter(boundary, fallback)
	if #boundary == 0 then
		return fallback
	end

	local sum = Vector3.zero
	for _, point in ipairs(boundary) do
		sum += point
	end
	local center = sum / #boundary
	return Vector3.new(center.X, fallback.Y, center.Z)
end

local function portalConnectorPoints(portal, surfaceY)
	local coreLeft = portal.coreLeft or portal.left
	local coreRight = portal.coreRight or portal.right
	local mouthLeft = portal.left
	local mouthRight = portal.right
	return Vector3.new(coreLeft.X, surfaceY, coreLeft.Z),
		Vector3.new(coreRight.X, surfaceY, coreRight.Z),
		Vector3.new(mouthLeft.X, surfaceY, mouthLeft.Z),
		Vector3.new(mouthRight.X, surfaceY, mouthRight.Z)
end

local function addLinearSubdivisionPoints(boundary, fromPoint, toPoint, subdivisions)
	for i = 1, subdivisions do
		appendBoundaryPoint(boundary, fromPoint:Lerp(toPoint, i / (subdivisions + 1)))
	end
end

local function isNaturalJunctionCorner(junction, fromEntry, toEntry, point)
	if not fromEntry.portal or not toEntry.portal then
		return false
	end

	local fromCorePoint = fromEntry.corePoint or fromEntry.point
	local toCorePoint = toEntry.corePoint or toEntry.point
	local fromAdvance = (point - fromCorePoint):Dot(fromEntry.portal.tangent)
	local toAdvance = (point - toCorePoint):Dot(toEntry.portal.tangent)
	if fromAdvance > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE or toAdvance > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE then
		return false
	end

	local maxDistance = math.max(
		distanceXZ(fromCorePoint, getJunctionMeshCenter(junction)) + (fromEntry.portal.halfWidth or 0),
		distanceXZ(toCorePoint, getJunctionMeshCenter(junction)) + (toEntry.portal.halfWidth or 0)
	)
	return distanceXZ(point, getJunctionMeshCenter(junction)) <= math.max(maxDistance, 6)
end

local function naturalJunctionCorner(junction, fromEntry, toEntry, surfaceY)
	if not fromEntry.portal or not toEntry.portal then
		return nil
	end

	local intersection = lineIntersectionXZ(
		fromEntry.corePoint or fromEntry.point,
		fromEntry.portal.tangent,
		toEntry.corePoint or toEntry.point,
		toEntry.portal.tangent
	)
	if not intersection then
		return nil
	end

	local point = Vector3.new(intersection.X, surfaceY, intersection.Z)
	if not isNaturalJunctionCorner(junction, fromEntry, toEntry, point) then
		return nil
	end
	return point
end

local function addConnectorBoundaryPoints(boundary, junction, fromEntry, toEntry, subdivisions, surfaceY)
	local corner = naturalJunctionCorner(junction, fromEntry, toEntry, surfaceY)
	if corner then
		addLinearSubdivisionPoints(boundary, Vector3.new(fromEntry.point.X, surfaceY, fromEntry.point.Z), corner, subdivisions)
		appendBoundaryPoint(boundary, corner)
		addLinearSubdivisionPoints(boundary, corner, Vector3.new(toEntry.point.X, surfaceY, toEntry.point.Z), subdivisions)
		return
	end

	if subdivisions > 0 then
		addConnectorSubdivisionPoints(boundary, junction, fromEntry.point, toEntry.point, subdivisions, surfaceY)
	end
end

local function getJunctionBoundary(junction, surfaceY)
	if not junction.portals or #junction.portals == 0 then
		return {}
	end

	if junction.surfaceBoundary and #junction.surfaceBoundary >= 3 then
		local boundary = {}
		for _, point in ipairs(junction.surfaceBoundary) do
			table.insert(boundary, Vector3.new(point.X, surfaceY, point.Z))
		end
		return boundary
	end

	if junction.coreBoundary and #junction.coreBoundary >= 3 then
		local boundary = {}
		for _, point in ipairs(junction.coreBoundary) do
			table.insert(boundary, Vector3.new(point.X, surfaceY, point.Z))
		end
		return boundary
	end

	local boundary = {}
	for _, portal in ipairs(junction.portals) do
		local coreLeft = portal.coreLeft or portal.left
		local coreRight = portal.coreRight or portal.right
		appendUniqueBoundaryPoint(boundary, Vector3.new(coreLeft.X, surfaceY, coreLeft.Z))
		appendUniqueBoundaryPoint(boundary, Vector3.new(coreRight.X, surfaceY, coreRight.Z))
	end
	return convexHullXZ(boundary)
end

local function addPortalConnectorToMesh(state, portal, surfaceY)
	local coreLeft, coreRight, mouthLeft, mouthRight = portalConnectorPoints(portal, surfaceY)
	if distanceXZ(coreLeft, mouthLeft) <= 0.05 and distanceXZ(coreRight, mouthRight) <= 0.05 then
		return
	end

	local coreLeftVertex = addMeshVertex(state, coreLeft)
	local mouthLeftVertex = addMeshVertex(state, mouthLeft)
	local mouthRightVertex = addMeshVertex(state, mouthRight)
	local coreRightVertex = addMeshVertex(state, coreRight)
	addMeshTriangle(state, coreLeftVertex, mouthLeftVertex, mouthRightVertex)
	addMeshTriangle(state, coreLeftVertex, mouthRightVertex, coreRightVertex)
end

local function addIntersectionPatchToMesh(state, junction)
	local fallbackCenter = getJunctionMeshCenter(junction) + Vector3.new(0, ROAD_MESH_THICKNESS * 0.5, 0)
	local boundary = getJunctionBoundary(junction, fallbackCenter.Y)
	if #boundary >= 3 then
		local center = fallbackCenter
		if not (junction.surfaceBoundary and #junction.surfaceBoundary >= 3) then
			center = polygonAverageCenter(boundary, fallbackCenter)
		end
		local centerVertex = addMeshVertex(state, center)
		local ring = {}
		for i, point in ipairs(boundary) do
			ring[i] = addMeshVertex(state, point)
		end

		for i = 1, #ring do
			addMeshTriangle(state, centerVertex, ring[(i % #ring) + 1], ring[i])
		end
	end

	for _, portal in ipairs(junction.portals or {}) do
		addPortalConnectorToMesh(state, portal, fallbackCenter.Y)
	end
end

local function buildRoadComponents(chains, junctions)
	local parent = {}
	for _, chain in ipairs(chains) do
		parent[chain] = chain
	end

	local function find(chain)
		local root = parent[chain]
		while root and parent[root] ~= root do
			root = parent[root]
		end
		if root and parent[chain] ~= root then
			parent[chain] = root
		end
		return root
	end

	local function union(a, b)
		local rootA = find(a)
		local rootB = find(b)
		if rootA and rootB and rootA ~= rootB then
			parent[rootB] = rootA
		end
	end

	for _, junction in ipairs(junctions) do
		local firstChain = nil
		for chain in pairs(junction.chains or {}) do
			if not firstChain then
				firstChain = chain
			else
				union(firstChain, chain)
			end
		end
	end

	local componentsByRoot = {}
	local components = {}
	local componentByChain = {}
	for _, chain in ipairs(chains) do
		local root = find(chain)
		local component = componentsByRoot[root]
		if not component then
			component = { chains = {}, junctions = {} }
			componentsByRoot[root] = component
			table.insert(components, component)
		end
		table.insert(component.chains, chain)
		componentByChain[chain] = component
	end

	for _, junction in ipairs(junctions) do
		local component = nil
		for chain in pairs(junction.chains or {}) do
			component = componentByChain[chain]
			break
		end
		if component then
			table.insert(component.junctions, junction)
		end
	end
	return components
end

local function createMeshPartFromState(state, parent, name)
	local meshContent = Content.fromObject(state.mesh)
	local okBake, bakeResult, bakedContent = pcall(function()
		return AssetService:CreateDataModelContentAsync(meshContent)
	end)
	if okBake and bakeResult == Enum.CreateContentResult.Success then
		meshContent = bakedContent
	elseif not okBake then
		if not dataModelContentWarningShown then
			dataModelContentWarningShown = true
			roadDebugLog("CreateDataModelContentAsync unavailable in this Studio session; using transient client mesh content. First mesh=%s error=%s", tostring(name), tostring(bakeResult))
		end
	elseif bakeResult ~= Enum.CreateContentResult.Success then
		roadDebugWarn("CreateDataModelContentAsync failed for %s: %s", tostring(name), tostring(bakeResult))
	end

	local meshPart = AssetService:CreateMeshPartAsync(meshContent, {
		CollisionFidelity = Enum.CollisionFidelity.Box,
	})
	meshPart.Name = name
	meshPart.Anchored = true
	meshPart.CanCollide = false
	meshPart.CanQuery = false
	meshPart.CanTouch = false
	meshPart.Material = Enum.Material.Asphalt
	meshPart.Color = Color3.fromRGB(28, 28, 32)
	pcall(function()
		meshPart.DoubleSided = true
	end)
	meshPart:SetAttribute("GeneratedBy", "Cab87RoadClientVisual")
	meshPart:SetAttribute("TriangleCount", state.faces)
	meshPart.Parent = parent
	roadDebugLog("created client mesh %s faces=%d", name, state.faces)
	return meshPart
end

local function buildClientRoadMesh(root, world)
	local chains = collectSplineBuildData(root)
	if #chains == 0 then
		error("No authored spline chains found", 0)
	end

	local processedRoadNetwork = root:GetAttribute("ProcessedRoadNetwork") == true
	roadDebugLog(
		"buildClientRoadMesh start: root=%s processed=%s chains=%d pointCountAttr=%s junctionCountAttr=%s",
		root:GetFullName(),
		tostring(processedRoadNetwork),
		#chains,
		tostring(root:GetAttribute("PointCount")),
		tostring(root:GetAttribute("JunctionCount"))
	)
	for i, chain in ipairs(chains) do
		roadDebugLog(
			"client chain %d: name=%s samples=%d width=%.1f closed=%s component=%d",
			i,
			getChainName(chain),
			#chain.samples,
			chain.width,
			tostring(chain.closed),
			chain.componentId or 0
		)
	end
	local junctions
	if processedRoadNetwork then
		junctions = collectProcessedJunctions(root)
		attachProcessedChainEndpointsToJunctions(chains, junctions)
	else
		local rawJunctions = collectEndpointJunctions(chains)
		for _, junction in ipairs(collectCrossIntersections(chains)) do
			table.insert(rawJunctions, junction)
		end

		junctions = mergeJunctions(rawJunctions)
		applyJunctionsToChains(chains, junctions)
	end

	local oldVisuals = world:FindFirstChild(CLIENT_VISUALS_NAME)
	if oldVisuals then
		oldVisuals:Destroy()
	end

	local visualModel = Instance.new("Model")
	visualModel.Name = CLIENT_VISUALS_NAME
	visualModel.Parent = world

	local totalSpans = 0
	local meshParts = 0
	local components = if processedRoadNetwork then buildProcessedComponents(chains, junctions) else buildRoadComponents(chains, junctions)
	for i, component in ipairs(components) do
		local state = newMeshState()
		for _, chain in ipairs(component.chains) do
			totalSpans += addRoadRibbonToMesh(state, chain.samples, chain.width, string.format("client component %03d/%s", i, getChainName(chain)))
		end
		for _, junction in ipairs(component.junctions) do
			addIntersectionPatchToMesh(state, junction)
		end

		if state.faces > 0 then
			local name = string.format("AuthoredRoadClientMesh_%03d", i)
			createMeshPartFromState(state, visualModel, name)
			meshParts += 1
		end
	end

	if meshParts == 0 then
		visualModel:Destroy()
		error("No client road mesh faces were generated", 0)
	end
	roadDebugLog("buildClientRoadMesh done: meshParts=%d spans=%d components=%d junctions=%d", meshParts, totalSpans, #components, #junctions)

	return meshParts, totalSpans
end

local function buildForWorld(world)
	if not world or not world.Parent then
		return
	end

	hideEditorDebugGeometry()

	if world:GetAttribute("NeedsClientRoadMesh") ~= true then
		roadDebugLog(
			"skipping client road mesh: world=%s NeedsClientRoadMesh=%s visualSource=%s",
			world:GetFullName(),
			tostring(world:GetAttribute("NeedsClientRoadMesh")),
			tostring(world:GetAttribute("AuthoredRoadVisualSource"))
		)
		local oldVisuals = world:FindFirstChild(CLIENT_VISUALS_NAME)
		if oldVisuals then
			oldVisuals:Destroy()
		end
		setWorldStatus(world, "SkippedServerMesh", "", 0, 0)
		return
	end

	local root = world:FindFirstChild(RUNTIME_SPLINE_DATA_NAME)
		or world:WaitForChild(RUNTIME_SPLINE_DATA_NAME, 5)
		or Workspace:FindFirstChild(ROAD_EDITOR_ROOT_NAME)
		or Workspace:WaitForChild(ROAD_EDITOR_ROOT_NAME, 5)
	if not (root and (root:IsA("Model") or root:IsA("Folder"))) then
		roadDebugWarn("missing spline data for world=%s", world:GetFullName())
		setWorldStatus(world, "MissingSplineData", RUNTIME_SPLINE_DATA_NAME .. " was not replicated to the client", 0, 0)
		return
	end
	roadDebugLog(
		"client road mesh source resolved: world=%s root=%s processed=%s",
		world:GetFullName(),
		root:GetFullName(),
		tostring(root:GetAttribute("ProcessedRoadNetwork") == true)
	)

	local ok, meshPartsOrErr, spans = pcall(function()
		return buildClientRoadMesh(root, world)
	end)
	if ok then
		setWorldStatus(world, "Built", "", meshPartsOrErr, spans)
		roadDebugLog("client road mesh status Built: parts=%d spans=%d", meshPartsOrErr, spans)
	else
		local message = tostring(meshPartsOrErr)
		roadDebugWarn("client road mesh build failed: %s", message)
		setWorldStatus(world, "Failed", message, 0, 0)
	end
end

local function scheduleBuild()
	buildSerial += 1
	local serial = buildSerial
	task.delay(0.25, function()
		if serial ~= buildSerial then
			return
		end

		local world = Workspace:FindFirstChild(RUNTIME_WORLD_NAME)
		if world and world:IsA("Model") then
			roadDebugLog("scheduled client road mesh build firing for %s", world:GetFullName())
			buildForWorld(world)
		else
			roadDebugLog("scheduled client road mesh build found no %s model", RUNTIME_WORLD_NAME)
		end
	end)
end

local function watchWorld(world)
	if watchedAttributeConnection then
		watchedAttributeConnection:Disconnect()
		watchedAttributeConnection = nil
	end
	if watchedChildConnection then
		watchedChildConnection:Disconnect()
		watchedChildConnection = nil
	end
	watchedWorld = world

	if watchedWorld then
		roadDebugLog("watching world %s NeedsClientRoadMesh=%s", watchedWorld:GetFullName(), tostring(watchedWorld:GetAttribute("NeedsClientRoadMesh")))
		watchedAttributeConnection = watchedWorld:GetAttributeChangedSignal("NeedsClientRoadMesh"):Connect(scheduleBuild)
		watchedChildConnection = watchedWorld.ChildAdded:Connect(function(child)
			if child.Name == RUNTIME_SPLINE_DATA_NAME then
				roadDebugLog("runtime spline data replicated; scheduling client road mesh rebuild")
				scheduleBuild()
			end
		end)
	end
	scheduleBuild()
end

roadDebugLog("AuthoredRoadVisual client script started")

Workspace.ChildAdded:Connect(function(child)
	if child.Name == RUNTIME_WORLD_NAME and child:IsA("Model") then
		watchWorld(child)
	end
end)

local existingWorld = Workspace:FindFirstChild(RUNTIME_WORLD_NAME)
if existingWorld and existingWorld:IsA("Model") then
	watchWorld(existingWorld)
end
