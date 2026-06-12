"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import * as api from "@/lib/api/endpoints";
import type { WorkoutLogInput } from "@/lib/api/endpoints";
import { useForgeAuth } from "@/lib/auth/use-forge-auth";
import type { UserProfile } from "@/types";

// Query hooks ---------------------------------------------------------------

export function useDashboard() {
  const { idToken, isAuthenticated } = useForgeAuth();
  return useQuery({
    queryKey: ["dashboard", "today"],
    queryFn: () => api.getDashboardToday(idToken),
    enabled: isAuthenticated,
  });
}

export function useSleep(days = 14) {
  const { idToken, isAuthenticated } = useForgeAuth();
  return useQuery({
    queryKey: ["sleep", days],
    queryFn: () => api.getSleep(idToken, days),
    enabled: isAuthenticated,
  });
}

export function useWorkoutHistory(days = 30) {
  const { idToken, isAuthenticated } = useForgeAuth();
  return useQuery({
    queryKey: ["workouts", "history", days],
    queryFn: () => api.getWorkoutHistory(idToken, days),
    enabled: isAuthenticated,
  });
}

export function useChatThread() {
  const { idToken, isAuthenticated } = useForgeAuth();
  return useQuery({
    queryKey: ["chat", "current"],
    queryFn: () => api.getChatThread(idToken),
    enabled: isAuthenticated,
  });
}

export function useProgressSummary(days = 30) {
  const { idToken, isAuthenticated } = useForgeAuth();
  return useQuery({
    queryKey: ["progress", "summary", days],
    queryFn: () => api.getProgressSummary(idToken, days),
    enabled: isAuthenticated,
  });
}

// Mutation hooks ------------------------------------------------------------

export function useUpdateProfile() {
  const { idToken } = useForgeAuth();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (profile: Partial<UserProfile>) => api.updateProfile(idToken, profile),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["me"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard"] });
    },
  });
}

export function useSendChatMessage() {
  const { idToken } = useForgeAuth();
  return useMutation({
    mutationFn: (content: string) => api.sendChatMessage(idToken, content),
  });
}

export function usePostWorkoutLog() {
  const { idToken } = useForgeAuth();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (workout: WorkoutLogInput) => api.postWorkoutLog(idToken, workout),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workouts"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard"] });
    },
  });
}
