export type CoachingStyle = "push-hard" | "balanced" | "patient" | "data-driven";

export type FitnessGoal = "build-muscle" | "lose-fat" | "improve-endurance" | "general-fitness" | "athletic-performance";

export type ExperienceLevel = "beginner" | "intermediate" | "advanced" | "elite";

export type WorkoutType = "strength" | "cardio" | "hiit" | "yoga" | "mobility" | "sport-specific";

export type SourceProvider =
  | "apple-health"
  | "oura"
  | "whoop"
  | "garmin"
  | "strava"
  | "manual";

export type IntegrationMiddleware = "terra" | "native";

export interface IntegrationConnection {
  provider: SourceProvider;
  displayName: string;
  status: "connected" | "needs-auth" | "syncing" | "error";
  lastSyncedAt?: string;
  errorMessage?: string;
  middleware?: IntegrationMiddleware;
  terraUserId?: string;
}

export interface UserProfile {
  name: string;
  fitnessGoals: FitnessGoal[];
  experienceLevel: ExperienceLevel;
  preferredWorkouts: WorkoutType[];
  coachingStyle: CoachingStyle;
  connectedDevices: string[];
  weeklySchedule: number[];
}

export interface ReadinessData {
  overall: number;
  sleepQuality: number;
  recoveryScore: number;
  stressLevel: number;
  energyBank: number;
}

export interface DailyMetrics {
  steps: number;
  activeCalories: number;
  hrv: number;
  restingHR: number;
  deepSleep: number;
  totalSleep: number;
}

export interface Exercise {
  id: string;
  name: string;
  sets: number;
  reps: number | string;
  weight?: number;
  restSeconds: number;
  notes?: string;
}

export interface WorkoutPlan {
  id: string;
  name: string;
  type: WorkoutType;
  duration: number;
  intensity: "low" | "moderate" | "high" | "max";
  exercises: Exercise[];
}

export interface ChatMessage {
  id: string;
  role: "trainer" | "user";
  content: string;
  timestamp: Date;
  richCard?: RichCard;
}

export interface RichCard {
  type: "workout-plan" | "data-chart" | "progress-comparison" | "form-check";
  data: Record<string, unknown>;
}

export interface SleepData {
  date: string;
  totalHours: number;
  deepMinutes: number;
  remMinutes: number;
  lightMinutes: number;
  awakeMinutes: number;
  score: number;
}

export interface WorkoutHistory {
  id: string;
  date: string;
  name: string;
  type: WorkoutType;
  duration: number;
  volume: number;
  intensity: string;
}

export interface PersonalRecord {
  exercise: string;
  value: number;
  unit: string;
  date: string;
}
