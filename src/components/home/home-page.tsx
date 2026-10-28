"use client";

import { useAppStore } from "@/stores/useAppStore";
import { AiGreeting } from "@/components/home/ai-greeting";
import { ReadinessSection } from "@/components/home/readiness-section";
import { TodayPlanCard } from "@/components/home/today-plan-card";
import { QuickStats } from "@/components/home/quick-stats";
import { BodyTalkCard } from "@/components/home/body-talk-card";
import { MorningCardView } from "@/components/home/morning-card";
import { PremiumAtmosphere, PremiumEntrance } from "@/components/brand/premium-atmosphere";
import { buildMorningCard } from "@/lib/aria-morning-card";

export function HomePage() {
  const { todayWorkout, startWorkout, setActiveTab, readiness, dailyMetrics } = useAppStore();
  const morning = buildMorningCard({
    numbers: {
      sleepHours: dailyMetrics.totalSleep > 0 ? dailyMetrics.totalSleep / 60 : null,
      readiness: readiness.overall || null,
    },
    gymLabel: "home",
    hasLifeSignal: (readiness.overall ?? 0) > 0 || dailyMetrics.totalSleep > 0,
  });

  const handleStartWorkout = () => {
    startWorkout();
    setActiveTab("workout");
  };

  const handleChangePlan = () => {
    setActiveTab("chat");
  };

  return (
    <div className="relative flex flex-col">
      <PremiumAtmosphere accent="#FF6B2B" secondary="#A9D8FF" intensity={0.4} className="opacity-90" />
      <div className="relative z-10 flex flex-col gap-5 px-4 pb-8 pt-12">
        <PremiumEntrance index={0}>
          <AiGreeting />
        </PremiumEntrance>
        <PremiumEntrance index={1}>
          <ReadinessSection />
        </PremiumEntrance>
        <PremiumEntrance index={2}>
          <MorningCardView card={morning} />
        </PremiumEntrance>
        {todayWorkout && (
          <PremiumEntrance index={3}>
            <TodayPlanCard
              workout={todayWorkout}
              onStart={handleStartWorkout}
              onChangePlan={handleChangePlan}
            />
          </PremiumEntrance>
        )}
        <details className="rounded-2xl bg-surface p-4">
          <summary className="type-eyebrow cursor-pointer text-text-secondary">
            The rest of today
          </summary>
          <div className="mt-4 flex flex-col gap-5">
            <QuickStats />
            <BodyTalkCard />
          </div>
        </details>
      </div>
    </div>
  );
}
