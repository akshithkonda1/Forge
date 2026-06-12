"use client";

import { useEffect } from "react";
import { useDashboard, useSleep, useWorkoutHistory, useChatThread } from "@/lib/api/hooks";
import { useAppStore } from "@/stores/useAppStore";

function FullScreen({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-[100dvh] items-center justify-center bg-background px-6 text-center">
      {children}
    </div>
  );
}

/**
 * Fetches the user's data once at the app root and pushes it into the Zustand
 * store, so the existing leaf components keep reading from the store unchanged.
 * Renders children only after the first successful load.
 */
export function DataLoader({ children }: { children: React.ReactNode }) {
  const dashboard = useDashboard();
  const sleep = useSleep(14);
  const history = useWorkoutHistory(30);
  const chat = useChatThread();
  const hydrateFromServer = useAppStore((s) => s.hydrateFromServer);

  const ready = Boolean(dashboard.data && sleep.data && history.data && chat.data);
  const error = dashboard.error ?? sleep.error ?? history.error ?? chat.error;

  useEffect(() => {
    if (dashboard.data && sleep.data && history.data && chat.data) {
      hydrateFromServer({
        userProfile: dashboard.data.profile,
        readiness: dashboard.data.readiness,
        dailyMetrics: dashboard.data.dailyMetrics,
        todayWorkout: dashboard.data.todayWorkout,
        personalRecords: dashboard.data.personalRecords,
        sleepData: sleep.data.sleep,
        workoutHistory: history.data.workouts,
        chatMessages: chat.data.messages,
      });
    }
  }, [dashboard.data, sleep.data, history.data, chat.data, hydrateFromServer]);

  if (error && !ready) {
    return (
      <FullScreen>
        <div className="flex flex-col items-center gap-3">
          <p className="text-sm text-red-400">Couldn’t load your data.</p>
          <p className="max-w-xs text-xs text-text-tertiary">{(error as Error).message}</p>
          <button
            onClick={() => {
              dashboard.refetch();
              sleep.refetch();
              history.refetch();
              chat.refetch();
            }}
            className="mt-1 rounded-full bg-ember px-4 py-2 text-sm text-white"
          >
            Retry
          </button>
        </div>
      </FullScreen>
    );
  }

  if (!ready) {
    return (
      <FullScreen>
        <div className="flex flex-col items-center gap-3 text-text-tertiary">
          <div className="h-6 w-6 animate-spin rounded-full border-2 border-text-tertiary border-t-ember" />
          <p className="text-sm">Loading your training data…</p>
        </div>
      </FullScreen>
    );
  }

  return <>{children}</>;
}
