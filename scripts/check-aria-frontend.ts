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
  ARIA_MARK_PAINT_HZ,
  ariaMarkPaintDue,
  ariaMarkShouldGlow,
  ariaMarkShouldSpin,
  ariaMarkSizeTier,
  clampGaze,
  compactRingIndices,
  contrastRingIndices,
  emberCoreRadius,
  emberLobe,
  nestOrbitHz,
  nestRingHex,
  orbCoreRadius,
  paintedNestOpacity,
  ringEllipse,
  ringSpinHz,
  ringStrokeWidth,
  visibleRingIndices,
} from "../src/lib/aria-mark.ts";
import {
  ARIA_MARK_LIFE,
  paintedRingOpacity,
  ringBreathScale,
  ringFlicker,
  ringGlowPulse,
  ringWobble,
} from "../src/lib/aria-ring-field.ts";
import { FORGE_FIRE, fireSpec, fireTongue, forgeFirePaintDue } from "../src/lib/forge-fire.ts";
import { FORGE_SPLASH, forgeSplashHoldMs } from "../src/lib/forge-splash.ts";
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
assert(ARIA_MARK.kind === "soft-hex-field", "living mark is soft-hex nest");
assert(ARIA_MARK.ringCount === 3, "nest has three rings");
assert(ARIA_MARK.radii.length === ARIA_MARK.ringCount, "radii match ringCount");
assert(ARIA_MARK.eccentricity.length === ARIA_MARK.ringCount, "eccentricity match ringCount");
assert(ARIA_MARK.tiltDeg.length === ARIA_MARK.ringCount, "tiltDeg match ringCount");
assert(ARIA_MARK.phaseOffsets.length === ARIA_MARK.ringCount, "phaseOffsets match ringCount");
assert(ARIA_MARK.opacity.length === ARIA_MARK.ringCount, "opacity match ringCount");
assert(ARIA_MARK.idleOrbitHz.length === ARIA_MARK.ringCount, "idleOrbitHz match ringCount");
assert(ARIA_MARK.speakingOrbitHz.length === ARIA_MARK.ringCount, "speakingOrbitHz match ringCount");
assert(
  ARIA_MARK.speakingOrbitHz.every((hz, i) => Math.abs(hz) > Math.abs(ARIA_MARK.idleOrbitHz[i] ?? 0)),
  "speaking orbits faster than idle"
);
assert(ARIA_MARK.strokeWidthCompact === 1.5, "compact stroke meets 1.5 floor");
assert(ARIA_MARK.strokeWidthHero === 1.75, "hero stroke is 1.75");
assert(ARIA_MARK.paintHz === 12, "paintHz is 12");
assert(ARIA_MARK.opacity.join(",") === "0.88,0.78,0.72", "opacity array is pearl/frost/orange lock");
assert(ARIA_MARK.opacity.every((o) => o >= ARIA_MARK_CONTRAST_FLOOR), "all nest ring opacities ≥ 0.70");
assert(ARIA_MARK.paintedOpacityFloor === 0.7, "painted flicker floor is 0.70");
assert(ARIA_MARK.ringHex.join(",") === `${ARIA_MARK.pearlHex},${ARIA_MARK.nestFrostHex},${ARIA_MARK.brandHue}`, "ringHex is pearl / frost / orange");
assert(ARIA_MARK.ringHex.length === ARIA_MARK.ringCount, "ringHex match ringCount");
assert(nestRingHex(0) === ARIA_MARK.pearlHex && ARIA_MARK.opacity[0] === 0.88, "ring 0 inner is pearl @ 0.88");
assert(nestRingHex(1) === ARIA_MARK.nestFrostHex && ARIA_MARK.opacity[1] === 0.78, "ring 1 mid is frost @ 0.78");
assert(nestRingHex(2) === ARIA_MARK.brandHue && ARIA_MARK.opacity[2] === 0.72, "ring 2 outer is Forge orange accent @ 0.72");
assert(ARIA_MARK.hearthSpecularMax === 0.55, "hearth specular is decorative under 0.55");
assert(ARIA_MARK.hearthSpecularMax < ARIA_MARK.paintedOpacityFloor, "hearth wash is never a compact silhouette");
assert(ARIA_MARK.notes.includes("Flicker/wave floor"), "notes name the flicker/wave floor");
assert(ARIA_MARK.notes.includes("never go below 0.70 after flicker/wave"), "notes lock painted opacity ≥ 0.70");
assert(paintedNestOpacity(0.72, 0.78) === ARIA_MARK.paintedOpacityFloor, "contrast ring flicker cannot drop below 0.70");
assert(paintedNestOpacity(0.88, 1) === 0.88, "full flicker keeps contract opacity");
assert(ARIA_MARK.wordmarkPrimaryMax === 32, "wordmark-primary ceiling is 32");
assert(ARIA_MARK.splash === "mark+wordmark", "splash is mark+wordmark");
assert(JSON.stringify(ARIA_MARK) === JSON.stringify(contract), "web ARIA_MARK matches shared/aria-mark.json");
assert(!("webPath" in ARIA_MARK) && !("sharedPath" in contract), "PNG is not the brand runtime");
assert(!("idleSpinHz" in ARIA_MARK) && !("speakingSpinHz" in contract), "ring-field spin scalars are retired");

