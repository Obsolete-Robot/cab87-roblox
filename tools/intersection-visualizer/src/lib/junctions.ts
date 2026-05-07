import { DEFAULTS } from './constants';
import { Point, Node, Edge } from "./types";
import { getDir } from "./math";
import { getEdgeControlPoints, getIncidentConnections } from "./network";

/**
 * Calculates a corner intersection between two road boundaries.
 */
export function calculateBothCornerPoints(
  center: Point,
  dir1: Point,
  width1: number,
  sw1: number,
  smoothness1: number,
  dir2: Point,
  width2: number,
  sw2: number,
  smoothness2: number,
  chamferAngleDeg: number
): [Point[], Point[]] {
  const right1 = { x: -dir1.y, y: dir1.x };
  const left2 = { x: dir2.y, y: -dir2.x };

  const W1 = width1 / 2;
  const W2 = width2 / 2;
  const OW1 = W1 + sw1;
  const OW2 = W2 + sw2;

  const A = { x: center.x + right1.x * W1, y: center.y + right1.y * W1, z: center.z };
  const B = { x: center.x + left2.x * W2, y: center.y + left2.y * W2, z: center.z };
  const OA = { x: center.x + right1.x * OW1, y: center.y + right1.y * OW1, z: center.z };
  const OB = { x: center.x + left2.x * OW2, y: center.y + left2.y * OW2, z: center.z };

  const cross = dir1.x * dir2.y - dir1.y * dir2.x;

  if (Math.abs(cross) > 0.001) {
    const dx = B.x - A.x;
    const dy = B.y - A.y;
    const t = (dx * dir2.y - dy * dir2.x) / cross;
    const u = (dx * dir1.y - dy * dir1.x) / cross;

    const odx = OB.x - OA.x;
    const ody = OB.y - OA.y;
    const ot = (odx * dir2.y - ody * dir2.x) / cross;
    const ou = (odx * dir1.y - ody * dir1.x) / cross;

    const dot = dir1.x * dir2.x + dir1.y * dir2.y;
    let interiorAngle = Math.atan2(cross, dot);
    if (interiorAngle < 0) interiorAngle += 2 * Math.PI;
    const interiorAngleDeg = interiorAngle * 180 / Math.PI;

    const isSharp = interiorAngleDeg < chamferAngleDeg || interiorAngleDeg > (360 - chamferAngleDeg);
    const isNearlyStraight = interiorAngleDeg > 150 && interiorAngleDeg < 210;

    let finalT = t;
    let finalU = u;
    let finalOT = ot;
    let finalOU = ou;

    if (isSharp || isNearlyStraight) {
        const maxDistInner = Math.max(W1, W2) * 1.5;
        const maxDistOuter = Math.max(OW1, OW2) * 1.5;

        const straightCapInner = Math.max(W1, W2) * 0.1;
        const straightCapOuter = Math.max(OW1, OW2) * 0.1;

        const spikeCapT = Math.max(W1, W2) * 5;
        const spikeCapOT = Math.max(OW1, OW2) * 5;

        // For sharp corners, cap negative distances to prevent backwards spikes, and cap positive distances to prevent infinite spikes
        // For nearly straight lines, cap both ways stringently to prevent infinite junction sizes from slightly offset/mismatched roads
        const capT = isNearlyStraight ? Math.max(-straightCapInner, Math.min(t, straightCapInner)) : (t < 0 ? Math.max(t, -maxDistInner) : Math.min(t, spikeCapT));
        const capU = isNearlyStraight ? Math.max(-straightCapInner, Math.min(u, straightCapInner)) : (u < 0 ? Math.max(u, -maxDistInner) : Math.min(u, spikeCapT));
        const capOT = isNearlyStraight ? Math.max(-straightCapOuter, Math.min(ot, straightCapOuter)) : (ot < 0 ? Math.max(ot, -maxDistOuter) : Math.min(ot, spikeCapOT));
        const capOU = isNearlyStraight ? Math.max(-straightCapOuter, Math.min(ou, straightCapOuter)) : (ou < 0 ? Math.max(ou, -maxDistOuter) : Math.min(ou, spikeCapOT));

        finalT = capT + smoothness1;
        finalU = capU + smoothness2;
        finalOT = capOT + smoothness1;
        finalOU = capOU + smoothness2;
    } else {
        finalT = t + smoothness1;
        finalU = u + smoothness2;
        finalOT = ot + smoothness1;
        finalOU = ou + smoothness2;
    }

    const A_inner = { x: A.x + finalT * dir1.x, y: A.y + finalT * dir1.y, z: center.z };
    const B_inner = { x: B.x + finalU * dir2.x, y: B.y + finalU * dir2.y, z: center.z };

    // Keep chamfered sidewalk width constant by making the outer chamfer line parallel to the inner one.
    let OA_outer = { x: OA.x + finalOT * dir1.x, y: OA.y + finalOT * dir1.y, z: center.z };
    let OB_outer = { x: OB.x + finalOU * dir2.x, y: OB.y + finalOU * dir2.y, z: center.z };

    const V = { x: B_inner.x - A_inner.x, y: B_inner.y - A_inner.y };
    const L = Math.hypot(V.x, V.y);

    if (L > 1e-4 && (finalT !== t || finalU !== u)) {
        let N = { x: V.y / L, y: -V.x / L };
        const M = { x: (A_inner.x + B_inner.x) / 2, y: (A_inner.y + B_inner.y) / 2 };
        const MC = { x: M.x - center.x, y: M.y - center.y };
        if (N.x * MC.x + N.y * MC.y < 0) {
            N.x = -N.x;
            N.y = -N.y;
        }

        const sw = Math.max(sw1, sw2);
        const P = { x: M.x + N.x * sw, y: M.y + N.y * sw };

        const det1 = V.x * dir1.y - V.y * dir1.x;
        if (Math.abs(det1) > 1e-5) {
            const a = ((P.y - OA.y) * V.x - (P.x - OA.x) * V.y) / det1;
            OA_outer = { x: OA.x + a * dir1.x, y: OA.y + a * dir1.y, z: center.z };
            finalOT = a;
        }

        const det2 = V.x * dir2.y - V.y * dir2.x;
        if (Math.abs(det2) > 1e-5) {
            const c = ((P.y - OB.y) * V.x - (P.x - OB.x) * V.y) / det2;
            OB_outer = { x: OB.x + c * dir2.x, y: OB.y + c * dir2.y, z: center.z };
            finalOU = c;
        }
    }

      if (finalT !== t || finalU !== u || finalOT !== ot || finalOU !== ou) {
        return [
          [A_inner, B_inner],
          [OA_outer, OB_outer]
        ];
      }

      return [
        [{ x: A.x + t * dir1.x, y: A.y + t * dir1.y, z: center.z }],
        [{ x: OA.x + ot * dir1.x, y: OA.y + ot * dir1.y, z: center.z }]
      ];
  }

  return [
    [
      { x: A.x + smoothness1 * dir1.x, y: A.y + smoothness1 * dir1.y, z: center.z },
      { x: B.x + smoothness2 * dir2.x, y: B.y + smoothness2 * dir2.y, z: center.z }
    ],
    [
      { x: OA.x + smoothness1 * dir1.x, y: OA.y + smoothness1 * dir1.y, z: center.z },
      { x: OB.x + smoothness2 * dir2.x, y: OB.y + smoothness2 * dir2.y, z: center.z }
    ]
  ];
}

