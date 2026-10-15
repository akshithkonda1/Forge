"use client";

import { useMemo } from "react";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  ResponsiveContainer,
  Tooltip,
  CartesianGrid,
} from "recharts";
import { motion } from "framer-motion";
import { useAppStore } from "@/stores/useAppStore";

const DAY_ABBREVIATIONS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function getDayAbbr(dateStr: string): string {
  const date = new Date(dateStr + "T00:00:00");
  return DAY_ABBREVIATIONS[date.getDay()];
}

interface CustomTooltipProps {
  active?: boolean;
  payload?: Array<{ name: string; value: number; color: string }>;
  label?: string;
}

function CustomTooltip({ active, payload, label }: CustomTooltipProps) {
  if (!active || !payload || payload.length === 0) return null;
  return (
    <div className="rounded-lg border border-border bg-surface-elevated px-3 py-2 shadow-lg">
      <p className="mb-1 text-xs text-text-tertiary">{label}</p>
      {payload.map((entry) => (
        <p key={entry.name} className="text-xs font-medium" style={{ color: entry.color }}>
          {entry.name}: {entry.value}
        </p>
      ))}
    </div>
  );
}

export function RecoveryTrends() {
  const sleepData = useAppStore((s) => s.sleepData);

  const recoveryChartData = useMemo(() => {
    // Show last 7 days, sleepData is newest first so slice then reverse
    return sleepData.slice(0, 7).reverse().map((d) => ({
      day: getDayAbbr(d.date),
      score: d.score,
    }));
  }, [sleepData]);

  return (
    <div className="flex flex-col gap-5">
      {/* Sleep score trend */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
      >
        <h3 className="type-headline mb-3 text-text-primary">Sleep trend</h3>
        <div className="rounded-2xl bg-surface p-5">
          <ResponsiveContainer width="100%" height={160}>
            <AreaChart data={recoveryChartData} margin={{ top: 5, right: 5, left: -20, bottom: 0 }}>
              <defs>
                <linearGradient id="recoveryFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#3B82F6" stopOpacity={0.3} />
                  <stop offset="100%" stopColor="#3B82F6" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid stroke="none" />
              <XAxis
                dataKey="day"
                axisLine={false}
                tickLine={false}
                tick={{ fill: "#71717A", fontSize: 11 }}
              />
              <YAxis
                domain={[40, 100]}
                axisLine={false}
                tickLine={false}
                tick={{ fill: "#71717A", fontSize: 11 }}
              />
              <Tooltip content={<CustomTooltip />} />
              <Area
                type="monotone"
                dataKey="score"
                name="Score"
                stroke="#3B82F6"
                strokeWidth={2}
                fill="url(#recoveryFill)"
                dot={{ fill: "#3B82F6", strokeWidth: 0, r: 3 }}
                activeDot={{ fill: "#60A5FA", strokeWidth: 0, r: 5 }}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </motion.div>

      <p className="text-sm text-text-secondary">
        Heart-rate context stays on your Watch and in ARIA&apos;s notes — this companion
        chart is last night&apos;s sleep score only.
      </p>
    </div>
  );
}
