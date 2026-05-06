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
};

export type PolygonFill = {
  id: string;
  points: string[]; // Can be node IDs or just keep simple and map them later
  color: string;
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
};

export type MeshData = {
  vertices: Point[];
  triangles: Triangle[];
  roadTriangles: Triangle[];
  hubTriangles: Triangle[];
  sidewalkTriangles: Triangle[];
  crosswalkTriangles: Triangle[];
  hubs: { id: string; polygon: Point[]; corners: { points: Point[]; sidewalkWidth: number }[]; outerPolygon: Point[]; outerCorners: Point[][] }[];
  roadPolygons: { id: string; polygon: Point[]; leftCurve: Point[]; rightCurve: Point[]; outerPolygon: Point[]; outerLeftCurve: Point[]; outerRightCurve: Point[]; sidewalkWidth: number }[];
  crosswalks: { edgeId: string; nodeId: string; polygon: Point[] }[];
  sidewalkPolygons: Point[][];
  dashedLines: Point[][];
  solidYellowLines: Point[][];
  dashedLineTriangles: Triangle[];
  solidLineTriangles: Triangle[];
  laneArrows: { position: Point; dir: Point }[];
  polygonTriangles: { triangles: Triangle[], color: string }[];
};
