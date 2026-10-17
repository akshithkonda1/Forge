export const ARIA_PAUSED_CODE = "aria_paused";
export const ARIA_PAUSED_STATUS = 503;
export const ARIA_PAUSED_LINE = "ARIA is taking a break.";
export const ARIA_PAUSED_TUTORIAL_LINE =
  "ARIA is taking a break. You can keep walking the app, or Skip.";
export const ARIA_PAUSED_ONBOARDING_LINE =
  "ARIA is taking a break. You can keep going, or Skip — the rest of Forge still works.";
export const ARIA_PAUSED_SWITCHER_LINE =
  "ARIA is taking a break. Personality will apply on the next reply.";

export function isAriaPaused(status: number, code?: string | null): boolean {
  if (status !== ARIA_PAUSED_STATUS) return false;
  return code == null || code === "" || code === ARIA_PAUSED_CODE;
}

export function pausedLineFor(surface: "chat" | "tutorial" | "onboarding" | "switcher"): string {
  switch (surface) {
    case "tutorial":
      return ARIA_PAUSED_TUTORIAL_LINE;
    case "onboarding":
      return ARIA_PAUSED_ONBOARDING_LINE;
    case "switcher":
      return ARIA_PAUSED_SWITCHER_LINE;
    default:
      return ARIA_PAUSED_LINE;
  }
}
