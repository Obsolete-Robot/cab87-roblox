import { Point, Node, Edge, MeshData } from "./types";
import { getDir } from "./math";
import { calculateBothCornerPoints } from "./junctions";
import { getEdgeControlPoints, sampleEdgeSpline, hasCrosswalk, isTrueJunction, getIncidentConnections } from "./network";

export function getEdgeBases(node: Node, sourceNode: Node, edge: Edge, isSource: boolean, nodeCorners: Map<string, Map<string, Point[]>>): [Point, Point] | null {
  const corners = nodeCorners.get(node.id);
  if (!corners) return null;
  const bases = corners.get(`${edge.id}_${isSource}`) || corners.get(edge.id);
  if (!bases || bases.length < 2) return null;
  return [bases[0], bases[1]];
}

export function buildNetworkMesh(nodes: Node[], edges: Edge[], chamferAngleDeg: number, meshResolution: number = 20): MeshData {
  const mesh: MeshData = {
    vertices: [],
    triangles: [],
    hubs: [],
    roadPolygons: [],
    crosswalks: [],
    sidewalkPolygons: [],
    centerLines: []
  };

  const edgeSplines = new Map<string, Point[]>();
  edges.forEach(e => edgeSplines.set(e.id, sampleEdgeSpline(e, nodes, edges, chamferAngleDeg, meshResolution)));

  const nodeClearances = new Map<string, Map<string, number>>();
  const nodeCorners = new Map<string, Map<string, Point[]>>();
  const nodeOuterCorners = new Map<string, Map<string, Point[]>>();

  // 1. Build Hubs
  for (const node of nodes) {
    const conns = getIncidentConnections(node.id, edges);
    if (conns.length === 0) continue;

    const outgoing = conns.map(c => {
      const isSource = c.isSource;
      const e = c.edge;
      const controlPts = getEdgeControlPoints(e, nodes);
      const p1 = node.point;
      const p2 = isSource ? controlPts[1] : controlPts[controlPts.length - 2];
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
        const sw = Math.max(r1.edge.sidewalk ?? 12, r2.edge.sidewalk ?? 12);
        
        if (N === 1) {
            const left = { x: r1.dir.y, y: -r1.dir.x };
            const right = { x: -r1.dir.y, y: r1.dir.x };
            const W = r1.edge.width / 2;
            const OW = W + sw;
            corners.push({
              points: [
                { x: node.point.x + left.x * W, y: node.point.y + left.y * W },
                { x: node.point.x + right.x * W, y: node.point.y + right.y * W }
              ],
              sidewalkWidth: sw
            });
            outerCorners.push([
                { x: node.point.x + left.x * OW, y: node.point.y + left.y * OW },
                { x: node.point.x + right.x * OW, y: node.point.y + right.y * OW }
            ]);
        } else {
            const [innerPts, outerPts] = calculateBothCornerPoints(
              node.point, 
              r1.dir, r1.edge.width, sw, 
              r2.dir, r2.edge.width, sw,
              chamferAngleDeg
            );
            corners.push({
              points: innerPts,
              sidewalkWidth: sw
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
      const bR = N === 1 ? corners[0].points[1] : corners[rIdx].points[0];
      const obL = N === 1 ? outerCorners[0][0] : outerCorners[i][outerCorners[i].length - 1];
      const obR = N === 1 ? outerCorners[0][1] : outerCorners[rIdx][0];

      const dir0 = r.dir;
      const distL = (bL.x - node.point.x) * dir0.x + (bL.y - node.point.y) * dir0.y;
      const distR = (bR.x - node.point.x) * dir0.x + (bR.y - node.point.y) * dir0.y;
      
      const odistL = (obL.x - node.point.x) * dir0.x + (obL.y - node.point.y) * dir0.y;
      const odistR = (obR.x - node.point.x) * dir0.x + (obR.y - node.point.y) * dir0.y;
      
      const maxDist = Math.max(distL, distR, odistL, odistR);

      if (N > 1) {
        const sL = { x: bL.x + dir0.x * (maxDist - distL), y: bL.y + dir0.y * (maxDist - distL) };
        const sR = { x: bR.x + dir0.x * (maxDist - distR), y: bR.y + dir0.y * (maxDist - distR) };

        const osL = { x: obL.x + dir0.x * (maxDist - odistL), y: obL.y + dir0.y * (maxDist - odistL) };
        const osR = { x: obR.x + dir0.x * (maxDist - odistR), y: obR.y + dir0.y * (maxDist - odistR) };

        if (distL < maxDist - 0.01) {
          hubPolygon.push(sL);
          mesh.sidewalkPolygons.push([obL, bL, sL, osL]);
          mesh.triangles.push([bL, sL, osL], [bL, osL, obL]);
        }
        if (distR < maxDist - 0.01) {
          hubPolygon.push(sR);
          mesh.sidewalkPolygons.push([osR, sR, bR, obR]);
          mesh.triangles.push([bR, osR, sR], [bR, obR, osR]);
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
    
    mesh.hubs.push({ id: node.id, polygon: hubPolygon, corners, outerPolygon: hubOuterPolygon, outerCorners });

    for (let i = 0; i < hubPolygon.length; i++) {
      const p1 = hubPolygon[i];
      const p2 = hubPolygon[(i + 1) % hubPolygon.length];
      mesh.triangles.push([node.point, p1, p2]);
    }

    for (let i = 0; i < corners.length; i++) {
      const innerPts = corners[i].points;
      const outerPts = outerCorners[i];
      
      const poly = [...outerPts];
      poly.push(...[...innerPts].reverse());
      mesh.sidewalkPolygons.push(poly);
      
      for (let j = 0; j < innerPts.length - 1; j++) {
        mesh.triangles.push([innerPts[j], outerPts[j], outerPts[j+1]]);
        mesh.triangles.push([innerPts[j], outerPts[j+1], innerPts[j+1]]);
      }
    }

    nodeClearances.set(node.id, clearances);
    nodeCorners.set(node.id, squaredBases);
    nodeOuterCorners.set(node.id, squaredOuterBases);
  }

  // 2. Build Roads
  for (const edge of edges) {
    const sourceNode = nodes.find(n => n.id === edge.source)!;
    const targetNode = edge.target ? nodes.find(n => n.id === edge.target) : null;
    
    // We get the forward-facing spline
    const spline = edgeSplines.get(edge.id)!;
    const W = edge.width / 2;

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

    const centerLine: Point[] = [];

    const controlPoints = getEdgeControlPoints(edge, nodes);
    const srcDir = getDir(controlPoints[0], controlPoints[1]);
    const tgtDir = targetNode ? getDir(controlPoints[controlPoints.length - 1], controlPoints[controlPoints.length - 2]) : {x:0, y:0};

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

      centerLine.push(p2);

      let dir = getDir(p1, p2);
      if (j < spline.length - 1) {
        dir = getDir(spline[j-1], spline[j+1]); 
      }
      const left = { x: dir.y, y: -dir.x };
      const right = { x: -dir.y, y: dir.x };
      const OW = W + (edge.sidewalk ?? 12);
      
      leftPoints.push({ x: p2.x + left.x * W, y: p2.y + left.y * W });
      rightPoints.push({ x: p2.x + right.x * W, y: p2.y + right.y * W });
      outerLeftPoints.push({ x: p2.x + left.x * OW, y: p2.y + left.y * OW });
      outerRightPoints.push({ x: p2.x + right.x * OW, y: p2.y + right.y * OW });
    }

    const cwWidth = 14;

    if (sourceBases && outerSourceBases) {
       let [bL, bR] = sourceBases;
       let [obL, obR] = outerSourceBases;
       
       if (isTrueJunction(sourceNode.id, nodes, edges)) {
         const sDir = getDir(spline[0], spline[Math.min(1, spline.length - 1)]);
         
         const new_bL = { x: bL.x + sDir.x * cwWidth, y: bL.y + sDir.y * cwWidth };
         const new_bR = { x: bR.x + sDir.x * cwWidth, y: bR.y + sDir.y * cwWidth };
         const new_obL = { x: obL.x + sDir.x * cwWidth, y: obL.y + sDir.y * cwWidth };
         const new_obR = { x: obR.x + sDir.x * cwWidth, y: obR.y + sDir.y * cwWidth };
         
         if (hasCrosswalk(edge.id, true, nodes, edges)) {
           mesh.crosswalks.push({ edgeId: edge.id, nodeId: sourceNode.id, polygon: [bL, bR, new_bR, new_bL] });
         }
         mesh.sidewalkPolygons.push([obL, bL, new_bL, new_obL]);
         mesh.sidewalkPolygons.push([bR, obR, new_obR, new_bR]);
         
         mesh.triangles.push([bL, bR, new_bR], [bL, new_bR, new_bL]);
         mesh.triangles.push([obL, bL, new_bL], [obL, new_bL, new_obL]);
         mesh.triangles.push([bR, obR, new_obR], [bR, new_obR, new_bR]);
         
         bL = new_bL; bR = new_bR;
         obL = new_obL; obR = new_obR;
       }

       const clStart = { x: (bL.x + bR.x) / 2, y: (bL.y + bR.y) / 2 };
       const fullCenterLine = [clStart, ...centerLine];

       let poly = [bL, bR, ...rightPoints];
       let outerPoly = [obL, obR, ...outerRightPoints];
       let tbL: Point | null = null, tbR: Point | null = null;
       let otbL: Point | null = null, otbR: Point | null = null;
       
       if (targetBases && outerTargetBases) {
           [tbL, tbR] = targetBases; 
           [otbL, otbR] = outerTargetBases;
           
           if (isTrueJunction(targetNode!.id, nodes, edges)) {
             const tDir = getDir(spline[spline.length - 1], spline[Math.max(0, spline.length - 2)]);
             
             const new_tbL = { x: tbL.x + tDir.x * cwWidth, y: tbL.y + tDir.y * cwWidth };
             const new_tbR = { x: tbR.x + tDir.x * cwWidth, y: tbR.y + tDir.y * cwWidth };
             const new_otbL = { x: otbL.x + tDir.x * cwWidth, y: otbL.y + tDir.y * cwWidth };
             const new_otbR = { x: otbR.x + tDir.x * cwWidth, y: otbR.y + tDir.y * cwWidth };
             
             if (hasCrosswalk(edge.id, false, nodes, edges)) {
               mesh.crosswalks.push({ edgeId: edge.id, nodeId: targetNode!.id, polygon: [tbL, tbR, new_tbR, new_tbL] });
             }
             mesh.sidewalkPolygons.push([otbL, tbL, new_tbL, new_otbL]);
             mesh.sidewalkPolygons.push([tbR, otbR, new_otbR, new_tbR]);
             
             mesh.triangles.push([tbL, tbR, new_tbR], [tbL, new_tbR, new_tbL]);
             mesh.triangles.push([otbL, tbL, new_tbL], [otbL, new_tbL, new_otbL]);
             mesh.triangles.push([tbR, otbR, new_otbR], [tbR, new_otbR, new_tbR]);
             
             tbL = new_tbL; tbR = new_tbR;
             otbL = new_otbL; otbR = new_otbR;
           }

           const clEnd = { x: (tbL.x + tbR.x) / 2, y: (tbL.y + tbR.y) / 2 };
           fullCenterLine.push(clEnd);
           
           poly.push(tbL, tbR);
           outerPoly.push(otbL, otbR);
       } else {
           if (leftPoints.length === 0) {
               const dir = getDir(sourceNode.point, spline[spline.length - 1]);
               const p2 = spline[spline.length - 1];
               const OW = W + (edge.sidewalk ?? 12);
               leftPoints.push({ x: p2.x + dir.y * W, y: p2.y + -dir.x * W });
               rightPoints.push({ x: p2.x + -dir.y * W, y: p2.y + dir.x * W });
               outerLeftPoints.push({ x: p2.x + dir.y * OW, y: p2.y + -dir.x * OW });
               outerRightPoints.push({ x: p2.x + -dir.y * OW, y: p2.y + dir.x * OW });
               poly = [bL, bR, ...rightPoints];
               outerPoly = [obL, obR, ...outerRightPoints];
               fullCenterLine.push(p2);
           } else {
               const lL = leftPoints[leftPoints.length - 1];
               const lR = rightPoints[rightPoints.length - 1];
               fullCenterLine.push({ x: (lL.x + lR.x) / 2, y: (lL.y + lR.y) / 2 });
           }
       }
       poly.push(...[...leftPoints].reverse());
       outerPoly.push(...[...outerLeftPoints].reverse());
       mesh.centerLines.push(fullCenterLine);
       
       mesh.roadPolygons.push({
           id: edge.id,
           polygon: poly,
           leftCurve: leftPoints,
           rightCurve: rightPoints,
           outerPolygon: outerPoly,
           outerLeftCurve: outerLeftPoints,
           outerRightCurve: outerRightPoints,
           sidewalkWidth: edge.sidewalk ?? 12
       });

       let currL = bL;
       let currR = bR;
       let currOL = obL;
       let currOR = obR;
       for (let j = 0; j < leftPoints.length; j++) {
         const nextL = leftPoints[j];
         const nextR = rightPoints[j];
         const nextOL = outerLeftPoints[j];
         const nextOR = outerRightPoints[j];
   
         mesh.triangles.push([currL, currR, nextR]);
         mesh.triangles.push([currL, nextR, nextL]);
         
         mesh.triangles.push([currOL, currL, nextL]);
         mesh.triangles.push([currOL, nextL, nextOL]);
         
         mesh.triangles.push([currR, currOR, nextOR]);
         mesh.triangles.push([currR, nextOR, nextR]);
         
         currL = nextL;
         currR = nextR;
         currOL = nextOL;
         currOR = nextOR;
       }

       if (tbL && tbR && otbL && otbR) {
          mesh.triangles.push([currL, currR, tbL]);
          mesh.triangles.push([currL, tbL, tbR]);
          
          mesh.triangles.push([currOL, currL, tbR]);
          mesh.triangles.push([currOL, tbR, otbR]);
          
          mesh.triangles.push([currR, currOR, otbL]);
          mesh.triangles.push([currR, otbL, tbL]);
       }
    }
  }

  return mesh;
}
