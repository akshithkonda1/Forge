"use client";

import { motion } from "framer-motion";
import { MessageCircle } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";

export function AiSleepInsight() {
  const setActiveTab = useAppStore((s) => s.setActiveTab);

  return (
    <motion.div
      className={cn(
        "rounded-xl border border-border bg-surface",
        "border-l-2 border-l-ember",
        "p-4"
      )}
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: 0.2 }}
    >
      {/* Forge AI label */}
      <div className="mb-2 flex items-center gap-2">
        <div className="h-1.5 w-1.5 rounded-full bg-ember" />
        <span className="text-xs font-medium text-ember">ARIA</span>
      </div>

      {/* Insight text */}
      <p className="text-sm leading-relaxed text-text-secondary">
        Your deep sleep has dropped 18% this week. This correlates with your increased
        evening screen time. Try the wind-down routine I suggested.
      </p>

      {/* Chat link */}
      <button
        onClick={() => setActiveTab("chat")}
        className={cn(
          "mt-3 inline-flex items-center gap-1.5",
          "text-xs font-medium text-text-secondary",
          "hover:text-text-primary transition-colors"
        )}
      >
        <MessageCircle size={13} />
        Ask ARIA about this
      </button>
    </motion.div>
  );
}
