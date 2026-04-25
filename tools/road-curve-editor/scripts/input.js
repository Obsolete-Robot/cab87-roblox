// Input handlers, DOM event binding, and app initialization.

function updateCursorReadout(clientX, clientY) {
	const world = screenToWorld(clientX, clientY);
	state.mouseWorld = world;
	elements.cursorReadout.textContent = `X ${formatNumber(world.x, 1)} | Z ${formatNumber(world.z, 1)} | Zoom ${formatNumber(state.zoom, 2)}x`;
}

function handleCanvasPointerDown(event) {
	event.preventDefault();
	const rect = elements.canvas.getBoundingClientRect();
	const localX = event.clientX - rect.left;
	const localY = event.clientY - rect.top;
	const world = screenToWorld(localX, localY);
	updateCursorReadout(localX, localY);

	if (event.button === 1 || event.button === 2) {
		state.drag = {
			mode: "pan",
			startClientX: event.clientX,
			startClientY: event.clientY,
			startCameraX: state.cameraX,
			startCameraZ: state.cameraZ,
		};
		elements.canvas.style.cursor = "grabbing";
		elements.canvas.setPointerCapture(event.pointerId);
		return;
	}

	if (state.junctionModeEnabled) {
		const radiusHit = pickJunctionRadius(localX, localY);
		const junctionHit = pickJunction(localX, localY);
		const hitJunction = junctionHit || radiusHit;
		if (hitJunction && event.altKey) {
			deleteJunction(hitJunction);
			return;
		}
		if (radiusHit) {
			startJunctionRadiusDrag(radiusHit, event.pointerId);
			setStatus(`Scaling ${radiusHit.name}.`);
			elements.canvas.setPointerCapture(event.pointerId);
			return;
		}
		if (junctionHit) {
			startJunctionDrag(junctionHit, event.pointerId);
			setStatus(`Dragging ${junctionHit.name}.`);
			elements.canvas.setPointerCapture(event.pointerId);
			return;
		}
		const pointHit = pickPoint(localX, localY);
		const junction = addJunctionAtControlPoint(pointHit);
		if (!junction) {
			return;
		}
		startJunctionDrag(junction, event.pointerId);
		setStatus(`Dragging ${junction.name} with ${state.drag.groupedPoints.length} grouped point${state.drag.groupedPoints.length === 1 ? "" : "s"}.`);
		elements.canvas.setPointerCapture(event.pointerId);
		return;
	}

	const hit = pickPoint(localX, localY);
	if (hit) {
		state.activeSplineIndex = hit.splineIndex;
		state.selectedJunctionId = null;
		startPointDrag(hit.spline, hit.pointIndex, event.pointerId);
		setStatus(`Dragging ${hit.spline.name}:${hit.pointIndex + 1}.`);
		elements.canvas.setPointerCapture(event.pointerId);
		return;
	}

	const insertion = getActiveCurveInsertionTarget(localX, localY, world);
	if (!insertion) {
		setStatus("Click the active curve to insert a point, or click New to start a new curve.");
		return;
	}

	const insertedIndex = insertPointAt(insertion.spline, insertion.insertIndex, insertion.point);
	startPointDrag(insertion.spline, insertedIndex, event.pointerId);
	if (insertion.mode === "prepend") {
		setStatus(`Prepending point ${insertedIndex + 1} on ${insertion.spline.name}.`);
	} else if (insertion.mode === "append") {
		setStatus(`Appending point ${insertedIndex + 1} on ${insertion.spline.name}.`);
	} else {
		setStatus(`Inserted point ${insertedIndex + 1} on ${insertion.spline.name}.`);
	}
	elements.canvas.setPointerCapture(event.pointerId);
}

