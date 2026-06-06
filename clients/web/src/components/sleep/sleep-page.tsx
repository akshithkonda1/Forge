"use client";

import { SleepScoreRing } from "@/components/sleep/sleep-score-ring";
import { SleepTimeline } from "@/components/sleep/sleep-timeline";
import { SleepBreakdown } from "@/components/sleep/sleep-breakdown";
import { RecoveryTrends } from "@/components/sleep/recovery-trends";
import { AiSleepInsight } from "@/components/sleep/ai-sleep-insight";

export function SleepPage() {
  return (
    <div className="min-h-screen bg-background pb-24">
      <div className="mx-auto max-w-md px-4 pt-12">
        {/* Page title */}
        <h1 className="mb-6 text-2xl font-bold text-white">Sleep & Recovery</h1>

        {/* Sections */}
        <div className="flex flex-col gap-6">
          <SleepScoreRing />
          <SleepTimeline />
          <SleepBreakdown />
          <RecoveryTrends />
          <AiSleepInsight />
        </div>
      </div>
    </div>
  );
}
