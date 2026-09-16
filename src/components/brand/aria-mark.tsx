"use client";

import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import { ARIA_MARK, ariaMarkPaintDue, ariaMarkShouldSpin } from "@/lib/aria-mark";
import { drawAriaRingField } from "@/lib/aria-ring-field";

/**
 * Adaptive Recovery Interactive Assistant.
 * Living contract is the B+E soft-hex nest in `ARIA_MARK` / `shared/aria-mark.json`.
 * Ring-field canvas + white metal-sun core is a stopgap until Wren's nest chase —
 * no PNG, no ember, no readiness chrome.
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
  const [visible, setVisible] = useState(true);
  const [live, setLive] = useState(false);

  const bindCanvas = (canvas: HTMLCanvasElement | null) => {
    canvasRef.current = canvas;
    if (!canvas || typeof window === "undefined") return;
    if (idRef.current === 0) idRef.current = nestLiveCreateId();
    try {
      paintNest(canvas, size, speakingRef.current, true, 0);
    } catch (err) {
      console.error("drawAriaNest failed", err);
    }
  };

  useEffect(() => {
    const id = idRef.current || nestLiveCreateId();
    idRef.current = id;
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
    media.addEventListener("change", sync);
    return () => {
      media.removeEventListener("change", sync);
      nestLiveRemove(id);
    };
  }, [size, speaking, visible]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry) setVisible(entry.isIntersecting);
      },
      { threshold: 0.01 }
    );
    io.observe(canvas);
    return () => io.disconnect();
  }, [size]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
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

    tick(performance.now());
    const onMotionPref = () => {
      cancelAnimationFrame(raf);
      tick(performance.now());
    };
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
      <NestStillSvg size={size} />
      <canvas
        ref={bindCanvas}
        className="pointer-events-none absolute inset-0 block h-full w-full"
      />
    </div>
  );
}
