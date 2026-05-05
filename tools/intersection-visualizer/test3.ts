import { calculateBothCornerPoints } from './src/lib/junctions';

const W1 = 10;
const W2 = 10;
const SW = 5;

for (let angle = 350; angle <= 350; angle += 10) {
  const rad = angle * Math.PI / 180;
  const dir1 = { x: 1, y: 0 };
  const dir2 = { x: Math.cos(rad), y: Math.sin(rad) };

  const center = { x: 0, y: 0 };

  // Custom manual calc for t and ot
  const cross = dir1.x * dir2.y - dir1.y * dir2.x;
  const right1 = { x: -dir1.y, y: dir1.x };
  const left2 = { x: dir2.y, y: -dir2.x };

  const A = { x: center.x + right1.x * W1, y: center.y + right1.y * W1 };
  const B = { x: center.x + left2.x * W2, y: center.y + left2.y * W2 };
  const dx = B.x - A.x;
  const dy = B.y - A.y;
  const t = (dx * dir2.y - dy * dir2.x) / cross;
  const u = (dx * dir1.y - dy * dir1.x) / cross;

  const OW1 = W1 + SW;
  const OW2 = W2 + SW;
  const OA = { x: center.x + right1.x * OW1, y: center.y + right1.y * OW1 };
  const OB = { x: center.x + left2.x * OW2, y: center.y + left2.y * OW2 };

  const odx = OB.x - OA.x;
  const ody = OB.y - OA.y;
  const ot = (odx * dir2.y - ody * dir2.x) / cross;
  const ou = (odx * dir1.y - ody * dir1.x) / cross;

  console.log(`${angle} | t=${t.toFixed(1)} | u=${u.toFixed(1)} | ot=${ot.toFixed(1)} | ou=${ou.toFixed(1)}`);
}
