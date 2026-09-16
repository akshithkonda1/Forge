"use client";

import { cn } from "@/lib/utils";

/** Soft mesh wash — Oura / Whoop–class depth, never rage-fire. */
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
        className="absolute inset-0"
        style={{
          background: `
            radial-gradient(ellipse 80% 55% at 50% 8%, rgba(247,244,240,${0.07 * a}) 0%, rgba(169,216,255,${0.045 * a}) 28%, transparent 62%),
            radial-gradient(ellipse 70% 50% at 22% 78%, ${hexAlpha(accent, 0.11 * a)} 0%, ${hexAlpha(accent, 0.03 * a)} 40%, transparent 70%),
            radial-gradient(ellipse 55% 45% at 88% 52%, ${hexAlpha(secondary, 0.07 * a)} 0%, transparent 65%),
            linear-gradient(180deg, rgba(10,10,10,0.12) 0%, transparent 28%, rgba(10,10,10,0.5) 72%, rgba(10,10,10,0.9) 100%)
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
      className={cn("pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full", className)}
      style={{
        width: size,
        height: size,
        background: `
          radial-gradient(circle at 50% 50%, ${hexAlpha(accent, 0.22)} 0%, ${hexAlpha(frost, 0.1)} 38%, transparent 68%),
          radial-gradient(circle at 50% 45%, rgba(247,244,240,0.14) 0%, transparent 42%)
        `,
        filter: "blur(10px)",
      }}
      aria-hidden
    />
  );
}

export function ForgeBrandMark({ size = 22, className }: { size?: number; className?: string }) {
  return (
    <span
      className={cn("inline-block shrink-0", className)}
      style={{
        width: size,
        height: size,
        borderRadius: size * 0.28,
        background: "linear-gradient(135deg, rgba(247,244,240,0.95), rgba(255,77,0,0.92), #C43A00)",
        boxShadow: "inset 0 0 0 0.8px rgba(255,255,255,0.22)",
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
  children: React.ReactNode;
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
        "flex w-full items-center justify-between rounded-full px-6 py-[17px] text-[17px] font-semibold transition active:scale-[0.98]",
        disabled
          ? "bg-surface-elevated text-white/35"
          : "bg-[#F7F4F0] text-[#0A0A0A]",
        className
      )}
    >
      {children}
    </button>
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
