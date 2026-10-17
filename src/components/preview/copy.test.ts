import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { DESIGN, containsBannedPhrase, tokenHex } from "@/lib/design-tokens";
import { PREVIEW_CATALOG } from "./catalog";
import {
  CHAT_SAMPLE,
  DISCOVERY,
  HEALTH,
  HOW_ARE_YOU,
  MEET,
  MEMORY,
  MOSAIC,
  PERSONALITIES,
  TUTORIAL,
} from "./copy";

describe("PR #472 preview gallery", () => {
  it("covers every requested surface", () => {
    const slugs = PREVIEW_CATALOG.map((entry) => entry.slug);
    expect(slugs).toEqual([
      "onboarding-meet",
      "onboarding-health",
      "onboarding-how-are-you",
      "tutorial-beginner",
      "tutorial-competitor",
      "home",
      "lifestyle",
      "sleep",
      "stats",
      "chat",
      "memory",
      "train",
    ]);
  });

  it("keeps permission rows and the how-are-you beat", () => {
    expect(HEALTH.rows.map((row) => row.title)).toEqual([
      "Apple Health",
      "Apple Calendar",
      "Contacts",
      "Reminders",
    ]);
    expect(HOW_ARE_YOU.chips).toContain("How did I sleep?");
    expect(HOW_ARE_YOU.aria.toLowerCase()).toContain("ask me something true");
  });

  it("branches beginner and competitor tutorial openings", () => {
    expect(TUTORIAL.beginner.welcome).toContain("no jargon");
    expect(TUTORIAL.competitor.welcome).toContain("not a sales pitch");
    expect(TUTORIAL.skip).toBe("Skip");
  });

  it("names Coach, Friend, Drill Sergeant and memory privacy", () => {
    expect(PERSONALITIES.map((p) => p.label)).toEqual(["Coach", "Friend", "Drill Sergeant"]);
    expect(MEMORY.privacy).toContain("On this phone");
    expect(DISCOVERY.suggest.toLowerCase()).toContain("could try");
    expect(MOSAIC.tiles.map((t) => t.track)).toEqual([
      "Sleep",
      "Train",
      "Water",
      "Move",
      "Habits",
    ]);
  });

  it("never diagnoses and never says recovery-first", () => {
    const blob = JSON.stringify({
      MEET,
      HEALTH,
      HOW_ARE_YOU,
      TUTORIAL,
      CHAT_SAMPLE,
      MEMORY,
      DISCOVERY,
    });
    expect(containsBannedPhrase(blob)).toBeUndefined();
    expect(MEET.capabilities.map((c) => c.title)).not.toContain("Recovery");
  });

  it("uses FDS tessera radius, hairline, and Home palette", () => {
    expect(DESIGN.radius.lg).toBe(18);
    expect(DESIGN.stroke.hairline).toBe(0.8);
    expect(tokenHex("background")).toBe("#08080C");
    expect(DESIGN.type.displayFamily).toBe("instrument-serif");
    expect(DESIGN.type.bodyFamily).toBe("geist");
  });

  it("keeps the ARIA mark procedural", () => {
    const mark = JSON.parse(readFileSync("shared/aria-mark.json", "utf8")) as {
      kind: string;
    };
    expect(mark.kind).toBe("soft-hex-field");
  });
});
