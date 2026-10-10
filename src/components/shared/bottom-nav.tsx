"use client";

import { Home, Dumbbell, Moon, User } from "lucide-react";
import { cn } from "@/lib/utils";
import type { TabId } from "@/stores/useAppStore";
import { AriaMark } from "@/components/brand/aria-mark";

interface BottomNavProps {
  activeTab: TabId;
  onTabChange: (tab: TabId) => void;
}

const tabs: { id: TabId; label: string; icon: typeof Home | null }[] = [
  { id: "home", label: "Home", icon: Home },
  { id: "chat", label: "ARIA", icon: null },
  { id: "workout", label: "Workout", icon: Dumbbell },
  { id: "sleep", label: "Sleep", icon: Moon },
  { id: "profile", label: "You", icon: User },
];

export function BottomNav({ activeTab, onTabChange }: BottomNavProps) {
  return (
    <nav
      className="shrink-0 border-t border-white/[0.06] bg-background/85 backdrop-blur-xl"
      aria-label="Primary"
    >
      <div className="flex h-16 items-center justify-around px-2 pb-[env(safe-area-inset-bottom,0px)]">
        {tabs.map((tab) => {
          const isActive = activeTab === tab.id;
          const isCenter = tab.id === "workout";
          const Icon = tab.icon;

          if (isCenter && Icon) {
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => onTabChange(tab.id)}
                aria-current={isActive ? "page" : undefined}
                aria-label="Workout"
                className="relative -mt-5 flex min-w-[3.5rem] flex-col items-center focus-visible:outline-none active:brightness-90"
              >
                <div
                  className={cn(
                    "flex h-12 w-12 items-center justify-center rounded-full transition-shadow duration-200",
                    isActive
                      ? "bg-paper text-background shadow-[0_8px_24px_rgba(247,244,240,0.18)]"
                      : "bg-white/[0.1] text-text-primary ring-1 ring-white/15"
                  )}
                >
                  <Icon size={22} />
                </div>
                <span
                  className={cn(
                    "mt-1.5 type-micro font-medium",
                    isActive ? "text-text-primary" : "text-text-tertiary"
                  )}
                >
                  {tab.label}
                </span>
              </button>
            );
          }

          return (
            <button
              key={tab.id}
              type="button"
              onClick={() => onTabChange(tab.id)}
              aria-current={isActive ? "page" : undefined}
              aria-label={tab.label}
              className="relative flex min-h-[3rem] min-w-[3.5rem] flex-col items-center justify-center gap-1 focus-visible:outline-none active:brightness-90"
            >
              {tab.id === "chat" || !Icon ? (
                <AriaMark size={24} speaking={false} />
              ) : (
                <Icon
                  size={22}
                  className={cn(
                    "transition-colors",
                    isActive ? "text-text-primary" : "text-text-tertiary"
                  )}
                />
              )}
              <span
                className={cn(
                  "type-micro font-medium transition-colors",
                  isActive ? "text-text-primary" : "text-text-tertiary"
                )}
              >
                {tab.label}
              </span>
              {isActive && (
                <span className="absolute -top-px h-0.5 w-7 rounded-full bg-paper/80" />
              )}
            </button>
          );
        })}
      </div>
    </nav>
  );
}
