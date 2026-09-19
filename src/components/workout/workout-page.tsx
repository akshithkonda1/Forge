"use client";

import { Play, Calendar } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { ActiveWorkoutView } from "./active-workout-view";
import {
  PremiumAtmosphere,
  PremiumEntrance,
  PremiumPrimaryButton,
} from "@/components/brand/premium-atmosphere";

export function WorkoutPage() {
  const { todayWorkout, activeWorkout, startWorkout, setActiveTab } = useAppStore();

  if (activeWorkout.isActive) {
    return (
      <div className="h-full">
        <ActiveWorkoutView />
      </div>
    );
  }

  return (
    <div className="relative flex min-h-full flex-col items-center bg-background px-6 py-10">
      <PremiumAtmosphere accent="#FF6B2B" secondary="#A9D8FF" intensity={0.45} />
      <div className="relative z-10 flex w-full max-w-sm flex-col">
        {todayWorkout ? (
          <>
            <PremiumEntrance index={0}>
              <p className="mb-2 text-[11px] font-medium uppercase tracking-[0.2em] text-text-tertiary">
                Today
              </p>
              <h2 className="mb-2 text-2xl font-semibold tracking-tight text-text-primary">
                {todayWorkout.name}
              </h2>
              <p className="mb-5 text-sm text-text-secondary">
                {todayWorkout.exercises.length} moves · {todayWorkout.duration} min ·{" "}
                {todayWorkout.intensity}
              </p>
            </PremiumEntrance>

            <PremiumEntrance index={1} className="mb-5">
              <PremiumPrimaryButton onClick={startWorkout}>
                <span className="inline-flex items-center gap-2">
                  <Play className="h-4 w-4 fill-current" />
                  Start session
                </span>
                <span aria-hidden>→</span>
              </PremiumPrimaryButton>
            </PremiumEntrance>

            <PremiumEntrance index={2}>
              <div className="w-full rounded-2xl border border-white/[0.08] bg-white/[0.035] p-4">
                {todayWorkout.exercises.map((exercise, index) => (
                  <div
                    key={exercise.id}
                    className="flex items-center justify-between border-b border-white/[0.06] py-2.5 last:border-b-0"
                  >
                    <div className="flex items-center gap-3">
                      <span className="w-5 text-right text-xs font-medium text-text-tertiary">
                        {index + 1}
                      </span>
                      <span className="text-sm text-text-primary">{exercise.name}</span>
                    </div>
                    <span className="text-xs text-text-tertiary">
                      {exercise.sets} × {exercise.reps}
                    </span>
                  </div>
                ))}
              </div>
            </PremiumEntrance>
          </>
        ) : (
          <div className="flex w-full max-w-sm flex-col items-center">
            <PremiumEntrance index={0}>
              <div className="mb-6 flex h-20 w-20 items-center justify-center rounded-2xl border border-white/10 bg-white/[0.04]">
                <Calendar className="h-10 w-10 text-text-tertiary" />
              </div>
              <h2 className="mb-2 text-center text-xl font-semibold text-text-primary">
                No workout planned
              </h2>
              <p className="mb-8 text-center text-sm leading-relaxed text-text-secondary">
                You don&apos;t have a session scheduled for today.
                <br />
                Talk with ARIA to plan one.
              </p>
            </PremiumEntrance>
            <PremiumEntrance index={1}>
              <PremiumPrimaryButton onClick={() => setActiveTab("chat")}>
                <span>Talk with ARIA</span>
                <span aria-hidden>→</span>
              </PremiumPrimaryButton>
            </PremiumEntrance>
          </div>
        )}
      </div>
    </div>
  );
}
