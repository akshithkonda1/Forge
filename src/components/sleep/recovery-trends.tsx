"use client";

import { useMemo } from "react";
import {
  AreaChart,
  Area,
  LineChart,
  Line,
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

// Mock HRV data around 45-58 range for 7 days
const MOCK_HRV_VALUES = [48, 45, 55, 42, 58, 50, 52];
const MOCK_RHR_VALUES = [60, 62, 57, 63, 56, 59, 58];

export function RecoveryTrends() {
  const sleepData = useAppStore((s) => s.sleepData);

  const recoveryChartData = useMemo(() => {
    // sleepData is newest first, reverse for chronological chart
    return [...sleepData].reverse().map((d) => ({
      day: getDayAbbr(d.date),
      score: d.score,
    }));
  }, [sleepData]);

  const hrvChartData = useMemo(() => {
    return [...sleepData].reverse().map((d, i) => ({
      day: getDayAbbr(d.date),
      hrv: MOCK_HRV_VALUES[i] ?? 50,
      rhr: MOCK_RHR_VALUES[i] ?? 60,
    }));
  }, [sleepData]);

  return (
    <div className="flex flex-col gap-5">
      {/* Recovery Trend Chart */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
      >
        <h3 className="mb-3 text-sm font-semibold text-white">Recovery Trend</h3>
        <div className="rounded-xl border border-border bg-surface p-3">
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

      {/* HRV Trend Chart */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5, delay: 0.15 }}
      >
        <h3 className="mb-3 text-sm font-semibold text-white">HRV & Resting HR</h3>
        <div className="rounded-xl border border-border bg-surface p-3">
          <ResponsiveContainer width="100%" height={160}>
            <LineChart data={hrvChartData} margin={{ top: 5, right: 5, left: -20, bottom: 0 }}>
              <CartesianGrid stroke="none" />
              <XAxis
                dataKey="day"
                axisLine={false}
                tickLine={false}
                tick={{ fill: "#71717A", fontSize: 11 }}
              />
              <YAxis
                axisLine={false}
                tickLine={false}
                tick={{ fill: "#71717A", fontSize: 11 }}
              />
              <Tooltip content={<CustomTooltip />} />
              <Line
                type="monotone"
                dataKey="hrv"
                name="HRV"
                stroke="#3B82F6"
                strokeWidth={2}
                dot={{ fill: "#3B82F6", strokeWidth: 0, r: 3 }}
                activeDot={{ fill: "#60A5FA", strokeWidth: 0, r: 5 }}
              />
              <Line
                type="monotone"
                dataKey="rhr"
                name="Resting HR"
                stroke="#FF4D00"
                strokeWidth={2}
                dot={{ fill: "#FF4D00", strokeWidth: 0, r: 3 }}
                activeDot={{ fill: "#FF6B2B", strokeWidth: 0, r: 5 }}
              />
            </LineChart>
          </ResponsiveContainer>

          {/* Legend */}
          <div className="mt-2 flex items-center justify-center gap-5">
            <div className="flex items-center gap-1.5">
              <div className="h-2 w-2 rounded-full bg-steel" />
              <span className="text-[10px] text-text-secondary">HRV (ms)</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="h-2 w-2 rounded-full bg-ember" />
              <span className="text-[10px] text-text-secondary">Resting HR (bpm)</span>
            </div>
          </div>
        </div>
      </motion.div>
    </div>
  );
}
