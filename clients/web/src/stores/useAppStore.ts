import { create } from "zustand";
import {
  forgeAPI,
  mapARIAMessage,
  mapConversation,
  type CoachingInsight,
  type ProgressSummary,
} from "@/lib/forge-api";
import { isDemoFallbackAllowed } from "@/lib/auth-config";
import { clearAuthSession, requiresSignIn } from "@/lib/auth-session";
import { API_DISPLAY_HOST } from "@/lib/forge-api";
import { forgePersistence } from "@/lib/persistence";
import {
  emptyMetrics,
  emptyProfile,
  emptyReadiness,
  offlineMockChat,
  offlineMockHistory,
  offlineMockMetrics,
  offlineMockPRs,
  offlineMockProfile,
  offlineMockReadiness,
  offlineMockSleep,
  offlineMockWorkout,
} from "@/lib/mock-data";
import type {
  UserProfile,
  ReadinessData,
  DailyMetrics,
  WorkoutPlan,
  ChatMessage,
  SleepData,
  WorkoutHistory,
  PersonalRecord,
  IntegrationConnection,
} from "@/types";

type DataLoadState = "idle" | "loading" | "loaded" | "offline" | "error";

interface AppState {
  hydrate: () => void;
  isOnboarded: boolean;
  onboardingStep: number;
  setOnboarded: (val: boolean) => void;
  setOnboardingStep: (step: number) => void;

  userProfile: UserProfile;
  connections: IntegrationConnection[];
  updateProfile: (profile: Partial<UserProfile>) => void;

  readiness: ReadinessData;
  dailyMetrics: DailyMetrics;
  todayWorkout: WorkoutPlan | null;

  activeWorkout: {
    isActive: boolean;
    currentExerciseIndex: number;
    currentSet: number;
    isResting: boolean;
    restTimeLeft: number;
    elapsedTime: number;
    currentHR: number;
  };
  startWorkout: () => void;
  nextSet: () => void;
  nextExercise: () => void;
  endWorkout: () => void;

  chatMessages: ChatMessage[];
  addMessage: (msg: ChatMessage) => void;

  sleepData: SleepData[];
  workoutHistory: WorkoutHistory[];
  personalRecords: PersonalRecord[];

  coachingInsights: CoachingInsight[];
  progressSummary: ProgressSummary | null;
  primaryInsight: () => CoachingInsight | undefined;
  sleepInsightText: () => string;

  activeTab: string;
  setActiveTab: (tab: string) => void;

  dataLoadState: DataLoadState;
  dataLoadError: string | null;
  isGeneratingResponse: boolean;
  isSavingProfile: boolean;
  isRefreshingSleep: boolean;
  isRefreshingPlan: boolean;
  loadDashboardFromAPI: () => Promise<void>;
  refreshProfileFromAPI: () => Promise<void>;
  saveProfileToAPI: (profile?: Partial<UserProfile>) => Promise<void>;
  refreshSleepData: (days?: number) => Promise<void>;
  refreshTodayWorkoutPlan: () => Promise<void>;
  sendChatMessage: (text: string) => Promise<void>;
  completeOnboarding: () => Promise<void>;
  signOut: () => void;
}

function userFacingError(error: unknown): string {
  if (error instanceof Error) {
    if (error.name === "AbortError") {
      return isDemoFallbackAllowed()
        ? "Request timed out. Is the backend running?"
        : `Request timed out reaching ${API_DISPLAY_HOST}.`;
    }
    if (error.message.includes("Failed to fetch")) {
      return isDemoFallbackAllowed()
        ? "Can't connect to the API. Run npm run backend:dev."
        : `Can't reach the Forge API at ${API_DISPLAY_HOST}. Check your connection and try again.`;
    }
    return error.message;
  }
  return "Request failed";
}

function applyOfflineDemo(set: (partial: Partial<AppState>) => void) {
  set({
    userProfile: offlineMockProfile,
    readiness: offlineMockReadiness,
    dailyMetrics: offlineMockMetrics,
    todayWorkout: offlineMockWorkout,
    chatMessages: offlineMockChat,
    sleepData: offlineMockSleep,
    workoutHistory: offlineMockHistory,
    personalRecords: offlineMockPRs,
    dataLoadState: "offline",
    dataLoadError: null,
  });
}

