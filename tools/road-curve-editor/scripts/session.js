// Session import/export and autosave persistence.

function cloneSplineForExport(spline) {
	return {
		name: spline.name,
		closed: spline.closed && spline.points.length >= 3,
		width: roundNumber(spline.width, 3),
		points: spline.points.map((point) => ({
			x: roundNumber(point.x, 3),
			y: 0,
			z: roundNumber(point.z, 3),
		})),
	};
}

function cloneSplineForEditorPersistence(spline) {
	return {
		name: spline.name,
		closed: spline.closed && spline.points.length >= 3,
		width: roundNumber(spline.width, 3),
		points: spline.points.map((point) => ({
			x: roundNumber(point.x, 3),
			y: roundNumber(point.y ?? 0, 3),
			z: roundNumber(point.z, 3),
		})),
	};
}

function cloneJunctionForExport(junction) {
	return {
		id: junction.name || junction.id,
		radius: roundNumber(sanitizeJunctionRadius(junction.radius), 3),
		subdivisions: sanitizeJunctionSubdivisions(junction.subdivisions),
		x: roundNumber(junction.x, 3),
		y: roundNumber(junction.y ?? 0, 3),
		z: roundNumber(junction.z, 3),
	};
}


function readFileAsText(file) {
	return new Promise((resolve, reject) => {
		const reader = new FileReader();
		reader.onload = () => resolve(typeof reader.result === "string" ? reader.result : "");
		reader.onerror = () => reject(new Error(`Could not read ${file.name}.`));
		reader.readAsText(file);
	});
}

function buildSessionPayload() {
	const selected = getSelectedPointRecord();
	const exportableJunctions = state.junctions.filter(junctionHasCurveConnections);
	return {
		version: 2,
		sampleStepStuds: SAMPLE_STEP_STUDS,
		coordinateSpace: {
			upAxis: "Y",
			planarAxes: ["X", "Z"],
			units: "studs",
		},
		splines: state.splines
			.filter((spline) => spline.points.length >= 2)
			.map(cloneSplineForExport),
		junctions: exportableJunctions.map(cloneJunctionForExport),
		editorState: {
			camera: {
				x: roundNumber(state.cameraX, 3),
				z: roundNumber(state.cameraZ, 3),
				zoom: roundNumber(state.zoom, 4),
			},
			activeSplineIndex: state.activeSplineIndex,
			selectedPoint: selected
				? {
					splineIndex: state.splines.findIndex((spline) => spline.id === selected.spline.id),
					pointIndex: selected.pointIndex,
				}
				: null,
			selectedJunctionIndex: exportableJunctions.findIndex((junction) => junction.id === state.selectedJunctionId),
			image: hasLoadedImage()
				? {
					fileName: state.image.fileName,
					mimeType: state.image.mimeType,
					width: state.image.intrinsicWidth,
					height: state.image.intrinsicHeight,
					dataUrl: state.image.dataUrl,
					offsetX: roundNumber(state.image.offsetX, 3),
					offsetZ: roundNumber(state.image.offsetZ, 3),
					scale: roundNumber(state.image.scale, 4),
					opacity: sanitizeOpacity(state.image.opacity),
				}
				: null,
			meshPreviewEnabled: state.meshPreviewEnabled,
			junctionModeEnabled: state.junctionModeEnabled,
		},
	};
}

function buildEditorPersistencePayload() {
	const payload = buildSessionPayload();
	return {
		...payload,
		splines: state.splines.map(cloneSplineForEditorPersistence),
		editorState: {
			...payload.editorState,
			autosavedAt: new Date().toISOString(),
		},
	};
}

function normalizeImportedSpline(splineData, index, options = {}) {
	if (!splineData || typeof splineData !== "object" || !Array.isArray(splineData.points)) {
		return null;
	}
	const minPoints = Number.isInteger(options.minPoints) ? options.minPoints : 2;

	const name = typeof splineData.name === "string" && splineData.name.trim().length > 0
		? splineData.name.trim()
		: `Spline${String(index + 1).padStart(3, "0")}`;
	const spline = makeSpline(name);
	spline.width = sanitizeRoadWidth(splineData.width);

	for (const pointData of splineData.points) {
		if (!pointData || typeof pointData !== "object") {
			continue;
		}
		const x = Number(pointData.x);
		const z = Number(pointData.z);
			if (!Number.isFinite(x) || !Number.isFinite(z)) {
				continue;
			}
			const y = Number(pointData.y);
			spline.points.push({
				x: roundNumber(x, 3),
				y: Number.isFinite(y) ? roundNumber(y, 3) : 0,
				z: roundNumber(z, 3),
			});
		}

	if (spline.points.length < minPoints) {
		return null;
	}

	spline.closed = splineData.closed === true && spline.points.length >= 3;
	return spline;
}

