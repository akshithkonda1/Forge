"use client";

import { motion } from "framer-motion";

export function BehavioralInsight() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: 0.3, ease: "easeOut" }}
      className="relative overflow-hidden rounded-2xl border border-[#2A2A2A] bg-[#141414]"
    >
      {/* Steel blue left border accent */}
      <div className="absolute inset-y-0 left-0 w-[3px] bg-[#3B82F6]" />

      <div className="p-5 pl-6">
        {/* Label */}
        <div className="flex items-center gap-2 mb-3">
          <span className="inline-block h-2 w-2 rounded-full bg-[#3B82F6]" />
          <span className="text-xs font-semibold uppercase tracking-wider text-[#3B82F6]">
            ARIA
          </span>
        </div>

        {/* Insight text */}
        <p className="text-sm leading-relaxed text-[#A1A1AA]">
          You train most consistently on Mon/Wed/Fri mornings. When you skip,
          it&apos;s usually Fridays after high-stress weeks. Consider scheduling a
          lighter Friday session as a fallback.
        </p>
      </div>
    </motion.div>
  );
}
