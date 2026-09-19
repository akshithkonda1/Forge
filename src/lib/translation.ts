export interface TranslationPillar {
  id: string;
  title: string;
  bullets: string[];
  accessoryNote?: string;
}

export const TRANSLATION_TAGLINE = "Your body talks. Forge translates.";

export const METABOLIC_ACCESSORY_NOTE =
  "Glucose via Stelo, Dexcom, Lingo, or Libre — sold separately. Forge reads it after you share it into Apple Health.";

export const TRANSLATION_PILLARS: TranslationPillar[] = [
  {
    id: "sleep",
    title: "Sleep",
    bullets: ["Last night and stages", "Chronotype", "Sleep debt", "Wind-down and smart wake"],
  },
  {
    id: "train",
    title: "Train",
    bullets: ["Today’s session", "Workout heart rate", "Steps and active calories", "Training load"],
  },
  {
    id: "metabolic",
    title: "Metabolic",
    bullets: ["Meals you logged", "Nutritional breakdown", "Hydration", "Glucose from a CGM"],
    accessoryNote: METABOLIC_ACCESSORY_NOTE,
  },
  {
    id: "stress",
    title: "Stress",
    bullets: ["Daytime load", "Mindfulness minutes", "Recovery", "Night wind-down"],
  },
  {
    id: "heart",
    title: "Heart",
    bullets: [
      "Cardiovascular age vs calendar age",
      "VO₂ max",
      "Heart rate variability",
      "All-day heart rate",
    ],
  },
  {
    id: "cycle",
    title: "Cycle",
    bullets: [
      "Phase and day",
      "Period as a range",
      "Training by phase",
      "Support for the people around you",
    ],
  },
];

/** Mirrors ForgeCore `AgingSnapshot.oneBreathLine`. */
export function oneBreathLine(input: {
  chronologicalAge?: number | null;
  fitnessAge?: number | null;
  biologicalAge?: number | null;
  confidence?: number;
}): string {
  const chrono = input.chronologicalAge;
  if (chrono == null) return "";
  if (input.fitnessAge != null) {
    return oneBreathSentence("cardiovascular age", input.fitnessAge, chrono);
  }
  if (input.biologicalAge == null || (input.confidence ?? 0) <= 0.25) return "";
  return oneBreathSentence("training age", input.biologicalAge, chrono);
}

function oneBreathSentence(noun: string, years: number, calendar: number): string {
  const delta = years - calendar;
  if (delta <= -2) return `Your ${noun} is below your actual age.`;
  if (delta >= 2) return `Your ${noun} is above your actual age.`;
  return `Your ${noun} is tracking your actual age.`;
}
