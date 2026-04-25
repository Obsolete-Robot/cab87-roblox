// Junction surface meshing helpers and geometry finalization.

function portalLineT(portal, point) {
	return dot2D(subtract2D(point, portal.boundaryPoint), portal.tangent);
}

function portalLinePointAtT(portal, t) {
	return makePoint(
		portal.boundaryPoint.x + (portal.tangent.x * t),
		portal.boundaryPoint.z + (portal.tangent.z * t),
		portal.boundaryPoint.y ?? 0,
	);
}

function getJunctionMeshCenter(junction) {
	return junction.intersectionCenter ?? junction.center;
}

function computeJunctionIntersectionCenter(junction) {
	const portals = junction.portals ?? [];
	if (portals.length === 0) {
		return junction.center;
	}

	const summed = portals.reduce((accumulator, portal) => {
		const point = portal.corePoint ?? portal.boundaryPoint ?? portal.point;
		return {
			x: accumulator.x + point.x,
			z: accumulator.z + point.z,
			y: accumulator.y + (point.y ?? 0),
		};
	}, { x: 0, z: 0, y: 0 });
	return makePoint(summed.x / portals.length, summed.z / portals.length, summed.y / portals.length);
}

function lineIntersectionWithParametersXZ(a, dirA, b, dirB) {
	const denom = cross2D(dirA, dirB);
	if (Math.abs(denom) < 1e-5) {
		return null;
	}

	const dx = b.x - a.x;
	const dz = b.z - a.z;
	const tA = ((dx * dirB.z) - (dz * dirB.x)) / denom;
	const tB = ((dx * dirA.z) - (dz * dirA.x)) / denom;
	return {
		point: makePoint(a.x + (dirA.x * tA), a.z + (dirA.z * tA), a.y ?? 0),
		tA,
		tB,
	};
}

function calculateIntersectionGeometry(center, roads) {
	const sortedRoads = roads
		.map((road, index) => {
			const direction = horizontalUnit(road.direction || subtract2D(road.endPoint || center, center));
			if (!direction) {
				return null;
			}
			const width = sanitizeRoadWidth(road.width);
			return {
				...road,
				id: road.id ?? String(index),
				width,
				halfWidth: width * 0.5,
				direction,
				angle: Math.atan2(direction.z, direction.x),
			};
		})
		.filter(Boolean)
		.sort((a, b) => a.angle - b.angle);

	const vertices = [];
	const corners = [];
	if (sortedRoads.length < 2) {
		return { vertices, sortedRoads, roadCutDistances: new Map(), corners };
	}

	for (let index = 0; index < sortedRoads.length; index += 1) {
		const road = sortedRoads[index];
		const nextRoad = sortedRoads[(index + 1) % sortedRoads.length];
		const side = roadRightFromTangent(road.direction);
		const nextSide = roadRightFromTangent(nextRoad.direction);
		const halfWidth = road.halfWidth;
		const nextHalfWidth = nextRoad.halfWidth;
		const endPoint = road.endPoint || makePoint(
			center.x + (road.direction.x * Math.max(road.width, halfWidth + 30)),
			center.z + (road.direction.z * Math.max(road.width, halfWidth + 30)),
			center.y ?? 0,
		);

		vertices.push(makePoint(
			endPoint.x + (side.x * halfWidth),
			endPoint.z + (side.z * halfWidth),
			center.y ?? 0,
		));
		vertices.push(makePoint(
			endPoint.x - (side.x * halfWidth),
			endPoint.z - (side.z * halfWidth),
			center.y ?? 0,
		));

		const fromSide = makePoint(
			center.x - (side.x * halfWidth),
			center.z - (side.z * halfWidth),
			center.y ?? 0,
		);
		const toSide = makePoint(
			center.x + (nextSide.x * nextHalfWidth),
			center.z + (nextSide.z * nextHalfWidth),
			center.y ?? 0,
		);
		const maxExtension = Math.max(halfWidth, nextHalfWidth) * 1.5 + 50;
		const intersection = lineIntersectionWithParametersXZ(fromSide, road.direction, toSide, nextRoad.direction);
		const points = [];

		if (intersection) {
			if (
				intersection.tA > maxExtension
				|| intersection.tB > maxExtension
				|| intersection.tA < 0
				|| intersection.tB < 0
			) {
				const safeFromT = Math.min(maxExtension, Math.max(0, intersection.tA));
				const safeToT = Math.min(maxExtension, Math.max(0, intersection.tB));
				points.push(makePoint(
					fromSide.x + (road.direction.x * safeFromT),
					fromSide.z + (road.direction.z * safeFromT),
					center.y ?? 0,
				));
				points.push(makePoint(
					toSide.x + (nextRoad.direction.x * safeToT),
					toSide.z + (nextRoad.direction.z * safeToT),
					center.y ?? 0,
				));
			} else {
				points.push(makePoint(intersection.point.x, intersection.point.z, center.y ?? 0));
			}
		} else {
			points.push(fromSide, toSide);
		}

		corners[index] = points;
		vertices.push(...points);
	}

	const roadCutDistances = new Map();
	sortedRoads.forEach((road, index) => {
		const previousIndex = (index - 1 + sortedRoads.length) % sortedRoads.length;
		const cornerPoints = [...(corners[previousIndex] || []), ...(corners[index] || [])];
		let maxProjection = 0;
		for (const point of cornerPoints) {
			const projection = dot2D(subtract2D(point, center), road.direction);
			if (projection > maxProjection) {
				maxProjection = projection;
			}
		}
		const cutDistance = Math.max(maxProjection, road.halfWidth) + 15;
		roadCutDistances.set(road.id, cutDistance + 15);
	});

	return { vertices, sortedRoads, roadCutDistances, corners };
}

