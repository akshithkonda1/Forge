import {
  ARIA_MARK,
  contrastRingIndices,
  ringEllipse,
  ringStrokeWidth,
  visibleRingIndices,
} from "./aria-mark";

/** Lockstep export for the three soft-hex nest (Swift `AriaSigilGeometry`). */
export const ARIA_RING_FIELD = {
  kind: ARIA_MARK.kind,
  shape: ARIA_MARK.shape,
  ringCount: ARIA_MARK.ringCount,
  radii: ARIA_MARK.radii,
  eccentricity: ARIA_MARK.eccentricity,
  tiltDeg: ARIA_MARK.tiltDeg,
  opacity: ARIA_MARK.opacity,
  cornerRoundness: ARIA_MARK.cornerRoundness,
  idleOrbitHz: ARIA_MARK.idleOrbitHz,
  speakingOrbitHz: ARIA_MARK.speakingOrbitHz,
} as const;

/** @deprecated Prefer `ARIA_RING_FIELD`. */
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
  radius: 0.28,
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

/** Flat-top rounded-hexagon path in local coords (center origin). */
function strokeRoundedHexagon(
  ctx: CanvasRenderingContext2D,
  rx: number,
  ry: number,
  roundness: number
): void {
  const verts = Array.from({ length: 6 }, (_, i) => {
    const angle = (i * Math.PI) / 3;
    return { x: Math.cos(angle) * rx, y: Math.sin(angle) * ry };
  });
  const corner = Math.min(Math.min(rx, ry) * Math.max(0, Math.min(0.42, roundness)), Math.min(rx, ry) * 0.42);

  ctx.beginPath();
  for (let i = 0; i < 6; i += 1) {
    const prev = verts[(i + 5) % 6]!;
    const curr = verts[i]!;
    const next = verts[(i + 1) % 6]!;
    const toPrev = { x: prev.x - curr.x, y: prev.y - curr.y };
    const toNext = { x: next.x - curr.x, y: next.y - curr.y };
    const lenPrev = Math.hypot(toPrev.x, toPrev.y);
    const lenNext = Math.hypot(toNext.x, toNext.y);
    if (lenPrev < 0.001 || lenNext < 0.001) continue;
    const dPrev = Math.min(corner, lenPrev * 0.45);
    const dNext = Math.min(corner, lenNext * 0.45);
    const p1 = {
      x: curr.x + (toPrev.x / lenPrev) * dPrev,
      y: curr.y + (toPrev.y / lenPrev) * dPrev,
    };
    const p2 = {
      x: curr.x + (toNext.x / lenNext) * dNext,
      y: curr.y + (toNext.y / lenNext) * dNext,
    };
    if (i === 0) ctx.moveTo(p1.x, p1.y);
    else ctx.lineTo(p1.x, p1.y);
    ctx.quadraticCurveTo(curr.x, curr.y, p2.x, p2.y);
  }
  ctx.closePath();
  ctx.stroke();
}

/**
 * Procedural kinetic orange/pearl soft-hex nest — Watch Home wirefield language
 * with rounded hexagon strokes around a white orb.
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

  const glow = ctx.createRadialGradient(cx, cy, size * 0.03, cx, cy, size * 0.46);
  glow.addColorStop(0, hexAlpha("#FFFFFF", 0.14));
  glow.addColorStop(0.25, hexAlpha(ARIA_MARK.frostHue ?? "#9FD6FF", 0.1));
  glow.addColorStop(0.55, hexAlpha(ARIA_MARK.brandHue, 0.14));
  glow.addColorStop(1, hexAlpha(ARIA_MARK.brandHue, 0));
  ctx.fillStyle = glow;
  ctx.beginPath();
  ctx.arc(cx, cy, size * 0.48, 0, Math.PI * 2);
  ctx.fill();

  // Soft white orb core (web canvas stand-in for the smart-metal orb).
  const orb = ctx.createRadialGradient(cx, cy, size * 0.02, cx, cy, size * 0.145);
  orb.addColorStop(0, "rgba(255,255,255,0.98)");
  orb.addColorStop(0.4, "rgba(232,238,244,0.82)");
  orb.addColorStop(0.75, "rgba(247,244,240,0.35)");
  orb.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = orb;
  ctx.beginPath();
  ctx.arc(cx, cy, size * 0.145, 0, Math.PI * 2);
  ctx.fill();

  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = ringStrokeWidth(cssSize) * scale;

  // Faint orbital plane.
  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate((12 * Math.PI) / 180);
  ctx.strokeStyle = hexAlpha("#6B7CFF", 0.12);
  ctx.lineWidth = Math.max(0.6, size * 0.004);
  ctx.beginPath();
  ctx.ellipse(0, 0, size * 0.36, size * 0.11, 0, 0, Math.PI * 2);
  ctx.stroke();
  ctx.restore();

  for (const index of visibleRingIndices(cssSize)) {
    const pose = ringEllipse(index, input.time, input.speaking, input.reduceMotion);
    const hue =
      index === 0
        ? "#FFFFFF"
        : index === 1
          ? (ARIA_MARK.frostHue ?? "#9FD6FF")
          : ARIA_MARK.brandHue;
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(pose.rotation);
    // Soft bloom.
    ctx.lineWidth = ringStrokeWidth(cssSize) * scale * 2.1;
    ctx.strokeStyle = hexAlpha(hue, pose.opacity * 0.28);
    strokeRoundedHexagon(
      ctx,
      (pose.rx * size) / 2,
      (pose.ry * size) / 2,
      ARIA_MARK.cornerRoundness
    );
    // Crisp wire.
    ctx.lineWidth = ringStrokeWidth(cssSize) * scale;
    ctx.strokeStyle = hexAlpha(hue, Math.min(1, pose.opacity + 0.08));
    strokeRoundedHexagon(
      ctx,
      (pose.rx * size) / 2,
      (pose.ry * size) / 2,
      ARIA_MARK.cornerRoundness
    );
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
