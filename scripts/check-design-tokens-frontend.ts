import { readFileSync } from "node:fs";

/**
 * Cross-client design-token contract — `shared/design-tokens.json`.
 * Home is the look. Web CSS and TS must read the same hex / type / UX.
 */

type Tokens = {
  kind: string;
  mixLock: string;
  color: Record<string, string>;
  type: { roles: Record<string, { tabular: boolean; design: string }> };
  motion: { eventOnly: boolean; liveGlowDefault: boolean; maxTickHz: number };
  ux: { minTap: number; onePrimaryCTA: boolean; permissionSkip: string };
  copy: { neverExpandARIA: boolean; ariaRole: string; bannedPhrases: string[] };
};

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

const file = JSON.parse(readFileSync("shared/design-tokens.json", "utf8")) as Tokens;
const css = readFileSync("src/app/globals.css", "utf8");
const ts = readFileSync("src/lib/design-tokens.ts", "utf8");

assert(file.kind === "forge-design-tokens", "kind is forge-design-tokens");
assert(file.mixLock === "home-is-source", "Home is the source of truth");
assert(file.color.background === "08080C", "background is Home 08080C");
assert(file.color.steel === "5B8DEF", "steel is Home 5B8DEF");
assert(file.color.miss === "7BA6F7", "miss is steel, not alert");
assert(file.color.miss !== "EF4444", "miss is not alert red");
assert(file.color.ember === "FF4D00", "ember stays nest energy");
assert(Object.keys(file.type.roles).join(",") === "display,title,headline,body,caption,metric", "named type scale");
assert(file.type.roles.metric.tabular === true, "metrics use tabular digits");
assert(file.motion.eventOnly === true, "motion is event-only");
assert(file.motion.liveGlowDefault === false, "no idle glow loop");
assert(file.motion.maxTickHz <= 12, "tick ceiling stays at nest paintHz");
assert(file.ux.minTap === 44, "tap targets are 44 pt");
assert(file.ux.onePrimaryCTA === true, "one primary CTA");
assert(file.ux.permissionSkip === "always-visible", "permission Skip is always visible");
assert(file.copy.neverExpandARIA === true, "never expand ARIA");
assert(file.copy.ariaRole === "lifestyle coach", "ARIA is a lifestyle coach");
assert(file.copy.bannedPhrases.includes("Adaptive Recovery"), "banned Adaptive Recovery");
assert(file.copy.bannedPhrases.includes("recovery week"), "banned recovery week");

assert(css.includes("#08080C"), "web CSS uses Home background");
assert(css.includes("#5B8DEF"), "web CSS uses Home steel");
assert(css.includes("#7BA6F7"), "web CSS uses miss steel");
assert(css.includes("--text-display"), "web CSS names display");
assert(css.includes("--text-metric"), "web CSS names metric");
assert(css.includes("tabular-nums"), "web metrics are tabular");
assert(css.includes(".type-display"), "web exposes type-display");
assert(css.includes("prefers-reduced-motion"), "web respects Reduce Motion");
assert(ts.includes("shared/design-tokens.json"), "web TS imports the shared file");

const settings = readFileSync("src/components/settings/settings-page.tsx", "utf8");
assert(!/recovery-first/i.test(settings), "settings about copy is not recovery-first");
assert(!/Adaptive Recovery/i.test(readFileSync("src/lib/aria-intro.ts", "utf8")), "intro never expands ARIA");

console.log("design-token frontend checks passed");
