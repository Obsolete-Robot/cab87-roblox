import { Point, Road, JunctionData } from "./types";
import { getDir, calculateCornerPoints } from "./math";

/**
 * High-level logic to calculate the structure of a junction.
 * This identifies the logical arrangement of roads and their intersection points.
 */
export function buildJunction(center: Point, roads: Road[]): JunctionData {
  const sortedRoads = roads
    .map((r) => ({
      ...r,
      angle: Math.atan2(r.end.y - center.y, r.end.x - center.x),
    }))
    .sort((a, b) => a.angle - b.angle);

  const N = sortedRoads.length;
  const corners: Point[][] = [];

  // 1. Find intersection points between adjacent roads
  for (let i = 0; i < N; i++) {
    const r1 = sortedRoads[i];
    const r2 = sortedRoads[(i + 1) % N];

    const dir1 = getDir(center, r1.end);
    const dir2 = getDir(center, r2.end);

    const pts = calculateCornerPoints(center, dir1, r1.width, dir2, r2.width);
    corners.push(pts);
  }

  return {
    center,
    roads,
    sortedRoads,
    corners,
  };
}
