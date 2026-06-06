export type ISODate = string;
export type ISODateTime = string;

export type SourceProvider =
  | "apple-health"
  | "oura"
  | "whoop"
  | "garmin"
  | "strava"
  | "manual";

export type CoachingStyle = "push-hard" | "balanced" | "patient" | "data-driven";

export type FitnessGoal =
  | "build-muscle"
  | "lose-fat"
  | "improve-endurance"
  | "general-fitness"
  | "athletic-performance";

export type ExperienceLevel = "beginner" | "intermediate" | "advanced" | "elite";

export type WorkoutType = "strength" | "cardio" | "hiit" | "yoga" | "mobility" | "sport-specific";

export type WorkoutIntensity = "low" | "moderate" | "high" | "max";

export interface ApiError {
  message: string;
  code?: string;
  details?: Record<string, unknown>;
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

export type IntegrationMiddleware = "terra" | "native";

export interface IntegrationConnection {
  provider: SourceProvider;
  displayName: string;
  status: "connected" | "needs-auth" | "syncing" | "error";
  lastSyncedAt?: ISODateTime;
  errorMessage?: string;
  middleware?: IntegrationMiddleware;
  terraUserId?: string;
}

export interface TerraWidgetSessionRequest {
  successRedirectUrl: string;
  failureRedirectUrl: string;
  language?: string;
}

export interface TerraWidgetSessionResponse {
  middleware: "terra";
  referenceId: string;
  sessionId?: string;
  url?: string;
  expiresAt?: string;
  status: string;
}

export interface TerraStatusResponse {
  middleware: "terra";
  configured: boolean;
  webhookConfigured: boolean;
  connected: boolean;
  terraUserId?: string;
  provider?: string;
  lastUpdatedAt?: ISODateTime;
}

export interface ReadinessData {
  overall: number;
  sleepQuality: number;
  recoveryScore: number;
  stressLevel: number;
  energyBank: number;
  generatedAt: ISODateTime;
}

export interface DailyMetrics {
  date: ISODate;
  steps: number;
  activeCalories: number;
  hrv: number;
  restingHR: number;
  deepSleep: number;
  totalSleep: number;
  sources: SourceProvider[];
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
  date: ISODate;
  name: string;
  type: WorkoutType;
  duration: number;
  intensity: WorkoutIntensity;
  exercises: Exercise[];
  generatedBy: "system" | "coach" | "user";
}

export interface SleepData {
  date: ISODate;
  totalHours: number;
  deepMinutes: number;
  remMinutes: number;
  lightMinutes: number;
  awakeMinutes: number;
  score: number;
  sources: SourceProvider[];
}

export interface WorkoutHistory {
  id: string;
  date: ISODate;
  name: string;
  type: WorkoutType;
  duration: number;
  volume: number;
  intensity: WorkoutIntensity;
  source: SourceProvider;
}

export interface PersonalRecord {
  exercise: string;
  value: number;
  unit: string;
  date: ISODate;
}

export interface DataChartCard {
  type: "data-chart";
  data: {
    title: string;
    values: number[];
    labels?: string[];
    insight: string;
    color?: string;
  };
}

export interface WorkoutPlanCard {
  type: "workout-plan";
  data: WorkoutPlan;
}

export interface ProgressComparisonCard {
  type: "progress-comparison";
  data: {
    title: string;
    current: number;
    previous: number;
    unit: string;
    insight: string;
  };
}

export type RichCard = DataChartCard | WorkoutPlanCard | ProgressComparisonCard;

export interface ChatMessage {
  id: string;
  role: "trainer" | "user";
  content: string;
  timestamp: ISODateTime;
  richCard?: RichCard;
}

export interface DashboardTodayResponse {
  profile: UserProfile;
  readiness: ReadinessData;
  dailyMetrics: DailyMetrics;
  todayWorkout: WorkoutPlan | null;
  recentSleep: SleepData[];
  recentWorkouts: WorkoutHistory[];
  personalRecords: PersonalRecord[];
  connections: IntegrationConnection[];
}

export interface ProfileResponse {
  profile: UserProfile;
  connections: IntegrationConnection[];
}

export interface UpdateProfileRequest {
  profile: Partial<UserProfile>;
}

export interface SleepListResponse {
  sleep: SleepData[];
}

export interface WorkoutTodayResponse {
  workout: WorkoutPlan | null;
}

export interface WorkoutHistoryResponse {
  workouts: WorkoutHistory[];
  personalRecords: PersonalRecord[];
}

export interface ProgressSummaryResponse {
  periodDays: number;
  workoutsCompleted: number;
  newPersonalRecords: PersonalRecord[];
  recoveryConsistencyDelta: number;
  summary: string;
}

export interface ChatThreadResponse {
  threadId: string;
  messages: ChatMessage[];
}

export interface SendChatMessageRequest {
  content: string;
}

export interface SendChatMessageResponse {
  userMessage: ChatMessage;
  trainerMessage: ChatMessage;
}

export interface HealthMetricInput {
  source: SourceProvider;
  metricType:
    | "steps"
    | "active-calories"
    | "hrv"
    | "resting-heart-rate"
    | "heart-rate"
    | "sleep-stage"
    | "body-weight"
    | "distance";
  startedAt: ISODateTime;
  endedAt?: ISODateTime;
  value: number;
  unit: string;
  metadata?: Record<string, unknown>;
}

export interface HealthBatchRequest {
  metrics: HealthMetricInput[];
}

export interface HealthBatchResponse {
  accepted: number;
  rejected: number;
  errors: ApiError[];
}
