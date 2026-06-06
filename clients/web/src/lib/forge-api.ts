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

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

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
}

export interface ARIAChatResponse {
  threadId: string;
  message: {
    id: string;
    role: string;
    content: string;
    timestamp: string;
  };
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });

  if (!response.ok) {
    const body = await response.json().catch(() => ({ message: response.statusText }));
    throw new ForgeAPIError(body.message ?? "Request failed", response.status);
  }

  return response.json() as Promise<T>;
}

export const forgeAPI = {
  getDashboardToday: () => request<DashboardTodayResponse>("/dashboard/today"),
  getSleep: (days = 14) => request<{ sleep: SleepData[] }>(`/sleep?days=${days}`),
  getWorkoutHistory: (days = 30) =>
    request<{ workouts: WorkoutHistory[]; personalRecords: PersonalRecord[] }>(
      `/workouts/history?days=${days}`,
    ),
  getProgressSummary: (days = 30) =>
    request<{
      periodDays: number;
      workoutsCompleted: number;
      summary: string;
    }>(`/progress/summary?days=${days}`),
  sendARIAChat: (content: string) =>
    request<ARIAChatResponse>("/aria/chat", {
      method: "POST",
      body: JSON.stringify({ content }),
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
};

export function mapARIAMessage(response: ARIAChatResponse): ChatMessage {
  return {
    id: response.message.id,
    role: response.message.role === "user" ? "user" : "trainer",
    content: response.message.content,
    timestamp: new Date(response.message.timestamp),
  };
}
