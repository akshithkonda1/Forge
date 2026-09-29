import { describe, expect, it } from "vitest";

import { ARIA_TONES, resolveCoachingStyle } from "@/lib/aria-companion";

describe("resolveCoachingStyle", () => {
  it("returns known styles unchanged", () => {
    expect(resolveCoachingStyle("push-hard")).toBe("push-hard");
    expect(resolveCoachingStyle("data-driven")).toBe("data-driven");
  });

  it("falls back to balanced when persist hands back a stale or empty style", () => {
    expect(resolveCoachingStyle("typo")).toBe("balanced");
    expect(resolveCoachingStyle(null)).toBe("balanced");
    expect(resolveCoachingStyle(undefined)).toBe("balanced");
    expect(resolveCoachingStyle("")).toBe("balanced");
    expect(ARIA_TONES[resolveCoachingStyle("legacy-coach")].title).toBe("Check-in");
  });
});
