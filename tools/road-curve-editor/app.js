const ROAD_WIDTH_DEFAULT = 28;
const ROAD_WIDTH_MIN = 8;
const ROAD_WIDTH_MAX = 200;
const AUTOSAVE_STORAGE_KEY = "cab87-road-curve-editor-autosave-v2";
const AUTOSAVE_DEBOUNCE_MS = 350;
const JUNCTION_RADIUS_DEFAULT = 22;
const JUNCTION_RADIUS_MIN = 6;
const JUNCTION_RADIUS_MAX = 220;
const JUNCTION_RADIUS_PADDING = 2;
const JUNCTION_VERTEX_EPSILON = 0.05;
const JUNCTION_SUBDIVISIONS_DEFAULT = 0;
const JUNCTION_SUBDIVISIONS_MIN = 0;
const JUNCTION_SUBDIVISIONS_MAX = 12;
const JUNCTION_CROSSWALK_LENGTH_DEFAULT = 8;
const JUNCTION_CROSSWALK_LENGTH_MIN = 0;
const JUNCTION_CROSSWALK_LENGTH_MAX = 80;
const JUNCTION_NATURAL_INTERSECTION_FORWARD_TOLERANCE = 0.5;
const SAMPLE_STEP_STUDS = 8;
const ENDPOINT_WELD_DISTANCE = 22;
const INTERSECTION_RADIUS_SCALE = 0.5;
const INTERSECTION_BLEND_SCALE = 0.95;
const INTERSECTION_MERGE_SCALE = 0.45;
const INTERSECTION_RING_SEGMENTS = 28;
const ROAD_EDGE_MITER_LIMIT = 2.75;
const ROAD_EDGE_SMOOTH_PASSES = 2;
const ROAD_EDGE_SMOOTH_ALPHA = 0.35;
const ROAD_WIDTH_TRIANGULATION_STEP = 24;
const ROAD_WIDTH_MAX_INTERNAL_LOOPS = 2;
const ROAD_LOFT_LENGTH_STEP = SAMPLE_STEP_STUDS;
const ROAD_EDGE_CURVE_SMOOTH_STEP = Math.max(1, ROAD_LOFT_LENGTH_STEP * 0.25);
const ROAD_EDGE_CURVE_FAIR_PASSES = 4;
const ROAD_EDGE_CURVE_FAIR_ALPHA = 0.42;
const ROAD_CURVE_EXPANSION_PASSES = 0;
const ROAD_CURVE_EXPANSION_ALPHA = 0.8;
const ROAD_INNER_EDGE_RADIUS_SCALE = 0.08;
const POINT_HIT_RADIUS_PX = 12;
const JUNCTION_HIT_RADIUS_PX = 13;
const JUNCTION_RADIUS_RING_HIT_PX = 8;
const CURVE_INSERT_HIT_RADIUS_PX = 18;
const CURVE_END_INSERT_ALPHA_THRESHOLD = 0.28;

const elements = {
	canvas: document.getElementById("editorCanvas"),
	splineList: document.getElementById("splineList"),
	widthInput: document.getElementById("widthInput"),
	closedToggle: document.getElementById("closedToggle"),
	meshPreviewToggle: document.getElementById("meshPreviewToggle"),
	deletePointButton: document.getElementById("deletePointButton"),
	splitSplineButton: document.getElementById("splitSplineButton"),
	centerViewButton: document.getElementById("centerViewButton"),
	junctionRadiusInput: document.getElementById("junctionRadiusInput"),
	junctionCrosswalkLengthInput: document.getElementById("junctionCrosswalkLengthInput"),
	junctionSubdivisionsInput: document.getElementById("junctionSubdivisionsInput"),
	junctionModeButton: document.getElementById("junctionModeButton"),
	autoJunctionButton: document.getElementById("autoJunctionButton"),
	deleteJunctionButton: document.getElementById("deleteJunctionButton"),
	newSplineButton: document.getElementById("newSplineButton"),
	prevSplineButton: document.getElementById("prevSplineButton"),
	nextSplineButton: document.getElementById("nextSplineButton"),
	deleteSplineButton: document.getElementById("deleteSplineButton"),
	imageInput: document.getElementById("imageInput"),
	imageOffsetXInput: document.getElementById("imageOffsetXInput"),
	imageOffsetZInput: document.getElementById("imageOffsetZInput"),
	imageScaleInput: document.getElementById("imageScaleInput"),
	imageOpacityInput: document.getElementById("imageOpacityInput"),
	resetImageButton: document.getElementById("resetImageButton"),
	clearImageButton: document.getElementById("clearImageButton"),
	importButton: document.getElementById("importButton"),
	curveJsonInput: document.getElementById("curveJsonInput"),
	exportButton: document.getElementById("exportButton"),
	status: document.getElementById("status"),
	cursorReadout: document.getElementById("cursorReadout"),
};

const ctx = elements.canvas.getContext("2d");

let autosaveReady = false;
let autosaveTimer = null;
let autosaveWarned = false;

const state = {
	cameraX: 0,
	cameraZ: 0,
	zoom: 1.1,
	splines: [],
	junctions: [],
	activeSplineIndex: 0,
	selectedPoint: null,
	selectedJunctionId: null,
	drag: null,
	mouseWorld: { x: 0, z: 0 },
	image: {
		objectUrl: null,
		element: null,
		dataUrl: "",
		fileName: "",
		mimeType: "",
		intrinsicWidth: 0,
		intrinsicHeight: 0,
		offsetX: 0,
		offsetZ: 0,
		scale: 1,
		opacity: 55,
	},
	statusMessage: "",
	meshPreviewEnabled: false,
	junctionModeEnabled: false,
	meshPreviewDirty: true,
	meshPreviewCache: null,
};

let renderQueued = false;

function sanitizeRoadWidth(value) {
	const width = Number(value);
	if (!Number.isFinite(width)) {
		return ROAD_WIDTH_DEFAULT;
	}
	return Math.min(ROAD_WIDTH_MAX, Math.max(ROAD_WIDTH_MIN, width));
}

function sanitizeJunctionRadius(value) {
	const radius = Number(value);
	if (!Number.isFinite(radius)) {
		return JUNCTION_RADIUS_DEFAULT;
	}
	return Math.min(JUNCTION_RADIUS_MAX, Math.max(JUNCTION_RADIUS_MIN, radius));
}

function sanitizeJunctionSubdivisions(value) {
	const subdivisions = Number(value);
	if (!Number.isFinite(subdivisions)) {
		return JUNCTION_SUBDIVISIONS_DEFAULT;
	}
	return Math.min(
		JUNCTION_SUBDIVISIONS_MAX,
		Math.max(JUNCTION_SUBDIVISIONS_MIN, Math.round(subdivisions)),
	);
}

function sanitizeJunctionCrosswalkLength(value) {
	const length = Number(value);
	if (!Number.isFinite(length)) {
		return JUNCTION_CROSSWALK_LENGTH_DEFAULT;
	}
	return Math.min(JUNCTION_CROSSWALK_LENGTH_MAX, Math.max(JUNCTION_CROSSWALK_LENGTH_MIN, length));
}

function roundNumber(value, decimals = 3) {
	const factor = 10 ** decimals;
	return Math.round(value * factor) / factor;
}

function formatNumber(value, decimals = 1) {
	if (!Number.isFinite(value)) {
		return "0";
	}
	const rounded = roundNumber(value, decimals);
	if (Math.abs(rounded - Math.round(rounded)) < 1e-4) {
		return String(Math.round(rounded));
	}
	return rounded.toFixed(decimals);
}

function makeSpline(name) {
	return {
		id: `spline-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
		name,
		width: ROAD_WIDTH_DEFAULT,
		closed: false,
		points: [],
	};
}

function makeJunction(
	position,
	radius = JUNCTION_RADIUS_DEFAULT,
	subdivisions = JUNCTION_SUBDIVISIONS_DEFAULT,
	crosswalkLength = JUNCTION_CROSSWALK_LENGTH_DEFAULT,
) {
	return {
		id: `junction-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
		name: `Junction${String(state.junctions.length + 1).padStart(3, "0")}`,
		x: roundNumber(position.x, 3),
		y: roundNumber(position.y ?? 0, 3),
		z: roundNumber(position.z, 3),
		radius: sanitizeJunctionRadius(radius),
		subdivisions: sanitizeJunctionSubdivisions(subdivisions),
		crosswalkLength: sanitizeJunctionCrosswalkLength(crosswalkLength),
	};
}

function sanitizeOpacity(value) {
	const opacity = Number(value);
	if (!Number.isFinite(opacity)) {
		return 55;
	}
	return Math.min(100, Math.max(0, opacity));
}

function sanitizeZoom(value) {
	const zoom = Number(value);
	if (!Number.isFinite(zoom)) {
		return 1.1;
	}
	return Math.min(12, Math.max(0.05, zoom));
}

function createEmptyImageState() {
	return {
		objectUrl: null,
		element: null,
		dataUrl: "",
		fileName: "",
		mimeType: "",
		intrinsicWidth: 0,
		intrinsicHeight: 0,
		offsetX: 0,
		offsetZ: 0,
		scale: 1,
		opacity: 55,
	};
}

function getNextSplineName() {
	let maxIndex = 0;
	for (const spline of state.splines) {
		const match = /^Spline(\d+)$/.exec(spline.name);
		if (match) {
			maxIndex = Math.max(maxIndex, Number(match[1]));
		}
	}
	return `Spline${String(maxIndex + 1).padStart(3, "0")}`;
}

