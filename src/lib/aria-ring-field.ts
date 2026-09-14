import {
  ARIA_MARK,
  contrastRingIndices,
  ringHex,
  ringStrokeWidth,
  visibleRingIndices,
} from "./aria-mark";

/** Lockstep export for the three-hex nest (Swift `AriaSigilGeometry`). */
export const ARIA_HEX_FIELD = {
  kind: ARIA_MARK.kind,
  shape: ARIA_MARK.shape,
  hexCount: ARIA_MARK.hexCount,
  radii: ARIA_MARK.radii,
  tiltDeg: ARIA_MARK.tiltDeg,
  opacity: ARIA_MARK.opacity,
} as const;

export const ARIA_HEXES = ARIA_MARK.radii.map((radius, index) => ({
  index,
  radius,
  tiltDeg: ARIA_MARK.tiltDeg[index] ?? 0,
  opacity: ARIA_MARK.opacity[index] ?? 0,
  pearl: index % 2 === 0,
}));

/** Web stand-in for the Swift smart-metal orb core. */
export const ARIA_ORB_CORE = {
  kind: "smart-metal",
  radius: 0.32,
  pearl: "#F7F4F0",
  pearlHot: "#FFFFFF",
} as const;

/** Flat-top hexagon vertices around (cx, cy) with circumradius `r`. */
export function hexagonPoints(
  cx: number,
  cy: number,
  r: number,
  rotationRad = 0
): Array<{ x: number; y: number }> {
  return Array.from({ length: 6 }, (_, i) => {
    const angle = (i * Math.PI) / 3 + rotationRad;
    return {
      x: cx + Math.cos(angle) * r,
      y: cy + Math.sin(angle) * r,
    };
  });
}

export type RingFieldDrawInput = {
  time: number;
  speaking: boolean;
  reduceMotion: boolean;
  /** CSS pixel size — drives stroke weight. */
  cssSize: number;
};

function hexAlpha(hex: string, alpha: number): string {
  const n = hex.replace("#", "");
  const r = Number.parseInt(n.slice(0, 2), 16);
  const g = Number.parseInt(n.slice(2, 4), 16);
  const b = Number.parseInt(n.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function strokeHexagon(
  ctx: CanvasRenderingContext2D,
  rx: number,
  ry: number
): void {
  ctx.beginPath();
  for (let i = 0; i < 6; i += 1) {
    const angle = (i * Math.PI) / 3;
    const x = Math.cos(angle) * rx;
    const y = Math.sin(angle) * ry;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.stroke();
}

/**
 * Procedural kinetic orange/pearl hex nest. Three stroked hexagons around the
 * mark center — no gooey additive lobes, no readiness trim.
 */
export function drawAriaRingField(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  input: RingFieldDrawInput
): void {
  const size = Math.min(width, height);
  const cx = width / 2;
  const cy = height / 2;
  const cssSize = input.cssSize;
  const scale = cssSize > 0 ? size / cssSize : 1;
  const highlight = new Set(contrastRingIndices());

  ctx.clearRect(0, 0, width, height);

  const glow = ctx.createRadialGradient(cx, cy, size * 0.04, cx, cy, size * 0.48);
  glow.addColorStop(0, hexAlpha(ARIA_MARK.brandHue, 0.18));
  glow.addColorStop(0.55, hexAlpha(ARIA_MARK.brandHue, 0.05));
  glow.addColorStop(1, hexAlpha(ARIA_MARK.brandHue, 0));
  ctx.fillStyle = glow;
  ctx.beginPath();
  ctx.arc(cx, cy, size * 0.48, 0, Math.PI * 2);
  ctx.fill();

  // Soft white orb core hint (web canvas stand-in for the smart-metal orb).
  const orb = ctx.createRadialGradient(cx, cy, size * 0.02, cx, cy, size * 0.16);
  orb.addColorStop(0, "rgba(255,255,255,0.95)");
  orb.addColorStop(0.45, "rgba(232,238,244,0.75)");
  orb.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = orb;
  ctx.beginPath();
  ctx.arc(cx, cy, size * 0.16, 0, Math.PI * 2);
  ctx.fill();

  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = ringStrokeWidth(cssSize) * scale;

  for (const index of visibleRingIndices(cssSize)) {
    const pose = ringHex(index, input.time, input.speaking, input.reduceMotion);
    const hue =
      index % 2 === 0
        ? "#FFFFFF"
        : highlight.has(index)
          ? ARIA_MARK.brandHueLight
          : ARIA_MARK.brandHue;
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(pose.rotation);
    ctx.strokeStyle = hexAlpha(hue, pose.opacity);
    strokeHexagon(ctx, (pose.rx * size) / 2, (pose.ry * size) / 2);
    ctx.restore();
  }

  ctx.restore();
}
