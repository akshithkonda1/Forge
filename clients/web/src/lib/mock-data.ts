import type {
  ChatMessage,
  DailyMetrics,
  PersonalRecord,
  ReadinessData,
  SleepData,
  UserProfile,
  WorkoutHistory,
  WorkoutPlan,
} from "@/types";

/** Offline demo data — only applied when the API is unreachable on first load. */
export const offlineMockProfile: UserProfile = {
  name: "Athlete",
  fitnessGoals: ["build-muscle"],
  experienceLevel: "intermediate",
  preferredWorkouts: ["strength", "hiit"],
  coachingStyle: "balanced",
  connectedDevices: [],
  weeklySchedule: [1, 3, 5],
};

export const offlineMockReadiness: ReadinessData = {
  overall: 72,
  sleepQuality: 74,
  recoveryScore: 70,
  stressLevel: 30,
  energyBank: 68,
  generatedAt: new Date().toISOString(),
};

export const offlineMockMetrics: DailyMetrics = {
  date: new Date().toISOString().slice(0, 10),
  steps: 0,
  activeCalories: 0,
  hrv: 45,
  restingHR: 62,
  deepSleep: 0,
  totalSleep: 0,
  sources: ["manual"],
};

export const offlineMockWorkout: WorkoutPlan = {
  id: "demo-w1",
  date: new Date().toISOString().slice(0, 10),
  name: "Upper Body Power",
  type: "strength",
  duration: 55,
  intensity: "high",
  generatedBy: "system",
  exercises: [
    { id: "e1", name: "Barbell Bench Press", sets: 4, reps: "6-8", weight: 135, restSeconds: 120 },
    { id: "e2", name: "Lat Pulldown", sets: 4, reps: "8-10", weight: 120, restSeconds: 90 },
    { id: "e3", name: "Overhead Press", sets: 3, reps: "8-10", weight: 95, restSeconds: 90 },
  ],
};

export const offlineMockChat: ChatMessage[] = [
  {
    id: "demo-m1",
    role: "trainer",
    content:
      "You're in offline demo mode. Start the backend with npm run backend:dev to sync live coaching and biometrics.",
    timestamp: new Date().toISOString(),
  },
];

export const offlineMockSleep: SleepData[] = [
  {
    date: "2026-06-05",
    totalHours: 7.1,
    deepMinutes: 88,
    remMinutes: 90,
    lightMinutes: 210,
    awakeMinutes: 24,
    score: 78,
    sources: ["manual"],
  },
  {
    date: "2026-06-04",
    totalHours: 6.8,
    deepMinutes: 72,
    remMinutes: 82,
    lightMinutes: 220,
    awakeMinutes: 28,
    score: 71,
    sources: ["manual"],
  },
];

export const offlineMockHistory: WorkoutHistory[] = [];
export const offlineMockPRs: PersonalRecord[] = [];

export const emptyProfile: UserProfile = {
  name: "",
  fitnessGoals: [],
  experienceLevel: "intermediate",
  preferredWorkouts: [],
  coachingStyle: "balanced",
  connectedDevices: [],
  weeklySchedule: [],
};

export const emptyReadiness: ReadinessData = {
  overall: 0,
  sleepQuality: 0,
  recoveryScore: 0,
  stressLevel: 0,
  energyBank: 0,
  generatedAt: new Date(0).toISOString(),
};

export const emptyMetrics: DailyMetrics = {
  date: new Date().toISOString().slice(0, 10),
  steps: 0,
  activeCalories: 0,
  hrv: 0,
  restingHR: 0,
  deepSleep: 0,
  totalSleep: 0,
  sources: [],
};