function ensureActiveSpline() {
	if (state.splines.length === 0) {
		state.splines.push(makeSpline("Spline001"));
	}
	state.activeSplineIndex = Math.min(Math.max(state.activeSplineIndex, 0), state.splines.length - 1);
	return state.splines[state.activeSplineIndex];
}

function getActiveSpline() {
	return ensureActiveSpline();
}

function getSelectedPointRecord() {
	if (!state.selectedPoint) {
		return null;
	}
	const spline = state.splines.find((item) => item.id === state.selectedPoint.splineId);
	if (!spline) {
		return null;
	}
	const point = spline.points[state.selectedPoint.pointIndex];
	if (!point) {
		return null;
	}
	return {
		spline,
		point,
		pointIndex: state.selectedPoint.pointIndex,
	};
}

function getSelectedJunction() {
	if (!state.selectedJunctionId) {
		return null;
	}
	return state.junctions.find((junction) => junction.id === state.selectedJunctionId) || null;
}

function setActiveSpline(index) {
	state.activeSplineIndex = Math.min(Math.max(index, 0), state.splines.length - 1);
	const selected = getSelectedPointRecord();
	if (selected && selected.spline.id !== getActiveSpline().id) {
		state.selectedPoint = null;
	}
	refreshInspector();
	renderSplineList();
	requestRender();
}

function setStatus(message) {
	state.statusMessage = message;
	updateStatus();
}

function updateStatus() {
	const spline = getActiveSpline();
	const selected = getSelectedPointRecord();
	const previewMode = state.meshPreviewEnabled ? "Mesh" : "Ribbon";
	const selectedText = selected
		? `Selected ${selected.spline.name}:${selected.pointIndex + 1} at X ${formatNumber(selected.point.x, 1)}, Z ${formatNumber(selected.point.z, 1)}.`
		: "No point selected.";
	elements.status.textContent =
		`${spline.name} | ${spline.points.length} control points | ${spline.closed ? "Closed" : "Open"} | Width ${formatNumber(spline.width, 1)} studs | Preview ${previewMode}.\n` +
		`${selectedText}\n` +
		`${state.statusMessage || "Preview uses the same Catmull-Rom subdivision rule as the Roblox road editor sampler."}`;
}

function setJunctionModeEnabled(enabled) {
	state.junctionModeEnabled = enabled;
	elements.junctionModeButton.classList.toggle("primary", enabled);
	elements.junctionModeButton.textContent = enabled ? "Junction Mode: On" : "Junction Mode";
}

function getJunctionModeStatus() {
	return state.junctionModeEnabled
		? "Junction Mode enabled. Click an existing curve point to add, drag centers to move grouped points, drag radius rings to scale, Alt-click to delete."
		: "Junction Mode disabled.";
}

function toggleJunctionMode() {
	setJunctionModeEnabled(!state.junctionModeEnabled);
	refreshInspector();
	setStatus(getJunctionModeStatus());
}

function refreshInspector() {
	const spline = getActiveSpline();
	elements.widthInput.value = formatNumber(spline.width, 1);
	elements.closedToggle.checked = spline.closed;
	elements.meshPreviewToggle.checked = state.meshPreviewEnabled;
	setJunctionModeEnabled(state.junctionModeEnabled);
	const selectedJunction = getSelectedJunction();
	elements.junctionRadiusInput.value = formatNumber(selectedJunction ? selectedJunction.radius : JUNCTION_RADIUS_DEFAULT, 1);
	elements.junctionCrosswalkLengthInput.value = formatNumber(selectedJunction ? sanitizeJunctionCrosswalkLength(selectedJunction.crosswalkLength) : JUNCTION_CROSSWALK_LENGTH_DEFAULT, 1);
	elements.junctionSubdivisionsInput.value = String(selectedJunction ? sanitizeJunctionSubdivisions(selectedJunction.subdivisions) : JUNCTION_SUBDIVISIONS_DEFAULT);
	elements.imageOffsetXInput.value = formatNumber(state.image.offsetX, 1);
	elements.imageOffsetZInput.value = formatNumber(state.image.offsetZ, 1);
	elements.imageScaleInput.value = formatNumber(state.image.scale, 2);
	elements.imageOpacityInput.value = String(state.image.opacity);
	updateStatus();
}

function markMeshPreviewDirty() {
	state.meshPreviewDirty = true;
	state.meshPreviewCache = null;
}

function renderSplineList() {
	elements.splineList.textContent = "";
	state.splines.forEach((spline, index) => {
		const card = document.createElement("button");
		card.type = "button";
		card.className = `spline-card${index === state.activeSplineIndex ? " active" : ""}`;
		card.addEventListener("click", () => {
			setActiveSpline(index);
			setStatus(`Active spline set to ${spline.name}.`);
		});

		const title = document.createElement("div");
		title.className = "spline-card-title";
		title.innerHTML = `<span>${spline.name}</span><span>${formatNumber(spline.width, 1)}</span>`;

		const meta = document.createElement("div");
		meta.className = "spline-card-meta";
		meta.textContent = `${spline.closed ? "Closed" : "Open"} | ${spline.points.length} pts`;

		card.append(title, meta);
		elements.splineList.append(card);
	});
}

function createVector(point) {
	return { x: point.x, y: point.y ?? 0, z: point.z };
}

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
		crosswalkLength: roundNumber(sanitizeJunctionCrosswalkLength(junction.crosswalkLength), 3),
		subdivisions: sanitizeJunctionSubdivisions(junction.subdivisions),
		x: roundNumber(junction.x, 3),
		y: roundNumber(junction.y ?? 0, 3),
		z: roundNumber(junction.z, 3),
	};
}

function hasLoadedImage() {
	return Boolean(state.image.element && state.image.dataUrl);
}

function readFileAsText(file) {
	return new Promise((resolve, reject) => {
		const reader = new FileReader();
		reader.onload = () => resolve(typeof reader.result === "string" ? reader.result : "");
		reader.onerror = () => reject(new Error(`Could not read ${file.name}.`));
		reader.readAsText(file);
	});
}

function readFileAsDataUrl(file) {
	return new Promise((resolve, reject) => {
		const reader = new FileReader();
		reader.onload = () => resolve(typeof reader.result === "string" ? reader.result : "");
		reader.onerror = () => reject(new Error(`Could not read ${file.name}.`));
		reader.readAsDataURL(file);
	});
}

function loadImageFromDataUrl(dataUrl, metadata = {}) {
	return new Promise((resolve, reject) => {
		if (!dataUrl) {
			reject(new Error("Missing image data."));
			return;
		}

		const image = new Image();
		image.onload = () => {
			state.image.element = image;
			state.image.dataUrl = dataUrl;
			state.image.fileName = metadata.fileName || "";
			state.image.mimeType = metadata.mimeType || "";
			state.image.intrinsicWidth = image.naturalWidth || image.width || Number(metadata.width) || 0;
			state.image.intrinsicHeight = image.naturalHeight || image.height || Number(metadata.height) || 0;
			resolve(image);
		};
		image.onerror = () => reject(new Error(`Could not decode image ${metadata.fileName || ""}`.trim()));
		image.src = dataUrl;
	});
}

function clearImageSourceState() {
	if (state.image.objectUrl) {
		URL.revokeObjectURL(state.image.objectUrl);
	}
	state.image = createEmptyImageState();
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
		junctionData.crosswalkLength,
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

function catmullRom(p0, p1, p2, p3, t) {
	const t2 = t * t;
	const t3 = t2 * t;
	return {
		x: 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
		y: 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3),
		z: 0.5 * ((2 * p1.z) + (-p0.z + p2.z) * t + (2 * p0.z - 5 * p1.z + 4 * p2.z - p3.z) * t2 + (-p0.z + 3 * p1.z - 3 * p2.z + p3.z) * t3),
	};
}

function magnitude(a, b) {
	const dx = b.x - a.x;
	const dy = b.y - a.y;
	const dz = b.z - a.z;
	return Math.sqrt((dx * dx) + (dy * dy) + (dz * dz));
}

function samplePositions(positions, closedCurve, sampleStep = SAMPLE_STEP_STUDS) {
	if (positions.length < 2) {
		return positions.slice();
	}

	let closed = closedCurve;
	if (closed && positions.length < 3) {
		closed = false;
	}

	const samples = [];
	const step = Math.max(Number(sampleStep) || SAMPLE_STEP_STUDS, 1);

	if (closed) {
		const count = positions.length;
		for (let i = 0; i < count; i += 1) {
			const p0 = positions[(i - 1 + count) % count];
			const p1 = positions[i];
			const p2 = positions[(i + 1) % count];
			const p3 = positions[(i + 2) % count];
			const segmentLength = magnitude(p1, p2);
			const subdivisions = Math.max(2, Math.floor(segmentLength / step));
			for (let s = 0; s < subdivisions; s += 1) {
				samples.push(catmullRom(p0, p1, p2, p3, s / subdivisions));
			}
		}
		if (samples.length > 1) {
			samples.push({ ...samples[0] });
		}
	} else {
		for (let i = 0; i < positions.length - 1; i += 1) {
			const p0 = positions[Math.max(0, i - 1)];
			const p1 = positions[i];
			const p2 = positions[i + 1];
			const p3 = positions[Math.min(positions.length - 1, i + 2)];
			const segmentLength = magnitude(p1, p2);
			const subdivisions = Math.max(2, Math.floor(segmentLength / step));
			for (let s = 0; s < subdivisions; s += 1) {
				samples.push(catmullRom(p0, p1, p2, p3, s / subdivisions));
			}
		}
		samples.push({ ...positions[positions.length - 1] });
	}

	return samples;
}

