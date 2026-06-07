const ONBOARDED_KEY = "forge.isOnboarded";
const ONBOARDING_STEP_KEY = "forge.onboardingStep";
const AUTH_ID_TOKEN_KEY = "forge.auth.idToken";
const AUTH_ACCESS_TOKEN_KEY = "forge.auth.accessToken";
const AUTH_REFRESH_TOKEN_KEY = "forge.auth.refreshToken";

export interface StoredAuthTokens {
  idToken: string | null;
  accessToken: string | null;
  refreshToken: string | null;
}

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

  getAuthTokens(): StoredAuthTokens {
    if (typeof window === "undefined") {
      return { idToken: null, accessToken: null, refreshToken: null };
    }
    return {
      idToken: localStorage.getItem(AUTH_ID_TOKEN_KEY),
      accessToken: localStorage.getItem(AUTH_ACCESS_TOKEN_KEY),
      refreshToken: localStorage.getItem(AUTH_REFRESH_TOKEN_KEY),
    };
  },

  setAuthTokens(tokens: StoredAuthTokens): void {
    if (typeof window === "undefined") return;
    if (tokens.idToken) {
      localStorage.setItem(AUTH_ID_TOKEN_KEY, tokens.idToken);
    } else {
      localStorage.removeItem(AUTH_ID_TOKEN_KEY);
    }
    if (tokens.accessToken) {
      localStorage.setItem(AUTH_ACCESS_TOKEN_KEY, tokens.accessToken);
    } else {
      localStorage.removeItem(AUTH_ACCESS_TOKEN_KEY);
    }
    if (tokens.refreshToken) {
      localStorage.setItem(AUTH_REFRESH_TOKEN_KEY, tokens.refreshToken);
    } else {
      localStorage.removeItem(AUTH_REFRESH_TOKEN_KEY);
    }
  },

  clearAuthTokens(): void {
    if (typeof window === "undefined") return;
    localStorage.removeItem(AUTH_ID_TOKEN_KEY);
    localStorage.removeItem(AUTH_ACCESS_TOKEN_KEY);
    localStorage.removeItem(AUTH_REFRESH_TOKEN_KEY);
  },

  reset(): void {
    if (typeof window === "undefined") return;
    localStorage.removeItem(ONBOARDED_KEY);
    localStorage.removeItem(ONBOARDING_STEP_KEY);
    this.clearAuthTokens();
  },
};