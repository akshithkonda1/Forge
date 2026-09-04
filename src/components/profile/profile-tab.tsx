"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import { ProgressPage } from "@/components/progress/progress-page";
import SettingsPage from "@/components/settings/settings-page";

const SUB_TABS = [
  { id: "progress", label: "Progress" },
  { id: "settings", label: "Settings" },
] as const;

type SubTab = (typeof SUB_TABS)[number]["id"];

export function ProfileTab() {
  const [subTab, setSubTab] = useState<SubTab>("progress");

  return (
    <div className="bg-background">
      {/* Sub-tab bar */}
      <div className="sticky top-0 z-30 bg-background/80 backdrop-blur-xl pt-12 px-4 pb-2">
        <div className="flex rounded-lg bg-surface p-1">
          {SUB_TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setSubTab(tab.id)}
              className={cn(
                "relative flex-1 rounded-md py-2 text-sm font-medium transition-colors",
                subTab === tab.id
                  ? "text-white"
                  : "text-text-tertiary hover:text-text-secondary"
              )}
            >
              {subTab === tab.id && (
                <motion.div
                  layoutId="profileSubTab"
                  className="absolute inset-0 rounded-md bg-surface-elevated"
                  transition={{ type: "spring", stiffness: 350, damping: 30 }}
                />
              )}
              <span className="relative z-10">{tab.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Content */}
      {subTab === "progress" ? <ProgressPage /> : <SettingsPage />}
    </div>
  );
}
