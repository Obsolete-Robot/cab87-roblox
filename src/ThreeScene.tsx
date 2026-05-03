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
  selectedEdges: string[];
  view: { x: number, y: number, zoom: number };
  setView: React.Dispatch<React.SetStateAction<{ x: number, y: number, zoom: number }>>;
  containerRef: React.RefObject<HTMLDivElement>;
  softSelectionEnabled: boolean;
  softSelectionRadius: number;
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

function PointerInterceptor({ 
   onPointerDown, onPointerMove, onPointerUp, onContextMenu, onPointerCancel, 
   isDragging, initialCameraParams, controlsRef, draggingPoint, nodes, edges 
}: any) {
   const { camera, raycaster, gl } = useThree();

   useEffect(() => {
      const getPos = (e: PointerEvent | MouseEvent) => {
         const rect = gl.domElement.getBoundingClientRect();
         const xp = ((e.clientX - rect.left) / rect.width) * 2 - 1;
         const yp = -((e.clientY - rect.top) / rect.height) * 2 + 1;
         raycaster.setFromCamera(new THREE.Vector2(xp, yp), camera);
         
         const target = new THREE.Vector3();
         
         if (e.shiftKey && isDragging && draggingPoint) {
            // Vertical dragging: intersect with a plane that faces the camera and passes through the point
            const cameraDir = new THREE.Vector3();
            camera.getWorldDirection(cameraDir);
            cameraDir.y = 0; // look horizontal
            cameraDir.normalize();
            
            const verticalPlane = new THREE.Plane().setFromNormalAndCoplanarPoint(
               cameraDir, 
               new THREE.Vector3(draggingPoint.x, draggingPoint.z ?? 4, draggingPoint.y)
            );
            
            raycaster.ray.intersectPlane(verticalPlane, target);
            if (target) return { x: draggingPoint.x, y: draggingPoint.y, z: target.y };
         } else {
            // Horizontal dragging or interaction
            let currentY = 4;
            
            if (isDragging && draggingPoint) {
               currentY = draggingPoint.z ?? 4;
            } else if (nodes && edges) {
               // Find closest point to snap interaction height
               let closestPt: THREE.Vector3 | null = null;
               let minDistSq = 15000; // rough capture radius, increased to handle zoomed-out views
               
               const checkPt = (pt: any) => {
                  if (!pt) return;
                  const pt3d = new THREE.Vector3(pt.x, pt.z ?? 4, pt.y);
                  const distSq = raycaster.ray.distanceSqToPoint(pt3d);
                  if (distSq < minDistSq) {
                     minDistSq = distSq;
                     closestPt = pt3d;
                  }
               };
               
               nodes.forEach((n: any) => checkPt(n.point));
               edges.forEach((e: any) => {
                  e.points.forEach((p: any) => checkPt(p));
               });
               
               if (closestPt) currentY = closestPt.y;
            }
            
            const horizontalPlane = new THREE.Plane().setFromNormalAndCoplanarPoint(
               new THREE.Vector3(0, 1, 0), 
               new THREE.Vector3(0, currentY, 0)
            );
            
            raycaster.ray.intersectPlane(horizontalPlane, target);
            if (target) {
               // If we are close to a point, actually snap the x and y coordinates returned so that
               // the 2D picking logic in App.tsx perfectly matches it!
               // But returning the target on the plane is usually good enough because raycaster intersection 
               // passing 'near' the point and intersecting the plane at the point's height guarantees the XZ intersection 
               // matches the point position closely.
               return { x: target.x, y: target.z, z: currentY };
            }
         }
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
   }, [camera, raycaster, gl, onPointerDown, onPointerMove, onPointerUp, onContextMenu, onPointerCancel]);

   return <OrbitControls 
      ref={controlsRef} 
      makeDefault 
      enabled={!isDragging} 
      target={initialCameraParams.target} 
      mouseButtons={{ LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.PAN, RIGHT: THREE.MOUSE.PAN }}
      enableDamping={false}
   />;
}

function ExtrudedPolygon({ points, color, height, yOffset = 0, wireframe = false }: { points: {x: number, y: number}[], color: string, height: number, yOffset?: number, wireframe?: boolean }) {
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
      {wireframe ? (
         <meshBasicMaterial color={color} wireframe={true} />
      ) : (
         <meshStandardMaterial color={color} side={THREE.DoubleSide} />
      )}
    </mesh>
  );
}

