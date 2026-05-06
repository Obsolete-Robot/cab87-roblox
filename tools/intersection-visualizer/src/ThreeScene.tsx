import React, { useMemo } from 'react';
import { Canvas } from '@react-three/fiber';
import { MeshData, Node, Edge, Point } from './lib/types';
import { buildNetworkMesh } from './lib/meshing';
import { SceneContent } from './components/three/SceneContent';

interface ThreeSceneProps {
  nodes: Node[];
  edges: Edge[];
  polygonFills: any[];
  chamferAngle: number;
  meshResolution: number;
  laneWidth?: number;
  showMesh: boolean;
  showControlPoints: boolean;
  setNodes: React.Dispatch<React.SetStateAction<Node[]>>;
  setEdges: React.Dispatch<React.SetStateAction<Edge[]>>;
  onPointerDown: (e: any) => void;
  onPointerMove: (e: any) => void;
  onPointerUp: (e: any) => void;
  onPointerCancel: (e: any) => void;
  onContextMenu: (e: any) => void;
  isDragging: boolean;
  selectedNode: string | null;
  selectedNodes: string[];
  selectedEdges: string[];
  selectedPointIndex: number | null;
  selectedPolygonFillId: string | null;
  view: { x: number, y: number, zoom: number };
  setView: React.Dispatch<React.SetStateAction<{ x: number, y: number, zoom: number }>>;
  containerRef: React.RefObject<HTMLDivElement>;
  softSelectionEnabled: boolean;
  softSelectionRadius: number;
  draggingPoint: Point | null;
}

export default function ThreeScene({
    nodes, edges, polygonFills, chamferAngle, meshResolution, laneWidth, showMesh, showControlPoints,
    setNodes, setEdges,
    onPointerDown, onPointerMove, onPointerUp, onPointerCancel, onContextMenu,
    isDragging, draggingPoint, selectedNode, selectedNodes, selectedEdges, selectedPointIndex, selectedPolygonFillId,
    softSelectionEnabled, softSelectionRadius,
    view, setView, containerRef
}: ThreeSceneProps) {
  const mesh = useMemo(() => buildNetworkMesh(nodes, edges, chamferAngle, meshResolution, laneWidth || 30, polygonFills), [nodes, edges, chamferAngle, meshResolution, laneWidth, polygonFills]);

  const initialCameraParams = useMemo(() => {
    const cW = containerRef.current?.clientWidth || 800;
    const cH = containerRef.current?.clientHeight || 600;

    const centerX = (cW / 2 - view.x) / view.zoom;
    const centerY = (cH / 2 - view.y) / view.zoom;

    const fov = 45;
    const rad = (fov / 2) * (Math.PI / 180);
    const distance = (cH / view.zoom) / (2 * Math.tan(rad));

    return {
      position: [centerX, distance * 0.8, centerY + distance * 0.6] as [number, number, number],
      target: [centerX, 0, centerY] as [number, number, number],
      fov
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="absolute inset-0 bg-slate-950 z-20">
      <Canvas camera={{ position: initialCameraParams.position, fov: initialCameraParams.fov, far: 50000 }} style={{ touchAction: 'none' }}>
        <SceneContent
          mesh={mesh}
          polygonFills={polygonFills}
          showMesh={showMesh}
          showControlPoints={showControlPoints}
          nodes={nodes}
          edges={edges}
          chamferAngle={chamferAngle}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerCancel}
          onContextMenu={onContextMenu}
          isDragging={isDragging}
          draggingPoint={draggingPoint}
          selectedNode={selectedNode}
          selectedNodes={selectedNodes}
          selectedEdges={selectedEdges}
          selectedPointIndex={selectedPointIndex}
          selectedPolygonFillId={selectedPolygonFillId}
          initialCameraParams={initialCameraParams}
          softSelectionEnabled={softSelectionEnabled}
          softSelectionRadius={softSelectionRadius}
          setView={setView}
          containerRef={containerRef}
        />
      </Canvas>
    </div>
  );
}
