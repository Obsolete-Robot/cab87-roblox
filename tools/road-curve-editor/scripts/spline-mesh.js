// Spline road meshing helpers and loft generation.

function getRoadSampleTangent(samples, index, edgeCount, closedLoop, fallbackDir) {
	if (closedLoop) {
		const prevIndex = index > 0 ? index - 1 : edgeCount - 1;
		const nextIndex = index < edgeCount - 1 ? index + 1 : 0;
		const prevDir = horizontalUnit(subtract2D(samples[index], samples[prevIndex]));
		const nextDir = horizontalUnit(subtract2D(samples[nextIndex], samples[index]));
		if (prevDir && nextDir) {
			const combined = add2D(prevDir, nextDir);
			const unit = horizontalUnit(combined);
			if (unit) {
				return unit;
			}
		}
		return nextDir || prevDir || fallbackDir;
	}

	if (index === 0) {
		return horizontalUnit(subtract2D(samples[1], samples[0])) || fallbackDir;
	}
	if (index === edgeCount - 1) {
		return horizontalUnit(subtract2D(samples[edgeCount - 1], samples[edgeCount - 2])) || fallbackDir;
	}

	const prevDir = horizontalUnit(subtract2D(samples[index], samples[index - 1]));
	const nextDir = horizontalUnit(subtract2D(samples[index + 1], samples[index]));
	if (prevDir && nextDir) {
		const combined = add2D(prevDir, nextDir);
		const unit = horizontalUnit(combined);
		if (unit) {
			return unit;
		}
	}
	return nextDir || prevDir || fallbackDir;
}

function expandCentersForRoadWidth(centers, roadWidth, closedLoop) {
	let expanded = centers.map(clonePoint);
	const edgeCount = expanded.length;
	const halfWidth = roadWidth * 0.5;
	const targetRadius = halfWidth + Math.max(6, roadWidth * ROAD_INNER_EDGE_RADIUS_SCALE);

	for (let pass = 0; pass < ROAD_CURVE_EXPANSION_PASSES; pass += 1) {
		const nextCenters = expanded.map(clonePoint);
		for (let index = 0; index < edgeCount; index += 1) {
			if (!closedLoop && (index === 0 || index === edgeCount - 1)) {
				continue;
			}

			const prevIndex = index > 0 ? index - 1 : edgeCount - 1;
			const nextIndex = index < edgeCount - 1 ? index + 1 : 0;
			const centerPoint = circleCenterXZ(expanded[prevIndex], expanded[index], expanded[nextIndex]);
			if (!centerPoint) {
				continue;
			}

			const inward = horizontalUnit(subtract2D(centerPoint, expanded[index]));
			if (!inward) {
				continue;
			}
			const radius = distanceXZ(centerPoint, expanded[index]);
			if (radius < targetRadius) {
				const push = (targetRadius - radius) * ROAD_CURVE_EXPANSION_ALPHA;
				nextCenters[index] = makePoint(
					expanded[index].x - (inward.x * push),
					expanded[index].z - (inward.z * push),
					expanded[index].y ?? 0,
				);
			}
		}
		expanded = nextCenters;
	}

	return expanded;
}

function offsetEdgePoint(center, prevDir, prevRight, nextDir, nextRight, sideSign, halfWidth) {
	const prevOffset = makePoint(
		center.x + (prevRight.x * sideSign * halfWidth),
		center.z + (prevRight.z * sideSign * halfWidth),
		center.y ?? 0,
	);
	const nextOffset = makePoint(
		center.x + (nextRight.x * sideSign * halfWidth),
		center.z + (nextRight.z * sideSign * halfWidth),
		center.y ?? 0,
	);
	const intersection = lineIntersectionXZ(prevOffset, prevDir, nextOffset, nextDir);
	const maxMiterDistance = halfWidth * ROAD_EDGE_MITER_LIMIT;
	if (intersection) {
		const fromCenter = subtract2D(intersection, center);
		const length = Math.hypot(fromCenter.x, fromCenter.z);
		if (length > 1e-4) {
			if (length <= maxMiterDistance) {
				return intersection;
			}
			const scale = maxMiterDistance / length;
			return makePoint(
				center.x + (fromCenter.x * scale),
				center.z + (fromCenter.z * scale),
				center.y ?? 0,
			);
		}
	}

	let averagedRight = add2D(prevRight, nextRight);
	if (Math.hypot(averagedRight.x, averagedRight.z) < 1e-4) {
		averagedRight = nextRight;
	}
	const unit = horizontalUnit(averagedRight) || { x: 1, z: 0 };
	return makePoint(
		center.x + (unit.x * sideSign * halfWidth),
		center.z + (unit.z * sideSign * halfWidth),
		center.y ?? 0,
	);
}

