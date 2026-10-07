import { readFileSync } from "node:fs";

/**
 * Phone Home HUD token contract — `shared/readiness.json` only.
 * Does not import web Home chrome or Nest mark sources.
 */

type Band = { id: string; label: string; min: number; hex: string; token: string };

type ReadinessFile = {
  kind: string;
  surface: string;
  mixLock: string;
  bands: Band[];
  hud: {
    plateHex: string;
    emberSteelHex: string;
    tickHz: number;
    tickHzCeiling: number;
    tickChromeFloor: number;
    armedMajorTickOpacity: number;
    inArcMinimumScale: number;
  };
  trend: {
    trendWindowDays: number;
    trendWindowAnchor: string;
    trendPoints: string;
    nightDate: string;
    nightCutoffHour: number;
  };
  bannedSurfacePhrases: string[];
};

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

function stripHash(hex: string): string {
  return hex.trim().replace(/^#/, "").toUpperCase();
}

function srgbChannel(value: number): number {
  return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
}

function relativeLuminance(hex: string): number {
  const raw = stripHash(hex);
  assert(/^[0-9A-F]{6}$/.test(raw), `hex ${hex} is not RRGGBB`);
  const r = srgbChannel(parseInt(raw.slice(0, 2), 16) / 255);
  const g = srgbChannel(parseInt(raw.slice(2, 4), 16) / 255);
  const b = srgbChannel(parseInt(raw.slice(4, 6), 16) / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrastRatio(foreground: string, background: string): number {
  const a = relativeLuminance(foreground);
  const b = relativeLuminance(background);
  const hi = Math.max(a, b);
  const lo = Math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

const file = JSON.parse(readFileSync("shared/readiness.json", "utf8")) as ReadinessFile;
const NEST_EMBER = "FF4D00";
const DARK = "0A0A0A";
const AA_NORMAL = 4.5;

assert(file.kind === "home-progress-hud", "kind is home-progress-hud");
assert(file.surface === "phone-home", "surface is phone-home");
assert(file.mixLock === "chrome-not-nest", "mixLock is chrome-not-nest");

const want = [
  { id: "peak", label: "Peak", min: 85, hex: "22C55E" },
  { id: "good", label: "Good", min: 70, hex: "F5A524" },
  { id: "fair", label: "Fair", min: 50, hex: "5B8DEF" },
  { id: "low", label: "Low", min: 0, hex: "EF4444" },
] as const;
assert(file.bands.length === 4, "exactly four Home bands");
for (const [i, band] of file.bands.entries()) {
  const expected = want[i];
  assert(expected, `band ${i} exists`);
  assert(band.id === expected.id, `band ${i} id is ${expected.id}`);
  assert(band.label === expected.label, `band ${i} label is ${expected.label}`);
  assert(band.min === expected.min, `band ${expected.label} min is ${expected.min}`);
  assert(stripHash(band.hex) === expected.hex, `band ${expected.label} hex is ${expected.hex}`);
}
assert(stripHash(file.bands[1]?.hex ?? "") !== NEST_EMBER, "Good is not nest ember FF4D00");
assert(
  !file.bands.some((band) => ["Primed", "Ready", "Moderate", "Recovery"].includes(band.label)),
  "Home bands are not Watch/Theme words"
);

const hud = file.hud;
assert(hud.tickHz <= hud.tickHzCeiling, "tickHz ≤ tickHzCeiling");
assert(hud.tickHzCeiling <= 12, "tickHzCeiling ≤ 12");
assert(hud.tickChromeFloor >= 0.7, "tickChromeFloor ≥ 0.70");
assert(hud.armedMajorTickOpacity >= hud.tickChromeFloor, "armed major ticks stay at/above chrome floor");
assert(hud.inArcMinimumScale === 0.7, "in-arc Dynamic Type scale floor is 0.7");

const trend = file.trend;
assert(trend.trendWindowDays === 7, "trendWindowDays is 7");
assert(trend.trendWindowAnchor === "lastNight", "trendWindowAnchor is lastNight");
assert(trend.trendPoints === "window", "trendPoints is window");
assert(trend.nightDate === "bedtime", "nightDate is bedtime");
assert(
  Number.isInteger(trend.nightCutoffHour) && trend.nightCutoffHour >= 0 && trend.nightCutoffHour <= 23,
  "nightCutoffHour is an hour 0–23"
);

const banned = [
  "diagnos",
  "treat",
  "prescribe",
  "cure",
  "medical advice",
  "recovery-first",
  "recovery week",
];
for (const phrase of banned) {
  assert(file.bannedSurfacePhrases.includes(phrase), `bannedSurfacePhrases includes ${phrase}`);
}

const contrastTargets: Array<[string, string]> = [
  ["Peak", file.bands[0]?.hex ?? ""],
  ["Good", file.bands[1]?.hex ?? ""],
  ["Fair", file.bands[2]?.hex ?? ""],
  ["Low", file.bands[3]?.hex ?? ""],
  ["plateHex", hud.plateHex],
];
for (const [name, hex] of contrastTargets) {
  const ratio = contrastRatio(hex, DARK);
  assert(ratio >= AA_NORMAL, `${name} ${hex} vs #${DARK} is ${ratio.toFixed(3)}:1, need ≥ ${AA_NORMAL}`);
}

console.log("readiness frontend checks passed");
