declare module 'cdt2d' {
  type Point2D = [number, number];
  type Edge = [number, number];
  type Triangle = [number, number, number];

  export default function cdt2d(
    points: Point2D[],
    edges?: Edge[],
    options?: {
      delaunay?: boolean;
      interior?: boolean;
      exterior?: boolean;
      infinity?: boolean;
    },
  ): Triangle[];
}