function getUniqueRoadSamples(samples, closedLoop) {
	const unique = samples.map(clonePoint);
	if (closedLoop && unique.length > 1 && distanceXZ(unique[0], unique[unique.length - 1]) <= 0.05) {
		unique.pop();
	}
	return unique;
}

function buildRoadCrossSections(samples, roadWidth) {
	if (samples.length < 2) {
		return null;
	}

	const width = sanitizeRoadWidth(roadWidth);
	const closedLoop = sampleLoopIsClosed(samples);
	const centerControls = getUniqueRoadSamples(samples, closedLoop);
	if (centerControls.length < (closedLoop ? 3 : 2)) {
		return null;
	}

	const centerLength = polylineLength(centerControls, closedLoop);
	if (centerLength <= 1e-4) {
		return null;
	}

	const halfWidth = width * 0.5;
	const widthSegments = Math.min(
		ROAD_WIDTH_MAX_INTERNAL_LOOPS + 1,
		Math.max(1, Math.ceil(width / ROAD_WIDTH_TRIANGULATION_STEP)),
	);
	const rowCount = closedLoop
		? Math.max(3, centerControls.length, Math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP))
		: Math.max(2, centerControls.length, Math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP) + 1);
	const spanCount = closedLoop ? rowCount : rowCount - 1;
	const centers = [];
	const leftPositions = [];
	const rightPositions = [];
	const rights = [];
	let fallbackDir = { x: 0, z: 1 };

	for (let index = 0; index < rowCount; index += 1) {
		const fraction = closedLoop
			? (index / rowCount)
			: (rowCount > 1 ? (index / (rowCount - 1)) : 0);
		centers[index] = samplePolylineAtFraction(centerControls, closedLoop, fraction);
	}

	for (let index = 0; index < rowCount; index += 1) {
		let tangent;
		if (closedLoop) {
			const prev = centers[index > 0 ? index - 1 : rowCount - 1];
			const next = centers[index < rowCount - 1 ? index + 1 : 0];
			tangent = horizontalUnit(subtract2D(next, prev));
		} else if (index === 0) {
			tangent = horizontalUnit(subtract2D(centers[1], centers[0]));
		} else if (index === rowCount - 1) {
			tangent = horizontalUnit(subtract2D(centers[rowCount - 1], centers[rowCount - 2]));
		} else {
			tangent = horizontalUnit(subtract2D(centers[index + 1], centers[index - 1]));
		}

		fallbackDir = tangent || fallbackDir;
		let right = roadRightFromTangent(fallbackDir);
		if (index > 0 && rights[index - 1] && dot2D(right, rights[index - 1]) < 0) {
			right = scale2D(right, -1);
		}
		rights[index] = right;
		leftPositions[index] = makePoint(
			centers[index].x - (right.x * halfWidth),
			centers[index].z - (right.z * halfWidth),
			centers[index].y ?? 0,
		);
		rightPositions[index] = makePoint(
			centers[index].x + (right.x * halfWidth),
			centers[index].z + (right.z * halfWidth),
			centers[index].y ?? 0,
		);
	}

	return {
		roadWidth: width,
		closed: closedLoop,
		rowCount,
		spanCount,
		widthSegments,
		centers,
		left: leftPositions,
		right: rightPositions,
	};
}

function buildLoftRowVertices(left, right, widthSegments) {
	const row = [];
	for (let segment = 0; segment <= widthSegments; segment += 1) {
		row[segment] = lerpPoint(left, right, segment / widthSegments);
	}
	return row;
}
