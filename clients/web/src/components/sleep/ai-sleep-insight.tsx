"use client";

import { motion } from "framer-motion";
import { MessageCircle } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";

export function AiSleepInsight() {
  const setActiveTab = useAppStore((s) => s.setActiveTab);
  const coachingInsights = useAppStore((s) => s.coachingInsights);
  const progressSummary = useAppStore((s) => s.progressSummary);
  const sleepData = useAppStore((s) => s.sleepData);
  const dailyMetrics = useAppStore((s) => s.dailyMetrics);

  const sleepInsight = coachingInsights.find((i) => i.type === "sleep");
  const latest = sleepData[0];
  const text = sleepInsight
    ? `${sleepInsight.observation} ${sleepInsight.recommendation}`
    : progressSummary?.summary
      ? progressSummary.summary
      : !latest
        ? "Connect Apple Health or a wearable to unlock personalized sleep coaching."
        : latest.score >= 85
          ? `Excellent recovery. ${Math.floor(latest.deepMinutes / 60)}hr ${latest.deepMinutes % 60}min of deep sleep has you primed for a heavy session today.`
          : latest.score >= 70
            ? `Good sleep — ${Math.floor(latest.deepMinutes / 60)}hr ${latest.deepMinutes % 60}min of deep sleep. Cut screens 45 minutes before bed to push this score higher.`
            : dailyMetrics.deepSleep > 0
              ? `Only ${Math.floor(dailyMetrics.deepSleep / 60)}hr ${dailyMetrics.deepSleep % 60}min of deep sleep last night. Consider a lighter session and an earlier bedtime tonight.`
              : "Connect a wearable to unlock personalized sleep coaching.";

  return (
    <motion.div
      className={cn(
        "rounded-xl border border-border bg-surface",
        "border-l-2 border-l-ember",
        "p-4",
      )}
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: 0.2 }}
    >
      <div className="mb-2 flex items-center gap-2">
        <div className="h-1.5 w-1.5 rounded-full bg-ember" />
        <span className="text-xs font-medium text-ember">Forge AI</span>
      </div>

      <p className="text-sm leading-relaxed text-text-secondary">{text}</p>

      <button
        type="button"
        onClick={() => setActiveTab("chat")}
        className={cn(
          "mt-3 inline-flex items-center gap-1.5",
          "text-xs font-medium text-text-secondary",
          "transition-colors hover:text-text-primary",
        )}
      >
        <MessageCircle size={13} />
        Chat about this
      </button>
    </motion.div>
  );
}