import readiness from "../../shared/readiness.json";

/** Shared Home readiness chrome — lockstep with `shared/readiness.json`. */
export const READINESS = readiness;

export type ReadinessBandId = "peak" | "good" | "fair" | "low";

export function readinessBand(score: number): (typeof READINESS.bands)[number] {
  const clamped = Math.max(0, Math.min(100, score));
  return (
    READINESS.bands.find((band) => clamped >= band.min) ??
    READINESS.bands[READINESS.bands.length - 1]
  );
}

export function readinessHex(score: number): string {
  return `#${readinessBand(score).hex}`;
}

export function readinessLabel(score: number): string {
  return readinessBand(score).label;
}

export function isAlmostThere(percent: number, remaining: number): boolean {
  const clamped = Math.max(0, Math.min(100, percent));
  return (
    remaining === READINESS.motivation.closingRemaining ||
    (clamped >= READINESS.motivation.almostTherePercent && clamped < 100)
  );
}

export function tileAlmostThere(progress: number): boolean {
  return progress >= READINESS.motivation.almostThereFloor && progress < 1;
}

export const PLATE_HEX = `#${READINESS.hud.plateHex}`;
export const MISS_HEX = `#${READINESS.motivation.missHex}`;
