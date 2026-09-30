import { afterEach, describe, expect, it } from "vitest";

import { useAppStore } from "@/stores/useAppStore";

describe("useAppStore onboarding step", () => {
  afterEach(() => {
    useAppStore.getState().setOnboardingStep(0);
  });

  it("clamps setOnboardingStep to the 0–3 flow", () => {
    useAppStore.getState().setOnboardingStep(9);
    expect(useAppStore.getState().onboardingStep).toBe(3);

    useAppStore.getState().setOnboardingStep(-4);
    expect(useAppStore.getState().onboardingStep).toBe(0);

    useAppStore.getState().setOnboardingStep(2);
    expect(useAppStore.getState().onboardingStep).toBe(2);
  });
});
