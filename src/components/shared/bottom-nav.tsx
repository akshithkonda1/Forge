"use client";

import { motion } from "framer-motion";
import { Home, Sparkles, Dumbbell, Moon, User } from "lucide-react";
import { cn } from "@/lib/utils";
import type { TabId } from "@/stores/useAppStore";

interface BottomNavProps {
  activeTab: TabId;
  onTabChange: (tab: TabId) => void;
}

const tabs: { id: TabId; label: string; icon: typeof Home }[] = [
  { id: "home", label: "Home", icon: Home },
  { id: "chat", label: "ARIA", icon: Sparkles },
  { id: "workout", label: "Workout", icon: Dumbbell },
  { id: "sleep", label: "Sleep", icon: Moon },
  { id: "profile", label: "You", icon: User },
];

export function BottomNav({ activeTab, onTabChange }: BottomNavProps) {
  return (
    <nav
      className="shrink-0 border-t border-border bg-background/90 backdrop-blur-xl"
      aria-label="Primary"
    >
      <div className="flex h-16 items-center justify-around px-2 pb-[env(safe-area-inset-bottom,0px)]">
        {tabs.map((tab) => {
          const isActive = activeTab === tab.id;
          const isCenter = tab.id === "workout";
          const Icon = tab.icon;

          if (isCenter) {
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => onTabChange(tab.id)}
                aria-current={isActive ? "page" : undefined}
                aria-label="Workout"
                className="relative -mt-6 flex min-w-[3.5rem] flex-col items-center focus-visible:outline-none"
              >
                <motion.div
                  className={cn(
                    "flex h-14 w-14 items-center justify-center rounded-full shadow-lg",
                    isActive
                      ? "bg-ember shadow-[0_0_24px_rgba(255,77,0,0.4)]"
                      : "bg-ember/80"
                  )}
                  whileTap={{ scale: 0.92 }}
                  transition={{ type: "spring", stiffness: 400, damping: 17 }}
                >
                  <Icon size={24} className="text-white" />
                </motion.div>
                <span
                  className={cn(
                    "mt-1 text-[10px] font-medium",
                    isActive ? "text-ember" : "text-text-tertiary"
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
              className="relative flex min-h-[3rem] min-w-[3.5rem] flex-col items-center justify-center gap-1 focus-visible:outline-none"
            >
              <motion.div
                whileTap={{ scale: 0.9 }}
                transition={{ type: "spring", stiffness: 400, damping: 17 }}
              >
                <Icon
                  size={22}
                  className={cn(
                    "transition-colors",
                    isActive ? "text-ember" : "text-text-tertiary"
                  )}
                />
              </motion.div>
              <span
                className={cn(
                  "text-[10px] font-medium transition-colors",
                  isActive ? "text-ember" : "text-text-tertiary"
                )}
              >
                {tab.label}
              </span>
              {isActive && (
                <motion.div
                  className="absolute -top-px h-0.5 w-8 rounded-full bg-ember"
                  layoutId="activeTab"
                  transition={{ type: "spring", stiffness: 300, damping: 25 }}
                />
              )}
            </button>
          );
        })}
      </div>
    </nav>
  );
}
