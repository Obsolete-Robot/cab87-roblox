export type Point = {
  x: number;
  y: number;
  z?: number;
  linked?: boolean;
  linear?: boolean;
  curveIndex?: number;
  t?: number;
};

export type Triangle = [Point, Point, Point];

export type Node = {
  id: string;
  point: Point;
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
  centerLines: Point[][];
};
