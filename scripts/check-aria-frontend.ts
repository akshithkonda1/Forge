import { coachReply } from "../src/lib/aria-coach.ts";
import { ARIA_CINEMATIC_LINES, firstSessionScript, whisperForStep } from "../src/lib/aria-onboarding.ts";
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
