// Core state, constants, and shared model helpers.

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
) {
	return {
		id: `junction-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
		name: `Junction${String(state.junctions.length + 1).padStart(3, "0")}`,
		x: roundNumber(position.x, 3),
		y: roundNumber(position.y ?? 0, 3),
		z: roundNumber(position.z, 3),
		radius: sanitizeJunctionRadius(radius),
		subdivisions: sanitizeJunctionSubdivisions(subdivisions),
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
