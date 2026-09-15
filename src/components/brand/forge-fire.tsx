"use client";

import { useEffect, useRef } from "react";
import { cn } from "@/lib/utils";
import {
  drawForgeFire,
  type ForgeFireIntensity,
  type ForgeFireOrigin,
} from "@/lib/forge-fire";

export function ForgeFireField({
  intensity = "rage",
  origin = "floor",
  className,
}: {
  intensity?: ForgeFireIntensity;
  origin?: ForgeFireOrigin;
  className?: string;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    let raf = 0;
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
      resize();
      const reduce = media.matches;
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
    media.addEventListener("change", () => {
      cancelAnimationFrame(raf);
      paint(performance.now());
    });
    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
    };
  }, [intensity, origin]);

  const wash =
    origin === "floor"
      ? "radial-gradient(ellipse 80% 55% at 50% 100%, rgba(255,90,10,0.55) 0%, rgba(255,40,0,0.18) 38%, transparent 70%)"
      : "radial-gradient(circle at 50% 62%, rgba(255,176,32,0.42) 0%, rgba(255,77,0,0.22) 40%, transparent 68%)";

  return (
    <div className={cn("pointer-events-none absolute inset-0 overflow-hidden", className)} aria-hidden>
      <div className="absolute inset-0" style={{ background: wash }} />
      <canvas ref={canvasRef} className="absolute inset-0 h-full w-full" />
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
