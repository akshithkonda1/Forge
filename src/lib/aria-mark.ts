/** Shared ARIA soft-hex field — lockstep with `shared/aria-mark.json`. No PNG runtime. */
export const ARIA_MARK = {
  "assetName": "AriaMark",
  "kind": "soft-hex-field",
  "shape": "rounded-hexagon",
  "brandHue": "#FF4D00",
  "brandHueLight": "#FF6B2B",
  "frostHue": "#9FD6FF",
  "ringCount": 3,
  "strokeWidthCompact": 1.35,
  "strokeWidthHero": 1.6,
  "radii": [
    0.46,
    0.52,
    0.58
  ],
  "eccentricity": [
    0.07,
    0.05,
    0.06
  ],
  "tiltDeg": [
    -18,
    24,
    -12
  ],
  "phaseOffsets": [
    0.0,
    0.33,
    0.66
  ],
  "opacity": [
    0.88,
    0.78,
    0.62
  ],
  "cornerRoundness": 0.34,
  "idleOrbitHz": [
    0.065,
    -0.042,
    0.028
  ],
  "speakingOrbitHz": [
    0.11,
    -0.075,
    0.048
  ],
  "idleSpinHz": 0.05,
  "speakingSpinHz": 0.09,
  "stillPoseAngleDeg": 18,
  "heroMinimumSize": 90,
  "compactRecommend": 28,
  "notes": "Brand mark = three rounded hexagons in a tight planetary nest around a white smart-metal orb. Each hex orbits at its own rate (inner fastest; middle retrograde). Soft corners + frost/orange/pearl dual-stroke glow. Not sharp hex. Not gooey ember. Not readiness trim. Reduce Motion freezes at stillPoseAngleDeg. No PNG runtime. Always draw all three."
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

export function ariaMarkShouldSpin(size: number, reduceMotion: boolean): boolean {
  return !reduceMotion && ariaMarkSizeTier(size) !== "compact";
}

export function contrastRingIndices(
  opacities: readonly number[] = ARIA_MARK.opacity
): number[] {
  return opacities.flatMap((opacity, index) =>
    opacity >= ARIA_MARK_CONTRAST_FLOOR ? [index] : []
  );
}

export function compactRingIndices(
  _opacities: readonly number[] = ARIA_MARK.opacity
): number[] {
  return Array.from({ length: ARIA_MARK.ringCount }, (_, index) => index);
}

export function visibleRingIndices(_size: number): number[] {
  return Array.from({ length: ARIA_MARK.ringCount }, (_, index) => index);
}

export function ringStrokeWidth(size: number): number {
  const raw =
    size < ARIA_MARK.heroMinimumSize
      ? ARIA_MARK.strokeWidthCompact
      : ARIA_MARK.strokeWidthHero;
  return Math.max(ARIA_MARK.strokeWidthCompact, Math.max(raw, size * 0.018));
}

export function ringOrbitHz(index: number, speaking: boolean): number {
  const i = Math.max(0, Math.min(ARIA_MARK.ringCount - 1, index));
  const table = speaking ? ARIA_MARK.speakingOrbitHz : ARIA_MARK.idleOrbitHz;
  return table[i] ?? table[0];
}

/** Lockstep with Swift planetary soft-hex orbit pose. */
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
  const still = (ARIA_MARK.stillPoseAngleDeg * Math.PI) / 180 + phase;
  const orbit = reduceMotion
    ? still
    : phase + time * ringOrbitHz(i, speaking) * Math.PI * 2;
  return {
    rx: radius * (1 + ecc),
    ry: radius * (1 - ecc),
    rotation: tilt + orbit,
    opacity: ARIA_MARK.opacity[i] ?? ARIA_MARK.opacity[0],
  };
}

export const ringHex = ringEllipse;
