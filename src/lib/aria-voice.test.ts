import { describe, expect, it } from "vitest";

import {
  ARIA_VOICE_ARIA_PRESET,
  ARIA_VOICE_CANARY_EMAIL,
  ARIA_VOICE_CANARY_NAME,
  ARIA_VOICE_DEFAULT_MODEL,
  ARIA_VOICE_LICENSE,
  ARIA_VOICE_RECIPES,
  ARIA_VOICE_STARTER_BUNDLE_MB,
  applyVoiceProfile,
  featuredLabelsAvoidTrademarkedNames,
  resolveVoiceMouth,
  sanitizeTTSText,
  speakRequestBody,
} from "./aria-voice";

describe("ARIA voice catalog", () => {
  it("defaults to Kokoro-82M and the ARIA af_heart preset", () => {
    expect(ARIA_VOICE_DEFAULT_MODEL).toBe("kokoro-82m");
    expect(ARIA_VOICE_ARIA_PRESET).toBe("af_heart");
    expect(ARIA_VOICE_LICENSE).toBe("Apache-2.0");
    expect(ARIA_VOICE_STARTER_BUNDLE_MB).toBe(210);
    expect(ARIA_VOICE_RECIPES[0].voiceId).toBe("af_heart");
  });

  it("always selects Kokoro, including Dummy and when cloud flags are on", () => {
    expect(resolveVoiceMouth({ fishEnabled: true, fishConfigured: true })).toBe(
      "kokoro"
    );
    expect(
      resolveVoiceMouth({
        fishEnabled: true,
        fishConfigured: true,
        fishBusy: true,
        pollyEnabled: true,
        pollyConfigured: true,
      })
    ).toBe("kokoro");
    expect(
      resolveVoiceMouth({ dummy: true, fishEnabled: true, fishConfigured: true })
    ).toBe("kokoro");
    expect(
      resolveVoiceMouth({
        offline: true,
        elevenLabsEnabled: true,
      })
    ).toBe("kokoro");
  });

  it("blocks canary name and health values from any cloud TTS payload", () => {
    const dirty = sanitizeTTSText(
      `${ARIA_VOICE_CANARY_NAME} ${ARIA_VOICE_CANARY_EMAIL} HRV 32 readiness 88`,
      [ARIA_VOICE_CANARY_NAME]
    );
    expect(dirty.safe).toBe(false);
    expect(dirty.text).not.toContain(ARIA_VOICE_CANARY_NAME);
    expect(sanitizeTTSText("I'm ARIA.").safe).toBe(true);
  });

  it("keeps featured labels free of trademarked characters", () => {
    expect(featuredLabelsAvoidTrademarkedNames()).toBe(true);
    expect(ARIA_VOICE_RECIPES.some((row) => /toph/i.test(row.label))).toBe(false);
  });

  it("switching profile changes the next local Kokoro voice id", () => {
    const warm = ARIA_VOICE_RECIPES[0];
    const ember = ARIA_VOICE_RECIPES[4];
    let selection = applyVoiceProfile({}, warm);
    const first = speakRequestBody("I'm ARIA.", selection);
    expect(first.voice_id).toBe("af_heart");
    expect(first.profile_id).toBe("warm");
    expect(first.text).toBeUndefined();

    selection = applyVoiceProfile(selection, ember);
    const next = speakRequestBody("I'm ARIA.", selection);
    expect(next.voice_id).toBe("af_bella");
    expect(next.profile_id).toBe("ember");
    expect(next.voice_id).not.toBe(first.voice_id);
  });
});