export const useAppStore = create<AppState>((set, get) => ({
  hydrate: () => {
    set({
      isOnboarded: forgePersistence.getIsOnboarded(),
      onboardingStep: forgePersistence.getOnboardingStep(),
    });
  },
  isOnboarded: false,
  onboardingStep: 0,
  setOnboarded: (val) => {
    forgePersistence.setIsOnboarded(val);
    set({ isOnboarded: val });
  },
  setOnboardingStep: (step) => {
    forgePersistence.setOnboardingStep(step);
    set({ onboardingStep: step });
  },

  userProfile: emptyProfile,
  connections: [],
  updateProfile: (profile) =>
    set((state) => ({
      userProfile: { ...state.userProfile, ...profile },
    })),

  readiness: emptyReadiness,
  dailyMetrics: emptyMetrics,
  todayWorkout: null,

  activeWorkout: {
    isActive: false,
    currentExerciseIndex: 0,
    currentSet: 1,
    isResting: false,
    restTimeLeft: 0,
    elapsedTime: 0,
    currentHR: 0,
  },
  startWorkout: () =>
    set((state) => ({
      activeWorkout: {
        ...state.activeWorkout,
        isActive: true,
        currentExerciseIndex: 0,
        currentSet: 1,
        elapsedTime: 0,
        currentHR: state.dailyMetrics.restingHR || 72,
      },
    })),
  nextSet: () =>
    set((state) => ({
      activeWorkout: {
        ...state.activeWorkout,
        currentSet: state.activeWorkout.currentSet + 1,
        isResting: true,
      },
    })),
  nextExercise: () =>
    set((state) => ({
      activeWorkout: {
        ...state.activeWorkout,
        currentExerciseIndex: state.activeWorkout.currentExerciseIndex + 1,
        currentSet: 1,
        isResting: false,
      },
    })),
  endWorkout: () =>
    set((state) => {
      if (!state.todayWorkout) {
        return { activeWorkout: { ...state.activeWorkout, isActive: false } };
      }

      const volume = state.todayWorkout.exercises.reduce(
        (sum, exercise) => sum + exercise.sets * (exercise.weight ?? 0),
        0,
      );
      const historyItem: WorkoutHistory = {
        id: `workout-${Date.now()}`,
        date: new Date().toISOString().slice(0, 10),
        name: state.todayWorkout.name,
        type: state.todayWorkout.type,
        duration: state.todayWorkout.duration,
        volume,
        intensity: state.todayWorkout.intensity,
      };

      void forgeAPI
        .postWorkoutLog({
          name: state.todayWorkout.name,
          type: state.todayWorkout.type,
          duration: state.todayWorkout.duration,
          volume,
          intensity: state.todayWorkout.intensity,
          startedAt: new Date().toISOString(),
        })
        .catch((error) => console.warn("Failed to log workout", error));

      return {
        activeWorkout: { ...state.activeWorkout, isActive: false },
        workoutHistory: [historyItem, ...state.workoutHistory],
      };
    }),

  chatMessages: [],
  addMessage: (msg) => set((state) => ({ chatMessages: [...state.chatMessages, msg] })),

  sleepData: [],
  workoutHistory: [],
  personalRecords: [],

  coachingInsights: [],
  progressSummary: null,
  primaryInsight: () => {
    const { coachingInsights } = get();
    return (
      coachingInsights.find((i) => i.type === "training" || i.type === "recovery") ??
      coachingInsights[0]
    );
  },
  sleepInsightText: () => {
    const { coachingInsights, progressSummary, sleepData, dailyMetrics } = get();
    const sleepInsight = coachingInsights.find((i) => i.type === "sleep");
    if (sleepInsight) {
      return `${sleepInsight.observation} ${sleepInsight.recommendation}`;
    }
    if (progressSummary?.summary) return progressSummary.summary;
    const latest = sleepData[0];
    if (!latest) {
      return "Connect Apple Health or a wearable to unlock personalized sleep coaching.";
    }
    const deep = `${Math.floor(latest.deepMinutes / 60)}hr ${latest.deepMinutes % 60}min`;
    if (latest.score >= 85) {
      return `Excellent recovery. ${deep} of deep sleep has you primed for a heavy session today.`;
    }
    if (latest.score >= 70) {
      return `Good sleep — ${deep} of deep sleep. Cut screens 45 minutes before bed to push this score higher.`;
    }
    return `Only ${deep} of deep sleep last night. Consider a lighter session and an earlier bedtime tonight.`;
  },

  activeTab: "home",
  setActiveTab: (tab) => set({ activeTab: tab }),

  dataLoadState: "idle",
  dataLoadError: null,
  isGeneratingResponse: false,
  isSavingProfile: false,
  isRefreshingSleep: false,
  isRefreshingPlan: false,

  loadDashboardFromAPI: async () => {
    if (requiresSignIn()) {
      return;
    }

    const prior = get();
    set({ dataLoadState: "loading", dataLoadError: null });

    try {
      const [dashboard, conversation, progress, insights] = await Promise.all([
        forgeAPI.getDashboardToday(),
        forgeAPI.getARIAConversation().catch(() => null),
        forgeAPI.getProgressSummary(30).catch(() => null),
        forgeAPI.getARIAInsights(7).catch(() => null),
      ]);

      const mappedChat = conversation ? mapConversation(conversation.messages) : [];

      set({
        userProfile: dashboard.profile,
        connections: dashboard.connections ?? [],
        readiness: dashboard.readiness,
        dailyMetrics: dashboard.dailyMetrics,
        todayWorkout: dashboard.todayWorkout,
        sleepData: dashboard.recentSleep,
        workoutHistory: dashboard.recentWorkouts,
        personalRecords: dashboard.personalRecords,
        chatMessages: mappedChat.length > 0 ? mappedChat : prior.chatMessages,
        progressSummary: progress,
        coachingInsights: insights?.insights ?? [],
        dataLoadState: "loaded",
        dataLoadError: null,
      });
    } catch (error) {
      const message = userFacingError(error);
      const hasCachedData =
        prior.sleepData.length > 0 ||
        prior.workoutHistory.length > 0 ||
        prior.readiness.overall > 0;

      if (hasCachedData || !isDemoFallbackAllowed()) {
        set({ dataLoadState: "error", dataLoadError: message });
      } else {
        applyOfflineDemo(set);
      }
      console.warn("Forge API unavailable", error);
    }
  },

  refreshProfileFromAPI: async () => {
    try {
      const profileResponse = await forgeAPI.getMe();
      const connectedDevices = profileResponse.connections
        .filter((connection) => connection.status === "connected")
        .map((connection) => connection.displayName);

      set({
        userProfile: {
          ...get().userProfile,
          ...profileResponse.profile,
          connectedDevices:
            connectedDevices.length > 0
              ? connectedDevices
              : profileResponse.profile.connectedDevices,
        },
        connections: profileResponse.connections,
      });
    } catch (error) {
      console.warn("Failed to refresh profile connections", error);
    }
  },

  saveProfileToAPI: async (profilePatch) => {
    const mergedProfile = { ...get().userProfile, ...profilePatch };
    set({ isSavingProfile: true, userProfile: mergedProfile });

    try {
      const response = await forgeAPI.updateProfile(mergedProfile);
      set({
        userProfile: { ...mergedProfile, ...response.profile },
        isSavingProfile: false,
        dataLoadError: null,
      });
    } catch (error) {
      console.warn("Failed to save profile", error);
      set({
        isSavingProfile: false,
        dataLoadError: userFacingError(error),
      });
      throw error;
    }
  },

  refreshSleepData: async (days = 14) => {
    set({ isRefreshingSleep: true });
    try {
      const response = await forgeAPI.getSleep(days);
      set({
        sleepData: response.sleep,
        isRefreshingSleep: false,
        dataLoadError: null,
      });
    } catch (error) {
      console.warn("Failed to refresh sleep data", error);
      set({
        isRefreshingSleep: false,
        dataLoadError: userFacingError(error),
      });
    }
  },

  refreshTodayWorkoutPlan: async () => {
    set({ isRefreshingPlan: true });
    try {
      const coach = await forgeAPI.fetchCoachWorkoutPlan();
      if (coach.todayPlan) {
        set({
          todayWorkout: coach.todayPlan,
          isRefreshingPlan: false,
          dataLoadError: null,
        });
        return;
      }

      const aria = await forgeAPI.generateARIAPlan("workout");
      set({
        isRefreshingPlan: false,
        dataLoadError: null,
      });
      set({ activeTab: "chat" });
      set((state) => ({
        chatMessages: [
          ...state.chatMessages,
          {
            id: `trainer-plan-${Date.now()}`,
            role: "trainer" as const,
            content: aria.plan,
            timestamp: new Date(),
          },
        ],
      }));
    } catch (error) {
      console.warn("Failed to refresh workout plan", error);
      set({
        isRefreshingPlan: false,
        dataLoadError: userFacingError(error),
        activeTab: "chat",
      });
    }
  },

  sendChatMessage: async (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;

    const userMsg: ChatMessage = {
      id: `user-${Date.now()}`,
      role: "user",
      content: trimmed,
      timestamp: new Date(),
    };

    set((state) => ({
      chatMessages: [...state.chatMessages, userMsg],
      isGeneratingResponse: true,
    }));

    try {
      const response = await forgeAPI.sendARIAChat(trimmed);
      const trainerMsg = mapARIAMessage(response);
      set((state) => ({
        chatMessages: [...state.chatMessages, trainerMsg],
        isGeneratingResponse: false,
      }));
    } catch (error) {
      console.warn("ARIA API failed", error);
      set((state) => ({
        isGeneratingResponse: false,
        chatMessages: [
          ...state.chatMessages,
          {
            id: `trainer-${Date.now()}`,
            role: "trainer" as const,
            content: "Sorry, I'm having trouble connecting right now. Try again in a moment.",
            timestamp: new Date(),
          },
        ],
      }));
    }
  },

  completeOnboarding: async () => {
    forgePersistence.setIsOnboarded(true);
    set({ isOnboarded: true });

    if (!requiresSignIn()) {
      try {
        await get().saveProfileToAPI(get().userProfile);
        await get().loadDashboardFromAPI();
      } catch (error) {
        console.warn("Failed to persist profile", error);
        set({ dataLoadState: "error", dataLoadError: userFacingError(error) });
      }
    }
  },

  signOut: () => {
    clearAuthSession();
    forgePersistence.reset();
    set({
      isOnboarded: false,
      onboardingStep: 0,
      userProfile: emptyProfile,
      connections: [],
      readiness: emptyReadiness,
      dailyMetrics: emptyMetrics,
      todayWorkout: null,
      chatMessages: [],
      sleepData: [],
      workoutHistory: [],
      personalRecords: [],
      coachingInsights: [],
      progressSummary: null,
      dataLoadState: "idle",
      dataLoadError: null,
      activeTab: "home",
    });
  },
}));