"use client";

import * as React from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import { TrendingUp } from "lucide-react";

interface DataInsightCardProps {
  title: string;
  values: number[];
  insight: string;
  color?: string;
}

function Sparkline({
  values,
  color,
  width = 200,
  height = 48,
}: {
  values: number[];
  color: string;
  width?: number;
  height?: number;
}) {
  if (values.length < 2) return null;

  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min || 1;

  const padding = 4;
  const chartWidth = width - padding * 2;
  const chartHeight = height - padding * 2;

  const points = values.map((val, i) => {
    const x = padding + (i / (values.length - 1)) * chartWidth;
    const y = padding + chartHeight - ((val - min) / range) * chartHeight;
    return { x, y };
  });

  const linePath = points
    .map((p, i) => `${i === 0 ? "M" : "L"} ${p.x} ${p.y}`)
    .join(" ");

  // Create area fill path
  const areaPath = `${linePath} L ${points[points.length - 1].x} ${height} L ${points[0].x} ${height} Z`;

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className="overflow-visible"
    >
      <defs>
        <linearGradient
          id={`sparkline-gradient-${color.replace("#", "")}`}
          x1="0"
          y1="0"
          x2="0"
          y2="1"
        >
          <stop offset="0%" stopColor={color} stopOpacity={0.3} />
          <stop offset="100%" stopColor={color} stopOpacity={0} />
        </linearGradient>
      </defs>

      {/* Area fill */}
      <motion.path
        d={areaPath}
        fill={`url(#sparkline-gradient-${color.replace("#", "")})`}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.6, delay: 0.3 }}
      />

      {/* Line */}
      <motion.path
        d={linePath}
        fill="none"
        stroke={color}
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
        initial={{ pathLength: 0, opacity: 0 }}
        animate={{ pathLength: 1, opacity: 1 }}
        transition={{ duration: 0.8, ease: "easeOut" }}
      />

      {/* End dot */}
      <motion.circle
        cx={points[points.length - 1].x}
        cy={points[points.length - 1].y}
        r={3}
        fill={color}
        initial={{ scale: 0, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.3, delay: 0.8 }}
      />
    </svg>
  );
}

function MiniBarChart({
  values,
  color,
  width = 200,
  height = 48,
}: {
  values: number[];
  color: string;
  width?: number;
  height?: number;
}) {
  if (values.length === 0) return null;

  const max = Math.max(...values);
  const barGap = 3;
  const barWidth = (width - barGap * (values.length - 1)) / values.length;

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className="overflow-visible"
    >
      {values.map((val, i) => {
        const barHeight = max > 0 ? (val / max) * (height - 4) : 0;
        const x = i * (barWidth + barGap);
        const y = height - barHeight;
        const isLast = i === values.length - 1;

        return (
          <motion.rect
            key={i}
            x={x}
            y={y}
            width={barWidth}
            height={barHeight}
            rx={2}
            fill={isLast ? color : `${color}40`}
            initial={{ scaleY: 0, originY: "100%" }}
            animate={{ scaleY: 1 }}
            transition={{ duration: 0.4, delay: i * 0.05 }}
          />
        );
      })}
    </svg>
  );
}

export function DataInsightCard({
  title,
  values,
  insight,
  color = "#FF4D00",
}: DataInsightCardProps) {
  const useBars = values.length <= 7;

  return (
    <motion.div
      className={cn(
        "overflow-hidden rounded-xl border border-border bg-surface"
      )}
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.3 }}
    >
      <div className="p-4">
        {/* Header */}
        <div className="mb-3 flex items-center gap-2">
          <div
            className="flex h-6 w-6 items-center justify-center rounded-md"
            style={{ backgroundColor: `${color}15` }}
          >
            <TrendingUp className="h-3.5 w-3.5" style={{ color }} />
          </div>
          <h4 className="text-sm font-semibold text-text-primary">{title}</h4>
        </div>

        {/* Chart */}
        <div className="mb-3 w-full">
          {useBars ? (
            <MiniBarChart values={values} color={color} width={220} height={44} />
          ) : (
            <Sparkline values={values} color={color} width={220} height={44} />
          )}
        </div>

        {/* Insight text */}
        <p className="text-xs leading-relaxed text-text-secondary">{insight}</p>
      </div>
    </motion.div>
  );
}
