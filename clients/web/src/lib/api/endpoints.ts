import { apiFetch } from "@/lib/api/client";
import type {
  ChatThreadResponse,
  DashboardTodayResponse,
  HealthBatchResponse,
  HealthMetricInput,
  ProfileResponse,
  ProgressSummaryResponse,
  SendChatMessageResponse,
  SleepListResponse,
  UserProfile,
  WorkoutHistory,
  WorkoutHistoryResponse,
  WorkoutTodayResponse,
} from "@/types";

// One typed function per backend route. `token` is null in auth-disabled dev mode.
type Token = string | null;

export const getMe = (token: Token) => apiFetch<ProfileResponse>("/me", { token });

export const updateProfile = (token: Token, profile: Partial<UserProfile>) =>
  apiFetch<ProfileResponse>("/me/profile", { method: "PUT", token, body: { profile } });

export const getDashboardToday = (token: Token) =>
  apiFetch<DashboardTodayResponse>("/dashboard/today", { token });

export const getSleep = (token: Token, days = 14) =>
  apiFetch<SleepListResponse>(`/sleep?days=${days}`, { token });

export const getWorkoutsToday = (token: Token) =>
  apiFetch<WorkoutTodayResponse>("/workouts/today", { token });

export const getWorkoutHistory = (token: Token, days = 30) =>
  apiFetch<WorkoutHistoryResponse>(`/workouts/history?days=${days}`, { token });

export const getProgressSummary = (token: Token, days = 30) =>
  apiFetch<ProgressSummaryResponse>(`/progress/summary?days=${days}`, { token });

export const getChatThread = (token: Token) =>
  apiFetch<ChatThreadResponse>("/chat/threads/current", { token });

export const sendChatMessage = (token: Token, content: string) =>
  apiFetch<SendChatMessageResponse>("/chat/threads/current/messages", {
    method: "POST",
    token,
    body: { content },
  });

/** The backend stores the posted workout object under WORKOUT#{startedAt} and echoes it back. */
export interface WorkoutLogInput extends Omit<WorkoutHistory, "id"> {
  id?: string;
  startedAt: string;
}

export const postWorkoutLog = (token: Token, workout: WorkoutLogInput) =>
  apiFetch<{ workout: WorkoutLogInput }>("/workouts/logs", {
    method: "POST",
    token,
    body: { workout },
  });

export const postHealthBatch = (token: Token, metrics: HealthMetricInput[]) =>
  apiFetch<HealthBatchResponse>("/health/batch", { method: "POST", token, body: { metrics } });
