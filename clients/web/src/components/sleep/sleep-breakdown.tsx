"use client";

import { motion } from "framer-motion";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";

const DEEP_GOAL = 90;
const REM_GOAL = 90;

function formatMinutesToHrMin(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h > 0) return `${h}hr ${m}min`;
  return `${m}min`;
}

interface BreakdownCardProps {
  label: string;
  value: string;
  progress?: number; // 0-100
  progressColor: string;
  subtitle?: string;
  index: number;
}

function BreakdownCard({
  label,
  value,
  progress,
  progressColor,
  subtitle,
  index,
}: BreakdownCardProps) {
  return (
    <motion.div
      className="flex flex-col gap-2 rounded-xl border border-border bg-surface p-3"
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.1 * index, duration: 0.4, ease: "easeOut" }}
    >
      <span className="text-xs font-medium text-text-secondary">{label}</span>
      <span className="text-lg font-bold text-white">{value}</span>

      {progress !== undefined && (
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-border">
          <motion.div
            className="h-full rounded-full"
            style={{ backgroundColor: progressColor }}
            initial={{ width: 0 }}
            animate={{ width: `${Math.min(progress, 100)}%` }}
            transition={{ duration: 0.8, ease: "easeOut", delay: 0.2 + 0.1 * index }}
          />
        </div>
      )}

      {subtitle && (
        <span className="text-[10px] text-text-tertiary">{subtitle}</span>
      )}
    </motion.div>
  );
}

export function SleepBreakdown() {
  const sleepData = useAppStore((s) => s.sleepData);
  const latest = sleepData[0];

  const deepPercent = (latest.deepMinutes / DEEP_GOAL) * 100;
  const remPercent = (latest.remMinutes / REM_GOAL) * 100;

  const totalSleepMinutes = latest.totalHours * 60;
  const efficiency =
    totalSleepMinutes > 0
      ? ((totalSleepMinutes - latest.awakeMinutes) / totalSleepMinutes) * 100
      : 0;

  const cards: BreakdownCardProps[] = [
    {
      label: "Deep Sleep",
      value: formatMinutesToHrMin(latest.deepMinutes),
      progress: deepPercent,
      progressColor: deepPercent >= 100 ? "#FF4D00" : "#3B82F6",
      subtitle: `${Math.round(deepPercent)}% of ${DEEP_GOAL}min goal`,
      index: 0,
    },
    {
      label: "REM Sleep",
      value: formatMinutesToHrMin(latest.remMinutes),
      progress: remPercent,
      progressColor: remPercent >= 100 ? "#FF4D00" : "#3B82F6",
      subtitle: `${Math.round(remPercent)}% of ${REM_GOAL}min goal`,
      index: 1,
    },
    {
      label: "Sleep Efficiency",
      value: `${Math.round(efficiency)}%`,
      progress: efficiency,
      progressColor: efficiency >= 85 ? "#22C55E" : efficiency >= 75 ? "#EAB308" : "#EF4444",
      subtitle: efficiency >= 85 ? "Excellent" : efficiency >= 75 ? "Good" : "Needs improvement",
      index: 2,
    },
    {
      label: "Time Awake",
      value: `${latest.awakeMinutes}min`,
      progress: undefined,
      progressColor: "#EF4444",
      subtitle: latest.awakeMinutes <= 15 ? "Great" : latest.awakeMinutes <= 30 ? "Normal" : "High",
      index: 3,
    },
  ];

  return (
    <div>
      <h3 className="mb-3 text-sm font-semibold text-white">Breakdown</h3>
      <div className="grid grid-cols-2 gap-3">
        {cards.map((card) => (
          <BreakdownCard key={card.label} {...card} />
        ))}
      </div>
    </div>
  );
}
