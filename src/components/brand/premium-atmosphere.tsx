"use client";

import { useEffect, useState, type ReactNode } from "react";
import { cn } from "@/lib/utils";

/** Soft mesh wash — Oura / Whoop–class depth with living drift. */
export function PremiumAtmosphere({
  accent = "#FF6B2B",
  secondary = "#A9D8FF",
  intensity = 1,
  className,
}: {
  accent?: string;
  secondary?: string;
  intensity?: number;
  className?: string;
}) {
  const a = Math.max(0, Math.min(1, intensity));
  return (
    <div className={cn("pointer-events-none absolute inset-0 overflow-hidden bg-background", className)} aria-hidden>
      <div
        className="premium-atmosphere-drift absolute inset-[-8%]"
        style={{
          background: `
            radial-gradient(ellipse 80% 55% at 50% 8%, rgba(247,244,240,${0.08 * a}) 0%, rgba(169,216,255,${0.05 * a}) 28%, transparent 62%),
            radial-gradient(ellipse 70% 50% at 22% 78%, ${hexAlpha(accent, 0.13 * a)} 0%, ${hexAlpha(accent, 0.035 * a)} 40%, transparent 70%),
            radial-gradient(ellipse 55% 45% at 88% 52%, ${hexAlpha(secondary, 0.09 * a)} 0%, transparent 65%),
            linear-gradient(115deg, transparent 30%, rgba(255,255,255,${0.03 * a}) 48%, transparent 62%),
            linear-gradient(180deg, rgba(10,10,10,0.1) 0%, transparent 28%, rgba(10,10,10,0.5) 72%, rgba(10,10,10,0.92) 100%)
          `,
        }}
      />
    </div>
  );
}

export function PremiumPresenceBloom({
  size = 200,
  accent = "#FF6B2B",
  frost = "#A9D8FF",
  className,
}: {
  size?: number;
  accent?: string;
  frost?: string;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2",
        className
      )}
      style={{ width: size, height: size }}
      aria-hidden
    >
      <div
        className="premium-bloom-breathe absolute inset-0 rounded-full"
        style={{
          background: `
            radial-gradient(circle at 50% 50%, ${hexAlpha(accent, 0.24)} 0%, ${hexAlpha(frost, 0.12)} 38%, transparent 68%),
            radial-gradient(circle at 50% 45%, rgba(247,244,240,0.16) 0%, transparent 42%)
          `,
          filter: "blur(12px)",
        }}
      />
      <div
        className="premium-bloom-orbit absolute inset-[14%] rounded-full"
        aria-hidden
      />
      <div className="absolute inset-[18%] rounded-full border border-white/8" />
    </div>
  );
}

export function ForgeBrandMark({ size = 22, className }: { size?: number; className?: string }) {
  return (
    <span
      className={cn("premium-brand-mark inline-block shrink-0", className)}
      style={{
        width: size,
        height: size,
        borderRadius: size * 0.28,
        background: "linear-gradient(135deg, rgba(247,244,240,0.95), rgba(255,77,0,0.92), #C43A00)",
        boxShadow: "inset 0 0 0 0.8px rgba(255,255,255,0.28), 0 2px 10px rgba(255,77,0,0.28)",
      }}
      aria-hidden
    />
  );
}

export function PremiumPrimaryButton({
  children,
  onClick,
  className,
  type = "button",
  disabled,
}: {
  children: ReactNode;
  onClick?: () => void;
  className?: string;
  type?: "button" | "submit";
  disabled?: boolean;
}) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={cn(
        "premium-cta group relative flex w-full items-center justify-between overflow-hidden rounded-full px-6 py-[17px] text-[17px] font-semibold transition duration-200 active:scale-[0.98]",
        disabled
          ? "bg-surface-elevated text-white/35"
          : "bg-[#F7F4F0] text-[#0A0A0A] shadow-[0_10px_30px_rgba(247,244,240,0.14)]",
        className
      )}
    >
      {!disabled && <span className="premium-cta-sheen pointer-events-none absolute inset-0" aria-hidden />}
      <span className="relative z-10 flex w-full items-center justify-between gap-3">{children}</span>
    </button>
  );
}

export function PremiumProgressDots({
  count,
  current,
  onSelect,
}: {
  count: number;
  current: number;
  onSelect?: (index: number) => void;
}) {
  return (
    <div className="flex items-center gap-1.5">
      {Array.from({ length: count }).map((_, i) => (
        <button
          key={i}
          type="button"
          aria-label={`Go to slide ${i + 1}`}
          onClick={() => onSelect?.(i)}
          className={cn(
            "h-1 rounded-full transition-all duration-300",
            i === current
              ? "w-5 bg-[#F7F4F0] shadow-[0_0_10px_rgba(247,244,240,0.35)]"
              : "w-1.5 bg-white/16"
          )}
        />
      ))}
    </div>
  );
}

export function PremiumEntrance({
  children,
  index = 0,
  className,
}: {
  children: ReactNode;
  index?: number;
  className?: string;
}) {
  const [show, setShow] = useState(false);
  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) {
      setShow(true);
      return;
    }
    const t = window.setTimeout(() => setShow(true), 40 + index * 70);
    return () => window.clearTimeout(t);
  }, [index]);

  return (
    <div
      className={cn(
        "transition-all duration-500 ease-out",
        show ? "translate-y-0 opacity-100 blur-0" : "translate-y-3 opacity-0 blur-[3px]",
        className
      )}
    >
      {children}
    </div>
  );
}

function hexAlpha(hex: string, alpha: number): string {
  const h = hex.replace("#", "");
  const full = h.length === 3 ? h.split("").map((c) => c + c).join("") : h;
  const n = parseInt(full, 16);
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  return `rgba(${r},${g},${b},${alpha})`;
}
