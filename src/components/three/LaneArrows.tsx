import React, { useMemo, useEffect, useRef } from 'react';
import * as THREE from 'three';
import { Point } from '../../lib/types';

export function LaneArrows({ arrows }: { arrows: { position: Point, dir: Point }[] }) {
  const instancedMeshRef = useRef<THREE.InstancedMesh>(null);
  const dummy = useMemo(() => new THREE.Object3D(), []);
  
  const geometry = useMemo(() => {
    const geo = new THREE.ConeGeometry(2, 6, 3);
    geo.rotateX(-Math.PI / 2); // Point forward along -Z
    return geo;
  }, []);

  useEffect(() => {
    if (instancedMeshRef.current) {
      arrows.forEach((arrow, i) => {
        dummy.position.set(arrow.position.x, (arrow.position.z ?? 4) + 0.5, arrow.position.y);
        
        // dir x,y corresponds to 3D x,z
        // Math.atan2(z, x) is the angle around Y
        const angle = Math.atan2(-arrow.dir.y, arrow.dir.x);
        dummy.rotation.set(0, angle - Math.PI / 2, 0);
        
        dummy.updateMatrix();
        instancedMeshRef.current!.setMatrixAt(i, dummy.matrix);
      });
      instancedMeshRef.current.instanceMatrix.needsUpdate = true;
    }
  }, [arrows, dummy]);

  if (!arrows || arrows.length === 0) return null;

  return (
    <instancedMesh ref={instancedMeshRef} args={[geometry, undefined, arrows.length]}>
      <meshBasicMaterial color="#ffffff" opacity={0.6} transparent depthWrite={false} />
    </instancedMesh>
  );
}
