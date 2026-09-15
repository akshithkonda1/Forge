import { readFileSync } from "node:fs";
import { coachReply } from "../src/lib/aria-coach.ts";
import { ARIA_CINEMATIC_LINES, firstSessionScript, whisperForStep, welcomeChatMessage } from "../src/lib/aria-onboarding.ts";
import { ARIA_INTRO } from "../src/lib/aria-intro.ts";
import {
  ARIA_LOBES,
  ARIA_MARK,
  ARIA_MARK_COMPACT_MAX,
  ARIA_MARK_CONTRAST_FLOOR,
  ARIA_ORB_CORE,
  LEGACY_EMBER,
  ariaMarkShouldSpin,
  ariaMarkSizeTier,
  clampGaze,
  compactRingIndices,
  contrastRingIndices,
  emberCoreRadius,
  emberLobe,
  orbCoreRadius,
  ringEllipse,
  ringSpinHz,
  ringStrokeWidth,
  visibleRingIndices,
} from "../src/lib/aria-mark.ts";
import type { DailyMetrics, ReadinessData, UserProfile } from "../src/types/index.ts";

const profile: UserProfile = {
  name: "Sam Rivera",
  fitnessGoals: ["build-muscle"],
  experienceLevel: "intermediate",
  preferredWorkouts: ["strength"],
  coachingStyle: "balanced",
  connectedDevices: [],
  weeklySchedule: [1, 3, 5],
};

const readiness: ReadinessData = {
  overall: 82,
  sleepQuality: 88,
  recoveryScore: 79,
  stressLevel: 24,
  energyBank: 76,
};

const metrics: DailyMetrics = {
  steps: 4000,
  activeCalories: 200,
  hrv: 52,
  restingHR: 58,
  deepSleep: 102,
  totalSleep: 432,
};

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

const contract = JSON.parse(readFileSync("shared/aria-mark.json", "utf8")) as typeof ARIA_MARK;
assert(ARIA_MARK.assetName === "AriaMark", "ARIA mark asset is AriaMark");
assert(ARIA_MARK.kind === "ring-field", "living mark is kinetic ring-field");
assert(ARIA_MARK.ringCount === 5, "ring-field has five ellipses");
assert(ARIA_MARK.radii.length === ARIA_MARK.ringCount, "radii match ringCount");
assert(ARIA_MARK.eccentricity.length === ARIA_MARK.ringCount, "eccentricity match ringCount");
assert(ARIA_MARK.tiltDeg.length === ARIA_MARK.ringCount, "tiltDeg match ringCount");
assert(ARIA_MARK.phaseOffsets.length === ARIA_MARK.ringCount, "phaseOffsets match ringCount");
assert(ARIA_MARK.opacity.length === ARIA_MARK.ringCount, "opacity match ringCount");
assert(ARIA_MARK.idleSpinHz < ARIA_MARK.speakingSpinHz, "speaking spins faster than idle");
assert(ARIA_MARK.strokeWidthCompact === 1.5, "compact stroke meets cove floor (~3 CSS px at 1×)");
assert(ARIA_MARK.strokeWidthHero === 1.85, "hero stroke stays 1.85");
assert(ARIA_MARK.opacity.filter((o) => o >= 0.7).length >= 2, "at least two rings are legal single-stroke reads");
assert(JSON.stringify(ARIA_MARK) === JSON.stringify(contract), "web ARIA_MARK matches shared/aria-mark.json");
assert(!("webPath" in ARIA_MARK) && !("sharedPath" in contract), "PNG is not the brand runtime");

assert(contrastRingIndices().join(",") === "1,2", "contrast rings are the two ≥0.70 ellipses");
assert(compactRingIndices().join(",") === "1,2,4", "compact 3-ring is contrast pair + strongest support");
assert(visibleRingIndices(ARIA_MARK.compactRecommend).join(",") === "1,2,4", "compact recommend draws 3 rings");
assert(visibleRingIndices(32).join(",") === "1,2,4", "compact ceiling draws 3 rings");
assert(visibleRingIndices(48).join(",") === "1,2,4", "mid draws the compact 3-ring subset");
assert(visibleRingIndices(ARIA_MARK.heroMinimumSize).join(",") === "0,1,2,3,4", "hero draws all five");
assert(ringStrokeWidth(28) === ARIA_MARK.strokeWidthCompact, "compact stroke is 1.5");
assert(ringStrokeWidth(90) === ARIA_MARK.strokeWidthHero, "hero stroke is 1.85");
assert(ringSpinHz(false) === ARIA_MARK.idleSpinHz && ringSpinHz(true) === ARIA_MARK.speakingSpinHz, "spin Hz follows presence");
assert(ariaMarkSizeTier(24) === "compact" && ariaMarkSizeTier(ARIA_MARK_COMPACT_MAX) === "compact", "nav slots are compact");
assert(ariaMarkSizeTier(36) === "mid" && ariaMarkSizeTier(89) === "mid", "chat chrome is mid");
assert(ariaMarkSizeTier(90) === "hero", "hero floor is 90");
assert(!ariaMarkShouldSpin(24, false), "compact marks stay still-pose");
assert(ariaMarkShouldSpin(96, false) && !ariaMarkShouldSpin(96, true), "hero spins only when motion is allowed");
assert(ARIA_MARK_CONTRAST_FLOOR === 0.7, "cove contrast floor is 0.70");

