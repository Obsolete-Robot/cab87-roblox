import React, { useEffect, useRef } from 'react';
import { useThree, useFrame } from '@react-three/fiber';
import * as THREE from 'three';

export function CameraSync({ setView, containerRef, controlsRef }: any) {
  const { camera } = useThree();
  const lastTarget = useRef<THREE.Vector3>(new THREE.Vector3());

  useFrame(() => {
    if (controlsRef.current) {
        lastTarget.current.copy(controlsRef.current.target);
    }
  });

  useEffect(() => {
    return () => {
      const target = lastTarget.current;
      const distance = camera.position.distanceTo(target);
      const fov = (camera as THREE.PerspectiveCamera).fov;
      const rad = (fov / 2) * (Math.PI / 180);

      const cW = containerRef.current?.clientWidth || 800;
      const cH = containerRef.current?.clientHeight || 600;

      const zoom = cH / (2 * distance * Math.tan(rad));

      setView({
        x: cW / 2 - target.x * zoom,
        y: cH / 2 - target.z * zoom,
        zoom
      });
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}
