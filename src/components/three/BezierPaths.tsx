import React, { useMemo } from 'react';
import * as THREE from 'three';
import { Edge } from '../../lib/types';
import { getExtendedEdgeControlPoints } from '../../lib/network';

export function BezierPaths({ edges, nodes, chamferAngle }: any) {
    const { tubes, lines } = useMemo(() => {
        const tubesList: THREE.TubeGeometry[] = [];
        const linesPoints: THREE.Vector3[] = [];
        
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
                linesPoints.push(new THREE.Vector3(cubicPts[i].x, cubicPts[i].z ?? 4, cubicPts[i].y));
                linesPoints.push(new THREE.Vector3(cubicPts[i+1].x, cubicPts[i+1].z ?? 4, cubicPts[i+1].y));
                linesPoints.push(new THREE.Vector3(cubicPts[i+2].x, cubicPts[i+2].z ?? 4, cubicPts[i+2].y));
                linesPoints.push(new THREE.Vector3(cubicPts[i+3].x, cubicPts[i+3].z ?? 4, cubicPts[i+3].y));
            }
        });
        
        const lineGeom = new THREE.BufferGeometry().setFromPoints(linesPoints);
        return { tubes: tubesList, lines: lineGeom };
    }, [edges, nodes, chamferAngle]);

    return (
        <group>
            {tubes.map((geo, i) => (
                <mesh key={`tube-${i}`} geometry={geo} renderOrder={999}>
                    <meshBasicMaterial color="#fcd34d" depthTest={false} depthWrite={false} transparent />
                </mesh>
            ))}
            <primitive object={new THREE.LineSegments(lines, new THREE.LineBasicMaterial({ color: "#94a3b8", linewidth: 2, depthTest: false, depthWrite: false, transparent: true }))} renderOrder={999} />
        </group>
    );
}
