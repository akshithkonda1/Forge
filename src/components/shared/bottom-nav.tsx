"use client";

import { motion } from "framer-motion";
import { Home, MessageCircle, Dumbbell, Moon, User } from "lucide-react";
import { cn } from "@/lib/utils";

type TabId = "home" | "chat" | "workout" | "sleep" | "profile";

interface BottomNavProps {
  activeTab: TabId;
  onTabChange: (tab: TabId) => void;
}

const tabs: { id: TabId; label: string; icon: typeof Home }[] = [
  { id: "home", label: "Home", icon: Home },
  { id: "chat", label: "Chat", icon: MessageCircle },
  { id: "workout", label: "Workout", icon: Dumbbell },
  { id: "sleep", label: "Sleep", icon: Moon },
  { id: "profile", label: "Profile", icon: User },
];

export function BottomNav({ activeTab, onTabChange }: BottomNavProps) {
  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50">
      <div className="border-t border-[#2A2A2A] bg-[#0A0A0A]/90 backdrop-blur-xl pb-[env(safe-area-inset-bottom,0px)]">
        <div className="flex h-16 items-center justify-around px-2">
          {tabs.map((tab) => {
            const isActive = activeTab === tab.id;
            const isCenter = tab.id === "workout";
            const Icon = tab.icon;

            if (isCenter) {
              return (
                <button
                  key={tab.id}
                  onClick={() => onTabChange(tab.id)}
                  className="relative -mt-6 flex flex-col items-center min-w-[3.5rem]"
                >
                  <motion.div
                    className={cn(
                      "flex h-14 w-14 items-center justify-center rounded-full shadow-lg",
                      isActive
                        ? "bg-[#FF4D00] shadow-[0_0_24px_rgba(255,77,0,0.4)]"
                        : "bg-[#FF4D00]/80"
                    )}
                    whileTap={{ scale: 0.92 }}
                    transition={{ type: "spring", stiffness: 400, damping: 17 }}
                  >
                    <Icon size={24} className="text-white" />
                  </motion.div>
                  <span
                    className={cn(
                      "mt-1 text-[10px] font-medium",
                      isActive ? "text-[#FF4D00]" : "text-[#71717A]"
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
                onClick={() => onTabChange(tab.id)}
                className="relative flex min-h-[3rem] min-w-[3.5rem] flex-col items-center justify-center gap-1"
              >
                <motion.div
                  whileTap={{ scale: 0.9 }}
                  transition={{ type: "spring", stiffness: 400, damping: 17 }}
                >
                  <Icon
                    size={22}
                    className={cn(
                      "transition-colors",
                      isActive ? "text-[#FF4D00]" : "text-[#71717A]"
                    )}
                  />
                </motion.div>
                <span
                  className={cn(
                    "text-[10px] font-medium transition-colors",
                    isActive ? "text-[#FF4D00]" : "text-[#71717A]"
                  )}
                >
                  {tab.label}
                </span>
                {isActive && (
                  <motion.div
                    className="absolute -top-px h-0.5 w-8 rounded-full bg-[#FF4D00]"
                    layoutId="activeTab"
                    transition={{ type: "spring", stiffness: 300, damping: 25 }}
                  />
                )}
              </button>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
