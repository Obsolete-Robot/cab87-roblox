import { DEFAULTS, sanitizeBuildingFillSettings } from './constants';
import { getLowestPointZ } from './buildings';
import { segmentIntersect } from './math';
import { buildNetworkMesh } from './meshing';
import { findClosedAreas } from './network';
import type { BuildingFillSettings, BuildingPolygon, Edge, MeshData, Node, Point } from './types';

type RoadPolygon = MeshData['roadPolygons'][number];

type BuildingFillParams = {
  nodes: Node[];
  edges: Edge[];
  selectedNodes: string[];
  selectedEdges: string[];
  buildings: BuildingPolygon[];
  chamferAngle: number;
  meshResolution: number;
  laneWidth: number;
  settings: BuildingFillSettings;
  seedSalt?: string;
};

type BuildingFillResult = {
  buildings: BuildingPolygon[];
  mode: 'closed' | 'open' | 'none';
};

type FillBoundary = {
  polygon: Point[];
  centroid: Point;
  edgeSegments?: Point[][];
};

type CurveSide = 'left' | 'right';

const MIN_CURVE_LENGTH = 1;
const BOUNDARY_EPSILON = 0.1;

function hashString(value: string) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function createRandom(seed: string) {
  let state = hashString(seed);
  return () => {
    state += 0x6d2b79f5;
    let next = state;
    next = Math.imul(next ^ (next >>> 15), next | 1);
    next ^= next + Math.imul(next ^ (next >>> 7), next | 61);
    return ((next ^ (next >>> 14)) >>> 0) / 4294967296;
  };
}

function randomRange(random: () => number, min: number, max: number) {
  if (max <= min) return min;
  return min + (max - min) * random();
}

function makeBuildingId(seed: string, usedIds: Set<string>) {
  const base = `bf_${hashString(seed).toString(36)}`;
  let id = base;
  let suffix = 2;
  while (usedIds.has(id)) {
    id = `${base}_${suffix}`;
    suffix++;
  }
  usedIds.add(id);
  return id;
}

function pointDistanceToSegment(point: Point, a: Point, b: Point) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lenSq = dx * dx + dy * dy;
  if (lenSq < 0.0001) return Math.hypot(point.x - a.x, point.y - a.y);
  const t = Math.max(0, Math.min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq));
  return Math.hypot(point.x - (a.x + dx * t), point.y - (a.y + dy * t));
}

function pointDistance(a: Point, b: Point) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function pointInPolygon(point: Point, polygon: Point[]) {
  if (polygon.length < 3) return false;

  for (let index = 0; index < polygon.length; index++) {
    if (pointDistanceToSegment(point, polygon[index], polygon[(index + 1) % polygon.length]) <= BOUNDARY_EPSILON) {
      return true;
    }
  }

  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const pi = polygon[i];
    const pj = polygon[j];
    if (
      (pi.y > point.y) !== (pj.y > point.y) &&
      point.x < ((pj.x - pi.x) * (point.y - pi.y)) / (pj.y - pi.y) + pi.x
    ) {
      inside = !inside;
    }
  }
  return inside;
}

function pointStrictlyInPolygon(point: Point, polygon: Point[]) {
  if (polygon.length < 3) return false;

  for (let index = 0; index < polygon.length; index++) {
    if (pointDistanceToSegment(point, polygon[index], polygon[(index + 1) % polygon.length]) <= BOUNDARY_EPSILON) {
      return false;
    }
  }

  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const pi = polygon[i];
    const pj = polygon[j];
    if (
      (pi.y > point.y) !== (pj.y > point.y) &&
      point.x < ((pj.x - pi.x) * (point.y - pi.y)) / (pj.y - pi.y) + pi.x
    ) {
      inside = !inside;
    }
  }
  return inside;
}

function polygonCentroid(polygon: Point[]): Point {
  let signedArea = 0;
  let cx = 0;
  let cy = 0;

  for (let index = 0; index < polygon.length; index++) {
    const current = polygon[index];
    const next = polygon[(index + 1) % polygon.length];
    const cross = current.x * next.y - next.x * current.y;
    signedArea += cross;
    cx += (current.x + next.x) * cross;
    cy += (current.y + next.y) * cross;
  }

  if (Math.abs(signedArea) > 0.0001) {
    const factor = 1 / (3 * signedArea);
    return { x: cx * factor, y: cy * factor };
  }

  const sum = polygon.reduce((acc, point) => ({ x: acc.x + point.x, y: acc.y + point.y }), { x: 0, y: 0 });
  return { x: sum.x / polygon.length, y: sum.y / polygon.length };
}

function polygonBounds(polygon: Point[]) {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  polygon.forEach((point) => {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  });

  return { minX, minY, maxX, maxY };
}

function polygonsOverlap(a: Point[], b: Point[]) {
  if (a.length < 3 || b.length < 3) return false;

  const boundsA = polygonBounds(a);
  const boundsB = polygonBounds(b);
  if (
    boundsA.maxX < boundsB.minX ||
    boundsB.maxX < boundsA.minX ||
    boundsA.maxY < boundsB.minY ||
    boundsB.maxY < boundsA.minY
  ) {
    return false;
  }

  for (let i = 0; i < a.length; i++) {
    const a0 = a[i];
    const a1 = a[(i + 1) % a.length];
    for (let j = 0; j < b.length; j++) {
      const b0 = b[j];
      const b1 = b[(j + 1) % b.length];
      const intersection = segmentIntersect(a0, a1, b0, b1);
      if (
        intersection &&
        pointDistance(intersection, a0) > BOUNDARY_EPSILON &&
        pointDistance(intersection, a1) > BOUNDARY_EPSILON &&
        pointDistance(intersection, b0) > BOUNDARY_EPSILON &&
        pointDistance(intersection, b1) > BOUNDARY_EPSILON
      ) {
        return true;
      }
    }
  }

  return (
    pointStrictlyInPolygon(a[0], b) ||
    pointStrictlyInPolygon(b[0], a) ||
    pointStrictlyInPolygon(averagePoint(a), b) ||
    pointStrictlyInPolygon(averagePoint(b), a)
  );
}

