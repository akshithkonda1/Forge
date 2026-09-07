import {
  ARIA_LOBES,
  clampGaze,
  emberCoreRadius,
  emberLobe,
} from "./aria-mark";

export type EmberDrawInput = {
  time: number;
  speaking: boolean;
  gazeX: number;
  gazeY: number;
  reduceMotion: boolean;
};

/** Procedural 4-lobe gooey ember. No ping rings. */
export function drawAriaEmber(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  input: EmberDrawInput
): void {
  const size = Math.min(width, height);
  const cx = width / 2;
  const cy = height / 2;
  const gx = clampGaze(input.gazeX);
  const gy = clampGaze(input.gazeY);

  ctx.clearRect(0, 0, width, height);
  ctx.save();
  ctx.globalCompositeOperation = "lighter";

  for (let i = 0; i < ARIA_LOBES.length; i++) {
    const lobe = emberLobe(i, input.time, input.speaking, input.reduceMotion);
    const lx = cx + (lobe.x + gx) * size * 0.5;
    const ly = cy + (lobe.y + gy) * size * 0.5;
    const r = lobe.r * size * 0.5;
    const g = ctx.createRadialGradient(lx, ly, 0, lx, ly, r);
    g.addColorStop(0, "rgba(255, 226, 138, 0.95)");
    g.addColorStop(0.22, "rgba(255, 106, 26, 0.82)");
    g.addColorStop(0.55, "rgba(168, 85, 247, 0.42)");
    g.addColorStop(0.82, "rgba(34, 211, 238, 0.28)");
    g.addColorStop(1, "rgba(34, 211, 238, 0)");
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(lx, ly, r, 0, Math.PI * 2);
    ctx.fill();
  }

  const coreR = emberCoreRadius(input.time, input.speaking, input.reduceMotion) * size;
  const core = ctx.createRadialGradient(cx + gx * size * 0.5, cy + gy * size * 0.5, 0, cx, cy, coreR);
  core.addColorStop(0, input.speaking ? "rgba(255, 250, 220, 0.95)" : "rgba(255, 236, 170, 0.85)");
  core.addColorStop(0.35, "rgba(255, 106, 26, 0.55)");
  core.addColorStop(1, "rgba(255, 106, 26, 0)");
  ctx.fillStyle = core;
  ctx.beginPath();
  ctx.arc(cx + gx * size * 0.35, cy + gy * size * 0.35, coreR, 0, Math.PI * 2);
  ctx.fill();

  const specX = cx + gx * size * 0.2 - size * 0.08;
  const specY = cy + gy * size * 0.2 - size * 0.1;
  const spec = ctx.createRadialGradient(specX, specY, 0, specX, specY, size * 0.08);
  spec.addColorStop(0, "rgba(255, 255, 255, 0.55)");
  spec.addColorStop(1, "rgba(255, 255, 255, 0)");
  ctx.fillStyle = spec;
  ctx.beginPath();
  ctx.arc(specX, specY, size * 0.08, 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();
}
