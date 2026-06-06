"use client";

import { useAppStore } from "@/stores/useAppStore";
import { AiGreeting } from "@/components/home/ai-greeting";
import { ReadinessSection } from "@/components/home/readiness-section";
import { TodayPlanCard } from "@/components/home/today-plan-card";
import { QuickStats } from "@/components/home/quick-stats";

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
    <div className="flex flex-col gap-6 pt-12 px-4 pb-4">
      <AiGreeting />
      <ReadinessSection />
      {todayWorkout && (
        <TodayPlanCard
          workout={todayWorkout}
          onStart={handleStartWorkout}
          onChangePlan={handleChangePlan}
        />
      )}
      <QuickStats />
    </div>
  );
}
