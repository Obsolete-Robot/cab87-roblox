import React, { useRef } from 'react';
import * as THREE from 'three';
import { Node, Edge, Point } from '../../lib/types';
import { CameraSync } from './CameraSync';
import { PointerInterceptor } from './PointerInterceptor';
import { BezierPaths } from './BezierPaths';
import { ActualMesh } from './ActualMesh';
import { LaneArrows } from './LaneArrows';
import { Grid } from '@react-three/drei';

export function SceneContent({
  mesh, showMesh, showControlPoints, nodes, edges, chamferAngle, polygonFills, selectedPolygonFillId,
  onPointerDown, onPointerMove, onPointerUp, onPointerCancel, onContextMenu,
  isDragging, draggingPoint, initialCameraParams, selectedNode, selectedNodes, selectedEdges, selectedPointIndex,
  softSelectionEnabled, softSelectionRadius,
  setView, containerRef
}: any) {
  const controlsRef = useRef<any>(null);

  return (
    <group>
      <ambientLight intensity={0.4} />
      <directionalLight position={[500, 1000, 500]} intensity={0.8} castShadow />

      <Grid
        infiniteGrid
        fadeDistance={5000}
        sectionColor="#404040"
        cellColor="#262626"
        position={[0, -0.2, 0]}
        cellSize={20}
        sectionSize={100}
        cellThickness={1}
        sectionThickness={2}
      />

      <CameraSync setView={setView} containerRef={containerRef} controlsRef={controlsRef} />

      <PointerInterceptor
        controlsRef={controlsRef}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerCancel}
        onContextMenu={onContextMenu}
        isDragging={isDragging}
        draggingPoint={draggingPoint}
        initialCameraParams={initialCameraParams}
        nodes={nodes}
        edges={edges}
        selectedNode={selectedNode}
      />

      <group>
        {showControlPoints && <BezierPaths edges={edges} nodes={nodes} chamferAngle={chamferAngle} />}
        {polygonFills && polygonFills.map((fill: any, i: number) => {
          let cx = 0, cy = 0, count = 0;
          fill.points.forEach((nid: string) => {
             const n = nodes.find((nn: any) => nn.id === nid);
             if (n) { cx += n.point.x; cy += n.point.y; count++; }
          });
          if (count > 0) {
            cx /= count; cy /= count;
            const isSelected = selectedPolygonFillId === fill.id;
            return (
              <mesh key={`fill-handle-${fill.id}`} position={[cx, 5, cy]} renderOrder={1000}>
                <sphereGeometry args={[isSelected ? 10 : 8, 16, 16]} />
                <meshBasicMaterial color={isSelected ? "#ffffff" : fill.color} depthTest={false} depthWrite={false} transparent={true} />
                {isSelected && (
                  <mesh position={[0, 0, 0]} rotation={[-Math.PI / 2, 0, 0]}>
                    <ringGeometry args={[14, 16, 32]} />
                    <meshBasicMaterial color="#3b82f6" side={THREE.DoubleSide} transparent opacity={0.8} />
                  </mesh>
                )}
              </mesh>
            );
          }
          return null;
        })}
        {nodes.map((n: Node) => {
          const isActive = selectedNode === n.id;
          const isSelected = selectedNodes?.includes(n.id) || isActive;
          const color = isActive ? (n.point.linked ? '#059669' : '#ef4444') : isSelected ? (n.point.linked ? '#6ee7b7' : '#fca5a5') : (n.point.linked ? '#10b981' : '#60a5fa');
          return (
            <mesh
              key={n.id}
              position={[n.point.x, n.point.z ?? 4, n.point.y]}
              renderOrder={1000}
            >
              <sphereGeometry args={[14, 16, 16]} />
              <meshBasicMaterial color={color} depthTest={false} depthWrite={false} transparent />
            </mesh>
          );
        })}

        {edges.flatMap((edge: Edge) =>
          edge.points.map((pt: Point, i: number) => {
            const isAnchor = (i % 3 === 2);
            if (!showControlPoints && !isAnchor) return null;
            const isSelectedEdge = selectedEdges.includes(edge.id);
            const isSelectedPoint = isSelectedEdge && selectedPointIndex === i;

            let color = "#fbbf24";
            if (isSelectedPoint) {
              color = "#ef4444";
            } else if (isAnchor) {
              if (pt.linked) color = "#10b981";
              else color = isSelectedEdge ? "#fcd34d" : "#fbbf24";
            } else {
              if (pt.linear) color = "#0ea5e9";
              else color = "#ffffff";
              if (!isSelectedEdge) {
                color = pt.linear ? "#38bdf8" : "#e2e8f0";
              }
            }

            let rotY = 0;
            if (!isAnchor && pt.linear) {
              const anchorA = i % 3 === 0
                ? (i === 0 ? nodes.find((n: any) => n.id === edge.source)?.point : edge.points[i - 1])
                : (i + 1 >= edge.points.length ? nodes.find((n: any) => n.id === edge.target)?.point : edge.points[i + 1]);

              if (anchorA) {
                rotY = -Math.atan2(pt.y - anchorA.y, pt.x - anchorA.x);
              }
            }

            return (
              <mesh
                key={`edge-${edge.id}-${i}`}
                position={[pt.x, pt.z ?? 4, pt.y]}
                rotation={[0, rotY, 0]}
                renderOrder={1000}
              >
                {isAnchor ? (
                  pt.linked ? <octahedronGeometry args={[14, 0]} /> : <sphereGeometry args={[12, 16, 16]} />
                ) : (
                  pt.linear ? <boxGeometry args={[16, 16, 16]} /> : <sphereGeometry args={[10, 16, 16]} />
                )}
                <meshBasicMaterial color={color} depthTest={false} depthWrite={false} transparent />
              </mesh>
            );
          })
        )}
      </group>

      <ActualMesh mesh={mesh} showMesh={showMesh} />
      <LaneArrows arrows={mesh.laneArrows} showMesh={showMesh} />

      {softSelectionEnabled && isDragging && draggingPoint && (
        <mesh
          position={[draggingPoint.x, (draggingPoint.z ?? 4) + 0.1, draggingPoint.y]}
          rotation={[-Math.PI / 2, 0, 0]}
        >
          <ringGeometry args={[softSelectionRadius - 1, softSelectionRadius + 1, 128]} />
          <meshBasicMaterial color="white" transparent opacity={0.4} />
        </mesh>
      )}
    </group>
  );
}