function junctionCoreBoundaryLimit(junction) {
	const center = getJunctionMeshCenter(junction);
	let limit = JUNCTION_RADIUS_MIN;
	for (const portal of junction.portals ?? []) {
		const width = (portal.halfWidth ?? 0) * 2;
		limit = Math.max(
			limit,
			width * 3,
			distanceXZ(portal.boundaryPoint, center) + (width * 2),
		);
	}
	return limit;
}

function portalSideLine(portal, sideSign) {
	const right = roadRightFromTangent(portal.tangent);
	const center = getJunctionMeshCenter(portal.junction);
	const basePoint = portalLinePointAtT(portal, portalLineT(portal, center));
	return {
		portal,
		point: makePoint(
			basePoint.x + (right.x * (portal.halfWidth ?? 0) * sideSign),
			basePoint.z + (right.z * (portal.halfWidth ?? 0) * sideSign),
			basePoint.y ?? 0,
		),
		dir: portal.tangent,
		sideSign,
	};
}

function collectPortalSideLines(junction) {
	const lines = [];
	for (const portal of junction.portals ?? []) {
		lines.push(portalSideLine(portal, -1));
		lines.push(portalSideLine(portal, 1));
	}
	return lines;
}

function sortedJunctionPortals(junction) {
	return [...(junction.portals ?? [])].sort(
		(a, b) => Math.atan2(a.tangent.z, a.tangent.x) - Math.atan2(b.tangent.z, b.tangent.x),
	);
}

function appendOrderedJunctionPoint(points, point) {
	if (points.length === 0 || distanceXZ(points[points.length - 1], point) > 0.05) {
		points.push(point);
	}
}

function finalizeOrderedJunctionBoundary(points) {
	if (points.length >= 2 && distanceXZ(points[0], points[points.length - 1]) <= 0.05) {
		points.pop();
	}
	return points;
}

