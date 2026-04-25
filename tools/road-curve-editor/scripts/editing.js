// Curve and junction editing actions.

function pickJunction(clientX, clientY) {
	let best = null;
	let bestDistance = Infinity;
	for (const junction of state.junctions) {
		const screen = worldToScreen(junction.x, junction.z);
		const distance = Math.hypot(screen.x - clientX, screen.y - clientY);
		const hitRadius = Math.max(JUNCTION_HIT_RADIUS_PX, Math.min(24, junction.radius * state.zoom * 0.25));
		if (distance <= hitRadius && distance < bestDistance) {
			best = junction;
			bestDistance = distance;
		}
	}
	return best;
}

function pickJunctionRadius(clientX, clientY) {
	let best = null;
	let bestDistance = Infinity;
	for (const junction of state.junctions) {
		const screen = worldToScreen(junction.x, junction.z);
		const radiusPixels = Math.max(5, junction.radius * state.zoom);
		const distance = Math.hypot(screen.x - clientX, screen.y - clientY);
		const handleDistance = Math.hypot((screen.x + radiusPixels) - clientX, screen.y - clientY);
		if (junction.id === state.selectedJunctionId && handleDistance <= 9 && handleDistance < distance) {
			return junction;
		}

		const centerHitRadius = Math.max(JUNCTION_HIT_RADIUS_PX, Math.min(24, radiusPixels * 0.25));
		if (distance <= centerHitRadius) {
			continue;
		}

		const ringDistance = Math.abs(distance - radiusPixels);
		if (ringDistance <= JUNCTION_RADIUS_RING_HIT_PX && ringDistance < bestDistance) {
			best = junction;
			bestDistance = ringDistance;
		}
	}
	return best;
}

function pickPoint(clientX, clientY) {
	let best = null;
	let bestDistance = Infinity;

	state.splines.forEach((spline, splineIndex) => {
		spline.points.forEach((point, pointIndex) => {
			const screen = worldToScreen(point.x, point.z);
			const distance = Math.hypot(screen.x - clientX, screen.y - clientY);
			if (distance < POINT_HIT_RADIUS_PX && distance < bestDistance) {
				best = { spline, splineIndex, pointIndex };
				bestDistance = distance;
			}
		});
	});

	return best;
}

function createPoint(worldPoint) {
	return {
		x: roundNumber(worldPoint.x, 3),
		y: 0,
		z: roundNumber(worldPoint.z, 3),
	};
}

function insertPointAt(spline, insertIndex, worldPoint) {
	const clampedIndex = Math.max(0, Math.min(insertIndex, spline.points.length));
	spline.points.splice(clampedIndex, 0, createPoint(worldPoint));
	state.selectedPoint = {
		splineId: spline.id,
		pointIndex: clampedIndex,
	};
	state.selectedJunctionId = null;
	markMeshPreviewDirty();
	renderSplineList();
	refreshInspector();
	requestRender();
	return clampedIndex;
}

function addPointAt(worldPoint) {
	const spline = getActiveSpline();
	return insertPointAt(spline, spline.points.length, worldPoint);
}

function startPointDrag(spline, pointIndex, pointerId) {
	state.selectedPoint = {
		splineId: spline.id,
		pointIndex,
	};
	state.selectedJunctionId = null;
	state.drag = {
		mode: "point",
		splineId: spline.id,
		pointIndex,
		pointerId,
	};
	refreshInspector();
	renderSplineList();
	requestRender();
}

function projectPointToSegment(worldPoint, a, b) {
	const dx = b.x - a.x;
	const dz = b.z - a.z;
	const lengthSquared = (dx * dx) + (dz * dz);
	if (lengthSquared <= 1e-6) {
		return {
			point: clonePoint(a),
			alpha: 0,
			distanceWorld: distanceXZ(worldPoint, a),
		};
	}

	const rawAlpha = (((worldPoint.x - a.x) * dx) + ((worldPoint.z - a.z) * dz)) / lengthSquared;
	const alpha = Math.max(0, Math.min(1, rawAlpha));
	const point = makePoint(
		a.x + (dx * alpha),
		a.z + (dz * alpha),
		(a.y ?? 0) + ((((b.y ?? 0) - (a.y ?? 0)) * alpha)),
	);
	return {
		point,
		alpha,
		distanceWorld: distanceXZ(worldPoint, point),
	};
}

