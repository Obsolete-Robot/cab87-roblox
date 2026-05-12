import React, { useMemo } from 'react';
import { Canvas } from '@react-three/fiber';
import { Node, Edge, Point, PointSelection, BuildingPolygon, VisibilitySettings } from './lib/types';
import { buildNetworkMesh } from './lib/meshing';
import { SceneContent } from './components/three/SceneContent';

interface ThreeSceneProps {
  nodes: Node[];
  edges: Edge[];
  polygonFills: any[];
  buildings: BuildingPolygon[];
  chamferAngle: number;
  meshResolution: number;
  laneWidth?: number;
  showMesh: boolean;
  visibilitySettings: VisibilitySettings;
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
  selectedPoints: PointSelection[];
  selectedPolygonFillId: string | null;
  selectedBuildingId: string | null;
  selectedBuildingVertex: { buildingId: string; vertexIndex: number } | null;
  view: { x: number, y: number, zoom: number };
  setView: React.Dispatch<React.SetStateAction<{ x: number, y: number, zoom: number }>>;
  containerRef: React.RefObject<HTMLDivElement>;
  softSelectionEnabled: boolean;
  softSelectionRadius: number;
  draggingPoint: Point | null;
  marqueeStart?: Point | null;
  marqueeEnd?: Point | null;
  snapGridSize?: number;
  debugOptions: any;
}

export default function ThreeScene({
    nodes, edges, polygonFills, buildings, chamferAngle, meshResolution, laneWidth, showMesh, visibilitySettings,
    setNodes, setEdges,
    onPointerDown, onPointerMove, onPointerUp, onPointerCancel, onContextMenu,
    isDragging, draggingPoint, selectedNode, selectedNodes, selectedEdges, selectedPoints, selectedPolygonFillId, selectedBuildingId, selectedBuildingVertex,
    softSelectionEnabled, softSelectionRadius,
    view, setView, containerRef, marqueeStart, marqueeEnd, snapGridSize, debugOptions
}: ThreeSceneProps) {
  const mesh = useMemo(() => buildNetworkMesh(nodes, edges, chamferAngle, meshResolution, laneWidth || 30, polygonFills, buildings), [nodes, edges, chamferAngle, meshResolution, laneWidth, polygonFills, buildings]);

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
          buildings={buildings}
          showMesh={showMesh}
          visibilitySettings={visibilitySettings}
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
          selectedPoints={selectedPoints}
          selectedPolygonFillId={selectedPolygonFillId}
          selectedBuildingId={selectedBuildingId}
          selectedBuildingVertex={selectedBuildingVertex}
          initialCameraParams={initialCameraParams}
          softSelectionEnabled={softSelectionEnabled}
          softSelectionRadius={softSelectionRadius}
          setView={setView}
          containerRef={containerRef}
          marqueeStart={marqueeStart}
          marqueeEnd={marqueeEnd}
          snapGridSize={snapGridSize}
          debugOptions={debugOptions}
        />
      </Canvas>
    </div>
  );
}