function isSimplePolygon(polygon: Point[]) {
  for (let i = 0; i < polygon.length; i++) {
    const a0 = polygon[i];
    const a1 = polygon[(i + 1) % polygon.length];

    for (let j = i + 1; j < polygon.length; j++) {
      if (Math.abs(i - j) <= 1 || (i === 0 && j === polygon.length - 1)) continue;

      const b0 = polygon[j];
      const b1 = polygon[(j + 1) % polygon.length];
      const intersection = segmentIntersect(a0, a1, b0, b1);
      if (
        intersection &&
        pointDistance(intersection, a0) > BOUNDARY_EPSILON &&
        pointDistance(intersection, a1) > BOUNDARY_EPSILON &&
        pointDistance(intersection, b0) > BOUNDARY_EPSILON &&
        pointDistance(intersection, b1) > BOUNDARY_EPSILON
      ) {
        return false;
      }
    }
  }

  return true;
}

function isValidBuildingFootprint(vertices: Point[]) {
  if (vertices.length < 3) return false;
  if (vertices.some((vertex) => !Number.isFinite(vertex.x) || !Number.isFinite(vertex.y))) return false;
  if (Math.abs(polygonSignedArea(vertices)) <= 1) return false;
  return isSimplePolygon(vertices);
}

function meetsMinimumFootprintSize(vertices: Point[], settings: BuildingFillSettings) {
  return vertices.every((vertex, index) => (
    pointDistance(vertex, vertices[(index + 1) % vertices.length]) >= settings.minWidth - BOUNDARY_EPSILON
  ));
}

function getPolylineLength(curve: Point[]) {
  let length = 0;
  for (let index = 1; index < curve.length; index++) {
    length += Math.hypot(curve[index].x - curve[index - 1].x, curve[index].y - curve[index - 1].y);
  }
  return length;
}

function getFillSegmentCount(totalLength: number, settings: BuildingFillSettings) {
  if (totalLength <= MIN_CURVE_LENGTH) return 0;

  const averageWidth = (settings.minWidth + settings.maxWidth) / 2;
  let count = Math.max(1, Math.round(totalLength / Math.max(averageWidth, 1)));

  if (totalLength / count > settings.maxWidth) {
    count = Math.ceil(totalLength / settings.maxWidth);
  }

  if (count > 1 && totalLength / count < settings.minWidth) {
    count = Math.max(1, Math.floor(totalLength / settings.minWidth));
  }

  return count;
}

function samplePolyline(curve: Point[], distance: number) {
  let remaining = Math.max(0, distance);
  for (let index = 1; index < curve.length; index++) {
    const previous = curve[index - 1];
    const current = curve[index];
    const dx = current.x - previous.x;
    const dy = current.y - previous.y;
    const length = Math.hypot(dx, dy);
    if (length <= 0.0001) continue;

    if (remaining <= length || index === curve.length - 1) {
      const t = Math.max(0, Math.min(1, remaining / length));
      return {
        point: {
          x: previous.x + dx * t,
          y: previous.y + dy * t,
          z: (previous.z ?? DEFAULTS.buildingBaseZ) + ((current.z ?? DEFAULTS.buildingBaseZ) - (previous.z ?? DEFAULTS.buildingBaseZ)) * t,
        },
        tangent: { x: dx / length, y: dy / length },
      };
    }

    remaining -= length;
  }

  const first = curve[0] ?? { x: 0, y: 0 };
  const last = curve[curve.length - 1] ?? first;
  const dx = last.x - first.x;
  const dy = last.y - first.y;
  const length = Math.hypot(dx, dy) || 1;
  return {
    point: { ...last },
    tangent: { x: dx / length, y: dy / length },
  };
}

function getPointDistances(curve: Point[]) {
  const distances = [0];
  for (let index = 1; index < curve.length; index++) {
    distances.push(distances[index - 1] + pointDistance(curve[index], curve[index - 1]));
  }
  return distances;
}

function slicePolyline(curve: Point[], startDistance: number, endDistance: number) {
  if (curve.length < 2) return [...curve];

  const distances = getPointDistances(curve);
  const totalLength = distances[distances.length - 1];
  const start = Math.max(0, Math.min(totalLength, startDistance));
  const end = Math.max(start, Math.min(totalLength, endDistance));
  const result: Point[] = [samplePolyline(curve, start).point];

  for (let index = 1; index < curve.length - 1; index++) {
    if (distances[index] > start + BOUNDARY_EPSILON && distances[index] < end - BOUNDARY_EPSILON) {
      result.push({ ...curve[index] });
    }
  }

  const endPoint = samplePolyline(curve, end).point;
  const previous = result[result.length - 1];
  if (!previous || pointDistance(previous, endPoint) > BOUNDARY_EPSILON) {
    result.push(endPoint);
  }

  return result;
}

