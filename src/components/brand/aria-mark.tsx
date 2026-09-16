"use client";

import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import {
  ARIA_MARK,
  ARIA_MARK_COMPACT_MAX,
  ariaMarkShouldSpin,
  nestLiveCreateId,
  nestLiveIsWinner,
  nestLiveRemove,
  nestLiveUpsert,
  nestRingPose,
  NEST_PAINT_INTERVAL_MS,
  ringStrokeWidth,
  visibleRingIndices,
} from "@/lib/aria-mark";
import { drawAriaNest, hexAlpha, softHexPathD } from "@/lib/aria-nest";

function sizeCanvas(canvas: HTMLCanvasElement, size: number): CanvasRenderingContext2D | null {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const px = Math.max(2, Math.round(size * dpr));
  if (canvas.width !== px || canvas.height !== px) {
    canvas.width = px;
    canvas.height = px;
  }
  canvas.style.width = `${size}px`;
  canvas.style.height = `${size}px`;
  return canvas.getContext("2d");
}

function NestStillSvg({ size }: { size: number }) {
  const compact = size <= ARIA_MARK_COMPACT_MAX;
  const stroke = Math.max(2.1, ringStrokeWidth(size) * (100 / Math.max(size, 1)) * 1.35);
  const sunR = ARIA_MARK.orbDiameterIdle * 50;
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      className="block"
      aria-hidden
    >
      {!compact && (
        <circle
          cx="50"
          cy="50"
          r="48"
          fill={hexAlpha(ARIA_MARK.hearthGlowHex, 0.22)}
        />
      )}
      {visibleRingIndices().map((index) => {
        const pose = nestRingPose(index, 0, false, true);
        return (
          <path
            key={index}
            d={softHexPathD(
              (pose.rx * 100) / 2,
              (pose.ry * 100) / 2,
              ARIA_MARK.cornerRoundness,
              0,
              0,
              50,
              50
            )}
            fill="none"
            stroke={pose.hex}
            strokeOpacity={pose.opacity}
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeLinejoin="round"
            transform={`rotate(${(pose.rotation * 180) / Math.PI} 50 50)`}
          />
        );
      })}
      <circle cx="50" cy="50" r={sunR} fill={ARIA_MARK.pearlHotHex} />
    </svg>
  );
}

function paintNest(
  canvas: HTMLCanvasElement,
  size: number,
  speaking: boolean,
  freeze: boolean,
  time: number
): void {
  const ctx = sizeCanvas(canvas, size);
  if (!ctx) return;
  drawAriaNest(ctx, canvas.width, canvas.height, {
    time,
    speaking,
    reduceMotion: freeze,
    cssSize: size,
  });
}

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
    let lastPaint = 0;
    const start = performance.now();

    const tick = (now: number) => {
      const freeze = !live || !ariaMarkShouldSpin(size, media.matches);
      try {
        if (freeze) {
          paintNest(canvas, size, speakingRef.current, true, 0);
          return;
        }
        if (now - lastPaint >= NEST_PAINT_INTERVAL_MS - 1) {
          lastPaint = now;
          paintNest(canvas, size, speakingRef.current, false, (now - start) / 1000);
        }
      } catch (err) {
        console.error("drawAriaNest failed", err);
        return;
      }
      raf = requestAnimationFrame(tick);
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
