import {
  clearAuthSession,
  getAuthorizationHeader,
  refreshSessionIfNeeded,
} from "@/lib/auth-session";
import { isAuthConfigured } from "@/lib/auth-config";
import type {
  ChatMessage,
  DailyMetrics,
  IntegrationConnection,
  PersonalRecord,
  ReadinessData,
  RichCard,
  SleepData,
  UserProfile,
  WorkoutHistory,
  WorkoutPlan,
} from "@/types";

export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://127.0.0.1:3001";

export const API_DISPLAY_HOST = API_BASE_URL.replace(/^https?:\/\//, "");

export class ForgeAPIError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "ForgeAPIError";
  }
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

export interface APIRichCardPayload {
  type: string;
  data?: Record<string, unknown>;
}

export interface ARIAChatResponse {
  threadId: string;
  message: {
    id: string;
    role: string;
    content: string;
    timestamp: string;
    richCard?: APIRichCardPayload;
    toolCallsMade?: string[];
  };
  toolCallsMade?: string[];
  toolCallDetails?: Array<{ tool: string; input: Record<string, unknown>; success: boolean }>;
}

export interface ARIAConversationMessage {
  id?: string;
  role: string;
  content: string;
  timestamp?: string;
  richCard?: APIRichCardPayload;
}

export interface ARIAConversationResponse {
  threadId: string;
  messages: ARIAConversationMessage[];
  messageCount: number;
}

export interface ARIAOfflineTemplates {
  chat: string;
  dashboard: string;
  mood: string;
  widget: string;
}

export interface ARIAConclusionsResponse {
  conclusions: Record<string, unknown>;
  coveragePct: number;
  coachingBrief: string;
  compoundFlags: string[];
  offlineTemplates: ARIAOfflineTemplates;
  retrievedAt: string;
}

export interface CoachingInsight {
  insightId?: string;
  type: string;
  priority: string;
  title: string;
  observation: string;
  recommendation: string;
  metric?: string;
}

export interface ProgressSummary {
  periodDays: number;
  workoutsCompleted: number;
  newPersonalRecords: { exercise: string; value: number; unit: string; date: string }[];
  recoveryConsistencyDelta: number;
  summary: string;
}

export async function forgeFetch<T>(
  path: string,
  init?: RequestInit,
  retriedAfterUnauthorized = false,
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);

  const headers = new Headers(init?.headers);
  headers.set("Content-Type", "application/json");

  const authorization = getAuthorizationHeader();
  if (authorization) {
    headers.set("Authorization", authorization);
  }

  try {
    const response = await fetch(`${API_BASE_URL}${path}`, {
      ...init,
      signal: controller.signal,
      headers,
    });

    if (
      response.status === 401 &&
      isAuthConfigured() &&
      !retriedAfterUnauthorized
    ) {
      const refreshed = await refreshSessionIfNeeded(true);
      if (refreshed) {
        return forgeFetch<T>(path, init, true);
      }
      clearAuthSession();
      throw new ForgeAPIError("Session expired. Sign in again.", 401);
    }

    if (!response.ok) {
      const body = await response.json().catch(() => ({ message: response.statusText }));
      throw new ForgeAPIError(body.message ?? "Request failed", response.status);
    }

    return response.json() as Promise<T>;
  } finally {
    clearTimeout(timeout);
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  return forgeFetch<T>(path, init);
}