function junctionGapPoints(center, fromPortal, toPortal) {
	const fromRight = roadRightFromTangent(fromPortal.tangent);
	const toRight = roadRightFromTangent(toPortal.tangent);
	const fromHalfWidth = fromPortal.halfWidth ?? 0;
	const toHalfWidth = toPortal.halfWidth ?? 0;
	const fromSide = makePoint(
		center.x - (fromRight.x * fromHalfWidth),
		center.z - (fromRight.z * fromHalfWidth),
		center.y ?? 0,
	);
	const toSide = makePoint(
		center.x + (toRight.x * toHalfWidth),
		center.z + (toRight.z * toHalfWidth),
		center.y ?? 0,
	);
	const maxExtension = Math.max(fromHalfWidth, toHalfWidth) * 1.5 + 50;

	const intersection = lineIntersectionWithParametersXZ(fromSide, fromPortal.tangent, toSide, toPortal.tangent);
	if (
		intersection
		&& intersection.tA >= 0
		&& intersection.tB >= 0
		&& intersection.tA <= maxExtension
		&& intersection.tB <= maxExtension
	) {
		const point = makePoint(intersection.point.x, intersection.point.z, center.y ?? 0);
		return { fromPoint: point, toPoint: point, points: [point] };
	}

	const safeFromT = Math.min(maxExtension, Math.max(0, intersection?.tA ?? 0));
	const safeToT = Math.min(maxExtension, Math.max(0, intersection?.tB ?? 0));
	const fromPoint = makePoint(
		fromSide.x + (fromPortal.tangent.x * safeFromT),
		fromSide.z + (fromPortal.tangent.z * safeFromT),
		center.y ?? 0,
	);
	const toPoint = makePoint(
		toSide.x + (toPortal.tangent.x * safeToT),
		toSide.z + (toPortal.tangent.z * safeToT),
		center.y ?? 0,
	);
	if (distanceXZ(fromPoint, toPoint) <= 0.05) {
		const point = makePoint(
			(fromPoint.x + toPoint.x) * 0.5,
			(fromPoint.z + toPoint.z) * 0.5,
			center.y ?? 0,
		);
		return { fromPoint: point, toPoint: point, points: [point] };
	}
	return { fromPoint, toPoint, points: [fromPoint, toPoint] };
}

function buildJunctionCoreBoundary(junction) {
	const portals = sortedJunctionPortals(junction);
	if (portals.length < 2) {
		return [];
	}

	const center = getJunctionMeshCenter(junction);
	const boundary = [];
	for (const portal of portals) {
		portal.coreLeft = null;
		portal.coreRight = null;
	}

	for (let index = 0; index < portals.length; index += 1) {
		const portal = portals[index];
		const nextPortal = portals[(index + 1) % portals.length];
		const gap = junctionGapPoints(center, portal, nextPortal);
		portal.coreLeft = gap.fromPoint;
		nextPortal.coreRight = gap.toPoint;
		for (const point of gap.points) {
			appendOrderedJunctionPoint(boundary, point);
		}
	}

	if (boundary.length < 3) {
		const fallback = [];
		for (const portal of portals) {
			const right = roadRightFromTangent(portal.tangent);
			appendUniqueBoundaryPoint(fallback, makePoint(
				center.x + (right.x * (portal.halfWidth ?? 0)),
				center.z + (right.z * (portal.halfWidth ?? 0)),
				center.y ?? 0,
			));
			appendUniqueBoundaryPoint(fallback, makePoint(
				center.x - (right.x * (portal.halfWidth ?? 0)),
				center.z - (right.z * (portal.halfWidth ?? 0)),
				center.y ?? 0,
			));
		}
		return convexHullXZ(fallback);
	}

	return finalizeOrderedJunctionBoundary(boundary);
}

function buildJunctionSurfaceBoundary(junction) {
	return (junction.coreBoundary ?? []).map(clonePoint);
}

function pointLineDistanceXZ(point, linePoint, lineDir) {
	return Math.abs(cross2D(subtract2D(point, linePoint), lineDir));
}

function boundaryPointOnPortalSide(boundary, portal, sideSign) {
	const line = portalSideLine(portal, sideSign);
	let best = null;
	let bestT = -Infinity;

	const consider = (point) => {
		if (pointLineDistanceXZ(point, line.point, line.dir) > 0.08) {
			return;
		}
		const t = portalLineT(portal, point);
		if (t > bestT) {
			best = makePoint(point.x, point.z, line.point.y ?? 0);
			bestT = t;
		}
	};

	for (const point of boundary) {
		consider(point);
	}

	if (!best && boundary.length >= 2) {
		for (let index = 0; index < boundary.length; index += 1) {
			const a = boundary[index];
			const b = boundary[(index + 1) % boundary.length];
			const edge = subtract2D(b, a);
			if (Math.hypot(edge.x, edge.z) <= 1e-4) {
				continue;
			}
			const intersection = lineIntersectionWithParametersXZ(line.point, line.dir, a, edge);
			if (intersection && intersection.tB >= -0.001 && intersection.tB <= 1.001) {
				consider(intersection.point);
			}
		}
	}

	return best;
}

