"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { useAppStore } from "@/stores/useAppStore";
import { BottomNav } from "@/components/shared/bottom-nav";
import { DataStatusBanner } from "@/components/shared/data-status-banner";
import { HomePage } from "@/components/home/home-page";
import { ChatPage } from "@/components/chat/chat-page";
import { WorkoutPage } from "@/components/workout/workout-page";
import { SleepPage } from "@/components/sleep/sleep-page";
import { ProfileTab } from "@/components/profile/profile-tab";

function TabRenderer({ activeTab }: { activeTab: string }) {
  switch (activeTab) {
    case "home":
      return <HomePage />;
    case "chat":
      return <ChatPage />;
    case "workout":
      return <WorkoutPage />;
    case "sleep":
      return <SleepPage />;
    case "profile":
      return <ProfileTab />;
    default:
      return <HomePage />;
  }
}

export default function Page() {
  const router = useRouter();
  const { isOnboarded, activeTab, setActiveTab, loadDashboardFromAPI } = useAppStore();

  useEffect(() => {
    if (!isOnboarded) {
      router.replace("/onboarding");
    }
  }, [isOnboarded, router]);

  useEffect(() => {
    if (isOnboarded) {
      void loadDashboardFromAPI();
    }
  }, [isOnboarded, loadDashboardFromAPI]);

  if (!isOnboarded) {
    return null;
  }

  return (
    <div className="relative min-h-[100dvh] bg-background">
      <DataStatusBanner />
      <div className="pb-[calc(5rem+env(safe-area-inset-bottom,0px))] min-h-[100dvh]">
        <AnimatePresence mode="wait">
          <motion.div
            key={activeTab}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.25, ease: "easeInOut" }}
          >
            <TabRenderer activeTab={activeTab} />
          </motion.div>
        </AnimatePresence>
      </div>
      <BottomNav
        activeTab={activeTab as "home" | "chat" | "workout" | "sleep" | "profile"}
        onTabChange={(tab) => setActiveTab(tab)}
      />
    </div>
  );
}
