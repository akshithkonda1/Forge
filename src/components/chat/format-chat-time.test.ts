import { describe, expect, it } from "vitest";

import { formatChatTime } from "./chat-page";

describe("formatChatTime", () => {
  it("formats Date and persisted ISO strings without throwing", () => {
    const fromDate = formatChatTime(new Date("2026-02-10T15:04:00.000Z"));
    const fromIso = formatChatTime("2026-02-10T15:04:00.000Z");
    expect(fromDate).toBe(fromIso);
    expect(fromDate.length).toBeGreaterThan(0);
  });

  it("returns empty string for invalid timestamps", () => {
    expect(formatChatTime("not-a-date")).toBe("");
  });
});
