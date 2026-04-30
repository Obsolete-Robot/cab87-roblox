import { calculateBothCornerPoints } from './src/lib/junctions';

const W1 = 10;
const W2 = 10;
const SW = 5;

for (let angle = 10; angle < 360; angle += 10) {
  const rad = angle * Math.PI / 180;
  const dir1 = { x: 1, y: 0 };
  const dir2 = { x: Math.cos(rad), y: Math.sin(rad) };
  
  const center = { x: 0, y: 0 };
  
  const cross = dir1.x * dir2.y - dir1.y * dir2.x;
  const dot = dir1.x * dir2.x + dir1.y * dir2.y;
  let interiorAngle = Math.atan2(cross, dot) * 180 / Math.PI;
  if (interiorAngle < 0) interiorAngle += 360;

  const right1 = { x: -dir1.y, y: dir1.x };
  const left2 = { x: dir2.y, y: -dir2.x };
  const A = { x: center.x + right1.x * W1, y: center.y + right1.y * W1 };
  const B = { x: center.x + left2.x * W2, y: center.y + left2.y * W2 };
  const dx = B.x - A.x;
  const dy = B.y - A.y;
  const t = (dx * dir2.y - dy * dir2.x) / cross;
  const u = (dx * dir1.y - dy * dir1.x) / cross;

  const res = calculateBothCornerPoints(center, dir1, W1*2, SW, 0, dir2, W2*2, SW, 0, 45);
  const pts = res[0].length;
  console.log(`${angle}\t| int=${interiorAngle.toFixed(1)}\t| t=${t.toFixed(1)}\t| u=${u.toFixed(1)}\t| points=${pts}`);
}
