/** Procedural Forge brand mark — a hammer striking a flame.
 *  Lockstep with `ForgeStrikeMarkGeometry` on iOS. No PNG.
 *
 *  Geometry sits on a 200-unit grid (step 0.005) inside a 1×1 optical box.
 *  The hammer is a side-view engineer’s head: landscape, filleted, slender
 *  handle. The flame is four nested organic envelopes, not cloned tongues.
 */
export const FORGE_STRIKE_MARK = {
  kind: "hammer-strike",
  assetName: "ForgeStrikeMark",
  paintHz: 12,
  strikeDuration: 0.56,
  compactThreshold: 36,
  heroMinimumSize: 90,
  sparkCount: 6,
  flameLayerCount: 4,
  gridStep: 0.005,
  paperHex: "F7F4F0",
  paperShadeHex: "E8E4DE",
  emberHex: "FF4D00",
  emberLightHex: "FF7A3D",
  emberDarkHex: "C43A00",
  amberHex: "FFB84D",
  kernelHex: "FFE6A8",
  pivotX: 0.68,
  pivotY: 0.5,
  strikeX: 0.5,
  strikeY: 0.62,
  flameOriginX: 0.36,
  flameOriginY: 0.86,
  raisedAngleDeg: 16,
  impactAngleDeg: -44,
  idleAngleDeg: -30,
  idleFlare: 0.4,
  holdEnd: 0.14,
  impactEnd: 0.32,
} as const;

export type ForgeStrikeCommand =
  | { type: "M"; x: number; y: number }
  | { type: "L"; x: number; y: number }
  | { type: "C"; cx1: number; cy1: number; cx2: number; cy2: number; x: number; y: number }
  | { type: "Z" };

export type ForgeStrikeSpark = {
  x: number;
  y: number;
  radius: number;
  opacity: number;
};

export type ForgeStrikePose = {
  hammerAngleDeg: number;
  flare: number;
  settled: boolean;
};

export type ForgeFlareScale = {
  x: number;
  y: number;
  originX: number;
  originY: number;
};

export function isCompactStrike(size: number): boolean {
  return size < FORGE_STRIKE_MARK.compactThreshold;
}

export function strikeProgress(elapsed: number): number {
  return Math.min(1, Math.max(0, elapsed / FORGE_STRIKE_MARK.strikeDuration));
}

export function strikePose(progress: number, reduceMotion: boolean): ForgeStrikePose {
  if (reduceMotion) {
    return {
      hammerAngleDeg: FORGE_STRIKE_MARK.idleAngleDeg,
      flare: FORGE_STRIKE_MARK.idleFlare,
      settled: true,
    };
  }
  const p = Math.min(1, Math.max(0, progress));
  return {
    hammerAngleDeg: hammerAngleDeg(p),
    flare: strikeFlare(p),
    settled: p >= 1,
  };
}

export function hammerAngleDeg(progress: number): number {
  const p = Math.min(1, Math.max(0, progress));
  const hold = FORGE_STRIKE_MARK.holdEnd;
  const hit = FORGE_STRIKE_MARK.impactEnd;
  if (p <= hold) return FORGE_STRIKE_MARK.raisedAngleDeg;
  if (p <= hit) {
    const t = (p - hold) / (hit - hold);
    return lerp(FORGE_STRIKE_MARK.raisedAngleDeg, FORGE_STRIKE_MARK.impactAngleDeg, t ** 4);
  }
  return lerp(
    FORGE_STRIKE_MARK.impactAngleDeg,
    FORGE_STRIKE_MARK.idleAngleDeg,
    spring01((p - hit) / (1 - hit))
  );
}

