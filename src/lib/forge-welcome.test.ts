import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { FORGE_WELCOME, FORGE_WELCOME_TAGLINES, forgeWelcomeTagline } from "@/lib/forge-welcome";

describe("forge welcome copy", () => {
  it("uses shared/forge-welcome.json as the one switch", () => {
    const file = JSON.parse(readFileSync("shared/forge-welcome.json", "utf8"));
    expect(FORGE_WELCOME).toEqual(file);
    expect(FORGE_WELCOME.activeIndex).toBe(0);
    expect(FORGE_WELCOME_TAGLINES).toEqual([
      "Forged, not promised. The rest is you.",
      "We bring the heat. You do the shaping.",
      "Stronger than you came in, if you put in the work.",
    ]);
    expect(forgeWelcomeTagline()).toBe(FORGE_WELCOME.taglines[FORGE_WELCOME.activeIndex]);
    expect(forgeWelcomeTagline()).toBe("Forged, not promised. The rest is you.");
    expect(FORGE_WELCOME.markLabel).toBe("Forge mark, a hammer striking a flame");
    expect(FORGE_WELCOME.firstPageId).toBe("brand");
  });

  it("wires the mark and tagline onto splash and welcome", () => {
    const splash = readFileSync("src/app/page.tsx", "utf8");
    const welcome = readFileSync("src/components/onboarding/welcome-screen.tsx", "utf8");
    const iosSplash = readFileSync("ForgeSwift/ForgeSwift/ContentView.swift", "utf8");
    const iosWelcome = readFileSync("ForgeSwift/ForgeSwift/AuthWelcomeView.swift", "utf8");
    expect(splash).toContain("ForgeStrikeMark");
    expect(splash).toContain("forgeWelcomeTagline");
    expect(splash).not.toContain("Forged.");
    expect(welcome).toContain("ForgeStrikeMark");
    expect(welcome).toContain("FORGE_WELCOME.firstPageId");
    expect(iosSplash).toContain("ForgeStrikeMark");
    expect(iosSplash).toContain("ForgeWelcomeCopy.tagline");
    expect(iosWelcome).toContain("ForgeStrikeMark");
    expect(iosWelcome).toContain("ForgeWelcomeCopy.firstPageId");
  });

  it("does not leak health metrics into welcome copy", () => {
    const lines = [...FORGE_WELCOME.taglines, FORGE_WELCOME.markLabel, FORGE_WELCOME.firstPageBody];
    for (const line of lines) {
      expect(line.toLowerCase()).not.toContain("hrv");
      expect(line.toLowerCase()).not.toContain("heart rate");
      expect(line.toLowerCase()).not.toContain("vo2");
      expect(line.toLowerCase()).not.toContain("healthkit");
    }
  });
});
