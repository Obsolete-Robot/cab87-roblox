const ROAD_WIDTH_DEFAULT = 28;
const ROAD_WIDTH_MIN = 8;
const ROAD_WIDTH_MAX = 200;
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
const CURVE_INSERT_HIT_RADIUS_PX = 18;
const CURVE_END_INSERT_ALPHA_THRESHOLD = 0.28;

const elements = {
	canvas: document.getElementById("editorCanvas"),
	splineList: document.getElementById("splineList"),
	widthInput: document.getElementById("widthInput"),
	closedToggle: document.getElementById("closedToggle"),
	meshPreviewToggle: document.getElementById("meshPreviewToggle"),
	deletePointButton: document.getElementById("deletePointButton"),
	centerViewButton: document.getElementById("centerViewButton"),
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

const state = {
	cameraX: 0,
	cameraZ: 0,
	zoom: 1.1,
	splines: [],
	activeSplineIndex: 0,
	selectedPoint: null,
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

function refreshInspector() {
	const spline = getActiveSpline();
	elements.widthInput.value = formatNumber(spline.width, 1);
	elements.closedToggle.checked = spline.closed;
	elements.meshPreviewToggle.checked = state.meshPreviewEnabled;
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
	return {
		version: 1,
		sampleStepStuds: SAMPLE_STEP_STUDS,
		coordinateSpace: {
			upAxis: "Y",
			planarAxes: ["X", "Z"],
			units: "studs",
		},
		splines: state.splines
			.filter((spline) => spline.points.length >= 2)
			.map(cloneSplineForExport),
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
		},
	};
}

function normalizeImportedSpline(splineData, index) {
	if (!splineData || typeof splineData !== "object" || !Array.isArray(splineData.points)) {
		return null;
	}

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
		spline.points.push({
			x: roundNumber(x, 3),
			y: 0,
			z: roundNumber(z, 3),
		});
	}

	if (spline.points.length < 2) {
		return null;
	}

	spline.closed = splineData.closed === true && spline.points.length >= 3;
	return spline;
}

