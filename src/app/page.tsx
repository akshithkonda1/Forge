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
import { AriaIntro } from "@/components/brand/aria-intro";
import { AriaMark } from "@/components/brand/aria-mark";
import { ForgeBrandFlame, ForgeFireField } from "@/components/brand/forge-fire";
import { forgeSplashHoldMs } from "@/lib/forge-splash";
import { cn } from "@/lib/utils";

const TABS: TabId[] = ["home", "chat", "workout", "sleep", "profile"];
let didFinishSplash = false;

function BootSplash() {
  return (
    <div className="relative flex min-h-[100dvh] flex-col items-center justify-center overflow-hidden bg-background">
      <ForgeFireField intensity="rage" origin="floor" className="opacity-80" />
      <div className="relative z-10 flex flex-col items-center">
        <div className="relative flex h-56 w-56 items-center justify-center">
          <ForgeFireField intensity="rage" origin="hearth" className="opacity-90" />
          <div
            className="pointer-events-none absolute inset-8 rounded-full"
            style={{
              background:
                "radial-gradient(circle, rgba(10,10,10,0.72) 0%, rgba(10,10,10,0.2) 55%, transparent 70%)",
            }}
          />
          <AriaMark size={148} speaking label="ARIA" className="relative z-10" />
        </div>
        <div className="mt-5 flex items-center gap-2 text-[32px] font-black tracking-[0.28em] text-white">
          <ForgeBrandFlame size={26} />
          FORGE
        </div>
        <p className="mt-3 text-[13px] font-semibold uppercase tracking-[0.32em] text-ember">
          Forged.
        </p>
      </div>
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
  const hasMetAria = useAppStore((s) => s.hasMetAria);
  const meetAria = useAppStore((s) => s.meetAria);
  const hasHydrated = useAppStore((s) => s.hasHydrated);
  const setHasHydrated = useAppStore((s) => s.setHasHydrated);
  const activeTab = useAppStore((s) => s.activeTab);
  const setActiveTab = useAppStore((s) => s.setActiveTab);
  const workoutActive = useAppStore((s) => s.activeWorkout.isActive);
  const mainRef = useRef<HTMLElement>(null);
  const [visited, setVisited] = useState<TabId[]>([activeTab]);
  const [showLaunchMeet, setShowLaunchMeet] = useState(true);
  const [showSplash, setShowSplash] = useState(!didFinishSplash);

  useEffect(() => {
    const finish = () => setHasHydrated(true);
    const unsub = useAppStore.persist.onFinishHydration(finish);
    if (useAppStore.persist.hasHydrated()) finish();
    return unsub;
  }, [setHasHydrated]);

  useEffect(() => {
    if (!showSplash) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const timer = window.setTimeout(() => {
      didFinishSplash = true;
      setShowSplash(false);
    }, forgeSplashHoldMs(reduce));
    return () => window.clearTimeout(timer);
  }, [showSplash]);

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

  if (showSplash || !hasHydrated) {
    return <BootSplash />;
  }

  if (!isOnboarded) {
    return <BootSplash />;
  }

  const waitingToMeet = !hasMetAria && (activeTab === "chat" || showLaunchMeet);
  if (waitingToMeet) {
    return (
      <div className="app-shell relative mx-auto min-h-[100dvh] w-full max-w-lg bg-background">
        <AriaIntro
          onContinue={() => {
            meetAria();
            setShowLaunchMeet(false);
            setActiveTab("chat");
          }}
          onSkip={() => {
            setShowLaunchMeet(false);
            setActiveTab("home");
          }}
        />
      </div>
    );
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
