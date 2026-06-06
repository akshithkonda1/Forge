import { create } from "zustand";
import { forgeAPI, mapARIAMessage } from "@/lib/forge-api";
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

interface AppState {
  // Onboarding
  isOnboarded: boolean;
  onboardingStep: number;
  setOnboarded: (val: boolean) => void;
  setOnboardingStep: (step: number) => void;

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
  activeTab: string;
  setActiveTab: (tab: string) => void;

  // API
  dataLoadState: "idle" | "loading" | "loaded" | "offline";
  isGeneratingResponse: boolean;
  loadDashboardFromAPI: () => Promise<void>;
  sendChatMessage: (text: string) => Promise<void>;
  completeOnboarding: () => Promise<void>;
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

// 15 realistic conversation exchanges showing the trainer's personality
const mockChatMessages: ChatMessage[] = [
  {
    id: "m1",
    role: "trainer",
    content: "Hey Akshith, welcome to Forge. I'm your AI training partner. I've synced up with your Apple Watch and Oura Ring \u2014 already pulling in your biometrics. Let's build something serious together.",
    timestamp: new Date(Date.now() - 86400000 * 2),
  },
  {
    id: "m2",
    role: "user",
    content: "Excited to get started. I've been training for about 2 years but feel like I've plateaued.",
    timestamp: new Date(Date.now() - 86400000 * 2 + 60000),
  },
  {
    id: "m3",
    role: "trainer",
    content: "Plateaus are normal \u2014 and breakable. Your training history shows solid consistency but your programming might need periodization. I'll structure progressive overload cycles and track your recovery so we push at the right times. First things first: let's establish your baseline this week.",
    timestamp: new Date(Date.now() - 86400000 * 2 + 120000),
  },
  {
    id: "m4",
    role: "user",
    content: "Sounds good. What should I focus on today?",
    timestamp: new Date(Date.now() - 86400000 + 30000),
  },
  {
    id: "m5",
    role: "trainer",
    content: "Yesterday was a rest day and your HRV bounced back nicely \u2014 48ms up to 52ms. Deep sleep hit 1hr 42min which is solid for recovery. I'd say you're primed for a strength session. How about lower body? Your squat has been progressing well.",
    timestamp: new Date(Date.now() - 86400000 + 90000),
  },
  {
    id: "m6",
    role: "user",
    content: "Actually I'm a bit sore from the hike over the weekend. Can we do upper body instead?",
    timestamp: new Date(Date.now() - 86400000 + 150000),
  },
  {
    id: "m7",
    role: "trainer",
    content: "Smart call \u2014 listening to your body is part of the game. I'll slot in Upper Body Power today and shift legs to Wednesday when you'll be fully recovered. Your bench has been stuck at 225 \u2014 today we're going to attack that with heavy triples and back-off sets.",
    timestamp: new Date(Date.now() - 86400000 + 210000),
  },
  {
    id: "m8",
    role: "user",
    content: "Let's do it. Also, I've been waking up at like 3am lately. Any idea why?",
    timestamp: new Date(Date.now() - 86400000 + 270000),
  },
  {
    id: "m9",
    role: "trainer",
    content: "I noticed that in your Oura data \u2014 you've had 3 wake-ups between 2-4am this week. A few things could cause this: cortisol spikes from late training, screen time before bed, or caffeine after 2pm. Your deep sleep is still decent but your awake time has crept up 40% this week. Try cutting screens 45 min before bed and see if it helps. I'll track the trend.",
    timestamp: new Date(Date.now() - 86400000 + 330000),
  },
  {
    id: "m10",
    role: "user",
    content: "Good catch. I have been scrolling before bed more lately.",
    timestamp: new Date(Date.now() - 86400000 + 390000),
  },
  {
    id: "m11",
    role: "trainer",
    content: "There it is. Small habit, big impact on recovery. Your muscles literally rebuild during deep sleep \u2014 protecting that window is as important as the workout itself. I'll check in on this next week to see if the numbers improve.",
    timestamp: new Date(Date.now() - 86400000 + 450000),
  },
  {
    id: "m12",
    role: "trainer",
    content: "Morning Akshith! Your deep sleep was solid last night \u2014 1hr 42min. HRV is up 12% from yesterday. You're primed for a heavy session today. Ready to hit upper body? \ud83d\udcaa",
    timestamp: new Date(Date.now() - 3600000),
  },
  {
    id: "m13",
    role: "user",
    content: "Yeah I'm feeling good today. What's the plan?",
    timestamp: new Date(Date.now() - 3500000),
  },
  {
    id: "m14",
    role: "trainer",
    content: "Love the energy. I've got an Upper Body Power session lined up \u2014 bench press, weighted pull-ups, OHP, rows. About 55 minutes, high intensity. Your recovery metrics say you can handle it. Want me to break down the full workout?",
    timestamp: new Date(Date.now() - 3400000),
    richCard: {
      type: "workout-plan",
      data: {
        name: "Upper Body Power",
        duration: 55,
        exercises: [
          { name: "Barbell Bench Press", sets: 4, reps: "6-8" },
          { name: "Weighted Pull-Ups", sets: 4, reps: "6-8" },
          { name: "Overhead Press", sets: 3, reps: "8-10" },
          { name: "Barbell Rows", sets: 3, reps: "8-10" },
          { name: "Incline DB Press", sets: 3, reps: "10-12" },
          { name: "Face Pulls", sets: 3, reps: "15-20" },
        ],
      },
    },
  },
  {
    id: "m15",
    role: "user",
    content: "Looks perfect. Let's go!",
    timestamp: new Date(Date.now() - 3300000),
  },
];

// 14 days of sleep data (newest first)
const mockSleepData: SleepData[] = [
  { date: "2026-02-10", totalHours: 7.2, deepMinutes: 102, remMinutes: 95, lightMinutes: 215, awakeMinutes: 20, score: 88 },
  { date: "2026-02-09", totalHours: 6.8, deepMinutes: 78, remMinutes: 88, lightMinutes: 225, awakeMinutes: 17, score: 74 },
  { date: "2026-02-08", totalHours: 7.5, deepMinutes: 110, remMinutes: 100, lightMinutes: 220, awakeMinutes: 20, score: 91 },
  { date: "2026-02-07", totalHours: 6.2, deepMinutes: 65, remMinutes: 72, lightMinutes: 210, awakeMinutes: 25, score: 62 },
  { date: "2026-02-06", totalHours: 7.8, deepMinutes: 115, remMinutes: 105, lightMinutes: 228, awakeMinutes: 20, score: 93 },
  { date: "2026-02-05", totalHours: 7.0, deepMinutes: 88, remMinutes: 92, lightMinutes: 218, awakeMinutes: 22, score: 80 },
  { date: "2026-02-04", totalHours: 6.5, deepMinutes: 72, remMinutes: 80, lightMinutes: 208, awakeMinutes: 30, score: 68 },
  { date: "2026-02-03", totalHours: 7.4, deepMinutes: 98, remMinutes: 96, lightMinutes: 222, awakeMinutes: 18, score: 85 },
  { date: "2026-02-02", totalHours: 6.9, deepMinutes: 82, remMinutes: 84, lightMinutes: 216, awakeMinutes: 32, score: 70 },
  { date: "2026-02-01", totalHours: 7.6, deepMinutes: 108, remMinutes: 102, lightMinutes: 224, awakeMinutes: 22, score: 90 },
  { date: "2026-01-31", totalHours: 5.8, deepMinutes: 55, remMinutes: 65, lightMinutes: 195, awakeMinutes: 33, score: 55 },
  { date: "2026-01-30", totalHours: 7.1, deepMinutes: 95, remMinutes: 90, lightMinutes: 218, awakeMinutes: 23, score: 82 },
  { date: "2026-01-29", totalHours: 7.3, deepMinutes: 100, remMinutes: 94, lightMinutes: 220, awakeMinutes: 24, score: 84 },
  { date: "2026-01-28", totalHours: 6.6, deepMinutes: 70, remMinutes: 78, lightMinutes: 212, awakeMinutes: 36, score: 65 },
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

export const useAppStore = create<AppState>((set) => ({
  isOnboarded: false,
  onboardingStep: 0,
  setOnboarded: (val) => set({ isOnboarded: val }),
  setOnboardingStep: (step) => set({ onboardingStep: step }),

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

  chatMessages: mockChatMessages,
  addMessage: (msg) =>
    set((state) => ({ chatMessages: [...state.chatMessages, msg] })),

  sleepData: mockSleepData,
  workoutHistory: mockHistory,
  personalRecords: mockPRs,

  activeTab: "home",
  setActiveTab: (tab) => set({ activeTab: tab }),

  dataLoadState: "idle",
  isGeneratingResponse: false,

  loadDashboardFromAPI: async () => {
    set({ dataLoadState: "loading" });
    try {
      const dashboard = await forgeAPI.getDashboardToday();
      set({
        userProfile: dashboard.profile,
        readiness: dashboard.readiness,
        dailyMetrics: dashboard.dailyMetrics,
        todayWorkout: dashboard.todayWorkout,
        sleepData: dashboard.recentSleep,
        workoutHistory: dashboard.recentWorkouts,
        personalRecords: dashboard.personalRecords,
        dataLoadState: "loaded",
      });
    } catch (error) {
      console.warn("Forge API unavailable, using offline data", error);
      set({
        chatMessages: mockChatMessages,
        sleepData: mockSleepData,
        workoutHistory: mockHistory,
        personalRecords: mockPRs,
        dataLoadState: "offline",
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
      console.warn("ARIA API failed, no trainer response", error);
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
    const profile = useAppStore.getState().userProfile;
    set({ isOnboarded: true });
    try {
      await forgeAPI.updateProfile(profile);
    } catch (error) {
      console.warn("Failed to persist profile", error);
    }
  },
}));
