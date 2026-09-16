"use client";

import dynamic from "next/dynamic";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { useAppStore, type TabId } from "@/stores/useAppStore";
import { BottomNav } from "@/components/shared/bottom-nav";
import { HomePage } from "@/components/home/home-page";
import { ChatPage } from "@/components/chat/chat-page";
import { WorkoutPage } from "@/components/workout/workout-page";
import { AriaIntro } from "@/components/brand/aria-intro";
import { AriaMark } from "@/components/brand/aria-mark";
import {
  ForgeBrandMark,
  PremiumAtmosphere,
  PremiumFloat,
  PremiumPresenceBloom,
} from "@/components/brand/premium-atmosphere";
import { forgeSplashHoldMs, peekPersistedOnboarded } from "@/lib/forge-splash";
import { cn } from "@/lib/utils";

const SleepPage = dynamic(
  () => import("@/components/sleep/sleep-page").then((m) => m.SleepPage),
  {
    ssr: false,
    loading: () => <TabSkeleton label="Sleep" />,
  }
);

const ProfileTab = dynamic(
  () => import("@/components/profile/profile-tab").then((m) => m.ProfileTab),
  {
    ssr: false,
    loading: () => <TabSkeleton label="You" />,
  }
);

const TABS: TabId[] = ["home", "chat", "workout", "sleep", "profile"];
let didFinishSplash = false;

function TabSkeleton({ label }: { label: string }) {
  return (
    <div className="flex flex-1 flex-col gap-4 px-4 pb-8 pt-12" aria-busy="true" aria-label={`Loading ${label}`}>
      <div className="h-8 w-40 animate-pulse rounded-lg bg-white/[0.06]" />
      <div className="h-36 animate-pulse rounded-2xl bg-white/[0.05]" />
      <div className="h-24 animate-pulse rounded-2xl bg-white/[0.04]" />
      <div className="h-24 animate-pulse rounded-2xl bg-white/[0.04]" />
    </div>
  );
}

function BootSplash({
  live = false,
  compact = false,
}: {
  live?: boolean;
  compact?: boolean;
}) {
  return (
    <div className="relative flex min-h-[100dvh] flex-col items-center justify-center overflow-hidden bg-background">
      <PremiumAtmosphere accent="#FF6B2B" secondary="#A9D8FF" intensity={compact ? 0.55 : 0.9} />
      <div className="relative z-10 flex flex-col items-center">
        {compact ? (
          <div className="relative flex h-28 w-28 items-center justify-center">
            <AriaMark size={72} speaking={false} label="ARIA" className="relative z-10" />
          </div>
        ) : (
          <PremiumFloat className="relative flex h-56 w-56 items-center justify-center">
            <PremiumPresenceBloom size={220} />
            <AriaMark size={148} speaking={live} label="ARIA" className="relative z-10" />
          </PremiumFloat>
        )}
        <div className="premium-enter mt-5 flex items-center gap-2.5 text-[28px] font-semibold tracking-[0.22em] text-[#F7F4F0]">
          <ForgeBrandMark size={22} />
          FORGE
        </div>
        <p className="premium-kicker-glow mt-3 text-[12px] font-medium uppercase tracking-[0.32em] text-text-tertiary">
          {compact ? "Loading…" : "Forged."}
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
  const chatMessages = useAppStore((s) => s.chatMessages);
  const seedAriaWelcome = useAppStore((s) => s.seedAriaWelcome);
  const hasHydrated = useAppStore((s) => s.hasHydrated);
  const setHasHydrated = useAppStore((s) => s.setHasHydrated);
  const activeTab = useAppStore((s) => s.activeTab);
  const setActiveTab = useAppStore((s) => s.setActiveTab);
  const workoutActive = useAppStore((s) => s.activeWorkout.isActive);
  const mainRef = useRef<HTMLElement>(null);
  const [visited, setVisited] = useState<TabId[]>([activeTab]);
  const [showLaunchMeet, setShowLaunchMeet] = useState(true);
  const [returning] = useState(() => peekPersistedOnboarded());
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
    }, forgeSplashHoldMs(reduce, { returning }));
    return () => window.clearTimeout(timer);
  }, [showSplash, returning]);

  useEffect(() => {
    if (!hasHydrated) return;
    if (!isOnboarded) {
      router.replace("/onboarding");
    }
  }, [hasHydrated, isOnboarded, router]);

  useEffect(() => {
    if (!hasHydrated || !isOnboarded) return;
    if (chatMessages.length === 0) {
      seedAriaWelcome();
    }
  }, [hasHydrated, isOnboarded, chatMessages.length, seedAriaWelcome]);

  useEffect(() => {
    setVisited((prev) => (prev.includes(activeTab) ? prev : [...prev, activeTab]));
    mainRef.current?.scrollTo({ top: 0 });
    window.scrollTo(0, 0);
  }, [activeTab]);

  if (showSplash) {
    return <BootSplash live={!returning} compact={returning} />;
  }

  if (!hasHydrated || !isOnboarded) {
    return <BootSplash compact />;
  }

  // Skip intro when they've already met ARIA or already have a welcome in chat.
  const waitingToMeet =
    !hasMetAria && chatMessages.length === 0 && (activeTab === "chat" || showLaunchMeet);
  if (waitingToMeet) {
    return (
      <div className="app-shell relative mx-auto min-h-[100dvh] w-full max-w-lg bg-background">
        <AriaIntro
          onContinue={() => {
            meetAria();
            if (chatMessages.length === 0) seedAriaWelcome();
            setShowLaunchMeet(false);
            setActiveTab("chat");
          }}
          onSkip={() => {
            meetAria();
            if (chatMessages.length === 0) seedAriaWelcome();
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