function getClosedCurve(polygon: Point[]) {
  if (polygon.length === 0) return [];
  return [...polygon, polygon[0]];
}

function isSharpBoundaryTurn(previous: Point, current: Point, next: Point) {
  const dx1 = current.x - previous.x;
  const dy1 = current.y - previous.y;
  const dx2 = next.x - current.x;
  const dy2 = next.y - current.y;
  const len1 = Math.hypot(dx1, dy1);
  const len2 = Math.hypot(dx2, dy2);
  if (len1 <= BOUNDARY_EPSILON || len2 <= BOUNDARY_EPSILON) return false;

  const dot = (dx1 * dx2 + dy1 * dy2) / (len1 * len2);
  return dot < Math.cos(Math.PI / 4);
}

function splitClosedBoundaryIntoRuns(polygon: Point[]) {
  if (polygon.length < 3) return [];

  const breakpoints: number[] = [];
  for (let index = 0; index < polygon.length; index++) {
    const previous = polygon[(index - 1 + polygon.length) % polygon.length];
    const current = polygon[index];
    const next = polygon[(index + 1) % polygon.length];
    if (isSharpBoundaryTurn(previous, current, next)) {
      breakpoints.push(index);
    }
  }

  if (breakpoints.length === 0) {
    return [getClosedCurve(polygon)];
  }

  return breakpoints.flatMap((startIndex, breakpointIndex) => {
    const endIndex = breakpoints[(breakpointIndex + 1) % breakpoints.length];
    const run: Point[] = [polygon[startIndex]];
    let index = (startIndex + 1) % polygon.length;
    let guard = 0;

    while (guard < polygon.length + 1) {
      run.push(polygon[index]);
      if (index === endIndex) break;
      index = (index + 1) % polygon.length;
      guard++;
    }

    return getPolylineLength(run) > MIN_CURVE_LENGTH ? [run] : [];
  });
}

function closestPointOnSegment(point: Point, a: Point, b: Point) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lenSq = dx * dx + dy * dy;
  if (lenSq < 0.0001) {
    return {
      point: a,
      distance: pointDistance(point, a),
      t: 0,
    };
  }

  const t = Math.max(0, Math.min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq));
  const closest = {
    x: a.x + dx * t,
    y: a.y + dy * t,
    z: (a.z ?? DEFAULTS.buildingBaseZ) + ((b.z ?? DEFAULTS.buildingBaseZ) - (a.z ?? DEFAULTS.buildingBaseZ)) * t,
  };

  return {
    point: closest,
    distance: pointDistance(point, closest),
    t,
  };
}

function closestBoundaryPoint(point: Point, polygon: Point[], closed = true) {
  let best = {
    point,
    segmentIndex: -1,
    distance: Infinity,
    t: 0,
  };

  const segmentCount = closed ? polygon.length : Math.max(polygon.length - 1, 0);
  for (let index = 0; index < segmentCount; index++) {
    const closest = closestPointOnSegment(point, polygon[index], polygon[(index + 1) % polygon.length]);
    if (closest.distance < best.distance) {
      best = {
        point: closest.point,
        segmentIndex: index,
        distance: closest.distance,
        t: closest.t,
      };
    }
  }

  return best;
}

function buildOpenBoundaryPath(hubPolygon: Point[], from: Point, to: Point): Point[] {
  if (hubPolygon.length < 2) return [];

  const fromBoundary = closestBoundaryPoint(from, hubPolygon, false);
  const toBoundary = closestBoundaryPoint(to, hubPolygon, false);
  if (fromBoundary.segmentIndex === -1 || toBoundary.segmentIndex === -1) return [];

  const fromPosition = fromBoundary.segmentIndex + fromBoundary.t;
  const toPosition = toBoundary.segmentIndex + toBoundary.t;
  const path: Point[] = [fromBoundary.point];

  if (fromPosition <= toPosition) {
    for (let index = fromBoundary.segmentIndex + 1; index <= toBoundary.segmentIndex; index++) {
      path.push(hubPolygon[index]);
    }
  } else {
    for (let index = fromBoundary.segmentIndex; index > toBoundary.segmentIndex; index--) {
      path.push(hubPolygon[index]);
    }
  }

  path.push(toBoundary.point);
  return path;
}

function buildHubBoundaryPath(hubPolygon: Point[], from: Point, to: Point, isClockwise: boolean, openBoundary = false): Point[] {
  if (hubPolygon.length < 2) return [];
  if (openBoundary) return buildOpenBoundaryPath(hubPolygon, from, to);

  const fromBoundary = closestBoundaryPoint(from, hubPolygon);
  const toBoundary = closestBoundaryPoint(to, hubPolygon);
  if (fromBoundary.segmentIndex === -1 || toBoundary.segmentIndex === -1) return [];
  if (fromBoundary.distance > 25 || toBoundary.distance > 25) return [];

  const forwardPath: Point[] = [fromBoundary.point];
  let forwardIndex = (fromBoundary.segmentIndex + 1) % hubPolygon.length;
  const forwardStop = (toBoundary.segmentIndex + 1) % hubPolygon.length;
  while (forwardIndex !== forwardStop && forwardPath.length < hubPolygon.length + 2) {
    forwardPath.push(hubPolygon[forwardIndex]);
    forwardIndex = (forwardIndex + 1) % hubPolygon.length;
  }
  forwardPath.push(toBoundary.point);

  const backwardPath: Point[] = [fromBoundary.point];
  let backwardIndex = fromBoundary.segmentIndex;
  while (backwardIndex !== toBoundary.segmentIndex && backwardPath.length < hubPolygon.length + 2) {
    backwardPath.push(hubPolygon[backwardIndex]);
    backwardIndex = (backwardIndex - 1 + hubPolygon.length) % hubPolygon.length;
  }
  backwardPath.push(toBoundary.point);

  const forwardLength = getPolylineLength(forwardPath);
  const backwardLength = getPolylineLength(backwardPath);
  if (Math.abs(forwardLength - backwardLength) > BOUNDARY_EPSILON) {
    return forwardLength <= backwardLength ? forwardPath : backwardPath;
  }

  return isClockwise ? backwardPath : forwardPath;
}

