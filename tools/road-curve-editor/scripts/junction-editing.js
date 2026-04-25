// Junction editing actions and grouped control-point helpers.

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
	const hitData = collectSplineJunctionHitData(junction);
	if (hitData.roadArmCount === 0) {
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
	state.drag = {
		mode: "junction",
		junctionId: junction.id,
		pointerId,
		startX: junction.x,
		startZ: junction.z,
	};
	refreshInspector();
	requestRender();
}

function updateDraggedJunction(localX, localY) {
	if (!state.drag || state.drag.mode !== "junction") {
		return;
	}

	const junction = state.junctions.find((item) => item.id === state.drag.junctionId);
	if (!junction) {
		return;
	}

	const world = screenToWorld(localX, localY);
	junction.x = roundNumber(world.x, 3);
	junction.z = roundNumber(world.z, 3);
	markMeshPreviewDirty();
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

function updateDraggedJunctionRadius(localX, localY) {
	if (!state.drag || state.drag.mode !== "junction-radius") {
		return;
	}

	const junction = state.junctions.find((item) => item.id === state.drag.junctionId);
	if (!junction) {
		return;
	}

	const world = screenToWorld(localX, localY);
	junction.radius = sanitizeJunctionRadius(distanceXZ(world, junction));
	markMeshPreviewDirty();
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
	return collectSplineJunctionHitData(junction).roadArmCount > 0;
}

function autoSelectedJunction() {
	const selected = getSelectedJunction();
	if (!selected) {
		setStatus("Select a junction before running Auto Junction.");
		return;
	}

	const hitData = collectSplineJunctionHitData(selected);
	if (hitData.hits.length === 0) {
		setStatus(`No sampled road entrances were found inside ${selected.name}'s radius.`);
		return;
	}

	const center = computeJunctionCenterFromHits(hitData.hits, selected);
	selected.x = roundNumber(center.x, 3);
	selected.y = roundNumber(center.y ?? selected.y ?? 0, 3);
	selected.z = roundNumber(center.z, 3);

	markMeshPreviewDirty();
	renderSplineList();
	refreshInspector();
	requestRender();
	setStatus(`Auto-fit ${selected.name}: centered from ${hitData.roadArmCount} sampled road arm${hitData.roadArmCount === 1 ? "" : "s"}.`);
}
