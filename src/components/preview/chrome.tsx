"use client";

import { Home, Dumbbell, Heart, Moon, ChartColumn, User } from "lucide-react";
import { AriaMark } from "@/components/brand/aria-mark";
import { cn } from "@/lib/utils";
import { SAMPLE_LABEL, SAMPLE_PERSON } from "./copy";
import { SAMPLE_CLOCK } from "./sample-data";
import type { PreviewTab } from "./catalog";

export function StatusBar({ quiet = false }: { quiet?: boolean }) {
  return (
    <div className="preview-status relative flex h-[54px] shrink-0 items-end px-7 pb-2">
      <span className="font-[family-name:var(--font-preview-geist)] text-[15px] font-semibold tabular-nums tracking-tight text-text-primary">
        {SAMPLE_CLOCK}
      </span>
      <div
        className="absolute left-1/2 top-[11px] h-[30px] w-[110px] -translate-x-1/2 rounded-full bg-black"
        aria-hidden
      />
      <div className="ml-auto flex items-center gap-1.5 text-text-primary" aria-hidden>
        <SignalGlyph />
        <WifiGlyph />
        <BatteryGlyph />
      </div>
      {!quiet && (
        <span className="preview-sample-chip absolute right-5 top-[8px]">{SAMPLE_LABEL}</span>
      )}
    </div>
  );
}

export function HomeIndicator() {
  return (
    <div className="flex h-[21px] shrink-0 items-start justify-center pt-1" aria-hidden>
      <span className="h-[5px] w-[134px] rounded-full bg-white/35" />
    </div>
  );
}

const TABS: { id: Exclude<PreviewTab, null>; label: string }[] = [
  { id: "home", label: "Home" },
  { id: "train", label: "Train" },
  { id: "life", label: "Life" },
  { id: "chat", label: "ARIA" },
  { id: "sleep", label: "Sleep" },
  { id: "stats", label: "Stats" },
  { id: "you", label: "You" },
];

export function IosTabBar({ active }: { active: Exclude<PreviewTab, null> }) {
  return (
    <nav
      className="preview-tabbar shrink-0 border-t border-[color:var(--preview-hairline)] bg-background"
      aria-label="Primary"
    >
      <div className="flex h-[52px] items-end justify-between px-1.5 pb-1">
        {TABS.map((tab) => {
          const on = tab.id === active;
          return (
            <div
              key={tab.id}
              className="relative flex min-w-[44px] flex-1 flex-col items-center gap-0.5"
              aria-current={on ? "page" : undefined}
            >
              {on ? (
                <span className="absolute -top-1 h-[2px] w-5 rounded-full bg-paper/80" />
              ) : null}
              <TabGlyph id={tab.id} on={on} />
              <span
                className={cn(
                  "type-micro",
                  on ? "text-text-primary" : "text-text-tertiary"
                )}
              >
                {tab.label}
              </span>
            </div>
          );
        })}
      </div>
    </nav>
  );
}

function TabGlyph({
  id,
  on,
}: {
  id: Exclude<PreviewTab, null>;
  on: boolean;
}) {
  const tone = on ? "text-text-primary" : "text-text-tertiary";
  if (id === "chat") {
    return (
      <span className={on ? "opacity-100" : "opacity-45"}>
        <AriaMark size={22} speaking={false} />
      </span>
    );
  }
  const Icon =
    id === "home"
      ? Home
      : id === "train"
        ? Dumbbell
        : id === "life"
          ? Heart
          : id === "sleep"
            ? Moon
            : id === "stats"
              ? ChartColumn
              : User;
  return <Icon size={16} strokeWidth={2.25} className={tone} />;
}

export function SampleRibbon() {
  return (
    <p className="preview-ribbon">
      {SAMPLE_LABEL} · {SAMPLE_PERSON} · PR #472 look, not live data
    </p>
  );
}

function SignalGlyph() {
  return (
    <svg width="17" height="12" viewBox="0 0 17 12" fill="currentColor">
      <rect x="0" y="8" width="3" height="4" rx="0.5" />
      <rect x="4.5" y="5.5" width="3" height="6.5" rx="0.5" />
      <rect x="9" y="3" width="3" height="9" rx="0.5" />
      <rect x="13.5" y="0" width="3" height="12" rx="0.5" opacity="0.35" />
    </svg>
  );
}

function WifiGlyph() {
  return (
    <svg width="16" height="12" viewBox="0 0 16 12" fill="none" stroke="currentColor">
      <path d="M1.5 4.2C4.4 1.6 11.6 1.6 14.5 4.2" strokeWidth="1.4" strokeLinecap="round" />
      <path d="M4 6.6c2.2-1.8 5.8-1.8 8 0" strokeWidth="1.4" strokeLinecap="round" />
      <circle cx="8" cy="10" r="1.15" fill="currentColor" stroke="none" />
    </svg>
  );
}

function BatteryGlyph() {
  return (
    <svg width="27" height="13" viewBox="0 0 27 13" fill="none">
      <rect x="0.6" y="0.6" width="22" height="11.8" rx="2.4" stroke="currentColor" strokeOpacity="0.45" />
      <rect x="2.1" y="2.1" width="16.4" height="8.8" rx="1.2" fill="currentColor" />
      <path d="M24.2 4.2v4.6c1 .4 1.6 0 1.6-2.3s-.6-2.7-1.6-2.3Z" fill="currentColor" fillOpacity="0.45" />
    </svg>
  );
}
