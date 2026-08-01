"use client";

import { motion } from "framer-motion";
import { Footprints, Flame, Activity, Heart } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { MetricPill } from "@/components/shared/metric-pill";
import { formatNumber } from "@/lib/utils";

export function QuickStats() {
  const dailyMetrics = useAppStore((s) => s.dailyMetrics);

  const metrics = [
    {
      icon: <Footprints size={14} />,
      label: "Steps",
      value: formatNumber(dailyMetrics.steps),
      trend: "up" as const,
    },
    {
      icon: <Flame size={14} />,
      label: "Calories",
      value: `${dailyMetrics.activeCalories} cal`,
      trend: "up" as const,
    },
    {
      icon: <Activity size={14} />,
      label: "HRV",
      value: `${dailyMetrics.hrv} ms`,
      trend: "up" as const,
    },
    {
      icon: <Heart size={14} />,
      label: "Resting HR",
      value: `${dailyMetrics.restingHR} bpm`,
      trend: "down" as const,
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

  return (
    <div>
      <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider mb-3">
        Today&apos;s Metrics
      </p>
      <motion.div
        className="flex gap-2.5 overflow-x-auto pb-2 -mx-4 px-4 scrollbar-hide"
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
