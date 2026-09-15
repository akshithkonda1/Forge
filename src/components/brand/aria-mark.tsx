"use client";

import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import {
  ARIA_MARK,
  ariaMarkShouldSpin,
  nestLiveCreateId,
  nestLiveIsWinner,
  nestLiveRemove,
  nestLiveUpsert,
  NEST_PAINT_INTERVAL_MS,
} from "@/lib/aria-mark";
import { drawAriaNest } from "@/lib/aria-nest";

/**
 * Adaptive Recovery Interactive Assistant.
 * Living brand mark: B+E soft-hex nest + metal sun from `shared/aria-mark.json`.
 * One live nest per screen; compact / Reduce Motion freeze pose + sun.
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
  const idRef = useRef(0);
  if (idRef.current === 0) idRef.current = nestLiveCreateId();
  const [visible, setVisible] = useState(true);
  const [live, setLive] = useState(false);

  useEffect(() => {
    const id = idRef.current;
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => {
      nestLiveUpsert(id, {
        size,
        speaking: speakingRef.current,
        visible,
        canLive: ariaMarkShouldSpin(size, media.matches),
        onChange: () => setLive(nestLiveIsWinner(id)),
      });
      setLive(nestLiveIsWinner(id));
    };
    sync();
    const onMotion = () => sync();
    media.addEventListener("change", onMotion);
    return () => {
      media.removeEventListener("change", onMotion);
      nestLiveRemove(id);
    };
  }, [size, speaking, visible]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    if (typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver(
      ([entry]) => setVisible(!!entry?.isIntersecting),
      { threshold: 0.15 }
    );
    io.observe(canvas);
    return () => io.disconnect();
  }, [size]);

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
    let lastPaint = 0;
    const start = performance.now();

    const draw = (now: number, freeze: boolean) => {
      const t = freeze ? 0 : (now - start) / 1000;
      drawAriaNest(ctx, canvas.width, canvas.height, {
        time: t,
        speaking: speakingRef.current,
        reduceMotion: freeze,
        cssSize: size,
      });
    };

    const tick = (now: number) => {
      const freeze = !live || !ariaMarkShouldSpin(size, media.matches);
      if (freeze) {
        draw(now, true);
        return;
      }
      if (now - lastPaint >= NEST_PAINT_INTERVAL_MS - 1) {
        lastPaint = now;
        draw(now, false);
      }
      raf = requestAnimationFrame(tick);
    };

    const onMotionPref = () => {
      cancelAnimationFrame(raf);
      tick(performance.now());
    };

    tick(start);
    media.addEventListener("change", onMotionPref);
    return () => {
      cancelAnimationFrame(raf);
      media.removeEventListener("change", onMotionPref);
    };
  }, [size, live]);

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
