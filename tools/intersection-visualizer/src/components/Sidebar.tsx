import React, { useState } from 'react';
import { X, ChevronDown, ChevronRight, Copy, ClipboardPaste, Trash2 } from 'lucide-react';
import { Node, Edge } from '../lib/types';
import { sanitizeLaneWidth, sanitizeMeshResolution } from '../lib/constants';

interface SidebarProps {
  isSidebarOpen: boolean;
  setIsSidebarOpen: (v: boolean) => void;
  addNode: () => void;
  addEdge: () => void;
  softSelectionEnabled: boolean;
  setSoftSelectionEnabled: (v: boolean) => void;
  softSelectionRadius: number;
  setSoftSelectionRadius: (v: number) => void;
  chamferAngle: number;
  setChamferAngle: (v: number) => void;
  meshResolution: number;
  setMeshResolution: (v: number) => void;
  laneWidth: number;
  setLaneWidth: (v: number) => void;
  nodes: Node[];
  setNodes: React.Dispatch<React.SetStateAction<Node[]>>;
  edges: Edge[];
  setEdges: React.Dispatch<React.SetStateAction<Edge[]>>;
  selectedNodes: string[];
  setSelectedNodes: React.Dispatch<React.SetStateAction<string[]>>;
  selectedEdges: string[];
  setSelectedEdges: React.Dispatch<React.SetStateAction<string[]>>;
}

export default function Sidebar({
  isSidebarOpen,
  setIsSidebarOpen,
  addNode,
  addEdge,
  softSelectionEnabled,
  setSoftSelectionEnabled,
  softSelectionRadius,
  setSoftSelectionRadius,
  chamferAngle,
  setChamferAngle,
  meshResolution,
  setMeshResolution,
  laneWidth,
  setLaneWidth,
  nodes,
  setNodes,
  edges,
  setEdges,
  selectedNodes,
  setSelectedNodes,
  selectedEdges,
  setSelectedEdges,
}: SidebarProps) {
  const [collapsedSections, setCollapsedSections] = useState<Record<string, boolean>>({});
  const toggleSection = (section: string) => setCollapsedSections(prev => ({ ...prev, [section]: !prev[section] }));

  const [editingEdgeName, setEditingEdgeName] = useState<string | null>(null);
  const [editingNameValue, setEditingNameValue] = useState("");
  const [copiedEdgeSettings, setCopiedEdgeSettings] = useState<Partial<Edge> | null>(null);

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
          onClick={() => toggleSection('soft_selection')}
        >
          <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest">Soft Selection</h3>
          {collapsedSections['soft_selection'] ? <ChevronRight className="w-4 h-4 text-slate-500" /> : <ChevronDown className="w-4 h-4 text-slate-500" />}
        </div>
        {!collapsedSections['soft_selection'] && (
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
                  onChange={(e) => setLaneWidth(sanitizeLaneWidth(e.target.value))}
                  className="flex-grow min-w-0"
                />
                <input
                  type="number"
                  min="10"
                  max="100"
                  value={laneWidth}
                  onChange={(e) => setLaneWidth(sanitizeLaneWidth(e.target.value))}
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
          onClick={() => toggleSection('selected_items')}
        >
          <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest">Selected Item</h3>
          {collapsedSections['selected_items'] ? <ChevronRight className="w-4 h-4 text-slate-500" /> : <ChevronDown className="w-4 h-4 text-slate-500" />}
        </div>
        {!collapsedSections['selected_items'] && (
          <div className="space-y-3 overflow-y-auto pb-4">
            {selectedNodes.length === 0 && selectedEdges.length === 0 ? (
              <div className="text-sm text-slate-500 text-center py-4 px-4 bg-slate-800/10 rounded-lg border border-slate-800/50 border-dashed">
                Select a junction or road in the viewport.
              </div>
            ) : (
              <>
                {nodes.filter(n => selectedNodes.includes(n.id)).map((n) => (
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
                    <div className="mt-2 pointer-events-auto">
                      <div className="flex justify-between text-xs text-slate-400 mb-1">
                        <span>Junction Smoothing</span>
                        <span>{n.transitionSmoothness ?? 0}px</span>
                      </div>
                      <input
                        type="range"
                        min="0"
                        max="200"
                        step="5"
                        value={n.transitionSmoothness ?? 0}
                        onChange={(evt) =>
                          setNodes((prev) =>
                            prev.map((pn) => (pn.id === n.id ? { ...pn, transitionSmoothness: parseInt(evt.target.value) } : pn))
                          )
                        }
                        className="w-full accent-blue-500 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer"
                      />
                    </div>
                  </div>
                ))}

                {edges.filter(e => selectedEdges.includes(e.id)).map((e, idx) => (
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
                          <span>{e.sidewalkLeft ?? e.sidewalk ?? 24}px</span>
                        </div>
                        <input
                          type="range"
                          min="0"
                          max="100"
                          step="2"
                          value={e.sidewalkLeft ?? e.sidewalk ?? 24}
                          onChange={(evt) =>
                            setEdges((prev) =>
                              prev.map((pr) => (pr.id === e.id ? { ...pr, sidewalkLeft: parseInt(evt.target.value) } : pr))
                            )
                          }
                          className="w-full accent-emerald-500 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer mb-3"
                        />
                        <div className="flex justify-between text-xs text-slate-400 mb-1">
                          <span>Sidewalk (Right)</span>
                          <span>{e.sidewalkRight ?? e.sidewalk ?? 24}px</span>
                        </div>
                        <input
                          type="range"
                          min="0"
                          max="100"
                          step="2"
                          value={e.sidewalkRight ?? e.sidewalk ?? 24}
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
                ))}
              </>
            )}
          </div>
        )}
      </section>
    </aside>
  );
}
