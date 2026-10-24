import welcome from "../../shared/forge-welcome.json";

/**
 * Welcome / launch taglines. **Switch the live line by changing
 * `activeIndex` in `shared/forge-welcome.json` only.**
 *
 * Lockstep with iOS `ForgeWelcomeCopy`. Alternates stay compiled so a
 * swap is one integer, not a hunt through splash and onboarding call sites.
 */
export const FORGE_WELCOME = welcome;

export const FORGE_WELCOME_TAGLINES = FORGE_WELCOME.taglines;

export function forgeWelcomeTagline(): string {
  return FORGE_WELCOME.taglines[FORGE_WELCOME.activeIndex] ?? FORGE_WELCOME.taglines[0];
}