function frameActiveSpline(setMessage = true) {
	const spline = getActiveSpline();
	const points = spline.points.length > 0
		? spline.points
		: state.splines.flatMap((item) => item.points);

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

async function importSessionFromText(text) {
	let payload;
	try {
		payload = JSON.parse(text);
	} catch (error) {
		throw new Error(`Could not parse JSON: ${error.message}`);
	}

	if (!payload || typeof payload !== "object" || !Array.isArray(payload.splines)) {
		throw new Error("Session JSON must include a splines array.");
	}

	const importedSplines = payload.splines
		.map((splineData, index) => normalizeImportedSpline(splineData, index))
		.filter(Boolean);

	if (importedSplines.length === 0) {
		throw new Error("Session JSON did not contain any valid splines with at least 2 points.");
	}

	state.splines = importedSplines;
	state.activeSplineIndex = 0;
	state.selectedPoint = null;

	const editorState = payload.editorState && typeof payload.editorState === "object"
		? payload.editorState
		: null;
	state.meshPreviewEnabled = editorState ? editorState.meshPreviewEnabled === true : false;

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
	setStatus(`Imported ${importedSplines.length} spline${importedSplines.length === 1 ? "" : "s"} from session JSON.`);
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

function lineIntersectionXZ(a, dirA, b, dirB) {
	const denom = (dirA.x * dirB.z) - (dirA.z * dirB.x);
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

function buildRoadCrossSections(samples, roadWidth) {
	if (samples.length < 2) {
		return null;
	}

	const width = sanitizeRoadWidth(roadWidth);
	const closedLoop = sampleLoopIsClosed(samples);
	const edgeCount = closedLoop ? samples.length - 1 : samples.length;
	if (edgeCount < 2) {
		return null;
	}

	const halfWidth = width * 0.5;
	const widthSegments = Math.min(
		ROAD_WIDTH_MAX_INTERNAL_LOOPS + 1,
		Math.max(1, Math.ceil(width / ROAD_WIDTH_TRIANGULATION_STEP)),
	);
	const centerControls = [];
	const leftControls = [];
	const rightControls = [];
	const rights = [];
	let fallbackDir = { x: 0, z: 1 };

	for (let index = 0; index < edgeCount; index += 1) {
		const tangent = getRoadSampleTangent(samples, index, edgeCount, closedLoop, fallbackDir) || fallbackDir;
		fallbackDir = tangent;
		let right = roadRightFromTangent(fallbackDir);
		if (index > 0 && rights[index - 1] && dot2D(right, rights[index - 1]) < 0) {
			right = scale2D(right, -1);
		}
		const center = clonePoint(samples[index]);
		centerControls[index] = center;
		rights[index] = right;
		leftControls[index] = makePoint(center.x - (right.x * halfWidth), center.z - (right.z * halfWidth), center.y ?? 0);
		rightControls[index] = makePoint(center.x + (right.x * halfWidth), center.z + (right.z * halfWidth), center.y ?? 0);
	}

	const smoothedCenterControls = sampleSmoothedCurveControls(centerControls, closedLoop, ROAD_EDGE_CURVE_SMOOTH_STEP);
	const smoothedLeftControls = fairEdgeCurveControls(leftControls, closedLoop, ROAD_EDGE_CURVE_SMOOTH_STEP);
	const smoothedRightControls = fairEdgeCurveControls(rightControls, closedLoop, ROAD_EDGE_CURVE_SMOOTH_STEP);

	const centerLength = polylineLength(smoothedCenterControls, closedLoop);
	const leftLength = polylineLength(smoothedLeftControls, closedLoop);
	const rightLength = polylineLength(smoothedRightControls, closedLoop);
	let desiredRowCount = closedLoop
		? Math.max(3, edgeCount, Math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP))
		: Math.max(2, edgeCount, Math.ceil(centerLength / ROAD_LOFT_LENGTH_STEP) + 1);
	const minEdgeStep = Math.max(2, width * 0.02);
	const shortestCurveLength = Math.min(centerLength, leftLength, rightLength);
	let edgeLimitedRowCount = desiredRowCount;
	if (shortestCurveLength > 1e-4) {
		edgeLimitedRowCount = closedLoop
			? Math.max(3, Math.floor(shortestCurveLength / minEdgeStep))
			: Math.max(2, Math.floor(shortestCurveLength / minEdgeStep) + 1);
	}
	const rowCount = Math.min(desiredRowCount, edgeLimitedRowCount);
	const spanCount = closedLoop ? rowCount : rowCount - 1;
	const centers = [];
	const leftPositions = [];
	const rightPositions = [];

	for (let index = 0; index < rowCount; index += 1) {
		const fraction = closedLoop
			? (index / rowCount)
			: (rowCount > 1 ? (index / (rowCount - 1)) : 0);
		centers[index] = samplePolylineAtFraction(smoothedCenterControls, closedLoop, fraction);
		leftPositions[index] = samplePolylineAtFraction(smoothedLeftControls, closedLoop, fraction);
		rightPositions[index] = samplePolylineAtFraction(smoothedRightControls, closedLoop, fraction);
		const lateral = horizontalUnit(subtract2D(rightPositions[index], leftPositions[index]));
		if (lateral) {
			const mid = makePoint(
				(leftPositions[index].x + rightPositions[index].x) * 0.5,
				(leftPositions[index].z + rightPositions[index].z) * 0.5,
				((leftPositions[index].y ?? 0) + (rightPositions[index].y ?? 0)) * 0.5,
			);
			leftPositions[index] = makePoint(mid.x - (lateral.x * halfWidth), mid.z - (lateral.z * halfWidth), mid.y ?? 0);
			rightPositions[index] = makePoint(mid.x + (lateral.x * halfWidth), mid.z + (lateral.z * halfWidth), mid.y ?? 0);
		}
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
	const chains = state.splines
		.filter((spline) => spline.points.length >= 2)
		.map((spline) => ({
			spline,
			points: spline.points.map(clonePoint),
			samples: samplePositions(spline.points.map(createVector), spline.closed, SAMPLE_STEP_STUDS),
			closed: spline.closed,
			width: spline.width,
		}));

	if (chains.length === 0) {
		return { chains: [], junctions: [] };
	}

	const rawJunctions = [
		...collectEndpointJunctions(chains),
		...collectCrossIntersections(chains),
	];
	const junctions = mergeJunctions(rawJunctions);
	applyJunctionsToChains(chains, junctions);

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
		const center = worldToScreen(junction.center.x, junction.center.z);
		const radius = junction.radius * state.zoom;
		ctx.beginPath();
		ctx.arc(center.x, center.y, radius, 0, Math.PI * 2);
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
		const center = worldToScreen(junction.center.x, junction.center.z);
		const radius = junction.radius * state.zoom;
		ctx.beginPath();
		ctx.arc(center.x, center.y, radius, 0, Math.PI * 2);
		ctx.stroke();
		for (let index = 0; index < INTERSECTION_RING_SEGMENTS; index += 1) {
			const theta = (index / INTERSECTION_RING_SEGMENTS) * Math.PI * 2;
			const edge = worldToScreen(
				junction.center.x + (Math.cos(theta) * junction.radius),
				junction.center.z + (Math.sin(theta) * junction.radius),
			);
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
		setStatus("Select a control point before deleting it.");
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
	setStatus(`Exported ${payload.splines.length} spline${payload.splines.length === 1 ? "" : "s"} to JSON.`);
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

	const hit = pickPoint(localX, localY);
	if (hit) {
		state.activeSplineIndex = hit.splineIndex;
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
	}
}

function bindEvents() {
	window.addEventListener("resize", resizeCanvas);
	window.addEventListener("keydown", handleKeyDown);

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
	elements.centerViewButton.addEventListener("click", centerViewOnActiveSpline);
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

function initialize() {
	state.splines = [makeSpline("Spline001")];
	state.image = createEmptyImageState();
	bindEvents();
	renderSplineList();
	refreshInspector();
	resizeCanvas();
	centerViewOnActiveSpline();
	setStatus("Ready. Import an image or start placing points.");
}

initialize();
