// Soft-selection transforms for large map layout edits.

function softSelectionWeight(distance, radius) {
	const safeRadius = Math.max(radius, SOFT_SELECTION_RADIUS_MIN);
	const t = Math.min(1, Math.max(0, distance / safeRadius));
	const smooth = (t * t) * (3 - (2 * t));
	return Math.max(0, 1 - smooth);
}

function getSoftSelectionStatus() {
	if (!state.softSelectionEnabled) {
		return "Soft Select disabled.";
	}
	return `Soft Select enabled. Radius ${formatNumber(state.softSelectionRadius, 1)} studs.`;
}

function setSoftSelectionRadius(value, showStatus = true) {
	state.softSelectionRadius = sanitizeSoftSelectionRadius(value);
	refreshInspector();
	requestRender();
	if (showStatus) {
		setStatus(getSoftSelectionStatus());
	}
}

function updateSoftSelectionRadiusFromInput() {
	setSoftSelectionRadius(elements.softSelectionRadiusInput.value);
}

function updateSoftSelectionRadiusFromSlider() {
	setSoftSelectionRadius(elements.softSelectionRadiusSlider.value, false);
}

function pickSoftSelectionAnchor(clientX, clientY) {
	let best = null;
	let bestDistance = Infinity;

	state.splines.forEach((spline, splineIndex) => {
		spline.points.forEach((point, pointIndex) => {
			const screen = worldToScreen(point.x, point.z);
			const distance = Math.hypot(screen.x - clientX, screen.y - clientY);
			if (distance <= POINT_HIT_RADIUS_PX && distance < bestDistance) {
				best = {
					type: "point",
					spline,
					splineIndex,
					point,
					pointIndex,
					distancePixels: distance,
				};
				bestDistance = distance;
			}
		});
	});

	for (const junction of state.junctions) {
		const screen = worldToScreen(junction.x, junction.z);
		const distance = Math.hypot(screen.x - clientX, screen.y - clientY);
		const hitRadius = Math.max(JUNCTION_HIT_RADIUS_PX, Math.min(24, junction.radius * state.zoom * 0.25));
		if (distance <= hitRadius && distance < bestDistance) {
			best = {
				type: "junction",
				junction,
				distancePixels: distance,
			};
			bestDistance = distance;
		}
	}

	return best;
}

function collectSoftSelectionTargets(origin, radius) {
	const targets = [];
	const safeRadius = sanitizeSoftSelectionRadius(radius);

	state.splines.forEach((spline) => {
		spline.points.forEach((point, pointIndex) => {
			const distance = distanceXZ(point, origin);
			if (distance > safeRadius + 0.001) {
				return;
			}
			const weight = softSelectionWeight(distance, safeRadius);
			if (weight <= SOFT_SELECTION_MIN_WEIGHT && distance > 0.001) {
				return;
			}
			targets.push({
				type: "point",
				target: point,
				splineId: spline.id,
				pointIndex,
				startX: point.x,
				startY: point.y ?? 0,
				startZ: point.z,
				distance,
				weight,
			});
		});
	});

	for (const junction of state.junctions) {
		const distance = distanceXZ(junction, origin);
		if (distance > safeRadius + 0.001) {
			continue;
		}
		const weight = softSelectionWeight(distance, safeRadius);
		if (weight <= SOFT_SELECTION_MIN_WEIGHT && distance > 0.001) {
			continue;
		}
		targets.push({
			type: "junction",
			target: junction,
			junctionId: junction.id,
			startX: junction.x,
			startY: junction.y ?? 0,
			startZ: junction.z,
			distance,
			weight,
		});
	}

	return targets;
}

function countSoftSelectionTargets(targets) {
	return targets.reduce((counts, target) => {
		if (target.type === "point") {
			counts.points += 1;
		} else if (target.type === "junction") {
			counts.junctions += 1;
		}
		return counts;
	}, { points: 0, junctions: 0 });
}

function describeSoftSelectionAnchor(anchor) {
	if (!anchor) {
		return "map control";
	}
	if (anchor.type === "point") {
		return `${anchor.spline.name}:${anchor.pointIndex + 1}`;
	}
	return anchor.junction.name;
}

function startSoftSelectionDrag(anchor, pointerWorld, pointerId) {
	const origin = anchor.type === "junction" ? anchor.junction : anchor.point;
	const radius = sanitizeSoftSelectionRadius(state.softSelectionRadius);
	const targets = collectSoftSelectionTargets(origin, radius);

	if (anchor.type === "point") {
		state.activeSplineIndex = anchor.splineIndex;
		state.selectedPoint = {
			splineId: anchor.spline.id,
			pointIndex: anchor.pointIndex,
		};
		state.selectedJunctionId = null;
	} else {
		state.selectedPoint = null;
		state.selectedJunctionId = anchor.junction.id;
	}

	state.drag = {
		mode: "soft-selection",
		pointerId,
		anchor,
		originX: origin.x,
		originZ: origin.z,
		startPointerX: pointerWorld.x,
		startPointerZ: pointerWorld.z,
		radius,
		targets,
	};

	const counts = countSoftSelectionTargets(targets);
	refreshInspector();
	renderSplineList();
	requestRender();
	setStatus(
		`Soft dragging ${describeSoftSelectionAnchor(anchor)} with ${counts.points} point${counts.points === 1 ? "" : "s"} and ${counts.junctions} junction${counts.junctions === 1 ? "" : "s"}.`,
	);
}

function updateDraggedSoftSelection(localX, localY) {
	if (!state.drag || state.drag.mode !== "soft-selection") {
		return;
	}

	const world = screenToWorld(localX, localY);
	const dx = world.x - state.drag.startPointerX;
	const dz = world.z - state.drag.startPointerZ;

	for (const target of state.drag.targets) {
		target.target.x = roundNumber(target.startX + (dx * target.weight), 3);
		target.target.y = roundNumber(target.startY, 3);
		target.target.z = roundNumber(target.startZ + (dz * target.weight), 3);
	}

	markMeshPreviewDirty();
	refreshInspector();
	requestRender();
}
