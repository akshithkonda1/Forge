import {
  ARIA_MARK,
  ARIA_MARK_CONTRAST_FLOOR,
  ARIA_ORB_CORE,
  ariaMarkShouldGlow,
  contrastRingIndices,
  orbCoreRadius,
  ringEllipse,
  ringStrokeWidth,
  visibleRingIndices,
} from "./aria-mark";

export type RingFieldDrawInput = {
  time: number;
  speaking: boolean;
  reduceMotion: boolean;
  /** CSS pixel size — drives stroke, haze, orb nest, and compact vs full ring count. */
  cssSize: number;
};

/** Draw-time life. Does not change `ringEllipse` / shared/aria-mark.json. */
export const ARIA_MARK_LIFE = {
  tickHz: 12,
} as const;

export function ringWobble(index: number, time: number, reduceMotion: boolean): number {
  if (reduceMotion) return 0;
  const phase = (ARIA_MARK.phaseOffsets[index] ?? 0) * Math.PI * 2;
  return 0.09 * Math.sin(time * 1.55 + phase);
}

/**
 * Contrast rings (contract opacities ≥ 0.70) keep a flicker wave, but the
 * multiplier is floored so painted opacity never drops below the Cove floor.
 */
export function ringFlicker(index: number, time: number, reduceMotion: boolean): number {
  if (reduceMotion) return 1;
  const phase = (ARIA_MARK.phaseOffsets[index] ?? 0) * Math.PI * 2;
  const wave = 0.78 + 0.22 * (0.5 + 0.5 * Math.sin(time * 3.4 + phase));
  const base = ARIA_MARK.opacity[index] ?? 0;
  if (base >= ARIA_MARK_CONTRAST_FLOOR) {
    return Math.max(wave, ARIA_MARK_CONTRAST_FLOOR / base);
  }
  return wave;
}

export function paintedRingOpacity(
  index: number,
  time: number,
  reduceMotion: boolean
): number {
  const base = ARIA_MARK.opacity[index] ?? 0;
  return base * ringFlicker(index, time, reduceMotion);
}

export function ringGlowPulse(time: number, energy: number, reduceMotion: boolean): number {
  if (reduceMotion) return 1;
  const wave = 0.5 + 0.5 * Math.sin(time * 2.1);
  return 0.7 + 0.3 * wave * (0.5 + Math.max(0, Math.min(1, energy)));
}

export function ringBreathScale(time: number, hero: boolean, reduceMotion: boolean): number {
  if (reduceMotion || !hero) return 1;
  return 1 + 0.028 * Math.sin(time * 2.35);
}

function hexAlpha(hex: string, alpha: number): string {
  const n = hex.replace("#", "");
  const r = Number.parseInt(n.slice(0, 2), 16);
  const g = Number.parseInt(n.slice(2, 4), 16);
  const b = Number.parseInt(n.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function drawWhiteOrb(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  size: number,
  cssSize: number,
  speaking: boolean
): void {
  const energy = speaking ? 1 : 0.72;
  const r = orbCoreRadius(cssSize) * size;
  const hx = cx - r * 0.32;
  const hy = cy - r * 0.38;

  const bloom = ctx.createRadialGradient(cx, cy, r * 0.2, cx, cy, r * 2.35);
  bloom.addColorStop(0, `rgba(255, 255, 255, ${0.42 * energy})`);
  bloom.addColorStop(0.28, hexAlpha(ARIA_ORB_CORE.hueSoft, 0.16 * energy));
  bloom.addColorStop(0.55, hexAlpha(ARIA_MARK.brandHue, 0.1 * energy));
  bloom.addColorStop(1, hexAlpha(ARIA_MARK.brandHue, 0));
  ctx.fillStyle = bloom;
  ctx.beginPath();
  ctx.arc(cx, cy, r * 2.35, 0, Math.PI * 2);
  ctx.fill();

  const body = ctx.createRadialGradient(hx, hy, r * 0.04, cx + r * 0.12, cy + r * 0.18, r);
  body.addColorStop(0, hexAlpha(ARIA_ORB_CORE.hue, 0.98));
  body.addColorStop(0.18, hexAlpha(ARIA_ORB_CORE.hue, 0.92));
  body.addColorStop(0.42, hexAlpha(ARIA_ORB_CORE.hueSoft, 0.78));
  body.addColorStop(0.7, `rgba(214, 224, 240, ${0.38 * energy})`);
  body.addColorStop(0.88, hexAlpha(ARIA_MARK.brandHueLight, 0.14));
  body.addColorStop(1, hexAlpha(ARIA_MARK.brandHue, 0));
  ctx.fillStyle = body;
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fill();

  const limb = ctx.createRadialGradient(cx, cy, r * 0.62, cx, cy, r);
  limb.addColorStop(0, "rgba(255, 255, 255, 0)");
  limb.addColorStop(0.65, `rgba(255, 255, 255, ${0.08 * energy})`);
  limb.addColorStop(1, hexAlpha(ARIA_MARK.brandHueLight, 0.22 * energy));
  ctx.fillStyle = limb;
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fill();

  const spec = ctx.createRadialGradient(hx, hy, 0, hx, hy, r * 0.46);
  spec.addColorStop(0, "rgba(255, 255, 255, 0.95)");
  spec.addColorStop(0.28, "rgba(255, 255, 255, 0.45)");
  spec.addColorStop(1, "rgba(255, 255, 255, 0)");
  ctx.fillStyle = spec;
  ctx.beginPath();
  ctx.arc(hx, hy, r * 0.46, 0, Math.PI * 2);
  ctx.fill();
}

/**
 * Retired kinetic ring-field stopgap. Living identity is soft-hex nest + metal
 * sun (`ARIA_MARK.kind === "soft-hex-field"`). Wren's canvas chase replaces this.
 * White orb is the current metal-sun stand-in. No gooey lobes, no circular
 * frame, no readiness trim.
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

  if (ariaMarkShouldGlow(cssSize)) {
    const haze = ctx.createRadialGradient(cx, cy, size * 0.08, cx, cy, size * 0.48);
    haze.addColorStop(0, hexAlpha(ARIA_MARK.brandHue, 0.08));
    haze.addColorStop(0.65, hexAlpha(ARIA_MARK.brandHue, 0.03));
    haze.addColorStop(1, hexAlpha(ARIA_MARK.brandHue, 0));
    ctx.fillStyle = haze;
    ctx.beginPath();
    ctx.arc(cx, cy, size * 0.48, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = ringStrokeWidth(cssSize) * scale;

  for (const index of visibleRingIndices(cssSize)) {
    const pose = ringEllipse(index, input.time, input.speaking, input.reduceMotion);
    const hue = highlight.has(index) ? ARIA_MARK.brandHueLight : ARIA_MARK.brandHue;
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(pose.rotation + ringWobble(index, input.time, input.reduceMotion));
    ctx.strokeStyle = hexAlpha(hue, paintedRingOpacity(index, input.time, input.reduceMotion));
    ctx.beginPath();
    ctx.ellipse(0, 0, (pose.rx * size) / 2, (pose.ry * size) / 2, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }

  ctx.restore();
  drawWhiteOrb(ctx, cx, cy, size, cssSize, input.speaking);
}
