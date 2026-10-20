export const ARIA_VOICE_SPEAK_PATH = "/ai/voice/speak";
export const ARIA_VOICE_CATALOG_PATH = "/ai/voice";
export const ARIA_VOICE_DEFAULT_MODEL = "s2.1-pro-free";
export const ARIA_VOICE_PAID_MODEL = "s2.1-pro";
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
