"use client";

import { useLayoutEffect } from "react";
import { useAppStore } from "@/stores/useAppStore";
import { SAMPLE_PERSON } from "./copy";

/** Seed the live store with SAMPLE fixtures so reused screens read real data. */
export function PreviewSeed() {
  useLayoutEffect(() => {
    useAppStore.setState({
      hasHydrated: true,
      isOnboarded: true,
      hasMetAria: true,
      onboardingStep: 3,
      userProfile: {
        ...useAppStore.getState().userProfile,
        name: SAMPLE_PERSON,
        experienceLevel: "intermediate",
        fitnessGoals: ["build-muscle"],
        preferredWorkouts: ["strength"],
        coachingStyle: "balanced",
        connectedDevices: ["apple-watch"],
        weeklySchedule: [1, 3, 5],
      },
    });
  }, []);
  return null;
}