const stillRingA = ringEllipse(0, 1, false, true);
const stillRingB = ringEllipse(0, 99, true, true);
assert(
  stillRingA.rx === stillRingB.rx &&
    stillRingA.ry === stillRingB.ry &&
    stillRingA.rotation === stillRingB.rotation &&
    stillRingA.opacity === stillRingB.opacity,
  "reduce-motion freezes the ring-field at stillPoseAngleDeg"
);
assert(
  Math.abs(stillRingA.rotation - ((ARIA_MARK.tiltDeg[0] * Math.PI) / 180 + ARIA_MARK.phaseOffsets[0] * Math.PI * 2 + (ARIA_MARK.stillPoseAngleDeg * Math.PI) / 180)) < 1e-9,
  "still pose is tilt + phase + stillPoseAngleDeg"
);
const liveRingA = ringEllipse(1, 0.4, false, false);
const liveRingB = ringEllipse(1, 1.1, false, false);
assert(liveRingA.rotation !== liveRingB.rotation, "idle rings spin when alive");
const idleDelta = ringEllipse(1, 1.1, false, false).rotation - ringEllipse(1, 0, false, false).rotation;
const talkDelta = ringEllipse(1, 1.1, true, false).rotation - ringEllipse(1, 0, true, false).rotation;
assert(talkDelta > idleDelta, "speaking spins faster than idle");

const rotations = new Set<string>();
for (let i = 0; i < ARIA_MARK.ringCount; i++) {
  const pose = ringEllipse(i, 0, false, true);
  assert(pose.rx > pose.ry, `ring ${i} is eccentric`);
  assert(pose.ry > 0.3 && pose.rx < 1.05, `ring ${i} stays in the mark disc`);
  rotations.add(pose.rotation.toFixed(4));
}
assert(rotations.size === ARIA_MARK.ringCount, "five rings overlap at distinct tilts");

assert(ARIA_ORB_CORE.hue === "#FFFFFF", "intelligence core is white");
const heroOrb = orbCoreRadius(ARIA_MARK.heroMinimumSize);
const compactOrb = orbCoreRadius(24);
const heroInner = ringEllipse(0, 0, false, true).ry / 2;
const compactInner = ringEllipse(1, 0, false, true).ry / 2;
assert(heroOrb < heroInner, "hero orb nests inside the innermost ellipse");
assert(compactOrb < compactInner, "compact orb nests inside the Cove 3-ring");
assert(Math.abs(heroOrb / heroInner - ARIA_ORB_CORE.nest) < 1e-9, "orb nest ratio is 0.88");
assert(compactOrb > heroOrb, "compact core stays readable at 24px");

const stillA = emberLobe(0, 1, false, true);
const stillB = emberLobe(0, 99, true, true);
assert(stillA.x === stillB.x && stillA.y === stillB.y && stillA.r === stillB.r, "reduce-motion freezes lobes");
assert(emberCoreRadius(1, true, true) === emberCoreRadius(40, false, true), "reduce-motion freezes the core");
assert(emberCoreRadius(0.4, true, false) > emberCoreRadius(0.4, false, false), "speaking core is larger");
assert(clampGaze(1) === LEGACY_EMBER.maxGaze && clampGaze(-1) === -LEGACY_EMBER.maxGaze, "gaze is clamped");
assert(ARIA_LOBES.length === 4, "legacy ember still has four lobes");
assert(ARIA_LOBES.length !== ARIA_MARK.ringCount, "retired ember is not the five-ring mark");
const liveA = emberLobe(1, 0.4, false, false);
const liveB = emberLobe(1, 1.1, false, false);
assert(liveA.x !== liveB.x || liveA.y !== liveB.y || liveA.r !== liveB.r, "idle lobes move when alive");

assert(ARIA_CINEMATIC_LINES.length === 1, "welcome is one beat");
assert(ARIA_INTRO.title === "This is ARIA", "first-meet title is This is ARIA");
assert(!ARIA_INTRO.lead.includes(ARIA_INTRO.pairingForbidden), "intro does not pair Forge × ARIA");
assert(ARIA_INTRO.lead.includes("designed for Forge"), "ARIA was designed for Forge");
assert(ARIA_INTRO.capabilities.length === 4, "intro names four things ARIA can do");
assert(!welcomeChatMessage({
  name: "Jack",
  goals: ["build-muscle"],
  experience: "intermediate",
  workouts: ["strength"],
  coachingStyle: "balanced",
  devicesConnected: 0,
}).includes("Jack"), "first ARIA line is not a name pairing");

const welcome = whisperForStep("welcome");
assert(!welcome.message.includes("HRV"), "welcome does not dump HRV");

const script = firstSessionScript({
  name: "Sam",
  goals: ["build-muscle"],
  experience: "intermediate",
  workouts: ["strength"],
  coachingStyle: "balanced",
  devicesConnected: 0,
});
assert(script.includes("Sam"), "session script uses name");
assert(!script.includes("HRV"), "session script stays human");

const train = coachReply("How should I train today?", profile, readiness, metrics, []);
assert(train.content.includes("primed"), "train reply uses readiness word");
assert(!train.content.includes("HRV"), "balanced voice does not dump HRV");
assert(train.richCard?.type === "workout-plan", "train reply ships a plan");

const dataProfile = { ...profile, coachingStyle: "data-driven" as const };
const dataTrain = coachReply("How should I train today?", dataProfile, readiness, metrics, []);
assert(dataTrain.content.includes("HRV"), "data-driven voice can cite HRV");

const sleep = coachReply("Explain my sleep data", profile, readiness, metrics, []);
assert(sleep.content.includes("rebuilt") || sleep.content.includes("thinner"), "sleep reply is a story");

const biceps = coachReply("hit my biceps today", profile, readiness, metrics, []);
assert(biceps.richCard?.type === "workout-plan", "biceps ask ships a plan");
assert(String((biceps.richCard?.data as { name?: string })?.name ?? "").toLowerCase().includes("bicep"), "biceps plan is named for the muscle");

console.log("aria frontend checks passed");
