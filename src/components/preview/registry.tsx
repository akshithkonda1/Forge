"use client";

import type { ReactNode } from "react";
import type { PreviewSlug } from "./catalog";
import { ChatScreen } from "./screens/chat";
import { HomeScreen } from "./screens/home";
import { LifestyleScreen } from "./screens/lifestyle";
import { MemoryScreen } from "./screens/memory";
import { OnboardingHealthScreen } from "./screens/onboarding-health";
import { OnboardingHowAreYouScreen } from "./screens/onboarding-how-are-you";
import { OnboardingMeetScreen } from "./screens/onboarding-meet";
import { SleepScreen } from "./screens/sleep";
import { StatsScreen } from "./screens/stats";
import { TrainScreen } from "./screens/train";
import { TutorialBeginnerScreen, TutorialCompetitorScreen } from "./screens/tutorial";

export const PREVIEW_SCREENS: Record<PreviewSlug, () => ReactNode> = {
  "onboarding-meet": () => <OnboardingMeetScreen />,
  "onboarding-health": () => <OnboardingHealthScreen />,
  "onboarding-how-are-you": () => <OnboardingHowAreYouScreen />,
  "tutorial-beginner": () => <TutorialBeginnerScreen />,
  "tutorial-competitor": () => <TutorialCompetitorScreen />,
  home: () => <HomeScreen />,
  lifestyle: () => <LifestyleScreen />,
  sleep: () => <SleepScreen />,
  stats: () => <StatsScreen />,
  chat: () => <ChatScreen />,
  memory: () => <MemoryScreen />,
  train: () => <TrainScreen />,
};
