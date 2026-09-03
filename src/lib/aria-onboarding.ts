import type { CoachingStyle, ExperienceLevel, FitnessGoal, WorkoutType } from "@/types";

export type AriaOnboardingStep = "welcome" | "profile" | "devices" | "coaching";

export interface AriaWhisper {
  title: string;
  message: string;
  mood: "energized" | "focused" | "calm" | "supportive";
}

/** One beat. A four-line typewriter was four re-renders per character. */
export const ARIA_CINEMATIC_LINES = [
  "I learn how you move, sleep, and live — then build plans that fit.",
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
        message: "Welcome. I'll coach the life you already have — not a spreadsheet of you.",
        mood: "focused",
      };
    case "profile":
      if (first) {
        return {
          title: `Got you, ${first}`,
          message: "Goals and the training you enjoy let me size the week without guessing.",
          mood: "focused",
        };
      }
      return {
        title: "Who am I coaching?",
        message: "Your name first — everything from here gets personal.",
        mood: "focused",
      };
    case "devices":
      if ((ctx.devicesConnected ?? 0) > 0) {
        return {
          title: "Signal lock",
          message: "Nice — recovery can shape the load from day one.",
          mood: "energized",
        };
      }
      return {
        title: "Recovery channel",
        message: "Optional. Connect later and I'll fold recovery in the moment it arrives.",
        mood: "calm",
      };
    case "coaching": {
      const style = ctx.coachingStyle;
      if (!style) {
        return {
          title: "Choose my voice",
          message: "This shapes every check-in and recovery nudge.",
          mood: "focused",
        };
      }
      return {
        title: "Voice locked",
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

export function moodForStyle(style: CoachingStyle): AriaWhisper["mood"] {
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
  const name = ctx.name?.trim().split(/\s+/)[0] || "there";
  const goal = (ctx.goals?.[0] ?? "general-fitness").replace(/-/g, " ");
  const workouts = (ctx.workouts ?? [])
    .slice(0, 2)
    .map((w) => w.replace(/-/g, " "))
    .join(" & ");
  const healthLine =
    (ctx.devicesConnected ?? 0) > 0
      ? " Recovery is already in the loop."
      : " Connect devices anytime and I'll fold recovery in.";

  switch (ctx.coachingStyle) {
    case "push-hard":
      return `${name} — week one targets ${goal}${workouts ? ` through ${workouts}` : ""}.${healthLine}`;
    case "patient":
      return `${name}, we make this doable — small wins toward ${goal}.${healthLine}`;
    case "data-driven":
      return `${name} — load and recovery map back to ${goal}. I'll show the why.${healthLine}`;
    case "balanced":
    default:
      return `${name}, first block balances work and recovery around ${goal}${workouts ? `, favoring ${workouts}` : ""}.${healthLine}`;
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
  return `${firstSessionScript(ctx)} Open chat anytime — I'm already tracking what we built.`;
}