function handleCanvasPointerMove(event) {
	const rect = elements.canvas.getBoundingClientRect();
	const localX = event.clientX - rect.left;
	const localY = event.clientY - rect.top;
	updateCursorReadout(localX, localY);

	if (!state.drag) {
		return;
	}

	if (state.drag.mode === "pan") {
		const dx = (event.clientX - state.drag.startClientX) / state.zoom;
		const dy = (event.clientY - state.drag.startClientY) / state.zoom;
		state.cameraX = state.drag.startCameraX - dx;
		state.cameraZ = state.drag.startCameraZ + dy;
		requestRender();
		return;
	}

	if (state.drag.mode === "point") {
		const record = getSelectedPointRecord();
		if (!record) {
			return;
		}
		const world = screenToWorld(localX, localY);
		record.point.x = roundNumber(world.x, 3);
		record.point.z = roundNumber(world.z, 3);
		markMeshPreviewDirty();
		refreshInspector();
		requestRender();
	}

	if (state.drag.mode === "junction") {
		const junction = state.junctions.find((item) => item.id === state.drag.junctionId);
		if (!junction) {
			return;
			}
			const world = screenToWorld(localX, localY);
			const dx = world.x - state.drag.startX;
			const dz = world.z - state.drag.startZ;
			junction.x = roundNumber(world.x, 3);
			junction.z = roundNumber(world.z, 3);
			for (const groupedPoint of state.drag.groupedPoints) {
				groupedPoint.point.x = roundNumber(groupedPoint.startX + dx, 3);
				groupedPoint.point.y = roundNumber(groupedPoint.startY, 3);
				groupedPoint.point.z = roundNumber(groupedPoint.startZ + dz, 3);
			}
			markMeshPreviewDirty();
			refreshInspector();
			requestRender();
		}

	if (state.drag.mode === "junction-radius") {
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
}

function handleCanvasPointerUp(event) {
	if (state.drag) {
		state.drag = null;
		elements.canvas.style.cursor = "crosshair";
		if (elements.canvas.hasPointerCapture(event.pointerId)) {
			elements.canvas.releasePointerCapture(event.pointerId);
		}
	}
}

function handleCanvasWheel(event) {
	event.preventDefault();
	const rect = elements.canvas.getBoundingClientRect();
	const localX = event.clientX - rect.left;
	const localY = event.clientY - rect.top;
	const before = screenToWorld(localX, localY);
	const factor = Math.exp(-event.deltaY * 0.0014);
	state.zoom = Math.max(0.05, Math.min(12, state.zoom * factor));
	const after = screenToWorld(localX, localY);
	state.cameraX += before.x - after.x;
	state.cameraZ += before.z - after.z;
	updateCursorReadout(localX, localY);
	requestRender();
}


function handleKeyDown(event) {
	const tag = document.activeElement && document.activeElement.tagName;
	if (tag === "INPUT" || tag === "TEXTAREA") {
		return;
	}
	if (event.key === "Delete" || event.key === "Backspace") {
		event.preventDefault();
		deleteSelectedPoint();
	} else if (event.key.toLowerCase() === "n") {
		event.preventDefault();
		createSplineAndActivate();
		setStatus(`Created ${getActiveSpline().name}.`);
	} else if (event.key.toLowerCase() === "j") {
		event.preventDefault();
		toggleJunctionMode();
	}
}

function bindEvents() {
	window.addEventListener("resize", resizeCanvas);
	window.addEventListener("keydown", handleKeyDown);
	window.addEventListener("beforeunload", flushAutosave);

	elements.canvas.addEventListener("contextmenu", (event) => event.preventDefault());
	elements.canvas.addEventListener("mousedown", (event) => {
		if (event.button === 1) {
			event.preventDefault();
		}
	});
	elements.canvas.addEventListener("auxclick", (event) => {
		event.preventDefault();
	});
	elements.canvas.addEventListener("pointerdown", handleCanvasPointerDown);
	elements.canvas.addEventListener("pointermove", handleCanvasPointerMove);
	elements.canvas.addEventListener("pointerup", handleCanvasPointerUp);
	elements.canvas.addEventListener("pointercancel", handleCanvasPointerUp);
	elements.canvas.addEventListener("wheel", handleCanvasWheel, { passive: false });

	elements.newSplineButton.addEventListener("click", () => {
		createSplineAndActivate();
		setStatus(`Created ${getActiveSpline().name}.`);
	});

	elements.prevSplineButton.addEventListener("click", () => {
		setActiveSpline((state.activeSplineIndex - 1 + state.splines.length) % state.splines.length);
		setStatus(`Active spline set to ${getActiveSpline().name}.`);
	});

	elements.nextSplineButton.addEventListener("click", () => {
		setActiveSpline((state.activeSplineIndex + 1) % state.splines.length);
		setStatus(`Active spline set to ${getActiveSpline().name}.`);
	});

	elements.deleteSplineButton.addEventListener("click", deleteActiveSpline);
	elements.deletePointButton.addEventListener("click", deleteSelectedPoint);
	elements.splitSplineButton.addEventListener("click", splitSelectedSplineAtPoint);
	elements.centerViewButton.addEventListener("click", centerViewOnActiveSpline);
	elements.junctionModeButton.addEventListener("click", toggleJunctionMode);
	elements.autoJunctionButton.addEventListener("click", autoSelectedJunction);
	elements.deleteJunctionButton.addEventListener("click", deleteSelectedJunction);
	elements.junctionRadiusInput.addEventListener("change", updateSelectedJunctionRadiusFromInput);
	elements.junctionRadiusInput.addEventListener("blur", updateSelectedJunctionRadiusFromInput);
	elements.junctionSubdivisionsInput.addEventListener("change", updateSelectedJunctionSubdivisionsFromInput);
	elements.junctionSubdivisionsInput.addEventListener("blur", updateSelectedJunctionSubdivisionsFromInput);
	elements.exportButton.addEventListener("click", exportCurves);
	elements.importButton.addEventListener("click", () => {
		elements.curveJsonInput.click();
	});

	elements.widthInput.addEventListener("change", updateActiveWidthFromInput);
	elements.widthInput.addEventListener("blur", updateActiveWidthFromInput);
	elements.closedToggle.addEventListener("change", () => {
		const spline = getActiveSpline();
		spline.closed = elements.closedToggle.checked;
		markMeshPreviewDirty();
		refreshInspector();
		renderSplineList();
		requestRender();
		setStatus(`${spline.name} is now ${spline.closed ? "closed" : "open"}.`);
	});
	elements.meshPreviewToggle.addEventListener("change", () => {
		state.meshPreviewEnabled = elements.meshPreviewToggle.checked;
		markMeshPreviewDirty();
		refreshInspector();
		requestRender();
		setStatus(state.meshPreviewEnabled ? "Roblox mesh preview enabled." : "Roblox mesh preview disabled.");
	});

	elements.imageInput.addEventListener("change", async () => {
		await loadImageFromFile(elements.imageInput.files[0]);
	});

	elements.curveJsonInput.addEventListener("change", async () => {
		const file = elements.curveJsonInput.files[0];
		elements.curveJsonInput.value = "";
		if (!file) {
			return;
		}

		try {
			const text = await readFileAsText(file);
			await importSessionFromText(text);
		} catch (error) {
			setStatus(error.message || `Could not import ${file.name}.`);
		}
	});

	elements.imageOffsetXInput.addEventListener("change", updateImageTransformFromInputs);
	elements.imageOffsetXInput.addEventListener("blur", updateImageTransformFromInputs);
	elements.imageOffsetZInput.addEventListener("change", updateImageTransformFromInputs);
	elements.imageOffsetZInput.addEventListener("blur", updateImageTransformFromInputs);
	elements.imageScaleInput.addEventListener("change", updateImageTransformFromInputs);
	elements.imageScaleInput.addEventListener("blur", updateImageTransformFromInputs);
	elements.imageOpacityInput.addEventListener("input", () => {
		state.image.opacity = Number(elements.imageOpacityInput.value);
		refreshInspector();
		requestRender();
	});

	elements.resetImageButton.addEventListener("click", resetImageTransform);
	elements.clearImageButton.addEventListener("click", clearImage);
}

async function initialize() {
	state.splines = [makeSpline("Spline001")];
	state.junctions = [];
	state.image = createEmptyImageState();
	bindEvents();
	resizeCanvas();

	let restored = false;
	try {
		restored = await restoreAutosavedSession();
	} catch (error) {
		const storage = getAutosaveStorage();
		if (storage) {
			storage.removeItem(AUTOSAVE_STORAGE_KEY);
		}
		console.warn("Cab87 Road Curve Editor could not restore autosaved session.", error);
	}

	autosaveReady = true;
	if (!restored) {
		renderSplineList();
		refreshInspector();
		centerViewOnActiveSpline();
		setStatus("Ready. Import an image or start placing points.");
	}
	scheduleAutosave();
}