export function getEdgeClearance(nodeId: string, edge: Edge, isSourceQuery: boolean, nodes: Node[], edges: Edge[], chamferAngleDeg: number): number {
  const node = nodes.find(n => n.id === nodeId);
  if (!node) return 0;

  const conns = getIncidentConnections(nodeId, edges);
  if (conns.length === 0) return 0;

  const outgoing = conns.map(c => {
    const isSource = c.isSource;
    const e = c.edge;
    const controlPts = getEdgeControlPoints(e, nodes);
    const p1 = node.point;
    let p2 = isSource ? controlPts[1] : controlPts[controlPts.length - 2];
    if (!p2) p2 = p1; // Fallback if controlPts is too short
    const dir = getDir(p1, p2);
    const angle = Math.atan2(dir.y, dir.x);
    return { edge: e, angle, isSource, dir };
  }).sort((a, b) => a.angle - b.angle);

  const N = outgoing.length;
  const corners: Point[][] = [];
  const outerCorners: Point[][] = [];

  for (let i = 0; i < N; i++) {
      const r1 = outgoing[i];
      const r2 = outgoing[(i + 1) % N];

      const sw1 = r1.isSource ? (r1.edge.sidewalkRight ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth) : (r1.edge.sidewalkLeft ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth);
      const sw2 = r2.isSource ? (r2.edge.sidewalkLeft ?? r2.edge.sidewalk ?? DEFAULTS.sidewalkWidth) : (r2.edge.sidewalkRight ?? r2.edge.sidewalk ?? DEFAULTS.sidewalkWidth);

      if (N === 1) {
          const sw_left = r1.isSource ? (r1.edge.sidewalkLeft ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth) : (r1.edge.sidewalkRight ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth);
          const sw_right = r1.isSource ? (r1.edge.sidewalkRight ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth) : (r1.edge.sidewalkLeft ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth);
          const left = { x: r1.dir.y, y: -r1.dir.x };
          const right = { x: -r1.dir.y, y: r1.dir.x };
          const W = r1.edge.width / 2;
          const OW_L = W + sw_left;
          const OW_R = W + sw_right;
          corners.push([
            { x: node.point.x + left.x * W, y: node.point.y + left.y * W, z: node.point.z },
            { x: node.point.x + right.x * W, y: node.point.y + right.y * W, z: node.point.z }
          ]);
          outerCorners.push([
              { x: node.point.x + left.x * OW_L, y: node.point.y + left.y * OW_L, z: node.point.z },
              { x: node.point.x + right.x * OW_R, y: node.point.y + right.y * OW_R, z: node.point.z }
          ]);
      } else {
          const [innerPts, outerPts] = calculateBothCornerPoints(
            node.point,
            r1.dir, r1.edge.width, sw1, (r1.edge.transitionSmoothness ?? 0) + (node.transitionSmoothness ?? 0),
            r2.dir, r2.edge.width, sw2, (r2.edge.transitionSmoothness ?? 0) + (node.transitionSmoothness ?? 0),
            chamferAngleDeg
          );
          corners.push(innerPts);
          outerCorners.push(outerPts);
      }
  }

  const outIdx = outgoing.findIndex(o => o.edge.id === edge.id && o.isSource === isSourceQuery);
  if (outIdx === -1) return 0;

  const r = outgoing[outIdx];
  const rPrevIdx = (outIdx - 1 + N) % N;

  const bL = N === 1 ? corners[0][0] : corners[rPrevIdx][corners[rPrevIdx].length - 1];
  const bR = N === 1 ? corners[0][1] : corners[outIdx][0];
  const obL = N === 1 ? outerCorners[0][0] : outerCorners[rPrevIdx][outerCorners[rPrevIdx].length - 1];
  const obR = N === 1 ? outerCorners[0][1] : outerCorners[outIdx][0];

  const dir0 = r.dir;
  const distL = (bL.x - node.point.x) * dir0.x + (bL.y - node.point.y) * dir0.y;
  const distR = (bR.x - node.point.x) * dir0.x + (bR.y - node.point.y) * dir0.y;

  const odistL = (obL.x - node.point.x) * dir0.x + (obL.y - node.point.y) * dir0.y;
  const odistR = (obR.x - node.point.x) * dir0.x + (obR.y - node.point.y) * dir0.y;

  return Math.max(distL, distR, odistL, odistR);
}
