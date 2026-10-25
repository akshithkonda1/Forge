export const ARIA_VOICE_CATALOG_PATH = "/ai/voice";
export const ARIA_VOICE_DEFAULT_MODEL = "kokoro-82m";
export const ARIA_VOICE_ARIA_PRESET = "af_heart";
export const ARIA_VOICE_LICENSE = "Apache-2.0";
export const ARIA_VOICE_PACKAGE = "mattmireles/kokoro-coreml";
export const ARIA_VOICE_WEIGHTS = "hexgrad/Kokoro-82M";
export const ARIA_VOICE_STARTER_BUNDLE_MB = 210;
export const ARIA_VOICE_CANARY_NAME = "AkshithKondaCanary";
export const ARIA_VOICE_CANARY_EMAIL = "akshith.canary@forge.test";

export type AriaVoiceMouth = "kokoro";

export function resolveVoiceMouth(_opts?: {
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
  return "kokoro";
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
export const ARIA_VOICE_BUSY_MESSAGE =
  "Voice could not load. The text reply is shown.";

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
    voiceId: "af_heart",
  },
  {
    id: "calm",
    label: "Calm",
    description: "Even, low, a man who is not in a hurry.",
    speed: 0.95,
    voiceId: "am_michael",
  },
  {
    id: "neutral",
    label: "Neutral",
    description: "Clear and even. Not styled as a man or a woman.",
    speed: 1,
    voiceId: "af_sarah",
  },
  {
    id: "spark",
    label: "Spark",
    description: "Brighter and a little faster. Still a coach, not a bit.",
    speed: 1.08,
    voiceId: "af_aoede",
  },
  {
    id: "ember",
    label: "Ember",
    description:
      "Blunt, gruff, confident. A young tomboy coach — original voice, not a character impression.",
    speed: 1.05,
    voiceId: "af_bella",
  },
];

export function applyVoiceProfile(
  selection: AriaVoiceSelection,
  profile: AriaVoiceProfile
): AriaVoiceSelection {
  return {
    profileId: profile.id,
    voiceId: profile.voiceId ?? selection.voiceId ?? ARIA_VOICE_ARIA_PRESET,
    speed: profile.speed,
  };
}

/** Next local Kokoro selection. Hex never receives the spoken line. */
export function speakRequestBody(
  text: string,
  selection: AriaVoiceSelection,
  preview = false
): Record<string, unknown> {
  void text;
  void preview;
  const body: Record<string, unknown> = {
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
