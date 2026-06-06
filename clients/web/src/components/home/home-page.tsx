"use client";

import { motion } from "framer-motion";
import { Dumbbell, MessageCircle } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { AiGreeting } from "@/components/home/ai-greeting";
import { ReadinessSection } from "@/components/home/readiness-section";
import { TodayPlanCard } from "@/components/home/today-plan-card";
import { QuickStats } from "@/components/home/quick-stats";
import { cn } from "@/lib/utils";

function HomeLoadingSkeleton() {
  return (
    <div className="flex flex-col gap-4 animate-pulse">
      <div className="h-28 rounded-2xl bg-surface" />
      <div className="h-40 rounded-2xl bg-surface" />
      <div className="h-48 rounded-2xl bg-surface" />
    </div>
  );
}

function EmptyTodayPlanCard({
  onChat,
  onWorkout,
}: {
  onChat: () => void;
  onWorkout: () => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className={cn(
        "rounded-2xl border border-dashed border-border bg-surface p-5",
        "flex flex-col gap-4",
      )}
    >
      <div className="flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-full bg-ember/15">
          <Dumbbell size={18} className="text-ember" />
        </div>
        <div>
          <p className="text-sm font-semibold text-text-primary">No plan for today yet</p>
          <p className="text-xs text-text-secondary">
            Ask ARIA to build a session matched to your readiness.
          </p>
        </div>
      </div>
      <div className="flex gap-2">
        <button
          type="button"
          onClick={onChat}
          className="flex flex-1 items-center justify-center gap-2 rounded-xl bg-ember px-4 py-3 text-sm font-semibold text-white"
        >
          <MessageCircle size={16} />
          Ask ARIA
        </button>
        <button
          type="button"
          onClick={onWorkout}
          className="rounded-xl border border-border px-4 py-3 text-sm font-medium text-text-secondary"
        >
          Browse
        </button>
      </div>
    </motion.div>
  );
}

export function HomePage() {
  const { todayWorkout, startWorkout, setActiveTab, dataLoadState } = useAppStore();

  const handleStartWorkout = () => {
    startWorkout();
    setActiveTab("workout");
  };

  const handleChangePlan = () => {
    setActiveTab("chat");
  };

  return (
    <div className="flex flex-col gap-6 pt-12 px-4 pb-4">
      {dataLoadState === "loading" ? (
        <HomeLoadingSkeleton />
      ) : (
        <>
          <AiGreeting />
          <ReadinessSection />
          {todayWorkout ? (
            <TodayPlanCard
              workout={todayWorkout}
              onStart={handleStartWorkout}
              onChangePlan={handleChangePlan}
            />
          ) : (
            <EmptyTodayPlanCard
              onChat={() => setActiveTab("chat")}
              onWorkout={() => setActiveTab("workout")}
            />
          )}
          <QuickStats />
        </>
      )}
    </div>
  );
}