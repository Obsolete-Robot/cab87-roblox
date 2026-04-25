import { Point } from "./types";

export function getDir(from: Point, to: Point): Point {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const len = Math.hypot(dx, dy);
  return len === 0 ? { x: 1, y: 0 } : { x: dx / len, y: dy / len };
}

/**
 * Calculates a corner intersection between two road boundaries.
 */
export function calculateCornerPoints(
  center: Point,
  dir1: Point,
  width1: number,
  dir2: Point,
  width2: number
): Point[] {
  const right1 = { x: -dir1.y, y: dir1.x };
  const left2 = { x: dir2.y, y: -dir2.x };

  const W1 = width1 / 2;
  const W2 = width2 / 2;

  const A = { x: center.x + right1.x * W1, y: center.y + right1.y * W1 };
  const B = { x: center.x + left2.x * W2, y: center.y + left2.y * W2 };

  const cross = dir1.x * dir2.y - dir1.y * dir2.x;
  let pts: Point[] = [];

  // If roads are not near-parallel
  if (Math.abs(cross) > 0.05) {
    const dx = B.x - A.x;
    const dy = B.y - A.y;
    const t = (dx * dir2.y - dy * dir2.x) / cross;
    const u = (dx * dir1.y - dy * dir1.x) / cross;

    // Ensure intersection is not backwards (too much) or infinitely far away
    if (t > -W1 && u > -W2 && t < 1000 && u < 1000) {
      pts.push({ x: A.x + t * dir1.x, y: A.y + t * dir1.y });
    } else {
      pts.push(A, B);
    }
  } else {
    // Fallback for near-parallel or acute angles
    pts.push(A, B);
  }

  return pts;
}
