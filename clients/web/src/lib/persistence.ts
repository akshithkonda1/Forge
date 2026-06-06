const ONBOARDED_KEY = "forge.isOnboarded";
const ONBOARDING_STEP_KEY = "forge.onboardingStep";

export const forgePersistence = {
  getIsOnboarded(): boolean {
    if (typeof window === "undefined") return false;
    return localStorage.getItem(ONBOARDED_KEY) === "true";
  },

  setIsOnboarded(value: boolean): void {
    if (typeof window === "undefined") return;
    localStorage.setItem(ONBOARDED_KEY, value ? "true" : "false");
    if (value) {
      localStorage.removeItem(ONBOARDING_STEP_KEY);
    }
  },

  getOnboardingStep(): number {
    if (typeof window === "undefined") return 0;
    const raw = localStorage.getItem(ONBOARDING_STEP_KEY);
    if (!raw) return 0;
    const step = Number.parseInt(raw, 10);
    return Number.isFinite(step) ? Math.max(0, Math.min(3, step)) : 0;
  },

  setOnboardingStep(step: number): void {
    if (typeof window === "undefined") return;
    localStorage.setItem(ONBOARDING_STEP_KEY, String(step));
  },

  reset(): void {
    if (typeof window === "undefined") return;
    localStorage.removeItem(ONBOARDED_KEY);
    localStorage.removeItem(ONBOARDING_STEP_KEY);
  },
};