"use client";

import { useState } from "react";
import { Heart, MessageCircle, Sparkles, Users } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import { whisperForStep } from "@/lib/aria-onboarding";
import { ARIA_TONE_ORDER, ARIA_TONES } from "@/lib/aria-companion";
import AriaCompanion from "./aria-companion";
import { PremiumPrimaryButton } from "@/components/brand/premium-atmosphere";
import type { CoachingStyle as CoachingStyleType } from "@/types";

interface CoachingStyleProps {
  onComplete: () => void;
}

const TONE_ICONS = {
  balanced: MessageCircle,
  patient: Heart,
  "data-driven": Sparkles,
  "push-hard": Users,
} as const;

export default function CoachingStyleScreen({
  onComplete,
}: CoachingStyleProps) {
  const updateProfile = useAppStore((s) => s.updateProfile);
  const setOnboarded = useAppStore((s) => s.setOnboarded);
  const seedAriaWelcome = useAppStore((s) => s.seedAriaWelcome);
  const userProfile = useAppStore((s) => s.userProfile);
  const [selected, setSelected] = useState<CoachingStyleType | null>(null);

  const handleComplete = () => {
    if (!selected) return;
    updateProfile({ coachingStyle: selected });
    setOnboarded(true);
    seedAriaWelcome();
    onComplete();
  };

  return (
    <div className="flex min-h-[100dvh] flex-col overflow-y-auto px-6 pb-8 pt-16">
      <div className="mb-4">
        <h2 className="mb-2 text-3xl font-semibold tracking-tight text-text-primary">
          How should I show up?
        </h2>
        <p className="text-text-tertiary">
          When the day is messy — a check-in, some space, the patterns, or an
          honest peer. Trainer is a flavor. I&apos;m still me.
        </p>
      </div>

      <div className="mb-5">
        <AriaCompanion
          compact
          whisper={whisperForStep("coaching", {
            name: userProfile.name,
            goals: userProfile.fitnessGoals,
            experience: userProfile.experienceLevel,
            workouts: userProfile.preferredWorkouts,
            coachingStyle: selected,
            devicesConnected: userProfile.connectedDevices.length,
          })}
        />
      </div>

      <div role="radiogroup" aria-label="How ARIA shows up" className="flex flex-col gap-3">
        {ARIA_TONE_ORDER.map((value) => {
          const option = ARIA_TONES[value];
          const Icon = TONE_ICONS[value];
          const isSelected = selected === value;
          return (
            <button
              key={value}
              type="button"
              role="radio"
              aria-checked={isSelected}
              onClick={() => setSelected(value)}
              className={cn(
                "flex items-start gap-4 rounded-xl border p-5 text-left",
                "transition-colors duration-150",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/50",
                isSelected
                  ? "border-white/20 bg-white/[0.06]"
                  : "border-border bg-surface hover:border-border-light"
              )}
            >
              <div
                className={cn(
                  "flex h-12 w-12 shrink-0 items-center justify-center rounded-lg",
                  isSelected
                    ? "bg-white/10 text-[#F7F4F0]"
                    : "bg-surface-elevated text-text-tertiary"
                )}
                aria-hidden
              >
                <Icon size={28} />
              </div>

              <div className="flex flex-col">
                <span className="text-base font-semibold text-text-primary">
                  {option.title}
                </span>
                <span className="mt-1 text-sm leading-relaxed text-text-tertiary">
                  {option.line}
                </span>
              </div>

              <div
                className={cn(
                  "ml-auto mt-1 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2",
                  isSelected ? "border-[#F7F4F0] bg-[#F7F4F0]" : "border-border"
                )}
                aria-hidden
              >
                {isSelected && (
                  <div className="h-2 w-2 rounded-full bg-[#0A0A0A]" />
                )}
              </div>
            </button>
          );
        })}
      </div>

      <PremiumPrimaryButton
        onClick={handleComplete}
        disabled={!selected}
        className="mt-8"
      >
        <span>Start with ARIA</span>
        <span aria-hidden>→</span>
      </PremiumPrimaryButton>
    </div>
  );
}
