/** Procedural Forge fire. Welcome / splash only — not the ARIA ring-field.
 *  Lockstep with `ForgeFireGeometry` on iOS.
 */
export const FORGE_FIRE = {
  kind: "rage-fire",
  tickHz: 12,
  rage: { tongueCount: 28, sparkCount: 24, heightScale: 1, coreHeat: 0.94 },
  ember: { tongueCount: 8, sparkCount: 6, heightScale: 0.34, coreHeat: 0.28 },
} as const;

/** First frame always paints (`lastPaintMs < 0`). Later frames cap near 12 Hz. */
export function forgeFirePaintDue(nowMs: number, lastPaintMs: number): boolean {
  if (lastPaintMs < 0) return true;
  return nowMs - lastPaintMs >= 1000 / FORGE_FIRE.tickHz;
}

export function forgeFireWash(origin: ForgeFireOrigin): string {
  return origin === "floor"
    ? "radial-gradient(ellipse 80% 55% at 50% 100%, rgba(255,90,10,0.55) 0%, rgba(255,40,0,0.18) 38%, transparent 70%)"
    : "radial-gradient(circle at 50% 62%, rgba(255,176,32,0.42) 0%, rgba(255,77,0,0.22) 40%, transparent 68%)";
}

export type ForgeFireIntensity = "ember" | "rage";
export type ForgeFireOrigin = "floor" | "hearth";

export type ForgeFireTongue = {
  baseX: number;
  baseY: number;
  tipX: number;
  tipY: number;
  width: number;
  heat: number;
  waver: number;
};

export type ForgeFireSpark = {
  x: number;
  y: number;
  radius: number;
  opacity: number;
};

function hash01(seed: number): number {
  const n = Math.sin(seed * 12.9898) * 43758.5453;
  return n - Math.floor(n);
}

export function fireSpec(intensity: ForgeFireIntensity) {
  return intensity === "rage" ? FORGE_FIRE.rage : FORGE_FIRE.ember;
}

export function fireTongue(
  index: number,
  count: number,
  time: number,
  intensity: ForgeFireIntensity,
  origin: ForgeFireOrigin,
  reduceMotion: boolean
): ForgeFireTongue {
  const spec = fireSpec(intensity);
  const i = Math.max(0, Math.min(Math.max(count - 1, 0), index));
  const seed = i * 17.13;
  const t = reduceMotion ? 0.18 : time;
  const n = Math.max(count, 1);
  const lane = i / (n - 1 === 0 ? 1 : n - 1);
  const flicker = reduceMotion
    ? 0.78
    : 0.62 + 0.38 * (0.5 + 0.5 * Math.sin(t * (2.4 + (i % 5) * 0.35) + seed));
  const rise = (0.22 + 0.7 * hash01(seed + 2.1)) * spec.heightScale * flicker;

  if (origin === "hearth") {
    const angle = lane * Math.PI * 1.15 + Math.PI * 0.42;
    const reach = (0.22 + 0.38 * hash01(seed)) * spec.heightScale * flicker;
    const cx = 0.5 + (reduceMotion ? 0 : 0.02 * Math.sin(t * 1.4 + seed));
    const cy = 0.62;
    const waver = reduceMotion ? 0 : 0.04 * Math.sin(t * 3.6 + seed);
    return {
      baseX: cx + Math.cos(angle) * 0.08,
      baseY: cy,
      tipX: cx + Math.cos(angle) * reach + waver,
      tipY: cy - Math.sin(angle * 0.35 + 0.9) * reach * 1.15,
      width: (0.04 + 0.03 * hash01(seed + 8)) * spec.heightScale,
      heat: spec.coreHeat * (0.7 + 0.3 * flicker),
      waver,
    };
  }

  const baseX = 0.06 + lane * 0.88 + (reduceMotion ? 0 : 0.03 * Math.sin(t * 1.7 + seed));
  const baseY = 0.94 + 0.04 * hash01(seed + 11);
  const waver = reduceMotion ? 0 : 0.055 * Math.sin(t * 3.2 + seed);
  return {
    baseX,
    baseY,
    tipX: baseX + waver * 1.55,
    tipY: baseY - rise,
    width: (0.034 + 0.055 * hash01(seed + 4)) * (0.75 + 0.55 * spec.heightScale),
    heat: spec.coreHeat * (0.72 + 0.28 * flicker),
    waver,
  };
}

export function fireSpark(
  index: number,
  time: number,
  intensity: ForgeFireIntensity,
  reduceMotion: boolean
): ForgeFireSpark {
  const seed = index * 23.71;
  if (reduceMotion) {
    return { x: hash01(seed), y: 0.55 + hash01(seed + 1) * 0.35, radius: 0.004, opacity: 0.12 };
  }
  const speed = 0.18 + (index % 7) * 0.04;
  const travel = (time * speed + hash01(seed)) % 1;
  const lift = intensity === "rage" ? 1 : 0.45;
  return {
    x: hash01(seed + 3) * 0.92 + 0.04 + 0.04 * Math.sin(time * 2.8 + seed),
    y: 1.05 - travel * (0.85 * lift),
    radius: 0.003 + hash01(seed + 5) * (intensity === "rage" ? 0.007 : 0.003),
    opacity:
      (intensity === "rage" ? 0.55 : 0.18) * (1 - travel) * (0.55 + 0.45 * hash01(seed + 9)),
  };
}

