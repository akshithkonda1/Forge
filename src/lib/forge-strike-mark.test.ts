import { describe, expect, it } from "vitest";

import { tokenHex } from "@/lib/design-tokens";
import {
  FORGE_STRIKE_MARK,
  contrastRatio,
  flameCommands,
  hammerAngleDeg,
  hammerCommands,
  isCompactStrike,
  strikeFlare,
  strikePose,
  strikeProgress,
  strikeSpark,
  svgPath,
} from "@/lib/forge-strike-mark";

describe("forge strike mark", () => {
  it("is a hammer-strike, not the ARIA nest", () => {
    expect(FORGE_STRIKE_MARK.kind).toBe("hammer-strike");
    expect(FORGE_STRIKE_MARK.assetName).toBe("ForgeStrikeMark");
    expect(FORGE_STRIKE_MARK.paintHz).toBe(12);
    expect(FORGE_STRIKE_MARK.strikeDuration).toBe(0.55);
    expect(FORGE_STRIKE_MARK.sparkCount).toBe(6);
  });

  it("freezes to the idle pose when Reduce Motion is on", () => {
    const a = strikePose(0, true);
    const b = strikePose(1, true);
    expect(a).toEqual(b);
    expect(a.hammerAngleDeg).toBe(FORGE_STRIKE_MARK.idleAngleDeg);
    expect(a.flare).toBe(FORGE_STRIKE_MARK.idleFlare);
    expect(a.settled).toBe(true);
    expect(strikeSpark(2, 0.5, true).opacity).toBe(0);
  });

  it("strikes, flares, then settles", () => {
    expect(hammerAngleDeg(0.1)).toBe(FORGE_STRIKE_MARK.raisedAngleDeg);
    expect(hammerAngleDeg(0.4)).toBe(FORGE_STRIKE_MARK.impactAngleDeg);
    expect(hammerAngleDeg(1)).toBe(FORGE_STRIKE_MARK.idleAngleDeg);
    expect(strikeFlare(0.46)).toBeGreaterThan(strikeFlare(0.2));
    expect(strikeFlare(0.46)).toBeGreaterThan(strikeFlare(1));
    expect(strikePose(1, false).settled).toBe(true);
    const mid = strikeSpark(1, 0.52, false);
    const done = strikeSpark(1, 1, false);
    expect(mid.opacity).toBeGreaterThan(0.2);
    expect(done.opacity).toBe(0);
  });

  it("emits closed SVG paths and compact sizes stay still-scale", () => {
    const hammer = svgPath(hammerCommands(), 100);
    expect(hammer.startsWith("M ")).toBe(true);
    expect(hammer.endsWith("Z")).toBe(true);
    expect(svgPath(flameCommands(1, 1), 100)).toContain("C ");
    expect(isCompactStrike(18)).toBe(true);
    expect(isCompactStrike(90)).toBe(false);
    expect(strikeProgress(-1)).toBe(0);
    expect(strikeProgress(9)).toBe(1);
  });

  it("keeps paper, ember, and tertiary text at WCAG AA on the background", () => {
    const background = tokenHex("background").slice(1);
    expect(contrastRatio(FORGE_STRIKE_MARK.paperHex, background)).toBeGreaterThanOrEqual(4.5);
    expect(contrastRatio(FORGE_STRIKE_MARK.emberHex, background)).toBeGreaterThanOrEqual(4.5);
    expect(contrastRatio("84848D", background)).toBeGreaterThanOrEqual(4.5);
    expect(`#${FORGE_STRIKE_MARK.emberHex}`).toBe(tokenHex("ember"));
    expect(`#${FORGE_STRIKE_MARK.amberHex}`).toBe(tokenHex("amber"));
  });
});
