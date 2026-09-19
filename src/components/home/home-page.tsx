"use client";

import { useAppStore } from "@/stores/useAppStore";
import { AiGreeting } from "@/components/home/ai-greeting";
import { ReadinessSection } from "@/components/home/readiness-section";
import { TodayPlanCard } from "@/components/home/today-plan-card";
import { QuickStats } from "@/components/home/quick-stats";
import { BodyTalkCard } from "@/components/home/body-talk-card";
import { PremiumAtmosphere, PremiumEntrance } from "@/components/brand/premium-atmosphere";

export function HomePage() {
  const { todayWorkout, startWorkout, setActiveTab } = useAppStore();

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
        {todayWorkout && (
          <PremiumEntrance index={2}>
            <TodayPlanCard
              workout={todayWorkout}
              onStart={handleStartWorkout}
              onChangePlan={handleChangePlan}
            />
          </PremiumEntrance>
        )}
        <PremiumEntrance index={3}>
          <QuickStats />
        </PremiumEntrance>
        <PremiumEntrance index={4}>
          <BodyTalkCard />
        </PremiumEntrance>
      </div>
    </div>
  );
}
