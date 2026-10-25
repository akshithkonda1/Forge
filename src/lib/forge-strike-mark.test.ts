import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { tokenHex } from "@/lib/design-tokens";
import {
  FORGE_STRIKE_MARK,
  contrastRatio,
  flameCommands,
  flareScale,
  hammerAngleDeg,
  hammerCommands,
  hammerHighlightCommands,
  isCompactStrike,
  spring01,
  strikeFlare,
  strikePose,
  strikeProgress,
  strikeSpark,
  svgPath,
} from "@/lib/forge-strike-mark";

function pointsOf(commands: ReturnType<typeof hammerCommands>) {
  return commands.flatMap((command) => {
    if (command.type === "M" || command.type === "L") return [{ x: command.x, y: command.y }];
    if (command.type === "C") return [{ x: command.x, y: command.y }];
    return [];
  });
}

describe("forge strike mark", () => {
  it("is a hammer-strike, not the ARIA nest", () => {
    expect(FORGE_STRIKE_MARK.kind).toBe("hammer-strike");
    expect(FORGE_STRIKE_MARK.assetName).toBe("ForgeStrikeMark");
    expect(FORGE_STRIKE_MARK.paintHz).toBe(12);
    expect(FORGE_STRIKE_MARK.strikeDuration).toBe(0.56);
    expect(FORGE_STRIKE_MARK.strikeDuration).toBeLessThan(0.6);
    expect(FORGE_STRIKE_MARK.sparkCount).toBe(6);
    expect(FORGE_STRIKE_MARK.flameLayerCount).toBe(4);
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

  it("strikes down, flares, springs, then settles", () => {
    expect(hammerAngleDeg(0.1)).toBe(FORGE_STRIKE_MARK.raisedAngleDeg);
    expect(hammerAngleDeg(FORGE_STRIKE_MARK.impactEnd)).toBe(FORGE_STRIKE_MARK.impactAngleDeg);
    expect(hammerAngleDeg(1)).toBeCloseTo(FORGE_STRIKE_MARK.idleAngleDeg, 0);
    expect(FORGE_STRIKE_MARK.raisedAngleDeg).toBeGreaterThan(FORGE_STRIKE_MARK.idleAngleDeg);
    expect(FORGE_STRIKE_MARK.impactAngleDeg).toBeLessThan(FORGE_STRIKE_MARK.idleAngleDeg);
    expect(strikeFlare(FORGE_STRIKE_MARK.impactEnd + 0.04)).toBeGreaterThan(strikeFlare(0.2));
    expect(strikeFlare(FORGE_STRIKE_MARK.impactEnd + 0.04)).toBeGreaterThan(strikeFlare(1));
    expect(strikePose(1, false).settled).toBe(true);
    const mid = strikeSpark(1, FORGE_STRIKE_MARK.impactEnd + 0.12, false);
    const done = strikeSpark(1, 1, false);
    expect(mid.opacity).toBeGreaterThan(0.2);
    expect(done.opacity).toBe(0);
    expect(spring01(0.45)).toBeGreaterThan(0.9);
    expect(spring01(1)).toBeCloseTo(1, 1);
  });

  it("emits closed SVG paths and compact sizes stay still-scale", () => {
    const hammer = svgPath(hammerCommands(), 100);
    expect(hammer.startsWith("M ")).toBe(true);
    expect(hammer.endsWith("Z")).toBe(true);
    expect(svgPath(flameCommands(1, 1), 100)).toContain("C ");
    expect(svgPath(hammerHighlightCommands(), 100)).toContain("C ");
    expect(isCompactStrike(18)).toBe(true);
    expect(isCompactStrike(90)).toBe(false);
    expect(strikeProgress(-1)).toBe(0);
    expect(strikeProgress(9)).toBe(1);
    const idle = flareScale(FORGE_STRIKE_MARK.idleFlare);
    expect(idle.y).toBeLessThan(1);
    expect(idle.originX).toBe(FORGE_STRIKE_MARK.flameOriginX);
  });

  it("uses a filleted engineer hammer with an eye, not a gavel or spatula", () => {
    const commands = hammerCommands();
    const cubics = commands.filter((command) => command.type === "C");
    const closes = commands.filter((command) => command.type === "Z");
    const pts = pointsOf(commands);
    const xs = pts.map((point) => point.x);
    const ys = pts.map((point) => point.y);
    const width = Math.max(...xs) - Math.min(...xs);
    const height = Math.max(...ys) - Math.min(...ys);
    expect(cubics.length).toBeGreaterThanOrEqual(8);
    expect(closes.length).toBe(2);
    expect(Math.min(...xs)).toBeLessThan(-0.2);
    expect(width).toBeGreaterThan(height);
    expect(height).toBeLessThan(0.28);
    expect(FORGE_STRIKE_MARK.idleAngleDeg).toBeLessThan(-18);
    expect(FORGE_STRIKE_MARK.idleAngleDeg).toBeGreaterThan(-36);
  });

  it("gives the flame a pointed two-tip silhouette and unique layers", () => {
    const outer = pointsOf(flameCommands(0, 1));
    const body = pointsOf(flameCommands(1, 1));
    const core = pointsOf(flameCommands(2, 1));
    const outerTip = Math.min(...outer.map((point) => point.y));
    const coreTip = Math.min(...core.map((point) => point.y));
    expect(outerTip).toBeLessThan(0.08);
    expect(coreTip).toBeGreaterThan(outerTip);
    expect(svgPath(flameCommands(0, 1), 100)).not.toBe(svgPath(flameCommands(1, 1), 100));
    expect(svgPath(flameCommands(1, 1), 100)).not.toBe(svgPath(flameCommands(2, 1), 100));
  });

  it("stays lockstep with iOS geometry constants", () => {
    const swift = readFileSync(
      "ForgeSwift/ForgeCore/Sources/ForgeCore/DesignSystem/ForgeStrikeMarkGeometry.swift",
      "utf8"
    );
    expect(swift).toContain(`strikeDuration: Double = ${FORGE_STRIKE_MARK.strikeDuration}`);
    expect(swift).toContain(`idleAngleDeg: Double = ${FORGE_STRIKE_MARK.idleAngleDeg}`);
    expect(swift).toContain(`raisedAngleDeg: Double = ${FORGE_STRIKE_MARK.raisedAngleDeg}`);
    expect(swift).toContain(`impactAngleDeg: Double = ${FORGE_STRIKE_MARK.impactAngleDeg}`);
    expect(swift).toContain(`pivotX: Double = ${FORGE_STRIKE_MARK.pivotX}`);
    expect(swift).toContain(`paperShadeHex = "${FORGE_STRIKE_MARK.paperShadeHex}"`);
    expect(swift).toContain(".close,");
    expect(readFileSync("src/components/brand/forge-strike-mark.tsx", "utf8")).toContain("fillRule=\"evenodd\"");
    expect(readFileSync("ForgeSwift/ForgeSwift/ForgeStrikeMark.swift", "utf8")).toContain(".evenOdd");
  });

  it("keeps paper, ember, and tertiary text at WCAG AA on the background", () => {
    const background = tokenHex("background").slice(1);
    expect(contrastRatio(FORGE_STRIKE_MARK.paperHex, background)).toBeGreaterThanOrEqual(4.5);
    expect(contrastRatio(FORGE_STRIKE_MARK.paperShadeHex, background)).toBeGreaterThanOrEqual(4.5);
    expect(contrastRatio(FORGE_STRIKE_MARK.emberHex, background)).toBeGreaterThanOrEqual(4.5);
    expect(contrastRatio("84848D", background)).toBeGreaterThanOrEqual(4.5);
    expect(`#${FORGE_STRIKE_MARK.emberHex}`).toBe(tokenHex("ember"));
    expect(`#${FORGE_STRIKE_MARK.amberHex}`).toBe(tokenHex("amber"));
  });
});
