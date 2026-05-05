import React, { useMemo } from 'react';
import * as THREE from 'three';
import { Edge } from '../../lib/types';
import { getExtendedEdgeControlPoints } from '../../lib/network';

export function BezierPaths({ edges, nodes, chamferAngle }: any) {
    const { tubes, handleTubes } = useMemo(() => {
        const tubesList: THREE.TubeGeometry[] = [];
        const handleTubesList: THREE.TubeGeometry[] = [];
        
        edges.forEach((e: Edge) => {
            const cubicPts = getExtendedEdgeControlPoints(e, nodes, edges, chamferAngle);
            for (let i = 0; i + 3 < cubicPts.length; i += 3) {
                const curve = new THREE.CubicBezierCurve3(
                    new THREE.Vector3(cubicPts[i].x, cubicPts[i].z ?? 4, cubicPts[i].y),
                    new THREE.Vector3(cubicPts[i+1].x, cubicPts[i+1].z ?? 4, cubicPts[i+1].y),
                    new THREE.Vector3(cubicPts[i+2].x, cubicPts[i+2].z ?? 4, cubicPts[i+2].y),
                    new THREE.Vector3(cubicPts[i+3].x, cubicPts[i+3].z ?? 4, cubicPts[i+3].y)
                );
                tubesList.push(new THREE.TubeGeometry(curve, 20, 1.5, 8, false));
                
                // Add handles 
                const v0 = new THREE.Vector3(cubicPts[i].x, cubicPts[i].z ?? 4, cubicPts[i].y);
                const v1 = new THREE.Vector3(cubicPts[i+1].x, cubicPts[i+1].z ?? 4, cubicPts[i+1].y);
                const v2 = new THREE.Vector3(cubicPts[i+2].x, cubicPts[i+2].z ?? 4, cubicPts[i+2].y);
                const v3 = new THREE.Vector3(cubicPts[i+3].x, cubicPts[i+3].z ?? 4, cubicPts[i+3].y);

                if (v0.distanceTo(v1) > 0.01) {
                    const line1 = new THREE.LineCurve3(v0, v1);
                    handleTubesList.push(new THREE.TubeGeometry(line1, 2, 3.0, 8, false));
                }
                if (v2.distanceTo(v3) > 0.01) {
                    const line2 = new THREE.LineCurve3(v2, v3);
                    handleTubesList.push(new THREE.TubeGeometry(line2, 2, 3.0, 8, false));
                }
            }
        });
        
        return { tubes: tubesList, handleTubes: handleTubesList };
    }, [edges, nodes, chamferAngle]);

    return (
        <group>
            {tubes.map((geo, i) => (
                <mesh key={`tube-${i}`} geometry={geo} renderOrder={999}>
                    <meshBasicMaterial color="#fcd34d" depthTest={false} depthWrite={false} transparent />
                </mesh>
            ))}
            {handleTubes.map((geo, i) => (
                <mesh key={`handle-tube-${i}`} geometry={geo} renderOrder={999}>
                    <meshBasicMaterial color="#94a3b8" depthTest={false} depthWrite={false} transparent opacity={0.6} />
                </mesh>
            ))}
        </group>
    );
}
