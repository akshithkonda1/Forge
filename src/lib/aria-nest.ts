import {
  ARIA_MARK,
  ARIA_MARK_COMPACT_MAX,
  metalSunPose,
  nestRingPose,
  ringStrokeWidth,
  visibleRingIndices,
} from "./aria-mark";

export type NestDrawInput = {
  time: number;
  speaking: boolean;
  reduceMotion: boolean;
  /** CSS pixel size — drives stroke, compact hearth skip, and live/still. */
  cssSize: number;
};

export function hexAlpha(hex: string, alpha: number): string {
  const n = hex.replace("#", "");
  const r = Number.parseInt(n.slice(0, 2), 16);
  const g = Number.parseInt(n.slice(2, 4), 16);
  const b = Number.parseInt(n.slice(4, 6), 16);
  const a = Math.max(0, Math.min(1, alpha));
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}

/**
 * Soft-hex silhouette: 6-fold rounded nest + liquid radial undulation.
 * Closed stroke only — no flower lobes, no ellipse-field, no industrial chrome.
 */
export function strokeSoftHex(
  ctx: CanvasRenderingContext2D,
  rx: number,
  ry: number,
  roundness: number,
  wavePhase: number,
  waveAmp: number
): void {
  const samples = 72;
  const soft = Math.max(0.12, Math.min(0.42, roundness));
  ctx.beginPath();
  for (let i = 0; i <= samples; i += 1) {
    const t = i / samples;
    const angle = t * Math.PI * 2;
    const hexBias = 1 + (1 - soft) * 0.1 * Math.cos(6 * angle);
    const liquid =
      1 +
      waveAmp *
        (0.55 * Math.sin(6 * angle + wavePhase) +
          0.28 * Math.sin(3 * angle - wavePhase * 1.35) +
          0.17 * Math.sin(9 * angle + wavePhase * 0.72));
    const x = Math.cos(angle) * rx * hexBias * liquid;
    const y = Math.sin(angle) * ry * hexBias * liquid;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.stroke();
}

function fillHearth(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  size: number,
  speaking: boolean
): void {
  const wash = Math.min(ARIA_MARK.hearthSpecularMax, speaking ? 0.32 : 0.22);
  const hearth = ctx.createRadialGradient(cx, cy, size * 0.04, cx, cy, size * 0.48);
  hearth.addColorStop(0, hexAlpha(ARIA_MARK.hearthGlowHex, wash));
  hearth.addColorStop(0.45, hexAlpha(ARIA_MARK.brandHue, Math.min(ARIA_MARK.hearthSpecularMax, wash * 0.45)));
  hearth.addColorStop(1, hexAlpha(ARIA_MARK.brandHue, 0));
  ctx.fillStyle = hearth;
  ctx.beginPath();
  ctx.arc(cx, cy, size * 0.48, 0, Math.PI * 2);
  ctx.fill();
}

function fillMetalSun(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  size: number,
  speaking: boolean,
  reduceMotion: boolean,
  time: number
): void {
  const sun = metalSunPose(time, speaking, reduceMotion);
  const diameter = sun.diameter * size;
  const radius = (diameter / 2) * Math.max(sun.sx, sun.sy);

  const bloom = ctx.createRadialGradient(cx, cy, radius * 0.15, cx, cy, radius * 1.65);
  bloom.addColorStop(0, hexAlpha(ARIA_MARK.pearlHotHex, 0.28 + sun.glow * 0.18));
  bloom.addColorStop(0.55, hexAlpha(ARIA_MARK.pearlHex, 0.1));
  bloom.addColorStop(1, hexAlpha(ARIA_MARK.pearlHex, 0));
  ctx.fillStyle = bloom;
  ctx.beginPath();
  ctx.arc(cx, cy, radius * 1.65, 0, Math.PI * 2);
  ctx.fill();

  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(sun.sx, sun.sy);
  const body = ctx.createRadialGradient(
    -radius * 0.22,
    -radius * 0.28,
    radius * 0.04,
    0,
    0,
    radius
  );
  body.addColorStop(0, hexAlpha(ARIA_MARK.pearlHotHex, 0.99));
  body.addColorStop(0.42, hexAlpha(ARIA_MARK.pearlHex, 0.94));
  body.addColorStop(1, hexAlpha(ARIA_MARK.pearlHex, 0.55));
  ctx.fillStyle = body;
  ctx.beginPath();
  ctx.arc(0, 0, radius, 0, Math.PI * 2);
  ctx.fill();

  const spec = ctx.createRadialGradient(
    -radius * 0.28,
    -radius * 0.34,
    0,
    -radius * 0.22,
    -radius * 0.3,
    radius * 0.42
  );
  spec.addColorStop(0, hexAlpha(ARIA_MARK.pearlHotHex, 0.85 * sun.highlight));
  spec.addColorStop(1, hexAlpha(ARIA_MARK.pearlHotHex, 0));
  ctx.fillStyle = spec;
  ctx.beginPath();
  ctx.ellipse(-radius * 0.18, -radius * 0.22, radius * 0.34, radius * 0.2, sun.sheenAngle * 0.15, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

/**
 * B+E living brand mark: 3-ring soft-hex nest + pearl metal sun.
 * Compact skips hearth so the wash is never the silhouette.
 */
export function drawAriaNest(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  input: NestDrawInput
): void {
  const size = Math.min(width, height);
  const cx = width / 2;
  const cy = height / 2;
  const cssSize = input.cssSize;
  const scale = cssSize > 0 ? size / cssSize : 1;
  const compact = cssSize <= ARIA_MARK_COMPACT_MAX;

  ctx.clearRect(0, 0, width, height);

  if (!compact) {
    fillHearth(ctx, cx, cy, size, input.speaking);
  }

  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = ringStrokeWidth(cssSize) * scale;

  for (const index of visibleRingIndices(cssSize)) {
    const pose = nestRingPose(index, input.time, input.speaking, input.reduceMotion);
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(pose.rotation);
    ctx.strokeStyle = hexAlpha(pose.hex, pose.opacity);
    strokeSoftHex(
      ctx,
      (pose.rx * size) / 2,
      (pose.ry * size) / 2,
      ARIA_MARK.cornerRoundness,
      pose.wavePhase,
      pose.waveAmp
    );
    ctx.restore();
  }

  ctx.restore();

  fillMetalSun(ctx, cx, cy, size, input.speaking, input.reduceMotion, input.time);
}
