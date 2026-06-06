"use client";

import { motion } from "framer-motion";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

interface ForgeEmptyStateProps {
  icon: LucideIcon;
  title: string;
  description: string;
  actionLabel?: string;
  onAction?: () => void;
  className?: string;
}

export function ForgeEmptyState({
  icon: Icon,
  title,
  description,
  actionLabel,
  onAction,
  className,
}: ForgeEmptyStateProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className={cn(
        "flex flex-col items-center rounded-2xl border border-dashed border-border bg-surface px-6 py-10 text-center",
        className,
      )}
    >
      <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-ember/10">
        <Icon size={22} className="text-ember" />
      </div>
      <p className="text-sm font-semibold text-text-primary">{title}</p>
      <p className="mt-1.5 max-w-[260px] text-xs leading-relaxed text-text-secondary">
        {description}
      </p>
      {actionLabel && onAction && (
        <button
          type="button"
          onClick={onAction}
          className="mt-5 rounded-xl bg-ember px-5 py-2.5 text-xs font-semibold text-white transition-opacity hover:opacity-90"
        >
          {actionLabel}
        </button>
      )}
    </motion.div>
  );
}