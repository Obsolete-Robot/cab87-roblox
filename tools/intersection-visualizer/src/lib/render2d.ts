import { Point, Node, Edge } from './types';
import { getExtendedEdgeControlPoints } from './network';
import { buildNetworkMesh } from './meshing';

export const drawNetwork2D = (
  ctx: CanvasRenderingContext2D,
  size: { w: number; h: number },
  nodes: Node[],
  edges: Edge[],
  selectedEdges: string[],
  selectedNodes: string[],
  selectedNode: string | null,
  showMesh: boolean,
  showControlPoints: boolean,
  isConnectMode: boolean,
  isMergeMode: boolean,
  chamferAngle: number,
  meshResolution: number,
  laneWidth: number,
  polygonFills: any[],
  softSelectionEnabled: boolean,
  softSelectionRadius: number,
  draggingPoint: Point | null,
  selectedPoints: any[],
  selectedPolygonFillId: string | null,
  view?: { x: number; y: number; zoom: number },
  snapGridSize: number = 10
) => {
  // Clear the canvas outside of the view transform or just fill the entire view area.
  // Wait, ctx is already transformed. To clear the whole canvas properly:
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0); // reset transform to clear screen
  ctx.clearRect(0, 0, size.w * (window.devicePixelRatio || 1), size.h * (window.devicePixelRatio || 1));
  ctx.restore();

  if (view) {
    const gridSize = Math.max(snapGridSize * 10, 100);
    const cellGridSize = snapGridSize;
    const invZoom = 1 / view.zoom;

    const minX = -view.x * invZoom;
    const maxX = (size.w - view.x) * invZoom;
    const minY = -view.y * invZoom;
    const maxY = (size.h - view.y) * invZoom;

    // Draw small grid cells
    ctx.lineWidth = 2 * invZoom;
    ctx.strokeStyle = '#262626';
    ctx.beginPath();
    let startX = Math.floor(minX / cellGridSize) * cellGridSize;
    for (let x = startX; x <= maxX; x += cellGridSize) {
      ctx.moveTo(x, minY);
      ctx.lineTo(x, maxY);
    }
    let startY = Math.floor(minY / cellGridSize) * cellGridSize;
    for (let y = startY; y <= maxY; y += cellGridSize) {
      ctx.moveTo(minX, y);
      ctx.lineTo(maxX, y);
    }
    ctx.stroke();

    // Draw main grid sections
    ctx.lineWidth = 2 * invZoom;
    ctx.strokeStyle = '#404040';
    ctx.beginPath();
    startX = Math.floor(minX / gridSize) * gridSize;
    for (let x = startX; x <= maxX; x += gridSize) {
      ctx.moveTo(x, minY);
      ctx.lineTo(x, maxY);
    }
    startY = Math.floor(minY / gridSize) * gridSize;
    for (let y = startY; y <= maxY; y += gridSize) {
      ctx.moveTo(minX, y);
      ctx.lineTo(maxX, y);
    }
    ctx.stroke();
  }

  if (nodes.length === 0) return;

  const mesh = buildNetworkMesh(nodes, edges, chamferAngle, meshResolution, laneWidth, polygonFills);

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

  if (showMesh && mesh.polygonTriangles) {
    mesh.polygonTriangles.forEach(pg => {
      ctx.beginPath();
      pg.triangles.forEach(tri => {
        ctx.moveTo(tri[0].x, tri[0].y);
        ctx.lineTo(tri[1].x, tri[1].y);
        ctx.lineTo(tri[2].x, tri[2].y);
        ctx.lineTo(tri[0].x, tri[0].y);
      });
      ctx.fillStyle = pg.color + '44'; // 44 is partial transparency
      ctx.fill();
      ctx.strokeStyle = pg.color;
      ctx.lineWidth = 1;
      ctx.stroke();
    });
  }

  if (!showMesh) {
    const getAvgZ = (paths: Point[]) => {
      let sum = 0;
      if (!paths || paths.length === 0) return 4;
      for (const p of paths) sum += (p.z ?? 4);
      return sum / paths.length;
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

    if (mesh.polygonTriangles) {
        mesh.polygonTriangles.forEach((pg, i) => {
            if (pg.triangles.length === 0) return;
            const fillDef = polygonFills[i];

            let cx = 0, cy = 0, count = 0;
            if (fillDef) {
                fillDef.points.forEach((nid: string) => {
                    const n = nodes.find(n => n.id === nid);
                    if (n) { cx += n.point.x; cy += n.point.y; count++; }
                });
                if (count > 0) { cx /= count; cy /= count; }
            }

            renderables.push({
                z: -10, // Always below everything
                priority: -100,
                paths: [],
                draw: () => {
                    ctx.save();
                    ctx.shadowColor = 'transparent';
                    ctx.shadowBlur = 0;
                    ctx.fillStyle = pg.color + '66'; // semi-transparent
                    ctx.strokeStyle = pg.color;
                    ctx.lineWidth = 0.5;
                    ctx.beginPath();
                    pg.triangles.forEach(tri => {
                        ctx.moveTo(tri[0].x, tri[0].y);
                        ctx.lineTo(tri[1].x, tri[1].y);
                        ctx.lineTo(tri[2].x, tri[2].y);
                        ctx.lineTo(tri[0].x, tri[0].y);
                    });
                    ctx.fill();
                    ctx.stroke();
                    ctx.restore();
                }
            });

            if (count > 0 && fillDef) {
                renderables.push({
                    z: 9999,
                    priority: 100, // On top of everything
                    paths: [],
                    draw: () => {
                        ctx.save();
                        ctx.beginPath();
                        ctx.arc(cx, cy, 6, 0, Math.PI * 2);
                        ctx.fillStyle = selectedPolygonFillId === fillDef.id ? '#ffffff' : pg.color;
                        ctx.strokeStyle = '#000000';
                        ctx.lineWidth = 2;
                        ctx.fill();
                        ctx.stroke();

                        if (selectedPolygonFillId === fillDef.id) {
                            ctx.beginPath();
                            ctx.arc(cx, cy, 10, 0, Math.PI * 2);
                            ctx.strokeStyle = '#3b82f6';
                            ctx.lineWidth = 2;
                            ctx.setLineDash([4, 4]);
                            ctx.stroke();
                        }
                        ctx.restore();
                    }
                });
            }
        });
    }

    mesh.roadPolygons.forEach(rp => {
      if (rp.ignoreMeshing) return;
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

    mesh.sidewalkPolygons.forEach(sidewalk => {
      const poly = sidewalk.polygon;
      if (sidewalk.ignoreMeshing) return;
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
      if (rp.ignoreMeshing) return;
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
       if (cw.ignoreMeshing) return;
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

    mesh.dashedLines.forEach(dashedLine => {
        const cl = dashedLine.points;
        if (dashedLine.ignoreMeshing) return;
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

    mesh.solidYellowLines.forEach(solidLine => {
        const cl = solidLine.points;
        if (solidLine.ignoreMeshing) return;
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
        if (arrow.ignoreMeshing) return;
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
      const isActive = selectedNode === n.id;
      const isSelected = selectedNodes.includes(n.id) || isActive;

      ctx.beginPath();
      ctx.arc(n.point.x, n.point.y, 8, 0, Math.PI * 2);
      ctx.fillStyle = isActive ? (n.point.linked ? '#059669' : '#ef4444') : isSelected ? (n.point.linked ? '#6ee7b7' : '#fca5a5') : (n.point.linked ? '#10b981' : '#60a5fa');
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = '#fff';
      ctx.stroke();

      if (isSelected) {
        ctx.beginPath();
        ctx.arc(n.point.x, n.point.y, 16, 0, Math.PI * 2);
        if (isActive && isConnectMode) {
            ctx.strokeStyle = 'rgba(52, 211, 153, 0.8)';
        } else if (isActive && isMergeMode) {
            ctx.strokeStyle = 'rgba(239, 68, 68, 0.8)';
        } else {
            ctx.strokeStyle = isActive ? 'rgba(239, 68, 68, 0.4)' : 'rgba(252, 165, 165, 0.4)';
        }
        ctx.lineWidth = (isActive && (isConnectMode || isMergeMode)) ? 3 : 2;
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
              ctx.lineWidth = 3;
              for (let i = 0; i + 3 < cubicPts.length; i += 3) {
                  ctx.moveTo(cubicPts[i].x, cubicPts[i].y);
                  ctx.lineTo(cubicPts[i+1].x, cubicPts[i+1].y);
                  ctx.moveTo(cubicPts[i+2].x, cubicPts[i+2].y);
                  ctx.lineTo(cubicPts[i+3].x, cubicPts[i+3].y);
              }
              ctx.stroke();

              ctx.fillStyle = '#94a3b8'; // light slate for automatic
              for (let i = 3; i < cubicPts.length - 1; i += 3) {
                  if (i === 3 || i === cubicPts.length - 4) {
                      ctx.beginPath();
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
          const isSelectedPoint = selectedPoints?.some(p => p.edgeId === e.id && p.pointIndex === j) || false;
          ctx.arc(pt.x, pt.y, isAnchor ? 10 : 8, 0, Math.PI * 2);
          ctx.fillStyle = selectedEdges.includes(e.id) ? (isSelectedPoint ? '#ef4444' : (isAnchor ? (pt.linked ? '#10b981' : '#fbbf24') : (pt.linear ? '#0ea5e9' : '#ffffff'))) : '#64748b';
          ctx.fill();
          ctx.stroke();
      });
  });
};
