"use client";

import { useState } from "react";
import { Heart, MessageCircle, Sparkles, Users } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import { whisperForStep } from "@/lib/aria-onboarding";
import { ARIA_TONE_ORDER, ARIA_TONES } from "@/lib/aria-companion";
import AriaCompanion from "./aria-companion";
import {
  PremiumAtmosphere,
  PremiumEntrance,
  PremiumPrimaryButton,
} from "@/components/brand/premium-atmosphere";
import type { CoachingStyle as CoachingStyleType } from "@/types";

interface CoachingStyleProps {
  onComplete: () => void;
}

interface StyleOption {
  value: CoachingStyleType;
  label: string;
  icon: React.ReactNode;
  description: string;
}

const styles: StyleOption[] = [
  {
    value: "push-hard",
    label: "Challenge me",
    icon: <Zap size={28} />,
    description: "High intensity when you’re ready. Clear standards every session.",
  },
  {
    value: "balanced",
    label: "Keep it balanced",
    icon: <Scale size={28} />,
    description: "Push when you can, back off when you need to. Smart training.",
  },
  {
    value: "patient",
    label: "Be patient with me",
    icon: <Heart size={28} />,
    description: "I’m building habits. Encouraging and supportive.",
  },
  {
    value: "data-driven",
    label: "Data-driven & precise",
    icon: <BarChart3 size={28} />,
    description: "Numbers guide the plan. Optimize from your metrics.",
  },
];

export default function CoachingStyleScreen({ onComplete }: CoachingStyleProps) {
  const updateProfile = useAppStore((s) => s.updateProfile);
  const setOnboarded = useAppStore((s) => s.setOnboarded);
  const seedAriaWelcome = useAppStore((s) => s.seedAriaWelcome);
  const meetAria = useAppStore((s) => s.meetAria);
  const userProfile = useAppStore((s) => s.userProfile);
  const [selected, setSelected] = useState<CoachingStyleType | null>(null);

  const handleComplete = () => {
    if (!selected) return;
    updateProfile({ coachingStyle: selected });
    setOnboarded(true);
    meetAria();
    seedAriaWelcome();
    onComplete();
  };

  return (
    <div className="relative flex min-h-[100dvh] flex-col overflow-y-auto px-6 pb-8 pt-16">
      <PremiumAtmosphere accent="#FF6B2B" secondary="#A9D8FF" intensity={0.5} />
      <div className="relative z-10 flex flex-1 flex-col">
        <PremiumEntrance index={0} className="mb-4">
          <h2 className="mb-2 text-3xl font-semibold tracking-tight text-text-primary">
            How do you like to be coached?
          </h2>
          <p className="text-text-tertiary">
            This shapes ARIA&apos;s voice — every check-in, plan, and recovery nudge.
          </p>
        </PremiumEntrance>

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

        <div className="flex flex-col gap-3">
          {styles.map((style) => {
            const isSelected = selected === style.value;
            return (
              <button
                key={style.value}
                type="button"
                onClick={() => setSelected(style.value)}
                className={cn(
                  "flex items-start gap-4 rounded-xl border p-5 text-left",
                  "transition-colors duration-150",
                  isSelected
                    ? "border-white/20 bg-white/[0.06]"
                    : "border-border bg-surface hover:border-border-light"
                )}
                aria-hidden
              >
                <div
                  className={cn(
                    "flex h-12 w-12 shrink-0 items-center justify-center rounded-lg transition-all duration-200",
                    isSelected
                      ? "bg-white/10 text-[#F7F4F0]"
                      : "bg-surface-elevated text-text-tertiary"
                  )}
                >
                  {style.icon}
                </div>
                <div className="flex flex-col">
                  <span className="text-base font-semibold text-text-primary">{style.label}</span>
                  <span className="mt-1 text-sm leading-relaxed text-text-tertiary">
                    {style.description}
                  </span>
                </div>
                <div
                  className={cn(
                    "ml-auto mt-1 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 transition-all duration-200",
                    isSelected ? "border-[#F7F4F0] bg-[#F7F4F0]" : "border-border"
                  )}
                >
                  {isSelected && <div className="h-2 w-2 rounded-full bg-[#0A0A0A]" />}
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
    </div>
  );
}
