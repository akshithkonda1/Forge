"use client";

import { cn } from "@/lib/utils";
import type { AriaWhisper } from "@/lib/aria-onboarding";
import { AriaMark } from "@/components/brand/aria-mark";

const moodAccent: Record<AriaWhisper["mood"], string> = {
  energized: "#FF4D00",
  focused: "#4A90D9",
  calm: "#A855F7",
  supportive: "#22C55E",
};

interface AriaCompanionProps {
  whisper: AriaWhisper;
  compact?: boolean;
  className?: string;
}

/** Thin wrapper — every prior AriaOrb call site now shows the living ember. */
export function AriaOrb({
  mood: _mood = "focused",
  size = 48,
  speaking = false,
}: {
  mood?: AriaWhisper["mood"];
  size?: number;
  speaking?: boolean;
}) {
  return <AriaMark size={size} speaking={speaking} />;
}

export default function AriaCompanion({
  whisper,
  compact = false,
  className,
}: AriaCompanionProps) {
  const accent = moodAccent[whisper.mood];

  return (
    <div
      className={cn(
        "relative overflow-hidden rounded-2xl border",
        compact ? "p-3.5" : "p-4",
        className
      )}
      style={{
        borderColor: `${accent}40`,
        background: `linear-gradient(135deg, ${accent}14 0%, rgba(20,20,20,0.95) 45%)`,
      }}
    >
      <div className="flex items-start gap-3">
        <AriaOrb mood={whisper.mood} size={compact ? 40 : 48} />
        <div className="min-w-0 flex-1">
          <div className="mb-1 flex items-start gap-2">
            <span
              className="text-[10px] font-black uppercase tracking-[0.18em]"
              style={{ color: accent }}
            >
              ARIA
            </span>
            <span className="text-text-muted">·</span>
            <span className="truncate text-xs font-bold text-text-primary">
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
