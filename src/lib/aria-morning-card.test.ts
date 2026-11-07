import { describe, expect, it } from "vitest";

import {
  buildMorningCard,
  MAX_REASON_WORDS,
  shouldSpeak,
  wordCount,
} from "@/lib/aria-morning-card";
import { containsBannedSpeech, decideSafety } from "@/lib/forge-condition-safety";

describe("morning card", () => {
  it("uses numbers, stays under 25 words, and stays quiet until a number moves", () => {
    const card = buildMorningCard({
      numbers: { sleepHours: 5.4, readiness: 48, calendarBusyHours: 5 },
      previous: { sleepHours: 7.4, readiness: 72 },
      gymLabel: "home",
      patternChanges: ["Coffee moves before 1 PM today"],
      safetyFlags: ["sleepLoss"],
      talkativeness: "balanced",
    });
    expect(card.empty).toBe(false);
    expect(card.call).toBe("Easy session");
    expect(card.actions[0]).toBe("Coffee moves before 1 PM today");
    expect(card.reason).toContain("5.4");
    expect(wordCount(card.reason)).toBeLessThanOrEqual(MAX_REASON_WORDS);
    expect(card.speak).toBe(true);
    expect(containsBannedSpeech(card.call)).toBe(false);
    expect(containsBannedSpeech(card.reason)).toBe(false);
    expect(
      shouldSpeak({ moved: true, talkativeness: "quiet", quietMode: false })
    ).toBe(false);
  });

  it("does not guess a condition", () => {
    const none = decideSafety({
      declared: [],
      sleepHours: 4.8,
      heatRisk: true,
      moveNames: ["Open Water Swim", "Rock Climbing"],
    });
    expect(none.applied).toBe(false);
    const epilepsy = decideSafety({
      declared: ["epilepsy"],
      sleepHours: 5.2,
      heatRisk: true,
      moveNames: ["Open Water Swim", "Goblet Squat"],
    });
    expect(epilepsy.blockedMoves).toContain("Open Water Swim");
    expect(epilepsy.keptMoves).toContain("Goblet Squat");
    expect(epilepsy.changeNote.toLowerCase()).toContain("safety rule");
    expect(containsBannedSpeech(epilepsy.changeNote)).toBe(false);
  });
});
