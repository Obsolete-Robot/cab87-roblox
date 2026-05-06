import React, { useMemo } from 'react';
import * as THREE from 'three';
import { Point } from '../../lib/types';

export function ActualMesh({ mesh, showMesh }: { mesh: any, showMesh: boolean }) {
  const createGeo = (triangles: Point[][]) => {
    const points: THREE.Vector3[] = [];
    const uvs: number[] = [];
    triangles.forEach(tri => {
      if (tri.length === 3) {
        // Render the actual flat mesh triangles
        const p0 = new THREE.Vector3(tri[0].x, tri[0].z ?? 4, tri[0].y);
        const p1 = new THREE.Vector3(tri[1].x, tri[1].z ?? 4, tri[1].y);
        const p2 = new THREE.Vector3(tri[2].x, tri[2].z ?? 4, tri[2].y);
        points.push(p0, p1, p2);

        uvs.push(tri[0].u ?? 0, tri[0].v ?? 0);
        uvs.push(tri[1].u ?? 0, tri[1].v ?? 0);
        uvs.push(tri[2].u ?? 0, tri[2].v ?? 0);
      }
    });
    const geo = new THREE.BufferGeometry().setFromPoints(points);
    if (uvs.length > 0) {
      geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
    }
    geo.computeVertexNormals();
    return geo;
  };

  const dashedMap = useMemo(() => {
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 128; // longer to represent a dash and a gap
    const ctx = canvas.getContext('2d');
    if (ctx) {
        ctx.fillStyle = '#cccccc';
        ctx.fillRect(0, 0, 64, 64);
        // keep bottom half clear for gap
    }

    const tex = new THREE.CanvasTexture(canvas);
    tex.wrapS = THREE.RepeatWrapping;
    tex.wrapT = THREE.RepeatWrapping;
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.LinearMipmapLinearFilter;
    tex.needsUpdate = true;
    return tex;
  }, []);

  const roadGeo = useMemo(() => createGeo(mesh.roadTriangles || []), [mesh.roadTriangles]);
  const hubGeo = useMemo(() => createGeo(mesh.hubTriangles || []), [mesh.hubTriangles]);
  const swGeo = useMemo(() => createGeo(mesh.sidewalkTriangles || []), [mesh.sidewalkTriangles]);
  const cwGeo = useMemo(() => createGeo(mesh.crosswalkTriangles || []), [mesh.crosswalkTriangles]);
  const dashedGeo = useMemo(() => createGeo(mesh.dashedLineTriangles || []), [mesh.dashedLineTriangles]);
  const solidGeo = useMemo(() => createGeo(mesh.solidLineTriangles || []), [mesh.solidLineTriangles]);

  const polygonGeos = useMemo(() => {
    if (!mesh.polygonTriangles) return [];
    return mesh.polygonTriangles.map((pGroup: { triangles: Point[][], color: string }) => ({
      geo: createGeo(pGroup.triangles),
      color: pGroup.color
    }));
  }, [mesh.polygonTriangles]);

  const wireColor = showMesh ? "#22d3ee" : undefined;

  return (
    <group>
      {polygonGeos.map((pg: any, i: number) => (
        <mesh key={`poly-${i}`} geometry={pg.geo} position={[0, -1.5, 0]}>
          <meshStandardMaterial color={wireColor || pg.color} side={THREE.DoubleSide} wireframe={showMesh} transparent={true} opacity={0.7} />
        </mesh>
      ))}
      <mesh geometry={roadGeo} position={[0, 0, 0]}>
        <meshStandardMaterial color={wireColor || "#1e293b"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={hubGeo} position={[0, 0.05, 0]}>
        <meshStandardMaterial color={wireColor || "#1e293b"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={cwGeo} position={[0, 0.1, 0]}>
        <meshStandardMaterial color={wireColor || "#334155"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={swGeo} position={[0, 0.15, 0]}>
        <meshStandardMaterial color={wireColor || "#94a3b8"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={dashedGeo} position={[0, 0, 0]}>
        <meshBasicMaterial
            map={showMesh ? undefined : dashedMap}
            color={showMesh ? "#cccccc" : 0xffffff}
            transparent={!showMesh}
            alphaTest={showMesh ? 0 : 0.5}
            side={THREE.DoubleSide}
            wireframe={showMesh}
        />
      </mesh>
      <mesh geometry={solidGeo} position={[0, 0, 0]}>
        <meshBasicMaterial color={wireColor || "#eab308"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
    </group>
  );
}
