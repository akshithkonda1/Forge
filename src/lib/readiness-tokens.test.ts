import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import {
  isAlmostThere,
  MISS_HEX,
  PLATE_HEX,
  READINESS,
  readinessBand,
  readinessHex,
  readinessLabel,
  tileAlmostThere,
} from "@/lib/readiness-tokens";

describe("shared readiness tokens", () => {
  it("stays lockstep with shared/readiness.json", () => {
    const file = JSON.parse(readFileSync("shared/readiness.json", "utf8"));
    expect(READINESS).toEqual(file);
    expect(READINESS.bands.map((band) => band.label)).toEqual([
      "Peak",
      "Good",
      "Fair",
      "Low",
    ]);
    expect(READINESS.motivation.brackets).toBe(false);
    expect(READINESS.motivation.scanlines).toBe(false);
    expect(READINESS.motivation.eventGlowOnly).toBe(true);
    expect(READINESS.motivation.liveGlowDefault).toBe(false);
  });

  it("uses Home Peak/Good/Fair/Low cuts, not Primed/Rest Day", () => {
    expect(readinessLabel(90)).toBe("Peak");
    expect(readinessLabel(72)).toBe("Good");
    expect(readinessLabel(60)).toBe("Fair");
    expect(readinessLabel(40)).toBe("Low");
    expect(readinessHex(72)).toBe("#F5A524");
    expect(readinessBand(88).id).toBe("peak");
    expect(PLATE_HEX).toBe("#7EC8FF");
    expect(MISS_HEX).toBe("#7BA6F7");
    expect(MISS_HEX).not.toBe("#EF4444");
  });

  it("marks almost-there without treating a miss as an alarm", () => {
    expect(isAlmostThere(80, 1)).toBe(true);
    expect(isAlmostThere(40, 3)).toBe(false);
    expect(tileAlmostThere(0.8)).toBe(true);
    expect(tileAlmostThere(0.4)).toBe(false);
    expect(tileAlmostThere(1)).toBe(false);
  });
});
