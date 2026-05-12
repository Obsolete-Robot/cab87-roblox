import { DEFAULTS } from './constants';
import { BuildingPolygon, Point } from './types';

function finiteNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

export function getLowestPointZ(points: Point[] | undefined, fallback = DEFAULTS.buildingBaseZ) {
  let lowest: number | undefined;
  for (const point of points ?? []) {
    const z = finiteNumber(point.z);
    if (z === undefined) continue;
    lowest = lowest === undefined ? z : Math.min(lowest, z);
  }

  return lowest ?? fallback;
}

export function getBuildingBaseZ(building: Pick<BuildingPolygon, 'baseZ'> & { vertices?: Point[] }) {
  return getLowestPointZ(building.vertices, building.baseZ ?? DEFAULTS.buildingBaseZ);
}

export function getBuildingHeight(building: Pick<BuildingPolygon, 'height'>) {
  return Math.max(1, building.height || DEFAULTS.buildingHeight);
}

export function getBuildingCenter(building: Pick<BuildingPolygon, 'vertices'>): Point {
  if (!building.vertices.length) return { x: 0, y: 0 };

  let signedArea = 0;
  let cx = 0;
  let cy = 0;

  for (let index = 0; index < building.vertices.length; index++) {
    const current = building.vertices[index];
    const next = building.vertices[(index + 1) % building.vertices.length];
    const cross = current.x * next.y - next.x * current.y;
    signedArea += cross;
    cx += (current.x + next.x) * cross;
    cy += (current.y + next.y) * cross;
  }

  if (Math.abs(signedArea) > 0.0001) {
    const factor = 1 / (3 * signedArea);
    return { x: cx * factor, y: cy * factor };
  }

  const sum = building.vertices.reduce((acc, vertex) => ({
    x: acc.x + vertex.x,
    y: acc.y + vertex.y,
  }), { x: 0, y: 0 });
  return { x: sum.x / building.vertices.length, y: sum.y / building.vertices.length };
}

export function pointInBuilding(point: Point, building: Pick<BuildingPolygon, 'vertices'>) {
  const vertices = building.vertices;
  if (vertices.length < 3) return false;

  let inside = false;
  for (let i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
    const pi = vertices[i];
    const pj = vertices[j];
    if (
      (pi.y > point.y) !== (pj.y > point.y) &&
      point.x < ((pj.x - pi.x) * (point.y - pi.y)) / (pj.y - pi.y) + pi.x
    ) {
      inside = !inside;
    }
  }
  return inside;
}

export function cleanBuildingVertices(vertices: Point[]) {
  const cleaned: Point[] = [];
  for (const vertex of vertices) {
    if (!Number.isFinite(vertex.x) || !Number.isFinite(vertex.y)) continue;
    const nextVertex: Point = { x: vertex.x, y: vertex.y };
    if (typeof vertex.z === 'number' && Number.isFinite(vertex.z)) {
      nextVertex.z = vertex.z;
    }

    const previous = cleaned[cleaned.length - 1];
    if (previous && Math.hypot(previous.x - nextVertex.x, previous.y - nextVertex.y) < 0.01) continue;
    cleaned.push(nextVertex);
  }

  if (cleaned.length > 2) {
    const first = cleaned[0];
    const last = cleaned[cleaned.length - 1];
    if (Math.hypot(first.x - last.x, first.y - last.y) < 0.01) {
      cleaned.pop();
    }
  }

  return cleaned;
}
