import { Point, Node, Edge } from "./types";
import { sampleSpline } from "./splines";
import { getEdgeClearance } from "./junctions";

export function getEdgeControlPoints(edge: Edge, nodes: Node[]): Point[] {
  const sourceNode = nodes.find(n => n.id === edge.source);
  if (!sourceNode) return [];
  const pts = [sourceNode.point, ...edge.points];
  if (edge.target) {
    const tgt = nodes.find(n => n.id === edge.target);
    if (tgt) pts.push(tgt.point);
  }
  return pts;
}

export function getExtendedEdgeControlPoints(edge: Edge, nodes: Node[], edges: Edge[], chamferAngleDeg: number): Point[] {
  const basePts = getEdgeControlPoints(edge, nodes);
  if (basePts.length < 2) return basePts;

  const res: Point[] = [];
  
  const p0 = basePts[0];
  const u1 = basePts[1];
  const d0x = u1.x - p0.x;
  const d0y = u1.y - p0.y;
  const len0 = Math.hypot(d0x, d0y);
  
  const sourceDegree = edges.filter(e => e.source === edge.source || e.target === edge.source).length;
  let W0 = getEdgeClearance(edge.source, edge, nodes, edges, chamferAngleDeg) + (sourceDegree > 1 ? 14 : 0);
  
  if (basePts.length === 2 && W0 > len0 / 2 - 5) {
      W0 = Math.max(0, len0 / 2 - 5);
  } else if (basePts.length > 2 && W0 > len0 - 5) {
      W0 = Math.max(0, len0 - 5);
  }
  
  // Straight line from p0 to cw0
  let cw0 = p0;
  if (len0 > 0.1) {
    cw0 = { x: p0.x + (d0x/len0)*W0, y: p0.y + (d0y/len0)*W0 };
  }
  
  res.push(p0);
  res.push({ x: p0.x + (cw0.x - p0.x)/3, y: p0.y + (cw0.y - p0.y)/3 });
  res.push({ x: p0.x + 2*(cw0.x - p0.x)/3, y: p0.y + 2*(cw0.y - p0.y)/3 });
  res.push(cw0);

  const pN = basePts[basePts.length - 1];
  const uLast = basePts[basePts.length - 2];
  const dnX = uLast.x - pN.x;
  const dnY = uLast.y - pN.y;
  const lenN = Math.hypot(dnX, dnY);
  
  const targetDegree = edge.target ? edges.filter(e => e.source === edge.target || e.target === edge.target).length : 0;
  let WN = (edge.target ? getEdgeClearance(edge.target, edge, nodes, edges, chamferAngleDeg) : 0) + (targetDegree > 1 ? 14 : 0);

  if (basePts.length === 2 && WN > lenN / 2 - 5) {
      WN = Math.max(0, lenN / 2 - 5);
  } else if (basePts.length > 2 && WN > lenN - 5) {
      WN = Math.max(0, lenN - 5);
  }

  let cwN = pN;
  if (lenN > 0.1) {
      cwN = { x: pN.x + (dnX/lenN)*WN, y: pN.y + (dnY/lenN)*WN };
  }

  // If there are middle points
  if (basePts.length > 2) {
    for (let i = 1; i < basePts.length - 1; i++) {
       res.push(basePts[i]);
    }
    
    res.push(cwN);
    res.push({ x: cwN.x + (pN.x - cwN.x)/3, y: cwN.y + (pN.y - cwN.y)/3 });
    res.push({ x: cwN.x + 2*(pN.x - cwN.x)/3, y: cwN.y + 2*(pN.y - cwN.y)/3 });
    res.push(pN);
  } else {
    // If just [N0, N1], len is 2.
    res.push({ x: cw0.x + (cwN.x - cw0.x)/3, y: cw0.y + (cwN.y - cw0.y)/3 });
    res.push({ x: cw0.x + 2*(cwN.x - cw0.x)/3, y: cw0.y + 2*(cwN.y - cw0.y)/3 });
    res.push(cwN);
    
    res.push({ x: cwN.x + (pN.x - cwN.x)/3, y: cwN.y + (pN.y - cwN.y)/3 });
    res.push({ x: cwN.x + 2*(pN.x - cwN.x)/3, y: cwN.y + 2*(pN.y - cwN.y)/3 });
    res.push(pN);
  }

  return res;
}

export function sampleEdgeSpline(edge: Edge, nodes: Node[], edges: Edge[], chamferAngleDeg: number): Point[] {
  return sampleSpline(getExtendedEdgeControlPoints(edge, nodes, edges, chamferAngleDeg), 15);
}
