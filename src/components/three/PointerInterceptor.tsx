import React, { useEffect } from 'react';
import { useThree } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import * as THREE from 'three';

export function PointerInterceptor({ 
   onPointerDown, onPointerMove, onPointerUp, onContextMenu, onPointerCancel, 
   isDragging, initialCameraParams, controlsRef, draggingPoint, nodes, edges, selectedNode 
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
            if (selectedNode && nodes) {
               const sn = nodes.find((n: any) => n.id === selectedNode);
               if (sn) {
                  currentY = sn.point.z ?? 4;
               }
            }
            
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
            e.__ray = {
               origin: raycaster.ray.origin.clone(),
               direction: raycaster.ray.direction.clone()
            };
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
   }, [camera, raycaster, gl, onPointerDown, onPointerMove, onPointerUp, onContextMenu, onPointerCancel, isDragging, draggingPoint, nodes, edges, selectedNode]);

   return <OrbitControls 
      ref={controlsRef} 
      makeDefault 
      enabled={!isDragging} 
      target={initialCameraParams.target} 
      mouseButtons={{ LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.PAN, RIGHT: THREE.MOUSE.PAN }}
      enableDamping={false}
   />;
}