assert(contrastRingIndices().join(",") === "0,1,2", "all three nest rings meet the contrast floor");
assert(compactRingIndices().join(",") === "0,1,2", "compact nest is the full 3-ring set");
assert(visibleRingIndices(ARIA_MARK.compactRecommend).join(",") === "0,1,2", "compact recommend draws 3 rings");
assert(visibleRingIndices(24).join(",") === "0,1,2", "nav compact draws 3 rings");
assert(visibleRingIndices(32).join(",") === "0,1,2", "compact ceiling draws 3 rings");
assert(visibleRingIndices(36).join(",") === "0,1,2", "mid 36 draws the 3-ring nest");
assert(visibleRingIndices(48).join(",") === "0,1,2", "mid 48 draws the 3-ring nest");
assert(visibleRingIndices(56).join(",") === "0,1,2", "mid 56 draws the 3-ring nest");
assert(visibleRingIndices(72).join(",") === "0,1,2", "mid 72 draws the 3-ring nest");
assert(visibleRingIndices(ARIA_MARK.heroMinimumSize).join(",") === "0,1,2", "hero draws the 3-ring nest");
assert(ringStrokeWidth(28) === ARIA_MARK.strokeWidthCompact, "compact stroke is 1.5");
assert(ringStrokeWidth(90) === ARIA_MARK.strokeWidthHero, "hero stroke is 1.75");
assert(nestOrbitHz(0, false) === ARIA_MARK.idleOrbitHz[0] && nestOrbitHz(0, true) === ARIA_MARK.speakingOrbitHz[0], "orbit Hz follows presence");
assert(ringSpinHz(false) === nestOrbitHz(0, false) && ringSpinHz(true, 1) === nestOrbitHz(1, true), "spin shim reads nest orbits");
assert(ariaMarkSizeTier(24) === "compact" && ariaMarkSizeTier(ARIA_MARK_COMPACT_MAX) === "compact", "nav slots are compact");
assert(ariaMarkSizeTier(36) === "mid" && ariaMarkSizeTier(89) === "mid", "chat chrome is mid");
assert(ariaMarkSizeTier(90) === "hero", "hero floor is 90");
assert(!ariaMarkShouldSpin(24, false), "compact marks stay still-pose");
assert(ariaMarkShouldSpin(36, false) && ariaMarkShouldSpin(56, false), "mid chat sizes orbit");
assert(ariaMarkShouldSpin(96, false) && !ariaMarkShouldSpin(96, true), "hero orbits only when motion is allowed");
assert(!ariaMarkShouldGlow(32) && !ariaMarkShouldGlow(ARIA_MARK.compactRecommend), "compact skips decorative glow");
assert(ariaMarkShouldGlow(36) && ariaMarkShouldGlow(90), "mid and hero keep soft glow");
assert(ARIA_MARK_PAINT_HZ === ARIA_MARK.paintHz && ARIA_MARK.paintHz === 12, "live paint cadence is contract paintHz 12");
assert(ariaMarkPaintDue(0, -1), "first frame always paints");
assert(!ariaMarkPaintDue(80, 0), "sub-12 Hz frames are skipped");
assert(ariaMarkPaintDue(1000 / ARIA_MARK_PAINT_HZ, 0), "12 Hz boundary paints");
assert(ARIA_MARK_CONTRAST_FLOOR === 0.7, "cove contrast floor is 0.70");

