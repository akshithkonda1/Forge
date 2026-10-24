/** Procedural Forge brand mark — a hammer striking a flame.
 *  Lockstep with `ForgeStrikeMarkGeometry` on iOS. No PNG.
 */
export const FORGE_STRIKE_MARK = {
  kind: "hammer-strike",
  assetName: "ForgeStrikeMark",
  paintHz: 12,
  strikeDuration: 0.55,
  compactThreshold: 36,
  heroMinimumSize: 90,
  sparkCount: 6,
  paperHex: "F7F4F0",
  emberHex: "FF4D00",
  emberLightHex: "FF7A3D",
  emberDarkHex: "C43A00",
  amberHex: "FFB84D",
  pivotX: 0.54,
  pivotY: 0.58,
  raisedAngleDeg: -44,
  impactAngleDeg: 8,
  idleAngleDeg: -16,
  idleFlare: 0.28,
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
  if (p <= 0.22) return FORGE_STRIKE_MARK.raisedAngleDeg;
  if (p <= 0.4) {
    const t = (p - 0.22) / 0.18;
    return lerp(FORGE_STRIKE_MARK.raisedAngleDeg, FORGE_STRIKE_MARK.impactAngleDeg, t * t * t);
  }
  if (p <= 0.62) {
    const t = (p - 0.4) / 0.22;
    const eased = 1 - (1 - t) ** 3;
    return lerp(FORGE_STRIKE_MARK.impactAngleDeg, FORGE_STRIKE_MARK.idleAngleDeg, eased);
  }
  return FORGE_STRIKE_MARK.idleAngleDeg;
}

export function strikeFlare(progress: number): number {
  const p = Math.min(1, Math.max(0, progress));
  const pre = FORGE_STRIKE_MARK.idleFlare * 0.45;
  if (p < 0.38) return pre;
  if (p < 0.46) {
    const t = (p - 0.38) / 0.08;
    return lerp(pre, 1, t);
  }
  if (p < 0.88) {
    const t = (p - 0.46) / 0.42;
    return lerp(1, FORGE_STRIKE_MARK.idleFlare, t);
  }
  return FORGE_STRIKE_MARK.idleFlare;
}

export function hammerCommands(): ForgeStrikeCommand[] {
  return [
    { type: "M", x: -0.175, y: -0.1 },
    { type: "L", x: -0.175, y: 0.1 },
    { type: "L", x: -0.018, y: 0.086 },
    { type: "L", x: -0.018, y: 0.036 },
    { type: "L", x: 0.02, y: 0.03 },
    { type: "L", x: 0.392, y: 0.026 },
    { type: "C", cx1: 0.448, cy1: 0.026, cx2: 0.448, cy2: -0.026, x: 0.392, y: -0.026 },
    { type: "L", x: 0.02, y: -0.03 },
    { type: "L", x: -0.018, y: -0.036 },
    { type: "L", x: -0.018, y: -0.086 },
    { type: "Z" },
  ];
}

export function flameCommands(index: number, flare: number): ForgeStrikeCommand[] {
  const f = Math.min(1, Math.max(0, flare));
  const rise = 0.56 + 0.44 * f;
  if (index === 0) {
    return tongue(0.388, 0.705, 0.318 - 0.02 * f, 0.705 - 0.4 * rise, 0.092 + 0.028 * f);
  }
  if (index === 1) {
    return tongue(0.425, 0.718, 0.402, 0.718 - 0.48 * rise, 0.072 + 0.022 * f);
  }
  return tongue(0.43, 0.698, 0.424, 0.698 - 0.28 * rise, 0.038 + 0.012 * f);
}

export function strikeSpark(
  index: number,
  progress: number,
  reduceMotion: boolean
): ForgeStrikeSpark {
  const i = Math.max(0, Math.min(FORGE_STRIKE_MARK.sparkCount - 1, index));
  if (reduceMotion) {
    return { x: FORGE_STRIKE_MARK.pivotX, y: FORGE_STRIKE_MARK.pivotY, radius: 0, opacity: 0 };
  }
  const p = Math.min(1, Math.max(0, progress));
  const age = (p - 0.4) / 0.36;
  if (age <= 0) {
    return { x: FORGE_STRIKE_MARK.pivotX, y: FORGE_STRIKE_MARK.pivotY, radius: 0.004, opacity: 0 };
  }
  const travel = Math.min(1, Math.max(0, age));
  const fade = travel < 1 ? 1 - travel : 0;
  const seed = i * 17.13;
  const angle = ((-125 + i * 28 + 8 * Math.sin(seed)) * Math.PI) / 180;
  const dist = (0.1 + 0.045 * (i % 3)) * travel;
  return {
    x: 0.41 + Math.cos(angle) * dist,
    y: 0.64 + Math.sin(angle) * dist,
    radius: 0.007 + 0.003 * hash01(seed),
    opacity: 0.85 * fade,
  };
}

export function impactGlowOpacity(flare: number): number {
  return (
    Math.max(0, Math.min(1, (flare - FORGE_STRIKE_MARK.idleFlare) / (1 - FORGE_STRIKE_MARK.idleFlare))) *
    0.55
  );
}

export function impactGlowRadius(flare: number): number {
  return 0.04 + 0.05 * Math.max(0, Math.min(1, flare));
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

function tongue(
  baseX: number,
  baseY: number,
  tipX: number,
  tipY: number,
  width: number
): ForgeStrikeCommand[] {
  const left = baseX - width;
  const right = baseX + width;
  const rise = baseY - tipY;
  return [
    { type: "M", x: left, y: baseY },
    {
      type: "C",
      cx1: left - width * 0.15,
      cy1: baseY - rise * 0.32,
      cx2: tipX - width * 0.58,
      cy2: tipY + rise * 0.24,
      x: tipX,
      y: tipY,
    },
    {
      type: "C",
      cx1: tipX + width * 0.58,
      cy1: tipY + rise * 0.24,
      cx2: right + width * 0.15,
      cy2: baseY - rise * 0.32,
      x: right,
      y: baseY,
    },
    {
      type: "C",
      cx1: baseX + width * 0.28,
      cy1: baseY + width * 0.38,
      cx2: baseX - width * 0.28,
      cy2: baseY + width * 0.38,
      x: left,
      y: baseY,
    },
    { type: "Z" },
  ];
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
