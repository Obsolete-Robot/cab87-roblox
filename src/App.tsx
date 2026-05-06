import React, { useState, useEffect, useRef, useMemo } from 'react';
import { Point, Node, Edge, PointSelection } from './lib/types';
import { getExtendedEdgeControlPoints, sampleEdgeSpline } from './lib/network';
import { getDir, distToSegment } from './lib/math';
import { splitBezier } from './lib/splines';
import ThreeScene from './ThreeScene';
import Sidebar from './components/Sidebar';
import Header from './components/Header';
import { drawNetwork2D } from './lib/render2d';
import { 
  COLORS, ROAD_NETWORK_SCHEMA, ROAD_NETWORK_VERSION, 
  sanitizeMeshResolution, DEFAULTS
} from './lib/constants';

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
    { id: 'e1', source: 'n1', target: 'n2', points: [{x: 466, y: 250, linear: true}, {x: 533, y: 200, linear: true}], width: DEFAULTS.roadWidth, sidewalk: DEFAULTS.sidewalkWidth, color: '#ef4444' },
    { id: 'e2', source: 'n1', target: 'n3', points: [{x: 333, y: 333, linear: true}, {x: 266, y: 366, linear: true}], width: DEFAULTS.roadWidth, sidewalk: DEFAULTS.sidewalkWidth, color: '#10b981' },
    { id: 'e3', source: 'n1', target: 'n4', points: [{x: 366, y: 233, linear: true}, {x: 333, y: 166, linear: true}], width: 80, sidewalk: DEFAULTS.sidewalkWidth, color: '#3b82f6' },
  ]);

  const [selectedEdges, setSelectedEdges] = useState<string[]>([]);
  const lastDragPosRef = useRef<Point | null>(null);
  const startDragPosRef = useRef<Point | null>(null);
  const addedToSelectionRef = useRef<boolean>(false);
  const [selectedNodes, setSelectedNodes] = useState<string[]>([]);
  const selectedNode = selectedNodes.length > 0 ? selectedNodes[selectedNodes.length - 1] : null;

  const setSelectedNode = (id: string | null) => {
    setSelectedNodes(id ? [id] : []);
  };
  const [isAddNodeMode, setIsAddNodeMode] = useState(false);
  
  const [dragging, setDragging] = useState<{ type: 'node' | 'edge' | 'pan' | 'marquee'; id: string; pointId?: number } | null>(null);
  const [marqueeStart, setMarqueeStart] = useState<Point | null>(null);
  const [marqueeEnd, setMarqueeEnd] = useState<Point | null>(null);

  const draggingPoint = useMemo(() => {
    if (!dragging) return null;
    if (dragging.type === 'node') return nodes.find(n => n.id === dragging.id)?.point || null;
    if (dragging.type === 'edge') {
        const edge = edges.find(e => e.id === dragging.id);
        if (dragging.pointId != null) return edge ? edge.points[dragging.pointId] : null;
        else if (lastDragPosRef.current) return lastDragPosRef.current;
    }
    return null;
  }, [dragging, nodes, edges]);

  const [isMergeMode, setIsMergeMode] = useState(false);
  const [showMesh, setShowMesh] = useState(false);
  const [showControlPoints, setShowControlPoints] = useState(true);
  const [view, setView] = useState({ x: 0, y: 0, zoom: 1 });
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [selectedPoints, setSelectedPoints] = useState<PointSelection[]>([]);
  const [selectedPolygonFillId, setSelectedPolygonFillId] = useState<string | null>(null);
  const [chamferAngle, setChamferAngle] = useState(DEFAULTS.chamferAngle);
  const [meshResolution, setMeshResolution] = useState(DEFAULTS.meshResolution);
  const [laneWidth, setLaneWidth] = useState(DEFAULTS.laneWidth);
  const [is3DMode, setIs3DMode] = useState(false);
  const [softSelectionEnabled, setSoftSelectionEnabled] = useState(false);
  const [softSelectionRadius, setSoftSelectionRadius] = useState(DEFAULTS.softSelectionRadius);

  const [polygonFills, setPolygonFills] = useState<{ id: string; points: string[]; color: string }[]>([]);

  const handleExport = () => {
    const data = JSON.stringify({
      schema: ROAD_NETWORK_SCHEMA,
      version: ROAD_NETWORK_VERSION,
      settings: {
        chamferAngleDeg: chamferAngle,
        meshResolution,
        laneWidth,
      },
      nodes,
      edges,
      polygonFills,
    }, null, 2);
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
        if (data.schema != null && data.schema !== ROAD_NETWORK_SCHEMA) {
          alert(`Unsupported road network schema: ${data.schema}`);
          return;
        }
        if (Array.isArray(data.nodes) && Array.isArray(data.edges)) {
          setNodes(data.nodes);
          setEdges(data.edges);
          if (typeof data.settings?.chamferAngleDeg === 'number') {
            setChamferAngle(data.settings.chamferAngleDeg);
          } else {
            setChamferAngle(DEFAULTS.chamferAngle);
          }
          const importedMeshResolution = data.settings?.meshResolution ?? data.settings?.splineSegments;
          if (typeof importedMeshResolution === 'number') {
            setMeshResolution(sanitizeMeshResolution(importedMeshResolution));
          } else {
            setMeshResolution(DEFAULTS.meshResolution);
          }
          if (typeof data.settings?.laneWidth === 'number') {
            setLaneWidth(data.settings.laneWidth);
          } else {
            setLaneWidth(DEFAULTS.laneWidth);
          }
          if (Array.isArray(data.polygonFills)) {
            setPolygonFills(data.polygonFills);
          } else {
            setPolygonFills([]);
          }
          setSelectedEdges([]);
          setSelectedNode(null);
          setSelectedPoints([]);
          setIsAddNodeMode(false);
          setDragging(null);
          setIsMergeMode(false);
        } else {
          alert('Invalid file format. Must contain nodes and edges arrays.');
        }
      } catch (err) {
        alert('Failed to parse JSON file.');
      }
    };
    reader.readAsText(file);
    e.target.value = '';
  };

  const pointersRef = useRef<Map<number, Point>>(new Map());
  const lastPanMidpointRef = useRef<Point | null>(null);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // ignore keydown if typing in input
      if (document.activeElement?.tagName === 'INPUT' || document.activeElement?.tagName === 'TEXTAREA') return;

      if (e.key === 'Escape') {
        setSelectedNode(null);
        setSelectedEdges([]);
        setSelectedPoints([]);
        setDragging(null);
        setIsAddNodeMode(false);
        setIsMergeMode(false);
      }
      if (e.key.toLowerCase() === 'c') {
        setIsAddNodeMode(prev => !prev);
        setIsMergeMode(false);
      }
      if (e.key.toLowerCase() === 'm') {
        setIsMergeMode(prev => !prev);
        setIsAddNodeMode(false);
      }
      if (e.key.toLowerCase() === 'p' && !e.ctrlKey) {
        if (selectedNodes.length >= 3) {
           const id = Math.random().toString(36).substring(2, 9);
           const color = '#10b981'; // default fill color (emerald)
           setPolygonFills(prev => [...prev, { id, points: [...selectedNodes], color }]);
           setSelectedNodes([]);
        } else {
           alert("Select at least 3 nodes to create a polygon fill constraint.");
        }
      }
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (selectedPolygonFillId) {
            setPolygonFills(prev => prev.filter(p => p.id !== selectedPolygonFillId));
            setSelectedPolygonFillId(null);
            return;
        }
        let deletedSomething = false;
        if (selectedPoints.length > 0 && selectedNodes.length === 0 && selectedEdges.length === 0) {
          setEdges(prev => prev.map(edge => {
            const edgePoints = selectedPoints.filter(p => p.edgeId === edge.id);
            if (edgePoints.length > 0) {
              const newPoints = [...edge.points];
              // sort descending by point index to avoid index shifting when deleting
              const sortedIndices = edgePoints.map(p => p.pointIndex).sort((a, b) => b - a);
              const deletedAnchorIndices = new Set<number>();
              sortedIndices.forEach(idx => {
                const anchorIndex = idx % 3 === 2 ? idx : (idx % 3 === 1 ? idx + 1 : idx - 1);
                if (anchorIndex > 0 && anchorIndex < newPoints.length - 1 && !deletedAnchorIndices.has(anchorIndex)) {
                   newPoints.splice(anchorIndex - 1, 3);
                   deletedAnchorIndices.add(anchorIndex);
                }
              });
              return { ...edge, points: newPoints };
            }
            return edge;
          }));
          setSelectedPoints([]);
          deletedSomething = true;
        } else if (selectedNodes.length > 0 || selectedEdges.length > 0) {
          setNodes(prev => prev.filter(n => !selectedNodes.includes(n.id)));
          setEdges(prev => prev.filter(edge => !selectedEdges.includes(edge.id) && !selectedNodes.includes(edge.source) && (!edge.target || !selectedNodes.includes(edge.target))));
          setSelectedNodes([]);
          setSelectedEdges([]);
          setSelectedPoints([]);
          deletedSomething = true;
        }

        if (!deletedSomething) {
          // If nothing else is deleted, clear the last polygon
          setPolygonFills(prev => prev.length > 0 ? prev.slice(0, prev.length - 1) : prev);
        }
      }
      if (e.key.toLowerCase() === 'f' && !e.ctrlKey && e.key !== 'F') {
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
  }, [selectedNode, selectedEdges, selectedPoints, nodes, edges, size, isMergeMode, isAddNodeMode]);

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

  // Automatic junction unlinking
  useEffect(() => {
    setNodes(prev => {
      let changed = false;
      const newNodes = prev.map(n => {
        if (n.point.linked) {
          let nonLinearCount = 0;
          edges.forEach(e => {
            if (e.source === n.id && e.points.length > 0 && !e.points[0].linear) nonLinearCount++;
            if (e.target === n.id && e.points.length > 0 && !e.points[e.points.length - 1].linear) nonLinearCount++;
          });
          if (nonLinearCount < 2) {
            changed = true;
            return { ...n, point: { ...n.point, linked: false } };
          }
        }
        return n;
      });
      return changed ? newNodes : prev;
    });
  }, [edges]);

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
  }, [is3DMode]);

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
    drawNetwork2D(
      ctx, size, nodes, edges, selectedEdges, selectedNodes, selectedNode,
      showMesh, showControlPoints, isAddNodeMode, isMergeMode,
      chamferAngle, meshResolution, laneWidth, polygonFills,
      softSelectionEnabled, softSelectionRadius, draggingPoint, selectedPoints,
      selectedPolygonFillId, view
    );
    ctx.restore();

    if (marqueeStart && marqueeEnd) {
      ctx.save();
      ctx.translate(view.x, view.y);
      ctx.scale(view.zoom, view.zoom);
      ctx.fillStyle = 'rgba(59, 130, 246, 0.2)';
      ctx.strokeStyle = 'rgba(59, 130, 246, 0.8)';
      ctx.lineWidth = 1 / view.zoom;
      const x = Math.min(marqueeStart.x, marqueeEnd.x);
      const y = Math.min(marqueeStart.y, marqueeEnd.y);
      const w = Math.abs(marqueeEnd.x - marqueeStart.x);
      const h = Math.abs(marqueeEnd.y - marqueeStart.y);
      ctx.fillRect(x, y, w, h);
      ctx.strokeRect(x, y, w, h);
      ctx.restore();
    }
  }, [size, nodes, edges, selectedEdges, selectedNodes, selectedNode, selectedPoints, selectedPolygonFillId, isAddNodeMode, isMergeMode, showMesh, showControlPoints, view, chamferAngle, meshResolution, laneWidth, softSelectionEnabled, softSelectionRadius, draggingPoint, polygonFills, marqueeStart, marqueeEnd]);

  const getMousePos = (e: React.PointerEvent | React.MouseEvent | any) => {
    if (e.__scenePos) return e.__scenePos;
    const rect = canvasRef.current!.getBoundingClientRect();
    return {
      x: (e.clientX - rect.left - view.x) / view.zoom,
      y: (e.clientY - rect.top - view.y) / view.zoom,
    };
  };

    const onContextMenu = (e: React.MouseEvent | any) => {
    e.preventDefault();
  };

  const handleRightClick = (e: React.PointerEvent | any, pos: any) => {
    const getNewEdgeParams = (sn: Node, targetPt: Point) => {
        let params: any = {
            width: DEFAULTS.roadWidth,
            sidewalk: DEFAULTS.sidewalkWidth,
            color: COLORS[edges.length % COLORS.length]
        };

        const conns = edges.filter(e => e.source === sn.id || e.target === sn.id);
        if (conns.length > 0) {
            const dx = targetPt.x - sn.point.x;
            const dy = targetPt.y - sn.point.y;
            const lenN = Math.hypot(dx, dy);

            let bestEdge: Edge | null = null;
            let minError = Infinity;

            if (lenN > 0) {
                for (const c of conns) {
                    const isSource = c.source === sn.id;
                    let nextPt: Point | undefined;
                    if (isSource) {
                        nextPt = c.points.length > 0 ? c.points[0] : nodes.find(n => n.id === c.target)?.point;
                    } else {
                        nextPt = c.points.length > 0 ? c.points[c.points.length - 1] : nodes.find(n => n.id === c.source)?.point;
                    }
                    
                    if (nextPt) {
                        const odx = nextPt.x - sn.point.x;
                        const ody = nextPt.y - sn.point.y;
                        const lenC = Math.hypot(odx, ody);
                        
                        if (lenC > 0) {
                            const dot = ((odx/lenC) * (dx/lenN) + (ody/lenC) * (dy/lenN));
                            const error = dot + 1; // 0 when perfectly opposite
                            if (error < minError) {
                                minError = error;
                                bestEdge = c;
                            }
                        }
                    }
                }
                
                if (bestEdge) {
                    params = {
                        width: bestEdge.width,
                        sidewalk: bestEdge.sidewalk,
                        sidewalkLeft: bestEdge.sidewalkLeft,
                        sidewalkRight: bestEdge.sidewalkRight,
                        transitionSmoothness: bestEdge.transitionSmoothness,
                        color: bestEdge.color,
                        oneWay: bestEdge.oneWay
                    };
                    Object.keys(params).forEach(key => params[key] === undefined && delete params[key]);
                }
            }
        }
        return params;
    };

    // Right click existing node
    for (const n of nodes) {
        if (Math.hypot(pos.x - n.point.x, pos.y - n.point.y) < 25) {
            if (selectedNode && selectedNode !== n.id) {
                const sn = nodes.find(nn => nn.id === selectedNode)!;
                const newEdgeId = Math.random().toString(36).substring(2, 9);
                const edgeParams = getNewEdgeParams(sn, n.point);
                const newEdge: Edge = {
                    id: newEdgeId,
                    source: selectedNode,
                    target: n.id,
                    points: [
                      { x: sn.point.x + (n.point.x - sn.point.x)/3, y: sn.point.y + (n.point.y - sn.point.y)/3, z: sn.point.z ?? 4, linear: true },
                      { x: sn.point.x + 2*(n.point.x - sn.point.x)/3, y: sn.point.y + 2*(n.point.y - sn.point.y)/3, z: n.point.z ?? 4, linear: true }
                    ],
                    ...edgeParams
                };
                setEdges(prev => [...prev, newEdge]);
                setSelectedNode(n.id);
                setSelectedEdges([newEdgeId]);
                setSelectedPoints([]);
                setIsMergeMode(false);
                startDragPosRef.current = pos;
                setDragging({ type: 'node', id: n.id });
            } else {
                setSelectedNode(n.id);
                setSelectedEdges([]);
                setSelectedPoints([]);
            }
            return;
        }
    }

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
                setSelectedNode(newNodeId);
                setSelectedEdges([]);
                setSelectedPoints([]);
                setIsMergeMode(false);
                startDragPosRef.current = pos;
                setDragging({ type: 'node', id: newNodeId });
                return;
            }
        }

        // Check if clicked ON a road segment to add a Node explicitly at any point
        // To accurately split, we need to find which control point segment was clicked.
        const pts = sampleEdgeSpline(edge, nodes, edges, chamferAngle, meshResolution);
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
            const hitPt = pts[hitIndex];
            const curveIndex = hitPt.curveIndex ?? 0;
            
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

            let t = hitPt.t ?? 0.5;
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
            
            const isLinear = originalPoints.length >= 2 ? !!originalPoints[userCurveIndex * 3]?.linear : true;

            const hp01 = { ...p01, linear: isLinear };
            const hp012 = { ...p012, linear: isLinear };
            const hp123 = { ...p123, linear: isLinear };
            const hp23 = { ...p23, linear: isLinear };

            leftPoints.push(hp01, hp012);
            rightPoints.unshift(hp123, hp23);

            const edge1: Edge = { ...edge, target: newNodeId, points: leftPoints };
            const edge2: Edge = { ...edge, id: Math.random().toString(36).substring(2, 9), source: newNodeId, points: rightPoints };
            
            const newEdges = [edge1, edge2];

            setNodes(prev => [...prev, newNode]);
            setEdges(prev => [...prev.filter(e => e.id !== edge.id), ...newEdges]);
            setSelectedNode(newNodeId);
            setSelectedEdges([]);
            setSelectedPoints([]);
            setIsMergeMode(false);
            startDragPosRef.current = pos;
            setDragging({ type: 'node', id: newNodeId });
            return;
        }
    }

    // Right click Empty Space
    const newNodeId = Math.random().toString(36).substring(2, 9);
    
    let spawnPos = { ...pos };
    if (selectedNode) {
        const sn = nodes.find(n => n.id === selectedNode);
        if (sn) {
            spawnPos.z = sn.point.z;
            if (e.__ray && Math.abs(e.__ray.direction.y) > 0.0001) {
                const zTarget = sn.point.z ?? 4;
                const t = (zTarget - e.__ray.origin.y) / e.__ray.direction.y;
                spawnPos.x = e.__ray.origin.x + e.__ray.direction.x * t;
                spawnPos.y = e.__ray.origin.z + e.__ray.direction.z * t;
            }
        }
    }

    setNodes(prev => [...prev, { id: newNodeId, point: spawnPos }]);

    if (selectedNode) {
        const sn = nodes.find(n => n.id === selectedNode);
        if (sn) {
            const newEdgeId = Math.random().toString(36).substring(2, 9);
            const edgeParams = getNewEdgeParams(sn, spawnPos);
            const newEdge: Edge = {
                id: newEdgeId, source: selectedNode, target: newNodeId, points: [
                  { x: sn.point.x + (spawnPos.x - sn.point.x)/3, y: sn.point.y + (spawnPos.y - sn.point.y)/3, z: sn.point.z ?? 4, linear: true },
                  { x: sn.point.x + 2*(spawnPos.x - sn.point.x)/3, y: sn.point.y + 2*(spawnPos.y - sn.point.y)/3, z: spawnPos.z ?? 4, linear: true }
                ], ...edgeParams
            };
            setEdges(prev => [...prev, newEdge]);
            setSelectedEdges([newEdgeId]);
        }
    } else {
        setSelectedEdges([]);
    }
    
    setSelectedNode(newNodeId);
    setSelectedPoints([]);
    setIsMergeMode(false);
    startDragPosRef.current = spawnPos;
    setDragging({ type: 'node', id: newNodeId });
  };

  const onPointerDown = (e: React.PointerEvent | any) => {
    if (e.button === 2) {
      handleRightClick(e, getMousePos(e));
      return;
    }

    if (is3DMode) {
      if (e.button !== 0) return;
    } else {
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

        if (e.target.setPointerCapture) (e.target as HTMLElement).setPointerCapture(e.pointerId);
    }

    const pos = getMousePos(e);
    
    // Divert behavior to handleRightClick if in Add Node Mode
    if (e.button === 0 && isAddNodeMode) {
      handleRightClick(e, pos);
      return;
    }

    setSelectedPolygonFillId(null);
    for (const pg of polygonFills) {
      let cx = 0, cy = 0, count = 0;
      pg.points.forEach(nid => {
         const n = nodes.find(nn => nn.id === nid);
         if (n) { cx += n.point.x; cy += n.point.y; count++; }
      });
      if (count > 0) {
          cx /= count; cy /= count;
          if (Math.hypot(pos.x - cx, pos.y - cy) < 20) {
              setSelectedPolygonFillId(pg.id);
              setSelectedNodes([]);
              setSelectedEdges([]);
              setSelectedPoints([]);
              return;
          }
      }
    }

    // Click nodes
    for (const n of nodes) {
        if (Math.hypot(pos.x - n.point.x, pos.y - n.point.y) < 25) {
            if (e.shiftKey) {
                if (!selectedNodes.includes(n.id)) {
                    setSelectedNodes(prev => [...prev, n.id]);
                    addedToSelectionRef.current = true;
                } else {
                    addedToSelectionRef.current = false;
                }
                setSelectedEdges([]);
                setSelectedPoints([]);
                startDragPosRef.current = pos;
                setDragging({ type: 'node', id: n.id });
                return;
            }

            if (selectedNodes.includes(n.id) && selectedNodes.length > 1) {
                startDragPosRef.current = pos;
                setDragging({ type: 'node', id: n.id });
                return;
            }

            if (e.ctrlKey) {
                if (n.point.linked) {
                    setNodes(prev => prev.map(node => node.id === n.id ? { ...node, point: { ...node.point, linked: false } } : node));
                    return;
                }

                let newEdges = [...edges];
                const incidentCount = newEdges.filter(edge => edge.source === n.id || edge.target === n.id).length;
                if (incidentCount === 0) return;
                
                // Ensure all incident edges have handles
                newEdges = newEdges.map(edge => {
                    if (edge.source === n.id || edge.target === n.id) {
                        if (edge.points.length === 0) {
                            const sourceNode = nodes.find(nn => nn.id === edge.source);
                            const targetNode = nodes.find(nn => nn.id === edge.target);
                            if (sourceNode && targetNode) {
                                return {
                                    ...edge,
                                    points: [
                                        { x: sourceNode.point.x + (targetNode.point.x - sourceNode.point.x) / 3, y: sourceNode.point.y + (targetNode.point.y - sourceNode.point.y) / 3, z: sourceNode.point.z ?? 4, linear: true, linked: false },
                                        { x: sourceNode.point.x + 2 * (targetNode.point.x - sourceNode.point.x) / 3, y: sourceNode.point.y + 2 * (targetNode.point.y - sourceNode.point.y) / 3, z: targetNode.point.z ?? 4, linear: true, linked: false }
                                    ]
                                };
                            }
                        }
                    }
                    return edge;
                });
                
                // Gather current handles attached to this node
                const connections = newEdges.filter(edge => edge.source === n.id || edge.target === n.id).map(edge => {
                    const isSource = edge.source === n.id;
                    const handle = isSource ? edge.points[0] : edge.points[edge.points.length - 1];
                    const dx = handle.x - n.point.x;
                    const dy = handle.y - n.point.y;
                    return {
                        edgeId: edge.id,
                        isSource,
                        dist: Math.hypot(dx, dy) || 1, // avoid division by zero
                        angle: Math.atan2(dy, dx)
                    };
                });
                
                const N = connections.length;
                if (N > 0) {
                    let targetAngles: number[] = [];
                    connections.sort((a, b) => a.angle - b.angle);
                    
                    if (N === 1) {
                         targetAngles = [connections[0].angle];
                    } else if (N === 2) {
                         let base1 = connections[0].angle;
                         let base2 = connections[1].angle;
                         
                         let angDiff = (base2 + Math.PI) - base1;
                         while (angDiff > Math.PI) angDiff -= 2 * Math.PI;
                         while (angDiff < -Math.PI) angDiff += 2 * Math.PI;
                         
                         let avgAngle = base1 + angDiff / 2;
                         targetAngles = [avgAngle, avgAngle + Math.PI];
                    } else if (N === 3) {
                         const diff1 = (connections[1].angle - connections[0].angle + 2 * Math.PI) % (2 * Math.PI);
                         const diff2 = (connections[2].angle - connections[0].angle + 2 * Math.PI) % (2 * Math.PI);
                         
                         const costY = Math.abs(diff1 - 2*Math.PI/3) + Math.abs(diff2 - 4*Math.PI/3);
                         const costT1 = Math.abs(diff1 - Math.PI/2) + Math.abs(diff2 - Math.PI);
                         const costT2 = Math.abs(diff1 - Math.PI/2) + Math.abs(diff2 - 3*Math.PI/2);
                         const costT3 = Math.abs(diff1 - Math.PI) + Math.abs(diff2 - 3*Math.PI/2);
                         
                         const minCost = Math.min(costY, costT1, costT2, costT3);
                         let base = connections[0].angle;
                         if (minCost === costY) {
                             targetAngles = [base, base + 2*Math.PI/3, base + 4*Math.PI/3];
                         } else if (minCost === costT1) {
                             targetAngles = [base, base + Math.PI/2, base + Math.PI];
                         } else if (minCost === costT2) {
                             targetAngles = [base, base + Math.PI/2, base + 3*Math.PI/2];
                         } else {
                             targetAngles = [base, base + Math.PI, base + 3*Math.PI/2];
                         }
                    } else if (N === 4) {
                         let base = connections[0].angle;
                         targetAngles = [base, base + Math.PI/2, base + Math.PI, base + 3*Math.PI/2];
                    } else {
                         let base = connections[0].angle;
                         const step = 2 * Math.PI / N;
                         for (let i = 0; i < N; i++) {
                             targetAngles.push(base + i * step);
                         }
                    }
                    
                    newEdges = newEdges.map(edge => {
                        const connIdx = connections.findIndex(c => c.edgeId === edge.id);
                        if (connIdx !== -1) {
                            const conn = connections[connIdx];
                            const angle = targetAngles[connIdx];
                            const newX = n.point.x + Math.cos(angle) * conn.dist;
                            const newY = n.point.y + Math.sin(angle) * conn.dist;
                            
                            const newPts = [...edge.points];
                            if (conn.isSource) {
                                newPts[0] = { ...newPts[0], x: newX, y: newY, linear: false };
                            } else {
                                newPts[newPts.length - 1] = { ...newPts[newPts.length - 1], x: newX, y: newY, linear: false };
                            }
                            return { ...edge, points: newPts };
                        }
                        return edge;
                    });
                    
                    const newNodes = nodes.map(node => node.id === n.id ? { ...node, point: { ...node.point, linked: true } } : node);
                    setNodes(newNodes);
                    setEdges(newEdges.map(e => enforceLinear(e, newNodes)));
                }
                
                setSelectedNode(n.id);
                setSelectedEdges([]);
                setSelectedPoints([]);
                setIsMergeMode(false);
                return;
            }

            if (e.altKey) {
                setEdges(prev => prev.map(edge => {
                    const newPts = [...edge.points];
                    let changed = false;
                    if (edge.source === n.id && newPts.length > 0) {
                        const targetHandle = newPts[1];
                        if (targetHandle) {
                            newPts[0] = { ...newPts[0], x: n.point.x + (targetHandle.x - n.point.x) / 2, y: n.point.y + (targetHandle.y - n.point.y) / 2, z: !newPts[0].linear ? n.point.z ?? 4 : newPts[0].z, linear: !newPts[0].linear };
                            changed = true;
                        }
                    }
                    if (edge.target === n.id && newPts.length > 1) {
                        const prevHandle = newPts[newPts.length - 2];
                        if (prevHandle) {
                            newPts[newPts.length - 1] = { ...newPts[newPts.length - 1], x: n.point.x + (prevHandle.x - n.point.x) / 2, y: n.point.y + (prevHandle.y - n.point.y) / 2, z: !newPts[newPts.length - 1].linear ? n.point.z ?? 4 : newPts[newPts.length - 1].z, linear: !newPts[newPts.length - 1].linear };
                            changed = true;
                        }
                    }
                    return changed ? enforceLinear({ ...edge, points: newPts }, nodes) : edge;
                }));
                setSelectedNode(n.id);
                setSelectedEdges([]);
                setSelectedPoints([]);
                setIsMergeMode(false);
                setDragging({ type: 'node', id: n.id });
                return;
            }

            if (selectedNode && selectedNode !== n.id && (isMergeMode)) {
                if (isMergeMode) {
                    const sn = nodes.find(nn => nn.id === selectedNode)!;
                    const mid = { x: (sn.point.x + n.point.x) / 2, y: (sn.point.y + n.point.y) / 2 };
                    const deltaSn = { x: mid.x - sn.point.x, y: mid.y - sn.point.y };
                    const deltaN = { x: mid.x - n.point.x, y: mid.y - n.point.y };

                    setNodes(prev => prev.map(node => node.id === n.id ? { ...node, point: mid } : node).filter(node => node.id !== selectedNode));

                    setEdges(prev => prev.map(edge => {
                        const newEdge = { ...edge };
                        const newPts = [...edge.points];
                        let changed = false;

                        if (edge.source === selectedNode) {
                            newEdge.source = n.id;
                            if (newPts.length > 0) {
                                newPts[0] = { ...newPts[0], x: newPts[0].x + deltaSn.x, y: newPts[0].y + deltaSn.y };
                                changed = true;
                            }
                        } else if (edge.source === n.id) {
                            if (newPts.length > 0) {
                                newPts[0] = { ...newPts[0], x: newPts[0].x + deltaN.x, y: newPts[0].y + deltaN.y };
                                changed = true;
                            }
                        }
                        
                        if (edge.target === selectedNode) {
                            newEdge.target = n.id;
                            if (newPts.length > 0) {
                                newPts[newPts.length - 1] = { ...newPts[newPts.length - 1], x: newPts[newPts.length - 1].x + deltaSn.x, y: newPts[newPts.length - 1].y + deltaSn.y };
                                changed = true;
                            }
                        } else if (edge.target === n.id) {
                            if (newPts.length > 0) {
                                newPts[newPts.length - 1] = { ...newPts[newPts.length - 1], x: newPts[newPts.length - 1].x + deltaN.x, y: newPts[newPts.length - 1].y + deltaN.y };
                                changed = true;
                            }
                        }

                        if (changed) {
                            newEdge.points = newPts;
                        }
                        return newEdge;
                    }).filter(edge => edge.source !== edge.target));

                    setSelectedNode(n.id);
                    setSelectedEdges([]);
                    setIsMergeMode(false);
                }
            } else {
                setDragging({ type: 'node', id: n.id });
                setSelectedNode(n.id);
                setSelectedEdges([]);
                setSelectedPoints([]);
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
                const prevHandle = newPts[j - 2];
                const nextHandle = j + 2 < newPts.length ? newPts[j + 2] : null;
                if (prevHandle) {
                  newPts[j - 1] = { 
                      ...newPts[j - 1], 
                      x: newPts[j].x + (prevHandle.x - newPts[j].x) / 2, 
                      y: newPts[j].y + (prevHandle.y - newPts[j].y) / 2, 
                      z: !newPts[j - 1].linear ? newPts[j].z ?? 4 : newPts[j - 1].z,
                      linear: !newPts[j - 1].linear 
                  };
                }
                newPts[j] = { ...newPts[j], linked: false };
                if ((targetNode || j + 3 < newPts.length) && nextHandle) {
                    newPts[j + 1] = { 
                        ...newPts[j + 1], 
                        x: newPts[j].x + (nextHandle.x - newPts[j].x) / 2, 
                        y: newPts[j].y + (nextHandle.y - newPts[j].y) / 2, 
                        z: !newPts[j + 1].linear ? newPts[j].z ?? 4 : newPts[j + 1].z,
                        linear: !newPts[j + 1].linear 
                    };
                }
              } else if (j % 3 === 0) {
                if (newPts[j].linear) {
                    newPts[j] = { ...newPts[j], linear: false };
                } else {
                    const anchorA = j === 0 ? sourceNode.point : newPts[j - 1];
                    const otherHandle = j + 1 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 1];
                    newPts[j] = { x: anchorA.x + (otherHandle.x - anchorA.x) / 2, y: anchorA.y + (otherHandle.y - anchorA.y) / 2, z: anchorA.z ?? 4, linear: true };
                }
                if (j > 0 && newPts[j - 1]) newPts[j - 1] = { ...newPts[j - 1], linked: false };
              } else if (j % 3 === 1) {
                if (newPts[j].linear) {
                    newPts[j] = { ...newPts[j], linear: false };
                } else {
                    const anchorA = j + 1 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 1];
                    const otherHandle = j - 1 < 0 ? (sourceNode ? sourceNode.point : newPts[j]) : newPts[j - 1];
                    newPts[j] = { x: anchorA.x + (otherHandle.x - anchorA.x) / 2, y: anchorA.y + (otherHandle.y - anchorA.y) / 2, z: anchorA.z ?? 4, linear: true };
                }
                if (j + 1 < newPts.length && newPts[j + 1]) newPts[j + 1] = { ...newPts[j + 1], linked: false };
              }
              return enforceLinear({ ...edge, points: newPts }, nodes, undefined, undefined, undefined);
            }));
            
            setDragging({ type: 'edge', id: edges[i].id, pointId: j });
            setSelectedEdges([edges[i].id]);
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
                    const a1 = Math.atan2(h1.y - anchor.y, h1.x - anchor.x);
                    const a2 = Math.atan2(h2.y - anchor.y, h2.x - anchor.x);
                    let angDiff = (a2 + Math.PI) - a1;
                    while (angDiff > Math.PI) angDiff -= 2 * Math.PI;
                    while (angDiff < -Math.PI) angDiff += 2 * Math.PI;
                    let avgAngle = a1 + angDiff / 2;
                    
                    const d1 = Math.hypot(h1.x - anchor.x, h1.y - anchor.y);
                    const d2 = Math.hypot(h2.x - anchor.x, h2.y - anchor.y);
                    newPts[j - 1] = { ...h1, x: anchor.x + Math.cos(avgAngle) * d1, y: anchor.y + Math.sin(avgAngle) * d1, linear: false };
                    newPts[j + 1] = { ...h2, x: anchor.x + Math.cos(avgAngle + Math.PI) * d2, y: anchor.y + Math.sin(avgAngle + Math.PI) * d2, linear: false };
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
                        const a1 = Math.atan2(h1.y - anchor.y, h1.x - anchor.x);
                        const a2 = Math.atan2(h2.y - anchor.y, h2.x - anchor.x);
                        let angDiff = (a2 + Math.PI) - a1;
                        while (angDiff > Math.PI) angDiff -= 2 * Math.PI;
                        while (angDiff < -Math.PI) angDiff += 2 * Math.PI;
                        let avgAngle = a1 + angDiff / 2;
                        
                        const d1 = Math.hypot(h1.x - anchor.x, h1.y - anchor.y);
                        const d2 = Math.hypot(h2.x - anchor.x, h2.y - anchor.y);
                        newPts[j] = { ...h1, x: anchor.x + Math.cos(avgAngle) * d1, y: anchor.y + Math.sin(avgAngle) * d1, linear: false };
                        newPts[oppositeIdx] = { ...h2, x: anchor.x + Math.cos(avgAngle + Math.PI) * d2, y: anchor.y + Math.sin(avgAngle + Math.PI) * d2, linear: false };
                        newPts[anchorIdx] = { ...anchor, linked: true };
                    }
                }
              }
              return enforceLinear({ ...edge, points: newPts }, nodes, undefined, undefined, undefined);
            }));
            // Note: we DO NOT return here, so that dragging can immediately begin.
            // Oh wait, Ctrl-click toggles link state, we shouldn't drag link toggle necessarily...
            // the previous code might start dragging. Let it be for now.
          }

          setDragging({ type: 'edge', id: edges[i].id, pointId: j });
          if (e.shiftKey) {
             const alreadySelected = selectedPoints.some(p => p.edgeId === edges[i].id && p.pointIndex === j);
             if (!alreadySelected) {
                 setSelectedPoints(prev => [...prev, { edgeId: edges[i].id, pointIndex: j }]);
             }
             if (!selectedEdges.includes(edges[i].id)) {
                 setSelectedEdges(prev => [...prev, edges[i].id]);
             }
          } else {
             setSelectedEdges([edges[i].id]);
             setSelectedPoints([{ edgeId: edges[i].id, pointIndex: j }]);
          }
          setSelectedNode(null);
          return;
        }
      }
    }



    // Add point to edge middle
    for (let i = edges.length - 1; i >= 0; i--) {
      const edge = edges[i];
      const pts = sampleEdgeSpline(edge, nodes, edges, chamferAngle, meshResolution);
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
        if (e.shiftKey) {
            if (!selectedEdges.includes(edge.id)) {
                setSelectedEdges(prev => [...prev, edge.id]);
                addedToSelectionRef.current = true;
            } else {
                addedToSelectionRef.current = false;
            }
            setSelectedNode(null);
            startDragPosRef.current = pos;
            setDragging({ type: 'edge', id: edge.id, pointId: hitIndex });
            return;
        }

        if (selectedEdges.includes(edge.id) && selectedEdges.length > 1) {
            startDragPosRef.current = pos;
            setDragging({ type: 'edge', id: edge.id, pointId: hitIndex });
            return;
        }

        // Only clear and multi-select edge, don't split unless multi-selection isn't active
        setSelectedEdges([edge.id]);

        const hitPt = pts[hitIndex];
        const curveIndex = hitPt.curveIndex ?? 0;
        
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
          let t = hitPt.t ?? 0.5;
          if (t < 0.1) t = 0.1;
          if (t > 0.9) t = 0.9;
          
          const { p01, p12, p23, p012, p123, pMid } = splitBezier(p0, p1, p2, p3, t);

          const newPoints = [...e.points];
          const isLinear = newPoints.length >= 2 ? !!newPoints[userCurveIndex * 3]?.linear : true;

          const hp01 = { ...p01, linear: isLinear };
          const hp012 = { ...p012, linear: isLinear };
          const hp123 = { ...p123, linear: isLinear };
          const hp23 = { ...p23, linear: isLinear };
          
          if (newPoints.length < 2) {
              // Note: our logic requires at least 2 points for the user curve
              return { ...e, points: [hp01, hp012, pMid, hp123, hp23] };
          } else {
              const spliceIdx = userCurveIndex * 3; 
              newPoints.splice(spliceIdx, 2, hp01, hp012, pMid, hp123, hp23);
              return { ...e, points: newPoints };
          }
        }));
        setSelectedNode(null);
        
        // start dragging the newly created `pMid`
        const dragPointId = userCurveIndex * 3 + 2; 
        setSelectedPoints([{ edgeId: edge.id, pointIndex: dragPointId }]);
        setDragging({ type: 'edge', id: edge.id, pointId: dragPointId });
        
        return;
      }
    }

    // Click Empty Space
    // Default deselect
    if (!e.shiftKey) {
      setSelectedNode(null);
      setSelectedNodes([]);
      setSelectedEdges([]);
      setSelectedPoints([]);
    }
    setIsAddNodeMode(false);
    setIsMergeMode(false);
    
    if ((!is3DMode || e.shiftKey) && e.button === 0) {
      setMarqueeStart(pos);
      setMarqueeEnd(pos);
      setDragging({ type: 'marquee', id: '' });
    }
  };

  const enforceLinear = (edge: Edge, currentNodes: Node[], oldEdge?: Edge, oldNodes?: Node[], draggingPointId?: number) => {
      const newPts = [...edge.points];
      let changed = false;
      const sourceNode = currentNodes.find(n => n.id === edge.source);
      const targetNode = edge.target ? currentNodes.find(n => n.id === edge.target) : null;
      
      const oldSourceNode = oldNodes ? oldNodes.find(n => n.id === edge.source) : sourceNode;
      const oldTargetNode = oldNodes && edge.target ? oldNodes.find(n => n.id === edge.target) : targetNode;
      const oldPts = oldEdge ? oldEdge.points : newPts;

      // 1. Process the dragging point first (if any)
      const processPoint = (j: number) => {
          const handle = newPts[j];
          if (!handle.linear) return;
          
          if (j % 3 === 0) {
              const anchorA = j === 0 ? sourceNode?.point : newPts[j - 1];
              const nextAnchorIndex = j + 2;
              const trueTargetAnchor = nextAnchorIndex >= newPts.length ? targetNode?.point : newPts[nextAnchorIndex];
              const otherHandle = j + 1 >= newPts.length ? undefined : newPts[j + 1];
              
              let targetForLine;
              if (otherHandle && otherHandle.linear && trueTargetAnchor) {
                  targetForLine = trueTargetAnchor;
              } else {
                  targetForLine = j + 1 >= newPts.length ? targetNode?.point : newPts[j + 1];
              }
              
              if (!anchorA || !targetForLine) return;
              
              const dx = targetForLine.x - anchorA.x;
              const dy = targetForLine.y - anchorA.y;
              const lenSq = dx * dx + dy * dy;
              
              if (lenSq > 0.0001) {
                  const hx = handle.x - anchorA.x;
                  const hy = handle.y - anchorA.y;
                  let t = (hx * dx + hy * dy) / lenSq;
                  t = Math.max(0, t);
                  newPts[j] = { ...handle, x: anchorA.x + dx * t, y: anchorA.y + dy * t, z: handle.z ?? anchorA.z ?? 4 };
                  changed = true;
              }
          } else if (j % 3 === 1) {
              const anchorA = j + 1 >= newPts.length ? targetNode?.point : newPts[j + 1];
              const prevAnchorIndex = j - 2;
              const trueSourceAnchor = prevAnchorIndex < 0 ? sourceNode?.point : newPts[prevAnchorIndex];
              const otherHandle = j - 1 < 0 ? undefined : newPts[j - 1];
              
              let targetForLine;
              if (otherHandle && otherHandle.linear && trueSourceAnchor) {
                  targetForLine = trueSourceAnchor;
              } else {
                  targetForLine = j - 1 < 0 ? sourceNode?.point : newPts[j - 1];
              }
              
              if (!anchorA || !targetForLine) return;
              
              const dx = targetForLine.x - anchorA.x;
              const dy = targetForLine.y - anchorA.y;
              const lenSq = dx * dx + dy * dy;
              
              if (lenSq > 0.0001) {
                  const hx = handle.x - anchorA.x;
                  const hy = handle.y - anchorA.y;
                  let t = (hx * dx + hy * dy) / lenSq;
                  t = Math.max(0, t);
                  newPts[j] = { ...handle, x: anchorA.x + dx * t, y: anchorA.y + dy * t, z: handle.z ?? anchorA.z ?? 4 };
                  changed = true;
              }
          }
      };

      if (draggingPointId !== undefined && draggingPointId >= 0 && draggingPointId < newPts.length) {
          processPoint(draggingPointId);
      }

      for (let j = 0; j < newPts.length; j++) {
          if (j !== draggingPointId) {
              processPoint(j);
          }
      }

      return changed ? { ...edge, points: newPts } : edge;
  };

  const handleDrag = (dragState: { type: 'node' | 'edge' | 'pan' | 'marquee'; id: string; pointId?: number }, pos: Point, shiftKey: boolean) => {
    const taper = (dist: number, radius: number) => Math.max(0, 1 - Math.pow(dist / radius, 2));

    if (dragState.type === 'node') {
        const draggingNode = nodes.find(n => n.id === dragState.id);
        if (draggingNode) {
            let dx = pos.x - draggingNode.point.x;
            let dy = pos.y - draggingNode.point.y;
            if (is3DMode && shiftKey) { dx = 0; dy = 0; }
            const dz = pos.z !== undefined ? pos.z - (draggingNode.point.z ?? 4) : 0;

            const originPoint = draggingNode.point;
            
            const newNodes = nodes.map(n => {
                const isSelected = selectedNodes.includes(n.id);
                if (n.id === draggingNode.id) {
                    return { ...n, point: { ...n.point, x: n.point.x + dx, y: n.point.y + dy, z: pos.z ?? originPoint.z } };
                } else if (isSelected) {
                    return { ...n, point: { ...n.point, x: n.point.x + dx, y: n.point.y + dy, z: (n.point.z ?? 4) + dz } };
                }
                if (!softSelectionEnabled) return n;
                const d = Math.hypot(n.point.x - originPoint.x, n.point.y - originPoint.y);
                const w = taper(d, softSelectionRadius);
                if (w <= 0) return n;
                return {
                    ...n,
                    point: {
                        x: n.point.x + dx * w,
                        y: n.point.y + dy * w,
                        z: (n.point.z ?? 4) + dz * w
                    }
                };
            });
            
            setNodes(newNodes);
            const movedNodes = new Set([...selectedNodes, draggingNode.id]);
            setEdges(edges.map(edge => {
                let newPoints = [...edge.points];
                let changed = false;

                if (movedNodes.has(edge.source) || movedNodes.has(edge.target)) {
                    if (movedNodes.has(edge.source) && newPoints.length > 0) {
                        newPoints[0] = { ...newPoints[0], x: newPoints[0].x + dx, y: newPoints[0].y + dy, z: (newPoints[0].z ?? 4) + dz };
                        changed = true;
                    }
                    if (movedNodes.has(edge.target) && newPoints.length > 0) {
                        newPoints[newPoints.length - 1] = { 
                            ...newPoints[newPoints.length - 1],
                            x: newPoints[newPoints.length - 1].x + dx, 
                            y: newPoints[newPoints.length - 1].y + dy,
                            z: (newPoints[newPoints.length - 1].z ?? 4) + dz
                        };
                        changed = true;
                    }
                }

                if (softSelectionEnabled) {
                    newPoints = newPoints.map((pt, idx) => {
                        if (movedNodes.has(edge.source) && idx === 0) return pt;
                        if (movedNodes.has(edge.target) && idx === newPoints.length - 1) return pt;
                        
                        const d = Math.hypot(pt.x - originPoint.x, pt.y - originPoint.y);
                        const w = taper(d, softSelectionRadius);
                        if (w <= 0) return pt;
                        changed = true;
                        return {
                            ...pt,
                            x: pt.x + dx * w,
                            y: pt.y + dy * w,
                            z: (pt.z ?? 4) + dz * w
                        };
                    });
                }

                return changed ? enforceLinear({ ...edge, points: newPoints }, newNodes, edge, nodes) : edge;
            }));
        }
    } else if (dragState.type === 'edge' && dragState.pointId !== undefined) {
      setEdges((prev) => {
        const pid = dragState.pointId as number;
        const draggingEdge = prev.find(e => e.id === dragState.id);
        if (!draggingEdge) return prev;
        
        const originPoint = draggingEdge.points[pid];
        let ddx = pos.x - originPoint.x;
        let ddy = pos.y - originPoint.y;
        if (is3DMode && shiftKey) { ddx = 0; ddy = 0; }
        const ddz = pos.z !== undefined ? pos.z - (originPoint.z ?? 4) : 0;

        let linkedNode: Node | null = null;
        let angleDelta = 0;
        let scaleRatio = 1;

        if (pid === 0 || pid === draggingEdge.points.length - 1) {
            const nodeId = pid === 0 ? draggingEdge.source : draggingEdge.target;
            if (nodeId && !originPoint.linear) {
               const node = nodes.find(n => n.id === nodeId);
               if (node && node.point.linked) {
                   linkedNode = node;
                   
                   const oldDx = originPoint.x - node.point.x;
                   const oldDy = originPoint.y - node.point.y;
                   const oldAngle = Math.atan2(oldDy, oldDx);
                   
                   const newPos = { x: originPoint.x + ddx, y: originPoint.y + ddy };
                   const newDx = newPos.x - node.point.x;
                   const newDy = newPos.y - node.point.y;
                   const newAngle = Math.atan2(newDy, newDx);
                   
                   angleDelta = newAngle - oldAngle;
               }
            }
        }

        let newNodes = nodes;
        if (softSelectionEnabled) {
            newNodes = nodes.map(n => {
                const d = Math.hypot(n.point.x - originPoint.x, n.point.y - originPoint.y);
                const w = taper(d, softSelectionRadius);
                if (w <= 0) return n;
                return {
                    ...n,
                    point: {
                        x: n.point.x + ddx * w,
                        y: n.point.y + ddy * w,
                        z: (n.point.z ?? 4) + ddz * w
                    }
                };
            });
            // Calling setNodes here relies on it batching nicely
            setNodes(newNodes);
        }

        return prev.map((e) => {
          let isLinkedEdge = false;
          if (linkedNode && e.id !== draggingEdge.id && (e.source === linkedNode.id || e.target === linkedNode.id)) {
              isLinkedEdge = true;
          }

          const isDraggingPointSelected = selectedPoints.some(p => p.edgeId === draggingEdge.id && p.pointIndex === pid);
          const hasSelectedPoints = selectedPoints.some(p => p.edgeId === e.id);
          if (e.id !== draggingEdge.id && !softSelectionEnabled && !isLinkedEdge && (!isDraggingPointSelected || !hasSelectedPoints)) return e;
          
          let newPoints = [...e.points];
          let changed = false;

          const edgeSelectedPoints = selectedPoints.filter(p => p.edgeId === e.id);
          
          if (isDraggingPointSelected && edgeSelectedPoints.length > 0) {
              const pointsToMove = new Set<number>();
              
              edgeSelectedPoints.forEach(sp => {
                  const mPid = sp.pointIndex;
                  pointsToMove.add(mPid);
                  
                  // if anchor, we might want to also move handles if they aren't explicitly selected
                  if (mPid % 3 === 2) {
                      if (mPid - 1 >= 0) pointsToMove.add(mPid - 1);
                      if (mPid + 1 < newPoints.length) pointsToMove.add(mPid + 1);
                  }
              });

              pointsToMove.forEach(mPid => {
                  const oldTarget = e.points[mPid];
                  if (mPid % 3 === 2 || (mPid % 3 !== 2 && pointsToMove.has(mPid%3 === 1 ? mPid+1 : mPid-1))) {
                      // simple linear shift
                      newPoints[mPid] = { ...oldTarget, x: oldTarget.x + ddx, y: oldTarget.y + ddy, z: oldTarget.z !== undefined ? oldTarget.z + ddz : 4 + ddz };
                  } else {
                      // This is a handle being moved independently of its anchor
                      const handle = oldTarget;
                      let effectivePos = { x: handle.x + ddx, y: handle.y + ddy, z: pos.z ?? oldTarget.z ?? 4 };
                      newPoints[mPid] = { ...handle, ...effectivePos };
                      
                      const isIncoming = mPid % 3 === 1;
                      const anchorIdx = isIncoming ? mPid + 1 : mPid - 1;
                      const oppositeIdx = isIncoming ? mPid + 2 : mPid - 2;
                      
                      if (!pointsToMove.has(oppositeIdx) && anchorIdx >= 0 && oppositeIdx >= 0 && oppositeIdx < newPoints.length && !handle.linear) {
                          const anchor = e.points[anchorIdx];
                          if (anchor.linked) {
                              const dxAngle = effectivePos.x - anchor.x;
                              const dyAngle = effectivePos.y - anchor.y;
                              const oppPos = e.points[oppositeIdx];
                              const curDist = Math.hypot(dxAngle, dyAngle);
                              const oppOldDx = oppPos.x - anchor.x;
                              const oppOldDy = oppPos.y - anchor.y;
                              const oppDist = Math.hypot(oppOldDx, oppOldDy);
                              if (curDist > 0.001) {
                                  newPoints[oppositeIdx] = {
                                      ...oppPos,
                                      x: anchor.x + (-dxAngle / curDist) * oppDist,
                                      y: anchor.y + (-dyAngle / curDist) * oppDist,
                                      linear: false
                                  };
                              }
                          }
                      }
                  }
              });
              changed = true;
          } else if (e.id === draggingEdge.id) {
              const oldTarget = originPoint;

              if (pid % 3 === 2) {
                 newPoints[pid] = { ...oldTarget, x: oldTarget.x + ddx, y: oldTarget.y + ddy, z: oldTarget.z !== undefined ? oldTarget.z + ddz : 4 + ddz };
                 if (pid - 1 >= 0) {
                     newPoints[pid - 1] = { ...newPoints[pid - 1], x: newPoints[pid - 1].x + ddx, y: newPoints[pid - 1].y + ddy, z: (newPoints[pid - 1].z ?? 4) + ddz };
                 }
                 if (pid + 1 < newPoints.length) {
                     newPoints[pid + 1] = { ...newPoints[pid + 1], x: newPoints[pid + 1].x + ddx, y: newPoints[pid + 1].y + ddy, z: (newPoints[pid + 1].z ?? 4) + ddz };
                 }
              } else if (pid % 3 === 0 || pid % 3 === 1) {
                  const handle = originPoint;
                  let effectivePos = { x: handle.x + ddx, y: handle.y + ddy, z: pos.z ?? oldTarget.z ?? 4 };

                  newPoints[pid] = { ...handle, ...effectivePos };
               
                  // Check if anchor is linked
                  const isIncoming = pid % 3 === 1;
                  const anchorIdx = isIncoming ? pid + 1 : pid - 1;
                  const oppositeIdx = isIncoming ? pid + 2 : pid - 2;
               
                  if (anchorIdx >= 0 && anchorIdx < newPoints.length && oppositeIdx >= 0 && oppositeIdx < newPoints.length && !handle.linear) {
                      const anchor = newPoints[anchorIdx];
                      if (anchor.linked) {
                          const dxAngle = effectivePos.x - anchor.x;
                          const dyAngle = effectivePos.y - anchor.y;
                          const oppPos = newPoints[oppositeIdx];
                          
                          const curDist = Math.hypot(dxAngle, dyAngle);
                          const oppOldDx = oppPos.x - anchor.x;
                          const oppOldDy = oppPos.y - anchor.y;
                          const oppDist = Math.hypot(oppOldDx, oppOldDy);
                          
                          if (curDist > 0.001) {
                              const oppDirX = -dxAngle / curDist;
                              const oppDirY = -dyAngle / curDist;
                              
                              newPoints[oppositeIdx] = {
                                  ...oppPos,
                                  x: anchor.x + oppDirX * oppDist,
                                  y: anchor.y + oppDirY * oppDist,
                                  linear: false
                              };
                          }
                      }
                  }
              }
              changed = true;

              if (softSelectionEnabled) {
                  newPoints = newPoints.map((pt, idx) => {
                      if (idx === pid) return pt;
                      if (pid % 3 === 2 && (idx === pid - 1 || idx === pid + 1)) return pt;
                      const d = Math.hypot(pt.x - originPoint.x, pt.y - originPoint.y);
                      const w = taper(d, softSelectionRadius);
                      if (w <= 0) return pt;
                      return {
                          ...pt,
                          x: pt.x + ddx * w,
                          y: pt.y + ddy * w,
                          z: (pt.z ?? 4) + ddz * w
                      };
                  });
              }
          } else if (isLinkedEdge && linkedNode && angleDelta !== 0) {
              if (e.source === linkedNode.id && newPoints.length > 0 && !newPoints[0].linear) {
                  const h = newPoints[0];
                  const odx = h.x - linkedNode.point.x;
                  const ody = h.y - linkedNode.point.y;
                  const oAng = Math.atan2(ody, odx);
                  const oDist = Math.hypot(odx, ody);
                  const nAng = oAng + angleDelta;
                  const nDist = oDist * scaleRatio;
                  newPoints[0] = { ...h, x: linkedNode.point.x + Math.cos(nAng) * nDist, y: linkedNode.point.y + Math.sin(nAng) * nDist, linear: false };
                  changed = true;
              }
              if (e.target === linkedNode.id && newPoints.length > 0 && !newPoints[newPoints.length - 1].linear) {
                  const idx = newPoints.length - 1;
                  const h = newPoints[idx];
                  const odx = h.x - linkedNode.point.x;
                  const ody = h.y - linkedNode.point.y;
                  const oAng = Math.atan2(ody, odx);
                  const oDist = Math.hypot(odx, ody);
                  const nAng = oAng + angleDelta;
                  const nDist = oDist * scaleRatio;
                  newPoints[idx] = { ...h, x: linkedNode.point.x + Math.cos(nAng) * nDist, y: linkedNode.point.y + Math.sin(nAng) * nDist, linear: false };
                  changed = true;
              }
          } else if (softSelectionEnabled) {
              newPoints = newPoints.map((pt, idx) => {
                  const d = Math.hypot(pt.x - originPoint.x, pt.y - originPoint.y);
                  const w = taper(d, softSelectionRadius);
                  if (w <= 0) return pt;
                  changed = true;
                  return {
                      ...pt,
                      x: pt.x + ddx * w,
                      y: pt.y + ddy * w,
                      z: (pt.z ?? 4) + ddz * w
                  };
              });
          }

          return changed ? enforceLinear({ ...e, points: newPoints }, newNodes, e, nodes, pid) : e;
        });
      });
    }
  };

  const onPointerMove = (e: React.PointerEvent | any) => {
    if (is3DMode) {
      if (!dragging || dragging.type === 'pan') return;
      if (dragging.type === 'marquee' && marqueeStart) {
        setMarqueeEnd(getMousePos(e));
        return;
      }
    } else {
      const rect = canvasRef.current!.getBoundingClientRect();
      const rawPos = { x: e.clientX - rect.left, y: e.clientY - rect.top };
      pointersRef.current.set(e.pointerId, rawPos);

      if (dragging?.type === 'marquee' && marqueeStart && pointersRef.current.size === 1) {
        setMarqueeEnd(getMousePos(e));
        return;
      }

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
    }

    const pos = getMousePos(e);

    handleDrag(dragging, pos, e.shiftKey);
  };

  const onPointerUp = (e: React.PointerEvent | any) => {
    if (dragging && e.shiftKey && startDragPosRef.current) {
        const pos = getMousePos(e);
        const dx = pos.x - startDragPosRef.current.x;
        const dy = pos.y - startDragPosRef.current.y;
        const dz = (pos.z ?? 0) - (startDragPosRef.current.z ?? 0);
        const dist = Math.hypot(Math.hypot(dx, dy), dz);
        
        if (dist < 5 && !addedToSelectionRef.current) {
            if (dragging.type === 'node') {
                setSelectedNodes(prev => prev.filter(id => id !== dragging.id));
            } else if (dragging.type === 'edge') {
                setSelectedEdges(prev => prev.filter(id => id !== dragging.id));
            }
        }
    }

    if (marqueeStart && marqueeEnd) {
      if (Math.hypot(marqueeEnd.x - marqueeStart.x, marqueeEnd.y - marqueeStart.y) > 5) {
        const xMin = Math.min(marqueeStart.x, marqueeEnd.x);
        const xMax = Math.max(marqueeStart.x, marqueeEnd.x);
        const yMin = Math.min(marqueeStart.y, marqueeEnd.y);
        const yMax = Math.max(marqueeStart.y, marqueeEnd.y);
        
        const selNodes: string[] = e.shiftKey ? [...selectedNodes] : [];
        const selEdges: string[] = e.shiftKey ? [...selectedEdges] : [];
        const selPoints: PointSelection[] = e.shiftKey ? [...selectedPoints] : [];
        
        nodes.forEach(n => {
           if (n.point.x >= xMin && n.point.x <= xMax && n.point.y >= yMin && n.point.y <= yMax) {
               if (!selNodes.includes(n.id)) selNodes.push(n.id);
           }
        });
        
        edges.forEach(edge => {
           let hasPointInside = false;
           for (let i = 0; i < edge.points.length; i++) {
               const p = edge.points[i];
               if (p.x >= xMin && p.x <= xMax && p.y >= yMin && p.y <= yMax) {
                   hasPointInside = true;
                   if (!selPoints.find(sp => sp.edgeId === edge.id && sp.pointIndex === i)) {
                       selPoints.push({ edgeId: edge.id, pointIndex: i });
                   }
               }
           }
           if (hasPointInside && !selEdges.includes(edge.id)) {
               selEdges.push(edge.id);
           }
        });
        
        setSelectedNodes(selNodes);
        setSelectedEdges(selEdges);
        setSelectedPoints(selPoints);
      }
      setMarqueeStart(null);
      setMarqueeEnd(null);
    }

    if (!is3DMode) {
      pointersRef.current.delete(e.pointerId);
      if (pointersRef.current.size < 2 && dragging?.type !== 'pan') {
        lastPanMidpointRef.current = null;
      }

      if (dragging?.type === 'pan') {
        setDragging(null);
        lastPanMidpointRef.current = null;
        return;
      }
    }

    if (dragging?.type === 'edge') {
        // If dropped near a node, attach it
        const pos = getMousePos(e);
        let targetNode = null;
        for (const n of nodes) {
            if (Math.hypot(pos.x - n.point.x, pos.y - n.point.y) < (is3DMode ? 40 : 30)) {
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

    if (!is3DMode && e.target.releasePointerCapture) {
      (e.target as HTMLElement).releasePointerCapture(e.pointerId);
    }
    setDragging(null);
  };

  const onPointerCancel = (e: React.PointerEvent | any) => {
    if (!is3DMode) {
      pointersRef.current.delete(e.pointerId);
      if (pointersRef.current.size < 2) {
        lastPanMidpointRef.current = null;
      }
    }
    setMarqueeStart(null);
    setMarqueeEnd(null);
    setDragging(null);
  };

  const handleFlipEdge = (id: string) => {
    setEdges(prev => prev.map(e => {
      if (e.id !== id) return e;
      if (!e.target) return e;
      return {
        ...e,
        source: e.target,
        target: e.source,
        points: [...e.points].reverse(),
        sidewalkLeft: e.sidewalkRight,
        sidewalkRight: e.sidewalkLeft
      };
    }));
  };

  return (
    <div className="w-full h-screen bg-slate-950 text-slate-300 font-sans flex flex-col overflow-hidden">
      <Header
        isSidebarOpen={isSidebarOpen}
        setIsSidebarOpen={setIsSidebarOpen}
        handleImport={handleImport}
        handleExport={handleExport}
        showControlPoints={showControlPoints}
        setShowControlPoints={setShowControlPoints}
        is3DMode={is3DMode}
        setIs3DMode={setIs3DMode}
        showMesh={showMesh}
        setShowMesh={setShowMesh}
      />

      <div className="flex flex-grow overflow-hidden relative">
        <main className="flex-grow relative bg-slate-900 overflow-hidden" ref={containerRef}>
          {is3DMode ? (
            <ThreeScene 
              nodes={nodes} 
              edges={edges} 
              polygonFills={polygonFills}
              chamferAngle={chamferAngle} 
              meshResolution={meshResolution} 
              laneWidth={laneWidth}
              showMesh={showMesh}
              showControlPoints={showControlPoints}
              setNodes={setNodes} 
              setEdges={setEdges} 
              view={view}
              setView={setView}
              containerRef={containerRef}
              onPointerDown={onPointerDown}
              onPointerMove={onPointerMove}
              onPointerUp={onPointerUp}
              onPointerCancel={onPointerCancel}
              onContextMenu={onContextMenu}
              isDragging={dragging !== null && dragging.type !== 'pan'}
              draggingPoint={draggingPoint}
              softSelectionEnabled={softSelectionEnabled}
              softSelectionRadius={softSelectionRadius}
              selectedNode={selectedNode}
              selectedNodes={selectedNodes}
              selectedEdges={selectedEdges}
              selectedPoints={selectedPoints}
              selectedPolygonFillId={selectedPolygonFillId}
              marqueeStart={marqueeStart}
              marqueeEnd={marqueeEnd}
            />
          ) : (
            <>
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
                  <span className={isAddNodeMode ? "text-emerald-400" : "text-blue-300"}>
                    {isAddNodeMode ? "Click Node/Space" : "C"}
                  </span> 
                  {isAddNodeMode ? "Connect to / New Road" : "Add Node Mode"}
                </div>
                <div className="text-white font-bold flex flex-col gap-1.5 opacity-90">
                  <span className={isMergeMode ? "text-red-400" : "text-blue-300"}>
                    {isMergeMode ? "Click Node" : "M"}
                  </span>
                  {isMergeMode ? "Merge With Selected" : "Merge Mode"}
                </div>
                <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Middle Drag / 2 Fingers</span> Pan</div>
                <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Scroll</span> Zoom</div>
                <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Click Edge</span> Add Point</div>
                <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">P</span> (with 3+ nodes) Fill Polygon</div>
                <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Esc</span> Deselect</div>
              </div>
            </>
          )}
        </main>

        <Sidebar
          isSidebarOpen={isSidebarOpen}
          setIsSidebarOpen={setIsSidebarOpen}
          isAddNodeMode={isAddNodeMode}
          setIsAddNodeMode={setIsAddNodeMode}
          softSelectionEnabled={softSelectionEnabled}
          setSoftSelectionEnabled={setSoftSelectionEnabled}
          softSelectionRadius={softSelectionRadius}
          setSoftSelectionRadius={setSoftSelectionRadius}
          chamferAngle={chamferAngle}
          setChamferAngle={setChamferAngle}
          meshResolution={meshResolution}
          setMeshResolution={setMeshResolution}
          laneWidth={laneWidth}
          setLaneWidth={setLaneWidth}
          nodes={nodes}
          setNodes={setNodes}
          edges={edges}
          setEdges={setEdges}
          selectedNodes={selectedNodes}
          setSelectedNodes={setSelectedNodes}
          selectedEdges={selectedEdges}
          setSelectedEdges={setSelectedEdges}
        />
      </div>
    </div>
  );
}
