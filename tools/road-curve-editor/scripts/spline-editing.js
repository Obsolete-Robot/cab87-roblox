// Spline editing actions and curve insertion helpers.

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

function updateDraggedPoint(localX, localY) {
	if (!state.drag || state.drag.mode !== "point") {
		return;
	}

	const spline = state.splines.find((item) => item.id === state.drag.splineId);
	if (!spline) {
		return;
	}

	const point = spline.points[state.drag.pointIndex];
	if (!point) {
		return;
	}

	const world = screenToWorld(localX, localY);
	point.x = roundNumber(world.x, 3);
	point.z = roundNumber(world.z, 3);
	state.selectedPoint = {
		splineId: spline.id,
		pointIndex: state.drag.pointIndex,
	};
	markMeshPreviewDirty();
	refreshInspector();
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
