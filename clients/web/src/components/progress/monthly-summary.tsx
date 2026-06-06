"use client";

import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.08,
      delayChildren: 0.1,
    },
  },
};

const itemVariants = {
  hidden: { opacity: 0, y: 12 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.4, ease: "easeOut" as const },
  },
};

interface StatPillProps {
  value: string;
  label: string;
  className?: string;
}

function StatPill({ value, label, className }: StatPillProps) {
  return (
    <motion.div
      variants={itemVariants}
      className={cn(
        "flex flex-1 flex-col items-center gap-1 rounded-xl bg-surface-elevated px-4 py-3",
        className,
      )}
    >
      <span className="text-xl font-bold text-text-primary">{value}</span>
      <span className="whitespace-nowrap text-[11px] text-text-tertiary">{label}</span>
    </motion.div>
  );
}

function formatRecoveryDelta(delta: number): string {
  const sign = delta >= 0 ? "+" : "";
  return `${sign}${Math.round(delta)}%`;
}

export function MonthlySummary() {
  const progressSummary = useAppStore((s) => s.progressSummary);
  const workoutHistory = useAppStore((s) => s.workoutHistory);
  const personalRecords = useAppStore((s) => s.personalRecords);
  const dataLoadState = useAppStore((s) => s.dataLoadState);

  const workouts =
    progressSummary?.workoutsCompleted ?? workoutHistory.length;
  const newPRs =
    progressSummary?.newPersonalRecords.length ?? personalRecords.length;
  const recoveryDelta = progressSummary?.recoveryConsistencyDelta;
  const summary =
    progressSummary?.summary ??
    (dataLoadState === "offline"
      ? "You're viewing demo data. Start the backend to see your real progress."
      : "Complete a few workouts and connect a wearable to unlock your monthly summary.");

  return (
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      className="relative overflow-hidden rounded-2xl border border-border bg-surface"
    >
      <div className="absolute inset-x-0 top-0 h-[2px] bg-gradient-to-r from-ember via-ember-light to-ember" />

      <div className="p-5">
        <motion.p
          variants={itemVariants}
          className="mb-4 text-xs font-medium uppercase tracking-wider text-text-tertiary"
        >
          Last {progressSummary?.periodDays ?? 30} Days
        </motion.p>

        <div className="mb-4 flex gap-2.5">
          <StatPill value={String(workouts)} label="Workouts" />
          <StatPill value={String(newPRs)} label="New PRs" />
          <StatPill
            value={recoveryDelta != null ? formatRecoveryDelta(recoveryDelta) : "—"}
            label="Recovery"
          />
        </div>

        <motion.p
          variants={itemVariants}
          className="text-sm leading-relaxed text-text-secondary"
        >
          {summary}
        </motion.p>
      </div>
    </motion.div>
  );
}