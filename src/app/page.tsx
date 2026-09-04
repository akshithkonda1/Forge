"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { useAppStore, type TabId } from "@/stores/useAppStore";
import { BottomNav } from "@/components/shared/bottom-nav";
import { HomePage } from "@/components/home/home-page";
import { ChatPage } from "@/components/chat/chat-page";
import { WorkoutPage } from "@/components/workout/workout-page";
import { SleepPage } from "@/components/sleep/sleep-page";
import { ProfileTab } from "@/components/profile/profile-tab";
import { AriaOrb } from "@/components/onboarding/aria-companion";
import { cn } from "@/lib/utils";

const TABS: TabId[] = ["home", "chat", "workout", "sleep", "profile"];

function BootSplash() {
  return (
    <div className="flex min-h-[100dvh] flex-col items-center justify-center bg-background">
      <AriaOrb mood="focused" size={88} />
      <p className="mt-5 text-[11px] font-black uppercase tracking-[0.28em] text-ember">
        FORGE × ARIA
      </p>
    </div>
  );
}

function TabPane({
  id,
  active,
  lock,
  children,
}: {
  id: TabId;
  active: boolean;
  lock: boolean;
  children: ReactNode;
}) {
  return (
    <div
      role="tabpanel"
      id={`tab-${id}`}
      hidden={!active}
      className={cn(
        "flex min-h-0 flex-1 flex-col",
        active && lock && "h-full overflow-hidden"
      )}
    >
      {children}
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
  const mainRef = useRef<HTMLElement>(null);
  const [visited, setVisited] = useState<TabId[]>([activeTab]);

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

  useEffect(() => {
    setVisited((prev) => (prev.includes(activeTab) ? prev : [...prev, activeTab]));
    mainRef.current?.scrollTo({ top: 0 });
    window.scrollTo(0, 0);
  }, [activeTab]);

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
        ref={mainRef}
        className={cn(
          "flex min-h-0 flex-1 flex-col",
          lockViewport ? "overflow-hidden" : "overflow-y-auto"
        )}
      >
        {TABS.filter((id) => visited.includes(id)).map((id) => (
          <TabPane
            key={id}
            id={id}
            active={activeTab === id}
            lock={id === "chat" || (id === "workout" && workoutActive)}
          >
            {id === "home" && <HomePage />}
            {id === "chat" && <ChatPage />}
            {id === "workout" && <WorkoutPage />}
            {id === "sleep" && <SleepPage />}
            {id === "profile" && <ProfileTab />}
          </TabPane>
        ))}
      </main>
      <BottomNav activeTab={activeTab} onTabChange={setActiveTab} />
    </div>
  );
}
