import React, { useRef, useState } from 'react';
import { Menu, X, Layers, Upload, Download, Box, ChevronDown, FileArchive, FileJson, FilePlus2 } from 'lucide-react';
import type { RobloxRoadMeshExportMode } from '../lib/meshExport';

interface HeaderProps {
  isSidebarOpen: boolean;
  setIsSidebarOpen: (v: boolean) => void;
  handleNewProject: () => void;
  handleImport: (e: React.ChangeEvent<HTMLInputElement>) => void;
  handleExport: () => void;
  handleExportObj: () => void;
  handleExportGlb: () => void;
  handleExportRoblox: (mode?: RobloxRoadMeshExportMode) => void;
  is3DMode: boolean;
  setIs3DMode: (v: boolean) => void;
  showMesh: boolean;
  setShowMesh: (v: boolean) => void;
}

export default function Header({
  isSidebarOpen,
  setIsSidebarOpen,
  handleNewProject,
  handleImport,
  handleExport,
  handleExportObj,
  handleExportGlb,
  handleExportRoblox,
  is3DMode,
  setIs3DMode,
  showMesh,
  setShowMesh
}: HeaderProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isRobloxMenuOpen, setIsRobloxMenuOpen] = useState(false);

  const chooseRobloxExport = (mode: RobloxRoadMeshExportMode) => {
    setIsRobloxMenuOpen(false);
    handleExportRoblox(mode);
  };

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
          onClick={handleNewProject}
          className="p-2 lg:px-3 lg:py-1.5 border rounded text-sm font-semibold flex items-center gap-2 transition-colors border-slate-700 hover:bg-slate-800 text-slate-300"
          title="New road graph"
        >
          <FilePlus2 className="w-4 h-4" />
          <span className="hidden xl:inline">New</span>
        </button>
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
        <div
          className="relative flex"
          onBlur={(event) => {
            const nextTarget = event.relatedTarget;
            if (!(nextTarget instanceof Node) || !event.currentTarget.contains(nextTarget)) {
              setIsRobloxMenuOpen(false);
            }
          }}
        >
          <button
            onClick={() => handleExportRoblox('zip')}
            className="p-2 lg:px-3 lg:py-1.5 border rounded-l rounded-r-none text-sm font-semibold flex items-center gap-2 transition-colors border-slate-700 hover:bg-slate-800 text-slate-300"
            title="Export Roblox ZIP Package"
          >
            <FileArchive className="w-4 h-4" />
            <span className="hidden lg:inline">Roblox</span>
          </button>
          <button
            onClick={() => setIsRobloxMenuOpen((isOpen) => !isOpen)}
            className="p-2 border rounded-r rounded-l-none text-sm font-semibold flex items-center transition-colors border-slate-700 border-l-0 hover:bg-slate-800 text-slate-300"
            title="Roblox Export Options"
            aria-haspopup="menu"
            aria-expanded={isRobloxMenuOpen}
          >
            <ChevronDown className="w-4 h-4" />
          </button>
          {isRobloxMenuOpen && (
            <div
              className="absolute right-0 top-full mt-2 w-56 rounded border border-slate-700 bg-slate-900 shadow-xl shadow-black/30 py-1 z-40"
              role="menu"
            >
              <button
                onClick={() => chooseRobloxExport('zip')}
                className="w-full px-3 py-2 text-left text-sm font-medium text-slate-200 hover:bg-slate-800 flex items-center gap-2"
                role="menuitem"
              >
                <FileArchive className="w-4 h-4 text-slate-400" />
                ZIP package
              </button>
              <button
                onClick={() => chooseRobloxExport('glb')}
                className="w-full px-3 py-2 text-left text-sm font-medium text-slate-200 hover:bg-slate-800 flex items-center gap-2"
                role="menuitem"
              >
                <Box className="w-4 h-4 text-slate-400" />
                Chunked GLB
              </button>
              <button
                onClick={() => chooseRobloxExport('manifest')}
                className="w-full px-3 py-2 text-left text-sm font-medium text-slate-200 hover:bg-slate-800 flex items-center gap-2"
                role="menuitem"
              >
                <FileJson className="w-4 h-4 text-slate-400" />
                Manifest JSON
              </button>
              <button
                onClick={() => chooseRobloxExport('files')}
                className="w-full px-3 py-2 text-left text-sm font-medium text-slate-200 hover:bg-slate-800 flex items-center gap-2"
                role="menuitem"
              >
                <Download className="w-4 h-4 text-slate-400" />
                Separate files
              </button>
            </div>
          )}
        </div>
        <div className="w-px h-6 bg-slate-700 hidden sm:block mx-1"></div>
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
