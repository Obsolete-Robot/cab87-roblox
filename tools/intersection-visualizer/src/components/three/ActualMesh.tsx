import React, { useMemo } from 'react';
import * as THREE from 'three';
import { Point } from '../../lib/types';
import { createTriangleGeometry } from '../../lib/meshExport';

export function ActualMesh({ mesh, showMesh, debugOptions }: { mesh: any, showMesh: boolean, debugOptions?: any }) {
  const createGeo = (triangles: Point[][]) => {
    return createTriangleGeometry(triangles);
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

  const showRoads = debugOptions?.roads !== false;
  const showJunctions = debugOptions?.junctions !== false;
  const showSidewalks = debugOptions?.sidewalks !== false;
  const showCrossroads = debugOptions?.crossroads !== false;
  const showLines = debugOptions?.lines !== false;
  const showPolyFills = debugOptions?.polyFills !== false;

  return (
    <group>
      {showPolyFills && polygonGeos.map((pg: any, i: number) => (
        <mesh key={`poly-${i}`} geometry={pg.geo} position={[0, -1.5, 0]}>
          <meshStandardMaterial color={wireColor || pg.color} side={THREE.DoubleSide} wireframe={showMesh} transparent={true} opacity={0.7} />
        </mesh>
      ))}
      {showRoads && (
        <mesh geometry={roadGeo} position={[0, 0, 0]}>
          <meshStandardMaterial color={wireColor || "#1e293b"} side={THREE.DoubleSide} wireframe={showMesh} />
        </mesh>
      )}
      {showJunctions && (
        <mesh geometry={hubGeo} position={[0, 0.05, 0]}>
          <meshStandardMaterial color={wireColor || "#1e293b"} side={THREE.DoubleSide} wireframe={showMesh} />
        </mesh>
      )}
      {showCrossroads && (
        <mesh geometry={cwGeo} position={[0, 0.1, 0]}>
          <meshStandardMaterial color={wireColor || "#334155"} side={THREE.DoubleSide} wireframe={showMesh} />
        </mesh>
      )}
      {showSidewalks && (
        <mesh geometry={swGeo} position={[0, 0.15, 0]}>
          <meshStandardMaterial color={wireColor || "#94a3b8"} side={THREE.DoubleSide} wireframe={showMesh} />
        </mesh>
      )}
      {showLines && (
        <>
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
        </>
      )}
    </group>
  );
}
