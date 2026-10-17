"use client";

import { TUTORIAL } from "../copy";
import { HomeScreen } from "./home";

export function TutorialBeginnerScreen() {
  return (
    <HomeScreen
      overlay={{
        prompt: TUTORIAL.beginner.welcome,
        gotIt: TUTORIAL.gotIt,
        skip: TUTORIAL.skip,
      }}
    />
  );
}

export function TutorialCompetitorScreen() {
  return (
    <HomeScreen
      overlay={{
        prompt: TUTORIAL.competitor.welcome,
        gotIt: TUTORIAL.gotIt,
        skip: TUTORIAL.skip,
      }}
    />
  );
}
