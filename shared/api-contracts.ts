export type ISODate = string;
export type ISODateTime = string;

export type SourceProvider =
  | "apple-health"
  | "health-connect"
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
  chatGamification?: ChatGamificationState;
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

export interface DailyScoresPayload {
  date: ISODate;
  strain: {
    score: number;
    trend: string;
    baselineLoad: number;
    todayLoad: number;
  };
  recovery: {
    score: number;
    hrv?: number;
    trend: string;
  };
  sleep: {
    score: number;
    sleepNeedMinutes: number;
    totalSleepMinutes: number;
    deepSleepMinutes: number;
  };
  trainingDecision: string;
  cycleContext: Record<string, unknown>;
  generatedAt: ISODateTime;
}

export interface BiologicalAgePayload {
  chronologicalAge: number;
  biologicalAge: number;
  deltaYears: number;
  drivers: string[];
  generatedAt: ISODateTime;
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
  dailyScores?: DailyScoresPayload;
  biologicalAge?: BiologicalAgePayload;
}

export interface RegisterPushDeviceRequest {
  token: string;
  platform?: "ios";
  bundleId?: string;
}

export interface RegisterPushDeviceResponse {
  registered: boolean;
  platform: string;
  hasRemoteEndpoint: boolean;
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

export interface LifestyleMetrics {
  sleepAverage: number;
  sleepTarget: number;
  nutritionQuality: number;
  dailySteps: number;
  stressLevel: "Low" | "Medium" | "High";
  qualityOfLifeScore: number;
  physicalHealth: number;
  mentalWellbeing: number;
  energyLevels: number;
  sleepQuality: number;
  nutritionScore: number;
}

export interface LifestyleRecommendation {
  id: string;
  title: string;
  description: string;
  impact: "Low" | "Medium" | "High";
  category: string;
}

export interface NutritionTargets {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  waterMl: number;
}

export interface NutritionMeal {
  id: string;
  date: ISODate;
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  loggedAt?: ISODateTime;
}

export interface NutritionDaily {
  date?: ISODate;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  waterMl: number;
  targets: NutritionTargets;
  meals: NutritionMeal[];
}

export interface WellbeingHabit {
  id: string;
  name: string;
  completed: boolean;
}

export interface LifestyleDashboardResponse {
  date: ISODate;
  metrics: LifestyleMetrics;
  recommendations: LifestyleRecommendation[];
  nutrition: NutritionDaily;
  habits: WellbeingHabit[];
  habitStreak: number;
}

export interface NutritionDailyResponse extends NutritionDaily {}

export interface LogNutritionMealRequest {
  meal: Omit<NutritionMeal, "id" | "loggedAt"> & { id?: string; loggedAt?: ISODateTime };
}

export interface LogNutritionMealResponse {
  meal: NutritionMeal;
}

export interface LogNutritionWaterRequest {
  water: { date?: ISODate; waterMl: number };
}

export interface LogNutritionWaterResponse {
  date: ISODate;
  waterMl: number;
}

export interface RestaurantMenuItem {
  id: string;
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  serving: string;
  isHealthy: boolean;
}

export interface Restaurant {
  id: string;
  name: string;
  logo: string;
  category: string;
  items: RestaurantMenuItem[];
}

export interface RestaurantsResponse {
  restaurants: Restaurant[];
  count: number;
}

export interface WellbeingHabitsResponse {
  date: ISODate;
  habits: WellbeingHabit[];
  habitStreak: number;
}

export interface CompleteWellbeingHabitRequest {
  date?: ISODate;
  completed: boolean;
}

export interface CompleteWellbeingHabitResponse extends WellbeingHabitsResponse {}

export interface ARIAToolCallDetail {
  tool: string;
  input: Record<string, unknown>;
  success: boolean;
}

export interface ARIAChatRequest {
  content: string;
  threadId?: string;
  useTools?: boolean;
}

export interface ARIAChatResponse {
  threadId: string;
  message: ChatMessage & { toolCallsMade?: string[] };
  toolCallsMade: string[];
  toolCallDetails?: ARIAToolCallDetail[];
  model?: string;
  usage?: {
    inputTokens: number;
    outputTokens: number;
    cacheReadTokens?: number;
    cacheCreationTokens?: number;
  };
}

export interface ARIAAnalyzeRequest {
  question: string;
  thinkingBudget?: number;
}

export interface ARIAAnalyzeResponse {
  question: string;
  analysis: string;
  model?: string;
  thinkingBudget?: number;
  usage?: Record<string, number>;
}

export interface ARIAPlanRequest {
  focus?: "auto" | "workout" | "recovery" | "nutrition";
}

export interface ARIAPlanResponse {
  focus: string;
  plan: string;
  toolCallsMade?: ARIAToolCallDetail[];
  model?: string;
  generatedAt: ISODateTime;
}

export interface ARIALifestyleRequest {
  focus?: "nutrition" | "wellbeing" | "holistic";
}

export interface ARIALifestyleResponse {
  focus: string;
  coaching: string;
  toolCallsMade?: ARIAToolCallDetail[];
  model?: string;
  generatedAt: ISODateTime;
}

export interface ARIAVoiceRequest {
  transcript: string;
}

export interface ARIAVoiceResponse {
  answer: string;
  processedTranscript: string;
  model?: string;
  usage?: Record<string, number>;
  timestamp: ISODateTime;
}

export interface ARIAInsight {
  insightId?: string;
  type: "sleep" | "training" | "recovery" | "nutrition" | "mindset";
  priority: "high" | "medium" | "low";
  title: string;
  observation: string;
  recommendation: string;
  metric?: string;
  createdAt?: ISODateTime;
}

export interface ARIAInsightsGenerateResponse {
  insights: ARIAInsight[];
  count: number;
  model?: string;
  generatedAt: ISODateTime;
}

export interface ARIAInsightsListResponse {
  insights: ARIAInsight[];
  count: number;
  periodDays: number;
  retrievedAt: ISODateTime;
}

export interface ARIAConversationResponse {
  threadId: string;
  messages: Array<ChatMessage & { toolCallsMade?: string[] }>;
  messageCount: number;
}

export interface ARIAClearConversationResponse {
  threadId: string;
  cleared: boolean;
  clearedAt: ISODateTime;
}

export interface ARIAOfflineTemplates {
  chat: string;
  dashboard: string;
  mood: string;
  widget: string;
}

export interface ARIADataSignal {
  id: string;
  category: string;
  severity: "high" | "medium" | "low";
  metric: string;
  value?: number;
  baseline?: number;
  direction: string;
}

export interface ARIADataConclusions {
  generatedAt: ISODateTime;
  date: ISODate;
  coveragePct: number;
  readiness: ReadinessData;
  signals: ARIADataSignal[];
  compoundFlags: string[];
  coachingBrief: string;
  dashboardHints: Record<string, unknown>;
  offlineTemplates: ARIAOfflineTemplates;
}

export interface ARIAConclusionsResponse {
  conclusions: ARIADataConclusions;
  coveragePct: number;
  coachingBrief: string;
  compoundFlags: string[];
  offlineTemplates: ARIAOfflineTemplates;
  retrievedAt: ISODateTime;
}

export type ARIABriefFocus = "morning" | "evening" | "post-workout" | "midday" | "auto";

export interface ARIABriefRequest {
  focus?: ARIABriefFocus;
  useLLM?: boolean;
  deliverPush?: boolean;
}

export interface ARIABriefDailyScores {
  date?: ISODate;
  strain?: { score: number; trend?: string };
  recovery?: { score: number; hrv?: number; trend?: string };
  sleep?: { score: number; sleepNeedMinutes?: number };
  trainingDecision?: string;
  cycleContext?: Record<string, unknown>;
}

export interface ARIABriefResponse {
  focus: ARIABriefFocus;
  title: string;
  headline: string;
  body: string;
  notificationCopy: string;
  trainingDecision: string;
  dailyScores?: ARIABriefDailyScores;
  compoundFlags: string[];
  coachingBrief?: string;
  coveragePct?: number;
  generatedAt: ISODateTime;
  llmEnhanced?: boolean;
  model?: string;
}

export interface DeleteAccountResponse {
  deleted: boolean;
  userId: string;
  itemsRemoved: number;
  deletedAt: ISODateTime;
}

export interface ChatGamificationState {
  xp: number;
  level: number;
  messageReactions: Record<string, string>;
  chatStreakDays: number;
  lastChatDate: string;
  totalMessagesSent: number;
  totalReactions: number;
  lifetimeXP: number;
}
