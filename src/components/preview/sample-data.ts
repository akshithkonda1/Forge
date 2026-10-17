/** Realistic sample fixtures, labeled SAMPLE in the chrome. Not live user data. */
export const SAMPLE_CLOCK = "9:41";
export const SAMPLE_DATE = "Sat 17 Oct";

export const SAMPLE_SESSION = {
  name: "Upper Body Power",
  type: "Strength",
  duration: 55,
  intensity: "High",
  exercises: [
    { n: 1, name: "Barbell Bench Press", rx: "4 × 6–8" },
    { n: 2, name: "Weighted Pull-Ups", rx: "4 × 6–8" },
    { n: 3, name: "Overhead Press", rx: "3 × 8–10" },
    { n: 4, name: "Barbell Rows", rx: "3 × 8–10" },
    { n: 5, name: "Incline Dumbbell Press", rx: "3 × 10–12" },
    { n: 6, name: "Face Pulls", rx: "3 × 15–20" },
  ],
} as const;

export const SAMPLE_METRICS = {
  readiness: 82,
  sleep: 88,
  rest: 79,
  stress: 24,
  energy: 76,
  steps: "3.2k",
  calories: "186",
  hrv: "52",
  rhr: "58",
} as const;

export const SAMPLE_SLEEP = {
  score: 88,
  total: "7h 12m",
  deep: 102,
  rem: 95,
  light: 215,
  awake: 20,
} as const;

export const SAMPLE_MEMORY_NOTES = [
  {
    folder: "Sleep",
    note: "Better nights when lights-out is before 10:30. No titles from Calendar.",
  },
  {
    folder: "Training",
    note: "Commercial gym. Barbell, rack, cables, dumbbells. Never coach form.",
  },
  {
    folder: "People",
    note: "First names you picked: Sam, Priya. Never the whole book.",
  },
] as const;

export const SAMPLE_NUTRITION = {
  protein: { current: "118 g", target: "150 g", fill: 0.79 },
  water: { current: "5 glasses", target: "6", fill: 0.83 },
  lastMeal: "Oats, eggs, leftover salmon — 8:14a",
} as const;
