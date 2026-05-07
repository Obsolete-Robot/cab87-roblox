import { Point } from "./types";

export function getDir(from: Point, to: Point): Point {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const len = Math.hypot(dx, dy);
  return len === 0 ? { x: 1, y: 0 } : { x: dx / len, y: dy / len };
}

export function distToSegmentSquared(p: Point, v: Point, w: Point): number {
  const l2 = (w.x - v.x) ** 2 + (w.y - v.y) ** 2;
  if (l2 === 0) return (p.x - v.x) ** 2 + (p.y - v.y) ** 2;
  let t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2;
  t = Math.max(0, Math.min(1, t));
  return (p.x - (v.x + t * (w.x - v.x))) ** 2 + (p.y - (v.y + t * (w.y - v.y))) ** 2;
}

export function distToSegment(p: Point, v: Point, w: Point): number {
  return Math.sqrt(distToSegmentSquared(p, v, w));
}

export function segmentIntersect(p0: Point, p1: Point, p2: Point, p3: Point): Point | null {
    const s1_x = p1.x - p0.x;
    const s1_y = p1.y - p0.y;
    const s2_x = p3.x - p2.x;
    const s2_y = p3.y - p2.y;

    const denom = (-s2_x * s1_y + s1_x * s2_y);
    if (Math.abs(denom) < 1e-10) return null; // parallel or collinear

    const s = (-s1_y * (p0.x - p2.x) + s1_x * (p0.y - p2.y)) / denom;
    const t = (s2_x * (p0.y - p2.y) - s2_y * (p0.x - p2.x)) / denom;

    if (s >= 0 && s <= 1 && t >= 0 && t <= 1) {
        return {
            x: p0.x + (t * s1_x),
            y: p0.y + (t * s1_y),
            z: (p0.z || 0) + t * ((p1.z || 0) - (p0.z || 0))
        };
    }

    return null;
}

export function intersectSegmentPolygon(p1: Point, p2: Point, polygon: Point[]): Point | null {
    let closest: Point | null = null;
    let minDist = Infinity;
    for (let i = 0; i < polygon.length; i++) {
        const poly1 = polygon[i];
        const poly2 = polygon[(i + 1) % polygon.length];
        const intersection = segmentIntersect(p1, p2, poly1, poly2);
        if (intersection) {
            const dist = Math.hypot(intersection.x - p1.x, intersection.y - p1.y);
            if (dist < minDist) {
                minDist = dist;
                closest = intersection;
            }
        }
    }
    return closest;
}