function portalSideEntriesForCore(junction) {
	const center = getJunctionMeshCenter(junction);
	const entries = [];
	for (const portal of junction.portals ?? []) {
		const right = roadRightFromTangent(portal.tangent);
		const centerT = portalLineT(portal, center);
		const projectedCenter = portalLinePointAtT(portal, centerT);
		entries.push({
			portal,
			linePoint: makePoint(
				portal.boundaryPoint.x - (right.x * portal.halfWidth),
				portal.boundaryPoint.z - (right.z * portal.halfWidth),
				portal.boundaryPoint.y ?? 0,
			),
			sortPoint: makePoint(
				projectedCenter.x - (right.x * portal.halfWidth),
				projectedCenter.z - (right.z * portal.halfWidth),
				projectedCenter.y ?? 0,
			),
		});
		entries.push({
			portal,
			linePoint: makePoint(
				portal.boundaryPoint.x + (right.x * portal.halfWidth),
				portal.boundaryPoint.z + (right.z * portal.halfWidth),
				portal.boundaryPoint.y ?? 0,
			),
			sortPoint: makePoint(
				projectedCenter.x + (right.x * portal.halfWidth),
				projectedCenter.z + (right.z * portal.halfWidth),
				projectedCenter.y ?? 0,
			),
		});
	}

	entries.sort((a, b) => junctionBoundaryAngle(a.sortPoint, junction) - junctionBoundaryAngle(b.sortPoint, junction));
	return entries;
}

function isCoreCornerCandidate(junction, fromEntry, toEntry, corner) {
	if (portalLineT(fromEntry.portal, corner) > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE) {
		return false;
	}
	if (portalLineT(toEntry.portal, corner) > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE) {
		return false;
	}

	const center = getJunctionMeshCenter(junction);
	const maxDistance = (junction.portals ?? []).reduce(
		(result, portal) => Math.max(result, distanceXZ(portal.boundaryPoint, center) + portal.halfWidth),
		junction.radius,
	);
	return distanceXZ(corner, center) <= Math.max(maxDistance, JUNCTION_RADIUS_MIN);
}

function updatePortalGeometry(junction, portal) {
	if (!junction.intersectionCenter) {
		junction.intersectionCenter = computeJunctionIntersectionCenter(junction);
	}

	const right = roadRightFromTangent(portal.tangent);
	const center = getJunctionMeshCenter(junction);
	let coreLeft = portal.coreLeft ?? makePoint(
		center.x - (right.x * portal.halfWidth),
		center.z - (right.z * portal.halfWidth),
		center.y ?? 0,
	);
	let coreRight = portal.coreRight ?? makePoint(
		center.x + (right.x * portal.halfWidth),
		center.z + (right.z * portal.halfWidth),
		center.y ?? 0,
	);
	if (dot2D(subtract2D(coreRight, coreLeft), right) < 0) {
		[coreLeft, coreRight] = [coreRight, coreLeft];
	}

	const corePoint = makePoint(
		(coreLeft.x + coreRight.x) * 0.5,
		(coreLeft.z + coreRight.z) * 0.5,
		((coreLeft.y ?? 0) + (coreRight.y ?? 0)) * 0.5,
	);
	const point = clonePoint(portal.boundaryPoint);
	const y = point.y ?? 0;
	portal.corePoint = corePoint;
	portal.coreLeft = coreLeft;
	portal.coreRight = coreRight;
	portal.point = point;
	portal.left = makePoint(point.x - (right.x * portal.halfWidth), point.z - (right.z * portal.halfWidth), y);
	portal.right = makePoint(point.x + (right.x * portal.halfWidth), point.z + (right.z * portal.halfWidth), y);
	portal.coreT = portalLineT(portal, corePoint);
	portal.mouthT = portalLineT(portal, point);
}

