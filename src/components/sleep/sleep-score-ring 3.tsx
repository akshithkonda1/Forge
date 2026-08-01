"use client";

import { motion } from "framer-motion";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";

export function SleepScoreRing() {
  const sleepData = useAppStore((s) => s.sleepData);
  const latest = sleepData[0];
  const score = Math.max(0, Math.min(100, latest.score));

  const size = 160;
  const strokeWidth = 10;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const progress = (score / 100) * circumference;
  const center = size / 2;

  // Format total hours as "Xh Ym"
  const totalHours = latest.totalHours;
  const hours = Math.floor(totalHours);
  const minutes = Math.round((totalHours - hours) * 60);
  const totalFormatted = `${hours}h ${minutes}m total`;

  return (
    <div className="flex flex-col items-center gap-3">
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
          <defs>
            <linearGradient id="sleepRingGradient" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#3B82F6" />
              <stop offset="50%" stopColor="#60A5FA" />
              <stop offset="100%" stopColor="#3B82F6" />
            </linearGradient>
          </defs>

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
            stroke="url(#sleepRingGradient)"
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
              filter: "drop-shadow(0 0 8px rgba(59, 130, 246, 0.4))",
            }}
          />
        </svg>

        {/* Center content */}
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <motion.span
            className="text-4xl font-bold text-white"
            initial={{ opacity: 0, scale: 0.5 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{
              type: "spring",
              stiffness: 100,
              damping: 12,
              delay: 0.2,
            }}
          >
            {score}
          </motion.span>
          <motion.span
            className="mt-0.5 text-xs font-medium text-steel"
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4, duration: 0.3 }}
          >
            Sleep Score
          </motion.span>
        </div>
      </div>

      {/* Summary below ring */}
      <motion.div
        className="flex flex-col items-center gap-0.5"
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5, duration: 0.4 }}
      >
        <span className="text-sm font-semibold text-white">{totalFormatted}</span>
        <span className="text-xs text-text-tertiary">Last night</span>
      </motion.div>
    </div>
  );
}
