import type { CoachingStyle } from "@/types";

/** Friend-first tone. Same four CoachingStyle ids as iOS / api-contracts. */
export const ARIA_TONE_ORDER: CoachingStyle[] = [
  "balanced",
  "patient",
  "data-driven",
  "push-hard",
];

export const ARIA_TONES: Record<
  CoachingStyle,
  { title: string; line: string }
> = {
  balanced: {
    title: "Check-in",
    line: "I'll check in — trainer flavor when you want it, friend first.",
  },
  patient: {
    title: "Space",
    line: "I'll give you space and still be here.",
  },
  "data-driven": {
    title: "Patterns",
    line: "I'll notice patterns with you — not to judge.",
  },
  "push-hard": {
    title: "Honest peer",
    line: "I'll be an honest peer. Kind, and I won't flinch.",
  },
};
