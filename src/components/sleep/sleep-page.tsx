"use client";

import dynamic from "next/dynamic";
import { SleepScoreRing } from "@/components/sleep/sleep-score-ring";
import { SleepTimeline } from "@/components/sleep/sleep-timeline";
import { SleepBreakdown } from "@/components/sleep/sleep-breakdown";
import { AiSleepInsight } from "@/components/sleep/ai-sleep-insight";
import { PremiumAtmosphere, PremiumEntrance } from "@/components/brand/premium-atmosphere";

const RecoveryTrends = dynamic(
  () => import("@/components/sleep/recovery-trends").then((m) => m.RecoveryTrends),
  {
    ssr: false,
    loading: () => (
      <div className="h-48 animate-pulse rounded-2xl bg-white/[0.04]" aria-label="Loading trends" />
    ),
  }
);

export function SleepPage() {
  return (
    <div className="relative bg-background">
      <PremiumAtmosphere accent="#60A5FA" secondary="#A9D8FF" intensity={0.45} />
      <div className="relative z-10 px-4 pb-6 pt-12">
        <PremiumEntrance index={0}>
          <h1 className="mb-2 text-2xl font-semibold tracking-tight text-text-primary">
            Sleep & Recovery
          </h1>
          <p className="mb-6 text-sm text-text-tertiary">
            Last night&apos;s rebuild — and how to use it today.
          </p>
        </PremiumEntrance>

        <div className="flex flex-col gap-5">
          <PremiumEntrance index={1}>
            <SleepScoreRing />
          </PremiumEntrance>
          <PremiumEntrance index={2}>
            <SleepTimeline />
          </PremiumEntrance>
          <PremiumEntrance index={3}>
            <SleepBreakdown />
          </PremiumEntrance>
          <PremiumEntrance index={4}>
            <RecoveryTrends />
          </PremiumEntrance>
          <PremiumEntrance index={5}>
            <AiSleepInsight />
          </PremiumEntrance>
        </div>
      </div>
    </div>
  );
}
