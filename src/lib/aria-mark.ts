/** Shared ARIA nest — lockstep with `shared/aria-mark.json`. No PNG runtime. */
export const ARIA_MARK = {
  assetName: "AriaMark",
  kind: "soft-hex-field",
  brandHue: "#FF4D00",
  brandHueLight: "#FF6B2B",
  pearlHex: "#F7F4F0",
  pearlHotHex: "#FFFFFF",
  nestFrostHex: "#A9D8FF",
  hearthGlowHex: "#3A0E12",
  ringHex: ["#F7F4F0", "#A9D8FF", "#FF4D00"],
  hearthSpecularMax: 0.55,
  ringCount: 3,
  strokeWidthCompact: 1.5,
  strokeWidthHero: 1.75,
  cornerRoundness: 0.34,
  orbDiameterIdle: 0.22,
  orbDiameterSpeaking: 0.245,
  radii: [0.46, 0.52, 0.58],
  eccentricity: [0.07, 0.05, 0.06],
  tiltDeg: [-18, 24, -12],
  phaseOffsets: [0, 0.33, 0.66],
  opacity: [0.88, 0.78, 0.72],
  paintedOpacityFloor: 0.7,
  idleOrbitHz: [0.065, -0.042, 0.028],
  speakingOrbitHz: [0.09, -0.06, 0.04],
  liquidWaveHz: 0.42,
  paintHz: 12,
  stillPoseAngleDeg: 18,
  heroMinimumSize: 90,
  compactRecommend: 28,
  wordmarkPrimaryMax: 32,
  splash: "mark+wordmark",
  notes:
    "B+E gallery lock: soft-hex nest + metal sun. Ring→color: 0 inner pearl #F7F4F0 @ 0.88; 1 mid frost #A9D8FF @ 0.78; 2 outer Forge orange #FF4D00 @ 0.72 (accent stroke — never under 0.70). Sun/metal: pearlHot #FFFFFF / pearl #F7F4F0. Hearth wash decorative only: #3A0E12 / orange specular under ~0.55 — never sole compact silhouette. Forge orange is accent (specular/wash), not kinetic ring-field silhouette. Flicker/wave floor: painted opacity for any ring with contract opacity ≥0.70 must never go below 0.70 after flicker/wave. No fire-under-logo, no flower petals, no industrial chrome, no PNG runtime. Home readiness data rings stay separate forever. Reduce Motion freezes at stillPoseAngleDeg. One live nest per screen; paintHz 12. Compact stroke ≥1.5; all ring opacities ≥0.70. ≤32pt wordmark-primary + tiny still nest if clear.",
} as const;

/**
 * Living mark is soft-hex nest + metal sun (`kind: soft-hex-field`).
 * Forge orange is accent (specular/wash), not a 5-ellipse ring-field silhouette.
 * Web canvas: `drawAriaNest` in `aria-nest.ts`.
 */
export const ARIA_MARK_KIND = ARIA_MARK.kind;

/** Web compact / wordmark-primary ceiling. Slots ≤32 stay still-pose. */
export const ARIA_MARK_COMPACT_MAX = ARIA_MARK.wordmarkPrimaryMax;
export const ARIA_MARK_CONTRAST_FLOOR = ARIA_MARK.paintedOpacityFloor;
export const NEST_PAINT_INTERVAL_MS = 1000 / ARIA_MARK.paintHz;
export const FORGE_WORDMARK = "FORGE";

/** Inner pearl, mid frost, outer Forge orange accent. */
export function nestRingHex(index: number): string {
  const i = Math.max(0, Math.min(ARIA_MARK.ringCount - 1, index));
  return ARIA_MARK.ringHex[i] ?? ARIA_MARK.ringHex[0];
}

/**
 * Cove / #281 flicker-wave floor: a ring whose contract opacity is ≥0.70
 * must never paint below 0.70 after flicker or liquid wave.
 */
export function paintedNestOpacity(contractOpacity: number, flicker = 1): number {
  const painted = contractOpacity * flicker;
  if (contractOpacity >= ARIA_MARK.paintedOpacityFloor) {
    return Math.max(ARIA_MARK.paintedOpacityFloor, painted);
  }
  return painted;
}

