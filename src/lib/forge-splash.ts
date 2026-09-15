/** Brand hold on the launch splash. Lockstep with `ForgeSplashTiming`. */
export const FORGE_SPLASH = {
  holdMs: 2450,
  reduceMotionHoldMs: 650,
  fadeMs: 380,
  brandFloorMs: 2000,
  freezeCeilingMs: 3100,
} as const;

export function forgeSplashHoldMs(reduceMotion: boolean): number {
  return reduceMotion ? FORGE_SPLASH.reduceMotionHoldMs : FORGE_SPLASH.holdMs;
}
