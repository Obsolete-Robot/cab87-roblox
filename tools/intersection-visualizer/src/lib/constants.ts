export const COLORS = ['#ef4444', '#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899'];
export const ROAD_NETWORK_SCHEMA = 'cab87-road-network';
export const ROAD_NETWORK_VERSION = 1;

export const DEFAULTS = {
  roadWidth: 60,
  sidewalkWidth: 24,
  crosswalkLength: 14,
  laneWidth: 30,
  softSelectionRadius: 200,
  chamferAngle: 70,
  meshResolution: 20,
};

export function sanitizeMeshResolution(value: unknown): number {
  const parsed = typeof value === 'number' ? value : parseInt(String(value), 10);
  if (!Number.isFinite(parsed)) return DEFAULTS.meshResolution;
  return Math.max(5, Math.min(100, Math.round(parsed)));
}