export function strikeFlare(progress: number): number {
  const p = Math.min(1, Math.max(0, progress));
  const pre = FORGE_STRIKE_MARK.idleFlare * 0.5;
  const wind = FORGE_STRIKE_MARK.impactEnd - 0.02;
  if (p < wind) return pre;
  if (p < FORGE_STRIKE_MARK.impactEnd + 0.04) {
    const t = (p - wind) / 0.06;
    return lerp(pre, 1, Math.min(1, Math.max(0, t)));
  }
  if (p < 0.86) {
    return lerp(1, FORGE_STRIKE_MARK.idleFlare, spring01((p - 0.36) / 0.5));
  }
  return FORGE_STRIKE_MARK.idleFlare;
}

export function flareScale(flare: number): ForgeFlareScale {
  const f = Math.min(1, Math.max(0, flare));
  return {
    x: 0.94 + 0.06 * f,
    y: 0.74 + 0.26 * f,
    originX: FORGE_STRIKE_MARK.flameOriginX,
    originY: FORGE_STRIKE_MARK.flameOriginY,
  };
}

export function spring01(t: number): number {
  const p = Math.min(1, Math.max(0, t));
  const zeta = 0.62;
  const omega = 9.2;
  const wd = omega * Math.sqrt(1 - zeta * zeta);
  const env = Math.exp(-zeta * omega * p);
  return 1 - env * (Math.cos(wd * p) + ((zeta * omega) / wd) * Math.sin(wd * p));
}

/** Hammer silhouette in local space (origin at the eye, +x along the handle). */
export function hammerCommands(): ForgeStrikeCommand[] {
  return [
    { type: "M", x: -0.243, y: -0.102 },
    { type: "C", cx1: -0.252, cy1: -0.102, cx2: -0.258, cy2: -0.095, x: -0.258, y: -0.086 },
    { type: "L", x: -0.258, y: 0.086 },
    { type: "C", cx1: -0.258, cy1: 0.095, cx2: -0.252, cy2: 0.102, x: -0.243, y: 0.102 },
    { type: "L", x: -0.04, y: 0.09 },
    { type: "C", cx1: -0.028, cy1: 0.09, cx2: -0.022, cy2: 0.084, x: -0.022, y: 0.074 },
    { type: "L", x: -0.022, y: 0.038 },
    { type: "C", cx1: -0.022, cy1: 0.033, cx2: -0.018, cy2: 0.03, x: -0.012, y: 0.03 },
    { type: "L", x: 0.34, y: 0.027 },
    { type: "C", cx1: 0.368, cy1: 0.027, cx2: 0.368, cy2: -0.027, x: 0.34, y: -0.027 },
    { type: "L", x: -0.012, y: -0.03 },
    { type: "C", cx1: -0.018, cy1: -0.03, cx2: -0.022, cy2: -0.033, x: -0.022, y: -0.038 },
    { type: "L", x: -0.022, y: -0.074 },
    { type: "C", cx1: -0.022, cy1: -0.084, cx2: -0.028, cy2: -0.09, x: -0.04, y: -0.09 },
    { type: "Z" },
    { type: "M", x: -0.005, y: -0.015 },
    { type: "C", cx1: 0.006, cy1: -0.015, cx2: 0.016, cy2: -0.008, x: 0.016, y: 0 },
    { type: "C", cx1: 0.016, cy1: 0.008, cx2: 0.006, cy2: 0.015, x: -0.005, y: 0.015 },
    { type: "C", cx1: -0.016, cy1: 0.015, cx2: -0.026, cy2: 0.008, x: -0.026, y: 0 },
    { type: "C", cx1: -0.026, cy1: -0.008, cx2: -0.016, cy2: -0.015, x: -0.005, y: -0.015 },
    { type: "Z" },
  ];
}

/** Inset cheek highlight — machined face, hero sizes only. */
export function hammerHighlightCommands(): ForgeStrikeCommand[] {
  return [
    { type: "M", x: -0.238, y: -0.084 },
    { type: "C", cx1: -0.246, cy1: -0.084, cx2: -0.248, cy2: -0.079, x: -0.248, y: -0.072 },
    { type: "L", x: -0.248, y: -0.012 },
    { type: "L", x: -0.04, y: -0.01 },
    { type: "L", x: -0.04, y: -0.072 },
    { type: "C", cx1: -0.04, cy1: -0.078, cx2: -0.044, cy2: -0.082, x: -0.052, y: -0.084 },
    { type: "Z" },
  ];
}