function trimChainEndpointToPortal(junction, portal) {
	const samples = portal.chain.samples;
	if (samples.length < 2) {
		return;
	}

	const isStart = distanceXZ(samples[0], portal.boundaryPoint) <= distanceXZ(samples[samples.length - 1], portal.boundaryPoint);
	if (isStart) {
		samples[0] = clonePoint(portal.point);
		while (
			samples.length > 2
			&& portalLineT(portal, samples[1]) < portal.mouthT - 0.05
		) {
			samples.splice(1, 1);
		}
	} else {
		samples[samples.length - 1] = clonePoint(portal.point);
		while (
			samples.length > 2
			&& portalLineT(portal, samples[samples.length - 2]) < portal.mouthT - 0.05
		) {
			samples.splice(samples.length - 2, 1);
		}
	}
}

function applySimplifiedJunctionGeometry(junction) {
	if (!junction.portals || junction.portals.length < 2) {
		return false;
	}

	const center = getJunctionMeshCenter(junction);
	const roads = junction.portals.map((portal, index) => ({
		id: String(index),
		direction: portal.tangent,
		endPoint: portal.boundaryPoint ?? portal.point,
		width: (portal.halfWidth ?? 0) * 2,
		portal,
	}));
	const geometry = calculateIntersectionGeometry(center, roads);
	if (geometry.vertices.length < 3) {
		return false;
	}

	for (const road of geometry.sortedRoads) {
		const portal = road.portal;
		if (!portal) {
			continue;
		}
		const side = roadRightFromTangent(portal.tangent);
		const point = portal.boundaryPoint ?? portal.point;
		portal.coreLeft = makePoint(
			point.x - (side.x * (portal.halfWidth ?? 0)),
			point.z - (side.z * (portal.halfWidth ?? 0)),
			point.y ?? 0,
		);
		portal.coreRight = makePoint(
			point.x + (side.x * (portal.halfWidth ?? 0)),
			point.z + (side.z * (portal.halfWidth ?? 0)),
			point.y ?? 0,
		);
	}

	junction.coreBoundary = geometry.vertices;
	junction.surfaceBoundary = geometry.vertices;
	junction.intersectionGeometry = geometry;
	return true;
}

function finalizeJunctionPortals(junctions) {
	for (const junction of junctions) {
		const hasSimplifiedGeometry = applySimplifiedJunctionGeometry(junction);
		if (!hasSimplifiedGeometry) {
			junction.coreBoundary = buildJunctionCoreBoundary(junction);
		}
		for (const portal of junction.portals || []) {
			updatePortalGeometry(junction, portal);
		}
		if (!hasSimplifiedGeometry) {
			junction.surfaceBoundary = buildJunctionSurfaceBoundary(junction);
		}
		for (const portal of junction.portals || []) {
			trimChainEndpointToPortal(junction, portal);
		}
	}
}

function finalizeAutomaticJunctionPortals(junctions) {
	for (const junction of junctions) {
		const hasSimplifiedGeometry = applySimplifiedJunctionGeometry(junction);
		if (!hasSimplifiedGeometry) {
			junction.coreBoundary = buildJunctionCoreBoundary(junction);
		}
		for (const portal of junction.portals || []) {
			updatePortalGeometry(junction, portal);
		}
		if (!hasSimplifiedGeometry) {
			junction.surfaceBoundary = buildJunctionSurfaceBoundary(junction);
		}
	}
}

function normalizePositiveAngleDelta(delta) {
	let result = delta;
	while (result <= 0) {
		result += Math.PI * 2;
	}
	while (result > Math.PI * 2) {
		result -= Math.PI * 2;
	}
	return result;
}

function junctionBoundaryAngle(point, junction) {
	const center = getJunctionMeshCenter(junction);
	return Math.atan2(point.z - center.z, point.x - center.x);
}

function entriesSharePortal(a, b) {
	return a.portal && b.portal && a.portal === b.portal;
}

function mergeBoundaryEntryPortal(target, source) {
	if (!entriesSharePortal(target, source)) {
		target.portal = null;
		target.corePoint = target.point;
	}
}

