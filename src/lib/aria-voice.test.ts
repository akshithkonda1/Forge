import { describe, expect, it } from "vitest";

import {
  ARIA_VOICE_DEFAULT_MODEL,
  ARIA_VOICE_PAID_MODEL,
  ARIA_VOICE_RECIPES,
  applyVoiceProfile,
  featuredLabelsAvoidTrademarkedNames,
  speakRequestBody,
} from "./aria-voice";

describe("ARIA voice catalog", () => {
  it("defaults to s2.1-pro-free and never names s1", () => {
    expect(ARIA_VOICE_DEFAULT_MODEL).toBe("s2.1-pro-free");
    expect(ARIA_VOICE_PAID_MODEL).toBe("s2.1-pro");
  });

  it("keeps featured labels free of trademarked characters", () => {
    expect(featuredLabelsAvoidTrademarkedNames()).toBe(true);
    expect(ARIA_VOICE_RECIPES.some((row) => /toph/i.test(row.label))).toBe(false);
  });

  it("switching profile changes the next speak request voice id", () => {
    const warm = { ...ARIA_VOICE_RECIPES[0], voiceId: "voice-warm-1" };
    const ember = { ...ARIA_VOICE_RECIPES[4], voiceId: "voice-ember-1" };
    let selection = applyVoiceProfile({}, warm);
    const first = speakRequestBody("I'm ARIA.", selection);
    expect(first.voice_id).toBe("voice-warm-1");
    expect(first.profile_id).toBe("warm");

    selection = applyVoiceProfile(selection, ember);
    const next = speakRequestBody("I'm ARIA.", selection);
    expect(next.voice_id).toBe("voice-ember-1");
    expect(next.profile_id).toBe("ember");
    expect(next.voice_id).not.toBe(first.voice_id);
  });
});