function normalizeImportedJunction(junctionData, index) {
	if (!junctionData || typeof junctionData !== "object") {
		return null;
	}

	const x = Number(junctionData.x);
	const z = Number(junctionData.z);
	if (!Number.isFinite(x) || !Number.isFinite(z)) {
		return null;
	}

	const junction = makeJunction(
		{
			x,
			y: Number.isFinite(Number(junctionData.y)) ? Number(junctionData.y) : 0,
			z,
		},
		junctionData.radius,
		junctionData.subdivisions,
	);
	junction.name = typeof junctionData.id === "string" && junctionData.id.trim().length > 0
		? junctionData.id.trim()
		: `Junction${String(index + 1).padStart(3, "0")}`;
	return junction;
}

function frameActiveSpline(setMessage = true) {
	const spline = getActiveSpline();
	const points = (spline.points.length > 0
		? spline.points
		: state.splines.flatMap((item) => item.points))
		.concat(state.junctions.map((junction) => ({
			x: junction.x,
			y: junction.y ?? 0,
			z: junction.z,
		})));

	if (points.length === 0) {
		state.cameraX = 0;
		state.cameraZ = 0;
		state.zoom = 1.1;
		if (setMessage) {
			setStatus("Centered on origin.");
		} else {
			refreshInspector();
			requestRender();
		}
		return;
	}

	let minX = Infinity;
	let maxX = -Infinity;
	let minZ = Infinity;
	let maxZ = -Infinity;
	points.forEach((point) => {
		minX = Math.min(minX, point.x);
		maxX = Math.max(maxX, point.x);
		minZ = Math.min(minZ, point.z);
		maxZ = Math.max(maxZ, point.z);
	});

	state.cameraX = (minX + maxX) * 0.5;
	state.cameraZ = (minZ + maxZ) * 0.5;

	const width = Math.max(50, maxX - minX);
	const height = Math.max(50, maxZ - minZ);
	const availableWidth = Math.max(220, elements.canvas.clientWidth - 120);
	const availableHeight = Math.max(220, elements.canvas.clientHeight - 120);
	const zoomX = availableWidth / width;
	const zoomY = availableHeight / height;
	state.zoom = Math.max(0.08, Math.min(8, Math.min(zoomX, zoomY)));

	if (setMessage) {
		setStatus(`Centered view on ${spline.name}.`);
	} else {
		refreshInspector();
		requestRender();
	}
}

async function importSessionFromText(text, options = {}) {
	let payload;
	try {
		payload = JSON.parse(text);
	} catch (error) {
		throw new Error(`Could not parse JSON: ${error.message}`);
	}

	if (!payload || typeof payload !== "object" || !Array.isArray(payload.splines)) {
		throw new Error("Session JSON must include a splines array.");
	}

	const minPoints = options.allowIncompleteSplines ? 0 : 2;
	const importedSplines = payload.splines
		.map((splineData, index) => normalizeImportedSpline(splineData, index, { minPoints }))
		.filter(Boolean);

	if (importedSplines.length === 0) {
		throw new Error(options.allowIncompleteSplines
			? "Saved session did not contain any valid splines."
			: "Session JSON did not contain any valid splines with at least 2 points.");
	}

	state.splines = importedSplines;
	state.junctions = Array.isArray(payload.junctions)
		? payload.junctions
			.map((junctionData, index) => normalizeImportedJunction(junctionData, index))
			.filter(Boolean)
		: [];
	state.activeSplineIndex = 0;
	state.selectedPoint = null;
	state.selectedJunctionId = null;

	const editorState = payload.editorState && typeof payload.editorState === "object"
		? payload.editorState
		: null;
	state.meshPreviewEnabled = editorState ? editorState.meshPreviewEnabled === true : false;
	state.junctionModeEnabled = editorState ? editorState.junctionModeEnabled === true : false;

	if (editorState && Number.isInteger(editorState.activeSplineIndex)) {
		state.activeSplineIndex = Math.min(
			Math.max(editorState.activeSplineIndex, 0),
			state.splines.length - 1,
		);
	}

	if (editorState && editorState.camera && typeof editorState.camera === "object") {
		state.cameraX = Number.isFinite(Number(editorState.camera.x)) ? Number(editorState.camera.x) : 0;
		state.cameraZ = Number.isFinite(Number(editorState.camera.z)) ? Number(editorState.camera.z) : 0;
		state.zoom = sanitizeZoom(editorState.camera.zoom);
	} else {
		frameActiveSpline(false);
	}

	if (editorState && editorState.selectedPoint && typeof editorState.selectedPoint === "object") {
		const splineIndex = Number(editorState.selectedPoint.splineIndex);
		const pointIndex = Number(editorState.selectedPoint.pointIndex);
		if (
			Number.isInteger(splineIndex)
			&& Number.isInteger(pointIndex)
			&& splineIndex >= 0
			&& splineIndex < state.splines.length
			&& pointIndex >= 0
			&& pointIndex < state.splines[splineIndex].points.length
		) {
			state.selectedPoint = {
				splineId: state.splines[splineIndex].id,
				pointIndex,
			};
		}
	}
	if (editorState && Number.isInteger(editorState.selectedJunctionIndex)) {
		const junction = state.junctions[editorState.selectedJunctionIndex];
		if (junction) {
			state.selectedJunctionId = junction.id;
			state.selectedPoint = null;
		}
	}

	clearImageSourceState();
	const imageState = editorState && editorState.image && typeof editorState.image === "object"
		? editorState.image
		: null;
	if (imageState && typeof imageState.dataUrl === "string" && imageState.dataUrl.length > 0) {
		await loadImageFromDataUrl(imageState.dataUrl, {
			fileName: imageState.fileName,
			mimeType: imageState.mimeType,
			width: imageState.width,
			height: imageState.height,
		});
		state.image.offsetX = Number.isFinite(Number(imageState.offsetX)) ? Number(imageState.offsetX) : 0;
		state.image.offsetZ = Number.isFinite(Number(imageState.offsetZ)) ? Number(imageState.offsetZ) : 0;
		state.image.scale = Number.isFinite(Number(imageState.scale)) && Number(imageState.scale) > 0
			? Number(imageState.scale)
			: 1;
		state.image.opacity = sanitizeOpacity(imageState.opacity);
	} else {
		state.image.offsetX = 0;
		state.image.offsetZ = 0;
		state.image.scale = 1;
		state.image.opacity = 55;
	}

	markMeshPreviewDirty();
	renderSplineList();
	refreshInspector();
	requestRender();
	if (options.statusMessage) {
		setStatus(options.statusMessage);
	} else {
		setStatus(`Imported ${importedSplines.length} spline${importedSplines.length === 1 ? "" : "s"} and ${state.junctions.length} junction${state.junctions.length === 1 ? "" : "s"} from session JSON.`);
	}
}