function sortedJunctionBoundaryEntries(junction) {
	const entries = [];
	for (const portal of junction.portals) {
		entries.push({ point: portal.left, corePoint: portal.coreLeft ?? portal.left, portal });
		entries.push({ point: portal.right, corePoint: portal.coreRight ?? portal.right, portal });
	}
	entries.sort((a, b) => junctionBoundaryAngle(a.point, junction) - junctionBoundaryAngle(b.point, junction));

	const filtered = [];
	for (const entry of entries) {
		const previous = filtered[filtered.length - 1];
		if (previous && distanceXZ(previous.point, entry.point) <= 0.05) {
			mergeBoundaryEntryPortal(previous, entry);
		} else {
			filtered.push({ point: entry.point, corePoint: entry.corePoint, portal: entry.portal });
		}
	}
	if (filtered.length >= 2 && distanceXZ(filtered[0].point, filtered[filtered.length - 1].point) <= 0.05) {
		mergeBoundaryEntryPortal(filtered[0], filtered[filtered.length - 1]);
		filtered.pop();
	}

	return filtered;
}

function addConnectorSubdivisionPoints(boundary, junction, fromPoint, toPoint, subdivisions) {
	const center = getJunctionMeshCenter(junction);
	const fromAngle = junctionBoundaryAngle(fromPoint, junction);
	const toAngle = junctionBoundaryAngle(toPoint, junction);
	const delta = normalizePositiveAngleDelta(toAngle - fromAngle);
	if (delta <= 1e-4 || delta >= (Math.PI * 2) - 1e-4) {
		return;
	}

	const fromRadius = distanceXZ(fromPoint, center);
	const toRadius = distanceXZ(toPoint, center);
	for (let index = 1; index <= subdivisions; index += 1) {
		const alpha = index / (subdivisions + 1);
		const angle = fromAngle + (delta * alpha);
		const radius = fromRadius + ((toRadius - fromRadius) * alpha);
		boundary.push(makePoint(
			center.x + (Math.cos(angle) * radius),
			center.z + (Math.sin(angle) * radius),
			(fromPoint.y ?? 0) + (((toPoint.y ?? 0) - (fromPoint.y ?? 0)) * alpha),
		));
	}
}

function appendBoundaryPoint(boundary, point) {
	if (boundary.length === 0 || distanceXZ(boundary[boundary.length - 1], point) > 0.05) {
		boundary.push(point);
	}
}

function appendUniqueBoundaryPoint(boundary, point) {
	if (!boundary.some((existing) => distanceXZ(existing, point) <= 0.05)) {
		boundary.push(point);
	}
}

function hullCrossXZ(origin, a, b) {
	return ((a.x - origin.x) * (b.z - origin.z)) - ((a.z - origin.z) * (b.x - origin.x));
}

function convexHullXZ(points) {
	if (points.length < 3) {
		return points;
	}

	const sorted = [...points].sort((a, b) => {
		if (Math.abs(a.x - b.x) > 0.001) {
			return a.x - b.x;
		}
		return a.z - b.z;
	});

	const lower = [];
	for (const point of sorted) {
		while (lower.length >= 2 && hullCrossXZ(lower[lower.length - 2], lower[lower.length - 1], point) <= 0.001) {
			lower.pop();
		}
		lower.push(point);
	}

	const upper = [];
	for (let index = sorted.length - 1; index >= 0; index -= 1) {
		const point = sorted[index];
		while (upper.length >= 2 && hullCrossXZ(upper[upper.length - 2], upper[upper.length - 1], point) <= 0.001) {
			upper.pop();
		}
		upper.push(point);
	}

	lower.pop();
	upper.pop();
	const hull = [...lower, ...upper];
	return hull.length >= 3 ? hull : points;
}

function portalConnectorPoints(portal) {
	const coreLeft = portal.coreLeft ?? portal.left;
	const coreRight = portal.coreRight ?? portal.right;
	return [
		clonePoint(coreLeft),
		clonePoint(coreRight),
		clonePoint(portal.left),
		clonePoint(portal.right),
	];
}

