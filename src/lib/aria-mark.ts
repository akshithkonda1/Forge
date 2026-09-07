/** Shared ARIA ember — lockstep with `AriaSigilGeometry` / `shared/aria-mark.json`. */
export const ARIA_MARK = {
  assetName: "AriaLogo",
  webPath: "/aria-mark.png",
  sharedPath: "shared/brand/aria-mark.png",
  cropScale: 1.0,
  heroMinimumSize: 90,
  idleBreathHz: 0.42,
  speakingBreathHz: 0.68,
  stillPose: 1.72,
  maxGaze: 0.14,
  lobeCount: 4,
} as const;

export const ARIA_LOBES = [
  { angle: 0.62, dist: 0.26, r: 0.44, phase: 0.0 },
  { angle: 2.18, dist: 0.24, r: 0.41, phase: 1.1 },
  { angle: 3.92, dist: 0.28, r: 0.43, phase: 2.4 },
  { angle: 5.48, dist: 0.23, r: 0.4, phase: 3.6 },
] as const;

export type AriaMarkState = "idle" | "listening" | "processing" | "speaking";

export function clampGaze(value: number): number {
  return Math.min(ARIA_MARK.maxGaze, Math.max(-ARIA_MARK.maxGaze, value));
}

export function emberLobe(
  index: number,
  time: number,
  speaking: boolean,
  reduceMotion: boolean
): { x: number; y: number; r: number } {
  const lobe = ARIA_LOBES[index] ?? ARIA_LOBES[0];
  if (reduceMotion) {
    return {
      x: Math.cos(lobe.angle) * lobe.dist,
      y: Math.sin(lobe.angle) * lobe.dist,
      r: lobe.r,
    };
  }
  const hz = speaking ? ARIA_MARK.speakingBreathHz : ARIA_MARK.idleBreathHz;
  const wave = Math.sin(time * hz * Math.PI * 2 + lobe.phase);
  const dist = lobe.dist + 0.045 * wave;
  const ang = lobe.angle + 0.09 * Math.sin(time * 0.28 * Math.PI * 2 + lobe.phase);
  const r = lobe.r * (0.93 + 0.09 * (0.5 + 0.5 * Math.sin(time * hz * Math.PI * 2)));
  return { x: Math.cos(ang) * dist, y: Math.sin(ang) * dist, r };
}

export function emberCoreRadius(time: number, speaking: boolean, reduceMotion: boolean): number {
  if (reduceMotion) return 0.22;
  const hz = speaking ? ARIA_MARK.speakingBreathHz : ARIA_MARK.idleBreathHz;
  const wave = 0.5 + 0.5 * Math.sin(time * hz * Math.PI * 2);
  return 0.18 + wave * 0.07 + (speaking ? 0.04 : 0);
}
