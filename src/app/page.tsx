"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { useAppStore, type TabId } from "@/stores/useAppStore";
import { BottomNav } from "@/components/shared/bottom-nav";
import { HomePage } from "@/components/home/home-page";
import { ChatPage } from "@/components/chat/chat-page";
import { WorkoutPage } from "@/components/workout/workout-page";
import { SleepPage } from "@/components/sleep/sleep-page";
import { ProfileTab } from "@/components/profile/profile-tab";
import { AriaOrb } from "@/components/onboarding/aria-companion";
import { cn } from "@/lib/utils";

function TabRenderer({ activeTab }: { activeTab: TabId }) {
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

function BootSplash() {
  return (
    <div className="flex min-h-[100dvh] flex-col items-center justify-center bg-background">
      <AriaOrb mood="focused" size={88} speaking />
      <p className="mt-5 text-[11px] font-black uppercase tracking-[0.28em] text-ember">
        FORGE × ARIA
      </p>
    </div>
  );
}

export default function Page() {
  const router = useRouter();
  const isOnboarded = useAppStore((s) => s.isOnboarded);
  const hasHydrated = useAppStore((s) => s.hasHydrated);
  const setHasHydrated = useAppStore((s) => s.setHasHydrated);
  const activeTab = useAppStore((s) => s.activeTab);
  const setActiveTab = useAppStore((s) => s.setActiveTab);
  const workoutActive = useAppStore((s) => s.activeWorkout.isActive);

  useEffect(() => {
    const finish = () => setHasHydrated(true);
    const unsub = useAppStore.persist.onFinishHydration(finish);
    if (useAppStore.persist.hasHydrated()) finish();
    return unsub;
  }, [setHasHydrated]);

  useEffect(() => {
    if (!hasHydrated) return;
    if (!isOnboarded) {
      router.replace("/onboarding");
    }
  }, [hasHydrated, isOnboarded, router]);

  if (!hasHydrated) {
    return <BootSplash />;
  }

  if (!isOnboarded) {
    return <BootSplash />;
  }

  const lockViewport = activeTab === "chat" || (activeTab === "workout" && workoutActive);

  return (
    <div className="app-shell relative mx-auto flex h-[100dvh] w-full max-w-lg flex-col bg-background">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[100] focus:rounded-lg focus:bg-ember focus:px-3 focus:py-2 focus:text-sm focus:text-white"
      >
        Skip to content
      </a>
      <main
        id="main"
        className={cn(
          "flex min-h-0 flex-1 flex-col",
          lockViewport ? "overflow-hidden" : "overflow-y-auto"
        )}
      >
        <AnimatePresence mode="wait">
          <motion.div
            key={activeTab}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.22, ease: "easeInOut" }}
            className={cn("flex min-h-0 flex-1 flex-col", lockViewport && "h-full overflow-hidden")}
          >
            <TabRenderer activeTab={activeTab} />
          </motion.div>
        </AnimatePresence>
      </main>
      <BottomNav activeTab={activeTab} onTabChange={setActiveTab} />
    </div>
  );
}
