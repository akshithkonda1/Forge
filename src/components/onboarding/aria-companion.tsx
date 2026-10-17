"use client";

import { cn } from "@/lib/utils";
import type { AriaWhisper } from "@/lib/aria-onboarding";
import { AriaMark } from "@/components/brand/aria-mark";

interface AriaCompanionProps {
  whisper: AriaWhisper;
  compact?: boolean;
  className?: string;
}

export default function AriaCompanion({
  whisper,
  compact = false,
  className,
}: AriaCompanionProps) {
  return (
    <div
      className={cn(
        "relative overflow-hidden rounded-2xl border border-white/10 bg-white/[0.04]",
        compact ? "p-3.5" : "p-4",
        className
      )}
    >
      <div className="flex items-start gap-3">
        <AriaMark size={compact ? 44 : 52} speaking />
        <div className="min-w-0 flex-1">
          <div className="mb-1 flex items-start gap-2">
            <span className="type-micro font-medium uppercase tracking-[0.18em] text-text-tertiary">
              ARIA
            </span>
            <span className="text-text-muted">·</span>
            <span className="truncate text-xs font-semibold text-text-primary">
              {whisper.title}
            </span>
          </div>
          <p
            className={cn(
              "leading-relaxed text-text-secondary",
              compact ? "text-xs" : "text-sm"
            )}
          >
            {whisper.message}
          </p>
        </div>
      </div>
    </div>
  );
}
