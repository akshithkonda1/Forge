import type { CoachingStyle, DailyMetrics, ReadinessData, SleepData, UserProfile } from "@/types";
import type { RichCard } from "@/types";

export interface CoachReply {
  content: string;
  richCard?: RichCard;
}

function firstName(profile: UserProfile): string {
  const raw = profile.name?.trim() ?? "";
  return raw.split(/\s+/)[0] || "there";
}

function readinessWord(score: number): "primed" | "steady" | "protected" {
  if (score >= 80) return "primed";
  if (score >= 60) return "steady";
  return "protected";
}

function dumpsNumbers(style: CoachingStyle | null | undefined): boolean {
  return style === "data-driven";
}

/**
 * Local, deterministic ARIA. Speaks like a companion, not a HUD.
 * Numbers stay behind the sentence unless the user asked for data-driven voice.
 */
export function coachReply(
  text: string,
  profile: UserProfile,
  readiness: ReadinessData,
  metrics: DailyMetrics,
  sleepData: SleepData[]
): CoachReply {
  const lower = text.toLowerCase();
  const name = firstName(profile);
  const word = readinessWord(readiness.overall);
  const numeric = dumpsNumbers(profile.coachingStyle);

  if (lower.includes("how should i train") || lower.includes("train today")) {
    const lead = numeric
      ? `Readiness ${readiness.overall}/100 — HRV ${metrics.hrv}ms. You're ${word}.`
      : `You're ${word} today. I'll keep the session honest for that.`;
    return {
      content: `${lead} Upper Body Power is the call — bench and pull-ups, about 55 minutes.`,
      richCard: {
        type: "workout-plan",
        data: {
          name: "Upper Body Power",
          duration: 55,
          exercises: [
            { name: "Barbell Bench Press", sets: 4, reps: "6-8" },
            { name: "Weighted Pull-Ups", sets: 4, reps: "6-8" },
            { name: "Overhead Press", sets: 3, reps: "8-10" },
            { name: "Barbell Rows", sets: 3, reps: "8-10" },
            { name: "Incline DB Press", sets: 3, reps: "10-12" },
            { name: "Face Pulls", sets: 3, reps: "15-20" },
          ],
        },
      },
    };
  }

  if (
    lower.includes("not feeling it") ||
    lower.includes("not feeling great") ||
    lower.includes("tired") ||
    lower.includes("low energy")
  ) {
    return {
      content: `Heard. We keep the streak without breaking you down — a short recovery flow, then we reassess tomorrow.`,
      richCard: {
        type: "workout-plan",
        data: {
          name: "Recovery Flow",
          duration: 30,
          exercises: [
            { name: "Foam Rolling", sets: 1, reps: "5 min" },
            { name: "World's Greatest Stretch", sets: 2, reps: "8 each side" },
            { name: "Band Pull-Aparts", sets: 3, reps: "15" },
            { name: "Goblet Squats (light)", sets: 2, reps: "10" },
            { name: "Dead Hangs", sets: 3, reps: "30 sec" },
          ],
        },
      },
    };
  }

  if (lower.includes("sleep") || lower.includes("how did i sleep")) {
    const lastSleep = sleepData[0];
    const deepMinutes = lastSleep?.deepMinutes ?? metrics.deepSleep;
    const totalHours = lastSleep?.totalHours ?? metrics.totalSleep / 60;
    const sleepScores = sleepData.slice(0, 7).map((s) => s.score).reverse();
    const solid = deepMinutes >= 90;
    const lead = numeric
      ? `Last night: ${totalHours.toFixed(1)}h, ${deepMinutes} min deep.`
      : solid
        ? "Last night actually rebuilt you."
        : "Last night was thinner than I'd like.";
    return {
      content: `${lead} Deep sleep is where the work lands — we'll protect that window.`,
      richCard: {
        type: "data-chart",
        data: {
          title: "Sleep Quality (7-day)",
          values: sleepScores.length > 0 ? sleepScores : [68, 74, 91, 62, 93, 80, 88],
          insight: solid
            ? "Deep sleep is doing its job. Keep the wind-down."
            : "Get to bed 30 minutes earlier tonight.",
          color: "#3B82F6",
        },
      },
    };
  }

  if (
    lower.includes("adjust") ||
    lower.includes("change my plan") ||
    lower.includes("modify") ||
    lower.includes("switch")
  ) {
    return {
      content: `Your plan should fit the day, not fight it. Lower body, a lighter recovery day, or a short HIIT hit — which one?`,
    };
  }

  if (
    lower.includes("injury") ||
    lower.includes("pain") ||
    lower.includes("hurt") ||
    lower.includes("sore") ||
    lower.includes("tweaked")
  ) {
    return {
      content: `${name}, we work around it, not through it. Where is it, sharp or dull, and when did it start? If it's more than normal soreness, see a physio — I'll keep the plan honest once you know.`,
    };
  }

  if (
    lower.includes("progress") ||
    lower.includes("how am i doing") ||
    lower.includes("personal record") ||
    lower.includes("gains")
  ) {
    return {
      content: numeric
        ? `${name} — bench climbed, squat is moving, consistency is the real PR. Keep the same rhythm.`
        : `${name}, the work is landing. Consistency is the real PR — keep showing up.`,
      richCard: {
        type: "data-chart",
        data: {
          title: "Strength Progress (4 weeks)",
          values: [185, 195, 205, 215, 225],
          insight: "Bench is trending up. Stay patient on the heavy singles.",
          color: "#FF4D00",
        },
      },
    };
  }

  return {
    content: `${name}, I'm with you. Tell me what the day feels like — training, sleep, or something in the way — and I'll meet you there.`,
  };
}
