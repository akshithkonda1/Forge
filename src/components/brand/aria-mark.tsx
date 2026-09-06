"use client";

import { cn } from "@/lib/utils";
import { ARIA_MARK } from "@/lib/aria-mark";

/**
 * Adaptive Recovery Interactive Assistant — living fluid ember.
 * Photo + CSS breath. Reduce Motion falls back to the still frame.
 */
export function AriaMark({
  size = 48,
  speaking = false,
  className,
  label,
}: {
  size?: number;
  speaking?: boolean;
  className?: string;
  label?: string;
}) {
  const hero = size >= ARIA_MARK.heroMinimumSize;
  return (
    <div
      className={cn("relative shrink-0", className)}
      style={{ width: size, height: size }}
      aria-hidden={hero ? undefined : true}
      aria-label={hero ? label ?? "ARIA" : undefined}
      role={hero ? "img" : undefined}
    >
      <div
        className="aria-mark-glow pointer-events-none absolute inset-[-18%] rounded-full"
        style={{ animationDuration: speaking ? `${ARIA_MARK.speakBreathSeconds}s` : `${ARIA_MARK.idleBreathSeconds}s` }}
      />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={ARIA_MARK.webPath}
        alt=""
        draggable={false}
        className={cn("aria-mark relative block h-full w-full object-contain", speaking && "aria-mark-speak")}
        style={{
          animationDuration: speaking ? `${ARIA_MARK.speakBreathSeconds}s` : `${ARIA_MARK.idleBreathSeconds}s`,
        }}
      />
    </div>
  );
}
