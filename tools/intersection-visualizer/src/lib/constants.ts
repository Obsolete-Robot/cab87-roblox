export const COLORS = ['#ef4444', '#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899'];
export const ROAD_NETWORK_SCHEMA = 'cab87-road-network';
export const ROAD_NETWORK_VERSION = 1;
export const DEFAULT_CHAMFER_ANGLE = 70;
export const DEFAULT_MESH_RESOLUTION = 20;

export function sanitizeMeshResolution(value: unknown): number {
  const parsed = typeof value === 'number' ? value : parseInt(String(value), 10);
  if (!Number.isFinite(parsed)) return DEFAULT_MESH_RESOLUTION;
  return Math.max(5, Math.min(100, Math.round(parsed)));
}
