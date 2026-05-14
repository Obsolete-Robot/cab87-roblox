export type PointSelection = { edgeId: string; pointIndex: number };

export type Point = {
  x: number;
  y: number;
  z?: number;
  u?: number;
  v?: number;
  linked?: boolean;
  linear?: boolean;
  curveIndex?: number;
  t?: number;
};

export type Triangle = [Point, Point, Point];

export type Node = {
  id: string;
  point: Point;
  transitionSmoothness?: number;
  ignoreMeshing?: boolean;
};

export type PolygonFill = {
  id: string;
  points: string[]; // Can be node IDs or just keep simple and map them later
  color: string;
};

export type BuildingPolygon = {
  id: string;
  name?: string;
  vertices: Point[];
  baseZ?: number;
  height: number;
  color: string;
  material?: string;
  fillSource?: BuildingFillSource;
};

export type BuildingFillSettings = {
  minWidth: number;
  maxWidth: number;
  minHeight: number;
  maxHeight: number;
};

export type BuildingFillSource = {
  groupId: string;
  mode: 'open' | 'closed';
  selectedNodes: string[];
  selectedEdges: string[];
  settings: BuildingFillSettings;
};

export type VisibilitySettings = {
  showNodeHandles: boolean;
  showNodeControlPoints: boolean;
  showPolyFillHandles: boolean;
  showBuildingHandles: boolean;
  showBuildingControlPoints: boolean;
};

export type BackgroundImageSettings = {
  filename: string;
  dataUrl: string;
  position: {
    x: number;
    y: number;
  };
  scale: number;
  opacity: number;
};

export type Edge = {
  id: string;
  source: string; // Node ID
  target: string | null; // Node ID or null for open end
  points: Point[]; // internal spline points
  width: number;
  sidewalk: number;
  sidewalkLeft?: number;
  sidewalkRight?: number;
  transitionSmoothness?: number;
  color: string;
  name?: string;
  oneWay?: boolean;
  ignoreMeshing?: boolean;
};

export type MeshData = {
  vertices: Point[];
  triangles: Triangle[];
  roadTriangles: Triangle[];
  hubTriangles: Triangle[];
  sidewalkTriangles: Triangle[];
  crosswalkTriangles: Triangle[];
  hubs: { id: string; polygon: Point[]; corners: { points: Point[]; sidewalkWidth: number }[]; outerPolygon: Point[]; outerCorners: Point[][]; ignoreMeshing?: boolean }[];
  roadPolygons: { id: string; polygon: Point[]; leftCurve: Point[]; rightCurve: Point[]; outerPolygon: Point[]; outerLeftCurve: Point[]; outerRightCurve: Point[]; sidewalkWidth: number; ignoreMeshing?: boolean }[];
  crosswalks: { edgeId: string; nodeId: string; polygon: Point[]; ignoreMeshing?: boolean }[];
  sidewalkPolygons: { polygon: Point[]; ignoreMeshing?: boolean }[];
  dashedLines: { points: Point[]; ignoreMeshing?: boolean }[];
  solidYellowLines: { points: Point[]; ignoreMeshing?: boolean }[];
  dashedLineTriangles: Triangle[];
  solidLineTriangles: Triangle[];
  laneArrows: { position: Point; dir: Point; ignoreMeshing?: boolean }[];
  polygonTriangles: { triangles: Triangle[], color: string }[];
  buildingMeshes: {
    id: string;
    name?: string;
    vertices: Point[];
    baseZ: number;
    height: number;
    color: string;
    material?: string;
    triangles: Triangle[];
    topTriangles: Triangle[];
    bottomTriangles: Triangle[];
    wallTriangles: Triangle[];
  }[];
  buildingTriangles: Triangle[];
};
