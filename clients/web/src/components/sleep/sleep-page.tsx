"use client";

import { useEffect } from "react";
import { RefreshCw } from "lucide-react";
import { SleepScoreRing } from "@/components/sleep/sleep-score-ring";
import { SleepTimeline } from "@/components/sleep/sleep-timeline";
import { SleepBreakdown } from "@/components/sleep/sleep-breakdown";
import { RecoveryTrends } from "@/components/sleep/recovery-trends";
import { AiSleepInsight } from "@/components/sleep/ai-sleep-insight";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";

export function SleepPage() {
  const { refreshSleepData, isRefreshingSleep } = useAppStore();

  useEffect(() => {
    void refreshSleepData(14);
  }, [refreshSleepData]);

  return (
    <div className="min-h-[100dvh] bg-background">
      <div className="px-4 pt-12">
        <div className="mb-6 flex items-center justify-between">
          <h1 className="text-2xl font-bold text-white">Sleep & Recovery</h1>
          <button
            type="button"
            onClick={() => void refreshSleepData(14)}
            disabled={isRefreshingSleep}
            className={cn(
              "inline-flex items-center gap-1.5 rounded-lg bg-surface px-3 py-2 text-xs font-medium text-text-secondary",
              isRefreshingSleep && "opacity-60",
            )}
          >
            <RefreshCw size={14} className={isRefreshingSleep ? "animate-spin" : ""} />
            {isRefreshingSleep ? "Syncing" : "Refresh"}
          </button>
        </div>

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
