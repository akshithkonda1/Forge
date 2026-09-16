"use client";

import { AriaMark } from "@/components/brand/aria-mark";
import { ARIA_MARK, ARIA_MARK_COMPACT_MAX, FORGE_WORDMARK } from "@/lib/aria-mark";
import { cn } from "@/lib/utils";

/**
 * FORGE wordmark-primary. Caps at 32pt. Tiny still nest only when the slot
 * is compact and large enough to stay readable — never a second live nest.
 */
export function ForgeWordmark({
  size = ARIA_MARK.wordmarkPrimaryMax,
  withNest = false,
  nestSize = 18,
  className,
}: {
  size?: number;
  withNest?: boolean;
  nestSize?: number;
  className?: string;
}) {
  const px = Math.min(ARIA_MARK.wordmarkPrimaryMax, Math.max(11, size));
  const nestClear =
    withNest && nestSize >= 16 && nestSize <= ARIA_MARK_COMPACT_MAX;

  return (
    <div className={cn("flex items-center justify-center gap-2", className)}>
      {nestClear ? <AriaMark size={nestSize} /> : null}
      <p
        className="font-black uppercase tracking-[0.28em] text-white"
        style={{
          fontFamily: "var(--font-display)",
          fontSize: px,
          lineHeight: 1,
        }}
      >
        {FORGE_WORDMARK}
      </p>
    </div>
  );
}