function LaneArrows({ arrows }: { arrows: { position: Point, dir: Point }[] }) {
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

function LaneLines({ dashedLines, solidYellowLines }: { dashedLines: Point[][], solidYellowLines: Point[][] }) {
  const lineGeometries = useMemo(() => {
    const dashed = dashedLines.map(line => {
      if (line.length < 2) return null;
      const points = line.map(p => new THREE.Vector3(p.x, (p.z ?? 4) + 0.1, p.y));
      const geo = new THREE.BufferGeometry().setFromPoints(points);
      // required for LineDashedMaterial to work
      const tempLine = new THREE.Line(geo, new THREE.LineBasicMaterial());
      tempLine.computeLineDistances();
      return tempLine.geometry;
    }).filter(Boolean) as THREE.BufferGeometry[];

    const solid = solidYellowLines.map(line => {
      if (line.length < 2) return null;
      // create double yellow line points
      const points1: THREE.Vector3[] = [];
      const points2: THREE.Vector3[] = [];
      for (let i = 0; i < line.length; i++) {
          const p = line[i];
          let dir = new THREE.Vector2();
          if (i < line.length - 1) {
              dir.set(line[i+1].x - p.x, line[i+1].y - p.y).normalize();
          } else if (i > 0) {
              dir.set(p.x - line[i-1].x, p.y - line[i-1].y).normalize();
          } else {
              dir.set(1, 0);
          }
          // offset by 2 units on each side
          const right = new THREE.Vector2(-dir.y, dir.x).multiplyScalar(2);
          points1.push(new THREE.Vector3(p.x + right.x, (p.z ?? 4) + 0.1, p.y + right.y));
          points2.push(new THREE.Vector3(p.x - right.x, (p.z ?? 4) + 0.1, p.y - right.y));
      }
      return [
        new THREE.BufferGeometry().setFromPoints(points1),
        new THREE.BufferGeometry().setFromPoints(points2)
      ];
    }).filter(Boolean).flat() as THREE.BufferGeometry[];

    return { dashed, solid };
  }, [dashedLines, solidYellowLines]);

  return (
    <group>
      {lineGeometries.dashed.map((geo, i) => (
        <primitive key={`dashed-${i}`} object={new THREE.Line(geo, new THREE.LineDashedMaterial({ color: "#cccccc", dashSize: 6, gapSize: 6, linewidth: 2 }))} />
      ))}
      {lineGeometries.solid.map((geo, i) => (
        <primitive key={`solid-${i}`} object={new THREE.Line(geo, new THREE.LineBasicMaterial({ color: "#eab308", linewidth: 3 }))} />
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
    }, [edges, nodes]);

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

function ActualMesh({ mesh, showMesh }: { mesh: any, showMesh: boolean }) {
  const createGeo = (triangles: Point[][]) => {
    const points: THREE.Vector3[] = [];
    triangles.forEach(tri => {
      if (tri.length === 3) {
        // Render the actual flat mesh triangles
        const p0 = new THREE.Vector3(tri[0].x, tri[0].z ?? 4, tri[0].y);
        const p1 = new THREE.Vector3(tri[1].x, tri[1].z ?? 4, tri[1].y);
        const p2 = new THREE.Vector3(tri[2].x, tri[2].z ?? 4, tri[2].y);
        points.push(p0, p1, p2);
      }
    });
    const geo = new THREE.BufferGeometry().setFromPoints(points);
    geo.computeVertexNormals();
    return geo;
  };

  const roadGeo = useMemo(() => createGeo(mesh.roadTriangles || []), [mesh.roadTriangles]);
  const hubGeo = useMemo(() => createGeo(mesh.hubTriangles || []), [mesh.hubTriangles]);
  const swGeo = useMemo(() => createGeo(mesh.sidewalkTriangles || []), [mesh.sidewalkTriangles]);
  const cwGeo = useMemo(() => createGeo(mesh.crosswalkTriangles || []), [mesh.crosswalkTriangles]);

  const wireColor = showMesh ? "#22d3ee" : undefined;

  return (
    <group>
      <mesh geometry={roadGeo}>
        <meshStandardMaterial color={wireColor || "#1e293b"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={hubGeo}>
        <meshStandardMaterial color={wireColor || "#1e293b"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={swGeo}>
        <meshStandardMaterial color={wireColor || "#94a3b8"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
      <mesh geometry={cwGeo}>
        <meshStandardMaterial color={wireColor || "#334155"} side={THREE.DoubleSide} wireframe={showMesh} />
      </mesh>
    </group>
  );
}

function SceneContent({ 
  mesh, showMesh, showControlPoints, nodes, edges, chamferAngle, 
  onPointerDown, onPointerMove, onPointerUp, onPointerCancel, onContextMenu, 
  isDragging, draggingPoint, initialCameraParams, selectedNode, selectedEdges, 
  softSelectionEnabled, softSelectionRadius,
  setView, containerRef 
}: any) {
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
        draggingPoint={draggingPoint}
        initialCameraParams={initialCameraParams}
        nodes={nodes}
        edges={edges}
      />

      <group>
        {showControlPoints && <BezierPaths edges={edges} nodes={nodes} chamferAngle={chamferAngle} />}
        {nodes.map((n: Node) => (
          <mesh 
            key={n.id} 
            position={[n.point.x, n.point.z ?? 4, n.point.y]}
            renderOrder={1000}
          >
            <sphereGeometry args={[12, 16, 16]} />
            <meshStandardMaterial color={selectedNode === n.id ? "#ef4444" : "#60a5fa"} depthTest={false} depthWrite={false} transparent />
          </mesh>
        ))}

        {edges.flatMap((edge: Edge) => 
          edge.points.map((pt, i) => {
            const isAnchor = (i % 3 === 2);
            if (!showControlPoints && !isAnchor) return null;
            return (
              <mesh 
                key={`edge-${edge.id}-${i}`}
                position={[pt.x, pt.z ?? 4, pt.y]}
                renderOrder={1000}
              >
                <sphereGeometry args={[isAnchor ? 8 : 5, 16, 16]} />
                <meshStandardMaterial color={selectedEdges.includes(edge.id) ? "#ef4444" : "#fbbf24"} depthTest={false} depthWrite={false} transparent />
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

export default function ThreeScene({ 
    nodes, edges, chamferAngle, meshResolution, laneWidth, showMesh, showControlPoints,
    setNodes, setEdges, 
    onPointerDown, onPointerMove, onPointerUp, onPointerCancel, onContextMenu,
    isDragging, draggingPoint, selectedNode, selectedEdges,
    softSelectionEnabled, softSelectionRadius,
    view, setView, containerRef 
}: ThreeSceneProps & { draggingPoint: Point | null, laneWidth: number }) {
  const mesh = useMemo(() => buildNetworkMesh(nodes, edges, chamferAngle, meshResolution, laneWidth), [nodes, edges, chamferAngle, meshResolution, laneWidth]);

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
          selectedEdges={selectedEdges}
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
