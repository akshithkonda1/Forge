"use client";

import { useEffect, useRef } from "react";
import { cn } from "@/lib/utils";
import {
  drawForgeFire,
  forgeFirePaintDue,
  forgeFireWash,
  type ForgeFireIntensity,
  type ForgeFireOrigin,
} from "@/lib/forge-fire";

export function ForgeFireField({
  intensity = "rage",
  origin = "floor",
  live = false,
  className,
}: {
  intensity?: ForgeFireIntensity;
  origin?: ForgeFireOrigin;
  /** One live canvas per screen. Wash-only layers skip the painter. */
  live?: boolean;
  className?: string;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    if (!live) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    let raf = 0;
    let lastPaint = -1;
    const start = performance.now();

    const resize = () => {
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      const rect = canvas.getBoundingClientRect();
      const w = Math.max(1, Math.round(rect.width * dpr));
      const h = Math.max(1, Math.round(rect.height * dpr));
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
        return true;
      }
      return false;
    };

    const paint = (now: number) => {
      const reduce = media.matches;
      if (!reduce && !forgeFirePaintDue(now, lastPaint)) {
        raf = requestAnimationFrame(paint);
        return;
      }
      lastPaint = now;
      resize();
      const t = reduce ? 0.18 : (now - start) / 1000;
      drawForgeFire(ctx, canvas.width, canvas.height, {
        time: t,
        intensity,
        origin,
        reduceMotion: reduce,
      });
      if (!reduce) raf = requestAnimationFrame(paint);
    };

    paint(start);
    const ro = new ResizeObserver(() => {
      if (resize()) paint(performance.now());
    });
    ro.observe(canvas);
    const onMotionPref = () => {
      cancelAnimationFrame(raf);
      paint(performance.now());
    };
    media.addEventListener("change", onMotionPref);
    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      media.removeEventListener("change", onMotionPref);
    };
  }, [intensity, origin, live]);

  return (
    <div className={cn("pointer-events-none absolute inset-0 overflow-hidden", className)} aria-hidden>
      <div className="absolute inset-0" style={{ background: forgeFireWash(origin) }} />
      {live ? <canvas ref={canvasRef} className="absolute inset-0 h-full w-full" /> : null}
    </div>
  );
}

export function ForgeBrandFlame({
  size = 22,
  className,
}: {
  size?: number;
  className?: string;
}) {
  return (
    <div
      className={cn("relative shrink-0 overflow-hidden", className)}
      style={{ width: size, height: size * 1.28 }}
      aria-hidden
    >
      <ForgeFireField intensity="rage" origin="hearth" />
    </div>
  );
}
