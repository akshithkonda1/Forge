"use client";

import { motion, useReducedMotion } from "framer-motion";
import { getReadinessColor, getReadinessLabel } from "@/lib/utils";
import { isAlmostThere, PLATE_HEX } from "@/lib/readiness-tokens";

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
  const reduceMotion = useReducedMotion();
  const closing = isAlmostThere(clampedScore, clampedScore >= 100 ? 0 : 99);
  const still = {
    type: "tween" as const,
    duration: 0,
  };

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
        <circle
          cx={center}
          cy={center}
          r={radius}
          fill="none"
          stroke="#2A2A2A"
          strokeWidth={strokeWidth}
          strokeLinecap="round"
        />
        {closing ? (
          <circle
            cx={center}
            cy={center}
            r={radius}
            fill="none"
            stroke={PLATE_HEX}
            strokeWidth={strokeWidth * 0.45}
            strokeLinecap="round"
            strokeDasharray={circumference}
            strokeDashoffset={0}
            opacity={0.28}
          />
        ) : null}
        <motion.circle
          cx={center}
          cy={center}
          r={radius}
          fill="none"
          stroke={color}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          initial={reduceMotion ? false : { strokeDashoffset: circumference }}
          animate={{ strokeDashoffset: circumference - progress }}
          transition={
            reduceMotion
              ? still
              : {
                  type: "spring",
                  stiffness: 60,
                  damping: 15,
                  mass: 1,
                }
          }
          style={{
            filter: `drop-shadow(0 0 5px ${color}33)`,
          }}
        />
      </svg>

      {showLabel && (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <motion.span
            className="text-5xl font-bold text-text-primary"
            initial={reduceMotion ? false : { opacity: 0, scale: 0.5 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={
              reduceMotion
                ? still
                : {
                    type: "spring",
                    stiffness: 100,
                    damping: 12,
                    delay: 0.2,
                  }
            }
          >
            {clampedScore}
          </motion.span>
          <motion.span
            className="mt-1 text-sm font-medium"
            style={{ color }}
            initial={reduceMotion ? false : { opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            transition={reduceMotion ? still : { delay: 0.4, duration: 0.3 }}
          >
            {label}
          </motion.span>
        </div>
      )}
    </div>
  );
}
