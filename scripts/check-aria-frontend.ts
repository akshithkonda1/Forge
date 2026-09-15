import { readFileSync } from "node:fs";
import { coachReply } from "../src/lib/aria-coach.ts";
import { ARIA_CINEMATIC_LINES, firstSessionScript, whisperForStep, welcomeChatMessage } from "../src/lib/aria-onboarding.ts";
import { ARIA_INTRO } from "../src/lib/aria-intro.ts";
import {
  ARIA_LOBES,
  ARIA_MARK,
  ARIA_MARK_COMPACT_MAX,
  ARIA_MARK_CONTRAST_FLOOR,
  LEGACY_EMBER,
  ariaMarkShouldSpin,
  ariaMarkSizeTier,
  clampGaze,
  compactRingIndices,
  contrastRingIndices,
  emberCoreRadius,
  emberLobe,
  FORGE_WORDMARK,
  NEST_PAINT_INTERVAL_MS,
  metalSunPose,
  nestLiveCreateId,
  nestLiveIsWinner,
  nestLiveReset,
  nestLiveUpsert,
  nestLiveWinnerId,
  nestOrbitHz,
  nestRingHex,
  nestRingPose,
  paintedNestOpacity,
  ringEllipse,
  ringSpinHz,
  ringStrokeWidth,
  visibleRingIndices,
} from "../src/lib/aria-mark.ts";
import { drawAriaNest } from "../src/lib/aria-nest.ts";
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
assert(visibleRingIndices(32).join(",") === "0,1,2", "compact ceiling draws 3 rings");
assert(visibleRingIndices(48).join(",") === "0,1,2", "mid draws the 3-ring nest");
assert(visibleRingIndices(ARIA_MARK.heroMinimumSize).join(",") === "0,1,2", "hero draws the 3-ring nest");
assert(ringStrokeWidth(28) === ARIA_MARK.strokeWidthCompact, "compact stroke is 1.5");
assert(ringStrokeWidth(90) === ARIA_MARK.strokeWidthHero, "hero stroke is 1.75");
assert(nestOrbitHz(0, false) === ARIA_MARK.idleOrbitHz[0] && nestOrbitHz(0, true) === ARIA_MARK.speakingOrbitHz[0], "orbit Hz follows presence");
assert(ringSpinHz(false) === nestOrbitHz(0, false) && ringSpinHz(true, 1) === nestOrbitHz(1, true), "spin shim reads nest orbits");
assert(ariaMarkSizeTier(24) === "compact" && ariaMarkSizeTier(ARIA_MARK_COMPACT_MAX) === "compact", "nav slots are compact");
assert(ariaMarkSizeTier(36) === "mid" && ariaMarkSizeTier(89) === "mid", "chat chrome is mid");
assert(ariaMarkSizeTier(90) === "hero", "hero floor is 90");
assert(!ariaMarkShouldSpin(24, false), "compact marks stay still-pose");
assert(ariaMarkShouldSpin(96, false) && !ariaMarkShouldSpin(96, true), "hero orbits only when motion is allowed");
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

assert(FORGE_WORDMARK === "FORGE", "wordmark is FORGE");
assert(NEST_PAINT_INTERVAL_MS === 1000 / 12, "paint interval is 12 Hz");

const stillNestA = nestRingPose(2, 1, true, true);
const stillNestB = nestRingPose(2, 99, true, true);
assert(
  stillNestA.rotation === stillNestB.rotation &&
    stillNestA.waveAmp === 0 &&
    stillNestB.waveAmp === 0 &&
    stillNestA.hex === ARIA_MARK.brandHue,
  "reduce-motion freezes nest wave + still pose"
);
assert(stillNestA.opacity >= ARIA_MARK_CONTRAST_FLOOR, "still outer ring stays at or above 0.70");

