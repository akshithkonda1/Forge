"use client";

import { motion } from "framer-motion";
import { Trophy } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.07,
      delayChildren: 0.05,
    },
  },
};

const cardVariants = {
  hidden: { opacity: 0, x: -12 },
  visible: {
    opacity: 1,
    x: 0,
    transition: { duration: 0.35, ease: "easeOut" as const },
  },
};

function formatPRDate(dateStr: string): string {
  const date = new Date(dateStr + "T00:00:00");
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function formatPRValue(value: number, unit: string): string {
  if (unit === "min") {
    const minutes = Math.floor(value);
    const seconds = Math.round((value - minutes) * 100);
    return `${minutes}:${String(seconds).padStart(2, "0")}`;
  }
  return String(value);
}

export function PersonalRecordsBoard() {
  const personalRecords = useAppStore((s) => s.personalRecords);

  return (
    <div>
      {/* Header */}
      <div className="flex items-center gap-2 mb-3">
        <Trophy className="h-5 w-5 text-[#FF4D00]" />
        <h2 className="text-lg font-semibold text-white">Personal Records</h2>
      </div>

      {/* PR cards */}
      <motion.div
        variants={containerVariants}
        initial="hidden"
        animate="visible"
        className="flex flex-col gap-2.5"
      >
        {personalRecords.map((pr) => (
          <motion.div
            key={pr.exercise}
            variants={cardVariants}
            className="flex items-center justify-between rounded-xl border border-[#2A2A2A] bg-[#141414] px-4 py-3.5"
          >
            {/* Left: exercise name & date */}
            <div className="flex flex-col gap-0.5">
              <span className="text-sm font-semibold text-white">
                {pr.exercise}
              </span>
              <span className="text-[11px] text-[#71717A]">
                {formatPRDate(pr.date)}
              </span>
            </div>

            {/* Right: value */}
            <div className="flex items-baseline gap-1">
              <span className="text-xl font-bold text-[#FF4D00]">
                {formatPRValue(pr.value, pr.unit)}
              </span>
              <span className="text-xs font-medium text-[#A1A1AA]">
                {pr.unit}
              </span>
            </div>
          </motion.div>
        ))}
      </motion.div>
    </div>
  );
}
