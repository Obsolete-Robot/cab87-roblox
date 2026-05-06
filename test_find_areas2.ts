import { getDir } from './src/lib/math';

const nodes = [
  { id: '1', point: { x: 0, y: 0 } },
  { id: '2', point: { x: 100, y: 0 } },
  { id: '3', point: { x: 100, y: 100 } },
  { id: '4', point: { x: 0, y: 100 } },
  { id: '5', point: { x: 200, y: 0 } },
  { id: '6', point: { x: 200, y: 100 } },
];
const edges = [
  { id: 'e1', source: '1', target: '2', points: [] },
  { id: 'e2', source: '2', target: '3', points: [] },
  { id: 'e3', source: '3', target: '4', points: [] },
  { id: 'e4', source: '4', target: '1', points: [] },
  { id: 'e5', source: '2', target: '5', points: [] },
  { id: 'e6', source: '5', target: '6', points: [] },
  { id: 'e7', source: '6', target: '3', points: [] },
];

function findFaces() {
  const halfEdges: any[] = [];
  for (const e of edges) {
    const n1 = nodes.find(n=>n.id === e.source)!;
    const n2 = nodes.find(n=>n.id === e.target)!;
    
    const d1 = getDir(n1.point, n2.point);
    halfEdges.push({ edgeId: e.id, from: e.source, to: e.target, dirOut: d1, dirIn: d1, angleOut: Math.atan2(d1.y, d1.x) });
    
    const d2 = getDir(n2.point, n1.point);
    halfEdges.push({ edgeId: e.id, from: e.target, to: e.source, dirOut: d2, dirIn: d2, angleOut: Math.atan2(d2.y, d2.x) });
  }

  const outMap = new Map();
  for (const he of halfEdges) {
    if (!outMap.has(he.from)) outMap.set(he.from, []);
    outMap.get(he.from).push(he);
  }

  for (const hes of outMap.values()) hes.sort((a:any, b:any) => a.angleOut - b.angleOut);

  const visited = new Set();
  const faces: any[] = [];

  for (const he of halfEdges) {
    const key = `${he.from}->${he.to}_${he.edgeId}`;
    if (visited.has(key)) continue;

    const faceNodes: string[] = [];
    let current = he;
    let isClosed = false;
    let maxIter = 100;

    while (maxIter-- > 0) {
      const curKey = `${current.from}->${current.to}_${current.edgeId}`;
      if (visited.has(curKey)) {
        if (curKey === key) isClosed = true;
        break;
      }
      visited.add(curKey);
      faceNodes.push(current.from);

      const hes = outMap.get(current.to) || [];
      const angleBack = Math.atan2(-current.dirIn.y, -current.dirIn.x);
      
      let nextHe = hes[0];
      for (const next of hes) {
        if (next.angleOut > angleBack + 1e-5) {
          nextHe = next;
          break;
        }
      }
      current = nextHe;
    }

    if (isClosed && faceNodes.length >= 3) {
      let signedArea = 0;
      for (let i = 0; i < faceNodes.length; i++) {
        const p1 = nodes.find(n => n.id === faceNodes[i])?.point!;
        const p2 = nodes.find(n => n.id === faceNodes[(i + 1) % faceNodes.length])?.point!;
        signedArea += (p1.x * p2.y - p2.x * p1.y);
      }
      if (signedArea < -1) { // CHANGED TO NEGATIVE
        faces.push(faceNodes);
      }
    }
  }
  return faces;
}

console.log(findFaces());