for (let t = 0; t < 4; t += 0.07) {
  for (const speaking of [false, true]) {
    for (let i = 0; i < ARIA_MARK.ringCount; i++) {
      const pose = nestRingPose(i, t, speaking, false);
      assert(pose.opacity >= ARIA_MARK_CONTRAST_FLOOR, `wave cannot paint ring ${i} below 0.70 at t=${t}`);
      assert(pose.hex === nestRingHex(i), `ring ${i} keeps contract hue`);
    }
  }
}

const stillSunA = metalSunPose(1, true, true);
const stillSunB = metalSunPose(40, false, true);
assert(
  stillSunA.diameter === ARIA_MARK.orbDiameterIdle &&
    stillSunA.diameter === stillSunB.diameter &&
    stillSunA.sheenAngle === stillSunB.sheenAngle,
  "reduce-motion freezes the metal sun at idle diameter"
);
assert(metalSunPose(0, false, false).diameter === ARIA_MARK.orbDiameterIdle, "idle sun is 0.22");
assert(metalSunPose(0, true, false).diameter === ARIA_MARK.orbDiameterSpeaking, "speaking sun is 0.245");

nestLiveReset();
const compactId = nestLiveCreateId();
const homeId = nestLiveCreateId();
const chatId = nestLiveCreateId();
const speakId = nestLiveCreateId();
const noop = () => {};
nestLiveUpsert(compactId, { size: 24, speaking: false, visible: true, canLive: false, onChange: noop });
nestLiveUpsert(homeId, { size: 36, speaking: false, visible: true, canLive: true, onChange: noop });
assert(nestLiveWinnerId() === homeId && nestLiveIsWinner(homeId), "one live nest: mid beats compact");
nestLiveUpsert(chatId, { size: 56, speaking: false, visible: true, canLive: true, onChange: noop });
assert(nestLiveWinnerId() === chatId, "one live nest: larger mid wins");
nestLiveUpsert(speakId, { size: 36, speaking: true, visible: true, canLive: true, onChange: noop });
assert(nestLiveWinnerId() === speakId, "one live nest: speaking beats larger idle");
nestLiveUpsert(speakId, { size: 36, speaking: true, visible: false, canLive: true, onChange: noop });
assert(nestLiveWinnerId() === chatId, "hidden speaking nest yields the live slot");
nestLiveReset();

function parseAlpha(style: string): number | null {
  const m = /rgba\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*([0-9.]+)\s*\)/.exec(style);
  return m ? Number(m[1]) : null;
}

function mockCtx() {
  const strokes: string[] = [];
  const fills: string[] = [];
  let strokeStyle = "";
  let fillStyle: string | { addColorStop: () => void } = "";
  const gradient = {
    addColorStop(_offset: number, color: string) {
      fills.push(color);
    },
  };
  return {
    strokes,
    fills,
    get strokeStyle() {
      return strokeStyle;
    },
    set strokeStyle(value: string) {
      strokeStyle = value;
    },
    get fillStyle() {
      return fillStyle;
    },
    set fillStyle(value: string | { addColorStop: () => void }) {
      fillStyle = value;
      if (typeof value === "string") fills.push(value);
    },
    lineWidth: 0,
    lineCap: "butt",
    lineJoin: "miter",
    globalAlpha: 1,
    clearRect() {},
    save() {},
    restore() {},
    translate() {},
    rotate() {},
    scale() {},
    beginPath() {},
    closePath() {},
    moveTo() {},
    lineTo() {},
    arc() {},
    ellipse() {},
    fill() {},
    stroke() {
      if (typeof strokeStyle === "string") strokes.push(strokeStyle);
    },
    createRadialGradient: () => gradient,
    createLinearGradient: () => gradient,
  };
}

