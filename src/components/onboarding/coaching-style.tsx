"use client";

import { useState } from "react";
import { Flame, Scale, Heart, BarChart3 } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import { whisperForStep } from "@/lib/aria-onboarding";
import AriaCompanion from "./aria-companion";
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
    label: "Push Me Hard",
    icon: <Flame size={28} />,
    description:
      "No excuses. Maximum intensity. I want to be challenged every session.",
  },
  {
    value: "balanced",
    label: "Keep It Balanced",
    icon: <Scale size={28} />,
    description:
      "Push when I can, back off when I need to. Smart training.",
  },
  {
    value: "patient",
    label: "Be Patient With Me",
    icon: <Heart size={28} />,
    description:
      "I'm building habits. Encouraging and supportive.",
  },
  {
    value: "data-driven",
    label: "Data-Driven & Precise",
    icon: <BarChart3 size={28} />,
    description:
      "Numbers don't lie. Optimize everything based on my metrics.",
  },
];

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
      {/* Header */}
      <div className="mb-4">
        <h2 className="mb-2 text-3xl font-bold text-text-primary">
          How do you like to be coached?
        </h2>
        <p className="text-text-tertiary">
          This shapes ARIA&apos;s voice — every check-in, plan, and recovery nudge.
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

      {/* Style cards */}
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
                  ? "border-ember bg-ember/10"
                  : "border-border bg-surface hover:border-border-light"
              )}
            >
              {/* Icon */}
              <div
                className={cn(
                  "flex h-12 w-12 shrink-0 items-center justify-center rounded-lg transition-all duration-200",
                  isSelected
                    ? "bg-ember/20 text-ember"
                    : "bg-surface-elevated text-text-tertiary"
                )}
              >
                {style.icon}
              </div>

              {/* Text */}
              <div className="flex flex-col">
                <span
                  className={cn(
                    "text-base font-semibold transition-colors duration-200",
                    isSelected ? "text-ember" : "text-text-primary"
                  )}
                >
                  {style.label}
                </span>
                <span className="mt-1 text-sm leading-relaxed text-text-tertiary">
                  {style.description}
                </span>
              </div>

              {/* Selection indicator */}
              <div
                className={cn(
                  "ml-auto mt-1 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 transition-all duration-200",
                  isSelected ? "border-ember bg-ember" : "border-border"
                )}
              >
                {isSelected && (
                  <div className="h-2 w-2 rounded-full bg-white" />
                )}
              </div>
            </button>
          );
        })}
      </div>

      <button
        type="button"
        onClick={handleComplete}
        disabled={!selected}
        className={cn(
          "mt-8 w-full rounded-xl px-8 py-4 text-lg font-semibold text-white",
          "focus:outline-none focus-visible:ring-2 focus-visible:ring-ember focus-visible:ring-offset-2 focus-visible:ring-offset-background",
          "disabled:cursor-not-allowed disabled:opacity-40"
        )}
        style={{
          background: selected
            ? "linear-gradient(135deg, #FF4D00, #FF6B2B)"
            : "#2A2A2A",
        }}
      >
        Start with ARIA
      </button>
    </div>
  );
}
