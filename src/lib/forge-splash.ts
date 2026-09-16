/** Brand hold on the launch splash. Lockstep with `ForgeSplashTiming`. */
export const FORGE_SPLASH = {
  holdMs: 2450,
  reduceMotionHoldMs: 650,
  /** Returning users already know the brand — keep a beat, not a wait. */
  returningHoldMs: 900,
  returningReduceMotionHoldMs: 200,
  fadeMs: 380,
  brandFloorMs: 2000,
  freezeCeilingMs: 3100,
} as const;

export function forgeSplashHoldMs(
  reduceMotion: boolean,
  options?: { returning?: boolean }
): number {
  if (options?.returning) {
    return reduceMotion
      ? FORGE_SPLASH.returningReduceMotionHoldMs
      : FORGE_SPLASH.returningHoldMs;
  }
  return reduceMotion ? FORGE_SPLASH.reduceMotionHoldMs : FORGE_SPLASH.holdMs;
}

/** Sync peek so splash length can adapt before zustand rehydrates. */
export function peekPersistedOnboarded(): boolean {
  if (typeof window === "undefined") return false;
  try {
    const raw = window.localStorage.getItem("forge-web");
    if (!raw) return false;
    const parsed = JSON.parse(raw) as { state?: { isOnboarded?: boolean } };
    return Boolean(parsed?.state?.isOnboarded);
  } catch {
    return false;
  }
}
