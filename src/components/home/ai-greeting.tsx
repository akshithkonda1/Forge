"use client";

import { useMemo } from "react";
import { MessageCircle } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";
import { getReadinessLabel } from "@/lib/utils";
import { AriaOrb } from "@/components/onboarding/aria-companion";

function buildGreeting(
  name: string,
  readiness: { overall: number; sleepQuality: number },
  workoutName: string | undefined,
  dataDriven: boolean,
  hrv: number
): string {
  const hour = new Date().getHours();
  const timeGreeting = hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening";
  const who = name.trim().split(/\s+/)[0] || "there";
  const readinessLabel = getReadinessLabel(readiness.overall).toLowerCase();

  const night =
    readiness.sleepQuality >= 80
      ? "Last night actually rebuilt you."
      : readiness.sleepQuality >= 60
        ? "Last night was decent — we'll keep the load honest."
        : "Last night was thinner than I'd like. We'll protect you today.";

  const session = workoutName
    ? readiness.overall >= 80
      ? `You're ${readinessLabel}. Ready to hit ${workoutName}?`
      : readiness.overall >= 60
        ? `You're ${readinessLabel}. ${workoutName} still fits if we stay honest.`
        : `Recovery is the work. Keep ${workoutName} light, or swap for mobility.`
    : "Today's a good day to rest and recover.";

  const extra = dataDriven ? ` HRV ${hrv}ms.` : "";
  return `${timeGreeting} ${who}. ${night} ${session}${extra}`;
}

export function AiGreeting() {
  const { userProfile, readiness, dailyMetrics, todayWorkout, setActiveTab } =
    useAppStore();

  const greeting = useMemo(
    () =>
      buildGreeting(
        userProfile.name,
        readiness,
        todayWorkout?.name,
        userProfile.coachingStyle === "data-driven",
        dailyMetrics.hrv
      ),
    [userProfile.name, userProfile.coachingStyle, readiness, todayWorkout?.name, dailyMetrics.hrv]
  );

  return (
    <div className={cn("rounded-2xl bg-surface border-l-2 border-l-ember", "p-4")}>
      <div className="flex items-start gap-3">
        <div className="flex-shrink-0">
          <AriaOrb mood="focused" size={36} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-xs font-medium text-ember mb-1.5">ARIA</p>
          <p className="text-sm leading-relaxed text-text-primary">{greeting}</p>
          <button
            onClick={() => setActiveTab("chat")}
            className={cn(
              "mt-3 inline-flex items-center gap-1.5",
              "text-xs font-medium text-ember",
              "hover:text-ember-light transition-colors"
            )}
          >
            <MessageCircle size={14} />
            Talk with ARIA
          </button>
        </div>
      </div>
    </div>
  );
}
