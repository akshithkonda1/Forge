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

export interface IntegrationConnection {
  provider: SourceProvider;
  displayName: string;
  status: "connected" | "needs-auth" | "syncing" | "error";
  lastSyncedAt?: ISODateTime;
  errorMessage?: string;
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

// ---------------------------------------------------------------------------
// ARIA coaching contract (Phase 1). Versioned interface for POST /ai/chat.
// Keep in sync with services/aria_engine.py. Do not add top-level response
// fields without bumping ARIA_SCHEMA_VERSION.
//   v1.1 — all data domains + per-domain data permissions + restricted_domains.
// ---------------------------------------------------------------------------

export const ARIA_SCHEMA_VERSION = "1.1";

export type AriaResponseType =
  | "insight"
  | "recommendation"
  | "plan"
  | "summary"
  | "clarification";

/** Every data domain ARIA can reason over. Each is independently grantable via
 *  AriaDataPermissions. */
export type AriaDataDomain =
  | "sleep"
  | "readiness"
  | "activity"
  | "training"
  | "chronotype"
  | "body"
  | "nutrition"
  | "profile"
  | "progress"
  | "lifestyle";

/** Living user model ARIA reasons over, spanning every data domain. Absent
 *  signals are `null`, never omitted, so `missingFields` stays honest. */
export interface AriaContext {
  timestamp: ISODateTime;
  sleep: {
    durationMinutes: number | null;
    efficiency: number | null; // 0–1
    remMinutes: number | null;
    deepMinutes: number | null;
    hrv: number | null; // SDNN ms, during sleep
    restingHR: number | null;
    nightsAvailable: number | null; // history depth, gates personal baseline (≥3)
  };
  readiness: {
    hrv7DayTrend: number | null; // % vs 30-day baseline
    hrv30DayBaseline: number | null;
    recoveryScore: number | null; // 0–100
    hrvDaysAvailable: number | null; // history depth, gates confidence
  };
  training: {
    lastWorkoutType: string | null;
    lastWorkoutDurationMinutes: number | null;
    hoursSinceLastWorkout: number | null;
    weeklyLoadScore: number | null; // null if < 3 sessions
  };
  activity: {
    steps3DayAvg: number | null;
    activeCalories3DayAvg: number | null;
  };
  chronotype: {
    typicalSleepOnset: string | null; // "23:30"
    typicalWakeTime: string | null; // "07:00"
    consistencyScore: number | null; // 0–1
  };
  body: {
    weightKg: number | null;
    weightTrendKg: number | null; // signed 30-day delta
    bodyFatPct: number | null;
    vo2Max: number | null;
  };
  nutrition: {
    caloriesIn3DayAvg: number | null;
    proteinG3DayAvg: number | null;
    hydrationMl3DayAvg: number | null;
    calorieTarget: number | null;
  };
  profile: {
    primaryGoal: FitnessGoal | null;
    experienceLevel: ExperienceLevel | null;
    coachingStyle: CoachingStyle | null;
    constraints: string[]; // injuries, time, equipment
  };
  progress: {
    workoutsCompleted30d: number | null;
    newPersonalRecords: number | null;
    trainingLoadTrend: "rising" | "steady" | "falling" | null;
    recoveryConsistencyDelta: number | null;
  };
  lifestyle: {
    tags: string[];
    recentPatterns: string[];
    goals: string[];
  };
}

/** Per-domain grants. Accepts a `{domain: boolean}` map, an `{allow|deny: []}`
 *  object, or an allow-list array. Omitted ⇒ allow-all (opt-out). Denied
 *  domains are redacted before ARIA reasons, and reported in restricted_domains. */
export type AriaDataPermissions =
  | Partial<Record<AriaDataDomain, boolean>>
  | { allow?: AriaDataDomain[]; deny?: AriaDataDomain[] }
  | AriaDataDomain[];

export interface AriaInsightCard {
  metric: string;
  current_value: string;
  vs_baseline: string;
  interpretation: string;
  priority: "high" | "medium" | "low";
}

export interface AriaRecommendationCard {
  action: string;
  rationale: string;
  timing: string;
  expected_effect: string;
}

export interface AriaSummaryCard {
  period_days: number;
  headline: string;
  win: string;
  risk: string;
  recommendation: string;
}

export interface AriaClarificationCard {
  question: string;
  why: string;
}

export type AriaCard =
  | AriaInsightCard
  | AriaRecommendationCard
  | AriaSummaryCard
  | AriaClarificationCard
  | null;

export interface AriaChatRequest {
  user_id: string;
  message: string;
  voice_mode?: boolean;
  /** Preferred: full structured context. */
  context?: AriaContext;
  /** Which domains ARIA may use this turn. Omitted ⇒ all allowed. */
  permissions?: AriaDataPermissions;
  /** Legacy fallback the engine still accepts (flat metric bag). */
  recent_metrics?: Record<string, number>;
}

/** Versioned response envelope. The first seven fields are canonical (schema
 *  v1.1); the remainder is the compatibility layer for the deployed chat UI. */
export interface AriaResponseEnvelope {
  schema_version: typeof ARIA_SCHEMA_VERSION;
  response_type: AriaResponseType;
  confidence: number; // 0.0–1.0, calibrated
  confidence_reason: string; // why confidence is this level (required < 0.5)
  prose_summary: string; // 1–3 sentences, mandatory voice-mode fallback
  card: AriaCard;
  restricted_domains: AriaDataDomain[]; // domains the user turned off this turn
  // --- compatibility layer ---
  message: string; // chat-bubble text (may be richer than prose_summary)
  suggested_actions: string[];
  model: string; // model the live path would route to
  context_updates?: { relationship_level: number };
  memory_reference?: string | null;
  missing_fields?: string[];
}
