"use client";

import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import type { AriaWhisper } from "@/lib/aria-onboarding";

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

export function AriaOrb({
  mood = "focused",
  size = 48,
  speaking = false,
}: {
  mood?: AriaWhisper["mood"];
  size?: number;
  speaking?: boolean;
}) {
  const accent = moodAccent[mood];
  return (
    <div
      className="relative shrink-0"
      style={{ width: size, height: size }}
      aria-hidden
    >
      <motion.div
        className="absolute inset-[-30%] rounded-full blur-xl"
        style={{ background: accent }}
        animate={{ opacity: speaking ? [0.25, 0.45, 0.25] : [0.12, 0.22, 0.12] }}
        transition={{ duration: 2.4, repeat: Infinity, ease: "easeInOut" }}
      />
      <motion.div
        className="absolute inset-0 rounded-full"
        style={{
          background: `radial-gradient(circle at 35% 30%, #1a1a1a 0%, ${accent}55 55%, #0A0A0A 100%)`,
          boxShadow: `0 0 24px ${accent}44`,
        }}
        animate={speaking ? { scale: [1, 1.06, 1] } : { scale: [1, 1.02, 1] }}
        transition={{ duration: speaking ? 1.2 : 3, repeat: Infinity, ease: "easeInOut" }}
      />
      <motion.div
        className="absolute inset-[-8%] rounded-full border"
        style={{ borderColor: `${accent}66` }}
        animate={{ opacity: [0.35, 0.8, 0.35], scale: [1, 1.08, 1] }}
        transition={{ duration: 2.8, repeat: Infinity, ease: "easeInOut" }}
      />
      <div
        className="absolute left-1/2 top-1/2 h-[18%] w-[18%] -translate-x-1/2 -translate-y-1/2 rounded-full bg-white/40 blur-[1px]"
      />
    </div>
  );
}

export default function AriaCompanion({
  whisper,
  compact = false,
  className,
}: AriaCompanionProps) {
  const accent = moodAccent[whisper.mood];

  return (
    <motion.div
      key={whisper.title + whisper.message}
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, ease: [0.25, 0.46, 0.45, 0.94] }}
      className={cn(
        "relative overflow-hidden rounded-2xl border",
        compact ? "p-3.5" : "p-4",
        className
      )}
      style={{
        borderColor: `${accent}40`,
        background: `linear-gradient(135deg, ${accent}14 0%, rgba(20,20,20,0.95) 45%)`,
        boxShadow: `0 8px 32px ${accent}12`,
      }}
    >
      <div className="flex items-start gap-3">
        <AriaOrb mood={whisper.mood} size={compact ? 40 : 48} speaking />
        <div className="min-w-0 flex-1">
          <div className="mb-1 flex items-center gap-2">
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
    </motion.div>
  );
}
