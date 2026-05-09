import { DEFAULTS } from './constants';
import { Point, Node, Edge, PolygonFill, MeshData, Triangle } from "./types";
import { getDir, intersectSegmentPolygon, segmentIntersect } from "./math";
import { calculateBothCornerPoints } from "./junctions";
import { getEdgeControlPoints, sampleEdgeSpline, hasCrosswalk, isTrueJunction, getIncidentConnections } from "./network";
import * as THREE from 'three';

export function getEdgeBases(node: Node, sourceNode: Node, edge: Edge, isSource: boolean, nodeCorners: Map<string, Map<string, Point[]>>): [Point, Point] | null {
  const corners = nodeCorners.get(node.id);
  if (!corners) return null;
  const bases = corners.get(`${edge.id}_${isSource}`) || corners.get(edge.id);
  if (!bases || bases.length < 2) return null;
  return [bases[0], bases[1]];
}

function topFacingTriangle(a: Point, b: Point, c: Point): Triangle {
  const signedArea = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  return signedArea > 0 ? [a, c, b] : [a, b, c];
}

function closestPointOnSegment(point: Point, a: Point, b: Point) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lenSq = dx * dx + dy * dy;
  if (lenSq < 0.0001) {
    return {
      point: a,
      distance: Math.hypot(point.x - a.x, point.y - a.y),
      t: 0,
    };
  }

  const t = Math.max(0, Math.min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq));
  const closest = {
    x: a.x + dx * t,
    y: a.y + dy * t,
    z: (a.z ?? 4) + ((b.z ?? 4) - (a.z ?? 4)) * t,
  };

  return {
    point: closest,
    distance: Math.hypot(point.x - closest.x, point.y - closest.y),
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
  for (let i = 0; i < segmentCount; i++) {
    const closest = closestPointOnSegment(point, polygon[i], polygon[(i + 1) % polygon.length]);
    if (closest.distance < best.distance) {
      best = {
        point: closest.point,
        segmentIndex: i,
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
    for (let i = fromBoundary.segmentIndex + 1; i <= toBoundary.segmentIndex; i++) {
      path.push(hubPolygon[i]);
    }
  } else {
    for (let i = fromBoundary.segmentIndex; i > toBoundary.segmentIndex; i--) {
      path.push(hubPolygon[i]);
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

  return isClockwise ? backwardPath : forwardPath;
}

function intersectSegmentBoundary(p1: Point, p2: Point, boundary: Point[], closed = true): Point | null {
  let closest: Point | null = null;
  let minDist = Infinity;
  const segmentCount = closed ? boundary.length : Math.max(boundary.length - 1, 0);

  for (let i = 0; i < segmentCount; i++) {
    const intersection = segmentIntersect(p1, p2, boundary[i], boundary[(i + 1) % boundary.length]);
    if (!intersection) continue;

    const dist = Math.hypot(intersection.x - p1.x, intersection.y - p1.y);
    if (dist < minDist) {
      minDist = dist;
      closest = intersection;
    }
  }

  return closest;
}

function closestBoundaryPointToSegment(p1: Point, p2: Point, boundary: Point[], closed = true): Point | null {
  let closest: Point | null = null;
  let minDistance = Infinity;
  const segmentCount = closed ? boundary.length : Math.max(boundary.length - 1, 0);

  const consider = (point: Point, distance: number) => {
    if (distance < minDistance) {
      minDistance = distance;
      closest = point;
    }
  };

  for (let i = 0; i < segmentCount; i++) {
    const a = boundary[i];
    const b = boundary[(i + 1) % boundary.length];
    const p1ToBoundary = closestPointOnSegment(p1, a, b);
    const p2ToBoundary = closestPointOnSegment(p2, a, b);
    const aToSegment = closestPointOnSegment(a, p1, p2);
    const bToSegment = closestPointOnSegment(b, p1, p2);

    consider(p1ToBoundary.point, p1ToBoundary.distance);
    consider(p2ToBoundary.point, p2ToBoundary.distance);
    consider(a, aToSegment.distance);
    consider(b, bToSegment.distance);
  }

  return closest;
}

function intersectHubBoundarySegment(p1: Point, p2: Point, hub: MeshData['hubs'][number]): Point | null {
  if (hub.corners.length === 1) {
    return (
      intersectSegmentBoundary(p1, p2, hub.outerPolygon, false) ??
      closestBoundaryPointToSegment(p1, p2, hub.outerPolygon, false)
    );
  }

  return intersectSegmentPolygon(p1, p2, hub.outerPolygon);
}

export function buildNetworkMesh(nodes: Node[], edges: Edge[], chamferAngleDeg: number, meshResolution: number = DEFAULTS.meshResolution, laneWidth: number = DEFAULTS.laneWidth, polygonFills: PolygonFill[] = []): MeshData {
  const mesh: MeshData = {
    vertices: [],
    triangles: [],
    roadTriangles: [],
    hubTriangles: [],
    sidewalkTriangles: [],
    crosswalkTriangles: [],
    hubs: [],
    roadPolygons: [],
    crosswalks: [],
    sidewalkPolygons: [],
    dashedLines: [],
    solidYellowLines: [],
    dashedLineTriangles: [],
    solidLineTriangles: [],
    laneArrows: [],
    polygonTriangles: []
  };

  const edgeSplines = new Map<string, Point[]>();
  edges.forEach(e => edgeSplines.set(e.id, sampleEdgeSpline(e, nodes, edges, chamferAngleDeg, meshResolution)));

  const nodeClearances = new Map<string, Map<string, number>>();
  const nodeCorners = new Map<string, Map<string, Point[]>>();
  const nodeOuterCorners = new Map<string, Map<string, Point[]>>();

  const roadNodes = nodes.filter((node) => !node.ignoreMeshing);
  const roadEdges = edges.filter((edge) => {
    const source = nodes.find((node) => node.id === edge.source);
    const target = edge.target ? nodes.find((node) => node.id === edge.target) : null;
    return !(source?.ignoreMeshing || target?.ignoreMeshing);
  });

  // 1. Build Hubs
  for (const node of roadNodes) {
    const conns = getIncidentConnections(node.id, roadEdges);
    if (conns.length === 0) continue;

    const outgoing = conns.map(c => {
      const isSource = c.isSource;
      const e = c.edge;
      const controlPts = getEdgeControlPoints(e, nodes);
      const p1 = node.point;
      let p2 = isSource ? controlPts[1] : controlPts[controlPts.length - 2];
      if (!p2) p2 = node.point; // Fallback if controlPts is too short
      const dir = getDir(p1, p2);
      const angle = Math.atan2(dir.y, dir.x);
      return { edge: e, angle, isSource, dir };
    }).sort((a, b) => a.angle - b.angle);

    const N = outgoing.length;
    const corners: { points: Point[]; sidewalkWidth: number }[] = [];
    const outerCorners: Point[][] = [];

    for (let i = 0; i < N; i++) {
        const r1 = outgoing[i];
        const r2 = outgoing[(i + 1) % N];

        const sw1 = r1.isSource ? (r1.edge.sidewalkRight ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth) : (r1.edge.sidewalkLeft ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth);
        const sw2 = r2.isSource ? (r2.edge.sidewalkLeft ?? r2.edge.sidewalk ?? DEFAULTS.sidewalkWidth) : (r2.edge.sidewalkRight ?? r2.edge.sidewalk ?? DEFAULTS.sidewalkWidth);

        if (N === 1) {
            const sw_left = r1.isSource ? (r1.edge.sidewalkLeft ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth) : (r1.edge.sidewalkRight ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth);
            const sw_right = r1.isSource ? (r1.edge.sidewalkRight ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth) : (r1.edge.sidewalkLeft ?? r1.edge.sidewalk ?? DEFAULTS.sidewalkWidth);
            const W = r1.edge.width / 2;
            const OW_L = W + sw_left;
            const OW_R = W + sw_right;

            const pts: Point[] = [];
            const outerPts: Point[] = [];

            const steps = 8;
            const angle0 = Math.atan2(r1.dir.y, r1.dir.x);
            const startAngle = angle0 - Math.PI / 2;

            for (let s = 0; s <= steps; s++) {
                const a = startAngle - Math.PI * (s / steps);
                const dx = Math.cos(a);
                const dy = Math.sin(a);
                pts.push({ x: node.point.x + dx * W, y: node.point.y + dy * W, z: node.point.z });
                const outerR = OW_L * (1 - s/steps) + OW_R * (s/steps);
                outerPts.push({ x: node.point.x + dx * outerR, y: node.point.y + dy * outerR, z: node.point.z });
            }

            corners.push({
              points: pts,
              sidewalkWidth: Math.max(sw_left, sw_right)
            });
            outerCorners.push(outerPts);
        } else {
            const [innerPts, outerPts] = calculateBothCornerPoints(
              node.point,
              r1.dir, r1.edge.width, sw1, (r1.edge.transitionSmoothness ?? 0) + (node.transitionSmoothness ?? 0),
              r2.dir, r2.edge.width, sw2, (r2.edge.transitionSmoothness ?? 0) + (node.transitionSmoothness ?? 0),
              chamferAngleDeg
            );
            corners.push({
              points: innerPts,
              sidewalkWidth: Math.max(sw1, sw2)
            });
            outerCorners.push(outerPts);
        }
    }

    const hubPolygon: Point[] = [];
    const hubOuterPolygon: Point[] = [];

    const clearances = new Map<string, number>();
    const squaredBases = new Map<string, Point[]>();
    const squaredOuterBases = new Map<string, Point[]>();

    for (let i = 0; i < N; i++) {
      hubPolygon.push(...corners[i].points);
      hubOuterPolygon.push(...outerCorners[i]);

      const rIdx = (i + 1) % N;
      const r = outgoing[rIdx];

      const bL = N === 1 ? corners[0].points[0] : corners[i].points[corners[i].points.length - 1];
      const bR = N === 1 ? corners[0].points[corners[0].points.length - 1] : corners[rIdx].points[0];
      const obL = N === 1 ? outerCorners[0][0] : outerCorners[i][outerCorners[i].length - 1];
      const obR = N === 1 ? outerCorners[0][outerCorners[0].length - 1] : outerCorners[rIdx][0];

      const dir0 = r.dir;
      const distL = (bL.x - node.point.x) * dir0.x + (bL.y - node.point.y) * dir0.y;
      const distR = (bR.x - node.point.x) * dir0.x + (bR.y - node.point.y) * dir0.y;

      const odistL = (obL.x - node.point.x) * dir0.x + (obL.y - node.point.y) * dir0.y;
      const odistR = (obR.x - node.point.x) * dir0.x + (obR.y - node.point.y) * dir0.y;

      let maxDist = Math.max(distL, distR, odistL, odistR);

      if (N > 1) {
        const pz = node.point.z ?? 4;
        const sL = { x: bL.x + dir0.x * (maxDist - distL), y: bL.y + dir0.y * (maxDist - distL), z: pz };
        const sR = { x: bR.x + dir0.x * (maxDist - distR), y: bR.y + dir0.y * (maxDist - distR), z: pz };

        const osL = { x: obL.x + dir0.x * (maxDist - odistL), y: obL.y + dir0.y * (maxDist - odistL), z: pz };
        const osR = { x: obR.x + dir0.x * (maxDist - odistR), y: obR.y + dir0.y * (maxDist - odistR), z: pz };

        if (distL < maxDist - 0.01) {
          hubPolygon.push(sL);
          if (!node.ignoreMeshing) {
            mesh.sidewalkPolygons.push({ polygon: [obL, bL, sL, osL] });
            const smoothingTriangles = [
              topFacingTriangle(bL, sL, osL),
              topFacingTriangle(bL, osL, obL),
            ];
            mesh.sidewalkTriangles.push(...smoothingTriangles);
            mesh.triangles.push(...smoothingTriangles);
          }
        }
        if (distR < maxDist - 0.01) {
          hubPolygon.push(sR);
          if (!node.ignoreMeshing) {
            mesh.sidewalkPolygons.push({ polygon: [osR, sR, bR, obR] });
            const smoothingTriangles = [
              topFacingTriangle(bR, osR, sR),
              topFacingTriangle(bR, obR, osR),
            ];
            mesh.sidewalkTriangles.push(...smoothingTriangles);
            mesh.triangles.push(...smoothingTriangles);
          }
        }

        if (odistL < maxDist - 0.01) hubOuterPolygon.push(osL);
        if (odistR < maxDist - 0.01) hubOuterPolygon.push(osR);

        squaredBases.set(`${r.edge.id}_${r.isSource}`, [sL, sR]);
        squaredOuterBases.set(`${r.edge.id}_${r.isSource}`, [osL, osR]);
      } else {
        const distMin = Math.min(distL, distR);
        squaredBases.set(`${r.edge.id}_${r.isSource}`, [bL, bR]);
        squaredOuterBases.set(`${r.edge.id}_${r.isSource}`, [obL, obR]);
      }

      clearances.set(`${r.edge.id}_${r.isSource}`, maxDist);
    }

    mesh.hubs.push({ id: node.id, polygon: hubPolygon, corners, outerPolygon: hubOuterPolygon, outerCorners, ignoreMeshing: node.ignoreMeshing });

    if (!node.ignoreMeshing) {
      for (let i = 0; i < hubPolygon.length; i++) {
        const p1 = hubPolygon[i];
        const p2 = hubPolygon[(i + 1) % hubPolygon.length];
        const hubTriangle = topFacingTriangle(node.point, p1, p2);
        mesh.hubTriangles.push(hubTriangle);
        mesh.triangles.push(hubTriangle);
      }

      for (let i = 0; i < corners.length; i++) {
        const innerPts = corners[i].points;
        const outerPts = outerCorners[i];

        const poly = [...outerPts];
        poly.push(...[...innerPts].reverse());
        mesh.sidewalkPolygons.push({ polygon: poly });

        for (let j = 0; j < innerPts.length - 1; j++) {
          const smoothingTriangles = [
            topFacingTriangle(innerPts[j], outerPts[j], outerPts[j+1]),
            topFacingTriangle(innerPts[j], outerPts[j+1], innerPts[j+1]),
          ];
          mesh.sidewalkTriangles.push(...smoothingTriangles);
          mesh.triangles.push(...smoothingTriangles);
        }
      }
    }

    nodeClearances.set(node.id, clearances);
    nodeCorners.set(node.id, squaredBases);
    nodeOuterCorners.set(node.id, squaredOuterBases);
  }

  // 2. Build Roads
  for (const edge of roadEdges) {
    const sourceNode = nodes.find(n => n.id === edge.source)!;
    const targetNode = edge.target ? nodes.find(n => n.id === edge.target) : null;

    // We get the forward-facing spline
    const spline = edgeSplines.get(edge.id)!;
    const W = edge.width / 2;
    const skipRoadMeshing = !!(sourceNode.ignoreMeshing || (targetNode ? targetNode.ignoreMeshing : false));

    const sourceClearance = nodeClearances.get(sourceNode.id)?.get(`${edge.id}_true`) || 0;
    const targetClearance = targetNode ? (nodeClearances.get(targetNode.id)?.get(`${edge.id}_false`) || 0) : 0;

    const sourceBases = getEdgeBases(sourceNode, sourceNode, edge, true, nodeCorners);
    const targetBases = targetNode ? getEdgeBases(targetNode, sourceNode, edge, false, nodeCorners) : null;

    const outerSourceBases = getEdgeBases(sourceNode, sourceNode, edge, true, nodeOuterCorners);
    const outerTargetBases = targetNode ? getEdgeBases(targetNode, sourceNode, edge, false, nodeOuterCorners) : null;

    const leftPoints: Point[] = [];
    const rightPoints: Point[] = [];
    const outerLeftPoints: Point[] = [];
    const outerRightPoints: Point[] = [];

    const centerLine: { p: Point, dir: Point }[] = [];

    const controlPoints = getEdgeControlPoints(edge, nodes);
    const srcDir = controlPoints.length > 1 ? getDir(controlPoints[0], controlPoints[1]) : { x: 1, y: 0 };
    const tgtDir = targetNode && controlPoints.length > 1 ? getDir(controlPoints[controlPoints.length - 1], controlPoints[controlPoints.length - 2]) : {x:0, y:0};

    for (let j = 1; j < spline.length; j++) {
      const p1 = spline[j - 1];
      const p2 = spline[j];

      const srcDist = Math.hypot(p2.x - sourceNode.point.x, p2.y - sourceNode.point.y);
      if (srcDist < sourceClearance + edge.width + 20) {
          const dSourceProj = (p2.x - sourceNode.point.x) * srcDir.x + (p2.y - sourceNode.point.y) * srcDir.y;
          if (dSourceProj < sourceClearance + 1) continue;
      }

      if (targetNode && j >= spline.length - 1) {
          continue;
      }

      if (targetNode) {
          const tgtDist = Math.hypot(p2.x - targetNode.point.x, p2.y - targetNode.point.y);
          if (tgtDist < targetClearance + edge.width + 20) {
              const dTargetProj = (p2.x - targetNode.point.x) * tgtDir.x + (p2.y - targetNode.point.y) * tgtDir.y;
              if (dTargetProj < targetClearance + 1) continue;
          }
      }

      let dir = getDir(p1, p2);
      if (j < spline.length - 1) {
        dir = getDir(spline[j-1], spline[j+1]);
      }

      centerLine.push({ p: p2, dir });
      const left = { x: dir.y, y: -dir.x };
      const right = { x: -dir.y, y: dir.x };
      const sw_left = edge.sidewalkLeft ?? edge.sidewalk ?? DEFAULTS.sidewalkWidth;
      const sw_right = edge.sidewalkRight ?? edge.sidewalk ?? DEFAULTS.sidewalkWidth;
      const OW_L = W + sw_left;
      const OW_R = W + sw_right;

      leftPoints.push({ x: p2.x + left.x * W, y: p2.y + left.y * W, z: p2.z });
      rightPoints.push({ x: p2.x + right.x * W, y: p2.y + right.y * W, z: p2.z });
      outerLeftPoints.push({ x: p2.x + left.x * OW_L, y: p2.y + left.y * OW_L, z: p2.z });
      outerRightPoints.push({ x: p2.x + right.x * OW_R, y: p2.y + right.y * OW_R, z: p2.z });
    }

    const cwWidth = DEFAULTS.crosswalkLength;

    if (sourceBases && outerSourceBases) {
       let [bL, bR] = sourceBases;
       let [obL, obR] = outerSourceBases;

       if (isTrueJunction(sourceNode.id, nodes, roadEdges)) {
         const sDir = getDir(spline[0], spline[Math.min(1, spline.length - 1)]);
         const sz = spline[0].z ?? 4;

         const new_bL = { x: bL.x + sDir.x * cwWidth, y: bL.y + sDir.y * cwWidth, z: sz };
         const new_bR = { x: bR.x + sDir.x * cwWidth, y: bR.y + sDir.y * cwWidth, z: sz };
         const new_obL = { x: obL.x + sDir.x * cwWidth, y: obL.y + sDir.y * cwWidth, z: sz };
         const new_obR = { x: obR.x + sDir.x * cwWidth, y: obR.y + sDir.y * cwWidth, z: sz };

         if (hasCrosswalk(edge.id, true, nodes, roadEdges)) {
           mesh.crosswalks.push({ edgeId: edge.id, nodeId: sourceNode.id, polygon: [bL, bR, new_bR, new_bL] });
         }
         if (!skipRoadMeshing) {
           mesh.sidewalkPolygons.push({ polygon: [obL, bL, new_bL, new_obL] });
           mesh.sidewalkPolygons.push({ polygon: [bR, obR, new_obR, new_bR] });

           mesh.crosswalkTriangles.push([bL, bR, new_bR], [bL, new_bR, new_bL]);
           mesh.sidewalkTriangles.push([obL, bL, new_bL], [obL, new_bL, new_obL]);
           mesh.sidewalkTriangles.push([bR, obR, new_obR], [bR, new_obR, new_bR]);
           mesh.triangles.push([bL, bR, new_bR], [bL, new_bR, new_bL]);
           mesh.triangles.push([obL, bL, new_bL], [obL, new_bL, new_obL]);
           mesh.triangles.push([bR, obR, new_obR], [bR, new_obR, new_bR]);
         }

         bL = new_bL; bR = new_bR;
         obL = new_obL; obR = new_obR;
       }

       const clStart = { x: (bL.x + bR.x) / 2, y: (bL.y + bR.y) / 2, z: (bL.z ?? 4) };
       const startDir = getDir(spline[0], spline[Math.min(1, spline.length - 1)]);
       const startRight = { x: (bR.x - clStart.x) / W, y: (bR.y - clStart.y) / W };
       const fullCenterLine: { p: Point, dir: Point, right: Point }[] = [{ p: clStart, dir: startDir, right: startRight }, ...centerLine.map(pt => ({ ...pt, right: { x: -pt.dir.y, y: pt.dir.x } }))];

       let poly = [bL, bR, ...rightPoints];
       let outerPoly = [obL, obR, ...outerRightPoints];
       let tbL: Point | null = null, tbR: Point | null = null;
       let otbL: Point | null = null, otbR: Point | null = null;

       if (targetBases && outerTargetBases) {
           [tbR, tbL] = targetBases;
           [otbR, otbL] = outerTargetBases;

           if (isTrueJunction(targetNode!.id, nodes, roadEdges)) {
             const tDir = getDir(spline[spline.length - 1], spline[Math.max(0, spline.length - 2)]);
             const tz = spline[spline.length - 1].z ?? 4;

             const new_tbL = { x: tbL.x + tDir.x * cwWidth, y: tbL.y + tDir.y * cwWidth, z: tz };
             const new_tbR = { x: tbR.x + tDir.x * cwWidth, y: tbR.y + tDir.y * cwWidth, z: tz };
             const new_otbL = { x: otbL.x + tDir.x * cwWidth, y: otbL.y + tDir.y * cwWidth, z: tz };
             const new_otbR = { x: otbR.x + tDir.x * cwWidth, y: otbR.y + tDir.y * cwWidth, z: tz };

             if (hasCrosswalk(edge.id, false, nodes, roadEdges)) {
               mesh.crosswalks.push({ edgeId: edge.id, nodeId: targetNode!.id, polygon: [tbL, tbR, new_tbR, new_tbL] });
             }
             if (!skipRoadMeshing) {
               mesh.sidewalkPolygons.push({ polygon: [otbL, tbL, new_tbL, new_otbL] });
               mesh.sidewalkPolygons.push({ polygon: [tbR, otbR, new_otbR, new_tbR] });

               mesh.crosswalkTriangles.push([tbL, new_tbR, tbR], [tbL, new_tbL, new_tbR]);
               mesh.sidewalkTriangles.push([otbL, new_tbL, tbL], [otbL, new_otbL, new_tbL]);
               mesh.sidewalkTriangles.push([tbR, new_otbR, otbR], [tbR, new_tbR, new_otbR]);
               mesh.triangles.push([tbL, new_tbR, tbR], [tbL, new_tbL, new_tbR]);
               mesh.triangles.push([otbL, new_tbL, tbL], [otbL, new_otbL, new_tbL]);
               mesh.triangles.push([tbR, new_otbR, otbR], [tbR, new_tbR, new_otbR]);
             }

             tbL = new_tbL; tbR = new_tbR;
             otbL = new_otbL; otbR = new_otbR;
           }

           const clEnd = { x: (tbL.x + tbR.x) / 2, y: (tbL.y + tbR.y) / 2, z: (tbL.z ?? 4) };
           const endDirForDashes = getDir(spline[Math.max(0, spline.length - 2)], spline[spline.length - 1]);
           const endRight = { x: (tbR.x - clEnd.x) / W, y: (tbR.y - clEnd.y) / W };
           fullCenterLine.push({ p: clEnd, dir: endDirForDashes, right: endRight });

           poly.push(tbR, tbL);
           outerPoly.push(otbR, otbL);
       } else {
           if (leftPoints.length === 0) {
               const dir = getDir(sourceNode.point, spline[spline.length - 1]);
               const p2 = spline[spline.length - 1];
               const sw_left = edge.sidewalkLeft ?? edge.sidewalk ?? DEFAULTS.sidewalkWidth;
               const sw_right = edge.sidewalkRight ?? edge.sidewalk ?? DEFAULTS.sidewalkWidth;
               const OW_L = W + sw_left;
               const OW_R = W + sw_right;
               leftPoints.push({ x: p2.x + dir.y * W, y: p2.y + -dir.x * W, z: p2.z });
               rightPoints.push({ x: p2.x + -dir.y * W, y: p2.y + dir.x * W, z: p2.z });
               outerLeftPoints.push({ x: p2.x + dir.y * OW_L, y: p2.y + -dir.x * OW_L, z: p2.z });
               outerRightPoints.push({ x: p2.x + -dir.y * OW_R, y: p2.y + dir.x * OW_R, z: p2.z });
               poly = [bL, bR, ...rightPoints];
               outerPoly = [obL, obR, ...outerRightPoints];
               fullCenterLine.push({ p: p2, dir, right: { x: -dir.y, y: dir.x } });
           } else {
               const lL = leftPoints[leftPoints.length - 1];
               const lR = rightPoints[rightPoints.length - 1];
               const endDirForDashes = getDir(spline[Math.max(0, spline.length - 2)], spline[spline.length - 1]);
               const clEnd = { x: (lL.x + lR.x) / 2, y: (lL.y + lR.y) / 2, z: (lL.z ?? 4) };
               const endRight = { x: (lR.x - clEnd.x) / W, y: (lR.y - clEnd.y) / W };
               fullCenterLine.push({ p: clEnd, dir: endDirForDashes, right: endRight });
           }
       }
       poly.push(...[...leftPoints].reverse());
       outerPoly.push(...[...outerLeftPoints].reverse());

       let numLanesForward = 0;
       let numLanesBackward = 0;
       const isOneWay = !!edge.oneWay;

       if (isOneWay) {
           numLanesForward = Math.max(1, Math.floor(edge.width / laneWidth));
           numLanesBackward = 0;
       } else {
           numLanesForward = Math.max(1, Math.floor((edge.width / 2) / laneWidth));
           numLanesBackward = Math.max(1, Math.floor((edge.width / 2) / laneWidth));
       }

       const laneCenters: { offset: number, dir: number }[] = [];
       const laneDividers: { offset: number, type: 'dashed' | 'double_yellow' }[] = [];

       if (isOneWay) {
           const N = numLanesForward;
           const startOffset = - (N - 1) * laneWidth / 2;
           for (let i = 0; i < N; i++) {
               laneCenters.push({ offset: startOffset + i * laneWidth, dir: 1 });
           }
           for (let i = 0; i < N - 1; i++) {
               laneDividers.push({ offset: startOffset + i * laneWidth + laneWidth / 2, type: 'dashed' });
           }
       } else {
           const N = numLanesForward;
           for (let i = 0; i < N; i++) {
               laneCenters.push({ offset: laneWidth / 2 + i * laneWidth, dir: 1 });
               laneCenters.push({ offset: - (laneWidth / 2 + i * laneWidth), dir: -1 });
           }
           laneDividers.push({ offset: 0, type: 'double_yellow' });
           for (let i = 1; i < N; i++) {
               laneDividers.push({ offset: i * laneWidth, type: 'dashed' });
               laneDividers.push({ offset: - i * laneWidth, type: 'dashed' });
           }
       }

       // Generate points along the full length for each divider
       for (const divider of laneDividers) {
           const linePoints: Point[] = [];
           for (let j = 0; j < fullCenterLine.length; j++) {
               const pt = fullCenterLine[j];
               const p = pt.p;
               const right = pt.right;
               linePoints.push({ x: p.x + right.x * divider.offset, y: p.y + right.y * divider.offset, z: p.z });
           }
           if (divider.type === 'dashed') {
               mesh.dashedLines.push({ points: linePoints, ignoreMeshing: skipRoadMeshing });
               if (!skipRoadMeshing) {
                let lengthSoFar = 0;
                const dashLength = 6;
                const dashGap = 6;
                const totalDash = dashLength + dashGap;
                const width = 2.0;
                const yOffset = 0.15;

                for (let j = 1; j < linePoints.length; j++) {
                    const p1 = linePoints[j - 1];
                    const p2 = linePoints[j];
                    const dx = p2.x - p1.x;
                    const dy = p2.y - p1.y;
                    const len = Math.hypot(dx, dy);
                    const dir = len > 0 ? { x: dx/len, y: dy/len } : { x: 1, y: 0 };
                    const right = { x: -dir.y, y: dir.x };
                    const dist = len;

                     const h1 = (p1.z ?? 4) + yOffset;
                     const br = { x: p1.x + right.x * width / 2, y: p1.y + right.y * width / 2, z: h1, u: 1, v: lengthSoFar / totalDash };
                     const bl = { x: p1.x - right.x * width / 2, y: p1.y - right.y * width / 2, z: h1, u: 0, v: lengthSoFar / totalDash };

                     const h2 = (p2.z ?? 4) + yOffset;
                     const nextV = (lengthSoFar + dist) / totalDash;
                     const tr = { x: p2.x + right.x * width / 2, y: p2.y + right.y * width / 2, z: h2, u: 1, v: nextV };
                     const tl = { x: p2.x - right.x * width / 2, y: p2.y - right.y * width / 2, z: h2, u: 0, v: nextV };

                     mesh.dashedLineTriangles.push([bl, tr, tl], [bl, br, tr]);
                    lengthSoFar += dist;
                }
               }
           } else {
               mesh.solidYellowLines.push({ points: linePoints, ignoreMeshing: skipRoadMeshing });
               if (!skipRoadMeshing) {
                const width = 2.0;
                const yOffset = 0.15;
                const spread = 1.5;

                for (let j = 1; j < linePoints.length; j++) {
                    const p1 = linePoints[j - 1];
                    const p2 = linePoints[j];
                    const right1 = fullCenterLine[j - 1].right;
                    const right2 = fullCenterLine[j].right;

                    const h1 = (p1.z ?? 4) + yOffset;
                    const h2 = (p2.z ?? 4) + yOffset;

                    const r1 = { x: p1.x + right1.x * spread, y: p1.y + right1.y * spread, z: h1 };
                    const r2 = { x: p2.x + right2.x * spread, y: p2.y + right2.y * spread, z: h2 };
                    const br1 = { x: r1.x + right1.x * width / 2, y: r1.y + right1.y * width / 2, z: h1 };
                    const bl1 = { x: r1.x - right1.x * width / 2, y: r1.y - right1.y * width / 2, z: h1 };
                    const tr1 = { x: r2.x + right2.x * width / 2, y: r2.y + right2.y * width / 2, z: h2 };
                    const tl1 = { x: r2.x - right2.x * width / 2, y: r2.y - right2.y * width / 2, z: h2 };
                    mesh.solidLineTriangles.push([bl1, tr1, tl1], [bl1, br1, tr1]);

                    const l1 = { x: p1.x - right1.x * spread, y: p1.y - right1.y * spread, z: h1 };
                    const l2 = { x: p2.x - right2.x * spread, y: p2.y - right2.y * spread, z: h2 };
                    const br2 = { x: l1.x + right1.x * width / 2, y: l1.y + right1.y * width / 2, z: h1 };
                    const bl2 = { x: l1.x - right1.x * width / 2, y: l1.y - right1.y * width / 2, z: h1 };
                    const tr2 = { x: l2.x + right2.x * width / 2, y: l2.y + right2.y * width / 2, z: h2 };
                    const tl2 = { x: l2.x - right2.x * width / 2, y: l2.y - right2.y * width / 2, z: h2 };
                    mesh.solidLineTriangles.push([bl2, tr2, tl2], [bl2, br2, tr2]);
                }
               }
           }
       }

       let currentLen = 0;
       for (let j = 1; j < fullCenterLine.length; j++) {
           const pt1 = fullCenterLine[j-1];
           const pt2 = fullCenterLine[j];
           const p1 = pt1.p;
           const p2 = pt2.p;
           const dist = Math.hypot(p2.x - p1.x, p2.y - p1.y);
           currentLen += dist;
           if (currentLen > 100) {
               currentLen = currentLen % 100;
               const dir = pt2.dir;
               const right = { x: -dir.y, y: dir.x };
               for (const center of laneCenters) {
                   const pos = { x: p2.x + right.x * center.offset, y: p2.y + right.y * center.offset, z: p2.z };
                   mesh.laneArrows.push({ position: pos, dir: center.dir === 1 ? dir : { x: -dir.x, y: -dir.y }, ignoreMeshing: skipRoadMeshing });
               }
           }
       }

       const leftSidewalkPoly = [obL, bL, ...leftPoints];
       if (tbL) leftSidewalkPoly.push(tbL);
       if (otbL) leftSidewalkPoly.push(otbL);
       leftSidewalkPoly.push(...[...outerLeftPoints].reverse());
       mesh.sidewalkPolygons.push({ polygon: leftSidewalkPoly, ignoreMeshing: skipRoadMeshing });

       const rightSidewalkPoly = [bR, obR, ...outerRightPoints];
       if (otbR) rightSidewalkPoly.push(otbR);
       if (tbR) rightSidewalkPoly.push(tbR);
       rightSidewalkPoly.push(...[...rightPoints].reverse());
       mesh.sidewalkPolygons.push({ polygon: rightSidewalkPoly, ignoreMeshing: skipRoadMeshing });

       mesh.roadPolygons.push({
           id: edge.id,
           polygon: poly,
           leftCurve: [bL, ...leftPoints, ...(tbL ? [tbL] : [])],
           rightCurve: [bR, ...rightPoints, ...(tbR ? [tbR] : [])],
           outerPolygon: outerPoly,
           outerLeftCurve: [obL, ...outerLeftPoints, ...(otbL ? [otbL] : [])],
           outerRightCurve: [obR, ...outerRightPoints, ...(otbR ? [otbR] : [])],
           sidewalkWidth: edge.sidewalk ?? DEFAULTS.sidewalkWidth,
           ignoreMeshing: skipRoadMeshing
       });

       let currL = bL;
       let currR = bR;
       let currOL = obL;
       let currOR = obR;
       if (!skipRoadMeshing) {
       for (let j = 0; j < leftPoints.length; j++) {
         const nextL = leftPoints[j];
         const nextR = rightPoints[j];
         const nextOL = outerLeftPoints[j];
         const nextOR = outerRightPoints[j];

         mesh.roadTriangles.push([currL, currR, nextR]);
         mesh.roadTriangles.push([currL, nextR, nextL]);
         mesh.triangles.push([currL, currR, nextR]);
         mesh.triangles.push([currL, nextR, nextL]);

         mesh.sidewalkTriangles.push([currOL, currL, nextL]);
         mesh.sidewalkTriangles.push([currOL, nextL, nextOL]);
         mesh.triangles.push([currOL, currL, nextL]);
         mesh.triangles.push([currOL, nextL, nextOL]);

         mesh.sidewalkTriangles.push([currR, currOR, nextOR]);
         mesh.sidewalkTriangles.push([currR, nextOR, nextR]);
         mesh.triangles.push([currR, currOR, nextOR]);
         mesh.triangles.push([currR, nextOR, nextR]);

         currL = nextL;
         currR = nextR;
         currOL = nextOL;
         currOR = nextOR;
       }
       }

       if (!skipRoadMeshing && tbL && tbR && otbL && otbR) {
          mesh.roadTriangles.push([currL, currR, tbR]);
          mesh.roadTriangles.push([currL, tbR, tbL]);
          mesh.triangles.push([currL, currR, tbR]);
          mesh.triangles.push([currL, tbR, tbL]);

          mesh.sidewalkTriangles.push([currOL, currL, tbL]);
          mesh.sidewalkTriangles.push([currOL, tbL, otbL]);
          mesh.triangles.push([currOL, currL, tbL]);
          mesh.triangles.push([currOL, tbL, otbL]);

          mesh.sidewalkTriangles.push([currR, currOR, otbR]);
          mesh.sidewalkTriangles.push([currR, otbR, tbR]);
          mesh.triangles.push([currR, currOR, otbR]);
          mesh.triangles.push([currR, otbR, tbR]);
       }
    }
  }

  // 3. Build Polygon Fills
  for (const poly of polygonFills) {
    if (poly.points.length < 3) continue;

    const polyNodes = poly.points.map(id => nodes.find(n => n.id === id)).filter(n => !!n) as Node[];
    if (polyNodes.length < 3) continue;

    let signedArea = 0;
    for (let i = 0; i < polyNodes.length; i++) {
        const p1 = polyNodes[i].point;
        const p2 = polyNodes[(i + 1) % polyNodes.length].point;
        signedArea += (p1.x * p2.y - p2.x * p1.y);
    }
    const isClockwise = signedArea > 0;

    const segments: Point[][] = [];

    for (let i = 0; i < poly.points.length; i++) {
        const n1_id = poly.points[i];
        const n2_id = poly.points[(i + 1) % poly.points.length];

        const n1 = nodes.find(n => n.id === n1_id);
        const n2 = nodes.find(n => n.id === n2_id);
        if (!n1 || !n2) continue;

        const edge = edges.find(e => (e.source === n1.id && e.target === n2.id) || (e.source === n2.id && e.target === n1.id));
        const roadPoly = edge ? mesh.roadPolygons.find(rp => rp.id === edge.id) : null;

        let curve: Point[] = [];
        if (roadPoly && !roadPoly.ignoreMeshing) {
            const isForward = edge!.source === n1_id;
            let useRightCurve = false;

            // For drawing fills around roads, tracing clockwise means the fill is on the RIGHT.
            // On the right side, we use the OUTER curve of the road.
            // When traversing forward, the right side is outerRightCurve.
            if (isClockwise) {
                useRightCurve = isForward;
            } else {
                useRightCurve = !isForward;
            }

            const chosenCurve = useRightCurve ? roadPoly.outerRightCurve : roadPoly.outerLeftCurve;

            // Reverse if traversing backwards relative to edge direction
            if (isForward) {
                for (let j = 0; j < chosenCurve.length; j++) {
                    curve.push(chosenCurve[j]);
                }
            } else {
                for (let j = chosenCurve.length - 1; j >= 0; j--) {
                    curve.push(chosenCurve[j]);
                }
            }
        } else if (roadPoly) {
            // Ignored road mesh, but we have the computed geometries for its junction connections.
            // We want the grass fill to extend over the fake road exactly up to the junction sidewalks.
            const isForward = edge!.source === n1_id;

            const pL1 = roadPoly.outerLeftCurve[0];
            const pR1 = roadPoly.outerRightCurve[0];
            const pL2 = roadPoly.outerLeftCurve[roadPoly.outerLeftCurve.length - 1];
            const pR2 = roadPoly.outerRightCurve[roadPoly.outerRightCurve.length - 1];

            const mid1 = { x: (pL1.x + pR1.x) / 2, y: (pL1.y + pR1.y) / 2, z: ((pL1.z ?? 0) + (pR1.z ?? 0)) / 2 };
            const mid2 = { x: (pL2.x + pR2.x) / 2, y: (pL2.y + pR2.y) / 2, z: ((pL2.z ?? 0) + (pR2.z ?? 0)) / 2 };

            const midStart = isForward ? mid1 : mid2;
            const midEnd = isForward ? mid2 : mid1;

            curve.push(midStart);

            const spline = edgeSplines.get(edge!.id);
            if (spline && spline.length > 2) {
                if (isForward) {
                    for (let j = 1; j < spline.length - 1; j++) curve.push(spline[j]);
                } else {
                    for (let j = spline.length - 2; j >= 1; j--) curve.push(spline[j]);
                }
            }

            curve.push(midEnd);
        } else {
            // No road mesh, use underlying edge spline or straight line.
            if (edge) {
                const spline = edgeSplines.get(edge.id);
                if (spline && spline.length > 0) {
                    const isForward = edge.source === n1_id;
                    if (isForward) {
                        for (let j = 0; j < spline.length; j++) curve.push(spline[j]);
                    } else {
                        for (let j = spline.length - 1; j >= 0; j--) curve.push(spline[j]);
                    }
                } else {
                    curve.push(n1.point);
                    curve.push(n2.point);
                }
            } else {
                curve.push(n1.point);
                curve.push(n2.point);
            }

            // Clip curve against hub boundaries so it doesn't draw through the junction area
            const hub2 = mesh.hubs.find(h => h.id === n2_id);
            if (hub2 && hub2.outerPolygon.length > 0 && curve.length > 1) {
                let endIdx = curve.length - 1;
                while (endIdx > 0 && pointInPolygon(curve[endIdx], hub2.outerPolygon)) {
                    endIdx--;
                }
                if (endIdx < curve.length - 1) {
                    const exactIntersect = intersectHubBoundarySegment(curve[endIdx], curve[endIdx + 1], hub2);
                    curve.length = endIdx + 1;
                    if (exactIntersect) {
                        curve.push(exactIntersect);
                    }
                }
            }

            const hub1 = mesh.hubs.find(h => h.id === n1_id);
            if (hub1 && hub1.outerPolygon.length > 0 && curve.length > 1) {
                let startIdx = 0;
                while (startIdx < curve.length - 1 && pointInPolygon(curve[startIdx], hub1.outerPolygon)) {
                    startIdx++;
                }
                if (startIdx > 0) {
                    const exactIntersect = intersectHubBoundarySegment(curve[startIdx], curve[startIdx - 1], hub1);
                    curve = curve.slice(startIdx);
                    if (exactIntersect) {
                        curve.unshift(exactIntersect);
                    }
                }
            }
        }
        segments.push(curve);
    }

    const boundaryPoints: Point[] = [];

    for (let i = 0; i < segments.length; i++) {
        const curve = segments[i];
        const nextCurve = segments[(i + 1) % segments.length];

        for (let j = 0; j < curve.length; j++) {
            boundaryPoints.push(curve[j]);
        }

        const p_end = curve[curve.length - 1];
        const p_start = nextCurve[0];

        const n2_id = poly.points[(i + 1) % poly.points.length];
        const hub = mesh.hubs.find(h => h.id === n2_id);

        if (hub && hub.outerPolygon.length > 0) {
            const hubPath = buildHubBoundaryPath(hub.outerPolygon, p_end, p_start, isClockwise, hub.corners.length === 1);
            for (let j = 0; j < hubPath.length; j++) {
                boundaryPoints.push(hubPath[j]);
            }
        }
    }

    if (boundaryPoints.length < 3) continue;

    // Filter consecutive duplicate points (ShapeUtils doesn't like duplicates)
    const uniqueBoundaryPoints: Point[] = [];
    for (let i = 0; i < boundaryPoints.length; i++) {
        const p = boundaryPoints[i];
        const next = boundaryPoints[(i + 1) % boundaryPoints.length];
        if (Math.hypot(p.x - next.x, p.y - next.y) > 0.01) {
            uniqueBoundaryPoints.push(p);
        }
    }

    if (uniqueBoundaryPoints.length < 3) continue;

    const fillTriangles = buildGridMesh(uniqueBoundaryPoints);

    mesh.polygonTriangles.push({ triangles: fillTriangles, color: poly.color });
  }

  return mesh;
}

function buildGridMesh(boundaryPoints: Point[]): Triangle[] {
    const contour = boundaryPoints.map((point) => new THREE.Vector2(point.x, point.y));
    const faces = THREE.ShapeUtils.triangulateShape(contour, []);
    return faces.map(([i0, i1, i2]) => topFacingTriangle(boundaryPoints[i0], boundaryPoints[i1], boundaryPoints[i2]));
}

function pointInPolygon(p: { x: number, y: number }, polygon: Point[]): boolean {
    let isInside = false;
    let minX = polygon[0].x, maxX = polygon[0].x;
    let minY = polygon[0].y, maxY = polygon[0].y;
    for (let n = 1; n < polygon.length; n++) {
        minX = Math.min(minX, polygon[n].x);
        maxX = Math.max(maxX, polygon[n].x);
        minY = Math.min(minY, polygon[n].y);
        maxY = Math.max(maxY, polygon[n].y);
    }
    if (p.x < minX || p.x > maxX || p.y < minY || p.y > maxY) {
        return false;
    }
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        if ((polygon[i].y > p.y) !== (polygon[j].y > p.y) &&
            p.x < (polygon[j].x - polygon[i].x) * (p.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x) {
            isInside = !isInside;
        }
    }
    return isInside;
}