function clonePoint(point) {
	return { x: point.x, y: point.y ?? 0, z: point.z };
}

function makePoint(x, z, y = 0) {
	return { x, y, z };
}

function lerpPoint(a, b, alpha) {
	return makePoint(
		a.x + ((b.x - a.x) * alpha),
		a.z + ((b.z - a.z) * alpha),
		(a.y ?? 0) + ((((b.y ?? 0) - (a.y ?? 0)) * alpha)),
	);
}

function distanceXZ(a, b) {
	return Math.hypot(a.x - b.x, a.z - b.z);
}

function horizontalUnit(vector) {
	const length = Math.hypot(vector.x, vector.z);
	if (length < 1e-4) {
		return null;
	}
	return { x: vector.x / length, z: vector.z / length };
}

function roadRightFromTangent(tangent) {
	const length = Math.hypot(tangent.x, tangent.z);
	if (length < 1e-4) {
		return { x: 1, z: 0 };
	}
	return { x: tangent.z / length, z: -tangent.x / length };
}

function add2D(a, b) {
	return { x: a.x + b.x, z: a.z + b.z };
}

function subtract2D(a, b) {
	return { x: a.x - b.x, z: a.z - b.z };
}

function scale2D(vector, scalar) {
	return { x: vector.x * scalar, z: vector.z * scalar };
}

function dot2D(a, b) {
	return (a.x * b.x) + (a.z * b.z);
}

function cross2D(a, b) {
	return (a.x * b.z) - (a.z * b.x);
}

function lineIntersectionXZ(a, dirA, b, dirB) {
	const denom = cross2D(dirA, dirB);
	if (Math.abs(denom) < 1e-5) {
		return null;
	}

	const dx = b.x - a.x;
	const dz = b.z - a.z;
	const t = ((dx * dirB.z) - (dz * dirB.x)) / denom;
	return makePoint(a.x + (dirA.x * t), a.z + (dirA.z * t), a.y ?? 0);
}

function circleCenterXZ(a, b, c) {
	const ax = a.x;
	const az = a.z;
	const bx = b.x;
	const bz = b.z;
	const cx = c.x;
	const cz = c.z;
	const denom = 2 * ((ax * (bz - cz)) + (bx * (cz - az)) + (cx * (az - bz)));
	if (Math.abs(denom) < 1e-4) {
		return null;
	}

	const a2 = (ax * ax) + (az * az);
	const b2 = (bx * bx) + (bz * bz);
	const c2 = (cx * cx) + (cz * cz);
	const ux = ((a2 * (bz - cz)) + (b2 * (cz - az)) + (c2 * (az - bz))) / denom;
	const uz = ((a2 * (cx - bx)) + (b2 * (ax - cx)) + (c2 * (bx - ax))) / denom;
	return makePoint(ux, uz, b.y ?? 0);
}

function sampleLoopIsClosed(samples) {
	if (samples.length < 3) {
		return false;
	}
	const first = samples[0];
	const last = samples[samples.length - 1];
	return distanceXZ(first, last) <= 0.05 && Math.abs((first.y ?? 0) - (last.y ?? 0)) <= 0.05;
}

function polylineLength(points, closedLoop) {
	const count = points.length;
	if (count < 2) {
		return 0;
	}

	const segmentCount = closedLoop ? count : count - 1;
	let total = 0;
	for (let index = 0; index < segmentCount; index += 1) {
		const nextIndex = closedLoop ? ((index + 1) % count) : (index + 1);
		total += magnitude(points[index], points[nextIndex]);
	}
	return total;
}

function samplePolylineAtFraction(points, closedLoop, fraction) {
	const count = points.length;
	if (count === 0) {
		return makePoint(0, 0);
	}
	if (count === 1) {
		return clonePoint(points[0]);
	}

	const totalLength = polylineLength(points, closedLoop);
	if (totalLength <= 1e-4) {
		return clonePoint(points[0]);
	}

	let target = Math.min(1, Math.max(0, fraction)) * totalLength;
	if (closedLoop) {
		target %= totalLength;
	} else if (target <= 0) {
		return clonePoint(points[0]);
	} else if (target >= totalLength) {
		return clonePoint(points[count - 1]);
	}

	let traveled = 0;
	const segmentCount = closedLoop ? count : count - 1;
	for (let index = 0; index < segmentCount; index += 1) {
		const nextIndex = closedLoop ? ((index + 1) % count) : (index + 1);
		const a = points[index];
		const b = points[nextIndex];
		const segmentLength = magnitude(a, b);
		if (segmentLength > 1e-4) {
			if ((traveled + segmentLength) >= target) {
				return lerpPoint(a, b, (target - traveled) / segmentLength);
			}
			traveled += segmentLength;
		}
	}

	return clonePoint(closedLoop ? points[0] : points[count - 1]);
}

function sampleSmoothedCurveControls(points, closedLoop, sampleStep) {
	const count = points.length;
	if (count < 3) {
		return points.map(clonePoint);
	}

	const smoothed = [];
	const appendPoint = (point) => {
		const last = smoothed[smoothed.length - 1];
		if (!last || magnitude(point, last) > 1e-4) {
			smoothed.push(clonePoint(point));
		}
	};

	const segmentCount = closedLoop ? count : count - 1;
	for (let index = 0; index < segmentCount; index += 1) {
		const p0 = closedLoop
			? points[(index - 1 + count) % count]
			: points[Math.max(0, index - 1)];
		const p1 = points[index];
		const p2 = points[(index + 1) % count] || points[index + 1];
		const p3 = closedLoop
			? points[(index + 2) % count]
			: points[Math.min(count - 1, index + 2)];
		const segmentLength = magnitude(p1, p2);
		const subdivisions = Math.max(2, Math.ceil(segmentLength / sampleStep));
		for (let step = 0; step < subdivisions; step += 1) {
			appendPoint(catmullRom(p0, p1, p2, p3, step / subdivisions));
		}
	}

	if (!closedLoop) {
		appendPoint(points[count - 1]);
	}

	return smoothed.length >= count ? smoothed : points.map(clonePoint);
}

function resamplePolylineControls(points, closedLoop, targetCount) {
	const roundedTarget = Math.floor(targetCount);
	if (roundedTarget <= 0 || points.length === 0) {
		return [];
	}
	if (points.length === 1) {
		return [clonePoint(points[0])];
	}

	const count = Math.max(closedLoop ? 3 : 2, roundedTarget);
	const resampled = [];
	for (let index = 0; index < count; index += 1) {
		const fraction = closedLoop
			? (index / count)
			: (count > 1 ? (index / (count - 1)) : 0);
		resampled[index] = samplePolylineAtFraction(points, closedLoop, fraction);
	}
	return resampled;
}

function fairEdgeCurveControls(points, closedLoop, sampleStep) {
	const length = polylineLength(points, closedLoop);
	let targetCount;
	if (length > 1e-4) {
		targetCount = closedLoop ? Math.ceil(length / sampleStep) : (Math.ceil(length / sampleStep) + 1);
		targetCount = Math.max(points.length, targetCount);
	} else {
		targetCount = points.length;
	}

	let relaxed = resamplePolylineControls(points, closedLoop, targetCount);
	for (let pass = 0; pass < ROAD_EDGE_CURVE_FAIR_PASSES; pass += 1) {
		const count = relaxed.length;
		if (count < 3) {
			return relaxed;
		}

		const nextPoints = [];
		for (let index = 0; index < count; index += 1) {
			if (closedLoop || (index > 0 && index < count - 1)) {
				const prevIndex = index > 0 ? index - 1 : count - 1;
				const nextIndex = index < count - 1 ? index + 1 : 0;
				const average = makePoint(
					(relaxed[prevIndex].x + relaxed[nextIndex].x) * 0.5,
					(relaxed[prevIndex].z + relaxed[nextIndex].z) * 0.5,
					((relaxed[prevIndex].y ?? 0) + (relaxed[nextIndex].y ?? 0)) * 0.5,
				);
				nextPoints[index] = lerpPoint(relaxed[index], average, ROAD_EDGE_CURVE_FAIR_ALPHA);
			} else {
				nextPoints[index] = clonePoint(relaxed[index]);
			}
		}
		relaxed = resamplePolylineControls(nextPoints, closedLoop, targetCount);
	}

	return sampleSmoothedCurveControls(relaxed, closedLoop, sampleStep);
}

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

function segmentCircleIntersections(a, b, center, radius) {
	const dx = b.x - a.x;
	const dz = b.z - a.z;
	const fx = a.x - center.x;
	const fz = a.z - center.z;
	const aa = (dx * dx) + (dz * dz);
	if (aa <= 1e-6) {
		return [];
	}

	const bb = 2 * ((fx * dx) + (fz * dz));
	const cc = (fx * fx) + (fz * fz) - (radius * radius);
	const discriminant = (bb * bb) - (4 * aa * cc);
	if (discriminant < -1e-6) {
		return [];
	}

	const root = Math.sqrt(Math.max(0, discriminant));
	return [(-bb - root) / (2 * aa), (-bb + root) / (2 * aa)]
		.filter((t) => t > 1e-4 && t < 1 - 1e-4);
}

function interpolateSegmentPoint(a, b, t) {
	return makePoint(
		a.x + ((b.x - a.x) * t),
		a.z + ((b.z - a.z) * t),
		(a.y ?? 0) + ((((b.y ?? 0) - (a.y ?? 0)) * t)),
	);
}

