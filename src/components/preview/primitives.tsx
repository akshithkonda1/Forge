"use client";

import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { readinessHex, readinessLabel } from "@/lib/readiness-tokens";
import { DESIGN, tokenHex } from "@/lib/design-tokens";

export function Tessera({
  children,
  className,
  as: Tag = "section",
}: {
  children: ReactNode;
  className?: string;
  as?: "section" | "article" | "div" | "li";
}) {
  return <Tag className={cn("preview-tessera", className)}>{children}</Tag>;
}

export function Eyebrow({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <p className={cn("type-eyebrow", className)}>{children}</p>;
}

export function DisplayTitle({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <h1 className={cn("preview-display", className)}>{children}</h1>;
}

export function Hairline({ className }: { className?: string }) {
  return <div className={cn("preview-hairline", className)} aria-hidden />;
}

export function Capsule({
  children,
  tone = "quiet",
  className,
}: {
  children: ReactNode;
  tone?: "quiet" | "ember" | "paper" | "selected";
  className?: string;
}) {
  return (
    <span className={cn("preview-capsule", `preview-capsule-${tone}`, className)}>
      {children}
    </span>
  );
}

export function PrimaryCta({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("preview-cta", className)}>
      <span>{children}</span>
    </div>
  );
}

export function GhostCta({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={cn("preview-ghost-cta", className)}>{children}</div>;
}

/** Solid sweep. Data is the arc. No ticks, no glow costume. */
export function Sweep({
  score,
  size = 168,
  stroke = DESIGN.stroke.ring,
  label = "Readiness",
}: {
  score: number;
  size?: number;
  stroke?: number;
  label?: string;
}) {
  const clamped = Math.max(0, Math.min(100, score));
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const progress = (clamped / 100) * circumference;
  const center = size / 2;
  const color = readinessHex(clamped);
  const band = readinessLabel(clamped);

  return (
    <div className="relative inline-flex items-center justify-center" style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90">
        <circle
          cx={center}
          cy={center}
          r={radius}
          fill="none"
          stroke={tokenHex("border")}
          strokeWidth={stroke}
          strokeLinecap="round"
        />
        <circle
          cx={center}
          cy={center}
          r={radius}
          fill="none"
          stroke={color}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference - progress}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="preview-metric text-[2.25rem] leading-none text-text-primary">{clamped}</span>
        <span className="mt-1 type-caption" style={{ color }}>
          {band}
        </span>
        <span className="mt-0.5 type-micro text-text-tertiary">{label}</span>
      </div>
    </div>
  );
}

export function FillBar({
  fraction,
  tint,
}: {
  fraction: number;
  tint: string;
}) {
  const width = `${Math.max(0, Math.min(1, fraction)) * 100}%`;
  return (
    <div className="h-[5px] w-full overflow-hidden rounded-full bg-border">
      <div className="h-full rounded-full" style={{ width, backgroundColor: tint }} />
    </div>
  );
}
