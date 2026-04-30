import { Point } from "./types";

export function cubicBezier(p0: Point, p1: Point, p2: Point, p3: Point, t: number): Point {
  const t2 = t * t;
  const t3 = t2 * t;
  const mt = 1 - t;
  const mt2 = mt * mt;
  const mt3 = mt2 * mt;

  return {
    x: p0.x * mt3 + 3 * p1.x * mt2 * t + 3 * p2.x * mt * t2 + p3.x * t3,
    y: p0.y * mt3 + 3 * p1.y * mt2 * t + 3 * p2.y * mt * t2 + p3.y * t3
  };
}

export function splitBezier(p0: Point, p1: Point, p2: Point, p3: Point, t: number) {
  const p01 = { x: p0.x*(1-t) + p1.x*t, y: p0.y*(1-t) + p1.y*t };
  const p12 = { x: p1.x*(1-t) + p2.x*t, y: p1.y*(1-t) + p2.y*t };
  const p23 = { x: p2.x*(1-t) + p3.x*t, y: p2.y*(1-t) + p3.y*t };
  const p012 = { x: p01.x*(1-t) + p12.x*t, y: p01.y*(1-t) + p12.y*t };
  const p123 = { x: p12.x*(1-t) + p23.x*t, y: p12.y*(1-t) + p23.y*t };
  const pMid = { x: p012.x*(1-t) + p123.x*t, y: p012.y*(1-t) + p123.y*t };

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
      res.push({ x: pA.x + (pB.x - pA.x)/3, y: pA.y + (pB.y - pA.y)/3 });
      res.push({ x: pA.x + 2*(pB.x - pA.x)/3, y: pA.y + 2*(pB.y - pA.y)/3 });
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

export function sampleSpline(points: Point[], segmentLength: number = 20): Point[] {
  const cubicPts = ensurePiecewiseCubic(points);
  if (cubicPts.length < 4) {
      // Fallback for line
      const res: Point[] = [];
      if (cubicPts.length === 0) return res;
      if (cubicPts.length === 1) return [cubicPts[0]];
      const dist = Math.hypot(cubicPts[1].x - cubicPts[0].x, cubicPts[1].y - cubicPts[0].y);
      const segments = Math.max(1, Math.ceil(dist / segmentLength));
      for(let step = 0; step <= segments; step++) {
          const t = step / segments;
          res.push({
              x: cubicPts[0].x*(1-t) + cubicPts[1].x*t, 
              y: cubicPts[0].y*(1-t) + cubicPts[1].y*t,
              t, curveIndex: 0 
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
      const len = bezierLength(p0, p1, p2, p3);
      const segments = Math.max(1, Math.ceil(len / segmentLength));
      
      for (let step = 0; step <= segments; step++) {
          if (i > 0 && step === 0) continue;
          const t = step / segments;
          const pt = cubicBezier(p0, p1, p2, p3, t);
          pt.t = t;
          pt.curveIndex = curveIndex;
          result.push(pt);
      }
  }
  return result;
}