function findNearestPolylineProjection(points, closedLoop, localX, localY, worldPoint) {
	if (points.length < 2) {
		return null;
	}

	const segmentCount = closedLoop ? points.length : points.length - 1;
	let best = null;
	let bestDistancePixels = Infinity;
	for (let index = 0; index < segmentCount; index += 1) {
		const nextIndex = closedLoop ? ((index + 1) % points.length) : (index + 1);
		const projection = projectPointToSegment(worldPoint, points[index], points[nextIndex]);
		const screen = worldToScreen(projection.point.x, projection.point.z);
		const distancePixels = Math.hypot(screen.x - localX, screen.y - localY);
		if (distancePixels < bestDistancePixels) {
			best = {
				segmentIndex: index,
				nextIndex,
				alpha: projection.alpha,
				point: projection.point,
				distancePixels,
				distanceWorld: projection.distanceWorld,
			};
			bestDistancePixels = distancePixels;
		}
	}

	return best;
}

function getActiveCurveInsertionTarget(localX, localY, worldPoint) {
	const spline = getActiveSpline();
	const points = spline.points.map(createVector);

	if (points.length === 0) {
		return {
			spline,
			insertIndex: 0,
			point: worldPoint,
			mode: "append",
		};
	}

	if (points.length === 1) {
		return {
			spline,
			insertIndex: 1,
			point: worldPoint,
			mode: "append",
		};
	}

	const sampled = samplePositions(points, spline.closed, SAMPLE_STEP_STUDS);
	const sampledProjection = findNearestPolylineProjection(
		sampled,
		spline.closed && sampled.length > 2,
		localX,
		localY,
		worldPoint,
	);

	const controlProjection = findNearestPolylineProjection(points, spline.closed, localX, localY, worldPoint);
	if (!controlProjection) {
		return null;
	}

	if (!sampledProjection || sampledProjection.distancePixels > CURVE_INSERT_HIT_RADIUS_PX) {
		if (spline.closed) {
			return null;
		}

		const startScreen = worldToScreen(points[0].x, points[0].z);
		const endScreen = worldToScreen(points[points.length - 1].x, points[points.length - 1].z);
		const startDistance = Math.hypot(startScreen.x - localX, startScreen.y - localY);
		const endDistance = Math.hypot(endScreen.x - localX, endScreen.y - localY);

		if (startDistance <= endDistance) {
			return {
				spline,
				insertIndex: 0,
				point: worldPoint,
				mode: "prepend",
			};
		}

		return {
			spline,
			insertIndex: points.length,
			point: worldPoint,
			mode: "append",
		};
	}

	let insertIndex = controlProjection.segmentIndex + 1;
	let mode = "insert";
	let point = sampledProjection.point;
	if (!spline.closed) {
		const lastSegmentIndex = points.length - 2;
		if (controlProjection.segmentIndex === 0 && controlProjection.alpha <= CURVE_END_INSERT_ALPHA_THRESHOLD) {
			insertIndex = 0;
			mode = "prepend";
			point = worldPoint;
		} else if (controlProjection.segmentIndex === lastSegmentIndex && controlProjection.alpha >= (1 - CURVE_END_INSERT_ALPHA_THRESHOLD)) {
			insertIndex = points.length;
			mode = "append";
			point = worldPoint;
		}
	}

	return {
		spline,
		insertIndex,
		point,
		mode,
	};
}