function leftNormal(dir: Point) {
  return { x: dir.y, y: -dir.x };
}

function rightNormal(dir: Point) {
  return { x: -dir.y, y: dir.x };
}

function offsetPoint(point: Point, normal: Point, distance: number): Point {
  return {
    x: point.x + normal.x * distance,
    y: point.y + normal.y * distance,
    z: point.z,
  };
}

function footprintPoint(point: Point, z = point.z): Point {
  const next: Point = { x: point.x, y: point.y };
  if (typeof z === 'number' && Number.isFinite(z)) {
    next.z = z;
  }
  return next;
}

function averagePoint(points: Point[]) {
  const sum = points.reduce((acc, point) => ({ x: acc.x + point.x, y: acc.y + point.y }), { x: 0, y: 0 });
  return { x: sum.x / points.length, y: sum.y / points.length };
}

function segmentMidpoint(a: Point, b: Point) {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

function hasBuildingOverlap(vertices: Point[], existingBuildings: BuildingPolygon[]) {
  return existingBuildings.some((building) => polygonsOverlap(vertices, building.vertices));
}

function hasForbiddenOverlap(vertices: Point[], forbiddenPolygons: Point[][]) {
  return forbiddenPolygons.some((polygon) => polygon.length >= 3 && polygonsOverlap(vertices, polygon));
}

function hasForbiddenInteriorPoint(vertices: Point[], forbiddenPolygons: Point[][]) {
  const probes = [
    averagePoint(vertices),
    segmentMidpoint(vertices[2], vertices[3]),
    vertices[2],
    vertices[3],
  ];

  return probes.some((point) => (
    forbiddenPolygons.some((polygon) => polygon.length >= 3 && pointStrictlyInPolygon(point, polygon))
  ));
}

function buildingFitsInsideBoundary(vertices: Point[], boundary: Point[]) {
  if (vertices.length < 3 || boundary.length < 3) return false;

  if (!vertices.every((vertex) => pointInPolygon(vertex, boundary))) {
    return false;
  }

  if (!pointInPolygon(averagePoint(vertices), boundary)) {
    return false;
  }

  for (let index = 0; index < vertices.length; index++) {
    const current = vertices[index];
    const next = vertices[(index + 1) % vertices.length];
    if (!pointInPolygon(segmentMidpoint(current, next), boundary)) {
      return false;
    }
  }

  for (let edgeIndex = 1; edgeIndex < vertices.length; edgeIndex++) {
    const current = vertices[edgeIndex];
    const next = vertices[(edgeIndex + 1) % vertices.length];

    for (let boundaryIndex = 0; boundaryIndex < boundary.length; boundaryIndex++) {
      const boundaryA = boundary[boundaryIndex];
      const boundaryB = boundary[(boundaryIndex + 1) % boundary.length];
      const intersection = segmentIntersect(current, next, boundaryA, boundaryB);
      if (!intersection) continue;

      const touchesBuildingEndpoint = (
        pointDistance(intersection, current) <= BOUNDARY_EPSILON * 2 ||
        pointDistance(intersection, next) <= BOUNDARY_EPSILON * 2
      );
      if (!touchesBuildingEndpoint) {
        return false;
      }
    }
  }

  return true;
}

function getLocalTangent(curve: Point[], index: number) {
  const previous = curve[Math.max(0, index - 1)];
  const next = curve[Math.min(curve.length - 1, index + 1)];
  const dx = next.x - previous.x;
  const dy = next.y - previous.y;
  const length = Math.hypot(dx, dy);
  return length > 0.0001 ? { x: dx / length, y: dy / length } : { x: 1, y: 0 };
}

function getEndpointTangent(curve: Point[], endpoint: 'start' | 'end') {
  if (curve.length < 2) return { x: 1, y: 0 };
  const a = endpoint === 'start' ? curve[0] : curve[curve.length - 2];
  const b = endpoint === 'start' ? curve[1] : curve[curve.length - 1];
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const length = Math.hypot(dx, dy);
  return length > 0.0001 ? { x: dx / length, y: dy / length } : getLocalTangent(curve, Math.floor((curve.length - 1) / 2));
}

function sideNormal(tangent: Point, side: CurveSide) {
  return side === 'left' ? leftNormal(tangent) : rightNormal(tangent);
}

function buildStripCandidate(frontCurve: Point[], side: CurveSide, depth: number) {
  const frontA = frontCurve[0];
  const frontB = frontCurve[frontCurve.length - 1];
  const dx = frontB.x - frontA.x;
  const dy = frontB.y - frontA.y;
  const chordLength = Math.hypot(dx, dy);
  const tangent = chordLength > BOUNDARY_EPSILON
    ? { x: dx / chordLength, y: dy / chordLength }
    : getEndpointTangent(frontCurve, 'start');
  const normal = sideNormal(tangent, side);
  const backB = offsetPoint(frontB, normal, depth);
  const backA = offsetPoint(frontA, normal, depth);

  return [
    footprintPoint(frontA),
    footprintPoint(frontB),
    footprintPoint(backB, frontB.z),
    footprintPoint(backA, frontA.z),
  ];
}

function getBuildingFillBaseZ(frontCurve: Point[], vertices: Point[]) {
  return getLowestPointZ([...frontCurve, ...vertices], DEFAULTS.buildingBaseZ);
}

function buildDepthCandidates(preferredDepth: number, settings: BuildingFillSettings) {
  const clampedPreferred = Math.max(settings.minWidth, Math.min(settings.maxWidth, preferredDepth));
  const candidates = [
    clampedPreferred,
    settings.maxWidth,
    clampedPreferred * 0.85,
    clampedPreferred * 0.7,
    clampedPreferred * 0.55,
    settings.minWidth,
  ];

  return candidates.filter((depth, index) => (
    depth >= settings.minWidth - BOUNDARY_EPSILON &&
    candidates.findIndex((candidate) => Math.abs(candidate - depth) <= BOUNDARY_EPSILON) === index
  ));
}

function chooseInteriorSide(frontCurve: Point[], boundary: FillBoundary): CurveSide {
  const middle = samplePolyline(frontCurve, getPolylineLength(frontCurve) / 2);
  const leftProbe = offsetPoint(middle.point, leftNormal(middle.tangent), 2);
  const rightProbe = offsetPoint(middle.point, rightNormal(middle.tangent), 2);
  const leftInside = pointInPolygon(leftProbe, boundary.polygon);
  const rightInside = pointInPolygon(rightProbe, boundary.polygon);

  if (leftInside !== rightInside) {
    return leftInside ? 'left' : 'right';
  }

  return pointDistance(leftProbe, boundary.centroid) <= pointDistance(rightProbe, boundary.centroid)
    ? 'left'
    : 'right';
}

function generateBuildingsAlongCurve(options: {
  curve: Point[];
  side: CurveSide;
  settings: BuildingFillSettings;
  existingBuildings: BuildingPolygon[];
  forbiddenPolygons: Point[][];
  usedIds: Set<string>;
  seed: string;
}) {
  const curve = options.curve.filter((point) => Number.isFinite(point.x) && Number.isFinite(point.y));
  const totalLength = getPolylineLength(curve);
  if (curve.length < 2 || totalLength <= MIN_CURVE_LENGTH) return [];

  const generated: BuildingPolygon[] = [];
  const buildingCount = getFillSegmentCount(totalLength, options.settings);
  const segmentLength = totalLength / buildingCount;

  for (let index = 0; index < buildingCount; index++) {
    const startDistance = index * segmentLength;
    const endDistance = index === buildingCount - 1 ? totalLength : (index + 1) * segmentLength;
    const frontCurve = slicePolyline(curve, startDistance, endDistance);
    if (frontCurve.length < 2) continue;

    const depthRandom = createRandom(`${options.seed}:${index}:depth`);
    const heightRandom = createRandom(`${options.seed}:${index}:height`);
    const requestedDepth = randomRange(depthRandom, options.settings.minWidth, options.settings.maxWidth);
    const height = Math.round(randomRange(heightRandom, options.settings.minHeight, options.settings.maxHeight));
    let acceptedVertices: Point[] | null = null;

    const depths = [
      requestedDepth,
      requestedDepth * 0.8,
      requestedDepth * 0.6,
      requestedDepth * 0.4,
      options.settings.minWidth,
    ];

    for (const depth of depths) {
      if (depth < options.settings.minWidth) continue;
      const vertices = buildStripCandidate(frontCurve, options.side, depth);
      if (!isValidBuildingFootprint(vertices)) continue;
      if (!meetsMinimumFootprintSize(vertices, options.settings)) continue;
      if (hasForbiddenInteriorPoint(vertices, options.forbiddenPolygons)) continue;
      if (hasBuildingOverlap(vertices, options.existingBuildings)) continue;
      acceptedVertices = vertices;
      break;
    }

    if (acceptedVertices) {
      const building: BuildingPolygon = {
        id: makeBuildingId(`${options.seed}:${index}`, options.usedIds),
        vertices: acceptedVertices,
        baseZ: getBuildingFillBaseZ(frontCurve, acceptedVertices),
        height,
        color: DEFAULTS.buildingColor,
        material: DEFAULTS.buildingMaterial,
      };
      generated.push(building);
    }
  }

  return generated;
}

function getCornerFrontage(curve: Point[], endpoint: 'start' | 'end', settings: BuildingFillSettings) {
  const totalLength = getPolylineLength(curve);
  if (curve.length < 2 || totalLength < settings.minWidth - BOUNDARY_EPSILON) return null;

  const buildingCount = getFillSegmentCount(totalLength, settings);
  if (buildingCount <= 0) return null;

  const frontageLength = totalLength / buildingCount;
  if (frontageLength < settings.minWidth - BOUNDARY_EPSILON) return null;

  return endpoint === 'start'
    ? slicePolyline(curve, 0, frontageLength)
    : slicePolyline(curve, totalLength - frontageLength, totalLength);
}

function tryCreateClosedCornerBuilding(options: {
  frontCurve: Point[];
  boundary: FillBoundary;
  settings: BuildingFillSettings;
  occupied: BuildingPolygon[];
  forbiddenPolygons: Point[][];
  usedIds: Set<string>;
  seed: string;
}) {
  const frontLength = getPolylineLength(options.frontCurve);
  if (frontLength < options.settings.minWidth - BOUNDARY_EPSILON) return null;

  const preferredSide = chooseInteriorSide(options.frontCurve, options.boundary);
  const sides: CurveSide[] = preferredSide === 'left' ? ['left', 'right'] : ['right', 'left'];
  const depthRandom = createRandom(`${options.seed}:depth`);
  const preferredDepth = randomRange(depthRandom, options.settings.minWidth, options.settings.maxWidth);

  for (const depth of buildDepthCandidates(preferredDepth, options.settings)) {
    for (const side of sides) {
      const vertices = buildStripCandidate(options.frontCurve, side, depth);
      if (!isValidBuildingFootprint(vertices)) continue;
      if (!meetsMinimumFootprintSize(vertices, options.settings)) continue;
      if (!buildingFitsInsideBoundary(vertices, options.boundary.polygon)) continue;
      if (hasForbiddenOverlap(vertices, options.forbiddenPolygons)) continue;
      if (hasBuildingOverlap(vertices, options.occupied)) continue;

      const heightRandom = createRandom(`${options.seed}:height`);
      return {
        id: makeBuildingId(options.seed, options.usedIds),
        vertices,
        baseZ: getBuildingFillBaseZ(options.frontCurve, vertices),
        height: Math.round(randomRange(heightRandom, options.settings.minHeight, options.settings.maxHeight)),
        color: DEFAULTS.buildingColor,
        material: DEFAULTS.buildingMaterial,
      } satisfies BuildingPolygon;
    }
  }

  return null;
}

function generateClosedCornerBuildings(options: {
  boundary: FillBoundary;
  settings: BuildingFillSettings;
  existingBuildings: BuildingPolygon[];
  forbiddenPolygons: Point[][];
  usedIds: Set<string>;
  seed: string;
}) {
  const edgeSegments = options.boundary.edgeSegments ?? [];
  if (edgeSegments.length < 2) return [];

  const generated: BuildingPolygon[] = [];
  const occupied = [...options.existingBuildings];

  edgeSegments.forEach((outgoingSegment, cornerIndex) => {
    const incomingSegment = edgeSegments[(cornerIndex - 1 + edgeSegments.length) % edgeSegments.length];
    const cornerFrontages = [
      { curve: getCornerFrontage(incomingSegment, 'end', options.settings), label: 'incoming' },
      { curve: getCornerFrontage(outgoingSegment, 'start', options.settings), label: 'outgoing' },
    ];

    cornerFrontages.forEach((frontage) => {
      if (!frontage.curve || frontage.curve.length < 2) return;

      const building = tryCreateClosedCornerBuilding({
        frontCurve: frontage.curve,
        boundary: options.boundary,
        settings: options.settings,
        occupied,
        forbiddenPolygons: options.forbiddenPolygons,
        usedIds: options.usedIds,
        seed: `${options.seed}:corner:${cornerIndex}:${frontage.label}`,
      });

      if (!building) return;
      generated.push(building);
      occupied.push(building);
    });
  });

  return generated;
}

function generateClosedBoundaryBuildings(options: {
  boundary: FillBoundary;
  settings: BuildingFillSettings;
  existingBuildings: BuildingPolygon[];
  forbiddenPolygons: Point[][];
  usedIds: Set<string>;
  seed: string;
}) {
  const generated: BuildingPolygon[] = [];
  const cornerBuildings = generateClosedCornerBuildings({
    boundary: options.boundary,
    settings: options.settings,
    existingBuildings: options.existingBuildings,
    forbiddenPolygons: options.forbiddenPolygons,
    usedIds: options.usedIds,
    seed: `${options.seed}:corners`,
  });
  generated.push(...cornerBuildings);

  const edgeBlockingBuildings = [...options.existingBuildings, ...cornerBuildings];
  const boundaryRuns = splitClosedBoundaryIntoRuns(options.boundary.polygon);

  boundaryRuns.forEach((boundaryRun, runIndex) => {
    const totalLength = getPolylineLength(boundaryRun);
    if (boundaryRun.length < 2 || totalLength < MIN_CURVE_LENGTH) return;

    const buildingCount = getFillSegmentCount(totalLength, options.settings);
    const segmentLength = totalLength / buildingCount;

    for (let index = 0; index < buildingCount; index++) {
      const startDistance = index * segmentLength;
      const endDistance = index === buildingCount - 1 ? totalLength : (index + 1) * segmentLength;
      const frontCurve = slicePolyline(boundaryRun, startDistance, endDistance);
      if (frontCurve.length < 2) continue;

      const side = chooseInteriorSide(frontCurve, options.boundary);
      const buildingSeed = `${options.seed}:${runIndex}:${index}`;
      const depthRandom = createRandom(`${buildingSeed}:depth`);
      const requestedDepth = randomRange(depthRandom, options.settings.minWidth, options.settings.maxWidth);
      let acceptedVertices: Point[] | null = null;

      for (const depth of buildDepthCandidates(requestedDepth, options.settings)) {
        if (depth < 4) continue;
        const vertices = buildStripCandidate(frontCurve, side, depth);
        if (!isValidBuildingFootprint(vertices)) continue;
        if (!meetsMinimumFootprintSize(vertices, options.settings)) continue;
        if (!buildingFitsInsideBoundary(vertices, options.boundary.polygon)) continue;
        if (hasForbiddenOverlap(vertices, options.forbiddenPolygons)) continue;
        if (hasBuildingOverlap(vertices, edgeBlockingBuildings)) continue;
        acceptedVertices = vertices;
        break;
      }

      if (!acceptedVertices) continue;

      const heightRandom = createRandom(`${buildingSeed}:height`);
      const building: BuildingPolygon = {
        id: makeBuildingId(buildingSeed, options.usedIds),
        vertices: acceptedVertices,
        baseZ: getBuildingFillBaseZ(frontCurve, acceptedVertices),
        height: Math.round(randomRange(heightRandom, options.settings.minHeight, options.settings.maxHeight)),
        color: DEFAULTS.buildingColor,
        material: DEFAULTS.buildingMaterial,
      };
      generated.push(building);
    }
  });

  return generated;
}

function findEdgeBetween(edges: Edge[], sourceId: string, targetId: string) {
  return edges.find((edge) => (
    (edge.source === sourceId && edge.target === targetId) ||
    (edge.source === targetId && edge.target === sourceId)
  ));
}

function getFaceEdgeIds(face: string[], edges: Edge[]) {
  const edgeIds: string[] = [];
  for (let index = 0; index < face.length; index++) {
    const edge = findEdgeBetween(edges, face[index], face[(index + 1) % face.length]);
    if (!edge) return [];
    edgeIds.push(edge.id);
  }
  return edgeIds;
}

function getSelectedTargetEdges(edges: Edge[], selectedNodes: string[], selectedEdges: string[]) {
  const selectedNodeSet = new Set(selectedNodes);
  const selectedEdgeIds = new Set(selectedEdges);

  edges.forEach((edge) => {
    if (edge.target && selectedNodeSet.has(edge.source) && selectedNodeSet.has(edge.target)) {
      selectedEdgeIds.add(edge.id);
    }
  });

  return edges.filter((edge) => selectedEdgeIds.has(edge.id));
}

function getClosedFaces(nodes: Node[], edges: Edge[], selectedNodes: string[], selectedEdges: string[]) {
  const selectedNodeSet = new Set(selectedNodes);
  const selectedEdgeSet = new Set(selectedEdges);
  const faces = findClosedAreas(nodes, edges);

  return faces.filter((face) => {
    const edgeIds = getFaceEdgeIds(face, edges);
    if (edgeIds.length !== face.length) return false;

    if (selectedEdgeSet.size > 0 && edgeIds.every((edgeId) => selectedEdgeSet.has(edgeId))) {
      return true;
    }

    return (
      selectedEdgeSet.size === 0 &&
      selectedNodeSet.size === face.length &&
      face.every((nodeId) => selectedNodeSet.has(nodeId))
    );
  });
}

function getRoadPolygonMap(mesh: MeshData) {
  return new Map(mesh.roadPolygons.map((roadPolygon) => [roadPolygon.id, roadPolygon]));
}

function orientCurve(curve: Point[], edge: Edge, fromNodeId: string) {
  return edge.source === fromNodeId ? [...curve] : [...curve].reverse();
}

function getAverageDistanceToPoint(curve: Point[], point: Point) {
  if (curve.length === 0) return Infinity;
  const total = curve.reduce((sum, curvePoint) => (
    sum + Math.hypot(curvePoint.x - point.x, curvePoint.y - point.y)
  ), 0);
  return total / curve.length;
}

function getInsidePointCount(curve: Point[], boundary: FillBoundary) {
  return curve.reduce((count, point) => count + (pointInPolygon(point, boundary.polygon) ? 1 : 0), 0);
}

function chooseInteriorCurve(roadPolygon: RoadPolygon, boundary: FillBoundary) {
  const leftInside = getInsidePointCount(roadPolygon.outerLeftCurve, boundary);
  const rightInside = getInsidePointCount(roadPolygon.outerRightCurve, boundary);
  if (leftInside !== rightInside) {
    return leftInside > rightInside
      ? { curve: roadPolygon.outerLeftCurve, side: 'left' as CurveSide }
      : { curve: roadPolygon.outerRightCurve, side: 'right' as CurveSide };
  }

  const leftDistance = getAverageDistanceToPoint(roadPolygon.outerLeftCurve, boundary.centroid);
  const rightDistance = getAverageDistanceToPoint(roadPolygon.outerRightCurve, boundary.centroid);
  return leftDistance <= rightDistance
    ? { curve: roadPolygon.outerLeftCurve, side: 'left' as CurveSide }
    : { curve: roadPolygon.outerRightCurve, side: 'right' as CurveSide };
}

function getFaceBoundary(face: string[], nodeById: Map<string, Node>): FillBoundary | null {
  const polygon = face
    .map((nodeId) => nodeById.get(nodeId)?.point)
    .filter((point): point is Point => !!point);

  if (polygon.length < 3) return null;
  return {
    polygon,
    centroid: polygonCentroid(polygon),
  };
}

function polygonSignedArea(polygon: Point[]) {
  let signedArea = 0;
  for (let index = 0; index < polygon.length; index++) {
    const current = polygon[index];
    const next = polygon[(index + 1) % polygon.length];
    signedArea += current.x * next.y - next.x * current.y;
  }
  return signedArea;
}

function cleanBoundaryPoints(points: Point[]) {
  const cleaned: Point[] = [];
  for (const point of points) {
    if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) continue;
    const previous = cleaned[cleaned.length - 1];
    if (previous && pointDistance(previous, point) <= BOUNDARY_EPSILON) continue;
    cleaned.push(point);
  }

  if (cleaned.length > 2 && pointDistance(cleaned[0], cleaned[cleaned.length - 1]) <= BOUNDARY_EPSILON) {
    cleaned.pop();
  }

  return cleaned;
}

