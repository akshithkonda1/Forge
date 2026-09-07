import { existsSync, readFileSync } from "node:fs";
import { coachReply } from "../src/lib/aria-coach.ts";
import { ARIA_CINEMATIC_LINES, firstSessionScript, whisperForStep } from "../src/lib/aria-onboarding.ts";
import { ARIA_LOBES, ARIA_MARK, clampGaze, emberCoreRadius, emberLobe } from "../src/lib/aria-mark.ts";
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
assert(ARIA_MARK.assetName === "AriaLogo", "ARIA mark asset is AriaLogo");
assert(ARIA_MARK.assetName === contract.assetName, "web assetName matches shared/aria-mark.json");
assert(ARIA_MARK.cropScale === 1, "ember mark is not zoom-cropped past a ring");
assert(ARIA_MARK.cropScale === contract.cropScale, "web cropScale matches shared/aria-mark.json");
assert(ARIA_MARK.lobeCount === 4, "living ember has four lobes");
assert(ARIA_MARK.lobeCount === contract.lobeCount, "web lobeCount matches shared/aria-mark.json");
assert(ARIA_LOBES.length === ARIA_MARK.lobeCount, "lobe table matches lobeCount");
assert(ARIA_MARK.idleBreathHz === contract.idleBreathHz, "web idle breath matches shared/aria-mark.json");
assert(ARIA_MARK.speakingBreathHz === contract.speakingBreathHz, "web speaking breath matches shared/aria-mark.json");
assert(ARIA_MARK.maxGaze === 0.14, "gaze stays inside the mark");
assert(ARIA_MARK.maxGaze === contract.maxGaze, "web maxGaze matches shared/aria-mark.json");
assert(ARIA_MARK.stillPose === contract.stillPose, "web stillPose matches shared/aria-mark.json");
assert(existsSync("public/aria-mark.png"), "still-frame web ARIA mark asset is present");
assert(existsSync("shared/brand/aria-mark.png"), "still-frame shared ARIA mark asset is present");

const stillA = emberLobe(0, 1, false, true);
const stillB = emberLobe(0, 99, true, true);
assert(stillA.x === stillB.x && stillA.y === stillB.y && stillA.r === stillB.r, "reduce-motion freezes lobes");
assert(emberCoreRadius(1, true, true) === emberCoreRadius(40, false, true), "reduce-motion freezes the core");
assert(emberCoreRadius(0.4, true, false) > emberCoreRadius(0.4, false, false), "speaking core is larger");
assert(clampGaze(1) === ARIA_MARK.maxGaze && clampGaze(-1) === -ARIA_MARK.maxGaze, "gaze is clamped");
const liveA = emberLobe(1, 0.4, false, false);
const liveB = emberLobe(1, 1.1, false, false);
assert(liveA.x !== liveB.x || liveA.y !== liveB.y || liveA.r !== liveB.r, "idle lobes move when alive");

assert(ARIA_CINEMATIC_LINES.length === 1, "welcome is one beat");

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