function deleteSelectedPoint() {
	const selected = getSelectedPointRecord();
	if (!selected) {
		if (state.selectedJunctionId) {
			deleteSelectedJunction();
			return;
		}
		setStatus("Select a control point or junction before deleting it.");
		return;
	}
	selected.spline.points.splice(selected.pointIndex, 1);
	state.selectedPoint = null;
	markMeshPreviewDirty();
	setStatus(`Removed point ${selected.pointIndex + 1} from ${selected.spline.name}.`);
	renderSplineList();
	refreshInspector();
	requestRender();
}

function findJunctionContainingControlPoint(pointHit) {
	if (!pointHit) {
		return null;
	}
	const point = pointHit.spline.points[pointHit.pointIndex];
	return state.junctions.find((junction) => distanceXZ(point, junction) <= junction.radius + 0.001) || null;
}

function addJunctionAtControlPoint(pointHit) {
	if (!pointHit) {
		setStatus("Junction Mode adds junctions from existing curve points. Add or click a curve point first.");
		return null;
	}

	const existing = findJunctionContainingControlPoint(pointHit);
	if (existing) {
		state.selectedJunctionId = existing.id;
		state.selectedPoint = null;
		refreshInspector();
		requestRender();
		return existing;
	}

	const selected = getSelectedJunction();
	const radius = selected ? selected.radius : sanitizeJunctionRadius(elements.junctionRadiusInput.value);
	const subdivisions = selected ? selected.subdivisions : sanitizeJunctionSubdivisions(elements.junctionSubdivisionsInput.value);
	const point = pointHit.spline.points[pointHit.pointIndex];
	const junction = makeJunction(point, radius, subdivisions);
	const records = collectControlPointsInJunction(junction);
	if (collectAutoJunctionConnections(junction, records).length === 0) {
		setStatus("Junctions need a curve point with a connected road segment. Add another point to the curve first.");
		return null;
	}

	state.junctions.push(junction);
	state.selectedJunctionId = junction.id;
	state.selectedPoint = null;
	markMeshPreviewDirty();
	refreshInspector();
	requestRender();
	setStatus(`Added ${junction.name} from ${pointHit.spline.name}:${pointHit.pointIndex + 1}.`);
	return junction;
}

function startJunctionDrag(junction, pointerId) {
	state.selectedJunctionId = junction.id;
	state.selectedPoint = null;
	const groupedPoints = collectControlPointsInJunction(junction).map((record) => ({
		point: record.point,
		startX: record.point.x,
		startY: record.point.y ?? 0,
		startZ: record.point.z,
	}));
	state.drag = {
		mode: "junction",
		junctionId: junction.id,
		pointerId,
		startX: junction.x,
		startZ: junction.z,
		groupedPoints,
	};
	refreshInspector();
	requestRender();
}

function startJunctionRadiusDrag(junction, pointerId) {
	state.selectedJunctionId = junction.id;
	state.selectedPoint = null;
	state.drag = {
		mode: "junction-radius",
		junctionId: junction.id,
		pointerId,
	};
	refreshInspector();
	requestRender();
}

function deleteJunction(junction) {
	state.junctions = state.junctions.filter((item) => item.id !== junction.id);
	if (state.selectedJunctionId === junction.id) {
		state.selectedJunctionId = null;
	}
	markMeshPreviewDirty();
	refreshInspector();
	requestRender();
	setStatus(`Deleted ${junction.name}.`);
}

function deleteSelectedJunction() {
	const selected = getSelectedJunction();
	if (!selected) {
		setStatus("Select a junction before deleting it.");
		return;
	}
	deleteJunction(selected);
}

function updateSelectedJunctionRadiusFromInput() {
	const selected = getSelectedJunction();
	const radius = sanitizeJunctionRadius(elements.junctionRadiusInput.value);
	if (selected) {
		selected.radius = radius;
		markMeshPreviewDirty();
		requestRender();
		setStatus(`Set ${selected.name} radius to ${formatNumber(radius, 1)} studs.`);
	}
	refreshInspector();
}

