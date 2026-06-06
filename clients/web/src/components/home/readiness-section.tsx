"use client";

import { motion } from "framer-motion";
import { useAppStore } from "@/stores/useAppStore";
import { ReadinessRing } from "@/components/shared/readiness-ring";
import { getReadinessColor } from "@/lib/utils";

interface BreakdownItem {
  label: string;
  value: number;
  inverted?: boolean;
}

function BreakdownDot({ color }: { color: string }) {
  return (
    <span
      className="inline-block h-2 w-2 rounded-full flex-shrink-0"
      style={{ backgroundColor: color }}
    />
  );
}

function BreakdownCard({ item, index }: { item: BreakdownItem; index: number }) {
  // For stress, lower is better, so we invert the display score for color
  const displayValue = item.inverted ? 100 - item.value : item.value;
  const color = getReadinessColor(displayValue);

  return (
    <motion.div
      className="flex items-center gap-2.5 rounded-xl bg-surface-elevated px-3 py-2.5"
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.6 + index * 0.1, duration: 0.3, ease: "easeOut" }}
    >
      <BreakdownDot color={color} />
      <div className="flex flex-1 items-center justify-between min-w-0">
        <span className="text-xs text-text-secondary">{item.label}</span>
        <span className="text-sm font-semibold text-text-primary">
          {item.inverted ? `${100 - item.value}%` : `${item.value}%`}
        </span>
      </div>
    </motion.div>
  );
}

export function ReadinessSection() {
  const readiness = useAppStore((s) => s.readiness);

  const breakdownItems: BreakdownItem[] = [
    { label: "Sleep Quality", value: readiness.sleepQuality },
    { label: "Recovery", value: readiness.recoveryScore },
    { label: "Stress", value: readiness.stressLevel, inverted: true },
    { label: "Energy Bank", value: readiness.energyBank },
  ];

  return (
    <motion.div
      className="rounded-2xl bg-surface p-5"
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: 0.1, ease: "easeOut" }}
    >
      {/* Section label */}
      <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider mb-5">
        Readiness Score
      </p>

      {/* Centered ring */}
      <div className="flex justify-center mb-6">
        <ReadinessRing score={readiness.overall} size={180} strokeWidth={14} showLabel />
      </div>

      {/* Breakdown grid */}
      <div className="grid grid-cols-2 gap-2.5">
        {breakdownItems.map((item, index) => (
          <BreakdownCard key={item.label} item={item} index={index} />
        ))}
      </div>
    </motion.div>
  );
}