export const forgeAPI = {
  getMe: () => request<ProfileResponse>("/me"),
  getDashboardToday: () => request<DashboardTodayResponse>("/dashboard/today"),
  getSleep: (days = 14) => request<{ sleep: SleepData[] }>(`/sleep?days=${days}`),
  getWorkoutHistory: (days = 30) =>
    request<{ workouts: WorkoutHistory[]; personalRecords: PersonalRecord[] }>(
      `/workouts/history?days=${days}`,
    ),
  getProgressSummary: (days = 30) =>
    request<ProgressSummary>(`/progress/summary?days=${days}`),
  getARIAConversation: (threadId = "current") =>
    request<ARIAConversationResponse>(`/aria/conversation?threadId=${threadId}`),
  getARIAInsights: (days = 7) =>
    request<{ insights: CoachingInsight[]; count: number; periodDays: number }>(
      `/aria/insights?days=${days}`,
    ),
  sendARIAChat: (content: string, useTools = false) =>
    request<ARIAChatResponse>("/aria/chat", {
      method: "POST",
      body: JSON.stringify({ content, useTools }),
    }),
  getARIAConclusions: () => request<ARIAConclusionsResponse>("/aria/conclusions"),
  sendARIAVoice: (transcript: string) =>
    request<{ answer: string; processedTranscript: string; pipelineIncomplete?: boolean }>(
      "/aria/voice",
      { method: "POST", body: JSON.stringify({ transcript }) },
    ),
  generateARIALifestyle: (focus: "nutrition" | "wellbeing" | "holistic" = "holistic") =>
    request<{ focus: string; coaching: string; generatedAt: string }>("/aria/lifestyle", {
      method: "POST",
      body: JSON.stringify({ focus }),
    }),
  deleteARIAConversation: (threadId = "current") =>
    request<{ cleared: boolean }>(`/aria/conversation?threadId=${threadId}`, {
      method: "DELETE",
    }),
  deleteAccount: () =>
    request<{ deleted: boolean; itemsRemoved: number }>("/me/account", {
      method: "DELETE",
    }),
  updateProfile: (profile: Partial<UserProfile>) =>
    request<{ profile: UserProfile }>("/me/profile", {
      method: "PUT",
      body: JSON.stringify({ profile }),
    }),
  postWorkoutLog: (workout: {
    name: string;
    type: string;
    duration: number;
    volume: number;
    intensity: string;
    startedAt: string;
  }) =>
    request("/workouts/logs", {
      method: "POST",
      body: JSON.stringify({ workout }),
    }),
  getDeviceConnectionStatus: () =>
    request<{
      configured: boolean;
      connected: boolean;
      provider?: string;
    }>("/integrations/terra/status"),
  createWearableWidgetSession: (payload: {
    successRedirectUrl: string;
    failureRedirectUrl: string;
    language?: string;
  }) =>
    request<{
      referenceId: string;
      sessionId?: string;
      url?: string;
      expiresAt?: string;
      status: string;
    }>("/integrations/terra/widget", {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  syncIntegration: (provider: string) =>
    request<{
      provider: string;
      jobId: string;
      status: string;
      queuedAt: string;
      requested?: string[];
    }>(`/integrations/${provider}/sync`, {
      method: "POST",
      body: JSON.stringify({}),
    }),
  generateARIAPlan: (focus: "workout" | "recovery" | "nutrition" | "auto" = "auto") =>
    request<{ focus: string; plan: string; generatedAt: string }>("/aria/plan", {
      method: "POST",
      body: JSON.stringify({ focus }),
    }),
};

function mapRichCard(payload?: APIRichCardPayload): RichCard | undefined {
  if (!payload?.type || !payload.data) return undefined;

  const type = payload.type as RichCard["type"];
  if (
    type !== "workout-plan" &&
    type !== "data-chart" &&
    type !== "progress-comparison" &&
    type !== "form-check"
  ) {
    return undefined;
  }

  return { type, data: payload.data };
}

export function mapARIAMessage(response: ARIAChatResponse): ChatMessage {
  return {
    id: response.message.id,
    role: response.message.role === "user" ? "user" : "trainer",
    content: response.message.content,
    timestamp: new Date(response.message.timestamp),
    richCard: mapRichCard(response.message.richCard),
  };
}

export function mapConversation(messages: ARIAConversationMessage[]): ChatMessage[] {
  return messages
    .filter((message) => {
      const trimmed = message.content.trim();
      return trimmed.length > 0 && !trimmed.startsWith("[ARIA CONVERSATION SUMMARY");
    })
    .map((message) => ({
      id: message.id ?? `msg-${message.timestamp ?? Date.now()}`,
      role: message.role === "user" ? "user" : "trainer",
      content: message.content.trim(),
      timestamp: message.timestamp ? new Date(message.timestamp) : new Date(),
      richCard: mapRichCard(message.richCard),
    }));
}