function updateSelectedJunctionSubdivisionsFromInput() {
	const selected = getSelectedJunction();
	const subdivisions = sanitizeJunctionSubdivisions(elements.junctionSubdivisionsInput.value);
	if (selected) {
		selected.subdivisions = subdivisions;
		markMeshPreviewDirty();
		requestRender();
		setStatus(`Set ${selected.name} subdivisions to ${subdivisions}.`);
	}
	refreshInspector();
}

function collectControlPointsInJunction(junction) {
	const records = [];
	for (const spline of state.splines) {
		const width = sanitizeRoadWidth(spline.width);
		spline.points.forEach((point, pointIndex) => {
			const distance = distanceXZ(point, junction);
			if (distance <= junction.radius + 0.001) {
				records.push({
					spline,
					point,
					pointIndex,
					distance,
					width,
				});
			}
		});
	}
	return records;
}

function getControlPointRecordKey(record) {
	return `${record.spline.id}:${record.pointIndex}`;
}

function getSplinePointIndex(spline, index) {
	const count = spline.points.length;
	if (count === 0) {
		return null;
	}
	if (spline.closed) {
		return (index + count) % count;
	}
	if (index < 0 || index >= count) {
		return null;
	}
	return index;
}

function findFirstOutsidePointIndex(spline, startIndex, step, snappedPointKeys) {
	for (let offset = 1; offset <= spline.points.length; offset += 1) {
		const index = getSplinePointIndex(spline, startIndex + (offset * step));
		if (index === null) {
			return null;
		}
		const key = `${spline.id}:${index}`;
		if (!snappedPointKeys.has(key)) {
			return index;
		}
	}
	return null;
}

function collectAutoJunctionConnections(junction, records) {
	const snappedPointKeys = new Set(records.map(getControlPointRecordKey));
	const connectionKeys = new Set();
	const connections = [];

	for (const record of records) {
		for (const step of [-1, 1]) {
			const outsideIndex = findFirstOutsidePointIndex(record.spline, record.pointIndex, step, snappedPointKeys);
			if (outsideIndex === null) {
				continue;
			}

			const connectionKey = `${record.spline.id}:${outsideIndex}:${step}`;
			if (connectionKeys.has(connectionKey)) {
				continue;
			}
			connectionKeys.add(connectionKey);

			const outsidePoint = record.spline.points[outsideIndex];
			const direction = horizontalUnit(subtract2D(outsidePoint, junction));
			if (!direction) {
				continue;
			}

			connections.push({
				direction,
				distance: distanceXZ(outsidePoint, junction),
				width: record.width,
			});
		}
	}

	return connections;
}

function junctionHasCurveConnections(junction) {
	const records = collectControlPointsInJunction(junction);
	return records.length > 0 && collectAutoJunctionConnections(junction, records).length > 0;
}

function angleBetweenUnitDirections(a, b) {
	const value = Math.max(-1, Math.min(1, dot2D(a, b)));
	return Math.acos(value);
}

function sameControlPointRecords(a, b) {
	if (a.length !== b.length) {
		return false;
	}

	const aKeys = new Set(a.map(getControlPointRecordKey));
	for (const record of b) {
		if (!aKeys.has(getControlPointRecordKey(record))) {
			return false;
		}
	}
	return true;
}

function calculateLargestRoadAutoJunctionRadius(records, connections) {
	let largestWidth = JUNCTION_RADIUS_MIN - JUNCTION_RADIUS_PADDING;
	for (const record of records) {
		largestWidth = Math.max(largestWidth, record.width);
	}
	for (const connection of connections) {
		largestWidth = Math.max(largestWidth, connection.width);
	}

	let radius = largestWidth + JUNCTION_RADIUS_PADDING;
	for (let i = 0; i < connections.length; i += 1) {
		for (let j = i + 1; j < connections.length; j += 1) {
			const angle = angleBetweenUnitDirections(connections[i].direction, connections[j].direction);
			if (angle < 0.12) {
				continue;
			}
			const widthAllowance = ((connections[i].width + connections[j].width) * 0.5) + JUNCTION_RADIUS_PADDING;
			radius = Math.max(radius, widthAllowance / Math.max(0.01, 2 * Math.sin(angle * 0.5)));
		}
	}

	return sanitizeJunctionRadius(radius);
}

