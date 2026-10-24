export const ARIA_VOICE_SPEAK_PATH = "/ai/voice/speak";
export const ARIA_VOICE_CATALOG_PATH = "/ai/voice";
export const ARIA_VOICE_DEFAULT_MODEL = "s2.1-pro-free";
export const ARIA_VOICE_PAID_MODEL = "s2.1-pro";
export const ARIA_VOICE_FREE_PROMO_ENDS = "2026-11-30";
export const ARIA_VOICE_CANARY_NAME = "AkshithKondaCanary";
export const ARIA_VOICE_CANARY_EMAIL = "akshith.canary@forge.test";

export type AriaVoiceMouth = "fish" | "polly" | "on_device" | "elevenlabs";

export function resolveVoiceMouth(opts: {
  dummy?: boolean;
  offline?: boolean;
  privacyOk?: boolean;
  quotaOk?: boolean;
  fishEnabled?: boolean;
  fishConfigured?: boolean;
  fishFailed?: boolean;
  fishBusy?: boolean;
  fishPromoExpired?: boolean;
  pollyEnabled?: boolean;
  pollyConfigured?: boolean;
  elevenLabsEnabled?: boolean;
}): AriaVoiceMouth {
  if (opts.dummy || opts.offline) return "on_device";
  if (opts.privacyOk === false || opts.quotaOk === false) return "on_device";
  const fishBlocked = Boolean(
    opts.fishFailed || opts.fishBusy || opts.fishPromoExpired
  );
  if (opts.fishEnabled && opts.fishConfigured && !fishBlocked) return "fish";
  if (fishBlocked && opts.pollyEnabled && opts.pollyConfigured) return "polly";
  return "on_device";
}

export function sanitizeTTSText(
  text: string,
  names: string[] = []
): { text: string; safe: boolean; reason?: string } {
  const line = text.trim();
  if (!line) return { text: "", safe: false, reason: "privacy" };
  const lower = line.toLowerCase();
  const blocked =
    line.includes("@") ||
    (lower.includes("hrv") && /\d/.test(line)) ||
    (lower.includes("readiness") && /\d/.test(line)) ||
    lower.includes("bpm") ||
    names.some((name) => name && lower.includes(name.toLowerCase())) ||
    lower.includes(ARIA_VOICE_CANARY_NAME.toLowerCase()) ||
    lower.includes(ARIA_VOICE_CANARY_EMAIL.toLowerCase());
  if (blocked) return { text: "", safe: false, reason: "privacy" };
  return { text: line, safe: true };
}
export const ARIA_VOICE_PREVIEW_TEXT =
  "I'm ARIA. Let's look at how you actually slept and what that means for training today. One next move, not a new identity.";
export const ARIA_VOICE_BUSY_MESSAGE = "Voice is busy. The text reply is shown.";

export const ARIA_VOICE_FEATURED_IDS = [
  "warm",
  "calm",
  "neutral",
  "spark",
  "ember",
] as const;

export type AriaVoiceFeaturedId = (typeof ARIA_VOICE_FEATURED_IDS)[number];

export type AriaVoiceSelection = {
  profileId?: string | null;
  voiceId?: string | null;
  speed?: number;
};

export type AriaVoiceProfile = {
  id: string;
  label: string;
  description: string;
  speed: number;
  voiceId?: string | null;
};

export const ARIA_VOICE_RECIPES: AriaVoiceProfile[] = [
  {
    id: "warm",
    label: "Warm",
    description: "Close, unhurried, a woman in the room.",
    speed: 1,
  },
  {
    id: "calm",
    label: "Calm",
    description: "Even, low, a man who is not in a hurry.",
    speed: 0.95,
  },
  {
    id: "neutral",
    label: "Neutral",
    description: "Clear and even. Not styled as a man or a woman.",
    speed: 1,
  },
  {
    id: "spark",
    label: "Spark",
    description: "Brighter and a little faster. Still a coach, not a bit.",
    speed: 1.08,
  },
  {
    id: "ember",
    label: "Ember",
    description:
      "Blunt, gruff, confident. A young tomboy coach — original voice, not a character impression.",
    speed: 1.05,
  },
];

export function applyVoiceProfile(
  selection: AriaVoiceSelection,
  profile: AriaVoiceProfile
): AriaVoiceSelection {
  return {
    profileId: profile.id,
    voiceId: profile.voiceId ?? selection.voiceId ?? null,
    speed: profile.speed,
  };
}

/** Next POST /ai/voice/speak body. Switching the profile changes voice_id. */
export function speakRequestBody(
  text: string,
  selection: AriaVoiceSelection,
  preview = false
): Record<string, unknown> {
  const body: Record<string, unknown> = {
    text,
    preview,
    speed: selection.speed ?? 1,
  };
  if (selection.profileId) body.profile_id = selection.profileId;
  if (selection.voiceId) body.voice_id = selection.voiceId;
  return body;
}

export function featuredLabelsAvoidTrademarkedNames(
  profiles: AriaVoiceProfile[] = ARIA_VOICE_RECIPES
): boolean {
  const banned = ["toph", "aang", "katara", "zuko", "avatar", "korra"];
  const blob = profiles
    .map((row) => `${row.id} ${row.label} ${row.description}`)
    .join(" ")
    .toLowerCase();
  return banned.every((token) => !blob.includes(token));
}
