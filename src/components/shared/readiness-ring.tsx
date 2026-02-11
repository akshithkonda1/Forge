"use client";

import { motion } from "framer-motion";
import { getReadinessColor, getReadinessLabel } from "@/lib/utils";

interface ReadinessRingProps {
  score: number;
  size?: number;
  strokeWidth?: number;
  showLabel?: boolean;
}

export function ReadinessRing({
  score,
  size = 200,
  strokeWidth = 12,
  showLabel = true,
}: ReadinessRingProps) {
  const clampedScore = Math.max(0, Math.min(100, score));
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const progress = (clampedScore / 100) * circumference;
  const center = size / 2;

  const color = getReadinessColor(clampedScore);
  const label = getReadinessLabel(clampedScore);

  return (
    <div
      className="relative inline-flex items-center justify-center"
      style={{ width: size, height: size }}
    >
      <svg
        width={size}
        height={size}
        viewBox={`0 0 ${size} ${size}`}
        className="-rotate-90"
      >
        {/* Background track */}
        <circle
          cx={center}
          cy={center}
          r={radius}
          fill="none"
          stroke="#2A2A2A"
          strokeWidth={strokeWidth}
          strokeLinecap="round"
        />

        {/* Progress arc */}
        <motion.circle
          cx={center}
          cy={center}
          r={radius}
          fill="none"
          stroke={color}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          initial={{ strokeDashoffset: circumference }}
          animate={{ strokeDashoffset: circumference - progress }}
          transition={{
            type: "spring",
            stiffness: 60,
            damping: 15,
            mass: 1,
          }}
          style={{
            filter: `drop-shadow(0 0 8px ${color}40)`,
          }}
        />
      </svg>

      {/* Center content */}
      {showLabel && (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <motion.span
            className="text-5xl font-bold text-white"
            initial={{ opacity: 0, scale: 0.5 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{
              type: "spring",
              stiffness: 100,
              damping: 12,
              delay: 0.2,
            }}
          >
            {clampedScore}
          </motion.span>
          <motion.span
            className="mt-1 text-sm font-medium"
            style={{ color }}
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4, duration: 0.3 }}
          >
            {label}
          </motion.span>
        </div>
      )}
    </div>
  );
}
