import { Point } from "./types";

const DEFAULT_SEGMENT_LENGTH = 20;

export function cubicBezier(p0: Point, p1: Point, p2: Point, p3: Point, t: number): Point {
  const t2 = t * t;
  const t3 = t2 * t;
  const mt = 1 - t;
  const mt2 = mt * mt;
  const mt3 = mt2 * mt;

  return {
    x: p0.x * mt3 + 3 * p1.x * mt2 * t + 3 * p2.x * mt * t2 + p3.x * t3,
    y: p0.y * mt3 + 3 * p1.y * mt2 * t + 3 * p2.y * mt * t2 + p3.y * t3,
    z: (p0.z ?? 4) * mt3 + 3 * (p1.z ?? 4) * mt2 * t + 3 * (p2.z ?? 4) * mt * t2 + (p3.z ?? 4) * t3
  };
}

export function splitBezier(p0: Point, p1: Point, p2: Point, p3: Point, t: number) {
  const p01 = { x: p0.x*(1-t) + p1.x*t, y: p0.y*(1-t) + p1.y*t, z: (p0.z ?? 4)*(1-t) + (p1.z ?? 4)*t };
  const p12 = { x: p1.x*(1-t) + p2.x*t, y: p1.y*(1-t) + p2.y*t, z: (p1.z ?? 4)*(1-t) + (p2.z ?? 4)*t };
  const p23 = { x: p2.x*(1-t) + p3.x*t, y: p2.y*(1-t) + p3.y*t, z: (p2.z ?? 4)*(1-t) + (p3.z ?? 4)*t };
  const p012 = { x: p01.x*(1-t) + p12.x*t, y: p01.y*(1-t) + p12.y*t, z: (p01.z ?? 4)*(1-t) + (p12.z ?? 4)*t };
  const p123 = { x: p12.x*(1-t) + p23.x*t, y: p12.y*(1-t) + p23.y*t, z: (p12.z ?? 4)*(1-t) + (p23.z ?? 4)*t };
  const pMid = { x: p012.x*(1-t) + p123.x*t, y: p012.y*(1-t) + p123.y*t, z: (p012.z ?? 4)*(1-t) + (p123.z ?? 4)*t };

  return { p01, p12, p23, p012, p123, pMid };
}

export function ensurePiecewiseCubic(points: Point[]): Point[] {
  if (points.length < 2) return points;
  if (points.length % 3 === 1) return points; // Already cubic piecewise

  // Convert straight lines or Catmull-Rom into Bezier
  const res: Point[] = [points[0]];
  for (let i = 0; i < points.length - 1; i++) {
      const pA = points[i];
      const pB = points[i+1];
      // Just straight lines between them using control points at 1/3 and 2/3
      res.push({ x: pA.x + (pB.x - pA.x)/3, y: pA.y + (pB.y - pA.y)/3, z: (pA.z ?? 4) + ((pB.z ?? 4) - (pA.z ?? 4))/3 });
      res.push({ x: pA.x + 2*(pB.x - pA.x)/3, y: pA.y + 2*(pB.y - pA.y)/3, z: (pA.z ?? 4) + 2*((pB.z ?? 4) - (pA.z ?? 4))/3 });
      res.push(pB);
  }
  return res;
}

export function bezierLength(p0: Point, p1: Point, p2: Point, p3: Point): number {
  let length = 0;
  let prev = p0;
  const steps = 15;

  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    const curr = cubicBezier(p0, p1, p2, p3, t);
    length += Math.hypot(curr.x - prev.x, curr.y - prev.y);
    prev = curr;
  }

  return length;
}

export function sampleSpline(points: Point[], segmentLength: number = DEFAULT_SEGMENT_LENGTH): Point[] {
  const safeSegmentLength = Math.max(Number.isFinite(segmentLength) ? segmentLength : DEFAULT_SEGMENT_LENGTH, 1);
  const cubicPts = ensurePiecewiseCubic(points);
  if (cubicPts.length < 4) {
      // Fallback for line
      const res: Point[] = [];
      if (cubicPts.length === 0) return res;
      if (cubicPts.length === 1) return [cubicPts[0]];
      const distance = Math.hypot(cubicPts[1].x - cubicPts[0].x, cubicPts[1].y - cubicPts[0].y);
      const segments = Math.max(1, Math.ceil(distance / safeSegmentLength));
      for(let step = 0; step <= segments; step++) {
          const t = step / segments;
          res.push({
              x: cubicPts[0].x*(1-t) + cubicPts[1].x*t, 
              y: cubicPts[0].y*(1-t) + cubicPts[1].y*t,
              z: (cubicPts[0].z ?? 4)*(1-t) + (cubicPts[1].z ?? 4)*t,
              curveIndex: 0,
              t
          });
      }
      return res;
  }
  
  const result: Point[] = [];
  for (let i = 0; i < cubicPts.length - 1; i += 3) {
      const p0 = cubicPts[i];
      const p1 = cubicPts[i+1];
      const p2 = cubicPts[i+2];
      const p3 = cubicPts[i+3];
      const curveIndex = i / 3;
      const segments = Math.max(1, Math.ceil(bezierLength(p0, p1, p2, p3) / safeSegmentLength));
      
      for (let step = 0; step <= segments; step++) {
          if (i > 0 && step === 0) continue;
          const t = step / segments;
          result.push({
            ...cubicBezier(p0, p1, p2, p3, t),
            curveIndex,
            t
          });
      }
  }
  return result;
}
