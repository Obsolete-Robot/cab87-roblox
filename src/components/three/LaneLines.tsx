import React, { useMemo } from 'react';
import * as THREE from 'three';
import { Point } from '../../lib/types';

export function LaneLines({ dashedLines, solidYellowLines }: { dashedLines: Point[][], solidYellowLines: Point[][] }) {
  const lineGeometries = useMemo(() => {
    const dashed = dashedLines.map(line => {
      if (line.length < 2) return null;
      const points = line.map(p => new THREE.Vector3(p.x, (p.z ?? 4) + 0.1, p.y));
      const geo = new THREE.BufferGeometry().setFromPoints(points);
      // required for LineDashedMaterial to work
      const tempLine = new THREE.Line(geo, new THREE.LineBasicMaterial());
      tempLine.computeLineDistances();
      return tempLine.geometry;
    }).filter(Boolean) as THREE.BufferGeometry[];

    const solid = solidYellowLines.map(line => {
      if (line.length < 2) return null;
      // create double yellow line points
      const points1: THREE.Vector3[] = [];
      const points2: THREE.Vector3[] = [];
      for (let i = 0; i < line.length; i++) {
          const p = line[i];
          let dir = new THREE.Vector2();
          if (i < line.length - 1) {
              dir.set(line[i+1].x - p.x, line[i+1].y - p.y).normalize();
          } else if (i > 0) {
              dir.set(p.x - line[i-1].x, p.y - line[i-1].y).normalize();
          } else {
              dir.set(1, 0);
          }
          // offset by 2 units on each side
          const right = new THREE.Vector2(-dir.y, dir.x).multiplyScalar(2);
          points1.push(new THREE.Vector3(p.x + right.x, (p.z ?? 4) + 0.1, p.y + right.y));
          points2.push(new THREE.Vector3(p.x - right.x, (p.z ?? 4) + 0.1, p.y - right.y));
      }
      return [
        new THREE.BufferGeometry().setFromPoints(points1),
        new THREE.BufferGeometry().setFromPoints(points2)
      ];
    }).filter(Boolean).flat() as THREE.BufferGeometry[];

    return { dashed, solid };
  }, [dashedLines, solidYellowLines]);

  return (
    <group>
      {lineGeometries.dashed.map((geo, i) => (
        <primitive key={`dashed-${i}`} object={new THREE.Line(geo, new THREE.LineDashedMaterial({ color: "#cccccc", dashSize: 6, gapSize: 6, linewidth: 2 }))} />
      ))}
      {lineGeometries.solid.map((geo, i) => (
        <primitive key={`solid-${i}`} object={new THREE.Line(geo, new THREE.LineBasicMaterial({ color: "#eab308", linewidth: 3 }))} />
      ))}
    </group>
  );
}
