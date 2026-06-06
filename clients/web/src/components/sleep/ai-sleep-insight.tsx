"use client";

import { motion } from "framer-motion";
import { MessageCircle } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";

export function AiSleepInsight() {
  const setActiveTab = useAppStore((s) => s.setActiveTab);
  const sleepInsightText = useAppStore((s) => s.sleepInsightText);
  const text = sleepInsightText();

  return (
    <motion.div
      className={cn(
        "rounded-xl border border-border bg-surface",
        "border-l-2 border-l-ember",
        "p-4",
      )}
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, delay: 0.2 }}
    >
      <div className="mb-2 flex items-center gap-2">
        <div className="h-1.5 w-1.5 rounded-full bg-ember" />
        <span className="text-xs font-medium text-ember">Forge AI</span>
      </div>

      <p className="text-sm leading-relaxed text-text-secondary">{text}</p>

      <button
        type="button"
        onClick={() => setActiveTab("chat")}
        className={cn(
          "mt-3 inline-flex items-center gap-1.5",
          "text-xs font-medium text-text-secondary",
          "transition-colors hover:text-text-primary",
        )}
      >
        <MessageCircle size={13} />
        Chat about this
      </button>
    </motion.div>
  );
}