function findInteriorPoint(polygon: Point[]) {
  const centroid = polygonCentroid(polygon);
  if (pointInPolygon(centroid, polygon)) return centroid;

  for (let index = 1; index < polygon.length - 1; index++) {
    const candidate = averagePoint([polygon[0], polygon[index], polygon[index + 1]]);
    if (pointInPolygon(candidate, polygon)) return candidate;
  }

  return averagePoint(polygon);
}

function buildClosedSidewalkBoundary(
  face: string[],
  nodeById: Map<string, Node>,
  edges: Edge[],
  roadPolygonById: Map<string, RoadPolygon>,
  mesh: MeshData
): FillBoundary | null {
  const centerlineBoundary = getFaceBoundary(face, nodeById);
  if (!centerlineBoundary) return null;

  const isClockwise = polygonSignedArea(centerlineBoundary.polygon) > 0;
  const segments: Point[][] = [];

  for (let index = 0; index < face.length; index++) {
    const fromNodeId = face[index];
    const toNodeId = face[(index + 1) % face.length];
    const edge = findEdgeBetween(edges, fromNodeId, toNodeId);
    const roadPolygon = edge ? roadPolygonById.get(edge.id) : null;
    if (!edge || !roadPolygon || roadPolygon.ignoreMeshing) return null;

    const interior = chooseInteriorCurve(roadPolygon, centerlineBoundary);
    segments.push(orientCurve(interior.curve, edge, fromNodeId));
  }

  const boundaryPoints: Point[] = [];
  for (let index = 0; index < segments.length; index++) {
    const curve = segments[index];
    const nextCurve = segments[(index + 1) % segments.length];
    boundaryPoints.push(...curve);

    const endPoint = curve[curve.length - 1];
    const startPoint = nextCurve[0];
    const hubNodeId = face[(index + 1) % face.length];
    const hub = mesh.hubs.find((item) => item.id === hubNodeId);

    if (hub && hub.outerPolygon.length > 0) {
      boundaryPoints.push(...buildHubBoundaryPath(
        hub.outerPolygon,
        endPoint,
        startPoint,
        isClockwise,
        hub.corners.length === 1
      ));
    }
  }

  const polygon = cleanBoundaryPoints(boundaryPoints);
  if (polygon.length < 3) return null;

  return {
    polygon,
    centroid: findInteriorPoint(polygon),
    edgeSegments: segments,
  };
}

