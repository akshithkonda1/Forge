import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";
import type {
  UserProfile,
  ReadinessData,
  DailyMetrics,
  WorkoutPlan,
  ChatMessage,
  SleepData,
  WorkoutHistory,
  PersonalRecord,
} from "@/types";
import { welcomeChatMessage } from "@/lib/aria-onboarding";

export type TabId = "home" | "chat" | "workout" | "sleep" | "profile";

export interface NotificationPrefs {
  workoutReminders: boolean;
  aiInsights: boolean;
  recoveryAlerts: boolean;
  weeklySummary: boolean;
}

const defaultNotificationPrefs: NotificationPrefs = {
  workoutReminders: true,
  aiInsights: true,
  recoveryAlerts: true,
  weeklySummary: false,
};

interface AppState {
  hasHydrated: boolean;
  setHasHydrated: (val: boolean) => void;

  // Onboarding
  isOnboarded: boolean;
  onboardingStep: number;
  setOnboarded: (val: boolean) => void;
  setOnboardingStep: (step: number) => void;
  resetSession: () => void;
  seedAriaWelcome: () => void;

  // User Profile
  userProfile: UserProfile;
  updateProfile: (profile: Partial<UserProfile>) => void;

  // Readiness
  readiness: ReadinessData;

  // Daily Metrics
  dailyMetrics: DailyMetrics;

  // Today's Workout
  todayWorkout: WorkoutPlan | null;

  // Active Workout
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

  // Chat
  chatMessages: ChatMessage[];
  addMessage: (msg: ChatMessage) => void;

  // Sleep
  sleepData: SleepData[];

  // History
  workoutHistory: WorkoutHistory[];
  personalRecords: PersonalRecord[];

  // Navigation
  activeTab: TabId;
  setActiveTab: (tab: TabId) => void;

  notificationPrefs: NotificationPrefs;
  setNotificationPref: (key: keyof NotificationPrefs, value: boolean) => void;
}

const mockProfile: UserProfile = {
  name: "Akshith",
  fitnessGoals: ["build-muscle"],
  experienceLevel: "intermediate",
  preferredWorkouts: ["strength", "hiit"],
  coachingStyle: "push-hard",
  connectedDevices: ["Apple Watch", "Oura Ring"],
  weeklySchedule: [1, 3, 5],
};

const mockReadiness: ReadinessData = {
  overall: 82,
  sleepQuality: 88,
  recoveryScore: 79,
  stressLevel: 24,
  energyBank: 76,
};

const mockMetrics: DailyMetrics = {
  steps: 3241,
  activeCalories: 186,
  hrv: 52,
  restingHR: 58,
  deepSleep: 102,
  totalSleep: 432,
};

const mockWorkout: WorkoutPlan = {
  id: "w1",
  name: "Upper Body Power",
  type: "strength",
  duration: 55,
  intensity: "high",
  exercises: [
    { id: "e1", name: "Barbell Bench Press", sets: 4, reps: "6-8", weight: 185, restSeconds: 120, notes: "Focus on controlled eccentric" },
    { id: "e2", name: "Weighted Pull-Ups", sets: 4, reps: "6-8", weight: 25, restSeconds: 120 },
    { id: "e3", name: "Overhead Press", sets: 3, reps: "8-10", weight: 115, restSeconds: 90 },
    { id: "e4", name: "Barbell Rows", sets: 3, reps: "8-10", weight: 155, restSeconds: 90 },
    { id: "e5", name: "Incline Dumbbell Press", sets: 3, reps: "10-12", weight: 65, restSeconds: 60 },
    { id: "e6", name: "Face Pulls", sets: 3, reps: "15-20", weight: 30, restSeconds: 60 },
  ],
};

const mockSleepData: SleepData[] = [
  { date: "2026-02-10", totalHours: 7.2, deepMinutes: 102, remMinutes: 95, lightMinutes: 215, awakeMinutes: 20, score: 88 },
  { date: "2026-02-09", totalHours: 6.8, deepMinutes: 78, remMinutes: 88, lightMinutes: 225, awakeMinutes: 17, score: 74 },
  { date: "2026-02-08", totalHours: 7.5, deepMinutes: 110, remMinutes: 100, lightMinutes: 220, awakeMinutes: 20, score: 91 },
  { date: "2026-02-07", totalHours: 6.2, deepMinutes: 65, remMinutes: 72, lightMinutes: 210, awakeMinutes: 25, score: 62 },
  { date: "2026-02-06", totalHours: 7.8, deepMinutes: 115, remMinutes: 105, lightMinutes: 228, awakeMinutes: 20, score: 93 },
  { date: "2026-02-05", totalHours: 7.0, deepMinutes: 88, remMinutes: 92, lightMinutes: 218, awakeMinutes: 22, score: 80 },
  { date: "2026-02-04", totalHours: 6.5, deepMinutes: 72, remMinutes: 80, lightMinutes: 208, awakeMinutes: 30, score: 68 },
];

