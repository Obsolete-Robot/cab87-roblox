import React, { useMemo, useState, useEffect, useRef } from 'react';
import { Canvas, useThree, useFrame } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import * as THREE from 'three';
import { MeshData, Node, Edge, Point } from './lib/types';
import { buildNetworkMesh } from './lib/meshing';
import { getExtendedEdgeControlPoints } from './lib/network';

interface ThreeSceneProps {
  nodes: Node[];
  edges: Edge[];
  chamferAngle: number;
  meshResolution: number;
  setNodes: React.Dispatch<React.SetStateAction<Node[]>>;
  setEdges: React.Dispatch<React.SetStateAction<Edge[]>>;
  onPointerDown: (e: any) => void;
  onPointerMove: (e: any) => void;
  onPointerUp: (e: any) => void;
  onPointerCancel: (e: any) => void;
  onContextMenu: (e: any) => void;
  isDragging: boolean;
  selectedNode: string | null;
  selectedEdge: string | null;
  view: { x: number, y: number, zoom: number };
  setView: React.Dispatch<React.SetStateAction<{ x: number, y: number, zoom: number }>>;
  containerRef: React.RefObject<HTMLDivElement>;
}

function CameraSync({ setView, containerRef, controlsRef }: any) {
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

function PointerInterceptor({ onPointerDown, onPointerMove, onPointerUp, onContextMenu, onPointerCancel, isDragging, initialCameraParams, controlsRef }: any) {
   const { camera, raycaster, gl } = useThree();
   const plane = useMemo(() => new THREE.Plane().setFromNormalAndCoplanarPoint(new THREE.Vector3(0, 1, 0), new THREE.Vector3(0, 4, 0)), []);

   useEffect(() => {
      const getPos = (e: PointerEvent | MouseEvent) => {
         const rect = gl.domElement.getBoundingClientRect();
         const xp = ((e.clientX - rect.left) / rect.width) * 2 - 1;
         const yp = -((e.clientY - rect.top) / rect.height) * 2 + 1;
         raycaster.setFromCamera(new THREE.Vector2(xp, yp), camera);
         const target = new THREE.Vector3();
         raycaster.ray.intersectPlane(plane, target);
         if (target) return { x: target.x, y: target.z };
         return null;
      };

      const wrap = (e: any, handler: any) => {
         if (!handler) return;
         const pos = getPos(e);
         if (pos) {
            e.__scenePos = pos;
            handler(e);
         }
      };

      const down = (e: any) => wrap(e, onPointerDown);
      const move = (e: any) => wrap(e, onPointerMove);
      const up = (e: any) => wrap(e, onPointerUp);
      const ctx = (e: any) => wrap(e, onContextMenu);
      const cancel = (e: any) => wrap(e, onPointerCancel);

      gl.domElement.addEventListener('pointerdown', down);
      gl.domElement.addEventListener('pointermove', move);
      gl.domElement.addEventListener('pointerup', up);
      gl.domElement.addEventListener('contextmenu', ctx);
      gl.domElement.addEventListener('pointercancel', cancel);
      return () => {
         gl.domElement.removeEventListener('pointerdown', down);
         gl.domElement.removeEventListener('pointermove', move);
         gl.domElement.removeEventListener('pointerup', up);
         gl.domElement.removeEventListener('contextmenu', ctx);
         gl.domElement.removeEventListener('pointercancel', cancel);
      };
   }, [camera, raycaster, gl, plane, onPointerDown, onPointerMove, onPointerUp, onContextMenu, onPointerCancel]);

   return <OrbitControls 
      ref={controlsRef} 
      makeDefault 
      enabled={!isDragging} 
      target={initialCameraParams.target} 
      mouseButtons={{ LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.PAN, RIGHT: THREE.MOUSE.PAN }}
      enableDamping={false}
   />;
}

function ExtrudedPolygon({ points, color, height, yOffset = 0 }: { points: {x: number, y: number}[], color: string, height: number, yOffset?: number }) {
  const pointsHash = points.map(p => `${Math.round(p.x * 100)},${Math.round(p.y * 100)}`).join('|');
  const geometry = useMemo(() => {
    if (points.length < 3) return null;
    
    // Calculate signed area to ensure counter-clockwise winding
    let area = 0;
    for (let i = 0; i < points.length; i++) {
        const p1 = points[i];
        const p2 = points[(i + 1) % points.length];
        area += (p2.x - p1.x) * (p2.y + p1.y);
    }
    
    const orientedPoints = area > 0 ? [...points].reverse() : points;

    const shape = new THREE.Shape();
    shape.moveTo(orientedPoints[0].x, orientedPoints[0].y);
    for (let i = 1; i < orientedPoints.length; i++) {
      shape.lineTo(orientedPoints[i].x, orientedPoints[i].y);
    }
    shape.closePath();

    const extrudeSettings = {
      depth: height,
      bevelEnabled: false,
    };
    const geo = new THREE.ExtrudeGeometry(shape, extrudeSettings);
    // Extrude builds along +Z. Rotate 90 degrees around X axis so Z becomes Y.
    geo.rotateX(Math.PI / 2);
    // Now depth corresponds to -Y. Shift it up.
    geo.translate(0, yOffset + height, 0);
    
    geo.computeVertexNormals(); // Ensure proper lighting
    return geo;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pointsHash, height, yOffset]);

  if (!geometry) return null;

  return (
    <mesh geometry={geometry}>
      <meshStandardMaterial color={color} side={THREE.DoubleSide} />
    </mesh>
  );
}

function CenterLines({ lines }: { lines: {x: number, y: number}[][] }) {
  const lineGeometries = useMemo(() => {
    return lines.map(line => {
      if (line.length < 2) return null;
      const points = line.map(p => new THREE.Vector3(p.x, 0.5, p.y));
      const geo = new THREE.BufferGeometry().setFromPoints(points);
      return geo;
    }).filter(Boolean) as THREE.BufferGeometry[];
  }, [lines]);

  return (
    <group>
      {lineGeometries.map((geo, i) => (
        <primitive key={i} object={new THREE.Line(geo, new THREE.LineDashedMaterial({ color: "white", dashSize: 10, gapSize: 10, linewidth: 2 }))} />
      ))}
    </group>
  );
}

function BezierPaths({ edges, nodes, chamferAngle }: any) {
    const { tubes, lines } = useMemo(() => {
        const tubesList: THREE.TubeGeometry[] = [];
        const linesPoints: THREE.Vector3[] = [];
        
        edges.forEach((e: Edge) => {
            const cubicPts = getExtendedEdgeControlPoints(e, nodes, edges, chamferAngle);
            for (let i = 0; i + 3 < cubicPts.length; i += 3) {
                const curve = new THREE.CubicBezierCurve3(
                    new THREE.Vector3(cubicPts[i].x, 4, cubicPts[i].y),
                    new THREE.Vector3(cubicPts[i+1].x, 4, cubicPts[i+1].y),
                    new THREE.Vector3(cubicPts[i+2].x, 4, cubicPts[i+2].y),
                    new THREE.Vector3(cubicPts[i+3].x, 4, cubicPts[i+3].y)
                );
                tubesList.push(new THREE.TubeGeometry(curve, 20, 1.5, 8, false));
                
                // Add handles 
                linesPoints.push(new THREE.Vector3(cubicPts[i].x, 4, cubicPts[i].y));
                linesPoints.push(new THREE.Vector3(cubicPts[i+1].x, 4, cubicPts[i+1].y));
                linesPoints.push(new THREE.Vector3(cubicPts[i+2].x, 4, cubicPts[i+2].y));
                linesPoints.push(new THREE.Vector3(cubicPts[i+3].x, 4, cubicPts[i+3].y));
            }
        });
        
        const lineGeom = new THREE.BufferGeometry().setFromPoints(linesPoints);
        return { tubes: tubesList, lines: lineGeom };
    }, [edges, nodes]);

    return (
        <group>
            {tubes.map((geo, i) => (
                <mesh key={`tube-${i}`} geometry={geo}>
                    <meshBasicMaterial color="#fcd34d" />
                </mesh>
            ))}
            <primitive object={new THREE.LineSegments(lines, new THREE.LineBasicMaterial({ color: "#94a3b8", linewidth: 2 }))} />
        </group>
    );
}

function SceneContent({ mesh, nodes, edges, chamferAngle, onPointerDown, onPointerMove, onPointerUp, onPointerCancel, onContextMenu, isDragging, initialCameraParams, selectedNode, selectedEdge, setView, containerRef }: any) {
  const controlsRef = React.useRef<any>(null);

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
        initialCameraParams={initialCameraParams}
      />

      <group>
        <BezierPaths edges={edges} nodes={nodes} chamferAngle={chamferAngle} />
        {nodes.map((n: Node) => (
          <mesh 
            key={n.id} 
            position={[n.point.x, 4, n.point.y]}
          >
            <sphereGeometry args={[12, 16, 16]} />
            <meshStandardMaterial color={selectedNode === n.id ? "#ef4444" : "#60a5fa"} />
          </mesh>
        ))}

        {edges.flatMap((edge: Edge) => 
          edge.points.map((pt, i) => (
            <mesh 
              key={`edge-${edge.id}-${i}`}
              position={[pt.x, 4, pt.y]}
            >
              <sphereGeometry args={[(i % 3 === 2) ? 8 : 5, 16, 16]} />
              <meshStandardMaterial color={selectedEdge === edge.id ? "#ef4444" : "#fbbf24"} />
            </mesh>
          ))
        )}
      </group>

      {/* Sidewalks -> slightly taller */}
      {mesh.sidewalkPolygons.map((poly: any, i: number) => (
        <ExtrudedPolygon key={`sw-${i}`} points={poly} color="#94a3b8" height={2} yOffset={0} />
      ))}
      
      {/* Road Hubs (intersections) */}
      {mesh.hubs.map((hub: any, i: number) => (
        <ExtrudedPolygon key={`hub-${i}`} points={hub.polygon} color="#1e293b" height={1} yOffset={0.2} />
      ))}

      {/* Road Segments */}
      {mesh.roadPolygons.map((rp: any, i: number) => (
        <ExtrudedPolygon key={`rp-${i}`} points={rp.polygon} color="#1e293b" height={1} yOffset={0.2} />
      ))}

      {/* Crosswalks */}
      {mesh.crosswalks.map((cw: any, i: number) => (
        <ExtrudedPolygon key={`cw-${i}`} points={cw.polygon} color="#334155" height={1.2} yOffset={0.3} />
      ))}

      {/* Center lines */}
      <CenterLines lines={mesh.centerLines} />
    </group>
  );
}

export default function ThreeScene({ 
    nodes, edges, chamferAngle, meshResolution, 
    setNodes, setEdges, 
    onPointerDown, onPointerMove, onPointerUp, onPointerCancel, onContextMenu,
    isDragging, selectedNode, selectedEdge,
    view, setView, containerRef 
}: ThreeSceneProps) {
  const mesh = useMemo(() => buildNetworkMesh(nodes, edges, chamferAngle, meshResolution), [nodes, edges, chamferAngle, meshResolution]);

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
          nodes={nodes} 
          edges={edges} 
          chamferAngle={chamferAngle}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerCancel}
          onContextMenu={onContextMenu}
          isDragging={isDragging}
          selectedNode={selectedNode}
          selectedEdge={selectedEdge}
          initialCameraParams={initialCameraParams}
          setView={setView}
          containerRef={containerRef}
        />
      </Canvas>
    </div>
  );
}
