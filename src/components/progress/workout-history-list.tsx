"use client";

import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";

function formatWorkoutDate(dateStr: string): string {
  const date = new Date(dateStr + "T00:00:00");
  return date.toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
  });
}

function intensityDotColor(intensity: string): string {
  switch (intensity) {
    case "max":
      return "#EF4444";
    case "high":
      return "#FF4D00";
    case "moderate":
      return "#EAB308";
    case "low":
      return "#22C55E";
    default:
      return "#A1A1AA";
  }
}

function typePillColor(type: string): { bg: string; text: string } {
  switch (type) {
    case "strength":
      return { bg: "bg-ember/10", text: "text-ember" };
    case "hiit":
      return { bg: "bg-alert/10", text: "text-alert" };
    case "cardio":
      return { bg: "bg-steel/10", text: "text-steel" };
    case "yoga":
      return { bg: "bg-vitality/10", text: "text-vitality" };
    case "mobility":
      return { bg: "bg-aurora/10", text: "text-aurora" };
    default:
      return { bg: "bg-text-secondary/10", text: "text-text-secondary" };
  }
}

export function WorkoutHistoryList() {
  const workoutHistory = useAppStore((s) => s.workoutHistory);

  return (
    <div>
      {/* Header */}
      <h2 className="type-headline text-text-primary mb-3">
        Recent Workouts
      </h2>

      {/* Workout entries */}
      <div className="flex flex-col gap-2.5">
        {workoutHistory.map((workout) => {
          const pillStyle = typePillColor(workout.type);

          return (
            <div
              key={workout.id}
              className="flex items-center gap-3 rounded-xl bg-surface px-4 py-3.5"
            >
              {/* Intensity dot */}
              <div className="flex-shrink-0">
                <div
                  className="h-2.5 w-2.5 rounded-full"
                  style={{ backgroundColor: intensityDotColor(workout.intensity) }}
                />
              </div>

              {/* Main info */}
              <div className="flex flex-1 flex-col gap-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-semibold text-text-primary truncate">
                    {workout.name}
                  </span>
                  <span
                    className={cn(
                      "inline-flex items-center rounded-full px-2 py-0.5 type-micro font-medium capitalize",
                      pillStyle.bg,
                      pillStyle.text
                    )}
                  >
                    {workout.type}
                  </span>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-xs text-text-tertiary">
                    {formatWorkoutDate(workout.date)}
                  </span>
                  <span className="text-xs text-text-secondary">
                    {workout.duration} min
                  </span>
                  {workout.volume > 0 && (
                    <span className="text-xs text-text-secondary">
                      {(workout.volume / 1000).toFixed(1)}k lbs
                    </span>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