// 2 weeks of workout history
const mockHistory: WorkoutHistory[] = [
  { id: "h1", date: "2026-02-10", name: "Lower Body Strength", type: "strength", duration: 62, volume: 18500, intensity: "high" },
  { id: "h2", date: "2026-02-08", name: "HIIT Conditioning", type: "hiit", duration: 30, volume: 0, intensity: "max" },
  { id: "h3", date: "2026-02-07", name: "Upper Body Hypertrophy", type: "strength", duration: 58, volume: 22400, intensity: "moderate" },
  { id: "h4", date: "2026-02-05", name: "Full Body Power", type: "strength", duration: 65, volume: 24000, intensity: "high" },
  { id: "h5", date: "2026-02-03", name: "Cardio + Core", type: "cardio", duration: 45, volume: 0, intensity: "moderate" },
  { id: "h6", date: "2026-02-01", name: "Push Day", type: "strength", duration: 52, volume: 19800, intensity: "high" },
  { id: "h7", date: "2026-01-31", name: "Pull Day", type: "strength", duration: 55, volume: 21000, intensity: "high" },
  { id: "h8", date: "2026-01-29", name: "Leg Day", type: "strength", duration: 60, volume: 26500, intensity: "high" },
  { id: "h9", date: "2026-01-28", name: "HIIT Sprint Intervals", type: "hiit", duration: 25, volume: 0, intensity: "max" },
  { id: "h10", date: "2026-01-27", name: "Mobility & Recovery", type: "mobility", duration: 35, volume: 0, intensity: "low" },
];

const mockPRs: PersonalRecord[] = [
  { exercise: "Bench Press", value: 225, unit: "lbs", date: "2026-01-28" },
  { exercise: "Squat", value: 315, unit: "lbs", date: "2026-02-01" },
  { exercise: "Deadlift", value: 365, unit: "lbs", date: "2026-01-15" },
  { exercise: "Mile Run", value: 6.45, unit: "min", date: "2026-02-05" },
  { exercise: "Pull-Ups", value: 18, unit: "reps", date: "2026-02-08" },
];

export const useAppStore = create<AppState>()(
  persist(
    (set, get) => ({
  hasHydrated: false,
  setHasHydrated: (val) => set({ hasHydrated: val }),

  isOnboarded: false,
  onboardingStep: 0,
  setOnboarded: (val) => set({ isOnboarded: val }),
  setOnboardingStep: (step) => set({ onboardingStep: Math.max(0, step) }),
  resetSession: () =>
    set({
      isOnboarded: false,
      onboardingStep: 0,
      activeTab: "home",
      chatMessages: [],
    }),
  seedAriaWelcome: () => {
    const profile = get().userProfile;
    const content = welcomeChatMessage({
      name: profile.name,
      goals: profile.fitnessGoals,
      experience: profile.experienceLevel,
      workouts: profile.preferredWorkouts,
      coachingStyle: profile.coachingStyle,
      devicesConnected: profile.connectedDevices.length,
    });
    const welcome: ChatMessage = {
      id: `aria-welcome-${Date.now()}`,
      role: "trainer",
      content,
      timestamp: new Date(),
    };
    set({ chatMessages: [welcome] });
  },

  userProfile: mockProfile,
  updateProfile: (profile) =>
    set((state) => ({
      userProfile: { ...state.userProfile, ...profile },
    })),

  readiness: mockReadiness,
  dailyMetrics: mockMetrics,
  todayWorkout: mockWorkout,

  activeWorkout: {
    isActive: false,
    currentExerciseIndex: 0,
    currentSet: 1,
    isResting: false,
    restTimeLeft: 0,
    elapsedTime: 0,
    currentHR: 72,
  },
  startWorkout: () =>
    set((state) => ({
      activeWorkout: {
        ...state.activeWorkout,
        isActive: true,
        currentExerciseIndex: 0,
        currentSet: 1,
        elapsedTime: 0,
        currentHR: 72,
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
    set((state) => ({
      activeWorkout: {
        ...state.activeWorkout,
        isActive: false,
      },
    })),

  chatMessages: [],
  addMessage: (msg) =>
    set((state) => ({ chatMessages: [...state.chatMessages, msg] })),

  sleepData: mockSleepData,
  workoutHistory: mockHistory,
  personalRecords: mockPRs,

  activeTab: "home",
  setActiveTab: (tab) => set({ activeTab: tab }),

  notificationPrefs: defaultNotificationPrefs,
  setNotificationPref: (key, value) =>
    set((state) => ({
      notificationPrefs: { ...state.notificationPrefs, [key]: value },
    })),
}),
    {
      name: "forge-web",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        isOnboarded: state.isOnboarded,
        onboardingStep: state.onboardingStep,
        userProfile: state.userProfile,
        activeTab: state.activeTab,
        notificationPrefs: state.notificationPrefs,
      }),
      onRehydrateStorage: () => (state) => {
        state?.setHasHydrated(true);
      },
    }
  )
);