export type AriaMarkSizeTier = "compact" | "mid" | "hero";
export type AriaRingPose = {
  rx: number;
  ry: number;
  rotation: number;
  opacity: number;
};
export type AriaNestRingPose = AriaRingPose & {
  wavePhase: number;
  waveAmp: number;
  hex: string;
};
export type AriaMetalSunPose = {
  diameter: number;
  glow: number;
  highlight: number;
  sheenAngle: number;
  sx: number;
  sy: number;
};

export function ariaMarkSizeTier(size: number): AriaMarkSizeTier {
  if (size <= ARIA_MARK_COMPACT_MAX) return "compact";
  if (size >= ARIA_MARK.heroMinimumSize) return "hero";
  return "mid";
}

/** Compact marks stay still. Mid/hero orbit unless Reduce Motion. */
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

/** Nest is three rings, all above the contrast floor — no 5-ellipse subset. */
export function compactRingIndices(
  opacities: readonly number[] = ARIA_MARK.opacity
): number[] {
  const contrast = contrastRingIndices(opacities);
  if (contrast.length >= ARIA_MARK.ringCount) return contrast.slice(0, ARIA_MARK.ringCount);
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

/** One 3-ring nest at every size. Compact no longer subsets a 5-ellipse field. */
export function visibleRingIndices(_size?: number): number[] {
  return Array.from({ length: ARIA_MARK.ringCount }, (_, index) => index);
}

export function ringStrokeWidth(size: number): number {
  const raw =
    size < ARIA_MARK.heroMinimumSize
      ? ARIA_MARK.strokeWidthCompact
      : ARIA_MARK.strokeWidthHero;
  return Math.max(ARIA_MARK.strokeWidthCompact, raw);
}

export function nestOrbitHz(index: number, speaking: boolean): number {
  const orbits = speaking ? ARIA_MARK.speakingOrbitHz : ARIA_MARK.idleOrbitHz;
  const i = Math.max(0, Math.min(ARIA_MARK.ringCount - 1, index));
  return orbits[i] ?? orbits[0];
}

/**
 * @deprecated Nest motion is per-ring `idleOrbitHz` / `speakingOrbitHz`.
 * Scalar kept so legacy ring-field helpers stay compiling.
 */
export function ringSpinHz(speaking: boolean, index = 0): number {
  return nestOrbitHz(index, speaking);
}

/** Shared nest pose (rx/ry/tilt/orbit). Silhouette is the soft-hex in `drawAriaNest`. */
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
  const spin = reduceMotion ? still : time * nestOrbitHz(i, speaking) * Math.PI * 2;
  return {
    rx: radius * (1 + ecc),
    ry: radius * (1 - ecc),
    rotation: tilt + phase + spin,
    opacity: ARIA_MARK.opacity[i] ?? ARIA_MARK.opacity[0],
  };
}

/**
 * Living nest ring: orbit + liquid wave, with Cove flicker floor on opacity.
 * Reduce Motion freezes wave amp at 0 and keeps stillPoseAngleDeg.
 */
export function nestRingPose(
  index: number,
  time: number,
  speaking: boolean,
  reduceMotion: boolean
): AriaNestRingPose {
  const i = Math.max(0, Math.min(ARIA_MARK.ringCount - 1, index));
  const base = ringEllipse(i, time, speaking, reduceMotion);
  const phase = (ARIA_MARK.phaseOffsets[i] ?? 0) * Math.PI * 2;
  if (reduceMotion) {
    return {
      ...base,
      wavePhase: phase,
      waveAmp: 0,
      hex: nestRingHex(i),
    };
  }
  const wavePhase = time * ARIA_MARK.liquidWaveHz * Math.PI * 2 + phase;
  const drive = speaking ? 1 : 0.22;
  const wave = Math.sin(wavePhase);
  const wave2 = Math.cos(wavePhase * 1.27 + i * 0.55);
  const flicker = 0.86 + 0.14 * (0.5 + 0.5 * wave);
  const waveAmp = ((speaking ? 0.055 : 0.028) + i * 0.004) * (1 + 0.55 * drive);
  return {
    rx: base.rx * (1 + wave * 0.018 * drive),
    ry: base.ry * (1 + wave2 * 0.022 * drive),
    rotation: base.rotation + wave * 0.012 * drive,
    opacity: paintedNestOpacity(base.opacity, flicker),
    wavePhase,
    waveAmp,
    hex: nestRingHex(i),
  };
}