const stillRingA = ringEllipse(0, 1, false, true);
const stillRingB = ringEllipse(0, 99, true, true);
assert(
  stillRingA.rx === stillRingB.rx &&
    stillRingA.ry === stillRingB.ry &&
    stillRingA.rotation === stillRingB.rotation &&
    stillRingA.opacity === stillRingB.opacity,
  "reduce-motion freezes the nest at stillPoseAngleDeg"
);
assert(
  Math.abs(stillRingA.rotation - ((ARIA_MARK.tiltDeg[0] * Math.PI) / 180 + ARIA_MARK.phaseOffsets[0] * Math.PI * 2 + (ARIA_MARK.stillPoseAngleDeg * Math.PI) / 180)) < 1e-9,
  "still pose is tilt + phase + stillPoseAngleDeg"
);
const liveRingA = ringEllipse(1, 0.4, false, false);
const liveRingB = ringEllipse(1, 1.1, false, false);
assert(liveRingA.rotation !== liveRingB.rotation, "idle rings orbit when alive");
const idleDelta = ringEllipse(1, 1.1, false, false).rotation - ringEllipse(1, 0, false, false).rotation;
const talkDelta = ringEllipse(1, 1.1, true, false).rotation - ringEllipse(1, 0, true, false).rotation;
assert(Math.abs(talkDelta) > Math.abs(idleDelta), "speaking orbits faster than idle");

const rotations = new Set<string>();
for (let i = 0; i < ARIA_MARK.ringCount; i++) {
  const pose = ringEllipse(i, 0, false, true);
  assert(pose.rx > pose.ry, `ring ${i} is eccentric`);
  assert(pose.ry > 0.3 && pose.rx < 1.05, `ring ${i} stays in the mark disc`);
  rotations.add(pose.rotation.toFixed(4));
}
assert(rotations.size === ARIA_MARK.ringCount, "three nest rings overlap at distinct tilts");

assert(ARIA_ORB_CORE.hue === ARIA_MARK.pearlHotHex, "stopgap core is pearlHot metal sun");
const heroOrb = orbCoreRadius(ARIA_MARK.heroMinimumSize);
const compactOrb = orbCoreRadius(24);
const inner = ringEllipse(0, 0, false, true).ry / 2;
assert(heroOrb < inner, "hero orb nests inside the innermost nest ring");
assert(compactOrb < inner, "compact orb nests inside the innermost nest ring");
assert(Math.abs(heroOrb / inner - ARIA_ORB_CORE.nest) < 1e-9, "orb nest ratio is 0.88");
assert(compactOrb === heroOrb, "one 3-ring nest: orb size is not a compact 5-ellipse subset");

