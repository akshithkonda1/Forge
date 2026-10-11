"use client";

import dynamic from "next/dynamic";
import { useAppStore } from "@/stores/useAppStore";
import { SleepScoreRing } from "@/components/sleep/sleep-score-ring";
import { SleepTimeline } from "@/components/sleep/sleep-timeline";
import { SleepBreakdown } from "@/components/sleep/sleep-breakdown";
import { PageHeader } from "@/components/ui/card";
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
  const hasSleep = useAppStore((s) => s.sleepData.length > 0);

  return (
    <div className="relative bg-background">
      <PremiumAtmosphere accent="#60A5FA" secondary="#A9D8FF" intensity={0.45} />
      <div className="relative z-10 px-4 pb-6 pt-12">
        <PremiumEntrance index={0}>
          <PageHeader
            className="mb-5"
            title="Sleep & Recovery"
            subtitle="Last night’s rebuild — and how to use it today."
          />
        </PremiumEntrance>

        <div className="flex flex-col gap-5">
          {hasSleep ? (
            <>
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
            </>
          ) : (
            <PremiumEntrance index={1}>
              <p className="text-sm text-text-secondary">No sleep yet</p>
            </PremiumEntrance>
          )}
          <PremiumEntrance index={5}>
            <AiSleepInsight />
          </PremiumEntrance>
        </div>
      </div>
    </div>
  );
}