function flamePath(
  ctx: CanvasRenderingContext2D,
  baseX: number,
  baseY: number,
  tipX: number,
  tipY: number,
  width: number,
  waver: number
): void {
  const h = baseY - tipY;
  const yBulge = baseY - h * 0.28;
  const yWaist = baseY - h * 0.62;
  const bulge = width * 1.45;
  const waist = width * 0.55;
  ctx.beginPath();
  ctx.moveTo(baseX - width * 0.55, baseY);
  ctx.quadraticCurveTo(baseX - bulge + waver * 0.4, yBulge, baseX - waist + waver, yWaist);
  ctx.quadraticCurveTo(baseX - waist * 0.4 + waver * 1.2, (yWaist + tipY) / 2, tipX, tipY);
  ctx.quadraticCurveTo(baseX + waist * 0.4 + waver * 1.2, (yWaist + tipY) / 2, baseX + waist + waver, yWaist);
  ctx.quadraticCurveTo(baseX + bulge + waver * 0.4, yBulge, baseX + width * 0.55, baseY);
  ctx.closePath();
}

export function drawForgeFire(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  input: {
    time: number;
    intensity: ForgeFireIntensity;
    origin: ForgeFireOrigin;
    reduceMotion: boolean;
  }
): void {
  if (width < 2 || height < 2) return;
  ctx.clearRect(0, 0, width, height);
  ctx.save();
  ctx.globalCompositeOperation = "lighter";

  const spec = fireSpec(input.intensity);
  const heat = input.intensity === "rage" ? 0.42 : 0.12;
  const gx = width * 0.5;
  const gy = input.origin === "floor" ? height * 0.92 : height * 0.58;
  const gr = input.origin === "floor" ? height * 0.62 : width * 0.48;
  const glow = ctx.createRadialGradient(gx, gy, 8, gx, gy, gr);
  glow.addColorStop(0, `rgba(255, 107, 43, ${heat})`);
  glow.addColorStop(0.45, `rgba(255, 77, 0, ${heat * 0.45})`);
  glow.addColorStop(1, "rgba(255, 77, 0, 0)");
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, width, height);

  if (input.origin === "floor" && input.intensity === "rage") {
    const bed = ctx.createRadialGradient(width * 0.5, height * 0.96, 4, width * 0.5, height * 0.96, width * 0.48);
    bed.addColorStop(0, "rgba(255, 226, 138, 0.35)");
    bed.addColorStop(0.45, "rgba(255, 77, 0, 0.28)");
    bed.addColorStop(1, "rgba(255, 77, 0, 0)");
    ctx.fillStyle = bed;
    ctx.beginPath();
    ctx.ellipse(width * 0.5, height * 0.92, width * 0.42, height * 0.14, 0, 0, Math.PI * 2);
    ctx.fill();
  }

  const drawTongues = (offset: number, outer: boolean) => {
    for (let i = 0; i < spec.tongueCount; i++) {
      const tongue = fireTongue(
        i,
        spec.tongueCount,
        input.time + offset,
        input.intensity,
        input.origin,
        input.reduceMotion
      );
      const baseX = tongue.baseX * width;
      const baseY = tongue.baseY * height;
      const tipX = tongue.tipX * width;
      const tipY = tongue.tipY * height;
      const w = tongue.width * width * (outer ? 1 : 0.46);
      const waver = tongue.waver * width;
      flamePath(ctx, baseX, baseY, tipX, tipY, w, waver);
      const g = ctx.createLinearGradient(baseX, baseY, tipX, tipY);
      if (outer) {
        g.addColorStop(0, `rgba(255, 42, 0, ${0.22 + tongue.heat * 0.2})`);
        g.addColorStop(0.55, `rgba(255, 77, 0, ${0.55 + tongue.heat * 0.25})`);
        g.addColorStop(1, "rgba(255, 176, 32, 0.15)");
      } else {
        g.addColorStop(0, `rgba(255, 107, 43, ${0.55 + tongue.heat * 0.3})`);
        g.addColorStop(0.55, `rgba(255, 226, 138, ${0.45 + tongue.heat * 0.5})`);
        g.addColorStop(1, `rgba(255, 255, 255, ${0.12 + tongue.heat * 0.35})`);
      }
      ctx.fillStyle = g;
      ctx.fill();
    }
  };

  drawTongues(0, true);
  drawTongues(0.07, false);

  for (let i = 0; i < spec.sparkCount; i++) {
    const spark = fireSpark(i, input.time, input.intensity, input.reduceMotion);
    const r = spark.radius * Math.min(width, height);
    ctx.beginPath();
    ctx.arc(spark.x * width, spark.y * height, r, 0, Math.PI * 2);
    const hot = input.intensity === "rage";
    ctx.fillStyle = `rgba(255, ${hot ? 235 : 140}, ${hot ? 140 : 46}, ${spark.opacity})`;
    ctx.fill();
  }

  ctx.restore();
}