export function generateBuildingFill(params: BuildingFillParams): BuildingFillResult {
  const settings = sanitizeBuildingFillSettings(params.settings);
  const seedPrefix = params.seedSalt ? `fill:${params.seedSalt}` : 'fill:default';
  const mesh = buildNetworkMesh(
    params.nodes,
    params.edges,
    params.chamferAngle,
    params.meshResolution,
    params.laneWidth,
    [],
    []
  );
  const roadPolygonById = getRoadPolygonMap(mesh);
  const forbiddenClosedFillPolygons = [
    ...mesh.hubs.map((hub) => hub.outerPolygon),
    ...mesh.roadPolygons.map((roadPolygon) => roadPolygon.outerPolygon),
    ...mesh.crosswalks.map((crosswalk) => crosswalk.polygon),
  ].filter((polygon) => polygon.length >= 3);
  const nodeById = new Map(params.nodes.map((node) => [node.id, node]));
  const usedIds = new Set(params.buildings.map((building) => building.id));
  const selectedTargetEdges = getSelectedTargetEdges(params.edges, params.selectedNodes, params.selectedEdges);
  const closedFaces = getClosedFaces(params.nodes, params.edges, params.selectedNodes, params.selectedEdges);
  const generated: BuildingPolygon[] = [];

  if (closedFaces.length > 0) {
    closedFaces.forEach((face, faceIndex) => {
      const boundary = buildClosedSidewalkBoundary(face, nodeById, params.edges, roadPolygonById, mesh);
      if (!boundary) return;

      const buildings = generateClosedBoundaryBuildings({
        boundary,
        settings,
        existingBuildings: params.buildings,
        forbiddenPolygons: forbiddenClosedFillPolygons,
        usedIds,
        seed: `${seedPrefix}:closed:${face.join('-')}:${faceIndex}`,
      });
      generated.push(...buildings);
    });

    return {
      buildings: generated,
      mode: generated.length > 0 ? 'closed' : 'none',
    };
  }

  selectedTargetEdges.forEach((edge) => {
    const roadPolygon = roadPolygonById.get(edge.id);
    if (!roadPolygon || roadPolygon.ignoreMeshing) return;

    const leftBuildings = generateBuildingsAlongCurve({
      curve: roadPolygon.outerLeftCurve,
      side: 'left',
      settings,
      existingBuildings: params.buildings,
      forbiddenPolygons: forbiddenClosedFillPolygons,
      usedIds,
      seed: `${seedPrefix}:open:${edge.id}:left`,
    });
    generated.push(...leftBuildings);

    const rightBuildings = generateBuildingsAlongCurve({
      curve: roadPolygon.outerRightCurve,
      side: 'right',
      settings,
      existingBuildings: params.buildings,
      forbiddenPolygons: forbiddenClosedFillPolygons,
      usedIds,
      seed: `${seedPrefix}:open:${edge.id}:right`,
    });
    generated.push(...rightBuildings);
  });

  return {
    buildings: generated,
    mode: generated.length > 0 ? 'open' : 'none',
  };
}
