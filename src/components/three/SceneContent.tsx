import React, { useRef } from 'react';
import * as THREE from 'three';
import { Node, Edge, Point } from '../../lib/types';
import { CameraSync } from './CameraSync';
import { PointerInterceptor } from './PointerInterceptor';
import { BezierPaths } from './BezierPaths';
import { ActualMesh } from './ActualMesh';
import { LaneLines } from './LaneLines';
import { LaneArrows } from './LaneArrows';

export function SceneContent({ 
  mesh, showMesh, showControlPoints, nodes, edges, chamferAngle, 
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
        {nodes.map((n: Node) => {
          const isActive = selectedNode === n.id;
          const isSelected = selectedNodes?.includes(n.id) || isActive;
          return (
            <mesh 
              key={n.id} 
              position={[n.point.x, n.point.z ?? 4, n.point.y]}
              renderOrder={1000}
            >
              <sphereGeometry args={[12, 16, 16]} />
              <meshStandardMaterial color={isActive ? "#ef4444" : isSelected ? "#fca5a5" : "#60a5fa"} depthTest={false} depthWrite={false} transparent />
            </mesh>
          );
        })}

        {edges.flatMap((edge: Edge) => 
          edge.points.map((pt: Point, i: number) => {
            const isAnchor = (i % 3 === 2);
            if (!showControlPoints && !isAnchor) return null;
            const isSelectedEdge = selectedEdges.includes(edge.id);
            const isSelectedPoint = isSelectedEdge && selectedPointIndex === i;
            return (
              <mesh 
                key={`edge-${edge.id}-${i}`}
                position={[pt.x, pt.z ?? 4, pt.y]}
                renderOrder={1000}
              >
                <sphereGeometry args={[isAnchor ? 8 : 5, 16, 16]} />
                <meshStandardMaterial color={isSelectedPoint ? "#ef4444" : isSelectedEdge ? "#fca5a5" : "#fbbf24"} depthTest={false} depthWrite={false} transparent />
              </mesh>
            );
          })
        )}
      </group>

      <ActualMesh mesh={mesh} showMesh={showMesh} />
      {!showMesh && <LaneLines dashedLines={mesh.dashedLines} solidYellowLines={mesh.solidYellowLines} />}
      {!showMesh && <LaneArrows arrows={mesh.laneArrows} />}

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
