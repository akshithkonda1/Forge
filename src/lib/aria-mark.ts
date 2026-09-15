/** Shared ARIA ring-field — lockstep with `shared/aria-mark.json`. No PNG runtime. */
export const ARIA_MARK = {
  assetName: "AriaMark",
  kind: "ring-field",
  brandHue: "#FF4D00",
  brandHueLight: "#FF6B2B",
  ringCount: 5,
  strokeWidthCompact: 1.5,
  strokeWidthHero: 1.85,
  radii: [0.38, 0.48, 0.58, 0.68, 0.78],
  eccentricity: [0.1, 0.14, 0.08, 0.16, 0.11],
  tiltDeg: [14, -22, 28, -10, 18],
  phaseOffsets: [0, 0.18, 0.41, 0.63, 0.88],
  opacity: [0.40, 0.72, 0.78, 0.45, 0.55],
  idleSpinHz: 0.04,
  speakingSpinHz: 0.075,
  stillPoseAngleDeg: 18,
  heroMinimumSize: 90,
  compactRecommend: 28,
  notes:
    "Brand mark = kinetic overlapping ellipses in Forge orange. Not gooey ember. Not readiness progress trim or score label. Reduce Motion freezes at stillPoseAngleDeg. No PNG runtime. Cove contrast: strokeWidthCompact 1.5 (never below ~3 CSS px at 1×). Compact 3-ring subset should prefer the two ≥0.70 rings + one supporting ring.",
} as const;

/** Web compact ceiling. Contract recommends 28; slots ≤32 stay still-pose. */
export const ARIA_MARK_COMPACT_MAX = 32;
export const ARIA_MARK_CONTRAST_FLOOR = 0.7;

export type AriaMarkSizeTier = "compact" | "mid" | "hero";
export type AriaRingPose = {
  rx: number;
  ry: number;
  rotation: number;
  opacity: number;
};

export function ariaMarkSizeTier(size: number): AriaMarkSizeTier {
  if (size <= ARIA_MARK_COMPACT_MAX) return "compact";
  if (size >= ARIA_MARK.heroMinimumSize) return "hero";
  return "mid";
}

/** Compact marks stay still. Mid/hero spin unless Reduce Motion. */
export function ariaMarkShouldSpin(size: number, reduceMotion: boolean): boolean {
  return !reduceMotion && ariaMarkSizeTier(size) !== "compact";
}

/** Soft radial glow is hero/mid atmosphere — skip at the compact 3-ring ceiling. */
export function ariaMarkShouldGlow(size: number): boolean {
  return ariaMarkSizeTier(size) !== "compact";
}

/** Paint cadence for live spin. Geometry still uses idle 0.04 / speaking 0.075 Hz. */
export const ARIA_MARK_PAINT_HZ = 12;

/** First frame always paints (`lastPaintMs < 0`). Later frames cap near 12 Hz. */
export function ariaMarkPaintDue(nowMs: number, lastPaintMs: number): boolean {
  if (lastPaintMs < 0) return true;
  return nowMs - lastPaintMs >= 1000 / ARIA_MARK_PAINT_HZ;
}

export function contrastRingIndices(
  opacities: readonly number[] = ARIA_MARK.opacity
): number[] {
  return opacities.flatMap((opacity, index) =>
    opacity >= ARIA_MARK_CONTRAST_FLOOR ? [index] : []
  );
}

/** Two ≥0.70 rings plus the strongest supporting ring — Cove 3-ring subset. */
export function compactRingIndices(
  opacities: readonly number[] = ARIA_MARK.opacity
): number[] {
  const contrast = contrastRingIndices(opacities);
  let support = -1;
  let best = Number.NEGATIVE_INFINITY;
  opacities.forEach((opacity, index) => {
    if (opacity < ARIA_MARK_CONTRAST_FLOOR && opacity > best) {
      best = opacity;
      support = index;
    }
  });
  return [...contrast, ...(support >= 0 ? [support] : [])].sort((a, b) => a - b);
}

export function visibleRingIndices(size: number): number[] {
  if (ariaMarkSizeTier(size) === "compact") return compactRingIndices();
  return Array.from({ length: ARIA_MARK.ringCount }, (_, index) => index);
}

export function ringStrokeWidth(size: number): number {
  const raw =
    size < ARIA_MARK.heroMinimumSize
      ? ARIA_MARK.strokeWidthCompact
      : ARIA_MARK.strokeWidthHero;
  return Math.max(ARIA_MARK.strokeWidthCompact, raw);
}

export function ringSpinHz(speaking: boolean): number {
  return speaking ? ARIA_MARK.speakingSpinHz : ARIA_MARK.idleSpinHz;
}

/** Lockstep with Swift `AriaSigilGeometry.ellipse`. */
export function ringEllipse(
  index: number,
  time: number,
  speaking: boolean,
  reduceMotion: boolean
): AriaRingPose {
  const i = Math.max(0, Math.min(ARIA_MARK.ringCount - 1, index));
  const radius = ARIA_MARK.radii[i] ?? ARIA_MARK.radii[0];
  const ecc = ARIA_MARK.eccentricity[i] ?? ARIA_MARK.eccentricity[0];
  const tilt = ((ARIA_MARK.tiltDeg[i] ?? 0) * Math.PI) / 180;
  const phase = (ARIA_MARK.phaseOffsets[i] ?? 0) * Math.PI * 2;
  const still = (ARIA_MARK.stillPoseAngleDeg * Math.PI) / 180;
  const spin = reduceMotion ? still : time * ringSpinHz(speaking) * Math.PI * 2;
  return {
    rx: radius * (1 + ecc),
    ry: radius * (1 - ecc),
    rotation: tilt + phase + spin,
    opacity: ARIA_MARK.opacity[i] ?? ARIA_MARK.opacity[0],
  };
}

/**
 * Legacy gooey-ember motion. Unused by brand slots — ring-field is the living mark.
 * Kept so the retired hearth can be deleted in one place.
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