function cloneJunctionForPreview(junction) {
	const radius = sanitizeJunctionRadius(junction.radius);
	return {
		id: junction.id,
		name: junction.name,
		center: makePoint(junction.x, junction.z, junction.y ?? 0),
		radius,
		blendRadius: radius,
		crosswalkLength: sanitizeJunctionCrosswalkLength(junction.crosswalkLength),
		subdivisions: sanitizeJunctionSubdivisions(junction.subdivisions),
		portals: [],
		chains: new Set(),
	};
}

function junctionContainingPoint(point, junctions) {
	let best = null;
	let bestDistance = Infinity;
	for (const junction of junctions) {
		const distance = distanceXZ(point, junction.center);
		if (distance <= junction.radius - 1e-3 && distance < bestDistance) {
			best = junction;
			bestDistance = distance;
		}
	}
	return best;
}

function junctionTouchingPoint(point, junctions) {
	let best = null;
	let bestDistance = Infinity;
	for (const junction of junctions) {
		const distance = distanceXZ(point, junction.center);
		if (distance <= junction.radius + JUNCTION_VERTEX_EPSILON && distance < bestDistance) {
			best = junction;
			bestDistance = distance;
		}
	}
	return best;
}

function intervalOutsideJunctions(a, b, junctions) {
	const midpoint = lerpPoint(a, b, 0.5);
	return !junctionContainingPoint(midpoint, junctions);
}

function addPortalForChain(junction, chain, boundaryPoint, outsidePoint) {
	if (!junction || !chain || !outsidePoint) {
		return;
	}

	const tangent = horizontalUnit(subtract2D(outsidePoint, boundaryPoint))
		|| horizontalUnit(subtract2D(boundaryPoint, junction.center))
		|| { x: 0, z: 1 };
	const right = roadRightFromTangent(tangent);
	const halfWidth = sanitizeRoadWidth(chain.width) * 0.5;
	const portal = {
		junction,
		chain,
		boundaryPoint: clonePoint(boundaryPoint),
		outsidePoint: clonePoint(outsidePoint),
		point: clonePoint(boundaryPoint),
		tangent,
		halfWidth,
		left: makePoint(boundaryPoint.x - (right.x * halfWidth), boundaryPoint.z - (right.z * halfWidth), boundaryPoint.y ?? 0),
		right: makePoint(boundaryPoint.x + (right.x * halfWidth), boundaryPoint.z + (right.z * halfWidth), boundaryPoint.y ?? 0),
	};
	junction.portals.push(portal);
	junction.chains.add(chain);
}

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

