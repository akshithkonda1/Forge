"use client";

import { Home, Dumbbell, Heart, Moon, ChartColumn, User } from "lucide-react";
import { AriaMark } from "@/components/brand/aria-mark";
import { cn } from "@/lib/utils";
import type { PreviewTab } from "./catalog";

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
    <nav className="preview-tabbar shrink-0 bg-background" aria-label="Primary">
      <div className="flex h-[52px] items-center justify-between px-1.5">
        {TABS.map((tab) => {
          const on = tab.id === active;
          return (
            <div
              key={tab.id}
              className="flex min-w-[44px] flex-1 flex-col items-center gap-0.5"
              aria-current={on ? "page" : undefined}
            >
              <TabGlyph id={tab.id} on={on} />
              <span
                className={cn(
                  "text-[10px] font-medium",
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
  return <Icon size={16} strokeWidth={2} className={tone} />;
}

