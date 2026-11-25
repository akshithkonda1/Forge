/** Procedural Forge fire. Welcome / splash only — not the ARIA ring-field.
 *  Lockstep with `ForgeFireGeometry` on iOS.
 */
export const FORGE_FIRE = {
  kind: "rage-fire",
  tickHz: 12,
  rage: { tongueCount: 28, sparkCount: 24, heightScale: 1, coreHeat: 0.94 },
  ember: { tongueCount: 8, sparkCount: 6, heightScale: 0.34, coreHeat: 0.28 },
} as const;

/** First frame always paints (`lastPaintMs < 0`). Later frames cap near 12 Hz. */
export function forgeFirePaintDue(nowMs: number, lastPaintMs: number): boolean {
  if (lastPaintMs < 0) return true;
  return nowMs - lastPaintMs >= 1000 / FORGE_FIRE.tickHz;
}

export type ForgeFireIntensity = "ember" | "rage";
export type ForgeFireOrigin = "floor" | "hearth";

export type ForgeFireTongue = {
  baseX: number;
  baseY: number;
  tipX: number;
  tipY: number;
  width: number;
  heat: number;
  waver: number;
};

function hash01(seed: number): number {
  const n = Math.sin(seed * 12.9898) * 43758.5453;
  return n - Math.floor(n);
}

export function fireSpec(intensity: ForgeFireIntensity) {
  return intensity === "rage" ? FORGE_FIRE.rage : FORGE_FIRE.ember;
}

export function fireTongue(
  index: number,
  count: number,
  time: number,
  intensity: ForgeFireIntensity,
  origin: ForgeFireOrigin,
  reduceMotion: boolean
): ForgeFireTongue {
  const spec = fireSpec(intensity);
  const i = Math.max(0, Math.min(Math.max(count - 1, 0), index));
  const seed = i * 17.13;
  const t = reduceMotion ? 0.18 : time;
  const n = Math.max(count, 1);
  const lane = i / (n - 1 === 0 ? 1 : n - 1);
  const flicker = reduceMotion
    ? 0.78
    : 0.62 + 0.38 * (0.5 + 0.5 * Math.sin(t * (2.4 + (i % 5) * 0.35) + seed));
  const rise = (0.22 + 0.7 * hash01(seed + 2.1)) * spec.heightScale * flicker;

  if (origin === "hearth") {
    const angle = lane * Math.PI * 1.15 + Math.PI * 0.42;
    const reach = (0.22 + 0.38 * hash01(seed)) * spec.heightScale * flicker;
    const cx = 0.5 + (reduceMotion ? 0 : 0.02 * Math.sin(t * 1.4 + seed));
    const cy = 0.62;
    const waver = reduceMotion ? 0 : 0.04 * Math.sin(t * 3.6 + seed);
    return {
      baseX: cx + Math.cos(angle) * 0.08,
      baseY: cy,
      tipX: cx + Math.cos(angle) * reach + waver,
      tipY: cy - Math.sin(angle * 0.35 + 0.9) * reach * 1.15,
      width: (0.04 + 0.03 * hash01(seed + 8)) * spec.heightScale,
      heat: spec.coreHeat * (0.7 + 0.3 * flicker),
      waver,
    };
  }

  const baseX = 0.06 + lane * 0.88 + (reduceMotion ? 0 : 0.03 * Math.sin(t * 1.7 + seed));
  const baseY = 0.94 + 0.04 * hash01(seed + 11);
  const waver = reduceMotion ? 0 : 0.055 * Math.sin(t * 3.2 + seed);
  return {
    baseX,
    baseY,
    tipX: baseX + waver * 1.55,
    tipY: baseY - rise,
    width: (0.034 + 0.055 * hash01(seed + 4)) * (0.75 + 0.55 * spec.heightScale),
    heat: spec.coreHeat * (0.72 + 0.28 * flicker),
    waver,
  };
}