const heroProbe = mockCtx();
drawAriaNest(heroProbe as unknown as CanvasRenderingContext2D, 180, 180, {
  time: 1.4,
  speaking: true,
  reduceMotion: false,
  cssSize: 112,
});
assert(heroProbe.strokes.length === ARIA_MARK.ringCount, "hero nest strokes three rings");
for (const style of heroProbe.strokes) {
  const alpha = parseAlpha(style);
  assert(alpha !== null && alpha >= ARIA_MARK_CONTRAST_FLOOR, `hero contrast stroke stays ≥0.70 (${style})`);
}
assert(
  heroProbe.strokes.some((s) => s.includes("247, 244, 240")) &&
    heroProbe.strokes.some((s) => s.includes("169, 216, 255")) &&
    heroProbe.strokes.some((s) => s.includes("255, 77, 0")),
  "hero nest paints pearl / frost / orange"
);
assert(
  heroProbe.fills.some((s) => s.includes("58, 14, 18")),
  "hero nest may use hearth wash"
);

const compactProbe = mockCtx();
drawAriaNest(compactProbe as unknown as CanvasRenderingContext2D, 48, 48, {
  time: 2,
  speaking: false,
  reduceMotion: true,
  cssSize: 24,
});
assert(compactProbe.strokes.length === 3, "compact nest still draws three rings");
assert(
  compactProbe.fills.every((s) => !s.includes("58, 14, 18")),
  "compact nest skips hearth wash so it is never the silhouette"
);
for (const style of compactProbe.strokes) {
  const alpha = parseAlpha(style);
  assert(alpha !== null && alpha >= ARIA_MARK_CONTRAST_FLOOR, `compact contrast stroke stays ≥0.70 (${style})`);
}

const markSrc = readFileSync("src/components/brand/aria-mark.tsx", "utf8");
assert(markSrc.includes("drawAriaNest"), "AriaMark paints drawAriaNest");
assert(!markSrc.includes("drawAriaRingField"), "AriaMark retired the ring-field drawer");
assert(markSrc.includes("NEST_PAINT_INTERVAL_MS"), "AriaMark honors paintHz");

const nestSrc = readFileSync("src/lib/aria-nest.ts", "utf8");
assert(nestSrc.includes("strokeSoftHex"), "nest drawer strokes soft-hex paths");
assert(!/petal/i.test(nestSrc), "nest drawer has no flower-lobe geometry");
assert(!/#C9D2DC|#E8EEF4|#6B7CFF/i.test(nestSrc), "nest sun is pearl metal, not industrial chrome");
assert(!nestSrc.includes("drawAriaRingField"), "living drawer is nest, not ring-field");

const ringFieldSrc = readFileSync("src/lib/aria-ring-field.ts", "utf8");
assert(ringFieldSrc.includes("@deprecated"), "ring-field helpers are marked legacy");
assert(ringFieldSrc.includes("drawAriaNest"), "legacy ring-field shim calls the nest");

const splashSrc = readFileSync("src/app/page.tsx", "utf8");
const splashBody = splashSrc.slice(splashSrc.indexOf("function BootSplash"), splashSrc.indexOf("function TabPane"));
assert(splashBody.includes("AriaMark"), "splash shows the nest");
assert(splashBody.includes("ForgeWordmark"), "splash shows the FORGE wordmark");
assert(!splashBody.includes("This is ARIA"), "splash is mark+wordmark only");
assert(!splashBody.includes("radial-gradient"), "splash has no fire-under-logo");

const introSrc = readFileSync("src/components/brand/aria-intro.tsx", "utf8");
assert(introSrc.includes("ForgeWordmark"), "intro shows the FORGE wordmark");
assert(introSrc.includes("AriaMark"), "intro shows the nest");
assert(!introSrc.includes("radial-gradient"), "intro has no fire-under-logo theater");
assert(!introSrc.includes("255,106,26"), "intro dropped the ember wash under the mark");

const wordmarkSrc = readFileSync("src/components/brand/forge-wordmark.tsx", "utf8");
assert(wordmarkSrc.includes("wordmarkPrimaryMax"), "wordmark caps at 32");
assert(wordmarkSrc.includes("FORGE_WORDMARK"), "wordmark renders FORGE");

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

console.log("aria frontend checks passed");
