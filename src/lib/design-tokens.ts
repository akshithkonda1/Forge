import tokens from "../../shared/design-tokens.json";

/** Shared Forge chrome — lockstep with `shared/design-tokens.json`. */
export const DESIGN = tokens;

export function tokenHex(key: keyof typeof DESIGN.color): string {
  return `#${DESIGN.color[key]}`;
}

export const TYPE_ROLES = DESIGN.type.roles;

export const UX = DESIGN.ux;

export function containsBannedPhrase(line: string): string | undefined {
  const lower = line.toLowerCase();
  return DESIGN.copy.bannedPhrases.find((phrase) => lower.includes(phrase.toLowerCase()));
}