/** Canonical flame envelopes. Renderers scale with `flareScale`. */
export function flameCommands(index: number, _flare = 1): ForgeStrikeCommand[] {
  switch (index) {
    case 0:
      return [
        { type: "M", x: 0.248, y: 0.852 },
        { type: "C", cx1: 0.13, cy1: 0.72, cx2: 0.12, cy2: 0.49, x: 0.18, y: 0.3 },
        { type: "C", cx1: 0.228, cy1: 0.15, cx2: 0.3, cy2: 0.07, x: 0.35, y: 0.048 },
        { type: "C", cx1: 0.365, cy1: 0.07, cx2: 0.4, cy2: 0.13, x: 0.418, y: 0.165 },
        { type: "C", cx1: 0.445, cy1: 0.12, cx2: 0.475, cy2: 0.09, x: 0.5, y: 0.108 },
        { type: "C", cx1: 0.518, cy1: 0.13, cx2: 0.515, cy2: 0.185, x: 0.49, y: 0.24 },
        { type: "C", cx1: 0.535, cy1: 0.36, cx2: 0.555, cy2: 0.52, x: 0.528, y: 0.68 },
        { type: "C", cx1: 0.505, cy1: 0.8, cx2: 0.44, cy2: 0.87, x: 0.36, y: 0.888 },
        { type: "C", cx1: 0.295, cy1: 0.905, cx2: 0.255, cy2: 0.888, x: 0.248, y: 0.852 },
        { type: "Z" },
      ];
    case 1:
      return [
        { type: "M", x: 0.282, y: 0.82 },
        { type: "C", cx1: 0.188, cy1: 0.705, cx2: 0.185, cy2: 0.5, x: 0.232, y: 0.335 },
        { type: "C", cx1: 0.268, cy1: 0.2, cx2: 0.322, cy2: 0.132, x: 0.358, y: 0.118 },
        { type: "C", cx1: 0.372, cy1: 0.138, cx2: 0.4, cy2: 0.185, x: 0.412, y: 0.212 },
        { type: "C", cx1: 0.432, cy1: 0.175, cx2: 0.455, cy2: 0.152, x: 0.472, y: 0.168 },
        { type: "C", cx1: 0.486, cy1: 0.188, cx2: 0.482, cy2: 0.23, x: 0.462, y: 0.275 },
        { type: "C", cx1: 0.5, cy1: 0.385, cx2: 0.512, cy2: 0.52, x: 0.492, y: 0.64 },
        { type: "C", cx1: 0.476, cy1: 0.74, cx2: 0.425, cy2: 0.808, x: 0.36, y: 0.828 },
        { type: "C", cx1: 0.315, cy1: 0.84, cx2: 0.292, cy2: 0.834, x: 0.282, y: 0.82 },
        { type: "Z" },
      ];
    case 2:
      return [
        { type: "M", x: 0.325, y: 0.52 },
        { type: "C", cx1: 0.3, cy1: 0.43, cx2: 0.302, cy2: 0.33, x: 0.332, y: 0.25 },
        { type: "C", cx1: 0.352, cy1: 0.195, cx2: 0.372, cy2: 0.165, x: 0.388, y: 0.158 },
        { type: "C", cx1: 0.4, cy1: 0.172, cx2: 0.412, cy2: 0.215, x: 0.416, y: 0.265 },
        { type: "C", cx1: 0.424, cy1: 0.34, cx2: 0.42, cy2: 0.43, x: 0.392, y: 0.49 },
        { type: "C", cx1: 0.375, cy1: 0.528, cx2: 0.345, cy2: 0.54, x: 0.325, y: 0.52 },
        { type: "Z" },
      ];
    default:
      return [
        { type: "M", x: 0.348, y: 0.42 },
        { type: "C", cx1: 0.338, cy1: 0.38, cx2: 0.34, cy2: 0.34, x: 0.355, y: 0.312 },
        { type: "C", cx1: 0.365, cy1: 0.292, cx2: 0.378, cy2: 0.288, x: 0.385, y: 0.3 },
        { type: "C", cx1: 0.394, cy1: 0.322, cx2: 0.395, cy2: 0.365, x: 0.382, y: 0.405 },
        { type: "C", cx1: 0.374, cy1: 0.428, cx2: 0.358, cy2: 0.432, x: 0.348, y: 0.42 },
        { type: "Z" },
      ];
  }
}

