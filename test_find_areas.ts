import { findClosedAreas } from './src/lib/network';
const nodes: any[] = [
  { id: '1', point: { x: 0, y: 0 } },
  { id: '2', point: { x: 100, y: 0 } },
  { id: '3', point: { x: 100, y: 100 } },
  { id: '4', point: { x: 0, y: 100 } },
  { id: '5', point: { x: 200, y: 0 } },
  { id: '6', point: { x: 200, y: 100 } },
];
const edges: any[] = [
  { id: 'e1', source: '1', target: '2', points: [] },
  { id: 'e2', source: '2', target: '3', points: [] },
  { id: 'e3', source: '3', target: '4', points: [] },
  { id: 'e4', source: '4', target: '1', points: [] },
  { id: 'e5', source: '2', target: '5', points: [] },
  { id: 'e6', source: '5', target: '6', points: [] },
  { id: 'e7', source: '6', target: '3', points: [] },
];
console.log(findClosedAreas(nodes, edges));
