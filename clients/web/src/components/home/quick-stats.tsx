"use client";

import { motion } from "framer-motion";
import { Footprints, Flame, Activity, Heart } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { MetricPill } from "@/components/shared/metric-pill";
import { formatNumber } from "@/lib/utils";

function metricTrend(
  value: number,
  lowerIsBetter = false,
): "up" | "down" | "neutral" | undefined {
  if (value <= 0) return undefined;
  return lowerIsBetter ? "down" : "up";
}

export function QuickStats() {
  const dailyMetrics = useAppStore((s) => s.dailyMetrics);
  const dataLoadState = useAppStore((s) => s.dataLoadState);
  const hasData =
    dailyMetrics.steps > 0 ||
    dailyMetrics.hrv > 0 ||
    dailyMetrics.restingHR > 0 ||
    dataLoadState === "loaded" ||
    dataLoadState === "offline";

  const metrics = [
    {
      icon: <Footprints size={14} />,
      label: "Steps",
      value: dailyMetrics.steps > 0 ? formatNumber(dailyMetrics.steps) : "—",
      trend: metricTrend(dailyMetrics.steps),
    },
    {
      icon: <Flame size={14} />,
      label: "Calories",
      value:
        dailyMetrics.activeCalories > 0
          ? `${formatNumber(dailyMetrics.activeCalories)} cal`
          : "—",
      trend: metricTrend(dailyMetrics.activeCalories),
    },
    {
      icon: <Activity size={14} />,
      label: "HRV",
      value: dailyMetrics.hrv > 0 ? `${dailyMetrics.hrv} ms` : "—",
      trend: metricTrend(dailyMetrics.hrv),
    },
    {
      icon: <Heart size={14} />,
      label: "Resting HR",
      value: dailyMetrics.restingHR > 0 ? `${dailyMetrics.restingHR} bpm` : "—",
      trend: metricTrend(dailyMetrics.restingHR, true),
    },
  ];

  const containerVariants = {
    hidden: { opacity: 0 },
    visible: {
      opacity: 1,
      transition: {
        staggerChildren: 0.08,
        delayChildren: 0.3,
      },
    },
  };

  const itemVariants = {
    hidden: { opacity: 0, y: 8 },
    visible: {
      opacity: 1,
      y: 0,
      transition: { duration: 0.3, ease: "easeOut" as const },
    },
  };

  if (!hasData) return null;

  return (
    <div>
      <p className="mb-3 text-xs font-medium uppercase tracking-wider text-text-tertiary">
        Today&apos;s Metrics
      </p>
      <motion.div
        className="scrollbar-hide -mx-4 flex gap-2.5 overflow-x-auto px-4 pb-2"
        style={{ WebkitOverflowScrolling: "touch" }}
        variants={containerVariants}
        initial="hidden"
        animate="visible"
      >
        {metrics.map((metric) => (
          <motion.div key={metric.label} variants={itemVariants} className="flex-shrink-0">
            <MetricPill
              icon={metric.icon}
              label={metric.label}
              value={metric.value}
              trend={metric.trend}
            />
          </motion.div>
        ))}
      </motion.div>
    </div>
  );
}