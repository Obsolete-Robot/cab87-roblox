import React, { useState, useEffect, useRef } from 'react';
import { Settings2, Trash2, Plus, Bug, Menu, X, Layers, Download, Upload } from 'lucide-react';
import { Point, Node, Edge, MeshData } from './lib/types';
import { getEdgeControlPoints, getExtendedEdgeControlPoints, sampleEdgeSpline } from './lib/network';
import { buildNetworkMesh } from './lib/meshing';
import { getDir, distToSegment } from './lib/math';
import { splitBezier } from './lib/splines';

const COLORS = ['#ef4444', '#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899'];

export default function App() {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [size, setSize] = useState({ w: 800, h: 600 });

  const [nodes, setNodes] = useState<Node[]>([
    { id: 'n1', point: { x: 400, y: 300 } },
    { id: 'n2', point: { x: 600, y: 150 } },
    { id: 'n3', point: { x: 200, y: 400 } },
    { id: 'n4', point: { x: 300, y: 100 } },
  ]);

  const [edges, setEdges] = useState<Edge[]>([
    { id: 'e1', source: 'n1', target: 'n2', points: [{x: 466, y: 250}, {x: 533, y: 200}], width: 60, sidewalk: 12, color: '#ef4444' },
    { id: 'e2', source: 'n1', target: 'n3', points: [{x: 333, y: 333}, {x: 266, y: 366}], width: 60, sidewalk: 12, color: '#10b981' },
    { id: 'e3', source: 'n1', target: 'n4', points: [{x: 366, y: 233}, {x: 333, y: 166}], width: 80, sidewalk: 12, color: '#3b82f6' },
  ]);

  const [selectedEdge, setSelectedEdge] = useState<string | null>(null);
  const [selectedNode, setSelectedNode] = useState<string | null>(null);
  const [isConnectMode, setIsConnectMode] = useState(false);
  const [showMesh, setShowMesh] = useState(false);
  const [showControlPoints, setShowControlPoints] = useState(true);
  const [view, setView] = useState({ x: 0, y: 0, zoom: 1 });
  const [dragging, setDragging] = useState<{ type: 'node' | 'edge' | 'pan'; id: string; pointId?: number } | null>(null);
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [selectedPointIndex, setSelectedPointIndex] = useState<number | null>(null);
  const [editingEdgeName, setEditingEdgeName] = useState<string | null>(null);
  const [editingNameValue, setEditingNameValue] = useState("");
  const [chamferAngle, setChamferAngle] = useState(70);
  
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleExport = () => {
    const data = JSON.stringify({ nodes, edges }, null, 2);
    const blob = new Blob([data], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'network.json';
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleImport = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (evt) => {
      try {
        const text = evt.target?.result as string;
        const data = JSON.parse(text);
        if (Array.isArray(data.nodes) && Array.isArray(data.edges)) {
          setNodes(data.nodes);
          setEdges(data.edges);
          setSelectedEdge(null);
          setSelectedNode(null);
          setSelectedPointIndex(null);
          setIsConnectMode(false);
          setDragging(null);
        } else {
          alert('Invalid file format. Must contain nodes and edges arrays.');
        }
      } catch (err) {
        alert('Failed to parse JSON file.');
      }
    };
    reader.readAsText(file);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const pointersRef = useRef<Map<number, Point>>(new Map());
  const lastPanMidpointRef = useRef<Point | null>(null);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // ignore keydown if typing in input
      if (document.activeElement?.tagName === 'INPUT' || document.activeElement?.tagName === 'TEXTAREA') return;

      if (e.key === 'Escape') {
        setSelectedNode(null);
        setSelectedEdge(null);
        setSelectedPointIndex(null);
        setDragging(null);
        setIsConnectMode(false);
      }
      if (e.key.toLowerCase() === 'c') {
        setIsConnectMode(prev => !prev);
      }
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (selectedNode) {
          setNodes(prev => prev.filter(n => n.id !== selectedNode));
          setEdges(prev => prev.filter(edge => edge.source !== selectedNode && edge.target !== selectedNode));
          setSelectedNode(null);
        } else if (selectedEdge && selectedPointIndex !== null) {
          setEdges(prev => prev.map(edge => {
            if (edge.id === selectedEdge) {
              const newPoints = [...edge.points];
              const anchorIndex = selectedPointIndex % 3 === 2 
                ? selectedPointIndex 
                : (selectedPointIndex % 3 === 1 ? selectedPointIndex + 1 : selectedPointIndex - 1);
              
              if (anchorIndex > 0 && anchorIndex < newPoints.length - 1) {
                newPoints.splice(anchorIndex - 1, 3);
              }
              return { ...edge, points: newPoints };
            }
            return edge;
          }));
          setSelectedPointIndex(null);
        } else if (selectedEdge) {
          setEdges(prev => prev.filter(edge => edge.id !== selectedEdge));
          setSelectedEdge(null);
          setSelectedPointIndex(null);
        }
      }
      if (e.key.toLowerCase() === 'f') {
        if (nodes.length > 0) {
          let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
          nodes.forEach(n => {
            minX = Math.min(minX, n.point.x);
            minY = Math.min(minY, n.point.y);
            maxX = Math.max(maxX, n.point.x);
            maxY = Math.max(maxY, n.point.y);
          });
          edges.forEach(edge => {
            edge.points.forEach(p => {
              minX = Math.min(minX, p.x);
              minY = Math.min(minY, p.y);
              maxX = Math.max(maxX, p.x);
              maxY = Math.max(maxY, p.y);
            });
          });
          
          if (minX !== Infinity) {
            const padding = 100;
            const w = Math.max(maxX - minX, 1);
            const h = Math.max(maxY - minY, 1);
            const zoomX = size.w / (w + padding * 2);
            const zoomY = size.h / (h + padding * 2);
            const newZoom = Math.min(zoomX, zoomY, 3); // Max zoom level
            
            const centerX = minX + w / 2;
            const centerY = minY + h / 2;
            
            setView({
              zoom: newZoom,
              x: size.w / 2 - centerX * newZoom,
              y: size.h / 2 - centerY * newZoom,
            });
          }
        }
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [selectedNode, selectedEdge, selectedPointIndex, nodes, edges, size]);

  useEffect(() => {
    if (!containerRef.current) return;
    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        setSize({ w: entry.contentRect.width, h: entry.contentRect.height });
      }
    });
    observer.observe(containerRef.current);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const handleWheel = (e: WheelEvent) => {
      e.preventDefault();
      const rect = canvas.getBoundingClientRect();
      const mx = e.clientX - rect.left;
      const my = e.clientY - rect.top;

      const delta = -e.deltaY * 0.001;
      const zoomFactor = Math.exp(delta);
      
      setView(prev => {
          const newZoom = Math.max(0.1, Math.min(5, prev.zoom * zoomFactor));
          const effectiveFactor = newZoom / prev.zoom;
          
          return {
              ...prev,
              zoom: newZoom,
              x: mx - (mx - prev.x) * effectiveFactor,
              y: my - (my - prev.y) * effectiveFactor,
          };
      });
    };
    canvas.addEventListener('wheel', handleWheel, { passive: false });
    return () => canvas.removeEventListener('wheel', handleWheel);
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = size.w * dpr;
    canvas.height = size.h * dpr;
    ctx.scale(dpr, dpr);
    canvas.style.width = `${size.w}px`;
    canvas.style.height = `${size.h}px`;

    ctx.save();
    ctx.translate(view.x, view.y);
    ctx.scale(view.zoom, view.zoom);
    draw(ctx, size, nodes, edges, selectedEdge, selectedNode, showMesh, chamferAngle);
    ctx.restore();
  }, [size, nodes, edges, selectedEdge, selectedNode, isConnectMode, showMesh, showControlPoints, view, chamferAngle]);

  const draw = (ctx: CanvasRenderingContext2D, size: { w: number; h: number }, nodes: Node[], edges: Edge[], selectedEdge: string | null, selectedNode: string | null, showMesh: boolean, chamferAngle: number) => {
    ctx.clearRect(0, 0, size.w, size.h);

    if (nodes.length === 0 || edges.length === 0) return;

    const mesh = buildNetworkMesh(nodes, edges, chamferAngle);

    if (showMesh) {
      mesh.triangles.forEach((tri, idx) => {
        ctx.beginPath();
        ctx.moveTo(tri[0].x, tri[0].y);
        ctx.lineTo(tri[1].x, tri[1].y);
        ctx.lineTo(tri[2].x, tri[2].y);
        ctx.closePath();
        
        ctx.fillStyle = `hsla(${(idx * 137) % 360}, 70%, 50%, 0.3)`;
        ctx.strokeStyle = `hsla(${(idx * 137) % 360}, 70%, 50%, 0.9)`;
        ctx.lineWidth = 1;
        ctx.fill();
        ctx.stroke();
      });
    }

    if (!showMesh) {
      // Background polygons
      ctx.fillStyle = '#1e293b'; 
      ctx.shadowColor = 'rgba(0,0,0,0.5)';
      ctx.shadowBlur = 15;
      ctx.shadowOffsetY = 4;
      
      // Draw outer polygons (sidewalks)
      ctx.fillStyle = '#94a3b8';

      mesh.roadPolygons.forEach(rp => {
        if (rp.outerPolygon && rp.outerPolygon.length > 0) {
            ctx.beginPath();
            ctx.moveTo(rp.outerPolygon[0].x, rp.outerPolygon[0].y);
            rp.outerPolygon.forEach(p => ctx.lineTo(p.x, p.y));
            ctx.closePath();
            ctx.fill();
        }
      });
      mesh.sidewalkPolygons.forEach(poly => {
        if (poly.length === 0) return;
        ctx.beginPath();
        ctx.moveTo(poly[0].x, poly[0].y);
        poly.forEach(p => ctx.lineTo(p.x, p.y));
        ctx.closePath();
        ctx.fill();
      });
      ctx.shadowColor = 'transparent';

      // Draw inner polygons (road surface)
      ctx.fillStyle = '#1e293b';
      mesh.hubs.forEach(hub => {
        if (hub.polygon.length === 0) return;
        ctx.beginPath();
        ctx.moveTo(hub.polygon[0].x, hub.polygon[0].y);
        hub.polygon.forEach(p => ctx.lineTo(p.x, p.y));
        ctx.closePath();
        ctx.fill();
      });

      mesh.roadPolygons.forEach(rp => {
        if (rp.polygon.length === 0) return;
        ctx.beginPath();
        ctx.moveTo(rp.polygon[0].x, rp.polygon[0].y);
        rp.polygon.forEach(p => ctx.lineTo(p.x, p.y));
        ctx.closePath();
        ctx.fill();
      });

      // Crosswalks
      ctx.fillStyle = '#334155'; // crosswalk background color
      mesh.crosswalks.forEach(cw => {
         if (cw.polygon.length === 0) return;
         ctx.beginPath();
         ctx.moveTo(cw.polygon[0].x, cw.polygon[0].y);
         cw.polygon.forEach(p => ctx.lineTo(p.x, p.y));
         ctx.closePath();
         ctx.fill();
      });

      ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
      ctx.lineWidth = 10;
      ctx.setLineDash([4, 6]); 
      ctx.beginPath();
      mesh.crosswalks.forEach(cw => {
         if (cw.polygon.length < 4) return;
         const p0 = cw.polygon[0]; // bL
         const p1 = cw.polygon[1]; // bR
         const p2 = cw.polygon[2]; // new_bR
         const p3 = cw.polygon[3]; // new_bL
         const midLeft = { x: (p0.x + p3.x)/2, y: (p0.y + p3.y)/2 };
         const midRight = { x: (p1.x + p2.x)/2, y: (p1.y + p2.y)/2 };
         ctx.moveTo(midLeft.x, midLeft.y);
         ctx.lineTo(midRight.x, midRight.y);
      });
      ctx.stroke();

      // Dashed CenterLines
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
      ctx.lineWidth = 2;
      ctx.setLineDash([15, 15]);
      ctx.beginPath();
      mesh.centerLines.forEach(cl => {
          if (cl.length > 0) {
            ctx.moveTo(cl[0].x, cl[0].y);
            for (let i = 1; i < cl.length; i++) ctx.lineTo(cl[i].x, cl[i].y);
          }
      });
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Nodes and control points
    nodes.forEach(n => {
        ctx.beginPath();
        ctx.arc(n.point.x, n.point.y, 8, 0, Math.PI * 2);
        ctx.fillStyle = selectedNode === n.id ? '#ffffff' : '#60a5fa';
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = '#fff';
        ctx.stroke();

        if (selectedNode === n.id) {
          ctx.beginPath();
          ctx.arc(n.point.x, n.point.y, 16, 0, Math.PI * 2);
          ctx.strokeStyle = isConnectMode ? 'rgba(52, 211, 153, 0.8)' : 'rgba(255, 255, 255, 0.4)';
          ctx.lineWidth = isConnectMode ? 3 : 2;
          ctx.stroke();
        }
    });

    edges.forEach((e) => {
        if (showControlPoints) {
            const controlPts = getExtendedEdgeControlPoints(e, nodes, edges, chamferAngle);
            if (controlPts.length > 0) {
                const cubicPts = controlPts;

                ctx.beginPath();
                ctx.strokeStyle = '#475569';
                ctx.lineWidth = 2;
                for (let i = 0; i < cubicPts.length - 1; i += 3) {
                    ctx.moveTo(cubicPts[i].x, cubicPts[i].y);
                    ctx.lineTo(cubicPts[i+1].x, cubicPts[i+1].y);
                    ctx.moveTo(cubicPts[i+2].x, cubicPts[i+2].y);
                    ctx.lineTo(cubicPts[i+3].x, cubicPts[i+3].y);
                }
                ctx.stroke();
                
                // Draw the invisible automatic nodes (indices 3, 6, 9 etc if they are anchors)
                // Actually, all anchors are at index i % 3 === 0
                ctx.fillStyle = '#94a3b8'; // light slate for automatic
                for (let i = 3; i < cubicPts.length - 1; i += 3) {
                    // Only draw if it's not a user-editable anchor.
                    // User anchors are normally at index 6, 12... wait.
                    // In getExtendedEdgeControlPoints, CW0 is at 3.
                    // then U1 is 4, U2 is 5, CW1 is 6!
                    // But wait, if there's a middle anchor A1, in extended it is:
                    // 3: CW0
                    // 4: U1
                    // 5: U2
                    // 6: A1 (user)
                    // 7: U3
                    // 8: U4
                    // 9: CW1
                    ctx.beginPath();
                    // Check if this anchor corresponds to a user anchor
                    // User points start at edge.points[0]. 
                    // In extended, index 4 is edge.points[0].
                    // So user points are at index 4, 5, 6, ...
                    // Is this index `i` an automatic point? 
                    // `i` is 3 (CW0) or `cubicPts.length - 4` (CW1).
                    // The other anchors (i=6, etc) are user anchors if there are multiple segments!
                    if (i === 3 || i === cubicPts.length - 4) {
                        ctx.arc(cubicPts[i].x, cubicPts[i].y, 4, 0, Math.PI * 2);
                        ctx.fill();
                    }
                }
            }
        }

        e.points.forEach((pt, j) => {
            const isAnchor = (j % 3 === 2);
            if (!showControlPoints && !isAnchor) return;

            ctx.beginPath();
            const isSelectedPoint = selectedEdge === e.id && selectedPointIndex === j;
            ctx.arc(pt.x, pt.y, isAnchor ? 8 : 5, 0, Math.PI * 2);
            ctx.fillStyle = selectedEdge === e.id ? (isSelectedPoint ? '#ef4444' : (isAnchor ? (pt.linked ? '#10b981' : '#fbbf24') : (pt.linear ? '#0ea5e9' : '#ffffff'))) : '#64748b';
            ctx.fill();
            ctx.stroke();
        });
    });
  };

  const getMousePos = (e: React.PointerEvent | React.MouseEvent) => {
    const rect = canvasRef.current!.getBoundingClientRect();
    return {
      x: (e.clientX - rect.left - view.x) / view.zoom,
      y: (e.clientY - rect.top - view.y) / view.zoom,
    };
  };

    const onContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    const pos = getMousePos(e);

    // Right click point to turn to node
    for (let i = edges.length - 1; i >= 0; i--) {
        const edge = edges[i];
        // Check control points
        for (let j = 0; j < edge.points.length; j++) {
            if (!showControlPoints && j % 3 !== 2) continue;
            if (Math.hypot(pos.x - edge.points[j].x, pos.y - edge.points[j].y) < 25) {
                const newNodeId = Math.random().toString(36).substring(2, 9);
                const newNode: Node = { id: newNodeId, point: edge.points[j] };
                const edge1: Edge = { ...edge, target: newNodeId, points: edge.points.slice(0, j) };
                const edge2: Edge = { ...edge, id: Math.random().toString(36).substring(2, 9), source: newNodeId, points: edge.points.slice(j + 1) };
                
                const newEdges = [edge1];
                if (edge2.points.length > 0 || edge2.target) newEdges.push(edge2);
                
                setNodes(prev => [...prev, newNode]);
                setEdges(prev => [...prev.filter(e => e.id !== edge.id), ...newEdges]);
                return;
            }
        }

        // Check if clicked ON a road segment to add a Node explicitly at any point
        // To accurately split, we need to find which control point segment was clicked.
        const pts = sampleEdgeSpline(edge, nodes, edges, chamferAngle);
        let hitIndex = -1;
        let minDist = Infinity;
        const threshold = Math.max(25, edge.width / 2);

        for (let j = 0; j < pts.length - 1; j++) {
            // Skip hitting exact hubs to allow node selection/creation near hubs
            if (nodes.some(n => Math.hypot(n.point.x - pts[j].x, n.point.y - pts[j].y) < 40)) continue;
            
            const d = distToSegment(pos, pts[j], pts[j+1]);
            if (d < minDist && d < threshold) {
                minDist = d;
                hitIndex = j;
            }
        }

        if (hitIndex !== -1) {
            // Split edge at new position
            const segmentsPerCurve = 15;
            const curveIndex = Math.floor(hitIndex / segmentsPerCurve);
            
            const controlPoints = getExtendedEdgeControlPoints(edge, nodes, edges, chamferAngle);
            const cubicPts = controlPoints;
            
            const numCurves = (cubicPts.length - 1) / 3;
            if (curveIndex === 0 || curveIndex === numCurves - 1) {
                continue;
            }
            
            const p0 = cubicPts[curveIndex * 3];
            const p1 = cubicPts[curveIndex * 3 + 1];
            const p2 = cubicPts[curveIndex * 3 + 2];
            const p3 = cubicPts[curveIndex * 3 + 3];

            let t = (hitIndex - curveIndex * segmentsPerCurve) / segmentsPerCurve;
            if (t < 0.1) t = 0.1;
            if (t > 0.9) t = 0.9;
            
            const { p01, p12, p23, p012, p123, pMid } = splitBezier(p0, p1, p2, p3, t);

            const newNodeId = Math.random().toString(36).substring(2, 9);
            const newNode: Node = { id: newNodeId, point: pMid };

            // We need to properly split the original edge logic. 
            // The original logic just passed p01, p012 etc to the new edge, but wait, those are interior points.
            // Edge points array only stores the user control points, so for edge1 it needs the first part of the split, and edge2 needs the second.
            // We should reconstruct the points arrays for the two new edges.
            
            const userCurveIndex = curveIndex - 1;
            
            const originalPoints = [...edge.points];
            const leftPoints = originalPoints.slice(0, userCurveIndex * 3);
            const rightPoints = originalPoints.slice(userCurveIndex * 3 + 2);
            
            leftPoints.push(p01, p012);
            rightPoints.unshift(p123, p23);

            const edge1: Edge = { ...edge, target: newNodeId, points: leftPoints };
            const edge2: Edge = { ...edge, id: Math.random().toString(36).substring(2, 9), source: newNodeId, points: rightPoints };
            
            const newEdges = [edge1, edge2];

            setNodes(prev => [...prev, newNode]);
            setEdges(prev => [...prev.filter(e => e.id !== edge.id), ...newEdges]);
            return;
        }
    }

    // Create free node
    const newNodeId = Math.random().toString(36).substring(2, 9);
    setNodes(prev => [...prev, { id: newNodeId, point: pos }]);
  };

  const onPointerDown = (e: React.PointerEvent) => {
    if (e.button === 2) return; // ignore right click

    const rect = canvasRef.current!.getBoundingClientRect();
    const rawPos = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    pointersRef.current.set(e.pointerId, rawPos);
    
    if (e.button === 1) { // middle mouse click
      e.preventDefault();
      setDragging({ type: 'pan', id: '' });
      lastPanMidpointRef.current = rawPos;
      return;
    }

    if (pointersRef.current.size === 2) {
      const pts = Array.from(pointersRef.current.values()) as Point[];
      lastPanMidpointRef.current = {
        x: (pts[0].x + pts[1].x) / 2,
        y: (pts[0].y + pts[1].y) / 2,
      };
      setDragging(null);
      return;
    }

    if (pointersRef.current.size > 1) return;

    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    const pos = getMousePos(e);

    // Click nodes
    for (const n of nodes) {
        if (Math.hypot(pos.x - n.point.x, pos.y - n.point.y) < 25) {
            if (e.altKey) {
                setEdges(prev => prev.map(edge => {
                    const newPts = [...edge.points];
                    let changed = false;
                    if (edge.source === n.id && newPts.length > 0) {
                        const targetNode = edge.target ? nodes.find(tn => tn.id === edge.target) : null;
                        const targetAnchor = newPts.length >= 3 ? newPts[2] : (targetNode ? targetNode.point : newPts[1]);
                        if (targetAnchor) {
                            newPts[0] = { ...newPts[0], x: n.point.x + (targetAnchor.x - n.point.x) / 3, y: n.point.y + (targetAnchor.y - n.point.y) / 3, linear: !newPts[0].linear };
                            changed = true;
                        }
                    }
                    if (edge.target === n.id && newPts.length > 1) {
                        const sourceNode = nodes.find(sn => sn.id === edge.source);
                        const prevAnchor = newPts.length >= 3 ? newPts[newPts.length - 3] : (sourceNode ? sourceNode.point : newPts[0]);
                        if (prevAnchor) {
                            newPts[newPts.length - 1] = { ...newPts[newPts.length - 1], x: n.point.x + (prevAnchor.x - n.point.x) / 3, y: n.point.y + (prevAnchor.y - n.point.y) / 3, linear: !newPts[newPts.length - 1].linear };
                            changed = true;
                        }
                    }
                    return changed ? { ...edge, points: newPts } : edge;
                }));
                setSelectedNode(n.id);
                setSelectedEdge(null);
                setSelectedPointIndex(null);
                setIsConnectMode(false);
                setDragging({ type: 'node', id: n.id });
                return;
            }

            if (selectedNode && selectedNode !== n.id && isConnectMode) {
                // Connect selectedNode to this node
                const sn = nodes.find(nn => nn.id === selectedNode)!;
                const id = Math.random().toString(36).substring(2, 9);
                const newEdge: Edge = {
                    id,
                    source: selectedNode,
                    target: n.id,
                    points: [
                      { x: sn.point.x + (n.point.x - sn.point.x)/3, y: sn.point.y + (n.point.y - sn.point.y)/3 },
                      { x: sn.point.x + 2*(n.point.x - sn.point.x)/3, y: sn.point.y + 2*(n.point.y - sn.point.y)/3 }
                    ],
                    width: 60,
                    sidewalk: 12,
                    color: COLORS[edges.length % COLORS.length]
                };
                setEdges(prev => [...prev, newEdge]);
                setSelectedNode(n.id);
                setSelectedEdge(id);
                setSelectedPointIndex(null);
                setIsConnectMode(false);
            } else {
                setDragging({ type: 'node', id: n.id });
                setSelectedNode(n.id);
                setSelectedEdge(null);
                setSelectedPointIndex(null);
            }
            return;
        }
    }

    // Click edge points
    for (let i = edges.length - 1; i >= 0; i--) {
      for (let j = 0; j < edges[i].points.length; j++) {
        if (!showControlPoints && j % 3 !== 2) continue;
        if (Math.hypot(pos.x - edges[i].points[j].x, pos.y - edges[i].points[j].y) < 25) {
          if (e.altKey) {
            setEdges(prev => prev.map(edge => {
              if (edge.id !== edges[i].id) return edge;
              const newPts = [...edge.points];
              const sourceNode = nodes.find(n => n.id === edge.source);
              if (!sourceNode) return edge;
              const targetNode = edge.target ? nodes.find(n => n.id === edge.target) : null;
              
              if (j % 3 === 2) {
                const prevAnchor = j === 2 ? sourceNode.point : newPts[j - 3];
                const nextAnchor = j + 3 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 3];
                newPts[j - 1] = { ...newPts[j - 1], x: newPts[j].x + (prevAnchor.x - newPts[j].x) / 3, y: newPts[j].y + (prevAnchor.y - newPts[j].y) / 3, linear: !newPts[j - 1].linear };
                if (targetNode || j + 3 < newPts.length) {
                    newPts[j + 1] = { ...newPts[j + 1], x: newPts[j].x + (nextAnchor.x - newPts[j].x) / 3, y: newPts[j].y + (nextAnchor.y - newPts[j].y) / 3, linear: !newPts[j + 1].linear };
                }
              } else if (j % 3 === 0) {
                if (newPts[j].linear) {
                    newPts[j] = { ...newPts[j], linear: false };
                } else {
                    const anchorA = j === 0 ? sourceNode.point : newPts[j - 1];
                    const anchorB = j + 2 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 2];
                    newPts[j] = { x: anchorA.x + (anchorB.x - anchorA.x) / 3, y: anchorA.y + (anchorB.y - anchorA.y) / 3, linear: true };
                }
              } else if (j % 3 === 1) {
                if (newPts[j].linear) {
                    newPts[j] = { ...newPts[j], linear: false };
                } else {
                    const anchorB = j + 1 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 1];
                    const anchorA = j === 1 ? sourceNode.point : newPts[j - 2];
                    newPts[j] = { x: anchorB.x + (anchorA.x - anchorB.x) / 3, y: anchorB.y + (anchorA.y - anchorB.y) / 3, linear: true };
                }
              }
              return { ...edge, points: newPts };
            }));
            
            setDragging({ type: 'edge', id: edges[i].id, pointId: j });
            setSelectedEdge(edges[i].id);
            setSelectedNode(null);
            return;
          }

          if (e.ctrlKey) {
            setEdges(prev => prev.map(edge => {
              if (edge.id !== edges[i].id) return edge;
              const newPts = [...edge.points];
              
              if (j % 3 === 2) {
                // Clicked anchor
                const anchor = newPts[j];
                if (anchor.linked) {
                    newPts[j] = { ...anchor, linked: false };
                } else if (j - 1 >= 0 && j + 1 < newPts.length) {
                    const h1 = newPts[j - 1];
                    const h2 = newPts[j + 1];
                    const angle = Math.atan2(h2.y - h1.y, h2.x - h1.x);
                    const d1 = Math.hypot(h1.x - anchor.x, h1.y - anchor.y);
                    const d2 = Math.hypot(h2.x - anchor.x, h2.y - anchor.y);
                    newPts[j - 1] = { x: anchor.x - Math.cos(angle) * d1, y: anchor.y - Math.sin(angle) * d1 };
                    newPts[j + 1] = { x: anchor.x + Math.cos(angle) * d2, y: anchor.y + Math.sin(angle) * d2 };
                    newPts[j] = { ...anchor, linked: true };
                }
              } else if (j % 3 === 0 || j % 3 === 1) {
                // Clicked handle
                const isIncoming = j % 3 === 1;
                const anchorIdx = isIncoming ? j + 1 : j - 1;
                const oppositeIdx = isIncoming ? j + 2 : j - 2;
                if (anchorIdx >= 0 && anchorIdx < newPts.length && oppositeIdx >= 0 && oppositeIdx < newPts.length) {
                    const anchor = newPts[anchorIdx];
                    if (anchor.linked) {
                        newPts[anchorIdx] = { ...anchor, linked: false };
                    } else {
                        const h1 = newPts[j];
                        const h2 = newPts[oppositeIdx];
                        const angle = Math.atan2(h1.y - anchor.y, h1.x - anchor.x);
                        const d2 = Math.hypot(h2.x - anchor.x, h2.y - anchor.y);
                        const oppAngle = angle + Math.PI;
                        newPts[oppositeIdx] = { x: anchor.x + Math.cos(oppAngle) * d2, y: anchor.y + Math.sin(oppAngle) * d2 };
                        newPts[anchorIdx] = { ...anchor, linked: true };
                    }
                }
              }
              return { ...edge, points: newPts };
            }));
            // Note: we DO NOT return here, so that dragging can immediately begin.
          }

          setDragging({ type: 'edge', id: edges[i].id, pointId: j });
          setSelectedEdge(edges[i].id);
          setSelectedNode(null);
          setSelectedPointIndex(j);
          return;
        }
      }
    }



    // Add point to edge middle
    for (let i = edges.length - 1; i >= 0; i--) {
      const edge = edges[i];
      const pts = sampleEdgeSpline(edge, nodes, edges, chamferAngle);
      let hitIndex = -1;
      let minDist = Infinity;
      const threshold = Math.max(25, edge.width / 2);

      for (let j = 0; j < pts.length - 1; j++) {
        // Skip hitting exact hubs to allow node selection/creation near hubs
        if (nodes.some(n => Math.hypot(n.point.x - pts[j].x, n.point.y - pts[j].y) < 40)) continue;
        
        const d = distToSegment(pos, pts[j], pts[j+1]);
        if (d < minDist && d < threshold) {
          minDist = d;
          hitIndex = j;
        }
      }

      if (hitIndex !== -1) {
        const segmentsPerCurve = 15;
        const curveIndex = Math.floor(hitIndex / segmentsPerCurve);
        
        // If clicking on the auto-generated straight segments at the hubs, ignore for inserting points.
        const numCurves = (getExtendedEdgeControlPoints(edge, nodes, edges, chamferAngle).length - 1) / 3;
        if (curveIndex === 0 || curveIndex === numCurves - 1) {
            continue;
        }
        
        const userCurveIndex = curveIndex - 1;

        setEdges((prev) => prev.map((e) => {
          if (e.id !== edge.id) return e;
          
          const controlPoints = getExtendedEdgeControlPoints(e, nodes, edges, chamferAngle);
          const cubicPts = controlPoints;
          
          const p0 = cubicPts[curveIndex * 3];
          const p1 = cubicPts[curveIndex * 3 + 1];
          const p2 = cubicPts[curveIndex * 3 + 2];
          const p3 = cubicPts[curveIndex * 3 + 3];
          
          // Split Bezier at t
          let t = (hitIndex - curveIndex * segmentsPerCurve) / segmentsPerCurve;
          if (t < 0.1) t = 0.1;
          if (t > 0.9) t = 0.9;
          
          const { p01, p12, p23, p012, p123, pMid } = splitBezier(p0, p1, p2, p3, t);

          const newPoints = [...e.points];
          
          if (newPoints.length < 2) {
              // Note: our logic requires at least 2 points for the user curve
              return { ...e, points: [p01, p012, pMid, p123, p23] };
          } else {
              const spliceIdx = userCurveIndex * 3; 
              newPoints.splice(spliceIdx, 2, p01, p012, pMid, p123, p23);
              return { ...e, points: newPoints };
          }
        }));
        setSelectedEdge(edge.id);
        setSelectedNode(null);
        
        // start dragging the newly created `pMid`
        const dragPointId = userCurveIndex * 3 + 2; 
        setSelectedPointIndex(dragPointId);
        setDragging({ type: 'edge', id: edge.id, pointId: dragPointId });
        
        return;
      }
    }

    // Click Empty Space
    if (selectedNode) {
        const newNodeId = Math.random().toString(36).substring(2, 9);
        const sn = nodes.find(n => n.id === selectedNode)!;
        const newEdgeId = Math.random().toString(36).substring(2, 9);
        const newEdge: Edge = {
            id: newEdgeId, source: selectedNode, target: newNodeId, points: [
              { x: sn.point.x + (pos.x - sn.point.x)/3, y: sn.point.y + (pos.y - sn.point.y)/3 },
              { x: sn.point.x + 2*(pos.x - sn.point.x)/3, y: sn.point.y + 2*(pos.y - sn.point.y)/3 }
            ], width: 60, sidewalk: 12, color: COLORS[edges.length % COLORS.length]
        };
        setNodes(prev => [...prev, { id: newNodeId, point: pos }]);
        setEdges(prev => [...prev, newEdge]);
        setSelectedEdge(newEdgeId);
        setSelectedNode(newNodeId);
        setSelectedPointIndex(null);
        setIsConnectMode(false);
        setDragging({ type: 'node', id: newNodeId });
        return;
    }

    // Default deselect
    setSelectedNode(null);
    setSelectedEdge(null);
    setSelectedPointIndex(null);
    setIsConnectMode(false);
  };

  const enforceLinear = (edge: Edge, currentNodes: Node[]) => {
      const newPts = [...edge.points];
      let changed = false;
      const sourceNode = currentNodes.find(n => n.id === edge.source);
      const targetNode = edge.target ? currentNodes.find(n => n.id === edge.target) : null;
      
      for (let j = 0; j < newPts.length; j++) {
          const handle = newPts[j];
          if (!handle.linear) continue;
          if (j % 3 === 0) {
              const anchorA = j === 0 ? sourceNode?.point : newPts[j - 1];
              const anchorB = j + 2 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 2];
              if (!anchorA || !anchorB) continue;
              const dx = anchorB.x - anchorA.x;
              const dy = anchorB.y - anchorA.y;
              const distAB = Math.hypot(dx, dy);
              if (distAB > 0.001) {
                  const dirX = dx / distAB;
                  const dirY = dy / distAB;
                  const hDist = Math.hypot(handle.x - anchorA.x, handle.y - anchorA.y);
                  newPts[j] = { ...handle, x: anchorA.x + dirX * hDist, y: anchorA.y + dirY * hDist };
                  changed = true;
              }
          } else if (j % 3 === 1) {
              const anchorA = j + 1 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 1];
              const anchorB = j === 1 ? sourceNode?.point : newPts[j - 2];
              if (!anchorA || !anchorB) continue;
              const dx = anchorB.x - anchorA.x;
              const dy = anchorB.y - anchorA.y;
              const distAB = Math.hypot(dx, dy);
              if (distAB > 0.001) {
                  const dirX = dx / distAB;
                  const dirY = dy / distAB;
                  const hDist = Math.hypot(handle.x - anchorA.x, handle.y - anchorA.y);
                  newPts[j] = { ...handle, x: anchorA.x + dirX * hDist, y: anchorA.y + dirY * hDist };
                  changed = true;
              }
          }
      }
      return changed ? { ...edge, points: newPts } : edge;
  };

  const onPointerMove = (e: React.PointerEvent) => {
    const rawPos = { x: e.clientX - canvasRef.current!.getBoundingClientRect().left, y: e.clientY - canvasRef.current!.getBoundingClientRect().top };
    pointersRef.current.set(e.pointerId, rawPos);

    if ((pointersRef.current.size === 2 || (dragging?.type === 'pan' && pointersRef.current.size === 1)) && lastPanMidpointRef.current) {
      const pts = Array.from(pointersRef.current.values()) as Point[];
      let newMidpoint = rawPos;
      if (pointersRef.current.size === 2) {
        newMidpoint = { x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2 };
      }
      const dx = newMidpoint.x - lastPanMidpointRef.current.x;
      const dy = newMidpoint.y - lastPanMidpointRef.current.y;
      setView(prev => ({ ...prev, x: prev.x + dx, y: prev.y + dy }));
      lastPanMidpointRef.current = newMidpoint;
      return;
    }

    if (!dragging || pointersRef.current.size > 1) return;
    const pos = getMousePos(e);

    if (dragging.type === 'node') {
        const draggingNode = nodes.find(n => n.id === dragging.id);
        if (draggingNode) {
            const dx = pos.x - draggingNode.point.x;
            const dy = pos.y - draggingNode.point.y;
            const newNodes = nodes.map(n => n.id === dragging.id ? { ...n, point: pos } : n);
            
            setNodes(newNodes);
            
            // Move only the explicitly connected control points (handles) with the node
            setEdges(prev => prev.map(edge => {
                if (edge.source === dragging.id || edge.target === dragging.id) {
                    const newPoints = [...edge.points];
                    if (edge.source === dragging.id && newPoints.length > 0) {
                        newPoints[0] = { ...newPoints[0], x: newPoints[0].x + dx, y: newPoints[0].y + dy };
                    }
                    if (edge.target === dragging.id && newPoints.length > 1) {
                        newPoints[newPoints.length - 1] = { 
                            ...newPoints[newPoints.length - 1],
                            x: newPoints[newPoints.length - 1].x + dx, 
                            y: newPoints[newPoints.length - 1].y + dy 
                        };
                    }
                    return enforceLinear({ ...edge, points: newPoints }, newNodes);
                }
                return edge;
            }));
        }
    } else if (dragging.type === 'edge' && dragging.pointId !== undefined) {
      setEdges((prev) => prev.map((edge) => {
        if (edge.id === dragging.id) {
          const newPoints = [...edge.points];
          const pid = dragging.pointId!;
          const oldPos = newPoints[pid];
          const dx = pos.x - oldPos.x;
          const dy = pos.y - oldPos.y;
          
          if (pid % 3 === 2) {
             // moving an anchor point, move its connected handles
             newPoints[pid] = { ...oldPos, x: pos.x, y: pos.y };
             if (pid - 1 >= 0) {
                 newPoints[pid - 1] = { ...newPoints[pid - 1], x: newPoints[pid - 1].x + dx, y: newPoints[pid - 1].y + dy };
             }
             if (pid + 1 < newPoints.length) {
                 newPoints[pid + 1] = { ...newPoints[pid + 1], x: newPoints[pid + 1].x + dx, y: newPoints[pid + 1].y + dy };
             }
          } else if (pid % 3 === 0 || pid % 3 === 1) {
             // moving a handle, check if its linear
             const handle = newPoints[pid];
             let effectivePos = pos;
             
             if (handle.linear) {
                 const sourceNode = nodes.find(n => n.id === edge.source);
                 const targetNode = edge.target ? nodes.find(n => n.id === edge.target) : null;
                 
                 let anchorA, anchorB;
                 if (pid % 3 === 0) {
                     anchorA = pid === 0 ? sourceNode?.point : newPoints[pid - 1];
                     anchorB = pid + 2 >= newPoints.length ? (targetNode ? targetNode.point : newPoints[pid]) : newPoints[pid + 2];
                 } else {
                     anchorA = pid + 1 >= newPoints.length ? (targetNode ? targetNode.point : newPoints[pid]) : newPoints[pid + 1];
                     anchorB = pid === 1 ? sourceNode?.point : newPoints[pid - 2];
                 }
                 
                 if (anchorA && anchorB) {
                     const dxL = anchorB.x - anchorA.x;
                     const dyL = anchorB.y - anchorA.y;
                     const distAB = Math.hypot(dxL, dyL);
                     if (distAB > 0.001) {
                         const dirX = dxL / distAB;
                         const dirY = dyL / distAB;
                         const vX = pos.x - anchorA.x;
                         const vY = pos.y - anchorA.y;
                         const dot = vX * dirX + vY * dirY;
                         // don't allow negative distance if we want it to stay between them or pointing the right way
                         const clampedDot = Math.max(0, dot);
                         effectivePos = { x: anchorA.x + dirX * clampedDot, y: anchorA.y + dirY * clampedDot };
                     }
                 }
             }

             newPoints[pid] = { ...handle, ...effectivePos };
             
             // Check if anchor is linked
             const isIncoming = pid % 3 === 1;
             const anchorIdx = isIncoming ? pid + 1 : pid - 1;
             const oppositeIdx = isIncoming ? pid + 2 : pid - 2;
             
             if (anchorIdx >= 0 && anchorIdx < newPoints.length && oppositeIdx >= 0 && oppositeIdx < newPoints.length) {
                 const anchor = newPoints[anchorIdx];
                 if (anchor.linked) {
                     const dxAngle = effectivePos.x - anchor.x;
                     const dyAngle = effectivePos.y - anchor.y;
                     const angle = Math.atan2(dyAngle, dxAngle);
                     const oppPos = newPoints[oppositeIdx];
                     const oppDist = Math.hypot(oppPos.x - anchor.x, oppPos.y - anchor.y);
                     const oppAngle = angle + Math.PI;
                     newPoints[oppositeIdx] = {
                         ...oppPos,
                         x: anchor.x + Math.cos(oppAngle) * oppDist,
                         y: anchor.y + Math.sin(oppAngle) * oppDist
                     };
                 }
             }
          }
          
          return enforceLinear({ ...edge, points: newPoints }, nodes);
        }
        return edge;
      }));
    }
  };

  const onPointerUp = (e: React.PointerEvent) => {
    pointersRef.current.delete(e.pointerId);
    if (pointersRef.current.size < 2 && dragging?.type !== 'pan') {
      lastPanMidpointRef.current = null;
    }

    if (dragging?.type === 'pan') {
      setDragging(null);
      lastPanMidpointRef.current = null;
      return;
    }

    if (dragging?.type === 'edge') {
        // If dropped near a node, attach it
        const pos = getMousePos(e);
        let targetNode = null;
        for (const n of nodes) {
            if (Math.hypot(pos.x - n.point.x, pos.y - n.point.y) < 30) {
                targetNode = n.id;
                break;
            }
        }

        if (targetNode) {
            setEdges(prev => prev.map(edge => {
                if (edge.id === dragging.id) {
                    // if it's the last point, set target
                    if (dragging.pointId === edge.points.length - 1 && edge.target === null && edge.source !== targetNode) {
                        const newPoints = [...edge.points];
                        newPoints.pop(); // remove point since it's now a node connection
                        return { ...edge, target: targetNode, points: newPoints };
                    }
                }
                return edge;
            }));
        }
    }

    (e.target as HTMLElement).releasePointerCapture(e.pointerId);
    setDragging(null);
  };

  const onPointerCancel = (e: React.PointerEvent) => {
    pointersRef.current.delete(e.pointerId);
    if (pointersRef.current.size < 2) {
      lastPanMidpointRef.current = null;
    }
    setDragging(null);
  };

  const addNode = () => {
    const id = Math.random().toString(36).substring(2, 9);
    setNodes(prev => [...prev, { id, point: { x: nodes[nodes.length-1]?.point.x + 100 || 400, y: nodes[nodes.length-1]?.point.y + 100 || 300 } }]);
  };

  const addEdge = () => {
      if (nodes.length === 0) return;
      const id = Math.random().toString(36).substring(2, 9);
      const tgtId = Math.random().toString(36).substring(2, 9);
      const srcNode = nodes[0];
      const tgtPos = { x: srcNode.point.x, y: srcNode.point.y + 100 };
      setNodes(prev => [...prev, { id: tgtId, point: tgtPos }]);
      setEdges(prev => [...prev, {
          id,
          source: srcNode.id,
          target: tgtId,
          points: [
              { x: srcNode.point.x, y: srcNode.point.y + 33 },
              { x: srcNode.point.x, y: srcNode.point.y + 66 }
          ],
          width: 60,
          sidewalk: 12,
          color: COLORS[prev.length % COLORS.length]
      }]);
  }

  return (
    <div className="w-full h-screen bg-slate-950 text-slate-300 font-sans flex flex-col overflow-hidden">
      <header className="h-14 lg:h-16 border-b border-slate-800 bg-slate-900/50 flex items-center justify-between px-4 lg:px-6 shrink-0 relative z-30">
        <div className="flex items-center gap-2 lg:gap-3">
          <button 
            onClick={() => setIsSidebarOpen(!isSidebarOpen)}
            className="p-2 lg:hidden text-slate-400 hover:text-white"
          >
            {isSidebarOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
          <div className="w-8 h-8 bg-blue-600 rounded flex items-center justify-center shrink-0">
            <Layers className="w-5 h-5 text-white" />
          </div>
          <h1 className="text-base lg:text-lg font-semibold tracking-tight text-white line-clamp-1">
            Network <span className="hidden sm:inline text-slate-500 font-normal">v3.0</span>
          </h1>
        </div>

        <div className="flex items-center gap-2 lg:gap-4">
          <button
            onClick={() => fileInputRef.current?.click()}
            className="p-2 lg:px-3 lg:py-1.5 border rounded text-sm font-semibold flex items-center gap-2 transition-colors border-slate-700 hover:bg-slate-800 text-slate-300"
            title="Import JSON"
          >
            <Upload className="w-4 h-4" />
            <span className="hidden xl:inline">Import</span>
          </button>
          <input
            type="file"
            accept=".json"
            ref={fileInputRef}
            onChange={handleImport}
            className="hidden"
          />
          <button
            onClick={handleExport}
            className="p-2 lg:px-3 lg:py-1.5 border rounded text-sm font-semibold flex items-center gap-2 transition-colors border-slate-700 hover:bg-slate-800 text-slate-300"
            title="Export JSON"
          >
            <Download className="w-4 h-4" />
            <span className="hidden xl:inline">Export</span>
          </button>
          <div className="w-px h-6 bg-slate-700 hidden sm:block mx-1"></div>
          <label className="flex items-center gap-2 cursor-pointer text-sm text-slate-300 font-medium hover:text-white sm:mr-2">
            <input 
              type="checkbox" 
              className="rounded bg-slate-800 border-slate-700 text-blue-600 focus:ring-blue-500 focus:ring-offset-slate-900 w-4 h-4 cursor-pointer"
              checked={showControlPoints} 
              onChange={(e) => setShowControlPoints(e.target.checked)} 
            />
            <span className="hidden md:inline">Show Control Points</span>
            <span className="md:hidden">Points</span>
          </label>
          <button
            onClick={() => setShowMesh(!showMesh)}
            className={`p-2 lg:px-3 lg:py-1.5 border rounded text-sm font-semibold flex items-center gap-2 transition-colors ${
              showMesh 
                ? 'bg-blue-600 border-blue-500 text-white hover:bg-blue-500' 
                : 'border-slate-700 hover:bg-slate-800 text-slate-300'
            }`}
          >
            <Layers className="w-4 h-4" />
            <span className="hidden md:inline">{showMesh ? 'Hide Mesh' : 'Show Mesh'}</span>
          </button>
        </div>
      </header>

      <div className="flex flex-grow overflow-hidden relative">
        <main className="flex-grow relative bg-slate-900 overflow-hidden" ref={containerRef}>
          <div 
            className="absolute inset-0 opacity-10 pointer-events-none" 
            style={{ 
              backgroundImage: 'radial-gradient(#64748b 1px, transparent 1px)', 
              backgroundSize: `${24 * view.zoom}px ${24 * view.zoom}px`,
              backgroundPosition: `${view.x}px ${view.y}px`
            }}
          ></div>
          
          <canvas
            ref={canvasRef}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerCancel}
            onContextMenu={onContextMenu}
            className="absolute inset-0 block outline-none cursor-crosshair touch-none"
          />

          <div className="absolute bottom-10 lg:bottom-6 left-1/2 -translate-x-1/2 lg:left-6 lg:translate-x-0 p-2.5 lg:p-3 bg-slate-900/80 backdrop-blur border border-slate-700 rounded-md shadow-xl flex gap-4 lg:gap-6 text-[9px] lg:text-[11px] font-medium tracking-wider uppercase pointer-events-none whitespace-nowrap z-10 flex-col sm:flex-row shadow-[0_0_20px_black] border-slate-600 flex-wrap justify-center">
            <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Right Click Edge</span> Create Node/Split</div>
            <div className="text-white font-bold flex flex-col gap-1.5 opacity-90">
              <span className={isConnectMode ? "text-emerald-400" : "text-blue-300"}>
                {isConnectMode ? "Click Node/Space" : "C"}
              </span> 
              {isConnectMode ? "Connect to / New Road" : "Connect Mode"}
            </div>
            <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Middle Drag / 2 Fingers</span> Pan</div>
            <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Scroll</span> Zoom</div>
            <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Click Edge</span> Add Point</div>
            <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Esc</span> Deselect</div>
          </div>
        </main>

        <aside className={`${isSidebarOpen ? 'translate-x-0' : 'translate-x-full lg:translate-x-0'} fixed lg:relative right-0 top-0 h-full w-full sm:w-80 lg:w-72 border-l border-slate-800 bg-slate-900 p-5 lg:p-6 flex flex-col gap-6 lg:gap-8 shrink-0 overflow-y-auto transition-transform duration-300 ease-in-out z-40 lg:z-10`}>
          <div className="flex items-center justify-between lg:hidden mb-2">
            <h2 className="text-white font-bold text-lg uppercase tracking-tight">Properties</h2>
            <button 
              onClick={() => setIsSidebarOpen(false)}
              className="p-2 text-slate-400 hover:text-white bg-slate-800 rounded-full"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          <section>
            <div className="flex gap-2 mb-4">
                <button onClick={addNode} className="flex-1 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded text-sm font-semibold flex justify-center items-center gap-2">Add Node</button>
                <button onClick={addEdge} className="flex-1 px-3 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded text-sm font-semibold flex justify-center items-center gap-2">Add Road</button>
            </div>
          </section>

          <section className="mb-6">
            <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4">Settings</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Chamfer Angle ({chamferAngle}°)
                </label>
                <div className="flex gap-2">
                  <input
                    type="range"
                    min="10"
                    max="180"
                    value={chamferAngle}
                    onChange={(e) => setChamferAngle(parseInt(e.target.value))}
                    className="flex-grow min-w-0"
                  />
                  <input
                    type="number"
                    min="10"
                    max="180"
                    value={chamferAngle}
                    onChange={(e) => setChamferAngle(parseInt(e.target.value) || 70)}
                    className="w-16 bg-slate-800 border bg-transparent text-white border-slate-700 rounded p-1 text-sm text-center"
                  />
                </div>
              </div>
            </div>
          </section>

          <section className="flex-grow flex flex-col min-h-0">
            <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4">Edges</h3>
            <div className="space-y-3 overflow-y-auto flex-grow pb-4">
              {edges.map((e, idx) => (
                <div
                  key={e.id}
                  onClick={() => setSelectedEdge(e.id)}
                  className={`p-3 lg:p-4 rounded-xl border transition-all cursor-pointer ${
                    selectedEdge === e.id
                      ? 'bg-blue-900/10 border-blue-500/50 ring-1 ring-blue-500/20'
                      : 'bg-slate-800/40 border-slate-800 hover:border-slate-700'
                  }`}
                >
                  <div className="flex justify-between items-center mb-3">
                    {editingEdgeName === e.id ? (
                      <input
                        autoFocus
                        value={editingNameValue}
                        onChange={(evt) => setEditingNameValue(evt.target.value)}
                        onBlur={() => {
                          setEdges(prev => prev.map(ed => ed.id === e.id ? { ...ed, name: editingNameValue } : ed));
                          setEditingEdgeName(null);
                        }}
                        onKeyDown={(evt) => {
                          if (evt.key === 'Enter') {
                            setEdges(prev => prev.map(ed => ed.id === e.id ? { ...ed, name: editingNameValue } : ed));
                            setEditingEdgeName(null);
                          } else if (evt.key === 'Escape') {
                            setEditingEdgeName(null);
                          }
                        }}
                        className="text-sm font-bold bg-slate-900 text-white px-1 py-0.5 rounded outline-none border border-blue-500 w-32"
                      />
                    ) : (
                      <span 
                        onDoubleClick={(evt) => {
                          evt.stopPropagation();
                          setEditingNameValue(e.name || `Road ${idx + 1}`);
                          setEditingEdgeName(e.id);
                        }}
                        className="text-sm font-bold text-slate-200 cursor-text"
                        title="Double-click to rename"
                      >
                        {e.name || `Road ${idx + 1}`}
                      </span>
                    )}
                    <button
                      onClick={(evt) => { evt.stopPropagation(); setEdges(prev => prev.filter(edge => edge.id !== e.id)); setSelectedEdge(null); }}
                      className="text-slate-500 hover:text-red-400 p-2 lg:p-1 rounded-lg hover:bg-slate-800 transition-colors"
                    >
                      <Trash2 className="w-4 h-4 opacity-70" />
                    </button>
                  </div>
                  <div className="flex flex-col gap-3">
                    <div>
                      <div className="flex justify-between text-xs text-slate-400 mb-1">
                        <span>Width</span>
                        <span>{e.width}px</span>
                      </div>
                      <input
                        type="range"
                        min="20"
                        max="200"
                        step="5"
                        value={e.width}
                        onChange={(evt) =>
                          setEdges((prev) =>
                            prev.map((pr) => (pr.id === e.id ? { ...pr, width: parseInt(evt.target.value) } : pr))
                          )
                        }
                        className="w-full accent-blue-600 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer"
                      />
                    </div>
                    <div>
                      <div className="flex justify-between text-xs text-slate-400 mb-1">
                        <span>Sidewalk</span>
                        <span>{e.sidewalk ?? 12}px</span>
                      </div>
                      <input
                        type="range"
                        min="0"
                        max="50"
                        step="2"
                        value={e.sidewalk ?? 12}
                        onChange={(evt) =>
                          setEdges((prev) =>
                            prev.map((pr) => (pr.id === e.id ? { ...pr, sidewalk: parseInt(evt.target.value) } : pr))
                          )
                        }
                        className="w-full accent-emerald-500 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer"
                      />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </section>
        </aside>
      </div>
    </div>
  );
}
