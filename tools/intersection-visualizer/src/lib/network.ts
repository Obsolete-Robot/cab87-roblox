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

export function getIncidentConnections(nodeId: string, edges: Edge[]): { edge: Edge, isSource: boolean }[] {
  const conns: { edge: Edge, isSource: boolean }[] = [];
  for (const e of edges) {
    if (e.source === nodeId) conns.push({ edge: e, isSource: true });
    if (e.target === nodeId) conns.push({ edge: e, isSource: false });
  }
  return conns;
}

export function isTrueJunction(nodeId: string, nodes: Node[], edges: Edge[]): boolean {
  const conns = getIncidentConnections(nodeId, edges);
  if (conns.length > 2) return true;
  if (conns.length < 2) return false;

  const outgoing = conns.map(c => {
    const isSrc = c.isSource;
    const controlPts = getEdgeControlPoints(c.edge, nodes);
    const p1 = nodes.find(n => n.id === nodeId)!.point;
    const p2 = isSrc ? controlPts[1] : controlPts[controlPts.length - 2];

    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const len = Math.hypot(dx, dy);
    return len === 0 ? { x: 1, y: 0 } : { x: dx / len, y: dy / len };
  });

  const dot = outgoing[0].x * outgoing[1].x + outgoing[0].y * outgoing[1].y;
  return dot > -0.95;
}

export function hasCrosswalk(edgeId: string, isSource: boolean, nodes: Node[], edges: Edge[]): boolean {
  const edge = edges.find(e => e.id === edgeId);
  if (!edge) return false;
  const nodeId = isSource ? edge.source : edge.target;
  if (!nodeId) return false;

  const conns = getIncidentConnections(nodeId, edges);
  if (conns.length > 2) return true;
  if (conns.length < 2) return false;

  const outgoing = conns.map(c => {
    const isSrc = c.isSource;
    const controlPts = getEdgeControlPoints(c.edge, nodes);
    const p1 = nodes.find(n => n.id === nodeId)!.point;
    const p2 = isSrc ? controlPts[1] : controlPts[controlPts.length - 2];

    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const len = Math.hypot(dx, dy);
    return { edgeId: c.edge.id, isSrc, vec: len === 0 ? { x: 1, y: 0 } : { x: dx / len, y: dy / len } };
  });

  const dot = outgoing[0].vec.x * outgoing[1].vec.x + outgoing[0].vec.y * outgoing[1].vec.y;

  if (dot < -0.95) return false;
  if (dot > -0.25) return true;

  const sortedConns = [
    `${outgoing[0].edgeId}_${outgoing[0].isSrc}`,
    `${outgoing[1].edgeId}_${outgoing[1].isSrc}`,
  ].sort();
  return `${edgeId}_${isSource}` === sortedConns[0];
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
  
  let W0 = getEdgeClearance(edge.source, edge, true, nodes, edges, chamferAngleDeg) + (isTrueJunction(edge.source, nodes, edges) ? 14 : 0);

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

  let WN = (edge.target ? getEdgeClearance(edge.target, edge, false, nodes, edges, chamferAngleDeg) : 0) + (edge.target && isTrueJunction(edge.target, nodes, edges) ? 14 : 0);

  if (basePts.length === 2 && WN > lenN / 2 - 5) {
      WN = Math.max(0, lenN / 2 - 5);
  } else if (basePts.length > 2 && WN > lenN - 5) {
      WN = Math.max(0, lenN - 5);
  }

  let cwN = pN;
  if (lenN > 0.1) {
      cwN = { x: pN.x + (dnX / lenN) * WN, y: pN.y + (dnY / lenN) * WN };
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
    res.push({ x: cw0.x + (cwN.x - cw0.x) / 3, y: cw0.y + (cwN.y - cw0.y) / 3 });
    res.push({ x: cw0.x + 2 * (cwN.x - cw0.x) / 3, y: cw0.y + 2 * (cwN.y - cw0.y) / 3 });
    res.push(cwN);

    res.push({ x: cwN.x + (pN.x - cwN.x) / 3, y: cwN.y + (pN.y - cwN.y) / 3 });
    res.push({ x: cwN.x + 2 * (pN.x - cwN.x) / 3, y: cwN.y + 2 * (pN.y - cwN.y) / 3 });
    res.push(pN);
  }

  return res;
}

export function sampleEdgeSpline(edge: Edge, nodes: Node[], edges: Edge[], chamferAngleDeg: number): Point[] {
  return sampleSpline(getExtendedEdgeControlPoints(edge, nodes, edges, chamferAngleDeg), 15);
}
