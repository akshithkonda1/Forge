"use client";

import { useState, type ComponentType, type ReactNode } from "react";
import { Heart, MessageCircle, Sparkles, Users } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import { useToast } from "@/stores/useToast";
import { Sheet } from "@/components/ui/sheet";
import { ARIA_TONE_ORDER, ARIA_TONES } from "@/lib/aria-companion";
import type { CoachingStyle } from "@/types";

const TONE_ICONS: Record<CoachingStyle, typeof MessageCircle> = {
  balanced: MessageCircle,
  patient: Heart,
  "data-driven": Sparkles,
  "push-hard": Users,
};

export function AriaCompanionControls({
  SettingsRow,
}: {
  SettingsRow: ComponentType<{
    icon?: ReactNode;
    iconColor?: string;
    label: string;
    value?: ReactNode;
    showChevron?: boolean;
    rightElement?: ReactNode;
    onClick?: () => void;
  }>;
}) {
  const userProfile = useAppStore((s) => s.userProfile);
  const updateProfile = useAppStore((s) => s.updateProfile);
  const showToast = useToast((s) => s.show);
  const [open, setOpen] = useState(false);
  const tone = ARIA_TONES[userProfile.coachingStyle];

  return (
    <>
      <SettingsRow
        icon={<Users size={18} />}
        iconColor="text-ember"
        label="How ARIA shows up"
        value={
          <span className="max-w-[160px] truncate text-right text-xs text-text-secondary">
            {tone.title}
          </span>
        }
        showChevron
        onClick={() => setOpen(true)}
      />
      <div className="px-4 py-2.5">
        <p className="text-xs leading-relaxed text-text-tertiary">{tone.line}</p>
      </div>

      <Sheet open={open} onClose={() => setOpen(false)} title="How ARIA shows up">
        <p className="mb-4 text-sm leading-relaxed text-text-secondary">
          When the day is messy — a check-in, some space, the patterns, or an
          honest peer. Trainer is a flavor. She&apos;s still ARIA.
        </p>
        <div
          role="radiogroup"
          aria-label="How ARIA shows up"
          className="flex flex-col gap-2"
        >
          {ARIA_TONE_ORDER.map((style) => {
            const option = ARIA_TONES[style];
            const selected = userProfile.coachingStyle === style;
            const Icon = TONE_ICONS[style];
            return (
              <button
                key={style}
                type="button"
                role="radio"
                aria-checked={selected}
                onClick={() => {
                  updateProfile({ coachingStyle: style });
                  setOpen(false);
                  showToast(`${option.title} — that's how she'll show up.`);
                }}
                className={cn(
                  "flex items-start gap-3 rounded-xl border p-3 text-left transition-colors",
                  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/50",
                  selected
                    ? "border-white/20 bg-white/[0.06]"
                    : "border-border bg-surface-elevated"
                )}
              >
                <Icon
                  size={18}
                  className={
                    selected ? "mt-0.5 text-[#F7F4F0]" : "mt-0.5 text-text-tertiary"
                  }
                />
                <span>
                  <span className="block text-sm font-semibold text-text-primary">
                    {option.title}
                  </span>
                  <span className="mt-1 block text-xs text-text-tertiary">
                    {option.line}
                  </span>
                </span>
              </button>
            );
          })}
        </div>
      </Sheet>
    </>
  );
}
