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
