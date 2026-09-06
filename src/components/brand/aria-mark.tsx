"use client";

import { cn } from "@/lib/utils";
import { ARIA_MARK } from "@/lib/aria-mark";

/**
 * Adaptive Recovery Interactive Assistant — living 4-lobe ember.
 * PNG is aspect-fit only. Motion is uniform scale + hue + a core pulse.
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
  const duration = speaking ? `${ARIA_MARK.speakBreathSeconds}s` : `${ARIA_MARK.idleBreathSeconds}s`;
  return (
    <div
      className={cn("relative shrink-0", className)}
      style={{ width: size, height: size }}
      aria-hidden={hero ? undefined : true}
      aria-label={hero ? label ?? "ARIA" : undefined}
      role={hero ? "img" : undefined}
    >
      <div className="aria-mark-glow pointer-events-none absolute inset-[-12%]" style={{ animationDuration: duration }} />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={ARIA_MARK.webPath}
        alt=""
        draggable={false}
        className={cn("aria-mark relative block h-full w-full", speaking && "aria-mark-speak")}
        style={{ animationDuration: duration }}
      />
      <div className="aria-mark-core pointer-events-none" style={{ animationDuration: duration }} />
    </div>
  );
}
