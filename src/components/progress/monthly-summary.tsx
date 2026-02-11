"use client";

import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.08,
      delayChildren: 0.1,
    },
  },
};

const itemVariants = {
  hidden: { opacity: 0, y: 12 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.4, ease: "easeOut" as const },
  },
};

interface StatPillProps {
  value: string;
  label: string;
  className?: string;
}

function StatPill({ value, label, className }: StatPillProps) {
  return (
    <motion.div
      variants={itemVariants}
      className={cn(
        "flex flex-col items-center gap-1 rounded-xl bg-[#1A1A1A] px-4 py-3 flex-1",
        className
      )}
    >
      <span className="text-xl font-bold text-white">{value}</span>
      <span className="text-[11px] text-[#A1A1AA] whitespace-nowrap">{label}</span>
    </motion.div>
  );
}

export function MonthlySummary() {
  return (
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      className="relative overflow-hidden rounded-2xl border border-[#2A2A2A] bg-[#141414]"
    >
      {/* Gradient top border accent */}
      <div className="absolute inset-x-0 top-0 h-[2px] bg-gradient-to-r from-[#FF4D00] via-[#FF6B2C] to-[#FF4D00]" />

      <div className="p-5">
        {/* Label */}
        <motion.p
          variants={itemVariants}
          className="text-xs font-medium uppercase tracking-wider text-[#71717A] mb-4"
        >
          This Month
        </motion.p>

        {/* Stats row */}
        <div className="flex gap-2.5 mb-4">
          <StatPill value="18" label="Workouts" />
          <StatPill value="3" label="New PRs" />
          <StatPill value="+22%" label="Recovery" />
        </div>

        {/* AI summary */}
        <motion.p
          variants={itemVariants}
          className="text-sm leading-relaxed text-[#A1A1AA]"
        >
          Strong month. You&apos;ve been consistent with your Mon/Wed/Fri schedule
          and hit 3 new personal records. Recovery consistency improved 22%
          &mdash; your sleep habits are paying off.
        </motion.p>
      </div>
    </motion.div>
  );
}
