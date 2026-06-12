"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { useAppStore } from "@/stores/useAppStore";
import { useForgeAuth } from "@/lib/auth/use-forge-auth";
import { DataLoader } from "@/components/system/data-loader";
import { BottomNav } from "@/components/shared/bottom-nav";
import { HomePage } from "@/components/home/home-page";
import { ChatPage } from "@/components/chat/chat-page";
import { WorkoutPage } from "@/components/workout/workout-page";
import { SleepPage } from "@/components/sleep/sleep-page";
import { ProfileTab } from "@/components/profile/profile-tab";

function LoadingScreen() {
  return (
    <div className="flex min-h-[100dvh] items-center justify-center bg-background">
      <div className="h-6 w-6 animate-spin rounded-full border-2 border-text-tertiary border-t-ember" />
    </div>
  );
}

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
  const { isReady, isAuthenticated, signIn } = useForgeAuth();
  const { isOnboarded, activeTab, setActiveTab } = useAppStore();

  useEffect(() => {
    if (isReady && !isAuthenticated) signIn();
  }, [isReady, isAuthenticated, signIn]);

  useEffect(() => {
    if (isReady && isAuthenticated && !isOnboarded) router.push("/onboarding");
  }, [isReady, isAuthenticated, isOnboarded, router]);

  if (!isReady) return <LoadingScreen />;
  if (!isAuthenticated) return null;
  if (!isOnboarded) return null;

  return (
    <DataLoader>
      <div className="relative min-h-[100dvh] bg-background">
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
    </DataLoader>
  );
}