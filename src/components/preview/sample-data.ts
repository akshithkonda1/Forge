/** Realistic sample fixtures, labeled Sample in the chrome. Not live user data. */
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

export const SAMPLE_WEEK = [
  { key: "mon", label: "M", session: true, today: false },
  { key: "tue", label: "T", session: false, today: false },
  { key: "wed", label: "W", session: true, today: false },
  { key: "thu", label: "T", session: false, today: false },
  { key: "fri", label: "F", session: true, today: false },
  { key: "sat", label: "S", session: false, today: true },
  { key: "sun", label: "S", session: false, today: false },
] as const;

export const SAMPLE_HISTORY = [
  { when: "Thu 15 Oct", name: "Lower Body Strength", minutes: 48 },
  { when: "Mon 12 Oct", name: "Upper Body Power", minutes: 55 },
  { when: "Fri 9 Oct", name: "Pull Emphasis", minutes: 50 },
] as const;

export const SAMPLE_PRS = [
  { exercise: "Bench Press", value: "225 lb", date: "28 Jan" },
  { exercise: "Squat", value: "315 lb", date: "1 Feb" },
  { exercise: "Deadlift", value: "365 lb", date: "15 Jan" },
] as const;

export const SAMPLE_SLEEP = {
  score: 88,
  total: "7h 12m",
  deep: 102,
  rem: 95,
  light: 215,
  awake: 20,
  hours: [
    { key: "22", label: "10", tone: "light" },
    { key: "23", label: "11", tone: "deep" },
    { key: "0", label: "12", tone: "deep" },
    { key: "1", label: "1", tone: "rem" },
    { key: "2", label: "2", tone: "deep" },
    { key: "3", label: "3", tone: "awake" },
    { key: "4", label: "4", tone: "rem" },
    { key: "5", label: "5", tone: "light" },
  ],
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
  water: { current: 5, target: 6, fill: 0.83 },
  lastMeal: "Oats, eggs, leftover salmon — 8:14a",
} as const;