const stillA = emberLobe(0, 1, false, true);
const stillB = emberLobe(0, 99, true, true);
assert(stillA.x === stillB.x && stillA.y === stillB.y && stillA.r === stillB.r, "reduce-motion freezes lobes");
assert(emberCoreRadius(1, true, true) === emberCoreRadius(40, false, true), "reduce-motion freezes the core");
assert(emberCoreRadius(0.4, true, false) > emberCoreRadius(0.4, false, false), "speaking core is larger");
assert(clampGaze(1) === LEGACY_EMBER.maxGaze && clampGaze(-1) === -LEGACY_EMBER.maxGaze, "gaze is clamped");
assert(ARIA_LOBES.length === 4, "legacy ember still has four lobes");
assert(ARIA_LOBES.length !== ARIA_MARK.ringCount, "retired ember is not the 3-ring nest");
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

assert(FORGE_SPLASH.holdMs === 2450, "splash hold is 2.45s");
assert(FORGE_SPLASH.reduceMotionHoldMs === 650, "reduce-motion splash is 0.65s");
assert(FORGE_SPLASH.holdMs >= FORGE_SPLASH.brandFloorMs, "splash is long enough to feel forged");
assert(FORGE_SPLASH.holdMs < FORGE_SPLASH.freezeCeilingMs, "splash is short of a freeze");
assert(forgeSplashHoldMs(false) === 2450 && forgeSplashHoldMs(true) === 650, "splash hold follows motion preference");
assert(FORGE_FIRE.kind === "rage-fire", "welcome fire is rage-fire, not the ring-field");
assert(FORGE_FIRE.kind !== ARIA_MARK.kind, "fire is not the ARIA mark");
assert(fireSpec("rage").tongueCount > fireSpec("ember").tongueCount, "rage has more tongues than ember");
assert(fireSpec("rage").heightScale > fireSpec("ember").heightScale, "rage tongues are taller");
assert(fireSpec("rage").coreHeat > fireSpec("ember").coreHeat, "rage is white-hot, ember is not");
const rageTip = fireTongue(3, 28, 0.4, "rage", "floor", false);
const emberTip = fireTongue(3, 8, 0.4, "ember", "floor", false);
assert(rageTip.tipY < emberTip.tipY, "rage tips sit higher than ember");
assert(FORGE_FIRE.tickHz === 12, "fire paints at 12 Hz");
assert(FORGE_FIRE.tickHz <= 15 && FORGE_FIRE.tickHz >= 12, "fire cadence is 12–15 Hz");
assert(forgeFirePaintDue(0, -1), "first fire frame always paints");
assert(!forgeFirePaintDue(80, 0), "sub-12 Hz fire frames are skipped");
assert(forgeFirePaintDue(1000 / FORGE_FIRE.tickHz, 0), "12 Hz fire boundary paints");
assert(ARIA_MARK_LIFE.tickHz === 12, "living mark paints at 12 Hz");
assert(ARIA_MARK_LIFE.tickHz <= 12, "mark timeline is not above 12 Hz");
assert(ARIA_MARK_LIFE.tickHz === ARIA_MARK_PAINT_HZ, "life cadence matches paint Hz");
assert(ringFlicker(1, 0.4, true) === 1, "reduce-motion flicker is still");
assert(ringWobble(1, 0.4, true) === 0, "reduce-motion wobble is still");
assert(ringBreathScale(0.4, true, true) === 1, "reduce-motion breath is still");
assert(ringBreathScale(0.4, false, false) === 1, "compact marks do not breathe");
assert(ringFlicker(0, 0.2, false) !== ringFlicker(0, 1.0, false), "support rings flicker when alive");
assert(ringGlowPulse(0.2, 1, false) !== ringGlowPulse(1.1, 1, false), "hero glow pulses");
for (const index of contrastRingIndices()) {
  const base = ARIA_MARK.opacity[index] ?? 0;
  for (let t = 0; t < 4; t += 0.05) {
    const painted = paintedRingOpacity(index, t, false);
    assert(painted >= ARIA_MARK_CONTRAST_FLOOR, `contrast ring ${index} stays ≥0.70 after flicker`);
    assert(base * ringFlicker(index, t, false) >= ARIA_MARK_CONTRAST_FLOOR, `flicker floor holds for ring ${index}`);
  }
}

console.log("aria frontend checks passed");
