"use client";

import { useEffect, useRef } from "react";
import { cn } from "@/lib/utils";
import { ARIA_MARK, ariaMarkPaintDue, ariaMarkShouldSpin } from "@/lib/aria-mark";
import { drawAriaRingField } from "@/lib/aria-ring-field";

/**
 * Adaptive Recovery Interactive Assistant.
 * Living mark is the kinetic ring-field in `ARIA_MARK` / `shared/aria-mark.json`
 * with a white intelligence orb at the core. Procedural canvas only.
 */
export function AriaMark({
  size = 48,
  speaking = false,
  className,
  label,
}: {
  size?: number;
  speaking?: boolean;
  className?: string;
  label?: string;
}) {
  const hero = size >= ARIA_MARK.heroMinimumSize;
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const speakingRef = useRef(speaking);
  speakingRef.current = speaking;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.max(1, Math.round(size * dpr));
    canvas.height = Math.max(1, Math.round(size * dpr));
    canvas.style.width = `${size}px`;
    canvas.style.height = `${size}px`;

    let raf = 0;
    let lastPaint = -1;
    const start = performance.now();

    const paint = (now: number) => {
      const reduce = !ariaMarkShouldSpin(size, media.matches);
      if (!reduce && !ariaMarkPaintDue(now, lastPaint)) {
        raf = requestAnimationFrame(paint);
        return;
      }
      lastPaint = now;
      const t = reduce ? 0 : (now - start) / 1000;
      drawAriaRingField(ctx, canvas.width, canvas.height, {
        time: t,
        speaking: speakingRef.current,
        reduceMotion: reduce,
        cssSize: size,
      });
      if (!reduce) raf = requestAnimationFrame(paint);
    };

    const onMotionPref = () => {
      cancelAnimationFrame(raf);
      paint(performance.now());
    };

    paint(start);
    media.addEventListener("change", onMotionPref);
    return () => {
      cancelAnimationFrame(raf);
      media.removeEventListener("change", onMotionPref);
    };
  }, [size]);

  return (
    <div
      className={cn("relative shrink-0", className)}
      style={{ width: size, height: size }}
      aria-hidden={hero ? undefined : true}
      aria-label={hero ? label ?? "ARIA" : undefined}
      role={hero ? "img" : undefined}
    >
      <canvas ref={canvasRef} className="block h-full w-full" />
    </div>
  );
}
