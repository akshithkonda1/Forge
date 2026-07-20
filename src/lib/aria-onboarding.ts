import type { CoachingStyle, ExperienceLevel, FitnessGoal, WorkoutType } from "@/types";

export type AriaOnboardingStep = "welcome" | "profile" | "devices" | "coaching";

export interface AriaWhisper {
  title: string;
  message: string;
  mood: "energized" | "focused" | "calm" | "supportive";
}

export const ARIA_CINEMATIC_LINES = [
  "I'm Aria — your adaptive recovery and intelligence coach.",
  "I learn how you move, sleep, stress, and recover.",
  "Then I build plans that respect your body and your ambition.",
  "Let's start with the signals that make coaching personal.",
] as const;

export function whisperForStep(
  step: AriaOnboardingStep,
  ctx: {
    name?: string;
    goals?: FitnessGoal[];
    experience?: ExperienceLevel | null;
    workouts?: WorkoutType[];
    coachingStyle?: CoachingStyle | null;
    devicesConnected?: number;
  } = {}
): AriaWhisper {
  const first = ctx.name?.trim().split(/\s+/)[0];

  switch (step) {
    case "welcome":
      return {
        title: "ARIA online",
        message:
          "Welcome. I'm here to unify your health signals and coach you like someone who actually knows you.",
        mood: "focused",
      };
    case "profile":
      if (first) {
        return {
          title: `Calibrating ${first}`,
          message:
            "Goals, experience, and the training you enjoy let me size intensity and speak your language.",
          mood: "focused",
        };
      }
      return {
        title: "Who am I coaching?",
        message:
          "Tell me your name first — everything from here will feel more human.",
        mood: "focused",
      };
    case "devices":
      if ((ctx.devicesConnected ?? 0) > 0) {
        return {
          title: "Signal lock",
          message: `Nice — ${ctx.devicesConnected} source${(ctx.devicesConnected ?? 0) > 1 ? "s" : ""} connected. Recovery and load will shape every plan.`,
          mood: "energized",
        };
      }
      return {
        title: "Recovery channel",
        message:
          "Optional but powerful. Connect devices so I can protect you on low-readiness days and push when you're primed.",
        mood: "calm",
      };
    case "coaching": {
      const style = ctx.coachingStyle;
      const goal = ctx.goals?.[0]?.replace(/-/g, " ") ?? "general fitness";
      if (!style) {
        return {
          title: "Choose my voice",
          message:
            "This shapes every check-in, plan adjustment, and recovery nudge.",
          mood: "focused",
        };
      }
      return {
        title: `Voice locked`,
        message: firstSessionScript({
          name: ctx.name,
          goals: ctx.goals,
          experience: ctx.experience,
          workouts: ctx.workouts,
          coachingStyle: style,
          devicesConnected: ctx.devicesConnected,
        }),
        mood: moodForStyle(style),
      };
    }
  }
}

export function moodForStyle(
  style: CoachingStyle
): AriaWhisper["mood"] {
  switch (style) {
    case "push-hard":
      return "energized";
    case "patient":
      return "supportive";
    case "data-driven":
      return "focused";
    case "balanced":
    default:
      return "calm";
  }
}

export function firstSessionScript(ctx: {
  name?: string;
  goals?: FitnessGoal[];
  experience?: ExperienceLevel | null;
  workouts?: WorkoutType[];
  coachingStyle: CoachingStyle;
  devicesConnected?: number;
}): string {
  const name = ctx.name?.trim() || "there";
  const goal = (ctx.goals?.[0] ?? "general-fitness").replace(/-/g, " ");
  const workouts = (ctx.workouts ?? [])
    .slice(0, 2)
    .map((w) => w.replace(/-/g, " "))
    .join(" & ");
  const healthLine =
    (ctx.devicesConnected ?? 0) > 0
      ? "Recovery signals are already in the loop."
      : "Connect devices anytime and I'll fold recovery into every call.";

  switch (ctx.coachingStyle) {
    case "push-hard":
      return `${name} — standards first. Week one targets ${goal}${workouts ? ` through ${workouts}` : ""}. Show up. Execute. Earn progression. ${healthLine}`;
    case "patient":
      return `${name}, we make this doable from day one. Small wins toward ${goal}, clear next steps, zero shame spirals. ${healthLine}`;
    case "data-driven":
      return `${name} — intensity, volume, and recovery will all map back to ${goal}. I'll explain the why so every session compounds. ${healthLine}`;
    case "balanced":
    default:
      return `${name}, your first block balances progressive work with recovery around ${goal}${workouts ? `, favoring ${workouts}` : ""}. Clear sessions, room to breathe. ${healthLine}`;
  }
}

export function welcomeChatMessage(ctx: {
  name?: string;
  goals?: FitnessGoal[];
  experience?: ExperienceLevel | null;
  workouts?: WorkoutType[];
  coachingStyle: CoachingStyle;
  devicesConnected?: number;
}): string {
  return (
    firstSessionScript(ctx) +
    "\n\nOpen chat anytime — I'm already tracking the context we built together."
  );
}