export function strikeSpark(
  index: number,
  progress: number,
  reduceMotion: boolean
): ForgeStrikeSpark {
  const i = Math.max(0, Math.min(FORGE_STRIKE_MARK.sparkCount - 1, index));
  if (reduceMotion) {
    return { x: FORGE_STRIKE_MARK.strikeX, y: FORGE_STRIKE_MARK.strikeY, radius: 0, opacity: 0 };
  }
  const p = Math.min(1, Math.max(0, progress));
  const age = (p - FORGE_STRIKE_MARK.impactEnd) / 0.34;
  if (age <= 0) {
    return { x: FORGE_STRIKE_MARK.strikeX, y: FORGE_STRIKE_MARK.strikeY, radius: 0.004, opacity: 0 };
  }
  const travel = Math.min(1, Math.max(0, age));
  const fade = travel < 1 ? 1 - travel : 0;
  const seed = i * 17.13;
  const angle = ((-118 + i * 26 + 7 * Math.sin(seed)) * Math.PI) / 180;
  const dist = (0.09 + 0.04 * (i % 3)) * travel;
  return {
    x: FORGE_STRIKE_MARK.strikeX + Math.cos(angle) * dist,
    y: FORGE_STRIKE_MARK.strikeY + Math.sin(angle) * dist,
    radius: 0.006 + 0.0025 * hash01(seed),
    opacity: 0.72 * fade,
  };
}

export function impactGlowOpacity(flare: number): number {
  return (
    Math.max(0, Math.min(1, (flare - FORGE_STRIKE_MARK.idleFlare) / (1 - FORGE_STRIKE_MARK.idleFlare))) *
    0.42
  );
}

export function impactGlowRadius(flare: number): number {
  return 0.055 + 0.07 * Math.max(0, Math.min(1, flare));
}

export function svgPath(commands: ForgeStrikeCommand[], side = 100): string {
  return commands
    .map((command) => {
      switch (command.type) {
        case "M":
          return `M ${fmt(command.x * side)} ${fmt(command.y * side)}`;
        case "L":
          return `L ${fmt(command.x * side)} ${fmt(command.y * side)}`;
        case "C":
          return `C ${fmt(command.cx1 * side)} ${fmt(command.cy1 * side)} ${fmt(command.cx2 * side)} ${fmt(command.cy2 * side)} ${fmt(command.x * side)} ${fmt(command.y * side)}`;
        case "Z":
          return "Z";
      }
    })
    .join(" ");
}

export function contrastRatio(hexA: string, hexB: string): number {
  const a = relativeLuminance(hexA);
  const b = relativeLuminance(hexB);
  const lighter = Math.max(a, b);
  const darker = Math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * Math.min(1, Math.max(0, t));
}

function hash01(seed: number): number {
  const n = Math.sin(seed * 12.9898) * 43758.5453;
  return n - Math.floor(n);
}

function fmt(value: number): string {
  return value.toFixed(3);
}

function relativeLuminance(hex: string): number {
  const cleaned = hex.replace("#", "");
  const n = parseInt(cleaned, 16);
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  const channel = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}
