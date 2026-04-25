import React, { useState, useEffect, useRef, useMemo } from 'react';
import { Settings2, Trash2, Plus, Bug, Menu, X, Layers } from 'lucide-react';
import { Point, Road } from './lib/types';
import { buildJunction } from './lib/junction';
import { generateJunctionMesh } from './lib/mesher';
import { getDir } from './lib/math';

const COLORS = ['#ef4444', '#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899'];

export default function App() {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [size, setSize] = useState({ w: 800, h: 600 });

  const [center, setCenter] = useState<Point>({ x: 400, y: 300 });
  const [roads, setRoads] = useState<Road[]>([
    { id: '1', end: { x: 400, y: 100 }, width: 80, color: '#ef4444' },
    { id: '2', end: { x: 650, y: 300 }, width: 60, color: '#3b82f6' },
    { id: '3', end: { x: 200, y: 400 }, width: 60, color: '#10b981' },
  ]);

  const [selectedRoad, setSelectedRoad] = useState<string | null>(null);
  const [showMesh, setShowMesh] = useState(false);
  const [viewOffset, setViewOffset] = useState<Point>({ x: 0, y: 0 });
  const [dragging, setDragging] = useState<{ type: 'center' | 'road'; id?: string } | null>(null);
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  
  // Track active pointer positions for multi-touch (panning)
  const pointersRef = useRef<Map<number, Point>>(new Map());
  const lastPanMidpointRef = useRef<Point | null>(null);
  const lastCreatedRoadIdRef = useRef<string | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;
    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        setSize({ w: entry.contentRect.width, h: entry.contentRect.height });
      }
    });
    observer.observe(containerRef.current);
    
    // Set initial center based on container
    const rect = containerRef.current.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0) {
      setCenter({ x: rect.width / 2, y: rect.height / 2 });
    }

    return () => observer.disconnect();
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
    ctx.translate(viewOffset.x, viewOffset.y);
    draw(ctx, size, center, roads, selectedRoad, showMesh);
    ctx.restore();
  }, [size, center, roads, selectedRoad, showMesh, viewOffset]);

  const draw = (ctx: CanvasRenderingContext2D, size: { w: number; h: number }, center: Point, roads: Road[], selectedRoad: string | null, showMesh: boolean) => {
    ctx.clearRect(0, 0, size.w, size.h);

    if (roads.length === 0) return;

    // Use refactored library
    const junction = buildJunction(center, roads);
    const mesh = generateJunctionMesh(junction);

    const { sortedRoads } = junction;
    const { vertices, triangles } = mesh;
    const N = sortedRoads.length;

    // 1. Draw Mesh (Triangle View) - Draw this first so it can be potentially overlaid or shown exclusively
    if (showMesh) {
      triangles.forEach((tri, idx) => {
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

    // 2. Standard rendering (Hide if mesh is shown to see purely mesh)
    if (!showMesh) {

      // Draw main polygon (Silhouette)
      if (vertices.length > 0) {
        ctx.beginPath();
        // Since `vertices` is a perfect ordered polygon, we just string it together
        ctx.moveTo(vertices[0].x, vertices[0].y);
        for (let i = 1; i < vertices.length; i++) {
          ctx.lineTo(vertices[i].x, vertices[i].y);
        }
        ctx.closePath();

        // Shadow for depth
        ctx.shadowColor = 'rgba(0,0,0,0.5)';
        ctx.shadowBlur = 15;
        ctx.shadowOffsetY = 4;
        
        ctx.fillStyle = '#1e293b'; // slate-800
        ctx.fill();
        
        ctx.shadowColor = 'transparent'; // reset

        // Draw boundaries (Outer strokes for corners and side roads only, NOT ends)
        ctx.lineJoin = 'round';
        ctx.lineWidth = 12;
        ctx.strokeStyle = '#60a5fa'; // blue-400 for intersection stroke based on design
        ctx.beginPath();
        
        sortedRoads.forEach((r, i) => {
          const prevIdx = (i - 1 + N) % N;
          const cornerPts = junction.corners[prevIdx];
          if (cornerPts.length > 0) {
            ctx.moveTo(cornerPts[0].x, cornerPts[0].y);
            for (let j = 1; j < cornerPts.length; j++) {
              ctx.lineTo(cornerPts[j].x, cornerPts[j].y);
            }
          }

          const rp = mesh.roadPolygons.find(p => p.id === r.id)!.polygon;
          ctx.moveTo(rp[0].x, rp[0].y); // bL
          ctx.lineTo(rp[3].x, rp[3].y); // eL
          
          ctx.moveTo(rp[1].x, rp[1].y); // bR
          ctx.lineTo(rp[2].x, rp[2].y); // eR
        });
        
        ctx.stroke();
      }

      // Draw crosswalks
      sortedRoads.forEach((r, i) => {
      const dir = getDir(center, r.end);
      const left = { x: dir.y, y: -dir.x };
      const right = { x: -dir.y, y: dir.x };
      const W = r.width / 2;

      const rp = mesh.roadPolygons.find(p => p.id === r.id)!.polygon;
      const bL = rp[0];
      const bR = rp[1];
      const bL_dist = (bL.x - center.x) * dir.x + (bL.y - center.y) * dir.y;
      const bR_dist = (bR.x - center.x) * dir.x + (bR.y - center.y) * dir.y;
      
      const cwDist = Math.max(bL_dist, bR_dist) + 5; // offset slightly
      const roadLen = Math.hypot(r.end.x - center.x, r.end.y - center.y);

      // Only draw if we have space on the road segment
      if (cwDist + 15 < roadLen) {
        const cwCenter = { x: center.x + dir.x * cwDist, y: center.y + dir.y * cwDist };
        const cwLeft = { x: cwCenter.x + left.x * W, y: cwCenter.y + left.y * W };
        const cwRight = { x: cwCenter.x + right.x * W, y: cwCenter.y + right.y * W };

        // Base asphalt band for crosswalk
        ctx.beginPath();
        ctx.moveTo(cwLeft.x, cwLeft.y);
        ctx.lineTo(cwRight.x, cwRight.y);
        ctx.lineWidth = 14;
        ctx.strokeStyle = '#1e293b'; 
        ctx.stroke();

        // Zebra stripes
        ctx.beginPath();
        ctx.moveTo(cwLeft.x, cwLeft.y);
        ctx.lineTo(cwRight.x, cwRight.y);
        ctx.lineWidth = 10;
        ctx.strokeStyle = '#e2e8f0';
        ctx.lineCap = 'butt';
        // Stroke dash patterns (width of dash, gap)
        ctx.setLineDash([4, 10]);
        ctx.stroke();
        ctx.setLineDash([]);
      }
    });

    // Road dashed lane markings
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.3)';
    ctx.lineWidth = 2;
    ctx.setLineDash([10, 15]);
    sortedRoads.forEach((r) => {
      ctx.beginPath();
      const dir = getDir(center, r.end);
      
      const rp = mesh.roadPolygons.find(p => p.id === r.id)!.polygon;
      const bL = rp[0];
      const bR = rp[1];
      const bL_dist = (bL.x - center.x) * dir.x + (bL.y - center.y) * dir.y;
      const bR_dist = (bR.x - center.x) * dir.x + (bR.y - center.y) * dir.y;
      
      const cwDist = Math.max(bL_dist, bR_dist) + 5;
      const startDist = cwDist + 5; 

      ctx.moveTo(center.x + dir.x * startDist, center.y + dir.y * startDist);
      ctx.lineTo(r.end.x, r.end.y);
      ctx.stroke();
    });
    }

    // Draw nodes
    // Center Node
    ctx.shadowColor = 'rgba(0,0,0,0.3)';
    ctx.shadowBlur = 8;
    ctx.shadowOffsetY = 2;
    ctx.beginPath();
    ctx.arc(center.x, center.y, 6, 0, Math.PI * 2);
    ctx.fillStyle = '#60a5fa'; // design blue
    ctx.fill();
    ctx.shadowColor = 'transparent';
    ctx.lineWidth = 2;
    ctx.strokeStyle = '#0f172a'; // slate-950
    ctx.stroke();

    // Road Nodes
    sortedRoads.forEach((r) => {
      ctx.shadowColor = 'rgba(0,0,0,0.3)';
      ctx.shadowBlur = 8;
      ctx.shadowOffsetY = 2;
      ctx.beginPath();
      ctx.arc(r.end.x, r.end.y, 6, 0, Math.PI * 2);
      ctx.fillStyle = '#60a5fa';
      ctx.fill();
      ctx.shadowColor = 'transparent';
      
      ctx.lineWidth = 2;
      ctx.strokeStyle = selectedRoad === r.id ? '#ffffff' : '#0f172a';
      ctx.stroke();

      if (selectedRoad === r.id) {
        ctx.beginPath();
        ctx.arc(r.end.x, r.end.y, 14, 0, Math.PI * 2);
        ctx.strokeStyle = 'rgba(96, 165, 250, 0.4)';
        ctx.lineWidth = 2;
        ctx.stroke();
      }
    });
  };

  const getMousePos = (e: React.PointerEvent) => {
    const rect = canvasRef.current!.getBoundingClientRect();
    return {
      x: e.clientX - rect.left - viewOffset.x,
      y: e.clientY - rect.top - viewOffset.y,
    };
  };

  const getRawMousePos = (e: React.PointerEvent) => {
    const rect = canvasRef.current!.getBoundingClientRect();
    return {
      x: e.clientX - rect.left,
      y: e.clientY - rect.top,
    };
  };

  const onPointerDown = (e: React.PointerEvent) => {
    const rawPos = getRawMousePos(e);
    pointersRef.current.set(e.pointerId, rawPos);
    
    if (pointersRef.current.size === 2) {
      // If we just created a road with the first finger and it turns out to be a pan, remove it
      if (lastCreatedRoadIdRef.current) {
        setRoads(prev => prev.filter(r => r.id !== lastCreatedRoadIdRef.current));
        lastCreatedRoadIdRef.current = null;
        setSelectedRoad(null);
      }
      
      // Initialize pan
      const pts = Array.from(pointersRef.current.values()) as Point[];
      lastPanMidpointRef.current = {
        x: (pts[0].x + pts[1].x) / 2,
        y: (pts[0].y + pts[1].y) / 2,
      };
      setDragging(null); // Cancel any single pointer dragging
      return;
    }

    if (pointersRef.current.size > 1) return;

    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    const pos = getMousePos(e);

    if (Math.hypot(pos.x - center.x, pos.y - center.y) < 25) {
      setDragging({ type: 'center' });
      return;
    }

    for (let i = roads.length - 1; i >= 0; i--) {
      if (Math.hypot(pos.x - roads[i].end.x, pos.y - roads[i].end.y) < 25) {
        setDragging({ type: 'road', id: roads[i].id });
        setSelectedRoad(roads[i].id);
        return;
      }
    }

    // Create new
    const id = Math.random().toString(36).substring(2, 9);
    const newRoad = {
      id,
      end: pos,
      width: 60,
      color: COLORS[roads.length % COLORS.length],
    };
    lastCreatedRoadIdRef.current = id;
    setRoads((prev) => [...prev, newRoad]);
    setDragging({ type: 'road', id });
    setSelectedRoad(id);
  };

  const onPointerMove = (e: React.PointerEvent) => {
    const rawPos = getRawMousePos(e);
    pointersRef.current.set(e.pointerId, rawPos);

    if (pointersRef.current.size === 2 && lastPanMidpointRef.current) {
      const pts = Array.from(pointersRef.current.values()) as Point[];
      const newMidpoint = {
        x: (pts[0].x + pts[1].x) / 2,
        y: (pts[0].y + pts[1].y) / 2,
      };
      
      const dx = newMidpoint.x - lastPanMidpointRef.current.x;
      const dy = newMidpoint.y - lastPanMidpointRef.current.y;
      
      setViewOffset(prev => ({ x: prev.x + dx, y: prev.y + dy }));
      lastPanMidpointRef.current = newMidpoint;
      return;
    }

    if (!dragging || pointersRef.current.size > 1) return;
    const pos = getMousePos(e);

    if (dragging.type === 'center') {
      setCenter(pos);
    } else if (dragging.type === 'road' && dragging.id) {
      setRoads((prev) => prev.map((r) => (r.id === dragging.id ? { ...r, end: pos } : r)));
    }
  };

  const onPointerUp = (e: React.PointerEvent) => {
    pointersRef.current.delete(e.pointerId);
    if (pointersRef.current.size < 2) {
      lastPanMidpointRef.current = null;
      lastCreatedRoadIdRef.current = null;
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

  const addRoadCenter = () => {
    const id = Math.random().toString(36).substring(2, 9);
    // Add road pointing roughly downwards
    setRoads((prev) => [
      ...prev,
      {
        id,
        end: { x: center.x, y: center.y + 150 },
        width: 60,
        color: COLORS[prev.length % COLORS.length],
      },
    ]);
    setSelectedRoad(id);
  };

  const removeRoad = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setRoads((prev) => prev.filter((r) => r.id !== id));
    if (selectedRoad === id) setSelectedRoad(null);
  };

  const debugConfig = () => {
    console.log("=== INTERSECTION DEBUG INFO ===");
    console.log("Center:", center);
    console.log("Roads:", JSON.stringify(roads, null, 2));
    console.log("===============================");
    alert("Debug info printed to console!");
  };

  return (
    <div className="w-full h-screen bg-slate-950 text-slate-300 font-sans flex flex-col overflow-hidden">
      {/* Header Navigation */}
      <header className="h-14 lg:h-16 border-b border-slate-800 bg-slate-900/50 flex items-center justify-between px-4 lg:px-6 shrink-0 relative z-30">
        <div className="flex items-center gap-2 lg:gap-3">
          <button 
            onClick={() => setIsSidebarOpen(!isSidebarOpen)}
            className="p-2 lg:hidden text-slate-400 hover:text-white"
          >
            {isSidebarOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
          <div className="w-8 h-8 bg-blue-600 rounded flex items-center justify-center shrink-0">
            <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 20l-5.447-2.724A2 2 0 013 15.488V5.512a2 2 0 011.553-1.952L9 2m0 18l6-3m-6 3V2m6 15l5.447 2.724A2 2 0 0021 17.912V7.912a2 2 0 00-1.553-1.952L15 2m0 15V2m0 0L9 5" />
            </svg>
          </div>
          <h1 className="text-base lg:text-lg font-semibold tracking-tight text-white line-clamp-1">
            InterSector <span className="hidden sm:inline text-slate-500 font-normal">v2.4</span>
          </h1>
        </div>

        <div className="flex items-center gap-2 lg:gap-4">
          <button
            onClick={() => setShowMesh(!showMesh)}
            className={`p-2 lg:px-3 lg:py-1.5 border rounded text-sm font-semibold flex items-center gap-2 transition-colors ${
              showMesh 
                ? 'bg-blue-600 border-blue-500 text-white hover:bg-blue-500' 
                : 'border-slate-700 hover:bg-slate-800 text-slate-300'
            }`}
            title="Toggle mesh visualization"
          >
            <Layers className="w-4 h-4" />
            <span className="hidden md:inline">{showMesh ? 'Hide Mesh' : 'Show Mesh'}</span>
          </button>
          
          <button
            onClick={addRoadCenter}
            className="px-3 py-1.5 lg:px-4 lg:py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded text-sm font-semibold flex items-center gap-2 shadow-lg shadow-blue-900/20"
          >
            <Plus className="w-4 h-4" />
            <span className="hidden sm:inline">Add Road</span>
          </button>
          
          <button
            onClick={debugConfig}
            className="p-2 lg:px-3 lg:py-1.5 border border-slate-700 hover:bg-slate-800 text-slate-300 rounded text-sm font-semibold flex items-center gap-2 transition-colors hidden md:flex"
            title="Print debug info to console"
          >
            <Bug className="w-4 h-4" />
            <span className="hidden lg:inline">Debug</span>
          </button>
        </div>
      </header>

      <div className="flex flex-grow overflow-hidden relative">
        {/* Main Canvas Viewport */}
        <main className="flex-grow relative bg-slate-900 overflow-hidden" ref={containerRef}>
          {/* Grid Overlay */}
          <div 
            className="absolute inset-0 opacity-10 pointer-events-none" 
            style={{ 
              backgroundImage: 'radial-gradient(#64748b 1px, transparent 1px)', 
              backgroundSize: '24px 24px',
              backgroundPosition: `${viewOffset.x}px ${viewOffset.y}px`
            }}
          ></div>
          
          <canvas
            ref={canvasRef}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerCancel}
            className="absolute inset-0 block outline-none cursor-crosshair touch-none"
          />

          {roads.length === 0 && (
            <div className="absolute inset-0 flex items-center justify-center pointer-events-none px-6 text-center">
              <div className="text-slate-500 text-sm font-medium tracking-wide">
                Touch or click anywhere to add a road arm.
              </div>
            </div>
          )}

          {/* Overlay Legend - Compact on mobile */}
          <div className="absolute bottom-10 lg:bottom-6 left-1/2 -translate-x-1/2 lg:left-6 lg:translate-x-0 p-2.5 lg:p-3 bg-slate-900/80 backdrop-blur border border-slate-700 rounded-md shadow-xl flex gap-4 lg:gap-6 text-[9px] lg:text-[11px] font-medium tracking-wider uppercase pointer-events-none whitespace-nowrap z-10">
            <div className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 lg:w-3 lg:h-3 bg-blue-400 rounded-full"></span> Node</div>
            <div className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 lg:w-3 lg:h-3 border border-blue-400 rounded-sm"></span> Hull</div>
            <div className="flex items-center gap-1.5"><span className="w-5 lg:w-6 h-2.5 lg:h-3 bg-slate-600 rounded-sm"></span> Road</div>
          </div>
        </main>

        {/* Sidebar Overlay for Mobile / Aside for Desktop */}
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
            <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-3 lg:mb-4 flex items-center gap-2">
              <Settings2 className="w-4 h-4" />
              Intersection Settings
            </h3>
            <p className="text-xs text-slate-400 leading-relaxed">
              Drag nodes to move. Touch the drawing surface to place new end nodes. Adjust road widths using the sliders below.
            </p>
          </section>

          <section className="flex-grow flex flex-col min-h-0">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest">Active Road Arms</h3>
              <span className="text-blue-400 text-xs font-semibold cursor-pointer hover:text-blue-300 transition-colors uppercase tracking-wide" onClick={addRoadCenter}>Add +</span>
            </div>
            
            <div className="space-y-3 overflow-y-auto flex-grow pb-4">
              {roads.length === 0 && (
                <div className="text-center py-10 text-slate-600 text-xs italic bg-slate-800/20 rounded-xl border border-dashed border-slate-700">
                  No active road segments.
                </div>
              )}
              {roads.map((r, idx) => (
                <div
                  key={r.id}
                  onClick={() => setSelectedRoad(r.id)}
                  className={`p-3 lg:p-4 rounded-xl border transition-all cursor-pointer ${
                    selectedRoad === r.id
                      ? 'bg-blue-900/10 border-blue-500/50 ring-1 ring-blue-500/20'
                      : 'bg-slate-800/40 border-slate-800 hover:border-slate-700'
                  }`}
                >
                  <div className="flex justify-between items-center mb-3">
                    <span className="text-sm font-bold text-slate-200">Road Arm {idx + 1}</span>
                    <button
                      onClick={(e) => removeRoad(r.id, e)}
                      className="text-slate-500 hover:text-red-400 p-2 lg:p-1 rounded-lg hover:bg-slate-800 transition-colors"
                      title="Remove road"
                    >
                      <Trash2 className="w-4 h-4 opacity-70" />
                    </button>
                  </div>
                  <div className="space-y-4">
                    <div>
                      <div className="flex justify-between items-center mb-2">
                         <span className="text-[10px] text-slate-500 uppercase font-bold tracking-wider">Lanes Width</span>
                         <span className="text-xs font-mono text-blue-400 bg-blue-900/20 px-1.5 py-0.5 rounded">{r.width}px</span>
                      </div>
                      <input
                        type="range"
                        min="20"
                        max="200"
                        step="5"
                        value={r.width}
                        onChange={(e) =>
                          setRoads((prev) =>
                            prev.map((pr) => (pr.id === r.id ? { ...pr, width: parseInt(e.target.value) } : pr))
                          )
                        }
                        className="w-full accent-blue-600 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer"
                      />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </section>

          {/* Summary Stats Footer */}
          <section className="pt-4 border-t border-slate-800 shrink-0">
            <div className="flex justify-between text-[10px] lg:text-[11px] mb-1.5">
              <span className="text-slate-500 uppercase font-bold tracking-wider">Total Segments</span>
              <span className="text-slate-300 font-mono font-bold">{roads.length}</span>
            </div>
            <div className="flex justify-between text-[10px] lg:text-[11px]">
              <span className="text-slate-500 uppercase font-bold tracking-wider">Renderer</span>
              <span className="text-blue-400 font-mono font-bold">CANVAS_2D</span>
            </div>
          </section>
        </aside>
      </div>

      {/* Bottom Status Bar - Smaller on mobile */}
      <footer className="h-6 lg:h-8 bg-blue-600 text-white text-[9px] lg:text-[10px] px-3 lg:px-4 flex items-center justify-between shrink-0 font-medium z-50">
        <div className="flex items-center gap-3 lg:gap-4 text-blue-100">
          <span className="font-mono hidden sm:inline">COORDINATES:</span>
          <span className="font-mono">X{Math.round(center.x)} Y{Math.round(center.y)}</span>
        </div>
        <div className="flex items-center gap-3 lg:gap-4 text-blue-100">
          <span className="opacity-90 hidden xs:inline">STATUS: LIVE_PREVIEW</span>
          <div className="w-1.5 h-1.5 lg:w-2 lg:h-2 bg-green-300 rounded-full animate-pulse shadow-[0_0_8px_rgba(134,239,172,0.6)]"></div>
        </div>
      </footer>
    </div>
  );
}

