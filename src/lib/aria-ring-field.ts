import {
  ARIA_MARK,
  contrastRingIndices,
  ringEllipse,
  ringStrokeWidth,
  visibleRingIndices,
} from "./aria-mark";

/** Lockstep export for the three-ellipse Watch nest (Swift `AriaSigilGeometry`). */
export const ARIA_RING_FIELD = {
  kind: ARIA_MARK.kind,
  shape: ARIA_MARK.shape,
  ringCount: ARIA_MARK.ringCount,
  radii: ARIA_MARK.radii,
  eccentricity: ARIA_MARK.eccentricity,
  tiltDeg: ARIA_MARK.tiltDeg,
  opacity: ARIA_MARK.opacity,
} as const;

/** @deprecated Prefer `ARIA_RING_FIELD` — mark is ellipses matching Watch Home. */
export const ARIA_HEX_FIELD = {
  kind: ARIA_MARK.kind,
  shape: ARIA_MARK.shape,
  hexCount: ARIA_MARK.ringCount,
  radii: ARIA_MARK.radii,
  tiltDeg: ARIA_MARK.tiltDeg,
  opacity: ARIA_MARK.opacity,
} as const;

export const ARIA_RINGS = ARIA_MARK.radii.map((radius, index) => ({
  index,
  radius,
  tiltDeg: ARIA_MARK.tiltDeg[index] ?? 0,
  opacity: ARIA_MARK.opacity[index] ?? 0,
  pearl: index === 0,
}));

/** @deprecated Prefer `ARIA_RINGS`. */
export const ARIA_HEXES = ARIA_RINGS;

/** Web stand-in for the Swift smart-metal orb core. */
export const ARIA_ORB_CORE = {
  kind: "smart-metal",
  radius: 0.32,
  pearl: "#F7F4F0",
  pearlHot: "#FFFFFF",
} as const;

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

/**
 * Procedural kinetic orange/pearl ellipse nest — Watch Home wirefield language.
 * Three stroked ellipses around the mark center; white orb in the middle.
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

  ctx.clearRect(0, 0, width, height);

  const glow = ctx.createRadialGradient(cx, cy, size * 0.04, cx, cy, size * 0.48);
  glow.addColorStop(0, hexAlpha("#FFFFFF", 0.1));
  glow.addColorStop(0.35, hexAlpha(ARIA_MARK.brandHue, 0.16));
  glow.addColorStop(0.7, hexAlpha(ARIA_MARK.brandHue, 0.04));
  glow.addColorStop(1, hexAlpha(ARIA_MARK.brandHue, 0));
  ctx.fillStyle = glow;
  ctx.beginPath();
  ctx.arc(cx, cy, size * 0.48, 0, Math.PI * 2);
  ctx.fill();

  // Soft white orb core (web canvas stand-in for the smart-metal orb).
  const orb = ctx.createRadialGradient(cx, cy, size * 0.02, cx, cy, size * 0.17);
  orb.addColorStop(0, "rgba(255,255,255,0.98)");
  orb.addColorStop(0.4, "rgba(232,238,244,0.82)");
  orb.addColorStop(0.75, "rgba(247,244,240,0.35)");
  orb.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = orb;
  ctx.beginPath();
  ctx.arc(cx, cy, size * 0.17, 0, Math.PI * 2);
  ctx.fill();

  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = ringStrokeWidth(cssSize) * scale;

  for (const index of visibleRingIndices(cssSize)) {
    const pose = ringEllipse(index, input.time, input.speaking, input.reduceMotion);
    // Watch hue rhythm: pearl → orange-light → orange.
    const hue =
      index === 0
        ? "#FFFFFF"
        : index === 1
          ? ARIA_MARK.brandHueLight
          : ARIA_MARK.brandHue;
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(pose.rotation);
    ctx.strokeStyle = hexAlpha(hue, pose.opacity);
    ctx.beginPath();
    ctx.ellipse(0, 0, (pose.rx * size) / 2, (pose.ry * size) / 2, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }

  ctx.restore();
}

export {
  contrastRingIndices,
  ringEllipse,
  ringStrokeWidth,
  visibleRingIndices,
};
