import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import {
  containsBannedPhrase,
  DESIGN,
  tokenHex,
  TYPE_ROLES,
  UX,
} from "@/lib/design-tokens";

describe("shared design tokens", () => {
  it("stays lockstep with shared/design-tokens.json", () => {
    const file = JSON.parse(readFileSync("shared/design-tokens.json", "utf8"));
    expect(DESIGN).toEqual(file);
    expect(DESIGN.mixLock).toBe("home-is-source");
    expect(DESIGN.motion.eventOnly).toBe(true);
    expect(DESIGN.motion.liveGlowDefault).toBe(false);
    expect(DESIGN.motion.maxTickHz).toBeLessThanOrEqual(12);
  });

  it("names one type scale with tabular metrics", () => {
    expect(Object.keys(TYPE_ROLES)).toEqual([
      "display",
      "title",
      "headline",
      "body",
      "caption",
      "metric",
    ]);
    expect(TYPE_ROLES.metric.tabular).toBe(true);
    expect(TYPE_ROLES.display.design).toBe("rounded");
    expect(TYPE_ROLES.body.design).toBe("default");
  });

  it("keeps Home palette and steel miss states", () => {
    expect(tokenHex("background")).toBe("#08080C");
    expect(tokenHex("ember")).toBe("#FF4D00");
    expect(tokenHex("steel")).toBe("#5B8DEF");
    expect(tokenHex("miss")).toBe("#7BA6F7");
    expect(tokenHex("miss")).not.toBe("#EF4444");
    expect(tokenHex("plate")).toBe("#7EC8FF");
  });

  it("locks UX tap, CTA, and copy voice", () => {
    expect(UX.minTap).toBe(44);
    expect(UX.onePrimaryCTA).toBe(true);
    expect(UX.permissionSkip).toBe("always-visible");
    expect(DESIGN.copy.neverExpandARIA).toBe(true);
    expect(DESIGN.copy.ariaRole).toBe("lifestyle coach");
    expect(containsBannedPhrase("Adaptive Recovery Interactive Assistant")).toBe(
      "Adaptive Recovery",
    );
    expect(containsBannedPhrase("recovery week")).toBe("recovery week");
    expect(containsBannedPhrase("Do this now")).toBeUndefined();
  });
});
