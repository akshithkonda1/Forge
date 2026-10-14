"use client";

import { useMemo } from "react";
import { MessageCircle } from "lucide-react";
import { useAppStore } from "@/stores/useAppStore";
import { cn } from "@/lib/utils";
import { getReadinessLabel } from "@/lib/utils";
import { AriaMark } from "@/components/brand/aria-mark";

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
        : "Last night was thinner. A lighter win still counts today.";

  const session = workoutName
    ? readiness.overall >= 85
      ? `You're ${readinessLabel}. Ready to hit ${workoutName}?`
      : readiness.overall >= 70
        ? `You're ${readinessLabel}. ${workoutName} still fits if we stay honest.`
        : readiness.overall >= 50
          ? `You're ${readinessLabel}. Train smart on ${workoutName} — not maximal.`
          : `A lighter win still makes you someone who trains. Keep ${workoutName} easy.`
    : readiness.overall >= 50
      ? "You're someone who trains. Write the session when you're ready."
      : "A lighter win still makes today count.";

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
    <div className="relative overflow-hidden rounded-3xl border border-white/[0.08] bg-white/[0.035] p-5">
      <div
        className="pointer-events-none absolute inset-0 opacity-70"
        style={{
          background:
            "radial-gradient(ellipse 70% 80% at 0% 0%, rgba(255,107,43,0.12), transparent 55%)",
        }}
        aria-hidden
      />
      <div className="relative flex items-start gap-3.5">
        <AriaMark size={40} speaking={false} label="ARIA" className="mt-0.5" />
        <div className="min-w-0 flex-1">
          <p className="type-caption mb-1.5 uppercase tracking-[0.2em] text-text-tertiary">
            ARIA
          </p>
          <p className="type-body text-text-primary">{greeting}</p>
          <button
            type="button"
            onClick={() => setActiveTab("chat")}
            className={cn(
              "min-tap mt-4 inline-flex items-center gap-1.5 rounded-full border border-white/12 bg-white/[0.06] px-3.5",
              "type-caption text-text-primary transition hover:bg-white/[0.1]"
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
