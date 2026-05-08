import React, { useRef } from 'react';
import { Menu, X, Layers, Upload, Download, Box } from 'lucide-react';

interface HeaderProps {
  isSidebarOpen: boolean;
  setIsSidebarOpen: (v: boolean) => void;
  handleImport: (e: React.ChangeEvent<HTMLInputElement>) => void;
  handleExport: () => void;
  handleExportObj: () => void;
  handleExportGlb: () => void;
  showControlPoints: boolean;
  setShowControlPoints: (v: boolean) => void;
  is3DMode: boolean;
  setIs3DMode: (v: boolean) => void;
  showMesh: boolean;
  setShowMesh: (v: boolean) => void;
}

export default function Header({
  isSidebarOpen,
  setIsSidebarOpen,
  handleImport,
  handleExport,
  handleExportObj,
  handleExportGlb,
  showControlPoints,
  setShowControlPoints,
  is3DMode,
  setIs3DMode,
  showMesh,
  setShowMesh
}: HeaderProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);

  return (
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
        <button
          onClick={handleExportObj}
          className="p-2 lg:px-3 lg:py-1.5 border rounded text-sm font-semibold flex items-center gap-2 transition-colors border-slate-700 hover:bg-slate-800 text-slate-300"
          title="Export OBJ Mesh"
        >
          <Download className="w-4 h-4" />
          <span className="hidden lg:inline">OBJ</span>
        </button>
        <button
          onClick={handleExportGlb}
          className="p-2 lg:px-3 lg:py-1.5 border rounded text-sm font-semibold flex items-center gap-2 transition-colors border-slate-700 hover:bg-slate-800 text-slate-300"
          title="Export GLB Mesh"
        >
          <Download className="w-4 h-4" />
          <span className="hidden lg:inline">GLB</span>
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
  );
}