function addLinearSubdivisionPoints(boundary, fromPoint, toPoint, subdivisions) {
	for (let index = 1; index <= subdivisions; index += 1) {
		const alpha = index / (subdivisions + 1);
		appendBoundaryPoint(boundary, lerpPoint(fromPoint, toPoint, alpha));
	}
}

function isNaturalJunctionCorner(junction, fromEntry, toEntry, point) {
	if (!fromEntry.portal || !toEntry.portal) {
		return false;
	}

	const fromCorePoint = fromEntry.corePoint ?? fromEntry.point;
	const toCorePoint = toEntry.corePoint ?? toEntry.point;
	const fromAdvance = dot2D(subtract2D(point, fromCorePoint), fromEntry.portal.tangent);
	const toAdvance = dot2D(subtract2D(point, toCorePoint), toEntry.portal.tangent);
	if (fromAdvance > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE || toAdvance > JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE) {
		return false;
	}

	const maxDistance = Math.max(
		distanceXZ(fromCorePoint, getJunctionMeshCenter(junction)) + (fromEntry.portal.halfWidth ?? 0),
		distanceXZ(toCorePoint, getJunctionMeshCenter(junction)) + (toEntry.portal.halfWidth ?? 0),
	);
	return distanceXZ(point, getJunctionMeshCenter(junction)) <= Math.max(maxDistance, JUNCTION_RADIUS_MIN);
}

function naturalJunctionCorner(junction, fromEntry, toEntry) {
	if (!fromEntry.portal || !toEntry.portal) {
		return null;
	}

	const intersection = lineIntersectionXZ(
		fromEntry.corePoint ?? fromEntry.point,
		fromEntry.portal.tangent,
		toEntry.corePoint ?? toEntry.point,
		toEntry.portal.tangent,
	);
	if (!intersection) {
		return null;
	}

	const point = makePoint(
		intersection.x,
		intersection.z,
		((fromEntry.point.y ?? 0) + (toEntry.point.y ?? 0)) * 0.5,
	);
	return isNaturalJunctionCorner(junction, fromEntry, toEntry, point) ? point : null;
}

function addConnectorBoundaryPoints(boundary, junction, fromEntry, toEntry, subdivisions) {
	const corner = naturalJunctionCorner(junction, fromEntry, toEntry);
	if (corner) {
		addLinearSubdivisionPoints(boundary, fromEntry.point, corner, subdivisions);
		appendBoundaryPoint(boundary, corner);
		addLinearSubdivisionPoints(boundary, corner, toEntry.point, subdivisions);
		return;
	}

	if (subdivisions > 0) {
		addConnectorSubdivisionPoints(boundary, junction, fromEntry.point, toEntry.point, subdivisions);
	}
}

function buildJunctionBoundary(junction) {
	if (!junction.portals || junction.portals.length === 0) {
		return [];
	}

	if (junction.surfaceBoundary && junction.surfaceBoundary.length >= 3) {
		return junction.surfaceBoundary.map(clonePoint);
	}

	if (junction.coreBoundary && junction.coreBoundary.length >= 3) {
		return junction.coreBoundary.map(clonePoint);
	}

	const boundary = [];
	for (const portal of junction.portals) {
		const [coreLeft, coreRight] = portalConnectorPoints(portal);
		appendUniqueBoundaryPoint(boundary, coreLeft);
		appendUniqueBoundaryPoint(boundary, coreRight);
	}
	return convexHullXZ(boundary);
}

function buildJunctionConnectorQuads(junction) {
	const quads = [];
	for (const portal of junction.portals ?? []) {
		const [coreLeft, coreRight, mouthLeft, mouthRight] = portalConnectorPoints(portal);
		if (distanceXZ(coreLeft, mouthLeft) <= 0.05 && distanceXZ(coreRight, mouthRight) <= 0.05) {
			continue;
		}
		quads.push([coreLeft, mouthLeft, mouthRight, coreRight]);
	}
	return quads;
}

function addJunctionPatchToMeshPreviewRows(junction) {
	if (!junction.portals || junction.portals.length === 0) {
		return [];
	}
	return buildJunctionBoundary(junction);
}