function autoSelectedJunction() {
	const selected = getSelectedJunction();
	if (!selected) {
		setStatus("Select a junction before running Auto Junction.");
		return;
	}

	const records = collectControlPointsInJunction(selected);
	if (records.length === 0) {
		setStatus(`No control points are inside ${selected.name}'s radius.`);
		return;
	}

	for (const record of records) {
		record.point.x = roundNumber(selected.x, 3);
		record.point.y = roundNumber(selected.y ?? 0, 3);
		record.point.z = roundNumber(selected.z, 3);
	}

	markMeshPreviewDirty();
	renderSplineList();
	refreshInspector();
	requestRender();
	setStatus(`Auto-fit ${selected.name}: centered ${records.length} control point${records.length === 1 ? "" : "s"}. Radius is only used to choose grouped points.`);
}

function createSplineAndActivate() {
	state.splines.push(makeSpline(getNextSplineName()));
	state.activeSplineIndex = state.splines.length - 1;
	state.selectedPoint = null;
	markMeshPreviewDirty();
	renderSplineList();
	refreshInspector();
	requestRender();
}

function deleteActiveSpline() {
	if (state.splines.length <= 1) {
		state.splines[0] = makeSpline("Spline001");
		state.activeSplineIndex = 0;
		state.selectedPoint = null;
		setStatus("Reset the only spline.");
	} else {
		const removed = getActiveSpline();
		state.splines.splice(state.activeSplineIndex, 1);
		state.activeSplineIndex = Math.max(0, state.activeSplineIndex - 1);
		state.selectedPoint = null;
		setStatus(`Deleted ${removed.name}.`);
	}
	markMeshPreviewDirty();
	renderSplineList();
	refreshInspector();
	requestRender();
}

function splitSelectedSplineAtPoint() {
	const selected = getSelectedPointRecord();
	if (!selected) {
		setStatus("Select an interior control point before splitting a curve.");
		return;
	}

	const spline = selected.spline;
	if (spline.closed) {
		setStatus("Split Curve works on open curves. Turn off Closed loop before splitting.");
		return;
	}
	if (spline.points.length < 3) {
		setStatus(`${spline.name} needs at least three control points to split.`);
		return;
	}
	if (selected.pointIndex <= 0 || selected.pointIndex >= spline.points.length - 1) {
		setStatus("Select an interior control point, not an endpoint, before splitting.");
		return;
	}

	const splineIndex = state.splines.findIndex((item) => item.id === spline.id);
	if (splineIndex < 0) {
		setStatus("Selected curve no longer exists.");
		return;
	}

	const originalName = spline.name;
	const secondSpline = makeSpline(getNextSplineName());
	secondSpline.width = spline.width;
	secondSpline.closed = false;
	secondSpline.points = spline.points.slice(selected.pointIndex).map(clonePoint);
	spline.points = spline.points.slice(0, selected.pointIndex + 1).map(clonePoint);

	state.splines.splice(splineIndex + 1, 0, secondSpline);
	state.activeSplineIndex = splineIndex + 1;
	state.selectedPoint = {
		splineId: secondSpline.id,
		pointIndex: 0,
	};
	state.selectedJunctionId = null;
	state.drag = null;

	markMeshPreviewDirty();
	renderSplineList();
	refreshInspector();
	requestRender();
	setStatus(`Split ${originalName} at point ${selected.pointIndex + 1}; ${secondSpline.name} starts at the split point.`);
}

function centerViewOnActiveSpline() {
	frameActiveSpline(true);
}


function updateActiveWidthFromInput() {
	const value = Number(elements.widthInput.value);
	if (!Number.isFinite(value)) {
		refreshInspector();
		setStatus("Enter a numeric road width.");
		return;
	}
	getActiveSpline().width = sanitizeRoadWidth(value);
	markMeshPreviewDirty();
	renderSplineList();
	refreshInspector();
	requestRender();
}
