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
          <p className="mb-1.5 text-[11px] font-medium uppercase tracking-[0.2em] text-text-tertiary">
            ARIA
          </p>
          <p className="text-[15px] leading-relaxed text-text-primary">{greeting}</p>
          <button
            type="button"
            onClick={() => setActiveTab("chat")}
            className={cn(
              "mt-4 inline-flex items-center gap-1.5 rounded-full border border-white/12 bg-white/[0.06] px-3.5 py-2",
              "text-xs font-medium text-[#F7F4F0] transition hover:bg-white/[0.1]"
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
