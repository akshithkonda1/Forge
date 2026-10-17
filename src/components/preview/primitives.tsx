"use client";

import type { ReactNode } from "react";
import { AriaMark } from "@/components/brand/aria-mark";
import { cn } from "@/lib/utils";

export function Screen({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={cn("preview-screen", className)}>{children}</div>;
}

export function PageHead({
  label,
  title,
  lead,
  mark = false,
}: {
  label: ReactNode;
  title: ReactNode;
  lead?: ReactNode;
  mark?: boolean;
}) {
  return (
    <header className="preview-head">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="preview-label">{label}</p>
          <h1 className="preview-display mt-1 text-[1.5rem] leading-tight">{title}</h1>
        </div>
        {mark ? <AriaMark size={36} speaking={false} /> : null}
      </div>
      {lead ? <p className="preview-body mt-2 text-text-secondary">{lead}</p> : null}
    </header>
  );
}

export function Stack({ children }: { children: ReactNode }) {
  return <div className="preview-stack">{children}</div>;
}

export function Tessera({
  children,
  className,
  inset = false,
  as: Tag = "section",
}: {
  children: ReactNode;
  className?: string;
  inset?: boolean;
  as?: "section" | "article" | "div" | "li";
}) {
  return (
    <Tag className={cn("preview-tessera", inset && "preview-tessera-inset", className)}>
      {children}
    </Tag>
  );
}

export function Eyebrow({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <p className={cn("preview-label", className)}>{children}</p>;
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

export function Row({
  label,
  value,
  hint,
}: {
  label: string;
  value: string;
  hint?: string;
}) {
  return (
    <div className="preview-row">
      <span className="preview-row-label">{label}</span>
      <span className="preview-row-value">
        {value}
        {hint ? <span className="preview-row-hint"> · {hint}</span> : null}
      </span>
    </div>
  );
}

export function AskAria({ children }: { children: ReactNode }) {
  return <p className="preview-ask">{children}</p>;
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

export function FootCtas({ children }: { children: ReactNode }) {
  return <div className="preview-foot">{children}</div>;
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
    <div className="preview-fill" aria-hidden>
      <div className="preview-fill-in" style={{ width, backgroundColor: tint }} />
    </div>
  );
}

export function WeekRhythm({
  days,
}: {
  days: readonly { key: string; label: string; session: boolean; today: boolean }[];
}) {
  return (
    <div className="preview-week" aria-label="This week">
      {days.map((day) => (
        <div key={day.key} className={cn("preview-week-day", day.today && "is-today")}>
          <span>{day.label}</span>
          <i className={cn("preview-week-mark", day.session && "is-session")} />
        </div>
      ))}
    </div>
  );
}

export function Sips({ total, filled }: { total: number; filled: number }) {
  return (
    <div className="preview-sips" aria-hidden>
      {Array.from({ length: total }, (_, i) => (
        <i key={i} className={cn("preview-sip", i < filled && "is-filled")} />
      ))}
    </div>
  );
}

export function NightHours({
  hours,
}: {
  hours: readonly { key: string; label: string; tone: "deep" | "rem" | "light" | "awake" }[];
}) {
  return (
    <div className="preview-night" aria-label="Last night">
      {hours.map((hour) => (
        <div key={hour.key} className="preview-night-hour">
          <i className={`preview-night-block is-${hour.tone}`} />
          <span>{hour.label}</span>
        </div>
      ))}
    </div>
  );
}
