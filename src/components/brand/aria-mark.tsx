"use client";

import { useEffect, useRef } from "react";
import { cn } from "@/lib/utils";
import { ARIA_MARK, clampGaze } from "@/lib/aria-mark";
import { drawAriaEmber } from "@/lib/aria-ember";

/**
 * Adaptive Recovery Interactive Assistant — living 4-lobe ember.
 * Canvas blob that follows the pointer. No ping rings. PNG is unused at runtime.
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
  const gaze = useRef({ x: 0, y: 0, tx: 0, ty: 0 });
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
    const start = performance.now();

    const paint = (now: number) => {
      const reduce = media.matches;
      if (reduce) {
        gaze.current.x = 0;
        gaze.current.y = 0;
        gaze.current.tx = 0;
        gaze.current.ty = 0;
      } else {
        gaze.current.x += (gaze.current.tx - gaze.current.x) * 0.14;
        gaze.current.y += (gaze.current.ty - gaze.current.y) * 0.14;
      }
      const t = reduce ? ARIA_MARK.stillPose : (now - start) / 1000;
      drawAriaEmber(ctx, canvas.width, canvas.height, {
        time: t,
        speaking: speakingRef.current,
        gazeX: gaze.current.x,
        gazeY: gaze.current.y,
        reduceMotion: reduce,
      });
      if (!reduce) raf = requestAnimationFrame(paint);
    };

    const followPointer = (event: PointerEvent) => {
      if (media.matches) return;
      const box = canvas.getBoundingClientRect();
      const reach = Math.max(box.width, 48);
      gaze.current.tx = clampGaze((event.clientX - (box.left + box.width / 2)) / reach);
      gaze.current.ty = clampGaze((event.clientY - (box.top + box.height / 2)) / reach);
    };

    const restGaze = () => {
      gaze.current.tx = 0;
      gaze.current.ty = 0;
    };

    const onMotionPref = () => {
      cancelAnimationFrame(raf);
      paint(performance.now());
    };

    paint(start);
    window.addEventListener("pointermove", followPointer, { passive: true });
    window.addEventListener("blur", restGaze);
    document.documentElement.addEventListener("mouseleave", restGaze);
    media.addEventListener("change", onMotionPref);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("pointermove", followPointer);
      window.removeEventListener("blur", restGaze);
      document.documentElement.removeEventListener("mouseleave", restGaze);
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
