import { describe, expect, it } from "vitest";
import {
  ARIA_PAUSED_LINE,
  isAriaPaused,
  pausedFromHttp,
  pausedLineFor,
} from "./aria-paused";

describe("aria paused", () => {
  it("detects 503 aria_paused and the calm line", () => {
    expect(isAriaPaused(503, "aria_paused")).toBe(true);
    expect(isAriaPaused(503, null)).toBe(true);
    expect(isAriaPaused(200, "aria_paused")).toBe(false);
    expect(pausedFromHttp(503, '{"code":"aria_paused"}')).toBe(true);
    expect(pausedFromHttp(503, "")).toBe(true);
    expect(pausedFromHttp(500, '{"code":"aria_paused"}')).toBe(false);
    expect(ARIA_PAUSED_LINE.toLowerCase()).toContain("taking a break");
    expect(pausedLineFor("tutorial").toLowerCase()).toContain("skip");
    expect(pausedLineFor("onboarding").toLowerCase()).toContain("keep going");
    expect(pausedLineFor("switcher").toLowerCase()).toContain("taking a break");
  });
});
