"use client";

import { motion } from "framer-motion";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";

const STAGE_COLORS = {
  awake: "#EF4444",
  light: "#71717A",
  deep: "#3B82F6",
  rem: "#A78BFA",
} as const;

interface StageInfo {
  key: string;
  label: string;
  minutes: number;
  color: string;
}

export function SleepTimeline() {
  const sleepData = useAppStore((s) => s.sleepData);
  const latest = sleepData[0];

  const totalMinutes =
    latest.awakeMinutes + latest.lightMinutes + latest.deepMinutes + latest.remMinutes;

  const stages: StageInfo[] = [
    { key: "awake", label: "Awake", minutes: latest.awakeMinutes, color: STAGE_COLORS.awake },
    { key: "light", label: "Light", minutes: latest.lightMinutes, color: STAGE_COLORS.light },
    { key: "deep", label: "Deep", minutes: latest.deepMinutes, color: STAGE_COLORS.deep },
    { key: "rem", label: "REM", minutes: latest.remMinutes, color: STAGE_COLORS.rem },
  ];

  function formatMinutes(min: number): string {
    const h = Math.floor(min / 60);
    const m = min % 60;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  return (
    <div className="rounded-xl border border-border bg-surface p-4">
      <h3 className="mb-3 text-sm font-semibold text-white">Sleep Stages</h3>

      {/* Timeline bar */}
      <div className="relative flex h-8 w-full overflow-hidden rounded-lg">
        {stages.map((stage) => {
          const widthPercent = totalMinutes > 0 ? (stage.minutes / totalMinutes) * 100 : 0;
          const isDeep = stage.key === "deep";

          return (
            <motion.div
              key={stage.key}
              className={cn(
                "relative",
                isDeep ? "h-full z-10" : "h-full"
              )}
              style={{
                backgroundColor: stage.color,
                ...(isDeep && {
                  boxShadow: `0 0 12px ${stage.color}80, 0 0 4px ${stage.color}60`,
                }),
              }}
              initial={{ width: 0 }}
              animate={{ width: `${widthPercent}%` }}
              transition={{
                duration: 0.8,
                ease: [0.25, 0.46, 0.45, 0.94],
                delay: stages.indexOf(stage) * 0.1,
              }}
            />
          );
        })}
      </div>

      {/* Deep sleep emphasis bar (slightly taller overlay) */}
      {(() => {
        const beforeDeep = latest.awakeMinutes + latest.lightMinutes;
        const deepLeft = totalMinutes > 0 ? (beforeDeep / totalMinutes) * 100 : 0;
        const deepWidth = totalMinutes > 0 ? (latest.deepMinutes / totalMinutes) * 100 : 0;
        return (
          <motion.div
            className="relative -mt-10 mx-0 h-10 rounded-md pointer-events-none"
            style={{
              marginLeft: `${deepLeft}%`,
              width: `${deepWidth}%`,
              background: `linear-gradient(180deg, ${STAGE_COLORS.deep}40 0%, transparent 100%)`,
            }}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.6, duration: 0.5 }}
          />
        );
      })()}

      {/* Legend */}
      <div className="mt-4 flex flex-wrap gap-x-4 gap-y-2">
        {stages.map((stage) => (
          <div key={stage.key} className="flex items-center gap-1.5">
            <div
              className={cn(
                "h-2.5 w-2.5 rounded-full",
                stage.key === "deep" && "ring-1 ring-steel/40"
              )}
              style={{ backgroundColor: stage.color }}
            />
            <span className="text-xs text-text-secondary">
              {stage.label}
            </span>
            <span className="text-xs font-medium text-white">
              {formatMinutes(stage.minutes)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
