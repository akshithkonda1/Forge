/** Shared ARIA ring-field — lockstep with `shared/aria-mark.json`. No PNG runtime. */
export const ARIA_MARK = {
  assetName: "AriaMark",
  kind: "ring-field",
  brandHue: "#FF4D00",
  brandHueLight: "#FF6B2B",
  ringCount: 5,
  strokeWidthCompact: 1.35,
  strokeWidthHero: 1.85,
  radii: [0.38, 0.48, 0.58, 0.68, 0.78],
  eccentricity: [0.1, 0.14, 0.08, 0.16, 0.11],
  tiltDeg: [14, -22, 28, -10, 18],
  phaseOffsets: [0, 0.18, 0.41, 0.63, 0.88],
  opacity: [0.32, 0.42, 0.55, 0.38, 0.48],
  idleSpinHz: 0.04,
  speakingSpinHz: 0.075,
  stillPoseAngleDeg: 18,
  heroMinimumSize: 90,
  compactRecommend: 28,
  notes:
    "Brand mark = kinetic overlapping ellipses in Forge orange. Not gooey ember. Not readiness progress trim or score label. Reduce Motion freezes at stillPoseAngleDeg. No PNG runtime.",
} as const;

/**
 * Legacy gooey-ember motion. Canvas still draws this until the ring-field
 * renderer lands. Not part of the living brand contract.
 */
export const LEGACY_EMBER = {
  idleBreathHz: 0.42,
  speakingBreathHz: 0.68,
  stillPose: 1.72,
  maxGaze: 0.14,
} as const;

/** @deprecated Living mark is ring-field (`ARIA_MARK`). Kept for the ember canvas. */
export const ARIA_LOBES = [
  { angle: 0.62, dist: 0.26, r: 0.44, phase: 0.0 },
  { angle: 2.18, dist: 0.24, r: 0.41, phase: 1.1 },
  { angle: 3.92, dist: 0.28, r: 0.43, phase: 2.4 },
  { angle: 5.48, dist: 0.23, r: 0.4, phase: 3.6 },
] as const;

export type AriaMarkState = "idle" | "listening" | "processing" | "speaking";

/** @deprecated Gaze is ember-canvas only. Ring-field does not use pointer gaze. */
export function clampGaze(value: number): number {
  return Math.min(LEGACY_EMBER.maxGaze, Math.max(-LEGACY_EMBER.maxGaze, value));
}

/** @deprecated Living mark is ring-field. Ember lobes stay for the legacy canvas. */
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
  const hz = speaking ? LEGACY_EMBER.speakingBreathHz : LEGACY_EMBER.idleBreathHz;
  const wave = Math.sin(time * hz * Math.PI * 2 + lobe.phase);
  const dist = lobe.dist + 0.045 * wave;
  const ang = lobe.angle + 0.09 * Math.sin(time * 0.28 * Math.PI * 2 + lobe.phase);
  const r = lobe.r * (0.93 + 0.09 * (0.5 + 0.5 * Math.sin(time * hz * Math.PI * 2)));
  return { x: Math.cos(ang) * dist, y: Math.sin(ang) * dist, r };
}

/** @deprecated Living mark is ring-field. Ember core stays for the legacy canvas. */
export function emberCoreRadius(time: number, speaking: boolean, reduceMotion: boolean): number {
  if (reduceMotion) return 0.22;
  const hz = speaking ? LEGACY_EMBER.speakingBreathHz : LEGACY_EMBER.idleBreathHz;
  const wave = 0.5 + 0.5 * Math.sin(time * hz * Math.PI * 2);
  return 0.18 + wave * 0.07 + (speaking ? 0.04 : 0);
}
