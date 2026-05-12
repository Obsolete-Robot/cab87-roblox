import type { BuildingFillSettings } from './types';

export const COLORS = ['#ef4444', '#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899'];
export const ROAD_NETWORK_SCHEMA = 'cab87-road-network';
export const ROAD_NETWORK_VERSION = 2;

export const DEFAULTS = {
  roadWidth: 60,
  sidewalkWidth: 24,
  crosswalkLength: 14,
  laneWidth: 30,
  softSelectionRadius: 200,
  chamferAngle: 70,
  meshResolution: 20,
  buildingBaseZ: 4,
  buildingHeight: 80,
  buildingColor: '#64748b',
  buildingMaterial: 'Concrete',
  buildingFillMinWidth: 48,
  buildingFillMaxWidth: 120,
  buildingFillMinHeight: 50,
  buildingFillMaxHeight: 160,
};

export function sanitizeMeshResolution(value: unknown): number {
  const parsed = typeof value === 'number' ? value : parseInt(String(value), 10);
  if (!Number.isFinite(parsed)) return DEFAULTS.meshResolution;
  return Math.max(5, Math.min(100, Math.round(parsed)));
}

function sanitizePositiveNumber(value: unknown, fallback: number): number {
  const parsed = typeof value === 'number' ? value : parseFloat(String(value));
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.max(1, Math.round(parsed));
}

function sanitizeRange(minValue: unknown, maxValue: unknown, fallbackMin: number, fallbackMax: number) {
  const min = sanitizePositiveNumber(minValue, fallbackMin);
  const max = sanitizePositiveNumber(maxValue, fallbackMax);
  return min <= max ? { min, max } : { min: max, max: min };
}

export function sanitizeBuildingFillSettings(value?: Partial<BuildingFillSettings> | null): BuildingFillSettings {
  const width = sanitizeRange(
    value?.minWidth,
    value?.maxWidth,
    DEFAULTS.buildingFillMinWidth,
    DEFAULTS.buildingFillMaxWidth
  );
  const height = sanitizeRange(
    value?.minHeight,
    value?.maxHeight,
    DEFAULTS.buildingFillMinHeight,
    DEFAULTS.buildingFillMaxHeight
  );

  return {
    minWidth: width.min,
    maxWidth: width.max,
    minHeight: height.min,
    maxHeight: height.max,
  };
}