function getAutosaveStorage() {
	try {
		return window.localStorage || null;
	} catch (error) {
		return null;
	}
}

function writeAutosavePayload(payload) {
	const storage = getAutosaveStorage();
	if (!storage) {
		return false;
	}
	storage.setItem(AUTOSAVE_STORAGE_KEY, JSON.stringify(payload));
	return true;
}

function saveEditorAutosave() {
	if (!autosaveReady || state.splines.length === 0) {
		return false;
	}

	const payload = buildEditorPersistencePayload();
	try {
		return writeAutosavePayload(payload);
	} catch (error) {
		const image = payload.editorState && payload.editorState.image;
		if (image && image.dataUrl) {
			try {
				const fallbackPayload = {
					...payload,
					editorState: {
						...payload.editorState,
						image: {
							...image,
							dataUrl: "",
							autosaveImageOmitted: true,
						},
					},
				};
				const saved = writeAutosavePayload(fallbackPayload);
				if (saved && !autosaveWarned) {
					autosaveWarned = true;
					console.warn("Cab87 Road Curve Editor autosave skipped trace image data because browser storage quota was exceeded.");
				}
				return saved;
			} catch (fallbackError) {
				if (!autosaveWarned) {
					autosaveWarned = true;
					console.warn("Cab87 Road Curve Editor autosave failed.", fallbackError);
				}
				return false;
			}
		}
		if (!autosaveWarned) {
			autosaveWarned = true;
			console.warn("Cab87 Road Curve Editor autosave failed.", error);
		}
		return false;
	}
}

function scheduleAutosave() {
	if (!autosaveReady) {
		return;
	}
	if (autosaveTimer) {
		window.clearTimeout(autosaveTimer);
	}
	autosaveTimer = window.setTimeout(() => {
		autosaveTimer = null;
		saveEditorAutosave();
	}, AUTOSAVE_DEBOUNCE_MS);
}

function flushAutosave() {
	if (autosaveTimer) {
		window.clearTimeout(autosaveTimer);
		autosaveTimer = null;
	}
	saveEditorAutosave();
}

async function restoreAutosavedSession() {
	const storage = getAutosaveStorage();
	if (!storage) {
		return false;
	}
	const saved = storage.getItem(AUTOSAVE_STORAGE_KEY);
	if (!saved) {
		return false;
	}
	await importSessionFromText(saved, {
		allowIncompleteSplines: true,
		statusMessage: "Restored autosaved editor session from this browser.",
	});
	return true;
}


function exportCurves() {
	const payload = buildSessionPayload();

	if (payload.splines.length === 0) {
		setStatus("Add at least one spline with two points before exporting.");
		return;
	}

	const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
	const url = URL.createObjectURL(blob);
	const link = document.createElement("a");
	link.href = url;
	link.download = "cab87-road-curves.json";
	link.click();
	URL.revokeObjectURL(url);
	setStatus(`Exported ${payload.splines.length} spline${payload.splines.length === 1 ? "" : "s"} and ${payload.junctions.length} junction${payload.junctions.length === 1 ? "" : "s"} to JSON.`);
}

