import { Point, Triangle, MeshData, JunctionData } from "./types";
import { getDir } from "./math";

/**
 * Meshing engine that takes JunctionData and generates a triangular mesh.
 */
export function generateJunctionMesh(junction: JunctionData): MeshData {
  const { center, sortedRoads, corners } = junction;
  const N = sortedRoads.length;
  
  const hubPolygon: Point[] = [];
  corners.forEach(pts => hubPolygon.push(...pts));

  const vertices: Point[] = [];
  const triangles: Triangle[] = [];
  const roadPolygons: { id: string; polygon: Point[] }[] = [];

  // Hub Geometry (Center radiating outward to corners)
  for (let i = 0; i < hubPolygon.length; i++) {
    const p1 = hubPolygon[i];
    const p2 = hubPolygon[(i + 1) % hubPolygon.length];
    triangles.push([center, p1, p2]);
  }

  sortedRoads.forEach((r, i) => {
    const prevIdx = (i - 1 + N) % N;
    const cornerPrev = corners[prevIdx];
    const cornerCurr = corners[i];

    // Left base is the end of the previous corner. Right base is the start of the current corner.
    const bL = cornerPrev[cornerPrev.length - 1]; 
    const bR = cornerCurr[0]; 

    const dir = getDir(center, r.end);
    const left = { x: dir.y, y: -dir.x };
    const right = { x: -dir.y, y: dir.x };
    const W = r.width / 2;

    const eL = { x: r.end.x + left.x * W, y: r.end.y + left.y * W };
    const eR = { x: r.end.x + right.x * W, y: r.end.y + right.y * W };

    roadPolygons.push({ id: r.id, polygon: [bL, bR, eR, eL] });

    // Road triangles
    triangles.push([bL, bR, eR]);
    triangles.push([bL, eR, eL]);

    // Build the ordered silhouette boundary
    vertices.push(...cornerPrev);
    vertices.push(eL, eR);
  });

  return {
    vertices,
    triangles,
    hubPolygon,
    roadPolygons
  };
}
