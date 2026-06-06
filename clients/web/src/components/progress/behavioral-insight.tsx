"use client";

import { motion } from "framer-motion";
import { useAppStore } from "@/stores/useAppStore";

export function BehavioralInsight() {
  const coachingInsights = useAppStore((s) => s.coachingInsights);
  const setActiveTab = useAppStore((s) => s.setActiveTab);

  const insight =
    coachingInsights.find((i) => i.type === "training" || i.type === "mindset") ??
    coachingInsights[0];

  if (!insight) return null;

  const text = `${insight.observation} ${insight.recommendation}`.trim();

  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: 0.3, ease: "easeOut" }}
      className="relative overflow-hidden rounded-2xl border border-border bg-surface"
    >
      <div className="absolute inset-y-0 left-0 w-[3px] bg-steel" />

      <div className="p-5 pl-6">
        <div className="mb-3 flex items-center gap-2">
          <span className="inline-block h-2 w-2 rounded-full bg-steel" />
          <span className="text-xs font-semibold uppercase tracking-wider text-steel">
            {insight.title || "Forge AI"}
          </span>
        </div>

        <p className="text-sm leading-relaxed text-text-secondary">{text}</p>

        <button
          type="button"
          onClick={() => setActiveTab("chat")}
          className="mt-3 text-xs font-medium text-steel transition-colors hover:text-text-primary"
        >
          Discuss with ARIA →
        </button>
      </div>
    </motion.div>
  );
}