import React, { useState, useEffect, useRef, useMemo } from 'react';
import { Settings2, Trash2, Plus, Bug, Menu, X, Layers, Download, Upload, Box, ChevronDown, ChevronRight, Copy, ClipboardPaste } from 'lucide-react';
import { Point, Node, Edge, MeshData } from './lib/types';
import { getEdgeControlPoints, getExtendedEdgeControlPoints, sampleEdgeSpline } from './lib/network';
import { buildNetworkMesh } from './lib/meshing';
import { getDir, distToSegment } from './lib/math';
import { splitBezier } from './lib/splines';
import ThreeScene from './ThreeScene';

const COLORS = ['#ef4444', '#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899'];
const ROAD_NETWORK_SCHEMA = 'cab87-road-network';
const ROAD_NETWORK_VERSION = 1;
const DEFAULT_CHAMFER_ANGLE = 70;
const DEFAULT_MESH_RESOLUTION = 20;

function sanitizeMeshResolution(value: unknown): number {
  const parsed = typeof value === 'number' ? value : parseInt(String(value), 10);
  if (!Number.isFinite(parsed)) return DEFAULT_MESH_RESOLUTION;
  return Math.max(5, Math.min(100, Math.round(parsed)));
}

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
    { id: 'e1', source: 'n1', target: 'n2', points: [{x: 466, y: 250, linear: true}, {x: 533, y: 200, linear: true}], width: 60, sidewalk: 12, color: '#ef4444' },
    { id: 'e2', source: 'n1', target: 'n3', points: [{x: 333, y: 333, linear: true}, {x: 266, y: 366, linear: true}], width: 60, sidewalk: 12, color: '#10b981' },
    { id: 'e3', source: 'n1', target: 'n4', points: [{x: 366, y: 233, linear: true}, {x: 333, y: 166, linear: true}], width: 80, sidewalk: 12, color: '#3b82f6' },
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
  const [isConnectMode, setIsConnectMode] = useState(false);
  
  const [dragging, setDragging] = useState<{ type: 'node' | 'edge' | 'pan'; id: string; pointId?: number } | null>(null);

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
  const [view, setView] = useState({ x: 0, y: 0, zoom: 1 });  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [selectedPointIndex, setSelectedPointIndex] = useState<number | null>(null);
  const [editingEdgeName, setEditingEdgeName] = useState<string | null>(null);
  const [editingNameValue, setEditingNameValue] = useState("");
  const [chamferAngle, setChamferAngle] = useState(DEFAULT_CHAMFER_ANGLE);
  const [meshResolution, setMeshResolution] = useState(DEFAULT_MESH_RESOLUTION);
  const [laneWidth, setLaneWidth] = useState(30);
  const [is3DMode, setIs3DMode] = useState(false);
  const [softSelectionEnabled, setSoftSelectionEnabled] = useState(false);
  const [softSelectionRadius, setSoftSelectionRadius] = useState(200);
  const [collapsedSections, setCollapsedSections] = useState<Record<string, boolean>>({});
  const toggleSection = (section: string) => setCollapsedSections(prev => ({ ...prev, [section]: !prev[section] }));
  const [copiedEdgeSettings, setCopiedEdgeSettings] = useState<Partial<Edge> | null>(null);

  const fileInputRef = useRef<HTMLInputElement>(null);

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
            setChamferAngle(DEFAULT_CHAMFER_ANGLE);
          }
          const importedMeshResolution = data.settings?.meshResolution ?? data.settings?.splineSegments;
          if (typeof importedMeshResolution === 'number') {
            setMeshResolution(sanitizeMeshResolution(importedMeshResolution));
          } else {
            setMeshResolution(DEFAULT_MESH_RESOLUTION);
          }
          if (typeof data.settings?.laneWidth === 'number') {
            setLaneWidth(data.settings.laneWidth);
          } else {
            setLaneWidth(30);
          }
          setSelectedEdges([]);
          setSelectedNode(null);
          setSelectedPointIndex(null);
          setIsConnectMode(false);
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
        setSelectedEdges([]);
        setSelectedPointIndex(null);
        setDragging(null);
        setIsConnectMode(false);
        setIsMergeMode(false);
      }
      if (e.key.toLowerCase() === 'c') {
        setIsConnectMode(prev => !prev);
        setIsMergeMode(false);
      }
      if (e.key.toLowerCase() === 'm') {
        setIsMergeMode(prev => !prev);
        setIsConnectMode(false);
      }
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (selectedEdges.length > 0 && selectedPointIndex !== null && selectedNodes.length === 0 && selectedEdges.length === 1) {
          setEdges(prev => prev.map(edge => {
            if (selectedEdges.includes(edge.id)) {
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
        } else if (selectedNodes.length > 0 || selectedEdges.length > 0) {
          setNodes(prev => prev.filter(n => !selectedNodes.includes(n.id)));
          setEdges(prev => prev.filter(edge => !selectedEdges.includes(edge.id) && !selectedNodes.includes(edge.source) && (!edge.target || !selectedNodes.includes(edge.target))));
          setSelectedNodes([]);
          setSelectedEdges([]);
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
  }, [selectedNode, selectedEdges, selectedPointIndex, nodes, edges, size, isMergeMode, isConnectMode]);

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
    draw(ctx, size, nodes, edges, selectedEdges, selectedNodes, showMesh, chamferAngle, meshResolution, laneWidth, softSelectionEnabled, softSelectionRadius, draggingPoint);
    ctx.restore();
  }, [size, nodes, edges, selectedEdges, selectedNodes, isConnectMode, isMergeMode, showMesh, showControlPoints, view, chamferAngle, meshResolution, laneWidth, softSelectionEnabled, softSelectionRadius, draggingPoint]);

  const draw = (ctx: CanvasRenderingContext2D, size: { w: number; h: number }, nodes: Node[], edges: Edge[], selectedEdges: string[], selectedNodes: string[], showMesh: boolean, chamferAngle: number, meshResolution: number, laneWidth: number, softSelectionEnabled: boolean, softSelectionRadius: number, draggingPoint: Point | null) => {
    ctx.clearRect(0, 0, size.w, size.h);

    if (nodes.length === 0) return;

    const mesh = buildNetworkMesh(nodes, edges, chamferAngle, meshResolution, laneWidth);

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
      const getAvgZ = (paths: Point[]) => {
        let sum = 0;
        for (const p of paths) sum += (p.z ?? 4);
        return sum / (paths.length || 1);
      };

      const getZColor = (paths: Point[], type: 'road' | 'sidewalk' | 'crosswalk' | 'hub') => {
        const z = getAvgZ(paths);
        const zDiff = (z - 4);
        if (type === 'road' || type === 'hub') {
            const l = Math.max(5, Math.min(80, 17 + zDiff * 0.06));
            return `hsl(217, 33%, ${l}%)`;
        } else if (type === 'sidewalk') {
            const l = Math.max(30, Math.min(95, 65 + zDiff * 0.06));
            return `hsl(215, 25%, ${l}%)`;
        } else if (type === 'crosswalk') {
            const l = Math.max(10, Math.min(85, 27 + zDiff * 0.06));
            return `hsl(215, 25%, ${l}%)`;
        }
        return '#000';
      };

      ctx.shadowColor = 'rgba(0,0,0,0.5)';
      ctx.shadowBlur = 15;
      ctx.shadowOffsetY = 4;
      
      const renderables: { z: number, priority: number, paths: Point[], draw: () => void }[] = [];

      mesh.roadPolygons.forEach(rp => {
        if (rp.outerLeftCurve && rp.outerRightCurve && rp.outerLeftCurve.length === rp.outerRightCurve.length && rp.outerLeftCurve.length > 0) {
            for (let i = 0; i < rp.outerLeftCurve.length - 1; i++) {
                const p0 = rp.outerLeftCurve[i];
                const p1 = rp.outerRightCurve[i];
                const p2 = rp.outerRightCurve[i+1];
                const p3 = rp.outerLeftCurve[i+1];
                const poly = [p0, p1, p2, p3];
                renderables.push({
                    z: getAvgZ(poly),
                    priority: 0,
                    paths: poly,
                    draw: () => {
                        ctx.fillStyle = getZColor(poly, 'sidewalk');
                        ctx.beginPath();
                        ctx.moveTo(p0.x, p0.y);
                        ctx.lineTo(p1.x, p1.y);
                        ctx.lineTo(p2.x, p2.y);
                        ctx.lineTo(p3.x, p3.y);
                        ctx.closePath();
                        ctx.fill();
                        ctx.strokeStyle = ctx.fillStyle;
                        ctx.lineWidth = 0.5;
                        ctx.stroke();
                    }
                });
            }
        } else if (rp.outerPolygon && rp.outerPolygon.length > 0) {
            renderables.push({
                z: getAvgZ(rp.outerPolygon),
                priority: 0,
                paths: rp.outerPolygon,
                draw: () => {
                    ctx.fillStyle = getZColor(rp.outerPolygon, 'sidewalk');
                    ctx.beginPath();
                    ctx.moveTo(rp.outerPolygon[0].x, rp.outerPolygon[0].y);
                    rp.outerPolygon.forEach(p => ctx.lineTo(p.x, p.y));
                    ctx.closePath();
                    ctx.fill();
                }
            });
        }
      });
      
      mesh.sidewalkPolygons.forEach(poly => {
        if (poly.length === 0) return;
        renderables.push({
            z: getAvgZ(poly),
            priority: 0,
            paths: poly,
            draw: () => {
                ctx.fillStyle = getZColor(poly, 'sidewalk');
                ctx.beginPath();
                ctx.moveTo(poly[0].x, poly[0].y);
                poly.forEach(p => ctx.lineTo(p.x, p.y));
                ctx.closePath();
                ctx.fill();
            }
        });
      });

      mesh.hubs.forEach(hub => {
        if (hub.polygon.length === 0) return;
        renderables.push({
            z: getAvgZ(hub.polygon),
            priority: 1,
            paths: hub.polygon,
            draw: () => {
                ctx.fillStyle = getZColor(hub.polygon, 'hub');
                ctx.beginPath();
                ctx.moveTo(hub.polygon[0].x, hub.polygon[0].y);
                hub.polygon.forEach(p => ctx.lineTo(p.x, p.y));
                ctx.closePath();
                ctx.fill();
            }
        });
      });

      mesh.roadPolygons.forEach(rp => {
        if (rp.leftCurve && rp.rightCurve && rp.leftCurve.length === rp.rightCurve.length && rp.leftCurve.length > 0) {
            for (let i = 0; i < rp.leftCurve.length - 1; i++) {
                const p0 = rp.leftCurve[i];
                const p1 = rp.rightCurve[i];
                const p2 = rp.rightCurve[i+1];
                const p3 = rp.leftCurve[i+1];
                const poly = [p0, p1, p2, p3];
                renderables.push({
                    z: getAvgZ(poly),
                    priority: 2,
                    paths: poly,
                    draw: () => {
                        ctx.fillStyle = getZColor(poly, 'road');
                        ctx.beginPath();
                        ctx.moveTo(p0.x, p0.y);
                        ctx.lineTo(p1.x, p1.y);
                        ctx.lineTo(p2.x, p2.y);
                        ctx.lineTo(p3.x, p3.y);
                        ctx.closePath();
                        ctx.fill();
                        ctx.strokeStyle = ctx.fillStyle;
                        ctx.lineWidth = 0.5;
                        ctx.stroke();
                    }
                });
            }
        } else if (rp.polygon && rp.polygon.length > 0) {
            renderables.push({
                z: getAvgZ(rp.polygon),
                priority: 2,
                paths: rp.polygon,
                draw: () => {
                    ctx.fillStyle = getZColor(rp.polygon, 'road');
                    ctx.beginPath();
                    ctx.moveTo(rp.polygon[0].x, rp.polygon[0].y);
                    rp.polygon.forEach(p => ctx.lineTo(p.x, p.y));
                    ctx.closePath();
                    ctx.fill();
                }
            });
        }
      });

      mesh.crosswalks.forEach(cw => {
         if (cw.polygon.length === 0) return;
         renderables.push({
             z: getAvgZ(cw.polygon),
             priority: 3,
             paths: cw.polygon,
             draw: () => {
                 ctx.fillStyle = getZColor(cw.polygon, 'crosswalk');
                 ctx.beginPath();
                 ctx.moveTo(cw.polygon[0].x, cw.polygon[0].y);
                 cw.polygon.forEach(p => ctx.lineTo(p.x, p.y));
                 ctx.closePath();
                 ctx.fill();
                 
                 if (cw.polygon.length === 4) {
                     const p0 = cw.polygon[0];
                     const p1 = cw.polygon[1];
                     const p2 = cw.polygon[2];
                     const p3 = cw.polygon[3];
                     const midLeft = { x: (p0.x + p3.x)/2, y: (p0.y + p3.y)/2 };
                     const midRight = { x: (p1.x + p2.x)/2, y: (p1.y + p2.y)/2 };
                     
                     ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
                     ctx.lineWidth = 10;
                     ctx.setLineDash([4, 6]);
                     ctx.beginPath();
                     ctx.moveTo(midLeft.x, midLeft.y);
                     ctx.lineTo(midRight.x, midRight.y);
                     ctx.stroke();
                     ctx.setLineDash([]);
                 }
             }
         });
      });
      
      mesh.dashedLines.forEach(cl => {
          if (cl.length > 0) {
              let currentDist = 0;
              for (let i = 0; i < cl.length - 1; i++) {
                  const p1 = cl[i];
                  const p2 = cl[i+1];
                  const segLen = Math.hypot(p2.x - p1.x, p2.y - p1.y);
                  const startOffset = currentDist;
                  currentDist += segLen;

                  renderables.push({
                      z: getAvgZ([p1, p2]),
                      priority: 4,
                      paths: [p1, p2],
                      draw: () => {
                          ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
                          ctx.lineWidth = 2;
                          ctx.setLineDash([15, 15]);
                          ctx.lineDashOffset = -startOffset;
                          ctx.beginPath();
                          ctx.moveTo(p1.x, p1.y);
                          ctx.lineTo(p2.x, p2.y);
                          ctx.stroke();
                          ctx.setLineDash([]);
                          ctx.lineDashOffset = 0;
                      }
                  });
              }
          }
      });

      mesh.solidYellowLines.forEach(cl => {
          if (cl.length > 0) {
              for (let j = 0; j < cl.length - 1; j++) {
                  const p1 = cl[j];
                  const p2 = cl[j+1];
                  renderables.push({
                      z: getAvgZ([p1, p2]),
                      priority: 4,
                      paths: [p1, p2],
                      draw: () => {
                          ctx.strokeStyle = '#eab308';
                          ctx.lineWidth = 2;
                          
                          const dx = p2.x - p1.x;
                          const dy = p2.y - p1.y;
                          const len = Math.hypot(dx, dy);
                          if (len === 0) return;
                          const nx = -dy / len * 2;
                          const ny = dx / len * 2;
                          
                          ctx.beginPath();
                          ctx.moveTo(p1.x + nx, p1.y + ny);
                          ctx.lineTo(p2.x + nx, p2.y + ny);
                          ctx.stroke();

                          ctx.beginPath();
                          ctx.moveTo(p1.x - nx, p1.y - ny);
                          ctx.lineTo(p2.x - nx, p2.y - ny);
                          ctx.stroke();
                      }
                  });
              }
          }
      });
      
      mesh.laneArrows.forEach(arrow => {
          renderables.push({
              z: arrow.position.z ?? 4,
              priority: 5,
              paths: [arrow.position],
              draw: () => {
                  ctx.fillStyle = 'rgba(255, 255, 255, 0.6)';
                  ctx.beginPath();
                  ctx.moveTo(arrow.position.x + arrow.dir.x * 6, arrow.position.y + arrow.dir.y * 6);
                  const right = { x: -arrow.dir.y, y: arrow.dir.x };
                  ctx.lineTo(arrow.position.x - arrow.dir.x * 4 + right.x * 4, arrow.position.y - arrow.dir.y * 4 + right.y * 4);
                  ctx.lineTo(arrow.position.x - arrow.dir.x * 4 - right.x * 4, arrow.position.y - arrow.dir.y * 4 - right.y * 4);
                  ctx.closePath();
                  ctx.fill();
              }
          });
      });

      renderables.sort((a, b) => {
          if (Math.abs(a.z - b.z) > 0.05) return a.z - b.z;
          return a.priority - b.priority;
      });

      renderables.forEach(r => {
          if (r.priority > 0) ctx.shadowColor = 'transparent';
          r.draw();
      });
      
    }

    // Soft selection radius
    if (softSelectionEnabled && draggingPoint) {
      ctx.beginPath();
      ctx.arc(draggingPoint.x, draggingPoint.y, softSelectionRadius, 0, Math.PI * 2);
      ctx.setLineDash([5, 5]);
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
      ctx.lineWidth = 2;
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Nodes and control points
    nodes.forEach(n => {
        ctx.beginPath();
        ctx.arc(n.point.x, n.point.y, 8, 0, Math.PI * 2);
        ctx.fillStyle = selectedNodes.includes(n.id) ? '#ffffff' : '#60a5fa';
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = '#fff';
        ctx.stroke();

        if (selectedNodes.includes(n.id)) {
          ctx.beginPath();
          ctx.arc(n.point.x, n.point.y, 16, 0, Math.PI * 2);
          ctx.strokeStyle = isConnectMode ? 'rgba(52, 211, 153, 0.8)' : isMergeMode ? 'rgba(239, 68, 68, 0.8)' : 'rgba(255, 255, 255, 0.4)';
          ctx.lineWidth = (isConnectMode || isMergeMode) ? 3 : 2;
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
                for (let i = 0; i + 3 < cubicPts.length; i += 3) {
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
            const isSelectedPoint = selectedEdges.includes(e.id) && selectedPointIndex === j;
            ctx.arc(pt.x, pt.y, isAnchor ? 8 : 5, 0, Math.PI * 2);
            ctx.fillStyle = selectedEdges.includes(e.id) ? (isSelectedPoint ? '#ef4444' : (isAnchor ? (pt.linked ? '#10b981' : '#fbbf24') : (pt.linear ? '#0ea5e9' : '#ffffff'))) : '#64748b';
            ctx.fill();
            ctx.stroke();
        });
    });
  };

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
    const pos = getMousePos(e);

    // Right click existing node
    for (const n of nodes) {
        if (Math.hypot(pos.x - n.point.x, pos.y - n.point.y) < 25) {
            if (selectedNode && selectedNode !== n.id) {
                const sn = nodes.find(nn => nn.id === selectedNode)!;
                const newEdgeId = Math.random().toString(36).substring(2, 9);
                const newEdge: Edge = {
                    id: newEdgeId,
                    source: selectedNode,
                    target: n.id,
                    points: [
                      { x: sn.point.x + (n.point.x - sn.point.x)/3, y: sn.point.y + (n.point.y - sn.point.y)/3, z: sn.point.z ?? 4, linear: true },
                      { x: sn.point.x + 2*(n.point.x - sn.point.x)/3, y: sn.point.y + 2*(n.point.y - sn.point.y)/3, z: n.point.z ?? 4, linear: true }
                    ],
                    width: 60,
                    sidewalk: 12,
                    color: COLORS[edges.length % COLORS.length]
                };
                setEdges(prev => [...prev, newEdge]);
                setSelectedNode(n.id);
                setSelectedEdges([newEdgeId]);
                setSelectedPointIndex(null);
                setIsConnectMode(false);
                setIsMergeMode(false);
            } else {
                setSelectedNode(n.id);
                setSelectedEdges([]);
                setSelectedPointIndex(null);
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
            return;
        }
    }

    // Right click Empty Space
    const newNodeId = Math.random().toString(36).substring(2, 9);
    
    let spawnPos = pos;
    if (selectedNode) {
        const sn = nodes.find(n => n.id === selectedNode);
        if (sn) {
            spawnPos = { ...pos, z: sn.point.z };
        }
    }

    setNodes(prev => [...prev, { id: newNodeId, point: spawnPos }]);

    if (selectedNode) {
        const sn = nodes.find(n => n.id === selectedNode);
        if (sn) {
            const newEdgeId = Math.random().toString(36).substring(2, 9);
            const newEdge: Edge = {
                id: newEdgeId, source: selectedNode, target: newNodeId, points: [
                  { x: sn.point.x + (spawnPos.x - sn.point.x)/3, y: sn.point.y + (spawnPos.y - sn.point.y)/3, z: sn.point.z ?? 4, linear: true },
                  { x: sn.point.x + 2*(spawnPos.x - sn.point.x)/3, y: sn.point.y + 2*(spawnPos.y - sn.point.y)/3, z: spawnPos.z ?? 4, linear: true }
                ], width: 60, sidewalk: 12, color: COLORS[edges.length % COLORS.length]
            };
            setEdges(prev => [...prev, newEdge]);
            setSelectedEdges([newEdgeId]);
        }
    } else {
        setSelectedEdges([]);
    }
    
    setSelectedNode(newNodeId);
    setSelectedPointIndex(null);
    setIsConnectMode(false);
    setIsMergeMode(false);
  };

  const onPointerDown = (e: React.PointerEvent | any) => {
    if (e.button === 2) return; // ignore right click

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
                setSelectedPointIndex(null);
                startDragPosRef.current = pos;
                setDragging({ type: 'node', id: n.id });
                return;
            }

            if (selectedNodes.includes(n.id) && selectedNodes.length > 1) {
                startDragPosRef.current = pos;
                setDragging({ type: 'node', id: n.id });
                return;
            }

            if (e.altKey) {
                setEdges(prev => prev.map(edge => {
                    const newPts = [...edge.points];
                    let changed = false;
                    if (edge.source === n.id && newPts.length > 0) {
                        const targetNode = edge.target ? nodes.find(tn => tn.id === edge.target) : null;
                        const targetAnchor = newPts.length >= 3 ? newPts[2] : (targetNode ? targetNode.point : newPts[1]);
                        if (targetAnchor) {
                            newPts[0] = { ...newPts[0], x: n.point.x + (targetAnchor.x - n.point.x) / 3, y: n.point.y + (targetAnchor.y - n.point.y) / 3, z: !newPts[0].linear ? n.point.z ?? 4 : newPts[0].z, linear: !newPts[0].linear };
                            changed = true;
                        }
                    }
                    if (edge.target === n.id && newPts.length > 1) {
                        const sourceNode = nodes.find(sn => sn.id === edge.source);
                        const prevAnchor = newPts.length >= 3 ? newPts[newPts.length - 3] : (sourceNode ? sourceNode.point : newPts[0]);
                        if (prevAnchor) {
                            newPts[newPts.length - 1] = { ...newPts[newPts.length - 1], x: n.point.x + (prevAnchor.x - n.point.x) / 3, y: n.point.y + (prevAnchor.y - n.point.y) / 3, z: !newPts[newPts.length - 1].linear ? n.point.z ?? 4 : newPts[newPts.length - 1].z, linear: !newPts[newPts.length - 1].linear };
                            changed = true;
                        }
                    }
                    return changed ? { ...edge, points: newPts } : edge;
                }));
                setSelectedNode(n.id);
                setSelectedEdges([]);
                setSelectedPointIndex(null);
                setIsConnectMode(false);
                setIsMergeMode(false);
                setDragging({ type: 'node', id: n.id });
                return;
            }

            if (selectedNode && selectedNode !== n.id && (isConnectMode || isMergeMode)) {
                if (isConnectMode) {
                    // Connect selectedNode to this node
                    const sn = nodes.find(nn => nn.id === selectedNode)!;
                    const id = Math.random().toString(36).substring(2, 9);
                    const newEdge: Edge = {
                        id,
                        source: selectedNode,
                        target: n.id,
                        points: [
                          { x: sn.point.x + (n.point.x - sn.point.x)/3, y: sn.point.y + (n.point.y - sn.point.y)/3, z: sn.point.z ?? 4, linear: true },
                          { x: sn.point.x + 2*(n.point.x - sn.point.x)/3, y: sn.point.y + 2*(n.point.y - sn.point.y)/3, z: n.point.z ?? 4, linear: true }
                        ],
                        width: 60,
                        sidewalk: 12,
                        color: COLORS[edges.length % COLORS.length]
                    };
                    setEdges(prev => [...prev, newEdge]);
                    setSelectedNode(n.id);
                    setSelectedEdges([id]);
                    setSelectedPointIndex(null);
                    setIsConnectMode(false);
                } else if (isMergeMode) {
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
                newPts[j - 1] = { 
                    ...newPts[j - 1], 
                    x: newPts[j].x + (prevAnchor.x - newPts[j].x) / 3, 
                    y: newPts[j].y + (prevAnchor.y - newPts[j].y) / 3, 
                    z: !newPts[j - 1].linear ? newPts[j].z ?? 4 : newPts[j - 1].z,
                    linear: !newPts[j - 1].linear 
                };
                  newPts[j] = { ...newPts[j], linked: false };
                if (targetNode || j + 3 < newPts.length) {
                    newPts[j + 1] = { 
                        ...newPts[j + 1], 
                        x: newPts[j].x + (nextAnchor.x - newPts[j].x) / 3, 
                        y: newPts[j].y + (nextAnchor.y - newPts[j].y) / 3, 
                        z: !newPts[j + 1].linear ? newPts[j].z ?? 4 : newPts[j + 1].z,
                        linear: !newPts[j + 1].linear 
                    };
                }
              } else if (j % 3 === 0) {
                if (newPts[j].linear) {
                    newPts[j] = { ...newPts[j], linear: false };
                } else {
                    const anchorA = j === 0 ? sourceNode.point : newPts[j - 1];
                    const anchorB = j + 2 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 2];
                    newPts[j] = { x: anchorA.x + (anchorB.x - anchorA.x) / 3, y: anchorA.y + (anchorB.y - anchorA.y) / 3, z: anchorA.z ?? 4, linear: true };
                }
                if (j > 0 && newPts[j - 1]) newPts[j - 1] = { ...newPts[j - 1], linked: false };
              } else if (j % 3 === 1) {
                if (newPts[j].linear) {
                    newPts[j] = { ...newPts[j], linear: false };
                } else {
                    const anchorB = j + 1 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 1];
                    const anchorA = j === 1 ? sourceNode.point : newPts[j - 2];
                    newPts[j] = { x: anchorB.x + (anchorA.x - anchorB.x) / 3, y: anchorB.y + (anchorA.y - anchorB.y) / 3, z: anchorB.z ?? 4, linear: true };
                }
                if (j + 1 < newPts.length && newPts[j + 1]) newPts[j + 1] = { ...newPts[j + 1], linked: false };
              }
              return { ...edge, points: newPts };
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
                    const angle = Math.atan2(h2.y - h1.y, h2.x - h1.x);
                    const d1 = Math.hypot(h1.x - anchor.x, h1.y - anchor.y);
                    const d2 = Math.hypot(h2.x - anchor.x, h2.y - anchor.y);
                    newPts[j - 1] = { ...h1, x: anchor.x - Math.cos(angle) * d1, y: anchor.y - Math.sin(angle) * d1, linear: false };
                    newPts[j + 1] = { ...h2, x: anchor.x + Math.cos(angle) * d2, y: anchor.y + Math.sin(angle) * d2, linear: false };
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
                        newPts[oppositeIdx] = { ...h2, x: anchor.x + Math.cos(oppAngle) * d2, y: anchor.y + Math.sin(oppAngle) * d2 };
                        newPts[anchorIdx] = { ...anchor, linked: true };
                    }
                }
              }
              return { ...edge, points: newPts };
            }));
            // Note: we DO NOT return here, so that dragging can immediately begin.
          }

          setDragging({ type: 'edge', id: edges[i].id, pointId: j });
          setSelectedEdges([edges[i].id]);
          setSelectedNode(null);
          setSelectedPointIndex(j);
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
        setSelectedPointIndex(dragPointId);
        setDragging({ type: 'edge', id: edge.id, pointId: dragPointId });
        
        return;
      }
    }

    // Click Empty Space
    // Default deselect
    setSelectedNode(null);
    setSelectedEdges([]);
    setSelectedPointIndex(null);
    setIsConnectMode(false);
    setIsMergeMode(false);
  };

  const enforceLinear = (edge: Edge, currentNodes: Node[], oldEdge?: Edge, oldNodes?: Node[]) => {
      const newPts = [...edge.points];
      let changed = false;
      const sourceNode = currentNodes.find(n => n.id === edge.source);
      const targetNode = edge.target ? currentNodes.find(n => n.id === edge.target) : null;
      
      const oldSourceNode = oldNodes ? oldNodes.find(n => n.id === edge.source) : sourceNode;
      const oldTargetNode = oldNodes && edge.target ? oldNodes.find(n => n.id === edge.target) : targetNode;
      const oldPts = oldEdge ? oldEdge.points : newPts;

      for (let j = 0; j < newPts.length; j++) {
          const handle = newPts[j];
          if (!handle.linear) continue;
          
          const oldHandle = oldPts[j] || handle;

          if (j % 3 === 0) {
              const anchorA = j === 0 ? sourceNode?.point : newPts[j - 1];
              const anchorB = j + 2 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 2];
              
              const oldAnchorA = j === 0 ? oldSourceNode?.point : oldPts[j - 1];
              const oldAnchorB = j + 2 >= oldPts.length ? (oldTargetNode ? oldTargetNode.point : oldPts[j]) : oldPts[j + 2];

              if (!anchorA || !anchorB || !oldAnchorA || !oldAnchorB) continue;
              
              const dx = anchorB.x - anchorA.x;
              const dy = anchorB.y - anchorA.y;
              
              const oldDx = oldAnchorB.x - oldAnchorA.x;
              const oldDy = oldAnchorB.y - oldAnchorA.y;
              const oldLenSq = oldDx * oldDx + oldDy * oldDy;
              
              if (oldLenSq > 0.0001) {
                  const hx = oldHandle.x - oldAnchorA.x;
                  const hy = oldHandle.y - oldAnchorA.y;
                  let t = (hx * oldDx + hy * oldDy) / oldLenSq;
                  t = Math.max(0, t);
                  newPts[j] = { ...handle, x: anchorA.x + dx * t, y: anchorA.y + dy * t, z: handle.z ?? anchorA.z ?? 4 };
                  changed = true;
              }
          } else if (j % 3 === 1) {
              const anchorA = j + 1 >= newPts.length ? (targetNode ? targetNode.point : newPts[j]) : newPts[j + 1];
              const anchorB = j === 1 ? sourceNode?.point : newPts[j - 2];
              
              const oldAnchorA = j + 1 >= oldPts.length ? (oldTargetNode ? oldTargetNode.point : oldPts[j]) : oldPts[j + 1];
              const oldAnchorB = j === 1 ? oldSourceNode?.point : oldPts[j - 2];

              if (!anchorA || !anchorB || !oldAnchorA || !oldAnchorB) continue;
              const dx = anchorB.x - anchorA.x;
              const dy = anchorB.y - anchorA.y;
              
              const oldDx = oldAnchorB.x - oldAnchorA.x;
              const oldDy = oldAnchorB.y - oldAnchorA.y;
              const oldLenSq = oldDx * oldDx + oldDy * oldDy;
              
              if (oldLenSq > 0.0001) {
                  const hx = oldHandle.x - oldAnchorA.x;
                  const hy = oldHandle.y - oldAnchorA.y;
                  let t = (hx * oldDx + hy * oldDy) / oldLenSq;
                  t = Math.max(0, t);
                  newPts[j] = { ...handle, x: anchorA.x + dx * t, y: anchorA.y + dy * t, z: handle.z ?? anchorA.z ?? 4 };
                  changed = true;
              }
          }
      }
      return changed ? { ...edge, points: newPts } : edge;
  };

  const handleDrag = (dragState: { type: 'node' | 'edge' | 'pan'; id: string; pointId?: number }, pos: Point, shiftKey: boolean) => {
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
      const pid = dragState.pointId;
      const draggingEdge = edges.find(e => e.id === dragState.id);
      if (!draggingEdge) return;
      const originPoint = draggingEdge.points[pid];
      let dx = pos.x - originPoint.x;
      let dy = pos.y - originPoint.y;
      if (is3DMode && shiftKey) { dx = 0; dy = 0; }
      const dz = pos.z !== undefined ? pos.z - (originPoint.z ?? 4) : 0;

      let newNodes = nodes;
      if (softSelectionEnabled) {
          newNodes = nodes.map(n => {
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
      }
      
      setEdges((prev) => prev.map((e) => {
        if (e.id !== draggingEdge.id && !softSelectionEnabled) return e;
        
        let newPoints = [...e.points];
        let changed = false;

        if (e.id === draggingEdge.id) {
            const oldTarget = newPoints[pid];
            let ddx = pos.x - oldTarget.x;
            let ddy = pos.y - oldTarget.y;
            if (is3DMode && shiftKey) { ddx = 0; ddy = 0; }
            const ddz = pos.z !== undefined ? pos.z - (oldTarget.z ?? 4) : 0;

            if (pid % 3 === 2) {
               newPoints[pid] = { ...oldTarget, x: oldTarget.x + ddx, y: oldTarget.y + ddy, z: pos.z ?? oldTarget.z ?? 4 };
               if (pid - 1 >= 0) {
                   newPoints[pid - 1] = { ...newPoints[pid - 1], x: newPoints[pid - 1].x + ddx, y: newPoints[pid - 1].y + ddy, z: (newPoints[pid - 1].z ?? 4) + ddz };
               }
               if (pid + 1 < newPoints.length) {
                   newPoints[pid + 1] = { ...newPoints[pid + 1], x: newPoints[pid + 1].x + ddx, y: newPoints[pid + 1].y + ddy, z: (newPoints[pid + 1].z ?? 4) + ddz };
               }
            } else if (pid % 3 === 0 || pid % 3 === 1) {
                const handle = newPoints[pid];
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
                        const oppDist = curDist;
                        
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
                        x: pt.x + dx * w,
                        y: pt.y + dy * w,
                        z: (pt.z ?? 4) + dz * w
                    };
                });
            }
        } else if (softSelectionEnabled) {
            newPoints = newPoints.map((pt, idx) => {
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

        const passOldEdge = (pid % 3 === 2);
        return changed ? enforceLinear({ ...e, points: newPoints }, newNodes, passOldEdge ? e : undefined, passOldEdge ? nodes : undefined) : e;
      }));
    }
  };

  const onPointerMove = (e: React.PointerEvent | any) => {
    if (is3DMode) {
      if (!dragging || dragging.type === 'pan') return;
    } else {
      const rect = canvasRef.current!.getBoundingClientRect();
      const rawPos = { x: e.clientX - rect.left, y: e.clientY - rect.top };
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
    setDragging(null);
  };

  const addNode = () => {
    const id = Math.random().toString(36).substring(2, 9);
    setNodes(prev => [...prev, { id, point: { x: (nodes[nodes.length-1]?.point?.x ?? 300) + 100, y: (nodes[nodes.length-1]?.point?.y ?? 200) + 100 } }]);
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
              { x: srcNode.point.x, y: srcNode.point.y + 33, z: srcNode.point.z ?? 4, linear: true },
              { x: srcNode.point.x, y: srcNode.point.y + 66, z: srcNode.point.z ?? 4, linear: true }
          ],
          width: 60,
          sidewalk: 12,
          color: COLORS[prev.length % COLORS.length]
      }]);
  }

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
            Cab87 Road Graph <span className="hidden sm:inline text-slate-500 font-normal">v3.0</span>
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
            onClick={() => setIs3DMode(!is3DMode)}
            className={`p-2 lg:px-3 lg:py-1.5 border rounded text-sm font-semibold flex items-center gap-2 transition-colors ${
              is3DMode 
                ? 'bg-blue-600 border-blue-500 text-white hover:bg-blue-500' 
                : 'border-slate-700 hover:bg-slate-800 text-slate-300'
            }`}
          >
            <Box className="w-4 h-4" />
            <span className="hidden md:inline">{is3DMode ? '2D View' : '3D View'}</span>
          </button>
          
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
          {is3DMode ? (
            <ThreeScene 
              nodes={nodes} 
              edges={edges} 
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
              selectedEdges={selectedEdges}
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
                  <span className={isConnectMode ? "text-emerald-400" : "text-blue-300"}>
                    {isConnectMode ? "Click Node/Space" : "C"}
                  </span> 
                  {isConnectMode ? "Connect to / New Road" : "Connect Mode"}
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
                <div className="text-white font-bold flex flex-col gap-1.5 opacity-90"><span className="text-blue-300">Esc</span> Deselect</div>
              </div>
            </>
          )}
        </main>

        <aside className={`${isSidebarOpen ? 'translate-x-0' : 'translate-x-full lg:translate-x-0'} fixed lg:relative right-0 top-0 h-full w-full sm:w-80 lg:w-72 border-l border-slate-800 bg-slate-900 p-4 lg:p-5 flex flex-col gap-4 shrink-0 overflow-y-auto transition-transform duration-300 ease-in-out z-40 lg:z-10`}>
          <div className="flex items-center justify-between lg:hidden mb-1">
            <h2 className="text-white font-bold text-lg uppercase tracking-tight">Properties</h2>
            <button 
              onClick={() => setIsSidebarOpen(false)}
              className="p-2 text-slate-400 hover:text-white bg-slate-800 rounded-full"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          <section>
            <div className="flex gap-2">
                <button onClick={addNode} className="flex-1 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded text-sm font-semibold flex justify-center items-center gap-2">Add Node</button>
                <button onClick={addEdge} className="flex-1 px-3 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded text-sm font-semibold flex justify-center items-center gap-2">Add Road</button>
            </div>
          </section>

          <section>
            <div 
              className="flex items-center justify-between cursor-pointer mb-2"
              onClick={() => toggleSection('selection')}
            >
              <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest">Selection</h3>
              {collapsedSections['selection'] ? <ChevronRight className="w-4 h-4 text-slate-500" /> : <ChevronDown className="w-4 h-4 text-slate-500" />}
            </div>
            {!collapsedSections['selection'] && (
              <div className="space-y-4 bg-slate-800/20 p-3 rounded-lg border border-slate-800/50">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-slate-300">Soft Selection</span>
                  <button 
                    onClick={() => setSoftSelectionEnabled(!softSelectionEnabled)}
                    className={`px-3 py-1 rounded text-xs font-medium transition-colors ${softSelectionEnabled ? 'bg-blue-600 text-white' : 'bg-slate-800 text-slate-400'}`}
                  >
                    {softSelectionEnabled ? 'ENABLED' : 'DISABLED'}
                  </button>
                </div>
                {softSelectionEnabled && (
                  <div>
                    <label className="block text-sm font-medium text-slate-300 mb-1">
                      Radius ({softSelectionRadius}px)
                    </label>
                    <input
                      type="range"
                      min="10"
                      max="1000"
                      step="10"
                      value={softSelectionRadius}
                      onChange={(e) => setSoftSelectionRadius(parseInt(e.target.value))}
                      className="w-full accent-blue-500 h-1.5 bg-slate-800 rounded-lg appearance-none cursor-pointer"
                    />
                  </div>
                )}
              </div>
            )}
          </section>

          <section>
            <div 
              className="flex items-center justify-between cursor-pointer mb-2"
              onClick={() => toggleSection('settings')}
            >
              <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest">Settings</h3>
              {collapsedSections['settings'] ? <ChevronRight className="w-4 h-4 text-slate-500" /> : <ChevronDown className="w-4 h-4 text-slate-500" />}
            </div>
            {!collapsedSections['settings'] && (
              <div className="space-y-4 bg-slate-800/20 p-3 rounded-lg border border-slate-800/50">
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
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-1">
                    Mesh Split Size ({meshResolution}px)
                  </label>
                  <div className="flex gap-2">
                    <input
                      type="range"
                      min="5"
                      max="100"
                      value={meshResolution}
                      onChange={(e) => setMeshResolution(sanitizeMeshResolution(e.target.value))}
                      className="flex-grow min-w-0"
                    />
                    <input
                      type="number"
                      min="5"
                      max="100"
                      value={meshResolution}
                      onChange={(e) => setMeshResolution(sanitizeMeshResolution(e.target.value))}
                      className="w-16 bg-slate-800 border bg-transparent text-white border-slate-700 rounded p-1 text-sm text-center"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-1">
                    Lane Width ({laneWidth}px)
                  </label>
                  <div className="flex gap-2">
                    <input
                      type="range"
                      min="10"
                      max="100"
                      value={laneWidth}
                      onChange={(e) => setLaneWidth(parseInt(e.target.value))}
                      className="flex-grow min-w-0"
                    />
                    <input
                      type="number"
                      min="10"
                      max="100"
                      value={laneWidth}
                      onChange={(e) => setLaneWidth(parseInt(e.target.value) || 30)}
                      className="w-16 bg-slate-800 border bg-transparent text-white border-slate-700 rounded p-1 text-sm text-center"
                    />
                  </div>
                </div>
              </div>
            )}
          </section>

          <section className="flex-grow flex flex-col min-h-0">
            <div 
              className="flex items-center justify-between cursor-pointer mb-2"
              onClick={() => toggleSection('junctions')}
            >
              <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest">Junctions {selectedNodes.length > 0 ? '(Selected)' : ''}</h3>
              {collapsedSections['junctions'] ? <ChevronRight className="w-4 h-4 text-slate-500" /> : <ChevronDown className="w-4 h-4 text-slate-500" />}
            </div>
            {!collapsedSections['junctions'] && (
              <div className="space-y-3 overflow-y-auto max-h-48 pb-4">
                {selectedNodes.length === 0 ? (
                  <div className="text-sm text-slate-500 text-center py-4 px-4 bg-slate-800/10 rounded-lg border border-slate-800/50 border-dashed">
                    Select a junction.
                  </div>
                ) : (
                  nodes.filter(n => selectedNodes.includes(n.id)).map((n) => (
                    <div
                      key={n.id}
                      className="p-3 bg-blue-900/10 rounded-xl border border-blue-500/50 flex flex-col gap-2"
                    >
                      <div className="flex justify-between items-center text-sm font-bold text-slate-200">
                        <span>Junction {n.id.substring(0,4)}</span>
                        <button
                          onClick={(evt) => {
                            evt.stopPropagation();
                            setNodes(prev => prev.filter(node => node.id !== n.id));
                            setSelectedNodes(prev => prev.filter(id => id !== n.id));
                            setEdges(prev => prev.filter(edge => edge.source !== n.id && edge.target !== n.id));
                          }}
                          className="text-slate-500 hover:text-red-400 p-1 rounded-lg hover:bg-slate-800 transition-colors"
                        >
                          <Trash2 className="w-4 h-4 opacity-70" />
                        </button>
                      </div>
                      <div className="grid grid-cols-3 gap-2">
                        <div>
                          <label className="text-xs text-slate-400 block mb-1">X</label>
                          <input type="number" disabled value={Math.round(n.point.x)} className="w-full bg-slate-900 text-slate-300 border border-slate-700 rounded p-1 text-xs" />
                        </div>
                        <div>
                          <label className="text-xs text-slate-400 block mb-1">Y</label>
                          <input type="number" disabled value={Math.round(n.point.y)} className="w-full bg-slate-900 text-slate-300 border border-slate-700 rounded p-1 text-xs" />
                        </div>
                        <div>
                          <label className="text-xs text-slate-400 block mb-1">Elevation Z</label>
                          <input 
                            type="number" 
                            value={Math.round(n.point.z ?? 4)} 
                            onChange={(e) => {
                                const val = parseInt(e.target.value) || 0;
                                setNodes(prev => prev.map(pn => pn.id === n.id ? { ...pn, point: { ...pn.point, z: val } } : pn));
                            }}
                            className="w-full bg-slate-800 text-white border border-slate-600 rounded p-1 text-xs focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 transition-colors" 
                          />
                        </div>
                      </div>
                    </div>
                  ))
                )}
              </div>
            )}
          </section>

          <section className="flex-grow flex flex-col min-h-0">
            <div 
              className="flex items-center justify-between cursor-pointer mb-2"
              onClick={() => toggleSection('edges')}
            >
              <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest">Edges {selectedEdges.length > 0 ? '(Selected)' : ''}</h3>
              {collapsedSections['edges'] ? <ChevronRight className="w-4 h-4 text-slate-500" /> : <ChevronDown className="w-4 h-4 text-slate-500" />}
            </div>
            {!collapsedSections['edges'] && (
              <div className="space-y-3 overflow-y-auto flex-grow pb-4">
                {edges.filter(e => selectedEdges.includes(e.id)).length === 0 ? (
                  <div className="text-sm text-slate-500 text-center py-8 px-4 bg-slate-800/10 rounded-lg border border-slate-800/50 border-dashed">
                    Select a road in the viewport to adjust its properties.
                  </div>
                ) : (
                  edges.filter(e => selectedEdges.includes(e.id)).map((e, idx) => (
                    <div
                      key={e.id}
                      className="p-3 lg:p-4 rounded-xl border transition-all pointer-events-none bg-blue-900/10 border-blue-500/50 ring-1 ring-blue-500/20"
                    >
                      <div className="flex justify-between items-center mb-3 pointer-events-auto">
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
                              setEditingNameValue(e.name || `Selected Road`);
                              setEditingEdgeName(e.id);
                            }}
                            className="text-sm font-bold text-slate-200 cursor-text"
                            title="Double-click to rename"
                          >
                            {e.name || `Selected Road`}
                          </span>
                        )}
                        <div className="flex items-center gap-1">
                          <button
                            onClick={(evt) => { 
                              evt.stopPropagation(); 
                              setCopiedEdgeSettings({
                                width: e.width,
                                sidewalkLeft: e.sidewalkLeft,
                                sidewalkRight: e.sidewalkRight,
                                transitionSmoothness: e.transitionSmoothness,
                              });
                            }}
                            title="Copy road settings"
                            className="text-slate-500 hover:text-blue-400 p-2 lg:p-1 rounded-lg hover:bg-slate-800 transition-colors"
                          >
                            <Copy className="w-4 h-4 opacity-70" />
                          </button>
                          <button
                            onClick={(evt) => { 
                              evt.stopPropagation(); 
                              if (!copiedEdgeSettings) return;
                              setEdges(prev => prev.map(ed => ed.id === e.id ? { ...ed, ...copiedEdgeSettings } : ed));
                            }}
                            title="Paste road settings"
                            disabled={!copiedEdgeSettings}
                            className={`p-2 lg:p-1 rounded-lg transition-colors ${copiedEdgeSettings ? 'text-slate-500 hover:text-emerald-400 hover:bg-slate-800 cursor-pointer' : 'text-slate-700 cursor-not-allowed'}`}
                          >
                            <ClipboardPaste className="w-4 h-4 opacity-70" />
                          </button>
                          <button
                            onClick={(evt) => { evt.stopPropagation(); setEdges(prev => prev.filter(edge => edge.id !== e.id)); setSelectedEdges(prev => prev.filter(id => id !== e.id)); }}
                            className="text-slate-500 hover:text-red-400 p-2 lg:p-1 rounded-lg hover:bg-slate-800 transition-colors ml-1"
                          >
                            <Trash2 className="w-4 h-4 opacity-70" />
                          </button>
                        </div>
                      </div>
                      <div className="flex flex-col gap-3 pointer-events-auto">
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
                            <span>Sidewalk (Left)</span>
                            <span>{e.sidewalkLeft ?? e.sidewalk ?? 12}px</span>
                          </div>
                          <input
                            type="range"
                            min="0"
                            max="100"
                            step="2"
                            value={e.sidewalkLeft ?? e.sidewalk ?? 12}
                            onChange={(evt) =>
                              setEdges((prev) =>
                                prev.map((pr) => (pr.id === e.id ? { ...pr, sidewalkLeft: parseInt(evt.target.value) } : pr))
                              )
                            }
                            className="w-full accent-emerald-500 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer mb-3"
                          />
                          <div className="flex justify-between text-xs text-slate-400 mb-1">
                            <span>Sidewalk (Right)</span>
                            <span>{e.sidewalkRight ?? e.sidewalk ?? 12}px</span>
                          </div>
                          <input
                            type="range"
                            min="0"
                            max="100"
                            step="2"
                            value={e.sidewalkRight ?? e.sidewalk ?? 12}
                            onChange={(evt) =>
                              setEdges((prev) =>
                                prev.map((pr) => (pr.id === e.id ? { ...pr, sidewalkRight: parseInt(evt.target.value) } : pr))
                              )
                            }
                            className="w-full accent-emerald-500 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer mb-3"
                          />
                          <div className="flex justify-between text-xs text-slate-400 mb-1">
                            <span>Transition Smoothing</span>
                            <span>{e.transitionSmoothness ?? 0}px</span>
                          </div>
                          <input
                            type="range"
                            min="0"
                            max="200"
                            step="5"
                            value={e.transitionSmoothness ?? 0}
                            onChange={(evt) =>
                              setEdges((prev) =>
                                prev.map((pr) => (pr.id === e.id ? { ...pr, transitionSmoothness: parseInt(evt.target.value) } : pr))
                              )
                            }
                            className="w-full accent-emerald-500 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer"
                          />
                        </div>
                        <div className="flex items-center gap-2 mt-2">
                          <input
                            type="checkbox"
                            checked={e.oneWay || false}
                            onChange={(evt) =>
                              setEdges((prev) =>
                                prev.map((pr) => (pr.id === e.id ? { ...pr, oneWay: evt.target.checked } : pr))
                              )
                            }
                            className="w-4 h-4 rounded bg-slate-800 border-slate-700 text-blue-600 focus:ring-blue-500 cursor-pointer"
                          />
                          <span className="text-xs text-slate-400">One Way Road</span>
                        </div>
                        <div className="mt-2 flex justify-end">
                          <button
                            onClick={() => handleFlipEdge(e.id)}
                            className="px-3 py-1.5 bg-slate-700 hover:bg-slate-600 text-white rounded text-xs font-semibold flex items-center justify-center gap-2 transition-colors"
                          >
                            Flip Direction
                          </button>
                        </div>
                      </div>
                    </div>
                  ))
                )}
              </div>
            )}
          </section>
        </aside>
      </div>
    </div>
  );
}