function junctionCoreBoundaryLimit(junction) {
	const center = getJunctionMeshCenter(junction);
	let limit = Math.max(sanitizeJunctionCrosswalkLength(junction.crosswalkLength) * 2, JUNCTION_RADIUS_MIN);
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
	const portals = sortedJunctionPortals(junction);
	if (portals.length < 2) {
		return [];
	}

	const boundary = [];
	for (let index = 0; index < portals.length; index += 1) {
		const portal = portals[index];
		const nextPortal = portals[(index + 1) % portals.length];
		const right = roadRightFromTangent(portal.tangent);
		appendOrderedJunctionPoint(boundary, makePoint(
			portal.point.x + (right.x * (portal.halfWidth ?? 0)),
			portal.point.z + (right.z * (portal.halfWidth ?? 0)),
			portal.point.y ?? 0,
		));
		appendOrderedJunctionPoint(boundary, makePoint(
			portal.point.x - (right.x * (portal.halfWidth ?? 0)),
			portal.point.z - (right.z * (portal.halfWidth ?? 0)),
			portal.point.y ?? 0,
		));

		if (portal.coreLeft && nextPortal.coreRight) {
			appendOrderedJunctionPoint(boundary, portal.coreLeft);
			appendOrderedJunctionPoint(boundary, nextPortal.coreRight);
		}
	}

	return finalizeOrderedJunctionBoundary(boundary);
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

	const crosswalkLength = sanitizeJunctionCrosswalkLength(junction.crosswalkLength);
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
	const point = makePoint(
		corePoint.x + (portal.tangent.x * crosswalkLength),
		corePoint.z + (portal.tangent.z * crosswalkLength),
		corePoint.y ?? 0,
	);
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

function finalizeJunctionPortals(junctions) {
	for (const junction of junctions) {
		junction.coreBoundary = buildJunctionCoreBoundary(junction);
		for (const portal of junction.portals || []) {
			updatePortalGeometry(junction, portal);
		}
		junction.surfaceBoundary = buildJunctionSurfaceBoundary(junction);
		for (const portal of junction.portals || []) {
			trimChainEndpointToPortal(junction, portal);
		}
	}
}

function emitRoadRun(processedChains, sourceChain, runVertices) {
	const samples = runVertices.map((vertex) => clonePoint(vertex.point));
	if (samples.length < 2 || polylineLength(samples, false) <= 0.05) {
		return;
	}

	const chain = {
		...sourceChain,
		samples,
		closed: false,
		sections: null,
	};
	processedChains.push(chain);

	const first = runVertices[0];
	const second = runVertices[1];
	const last = runVertices[runVertices.length - 1];
	const beforeLast = runVertices[runVertices.length - 2];
	if (first.junction) {
		addPortalForChain(first.junction, chain, first.point, second.point);
	}
	if (last.junction) {
		addPortalForChain(last.junction, chain, last.point, beforeLast.point);
	}
}

function samplesWithClosedSeam(samples, closedLoop) {
	const result = samples.map(clonePoint);
	if (closedLoop && result.length > 1 && distanceXZ(result[0], result[result.length - 1]) > 0.05) {
		result.push(clonePoint(result[0]));
	}
	return result;
}

function closestPointOnSegmentXZ(a, b, point) {
	const dx = b.x - a.x;
	const dz = b.z - a.z;
	const lengthSq = (dx * dx) + (dz * dz);
	if (lengthSq <= 1e-6) {
		return { t: 0, point: clonePoint(a), distance: distanceXZ(a, point) };
	}

	const rawT = (((point.x - a.x) * dx) + ((point.z - a.z) * dz)) / lengthSq;
	const t = Math.min(1, Math.max(0, rawT));
	const projected = interpolateSegmentPoint(a, b, t);
	return { t, point: projected, distance: distanceXZ(projected, point) };
}

function buildChainPath(chain) {
	const closed = chain.closed || sampleLoopIsClosed(chain.samples);
	const samples = getUniqueRoadSamples(chain.samples, closed);
	if (samples.length < (closed ? 3 : 2)) {
		return null;
	}

	const distances = [0];
	let totalLength = 0;
	for (let index = 0; index < samples.length - 1; index += 1) {
		totalLength += distanceXZ(samples[index], samples[index + 1]);
		distances[index + 1] = totalLength;
	}
	if (closed) {
		totalLength += distanceXZ(samples[samples.length - 1], samples[0]);
	}
	if (totalLength <= 1e-4) {
		return null;
	}

	return { chain, samples, closed, distances, totalLength };
}

function pathSegmentInfo(path, segmentIndex) {
	const nextIndex = (segmentIndex + 1) % path.samples.length;
	const startDistance = path.distances[segmentIndex];
	const endDistance = path.closed && segmentIndex === path.samples.length - 1
		? path.totalLength
		: path.distances[nextIndex];
	return {
		a: path.samples[segmentIndex],
		b: path.samples[nextIndex],
		startDistance,
		endDistance,
	};
}

function pathPointAtDistance(path, distance) {
	let d = path.closed
		? ((distance % path.totalLength) + path.totalLength) % path.totalLength
		: Math.min(path.totalLength, Math.max(0, distance));
	const segmentCount = path.closed ? path.samples.length : path.samples.length - 1;
	for (let index = 0; index < segmentCount; index += 1) {
		const segment = pathSegmentInfo(path, index);
		if (d <= segment.endDistance || index === segmentCount - 1) {
			const segmentLength = Math.max(segment.endDistance - segment.startDistance, 1e-6);
			return interpolateSegmentPoint(segment.a, segment.b, (d - segment.startDistance) / segmentLength);
		}
	}
	return clonePoint(path.samples[path.samples.length - 1]);
}

function collectPathSamples(path, startDistance, endDistance) {
	const result = [];
	let effectiveEnd = endDistance;
	if (path.closed && effectiveEnd <= startDistance) {
		effectiveEnd += path.totalLength;
	}

	const appendPoint = (point) => {
		if (result.length === 0 || distanceXZ(result[result.length - 1], point) > 0.05) {
			result.push(clonePoint(point));
		}
	};

	appendPoint(pathPointAtDistance(path, startDistance));
	const passes = path.closed ? 1 : 0;
	for (let pass = 0; pass <= passes; pass += 1) {
		const offset = pass * path.totalLength;
		for (let index = 0; index < path.samples.length; index += 1) {
			const d = path.distances[index] + offset;
			if (d > startDistance + 0.05 && d < effectiveEnd - 0.05) {
				appendPoint(path.samples[index]);
			}
		}
	}
	appendPoint(pathPointAtDistance(path, effectiveEnd));
	return result;
}

function pathDistanceForSegment(path, segmentIndex, t) {
	const segment = pathSegmentInfo(path, segmentIndex);
	return segment.startDistance + ((segment.endDistance - segment.startDistance) * t);
}

function closestPathHit(path, point) {
	let best = null;
	const segmentCount = path.closed ? path.samples.length : path.samples.length - 1;
	for (let index = 0; index < segmentCount; index += 1) {
		const segment = pathSegmentInfo(path, index);
		const projection = closestPointOnSegmentXZ(segment.a, segment.b, point);
		if (!best || projection.distance < best.distance) {
			best = {
				path,
				chain: path.chain,
				segment: index,
				t: projection.t,
				point: projection.point,
				distance: projection.distance,
				pathDistance: pathDistanceForSegment(path, index, projection.t),
				lineDir: horizontalUnit(subtract2D(segment.b, segment.a)) || { x: 0, z: 1 },
			};
		}
	}
	return best;
}

function collectExplicitJunctionHits(paths, junctions) {
	const hitsByPath = new Map(paths.map((path) => [path, []]));
	for (const junction of junctions) {
		junction.hits = [];
		junction.portals = [];
		junction.chains = new Set();
		for (const path of paths) {
			const hit = closestPathHit(path, junction.center);
			if (hit && hit.distance <= junction.radius + JUNCTION_VERTEX_EPSILON) {
				hit.junction = junction;
				junction.hits.push(hit);
				hitsByPath.get(path).push(hit);
				junction.chains.add(path.chain);
			}
		}
	}
	return hitsByPath;
}

function computeExplicitJunctionCenter(junction) {
	const hits = junction.hits ?? [];
	if (hits.length === 0) {
		return junction.center;
	}

	const candidates = [];
	for (let i = 0; i < hits.length; i += 1) {
		for (let j = i + 1; j < hits.length; j += 1) {
			const a = hits[i];
			const b = hits[j];
			const intersection = lineIntersectionXZ(a.point, a.lineDir, b.point, b.lineDir);
			if (!intersection) {
				continue;
			}
			candidates.push(intersection);
		}
	}

	const source = candidates.length > 0 ? candidates : hits.map((hit) => hit.point);
	const summed = source.reduce((accumulator, point) => ({
		x: accumulator.x + point.x,
		z: accumulator.z + point.z,
		y: accumulator.y + (point.y ?? 0),
	}), { x: 0, z: 0, y: 0 });
	return makePoint(summed.x / source.length, summed.z / source.length, summed.y / source.length);
}

function finalizeExplicitJunctionCenters(junctions) {
	for (const junction of junctions) {
		junction.intersectionCenter = computeExplicitJunctionCenter(junction);
		for (const hit of junction.hits ?? []) {
			const refined = closestPathHit(hit.path, junction.intersectionCenter);
			if (refined) {
				hit.segment = refined.segment;
				hit.t = refined.t;
				hit.point = refined.point;
				hit.distance = refined.distance;
				hit.pathDistance = refined.pathDistance;
				hit.lineDir = refined.lineDir;
			}
		}
	}
}

function splitChainByExplicitJunctions(chain, junctions, processedChains) {
	const closedLoop = chain.closed || sampleLoopIsClosed(chain.samples);
	const baseSamples = getUniqueRoadSamples(chain.samples, closedLoop);
	if (baseSamples.length < (closedLoop ? 3 : 2) || junctions.length === 0) {
		processedChains.push({ ...chain, samples: samplesWithClosedSeam(baseSamples, closedLoop), closed: closedLoop });
		return;
	}

	const vertices = [];
	const appendVertex = (vertex) => {
		const previous = vertices[vertices.length - 1];
		if (
			previous
			&& distanceXZ(previous.point, vertex.point) <= 0.01
			&& previous.junction === vertex.junction
		) {
			return;
		}
		vertices.push(vertex);
	};

	const segmentCount = closedLoop ? baseSamples.length : baseSamples.length - 1;
	appendVertex({ point: baseSamples[0], junction: junctionTouchingPoint(baseSamples[0], junctions) });
	for (let index = 0; index < segmentCount; index += 1) {
		const nextIndex = (index + 1) % baseSamples.length;
		const a = baseSamples[index];
		const b = baseSamples[nextIndex];
		const cuts = [];
		for (const junction of junctions) {
			for (const t of segmentCircleIntersections(a, b, junction.center, junction.radius)) {
				cuts.push({
					t,
					point: interpolateSegmentPoint(a, b, t),
					junction,
				});
			}
		}
		cuts.sort((left, right) => left.t - right.t);
		for (const cut of cuts) {
			const duplicate = vertices.some((vertex) => distanceXZ(vertex.point, cut.point) <= 0.01 && vertex.junction === cut.junction);
			if (!duplicate) {
				appendVertex({ point: cut.point, junction: cut.junction });
			}
		}
		if (!closedLoop || nextIndex !== 0) {
			appendVertex({ point: b, junction: junctionTouchingPoint(b, junctions) });
		}
	}

	if (vertices.length < 2) {
		return;
	}

	if (!closedLoop) {
		let run = [];
		for (let index = 0; index < vertices.length - 1; index += 1) {
			const outside = intervalOutsideJunctions(vertices[index].point, vertices[index + 1].point, junctions);
			if (outside) {
				if (run.length === 0) {
					run.push(vertices[index]);
				}
				run.push(vertices[index + 1]);
			} else if (run.length > 0) {
				emitRoadRun(processedChains, chain, run);
				run = [];
			}
		}
		if (run.length > 0) {
			emitRoadRun(processedChains, chain, run);
		}
		return;
	}

	const intervalCount = vertices.length;
	const outsideIntervals = [];
	for (let index = 0; index < intervalCount; index += 1) {
		const nextIndex = (index + 1) % intervalCount;
		outsideIntervals[index] = intervalOutsideJunctions(vertices[index].point, vertices[nextIndex].point, junctions);
	}

	if (outsideIntervals.every(Boolean)) {
		processedChains.push({ ...chain, samples: samplesWithClosedSeam(baseSamples, true), closed: true });
		return;
	}

	for (let start = 0; start < intervalCount; start += 1) {
		const previous = (start - 1 + intervalCount) % intervalCount;
		if (!outsideIntervals[start] || outsideIntervals[previous]) {
			continue;
		}

		const run = [vertices[start]];
		let index = start;
		while (outsideIntervals[index]) {
			const nextIndex = (index + 1) % intervalCount;
			run.push(vertices[nextIndex]);
			index = nextIndex;
			if (index === start) {
				break;
			}
		}
		emitRoadRun(processedChains, chain, run);
	}
}

function emitExplicitRoadRun(processedChains, sourceChain, samples, startPortal, endPortal) {
	if (samples.length < 2 || polylineLength(samples, false) <= 0.05) {
		return;
	}

	const chain = {
		...sourceChain,
		samples: samples.map(clonePoint),
		closed: false,
		sections: null,
	};
	processedChains.push(chain);

	if (startPortal) {
		addPortalForChain(startPortal.junction, chain, startPortal.point, chain.samples[0]);
	}
	if (endPortal) {
		addPortalForChain(endPortal.junction, chain, endPortal.point, chain.samples[chain.samples.length - 1]);
	}
}

function portalRecordForHit(hit, distance) {
	return {
		junction: hit.junction,
		point: hit.point,
		distance,
	};
}

function splitOpenPathByExplicitHits(processedChains, path, hits) {
	hits.sort((a, b) => a.pathDistance - b.pathDistance);
	let cursor = 0;
	let startPortal = null;
	for (const hit of hits) {
		const crosswalkLength = sanitizeJunctionCrosswalkLength(hit.junction.crosswalkLength);
		const beforeDistance = Math.max(0, hit.pathDistance - crosswalkLength);
		const afterDistance = Math.min(path.totalLength, hit.pathDistance + crosswalkLength);
		if (beforeDistance > cursor + 0.05) {
			emitExplicitRoadRun(
				processedChains,
				path.chain,
				collectPathSamples(path, cursor, beforeDistance),
				startPortal,
				portalRecordForHit(hit, beforeDistance),
			);
		}
		cursor = Math.max(cursor, afterDistance);
		startPortal = cursor < path.totalLength - 0.05 ? portalRecordForHit(hit, cursor) : null;
	}

	if (cursor < path.totalLength - 0.05) {
		emitExplicitRoadRun(processedChains, path.chain, collectPathSamples(path, cursor, path.totalLength), startPortal, null);
	}
}

function splitClosedPathByExplicitHits(processedChains, path, hits) {
	hits.sort((a, b) => a.pathDistance - b.pathDistance);
	if (hits.length === 0) {
		processedChains.push({ ...path.chain, samples: samplesWithClosedSeam(path.samples, true), closed: true });
		return;
	}

	for (let index = 0; index < hits.length; index += 1) {
		const hit = hits[index];
		const nextHit = hits[(index + 1) % hits.length];
		const hitCrosswalk = sanitizeJunctionCrosswalkLength(hit.junction.crosswalkLength);
		const nextCrosswalk = sanitizeJunctionCrosswalkLength(nextHit.junction.crosswalkLength);
		const startDistance = (hit.pathDistance + hitCrosswalk) % path.totalLength;
		const endDistance = (nextHit.pathDistance - nextCrosswalk + path.totalLength) % path.totalLength;
		let effectiveEnd = endDistance;
		if (effectiveEnd <= startDistance) {
			effectiveEnd += path.totalLength;
		}
		if (effectiveEnd > startDistance + 0.05) {
			emitExplicitRoadRun(
				processedChains,
				path.chain,
				collectPathSamples(path, startDistance, effectiveEnd),
				portalRecordForHit(hit, startDistance),
				portalRecordForHit(nextHit, effectiveEnd),
			);
		}
	}
}

function splitPathByExplicitJunctions(processedChains, path, hits) {
	if (!hits || hits.length === 0) {
		processedChains.push({ ...path.chain, samples: samplesWithClosedSeam(path.samples, path.closed), closed: path.closed });
		return;
	}

	if (path.closed) {
		splitClosedPathByExplicitHits(processedChains, path, hits);
	} else {
		splitOpenPathByExplicitHits(processedChains, path, hits);
	}
}

function applyExplicitJunctionsToChains(chains, junctions) {
	const processedChains = [];
	const paths = chains.map(buildChainPath).filter(Boolean);
	const hitsByPath = collectExplicitJunctionHits(paths, junctions);
	finalizeExplicitJunctionCenters(junctions);
	for (const path of paths) {
		splitPathByExplicitJunctions(processedChains, path, hitsByPath.get(path));
	}
	finalizeJunctionPortals(junctions);
	return processedChains;
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
	if (junction.surfaceBoundary && junction.surfaceBoundary.length >= 3) {
		return [];
	}

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

function maxRoadWidthForMembers(members) {
	let width = null;
	for (const member of members) {
		if (member.chain) {
			width = Math.max(width ?? 0, sanitizeRoadWidth(member.chain.width));
		}
	}
	return width ?? ROAD_WIDTH_DEFAULT;
}

function collectEndpointJunctions(chains) {
	const endpoints = [];
	for (const chain of chains) {
		if (!chain.closed && chain.samples.length >= 2) {
			endpoints.push({ chain, index: 0, pos: chain.samples[0] });
			endpoints.push({ chain, index: chain.samples.length - 1, pos: chain.samples[chain.samples.length - 1] });
		}
	}

	const clusters = [];
	for (const endpoint of endpoints) {
		let placed = false;
		const endpointWidth = sanitizeRoadWidth(endpoint.chain.width);
		for (const cluster of clusters) {
			const weldDistance = Math.max(ENDPOINT_WELD_DISTANCE, Math.max(cluster.width, endpointWidth) * 0.8);
			if (distanceXZ(cluster.center, endpoint.pos) <= weldDistance) {
				cluster.members.push(endpoint);
				cluster.width = Math.max(cluster.width, endpointWidth);
				const summed = cluster.members.reduce((accumulator, member) => ({
					x: accumulator.x + member.pos.x,
					z: accumulator.z + member.pos.z,
				}), { x: 0, z: 0 });
				cluster.center = makePoint(summed.x / cluster.members.length, summed.z / cluster.members.length);
				placed = true;
				break;
			}
		}
		if (!placed) {
			clusters.push({ center: clonePoint(endpoint.pos), members: [endpoint], width: endpointWidth });
		}
	}

	return clusters
		.filter((cluster) => cluster.members.length >= 2)
		.map((cluster) => ({
			center: cluster.center,
			members: cluster.members,
		}));
}

function segmentIntersection2D(a, b, c, d) {
	const cross2 = (u, v) => (u.x * v.z) - (u.z * v.x);
	const p = { x: a.x, z: a.z };
	const r = { x: b.x - a.x, z: b.z - a.z };
	const q = { x: c.x, z: c.z };
	const s = { x: d.x - c.x, z: d.z - c.z };
	const denom = cross2(r, s);
	if (Math.abs(denom) < 1e-6) {
		return null;
	}

	const qp = { x: q.x - p.x, z: q.z - p.z };
	let t = cross2(qp, s) / denom;
	let u = cross2(qp, r) / denom;
	const endpointEpsilon = 1e-4;
	if (t < -endpointEpsilon || t > (1 + endpointEpsilon) || u < -endpointEpsilon || u > (1 + endpointEpsilon)) {
		return null;
	}
	t = Math.min(1, Math.max(0, t));
	u = Math.min(1, Math.max(0, u));
	return {
		position: makePoint(p.x + (r.x * t), p.z + (r.z * t)),
		t,
		u,
	};
}

function collectCrossIntersections(chains) {
	const junctions = [];
	for (let chainIndex = 0; chainIndex < chains.length; chainIndex += 1) {
		const aChain = chains[chainIndex];
		for (let otherIndex = chainIndex + 1; otherIndex < chains.length; otherIndex += 1) {
			const bChain = chains[otherIndex];
			for (let aSegment = 0; aSegment < aChain.samples.length - 1; aSegment += 1) {
				const a1 = aChain.samples[aSegment];
				const a2 = aChain.samples[aSegment + 1];
				for (let bSegment = 0; bSegment < bChain.samples.length - 1; bSegment += 1) {
					const b1 = bChain.samples[bSegment];
					const b2 = bChain.samples[bSegment + 1];
					const hit = segmentIntersection2D(a1, a2, b1, b2);
					if (hit) {
						junctions.push({
							center: hit.position,
							members: [
								{ chain: aChain, segment: aSegment, t: hit.t, pos: hit.position },
								{ chain: bChain, segment: bSegment, t: hit.u, pos: hit.position },
							],
						});
					}
				}
			}
		}
	}
	return junctions;
}

function mergeJunctions(rawJunctions) {
	const clusters = [];
	for (const junction of rawJunctions) {
		let placed = false;
		const junctionWidth = maxRoadWidthForMembers(junction.members);
		for (const cluster of clusters) {
			const mergeDistance = Math.max(cluster.width, junctionWidth) * INTERSECTION_MERGE_SCALE;
			if (distanceXZ(cluster.center, junction.center) <= mergeDistance) {
				cluster.members.push(...junction.members);
				cluster.width = Math.max(cluster.width, junctionWidth);
				const summed = cluster.members.reduce((accumulator, member) => ({
					x: accumulator.x + (member.pos?.x ?? junction.center.x),
					z: accumulator.z + (member.pos?.z ?? junction.center.z),
				}), { x: 0, z: 0 });
				cluster.center = makePoint(summed.x / cluster.members.length, summed.z / cluster.members.length);
				placed = true;
				break;
			}
		}
		if (!placed) {
			clusters.push({
				center: clonePoint(junction.center),
				members: [...junction.members],
				width: junctionWidth,
			});
		}
	}

	return clusters.map((cluster) => ({
		center: cluster.center,
		members: cluster.members,
		chains: new Set(cluster.members.map((member) => member.chain).filter(Boolean)),
		width: cluster.width,
		radius: cluster.width * INTERSECTION_RADIUS_SCALE,
		blendRadius: Math.max(cluster.width * INTERSECTION_BLEND_SCALE, (cluster.width * INTERSECTION_RADIUS_SCALE) + 0.05),
	}));
}

function addInsertForChain(insertsByChain, chain, segment, t, pos) {
	const inserts = insertsByChain.get(chain) || [];
	inserts.push({ segment, t, pos });
	insertsByChain.set(chain, inserts);
}

function applyJunctionsToChains(chains, junctions) {
	const insertsByChain = new Map();

	for (const junction of junctions) {
		for (const member of junction.members) {
			if (Number.isInteger(member.index)) {
				member.chain.samples[member.index] = clonePoint(junction.center);
			} else if (Number.isInteger(member.segment) && Number.isFinite(member.t)) {
				addInsertForChain(insertsByChain, member.chain, member.segment, member.t, clonePoint(junction.center));
			}
		}
	}

	for (const [chain, inserts] of insertsByChain.entries()) {
		inserts.sort((a, b) => {
			if (a.segment === b.segment) {
				return b.t - a.t;
			}
			return b.segment - a.segment;
		});

		for (const insert of inserts) {
			const before = chain.samples[insert.segment];
			const after = chain.samples[insert.segment + 1];
			if (before && after && distanceXZ(before, insert.pos) > 0.05 && distanceXZ(after, insert.pos) > 0.05) {
				chain.samples.splice(insert.segment + 1, 0, clonePoint(insert.pos));
			}
		}
	}

	for (const chain of chains) {
		for (let index = 0; index < chain.samples.length; index += 1) {
			const sample = chain.samples[index];
			let bestJunction = null;
			let bestDistance = Infinity;
			for (const junction of junctions) {
				if (!junction.chains.has(chain)) {
					continue;
				}
				const distance = distanceXZ(sample, junction.center);
				const blendRadius = junction.blendRadius ?? (junction.radius + 0.05);
				if (distance <= blendRadius && distance < bestDistance) {
					bestDistance = distance;
					bestJunction = junction;
				}
			}

			if (bestJunction) {
				let alpha;
				if (bestDistance <= bestJunction.radius) {
					alpha = 1;
				} else {
					const blendRadius = bestJunction.blendRadius ?? (bestJunction.radius + 0.05);
					alpha = 1 - ((bestDistance - bestJunction.radius) / Math.max(blendRadius - bestJunction.radius, 0.001));
				}
				chain.samples[index] = lerpPoint(sample, bestJunction.center, alpha);
			}
		}
	}
}

function computeMeshPreview() {
	const sourceChains = state.splines
		.filter((spline) => spline.points.length >= 2)
		.map((spline) => ({
			spline,
			points: spline.points.map(clonePoint),
			samples: samplePositions(spline.points.map(createVector), spline.closed, SAMPLE_STEP_STUDS),
			closed: spline.closed,
			width: spline.width,
		}));

	if (sourceChains.length === 0) {
		return { chains: [], junctions: [] };
	}

	const junctions = state.junctions
		.filter(junctionHasCurveConnections)
		.map(cloneJunctionForPreview);
	const chains = applyExplicitJunctionsToChains(sourceChains, junctions);

	for (const chain of chains) {
		chain.sections = buildRoadCrossSections(chain.samples, chain.width);
	}

	return { chains, junctions };
}

function getMeshPreview() {
	if (!state.meshPreviewEnabled) {
		return null;
	}
	if (!state.meshPreviewDirty && state.meshPreviewCache) {
		return state.meshPreviewCache;
	}
	state.meshPreviewCache = computeMeshPreview();
	state.meshPreviewDirty = false;
	return state.meshPreviewCache;
}

function worldToScreen(x, z) {
	return {
		x: ((x - state.cameraX) * state.zoom) + (elements.canvas.clientWidth * 0.5),
		y: ((state.cameraZ - z) * state.zoom) + (elements.canvas.clientHeight * 0.5),
	};
}

function screenToWorld(x, y) {
	return {
		x: ((x - (elements.canvas.clientWidth * 0.5)) / state.zoom) + state.cameraX,
		z: state.cameraZ - ((y - (elements.canvas.clientHeight * 0.5)) / state.zoom),
	};
}

function requestRender() {
	scheduleAutosave();
	if (renderQueued) {
		return;
	}
	renderQueued = true;
	window.requestAnimationFrame(() => {
		renderQueued = false;
		render();
	});
}

function resizeCanvas() {
	const dpr = window.devicePixelRatio || 1;
	const width = Math.max(1, Math.floor(elements.canvas.clientWidth * dpr));
	const height = Math.max(1, Math.floor(elements.canvas.clientHeight * dpr));
	if (elements.canvas.width !== width || elements.canvas.height !== height) {
		elements.canvas.width = width;
		elements.canvas.height = height;
	}
	ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
	requestRender();
}

function drawGrid() {
	const width = elements.canvas.clientWidth;
	const height = elements.canvas.clientHeight;
	const bounds = {
		left: screenToWorld(0, height).x,
		right: screenToWorld(width, 0).x,
		bottom: screenToWorld(0, height).z,
		top: screenToWorld(width, 0).z,
	};
	const minorStep = 25;
	const majorStep = 100;

	ctx.fillStyle = "#d5dfe1";
	ctx.fillRect(0, 0, width, height);

	for (let x = Math.floor(bounds.left / minorStep) * minorStep; x <= bounds.right; x += minorStep) {
		const screen = worldToScreen(x, 0).x;
		const major = Math.abs(x % majorStep) < 0.001;
		ctx.beginPath();
		ctx.strokeStyle = major ? "rgba(35, 49, 58, 0.18)" : "rgba(35, 49, 58, 0.08)";
		ctx.lineWidth = major ? 1.2 : 1;
		ctx.moveTo(screen, 0);
		ctx.lineTo(screen, height);
		ctx.stroke();
	}

	for (let z = Math.floor(bounds.bottom / minorStep) * minorStep; z <= bounds.top; z += minorStep) {
		const screen = worldToScreen(0, z).y;
		const major = Math.abs(z % majorStep) < 0.001;
		ctx.beginPath();
		ctx.strokeStyle = major ? "rgba(35, 49, 58, 0.18)" : "rgba(35, 49, 58, 0.08)";
		ctx.lineWidth = major ? 1.2 : 1;
		ctx.moveTo(0, screen);
		ctx.lineTo(width, screen);
		ctx.stroke();
	}

	const origin = worldToScreen(0, 0);
	ctx.beginPath();
	ctx.strokeStyle = "rgba(200, 91, 42, 0.35)";
	ctx.lineWidth = 1.5;
	ctx.moveTo(origin.x, 0);
	ctx.lineTo(origin.x, height);
	ctx.moveTo(0, origin.y);
	ctx.lineTo(width, origin.y);
	ctx.stroke();
}

function drawTraceImage() {
	const image = state.image.element;
	if (!image) {
		return;
	}
	const center = worldToScreen(state.image.offsetX, state.image.offsetZ);
	const width = image.width * state.image.scale * state.zoom;
	const height = image.height * state.image.scale * state.zoom;
	ctx.save();
	ctx.globalAlpha = Math.min(1, Math.max(0, state.image.opacity / 100));
	ctx.drawImage(image, center.x - (width * 0.5), center.y - (height * 0.5), width, height);
	ctx.restore();
}

function drawSplineRibbon(spline, active) {
	if (spline.points.length < 2) {
		return;
	}
	const samples = samplePositions(spline.points.map(createVector), spline.closed, SAMPLE_STEP_STUDS);
	if (samples.length < 2) {
		return;
	}

	ctx.save();
	ctx.beginPath();
	samples.forEach((sample, index) => {
		const screen = worldToScreen(sample.x, sample.z);
		if (index === 0) {
			ctx.moveTo(screen.x, screen.y);
		} else {
			ctx.lineTo(screen.x, screen.y);
		}
	});
	ctx.lineCap = "round";
	ctx.lineJoin = "round";
	ctx.strokeStyle = active ? "rgba(26, 33, 38, 0.95)" : "rgba(55, 67, 76, 0.55)";
	ctx.lineWidth = Math.max(2, spline.width * state.zoom);
	ctx.stroke();

	ctx.beginPath();
	samples.forEach((sample, index) => {
		const screen = worldToScreen(sample.x, sample.z);
		if (index === 0) {
			ctx.moveTo(screen.x, screen.y);
		} else {
			ctx.lineTo(screen.x, screen.y);
		}
	});
	ctx.lineCap = "round";
	ctx.lineJoin = "round";
	ctx.strokeStyle = active ? "rgba(235, 224, 207, 0.52)" : "rgba(236, 231, 222, 0.28)";
	ctx.lineWidth = Math.max(1.5, (spline.width * state.zoom) - 4);
	ctx.stroke();
	ctx.restore();
}

function drawMeshPreview() {
	const preview = getMeshPreview();
	if (!preview) {
		return;
	}

	ctx.save();

	for (const chain of preview.chains) {
		const sections = chain.sections;
		if (!sections) {
			continue;
		}

		for (let rowIndex = 0; rowIndex < sections.spanCount; rowIndex += 1) {
			const nextIndex = sections.closed ? ((rowIndex + 1) % sections.rowCount) : (rowIndex + 1);
			const leftA = worldToScreen(sections.left[rowIndex].x, sections.left[rowIndex].z);
			const leftB = worldToScreen(sections.left[nextIndex].x, sections.left[nextIndex].z);
			const rightB = worldToScreen(sections.right[nextIndex].x, sections.right[nextIndex].z);
			const rightA = worldToScreen(sections.right[rowIndex].x, sections.right[rowIndex].z);

			ctx.beginPath();
			ctx.moveTo(leftA.x, leftA.y);
			ctx.lineTo(leftB.x, leftB.y);
			ctx.lineTo(rightB.x, rightB.y);
			ctx.lineTo(rightA.x, rightA.y);
			ctx.closePath();
			ctx.fillStyle = "rgba(26, 33, 38, 0.9)";
			ctx.fill();
		}
	}

	for (const junction of preview.junctions) {
		for (const quad of buildJunctionConnectorQuads(junction)) {
			ctx.beginPath();
			quad.forEach((point, index) => {
				const screen = worldToScreen(point.x, point.z);
				if (index === 0) {
					ctx.moveTo(screen.x, screen.y);
				} else {
					ctx.lineTo(screen.x, screen.y);
				}
			});
			ctx.closePath();
			ctx.fillStyle = "rgba(26, 33, 38, 0.92)";
			ctx.fill();
		}

		const boundary = addJunctionPatchToMeshPreviewRows(junction);
		if (boundary.length < 3) {
			continue;
		}
		ctx.beginPath();
		boundary.forEach((point, index) => {
			const screen = worldToScreen(point.x, point.z);
			if (index === 0) {
				ctx.moveTo(screen.x, screen.y);
			} else {
				ctx.lineTo(screen.x, screen.y);
			}
		});
		ctx.closePath();
		ctx.fillStyle = "rgba(26, 33, 38, 0.92)";
		ctx.fill();
	}

	ctx.strokeStyle = "rgba(223, 238, 241, 0.3)";
	ctx.lineWidth = 1;

	for (const chain of preview.chains) {
		const sections = chain.sections;
		if (!sections) {
			continue;
		}

		const rows = [];
		for (let rowIndex = 0; rowIndex < sections.rowCount; rowIndex += 1) {
			rows[rowIndex] = buildLoftRowVertices(sections.left[rowIndex], sections.right[rowIndex], sections.widthSegments);
		}

		for (let rowIndex = 0; rowIndex < sections.rowCount; rowIndex += 1) {
			ctx.beginPath();
			for (let segment = 0; segment <= sections.widthSegments; segment += 1) {
				const vertex = worldToScreen(rows[rowIndex][segment].x, rows[rowIndex][segment].z);
				if (segment === 0) {
					ctx.moveTo(vertex.x, vertex.y);
				} else {
					ctx.lineTo(vertex.x, vertex.y);
				}
			}
			ctx.stroke();
		}

		for (let rowIndex = 0; rowIndex < sections.spanCount; rowIndex += 1) {
			const nextIndex = sections.closed ? ((rowIndex + 1) % sections.rowCount) : (rowIndex + 1);
			for (let segment = 0; segment <= sections.widthSegments; segment += 1) {
				const from = worldToScreen(rows[rowIndex][segment].x, rows[rowIndex][segment].z);
				const to = worldToScreen(rows[nextIndex][segment].x, rows[nextIndex][segment].z);
				ctx.beginPath();
				ctx.moveTo(from.x, from.y);
				ctx.lineTo(to.x, to.y);
				ctx.stroke();
			}

			for (let segment = 0; segment < sections.widthSegments; segment += 1) {
				const diagonalFrom = worldToScreen(rows[rowIndex][segment].x, rows[rowIndex][segment].z);
				const diagonalTo = worldToScreen(rows[nextIndex][segment + 1].x, rows[nextIndex][segment + 1].z);
				ctx.beginPath();
				ctx.moveTo(diagonalFrom.x, diagonalFrom.y);
				ctx.lineTo(diagonalTo.x, diagonalTo.y);
				ctx.stroke();
			}
		}
	}

	ctx.strokeStyle = "rgba(223, 238, 241, 0.28)";
	for (const junction of preview.junctions) {
		for (const quad of buildJunctionConnectorQuads(junction)) {
			ctx.beginPath();
			quad.forEach((point, index) => {
				const screen = worldToScreen(point.x, point.z);
				if (index === 0) {
					ctx.moveTo(screen.x, screen.y);
				} else {
					ctx.lineTo(screen.x, screen.y);
				}
			});
			ctx.closePath();
			ctx.stroke();

			const a = worldToScreen(quad[0].x, quad[0].z);
			const c = worldToScreen(quad[2].x, quad[2].z);
			ctx.beginPath();
			ctx.moveTo(a.x, a.y);
			ctx.lineTo(c.x, c.y);
			ctx.stroke();
		}

		const boundary = addJunctionPatchToMeshPreviewRows(junction);
		if (boundary.length < 2) {
			continue;
		}
		ctx.beginPath();
		boundary.forEach((point, index) => {
			const screen = worldToScreen(point.x, point.z);
			if (index === 0) {
				ctx.moveTo(screen.x, screen.y);
			} else {
				ctx.lineTo(screen.x, screen.y);
			}
		});
		ctx.closePath();
		ctx.stroke();
		const meshCenter = getJunctionMeshCenter(junction);
		const center = worldToScreen(meshCenter.x, meshCenter.z);
		for (const point of boundary) {
			const edge = worldToScreen(point.x, point.z);
			ctx.beginPath();
			ctx.moveTo(center.x, center.y);
			ctx.lineTo(edge.x, edge.y);
			ctx.stroke();
		}
	}

	ctx.restore();
}

function drawControlPolygon(spline, active) {
	if (spline.points.length === 0) {
		return;
	}

	ctx.save();
	if (spline.points.length >= 2) {
		ctx.beginPath();
		spline.points.forEach((point, index) => {
			const screen = worldToScreen(point.x, point.z);
			if (index === 0) {
				ctx.moveTo(screen.x, screen.y);
			} else {
				ctx.lineTo(screen.x, screen.y);
			}
		});
		if (spline.closed && spline.points.length >= 3) {
			const first = worldToScreen(spline.points[0].x, spline.points[0].z);
			ctx.lineTo(first.x, first.y);
		}
		ctx.setLineDash([6, 6]);
		ctx.strokeStyle = active ? "rgba(200, 91, 42, 0.95)" : "rgba(200, 91, 42, 0.45)";
		ctx.lineWidth = active ? 1.5 : 1;
		ctx.stroke();
		ctx.setLineDash([]);
	}

	spline.points.forEach((point, pointIndex) => {
		const screen = worldToScreen(point.x, point.z);
		const isSelected = state.selectedPoint
			&& state.selectedPoint.splineId === spline.id
			&& state.selectedPoint.pointIndex === pointIndex;

		ctx.beginPath();
		ctx.arc(screen.x, screen.y, isSelected ? 7 : 5.5, 0, Math.PI * 2);
		ctx.fillStyle = isSelected ? "#d6421a" : "#ffaf45";
		ctx.fill();
		ctx.lineWidth = 2;
		ctx.strokeStyle = active ? "rgba(255, 250, 242, 0.96)" : "rgba(255, 250, 242, 0.74)";
		ctx.stroke();
	});

	ctx.restore();
}

function drawJunctions() {
	ctx.save();
	for (const junction of state.junctions) {
		const screen = worldToScreen(junction.x, junction.z);
		const selected = junction.id === state.selectedJunctionId;
		const radiusPixels = Math.max(5, junction.radius * state.zoom);
		ctx.beginPath();
		ctx.arc(screen.x, screen.y, radiusPixels, 0, Math.PI * 2);
		ctx.fillStyle = selected ? "rgba(214, 66, 26, 0.2)" : "rgba(28, 132, 125, 0.16)";
		ctx.fill();
		ctx.lineWidth = selected ? 2.5 : 1.5;
		ctx.strokeStyle = selected ? "rgba(214, 66, 26, 0.9)" : "rgba(28, 132, 125, 0.78)";
		ctx.stroke();

		if (selected) {
			ctx.beginPath();
			ctx.arc(screen.x + radiusPixels, screen.y, 4.5, 0, Math.PI * 2);
			ctx.fillStyle = "#d6421a";
			ctx.fill();
			ctx.strokeStyle = "rgba(255, 250, 242, 0.92)";
			ctx.lineWidth = 1.5;
			ctx.stroke();
		}

		ctx.beginPath();
		ctx.arc(screen.x, screen.y, selected ? 6 : 4.5, 0, Math.PI * 2);
		ctx.fillStyle = selected ? "#d6421a" : "#1c847d";
		ctx.fill();
		ctx.strokeStyle = "rgba(255, 250, 242, 0.9)";
		ctx.lineWidth = 1.5;
		ctx.stroke();
	}
	ctx.restore();
}

function render() {
	resizeCanvas();
	const width = elements.canvas.clientWidth;
	const height = elements.canvas.clientHeight;
	ctx.clearRect(0, 0, width, height);
	drawGrid();
	drawTraceImage();
	if (state.meshPreviewEnabled) {
		drawMeshPreview();
	} else {
		state.splines.forEach((spline, index) => {
			drawSplineRibbon(spline, index === state.activeSplineIndex);
		});
	}

	state.splines.forEach((spline, index) => {
		drawControlPolygon(spline, index === state.activeSplineIndex);
	});
	drawJunctions();
}

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
	const crosswalkLength = selected ? selected.crosswalkLength : sanitizeJunctionCrosswalkLength(elements.junctionCrosswalkLengthInput.value);
	const point = pointHit.spline.points[pointHit.pointIndex];
	const junction = makeJunction(point, radius, subdivisions, crosswalkLength);
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

function updateSelectedJunctionCrosswalkLengthFromInput() {
	const selected = getSelectedJunction();
	const crosswalkLength = sanitizeJunctionCrosswalkLength(elements.junctionCrosswalkLengthInput.value);
	if (selected) {
		selected.crosswalkLength = crosswalkLength;
		markMeshPreviewDirty();
		requestRender();
		setStatus(`Set ${selected.name} crosswalk length to ${formatNumber(crosswalkLength, 1)} studs.`);
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

	let records = collectControlPointsInJunction(selected);
	if (records.length === 0) {
		setStatus(`No control points are inside ${selected.name}'s radius.`);
		return;
	}

	let connections = collectAutoJunctionConnections(selected, records);
	let radius = calculateLargestRoadAutoJunctionRadius(records, connections);
	for (let pass = 0; pass < 4; pass += 1) {
		selected.radius = radius;
		const expandedRecords = collectControlPointsInJunction(selected);
		if (sameControlPointRecords(records, expandedRecords)) {
			break;
		}
		records = expandedRecords;
		connections = collectAutoJunctionConnections(selected, records);
		radius = calculateLargestRoadAutoJunctionRadius(records, connections);
	}
	selected.radius = radius;

	for (const record of records) {
		record.point.x = roundNumber(selected.x, 3);
		record.point.y = roundNumber(selected.y ?? 0, 3);
		record.point.z = roundNumber(selected.z, 3);
	}

	markMeshPreviewDirty();
	renderSplineList();
	refreshInspector();
	requestRender();
	setStatus(`Auto-fit ${selected.name}: centered ${records.length} control point${records.length === 1 ? "" : "s"} and sized from the widest intersecting road at ${formatNumber(selected.radius, 1)} studs.`);
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

function updateImageTransformFromInputs() {
	const offsetX = Number(elements.imageOffsetXInput.value);
	const offsetZ = Number(elements.imageOffsetZInput.value);
	const scale = Number(elements.imageScaleInput.value);
	state.image.offsetX = Number.isFinite(offsetX) ? offsetX : 0;
	state.image.offsetZ = Number.isFinite(offsetZ) ? offsetZ : 0;
	state.image.scale = Number.isFinite(scale) && scale > 0 ? scale : 1;
	refreshInspector();
	requestRender();
}

function resetImageTransform() {
	state.image.offsetX = 0;
	state.image.offsetZ = 0;
	state.image.scale = 1;
	state.image.opacity = 55;
	refreshInspector();
	requestRender();
	setStatus("Reset image transform.");
}

function clearImage() {
	clearImageSourceState();
	elements.imageInput.value = "";
	refreshInspector();
	requestRender();
	setStatus("Cleared trace image.");
}

async function loadImageFromFile(file) {
	if (!file) {
		return;
	}
	try {
		clearImageSourceState();
		const dataUrl = await readFileAsDataUrl(file);
		await loadImageFromDataUrl(dataUrl, {
			fileName: file.name,
			mimeType: file.type,
		});
		resetImageTransform();
		setStatus(`Loaded trace image ${file.name}.`);
	} catch (error) {
		setStatus(error.message || `Could not load image ${file.name}.`);
	}
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
	elements.junctionCrosswalkLengthInput.addEventListener("change", updateSelectedJunctionCrosswalkLengthFromInput);
	elements.junctionCrosswalkLengthInput.addEventListener("blur", updateSelectedJunctionCrosswalkLengthFromInput);
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

initialize();
