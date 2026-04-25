export type Point = {
  x: number;
  y: number;
};

export type Road = {
  id: string;
  end: Point;
  width: number;
  color: string;
};

export type Triangle = [Point, Point, Point];

export type JunctionData = {
  center: Point;
  roads: Road[];
  sortedRoads: (Road & { angle: number })[];
  corners: Point[][];
};

export type MeshData = {
  vertices: Point[];
  triangles: Triangle[];
  hubPolygon: Point[];
  roadPolygons: { id: string; polygon: Point[] }[];
};
