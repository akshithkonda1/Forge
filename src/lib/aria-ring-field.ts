import {
  ARIA_MARK,
  contrastRingIndices,
  ringEllipse,
  ringStrokeWidth,
  visibleRingIndices,
} from "./aria-mark";

export type RingFieldDrawInput = {
  time: number;
  speaking: boolean;
  reduceMotion: boolean;
  /** CSS pixel size — drives stroke and compact/hero ring count. */
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
 * Retired kinetic ring-field stopgap. Living identity is soft-hex nest + metal
 * sun (`ARIA_MARK.kind === "soft-hex-field"`). Wren's canvas chase replaces this.
 * Stroked ellipses only — no gooey lobes, no circular frame, no readiness trim.
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

  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = ringStrokeWidth(cssSize) * scale;

  for (const index of visibleRingIndices(cssSize)) {
    const pose = ringEllipse(index, input.time, input.speaking, input.reduceMotion);
    const hue = highlight.has(index) ? ARIA_MARK.brandHueLight : ARIA_MARK.brandHue;
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