/** Metal sun. Reduce Motion freezes diameter at idle and kills sheen travel. */
export function metalSunPose(
  time: number,
  speaking: boolean,
  reduceMotion: boolean
): AriaMetalSunPose {
  if (reduceMotion) {
    return {
      diameter: ARIA_MARK.orbDiameterIdle,
      glow: 0.55,
      highlight: 0.7,
      sheenAngle: (ARIA_MARK.stillPoseAngleDeg * Math.PI) / 180,
      sx: 1,
      sy: 1,
    };
  }
  const drive = speaking ? 1 : 0.22;
  const phase = time * ARIA_MARK.liquidWaveHz * Math.PI * 2;
  const wave = Math.sin(phase);
  const breath = 0.012 * Math.sin(time * 0.55 * Math.PI * 2);
  const diameter = speaking ? ARIA_MARK.orbDiameterSpeaking : ARIA_MARK.orbDiameterIdle;
  return {
    diameter: diameter * (1 + 0.04 * drive * wave),
    glow: 0.5 + 0.36 * drive,
    highlight: 0.7 + 0.26 * drive,
    sheenAngle: phase,
    sx: 1 + breath + wave * 0.04 * drive,
    sy: 1 + breath * 0.85,
  };
}

export type NestLiveSlot = {
  size: number;
  speaking: boolean;
  visible: boolean;
  canLive: boolean;
};

type NestLiveInternal = NestLiveSlot & { onChange: () => void };

const nestLiveSlots = new Map<number, NestLiveInternal>();
let nestLiveSeq = 1;

/** One live nest per screen — mid/hero only; speaking beats idle; larger wins ties. */
export function nestLiveCreateId(): number {
  nestLiveSeq += 1;
  return nestLiveSeq;
}

export function nestLiveReset(): void {
  nestLiveSlots.clear();
  nestLiveSeq = 1;
}

export function nestLiveWinnerId(): number | null {
  let bestId: number | null = null;
  let best = Number.NEGATIVE_INFINITY;
  for (const [id, slot] of nestLiveSlots) {
    if (!slot.visible || !slot.canLive) continue;
    const score = (slot.speaking ? 10_000 : 0) + slot.size;
    if (score > best) {
      best = score;
      bestId = id;
    }
  }
  return bestId;
}

export function nestLiveIsWinner(id: number): boolean {
  return nestLiveWinnerId() === id;
}

export function nestLiveUpsert(id: number, slot: NestLiveInternal): void {
  nestLiveSlots.set(id, slot);
  for (const entry of nestLiveSlots.values()) entry.onChange();
}

export function nestLiveRemove(id: number): void {
  if (!nestLiveSlots.delete(id)) return;
  for (const entry of nestLiveSlots.values()) entry.onChange();
}

/**
 * Legacy gooey-ember motion. Unused by brand slots — nest is the living mark.
 * Kept so the retired hearth can be deleted in one place.
 */
export const LEGACY_EMBER = {
  idleBreathHz: 0.42,
  speakingBreathHz: 0.68,
  stillPose: 1.72,
  maxGaze: 0.14,
} as const;

/** @deprecated Living mark is soft-hex nest (`ARIA_MARK`). Kept for the ember canvas. */
export const ARIA_LOBES = [
  { angle: 0.62, dist: 0.26, r: 0.44, phase: 0.0 },
  { angle: 2.18, dist: 0.24, r: 0.41, phase: 1.1 },
  { angle: 3.92, dist: 0.28, r: 0.43, phase: 2.4 },
  { angle: 5.48, dist: 0.23, r: 0.4, phase: 3.6 },
] as const;

export type AriaMarkState = "idle" | "listening" | "processing" | "speaking";

/** @deprecated Gaze is ember-canvas only. Nest does not use pointer gaze. */
export function clampGaze(value: number): number {
  return Math.min(LEGACY_EMBER.maxGaze, Math.max(-LEGACY_EMBER.maxGaze, value));
}

/** @deprecated Living mark is soft-hex nest. Ember lobes stay for the legacy canvas. */
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

/** @deprecated Living mark is soft-hex nest. Ember core stays for the legacy canvas. */
export function emberCoreRadius(time: number, speaking: boolean, reduceMotion: boolean): number {
  if (reduceMotion) return 0.22;
  const hz = speaking ? LEGACY_EMBER.speakingBreathHz : LEGACY_EMBER.idleBreathHz;
  const wave = 0.5 + 0.5 * Math.sin(time * hz * Math.PI * 2);
  return 0.18 + wave * 0.07 + (speaking ? 0.04 : 0);
}
