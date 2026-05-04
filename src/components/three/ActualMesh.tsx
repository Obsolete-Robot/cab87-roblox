import React, { useMemo } from 'react';
import * as THREE from 'three';
import { Point } from '../../lib/types';

export function ActualMesh({ mesh, showMesh }: { mesh: any, showMesh: boolean }) {
  const createGeo = (triangles: Point[][]) => {
    const points: THREE.Vector3[] = [];
    triangles.forEach(tri => {
      if (tri.length === 3) {
        // Render the actual flat mesh triangles
        const p0 = new THREE.Vector3(tri[0].x, tri[0].z ?? 4, tri[0].y);
        const p1 = new THREE.Vector3(tri[1].x, tri[1].z ?? 4, tri[1].y);
        const p2 = new THREE.Vector3(tri[2].x, tri[2].z ?? 4, tri[2].y);
        points.push(p0, p1, p2);
      }
    });
    const geo = new THREE.BufferGeometry().setFromPoints(points);
    geo.computeVertexNormals();
    return geo;
  };

  const roadGeo = useMemo(() => createGeo(mesh.roadTriangles || []), [mesh.roadTriangles]);
  const hubGeo = useMemo(() => createGeo(mesh.hubTriangles || []), [mesh.hubTriangles]);
  const swGeo = useMemo(() => createGeo(mesh.sidewalkTriangles || []), [mesh.sidewalkTriangles]);
  const cwGeo = useMemo(() => createGeo(mesh.crosswalkTriangles || []), [mesh.crosswalkTriangles]);

  const wireColor = showMesh ? "#22d3ee" : undefined;

  return (
    <group>
      <mesh geometry={roadGeo}>
        <meshStandardMaterial color={wireColor || "#1e293b"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={hubGeo}>
        <meshStandardMaterial color={wireColor || "#1e293b"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={swGeo}>
        <meshStandardMaterial color={wireColor || "#94a3b8"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={cwGeo}>
        <meshStandardMaterial color={wireColor || "#334155"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
    </group>
  );
}
