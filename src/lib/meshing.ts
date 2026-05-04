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

export function buildNetworkMesh(nodes: Node[], edges: Edge[], chamferAngleDeg: number, meshResolution: number = 20, laneWidth: number = 30): MeshData {
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
    laneArrows: []
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
        
        const sw1 = r1.isSource ? (r1.edge.sidewalkRight ?? r1.edge.sidewalk ?? 12) : (r1.edge.sidewalkLeft ?? r1.edge.sidewalk ?? 12);
        const sw2 = r2.isSource ? (r2.edge.sidewalkLeft ?? r2.edge.sidewalk ?? 12) : (r2.edge.sidewalkRight ?? r2.edge.sidewalk ?? 12);

        if (N === 1) {
            const sw_left = r1.isSource ? (r1.edge.sidewalkLeft ?? r1.edge.sidewalk ?? 12) : (r1.edge.sidewalkRight ?? r1.edge.sidewalk ?? 12);
            const sw_right = r1.isSource ? (r1.edge.sidewalkRight ?? r1.edge.sidewalk ?? 12) : (r1.edge.sidewalkLeft ?? r1.edge.sidewalk ?? 12);
            const left = { x: r1.dir.y, y: -r1.dir.x };
            const right = { x: -r1.dir.y, y: r1.dir.x };
            const W = r1.edge.width / 2;
            const OW_L = W + sw_left;
            const OW_R = W + sw_right;
            corners.push({
              points: [
                { x: node.point.x + left.x * W, y: node.point.y + left.y * W, z: node.point.z },
                { x: node.point.x + right.x * W, y: node.point.y + right.y * W, z: node.point.z }
              ],
              sidewalkWidth: Math.max(sw_left, sw_right)
            });
            outerCorners.push([
                { x: node.point.x + left.x * OW_L, y: node.point.y + left.y * OW_L, z: node.point.z },
                { x: node.point.x + right.x * OW_R, y: node.point.y + right.y * OW_R, z: node.point.z }
            ]);
        } else {
            const [innerPts, outerPts] = calculateBothCornerPoints(
              node.point, 
              r1.dir, r1.edge.width, sw1, r1.edge.transitionSmoothness ?? 0,
              r2.dir, r2.edge.width, sw2, r2.edge.transitionSmoothness ?? 0,
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
      const bR = N === 1 ? corners[0].points[1] : corners[rIdx].points[0];
      const obL = N === 1 ? outerCorners[0][0] : outerCorners[i][outerCorners[i].length - 1];
      const obR = N === 1 ? outerCorners[0][1] : outerCorners[rIdx][0];

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
          mesh.sidewalkPolygons.push([obL, bL, sL, osL]);
          mesh.sidewalkTriangles.push([bL, sL, osL], [bL, osL, obL]);
          mesh.triangles.push([bL, sL, osL], [bL, osL, obL]);
        }
        if (distR < maxDist - 0.01) {
          hubPolygon.push(sR);
          mesh.sidewalkPolygons.push([osR, sR, bR, obR]);
          mesh.sidewalkTriangles.push([bR, osR, sR], [bR, obR, osR]);
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
      mesh.hubTriangles.push([node.point, p1, p2]);
      mesh.triangles.push([node.point, p1, p2]);
    }

    for (let i = 0; i < corners.length; i++) {
      const innerPts = corners[i].points;
      const outerPts = outerCorners[i];
      
      const poly = [...outerPts];
      poly.push(...[...innerPts].reverse());
      mesh.sidewalkPolygons.push(poly);
      
      for (let j = 0; j < innerPts.length - 1; j++) {
        mesh.sidewalkTriangles.push([innerPts[j], outerPts[j], outerPts[j+1]]);
        mesh.sidewalkTriangles.push([innerPts[j], outerPts[j+1], innerPts[j+1]]);
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

    const centerLine: { p: Point, dir: Point }[] = [];

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

      let dir = getDir(p1, p2);
      if (j < spline.length - 1) {
        dir = getDir(spline[j-1], spline[j+1]); 
      }
      
      centerLine.push({ p: p2, dir });
      const left = { x: dir.y, y: -dir.x };
      const right = { x: -dir.y, y: dir.x };
      const sw_left = edge.sidewalkLeft ?? edge.sidewalk ?? 12;
      const sw_right = edge.sidewalkRight ?? edge.sidewalk ?? 12;
      const OW_L = W + sw_left;
      const OW_R = W + sw_right;
      
      leftPoints.push({ x: p2.x + left.x * W, y: p2.y + left.y * W, z: p2.z });
      rightPoints.push({ x: p2.x + right.x * W, y: p2.y + right.y * W, z: p2.z });
      outerLeftPoints.push({ x: p2.x + left.x * OW_L, y: p2.y + left.y * OW_L, z: p2.z });
      outerRightPoints.push({ x: p2.x + right.x * OW_R, y: p2.y + right.y * OW_R, z: p2.z });
    }

    const cwWidth = 14;

    if (sourceBases && outerSourceBases) {
       let [bL, bR] = sourceBases;
       let [obL, obR] = outerSourceBases;
       
       if (isTrueJunction(sourceNode.id, nodes, edges)) {
         const sDir = getDir(spline[0], spline[Math.min(1, spline.length - 1)]);
         const sz = spline[0].z ?? 4;
         
         const new_bL = { x: bL.x + sDir.x * cwWidth, y: bL.y + sDir.y * cwWidth, z: sz };
         const new_bR = { x: bR.x + sDir.x * cwWidth, y: bR.y + sDir.y * cwWidth, z: sz };
         const new_obL = { x: obL.x + sDir.x * cwWidth, y: obL.y + sDir.y * cwWidth, z: sz };
         const new_obR = { x: obR.x + sDir.x * cwWidth, y: obR.y + sDir.y * cwWidth, z: sz };
         
         if (hasCrosswalk(edge.id, true, nodes, edges)) {
           mesh.crosswalks.push({ edgeId: edge.id, nodeId: sourceNode.id, polygon: [bL, bR, new_bR, new_bL] });
         }
         mesh.sidewalkPolygons.push([obL, bL, new_bL, new_obL]);
         mesh.sidewalkPolygons.push([bR, obR, new_obR, new_bR]);
         
         mesh.crosswalkTriangles.push([bL, bR, new_bR], [bL, new_bR, new_bL]);
         mesh.sidewalkTriangles.push([obL, bL, new_bL], [obL, new_bL, new_obL]);
         mesh.sidewalkTriangles.push([bR, obR, new_obR], [bR, new_obR, new_bR]);
         mesh.triangles.push([bL, bR, new_bR], [bL, new_bR, new_bL]);
         mesh.triangles.push([obL, bL, new_bL], [obL, new_bL, new_obL]);
         mesh.triangles.push([bR, obR, new_obR], [bR, new_obR, new_bR]);
         
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
           
           if (isTrueJunction(targetNode!.id, nodes, edges)) {
             const tDir = getDir(spline[spline.length - 1], spline[Math.max(0, spline.length - 2)]);
             const tz = spline[spline.length - 1].z ?? 4;
             
             const new_tbL = { x: tbL.x + tDir.x * cwWidth, y: tbL.y + tDir.y * cwWidth, z: tz };
             const new_tbR = { x: tbR.x + tDir.x * cwWidth, y: tbR.y + tDir.y * cwWidth, z: tz };
             const new_otbL = { x: otbL.x + tDir.x * cwWidth, y: otbL.y + tDir.y * cwWidth, z: tz };
             const new_otbR = { x: otbR.x + tDir.x * cwWidth, y: otbR.y + tDir.y * cwWidth, z: tz };
             
             if (hasCrosswalk(edge.id, false, nodes, edges)) {
               mesh.crosswalks.push({ edgeId: edge.id, nodeId: targetNode!.id, polygon: [tbL, tbR, new_tbR, new_tbL] });
             }
             mesh.sidewalkPolygons.push([otbL, tbL, new_tbL, new_otbL]);
             mesh.sidewalkPolygons.push([tbR, otbR, new_otbR, new_tbR]);
             
             mesh.crosswalkTriangles.push([tbL, tbR, new_tbR], [tbL, new_tbR, new_tbL]);
             mesh.sidewalkTriangles.push([otbL, tbL, new_tbL], [otbL, new_tbL, new_otbL]);
             mesh.sidewalkTriangles.push([tbR, otbR, new_otbR], [tbR, new_otbR, new_tbR]);
             mesh.triangles.push([tbL, tbR, new_tbR], [tbL, new_tbR, new_tbL]);
             mesh.triangles.push([otbL, tbL, new_tbL], [otbL, new_tbL, new_otbL]);
             mesh.triangles.push([tbR, otbR, new_otbR], [tbR, new_otbR, new_tbR]);
             
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
               const sw_left = edge.sidewalkLeft ?? edge.sidewalk ?? 12;
               const sw_right = edge.sidewalkRight ?? edge.sidewalk ?? 12;
               const OW_L = W + sw_left;
               const OW_R = W + sw_right;
               leftPoints.push({ x: p2.x + dir.y * W, y: p2.y + -dir.x * W, z: p2.z });
               rightPoints.push({ x: p2.x + -dir.y * W, y: p2.y + dir.x * W, z: p2.z });
               outerLeftPoints.push({ x: p2.x + dir.y * OW_L, y: p2.y + -dir.x * OW_L, z: p2.z });
               outerRightPoints.push({ x: p2.x + -dir.y * OW_R, y: p2.y + dir.x * OW_R, z: p2.z });
               poly = [bL, bR, ...rightPoints];
               outerPoly = [obL, obR, ...outerRightPoints];
               fullCenterLine.push({ p: p2, dir });
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
               mesh.dashedLines.push(linePoints);
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

                    if (lengthSoFar % totalDash < dashLength) {
                        const h1 = (p1.z ?? 4) + yOffset;
                        const br = { x: p1.x + right.x * width / 2, y: p1.y + right.y * width / 2, z: h1 };
                        const bl = { x: p1.x - right.x * width / 2, y: p1.y - right.y * width / 2, z: h1 };
                        
                        const h2 = (p2.z ?? 4) + yOffset;
                        const tr = { x: p2.x + right.x * width / 2, y: p2.y + right.y * width / 2, z: h2 };
                        const tl = { x: p2.x - right.x * width / 2, y: p2.y - right.y * width / 2, z: h2 };

                        mesh.dashedLineTriangles.push([bl, tr, tl], [bl, br, tr]);
                    }
                    lengthSoFar += dist;
                }
           } else {
               mesh.solidYellowLines.push(linePoints);
                const width = 2.0;
                const yOffset = 0.15;
                const spread = 1.5;

                for (let j = 1; j < linePoints.length; j++) {
                    const p1 = linePoints[j - 1];
                    const p2 = linePoints[j];
                    const dx = p2.x - p1.x;
                    const dy = p2.y - p1.y;
                    const len = Math.hypot(dx, dy);
                    const dir = len > 0 ? { x: dx/len, y: dy/len } : { x: 1, y: 0 };
                    const right = { x: -dir.y, y: dir.x };
                    
                    const h1 = (p1.z ?? 4) + yOffset;
                    const h2 = (p2.z ?? 4) + yOffset;

                    const r1 = { x: p1.x + right.x * spread, y: p1.y + right.y * spread, z: h1 };
                    const r2 = { x: p2.x + right.x * spread, y: p2.y + right.y * spread, z: h2 };
                    const br1 = { x: r1.x + right.x * width / 2, y: r1.y + right.y * width / 2, z: h1 };
                    const bl1 = { x: r1.x - right.x * width / 2, y: r1.y - right.y * width / 2, z: h1 };
                    const tr1 = { x: r2.x + right.x * width / 2, y: r2.y + right.y * width / 2, z: h2 };
                    const tl1 = { x: r2.x - right.x * width / 2, y: r2.y - right.y * width / 2, z: h2 };
                    mesh.solidLineTriangles.push([bl1, tr1, tl1], [bl1, br1, tr1]);

                    const l1 = { x: p1.x - right.x * spread, y: p1.y - right.y * spread, z: h1 };
                    const l2 = { x: p2.x - right.x * spread, y: p2.y - right.y * spread, z: h2 };
                    const br2 = { x: l1.x + right.x * width / 2, y: l1.y + right.y * width / 2, z: h1 };
                    const bl2 = { x: l1.x - right.x * width / 2, y: l1.y - right.y * width / 2, z: h1 };
                    const tr2 = { x: l2.x + right.x * width / 2, y: l2.y + right.y * width / 2, z: h2 };
                    const tl2 = { x: l2.x - right.x * width / 2, y: l2.y - right.y * width / 2, z: h2 };
                    mesh.solidLineTriangles.push([bl2, tr2, tl2], [bl2, br2, tr2]);
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
                   mesh.laneArrows.push({ position: pos, dir: center.dir === 1 ? dir : { x: -dir.x, y: -dir.y } });
               }
           }
       }
       
       const leftSidewalkPoly = [obL, bL, ...leftPoints];
       if (tbL) leftSidewalkPoly.push(tbL);
       if (otbL) leftSidewalkPoly.push(otbL);
       leftSidewalkPoly.push(...[...outerLeftPoints].reverse());
       mesh.sidewalkPolygons.push(leftSidewalkPoly);

       const rightSidewalkPoly = [bR, obR, ...outerRightPoints];
       if (otbR) rightSidewalkPoly.push(otbR);
       if (tbR) rightSidewalkPoly.push(tbR);
       rightSidewalkPoly.push(...[...rightPoints].reverse());
       mesh.sidewalkPolygons.push(rightSidewalkPoly);

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

       if (tbL && tbR && otbL && otbR) {
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

  return mesh;
}
