/**
 * Copy for the PR #472 frontend preview.
 * Strings are lockstep with ForgeTutorial, AriaInterviewVoice, AriaFirstBond,
 * AriaSoul, AriaFactPrivacy, ForgeExerciseDiscovery, and LifestyleSegment
 * on `cursor/fix-premium-refresh-breakage-3b09`.
 */
import { containsBannedPhrase } from "@/lib/design-tokens";
import { ARIA_TONES } from "@/lib/aria-companion";

export const SAMPLE_LABEL = "SAMPLE";
export const SAMPLE_PERSON = "Jordan Hale";
export const SAMPLE_FIRST = "Jordan";

export const MEET = {
  eyebrow: "Your lifestyle coach",
  title: "ARIA",
  lead: "Your lifestyle coach — built for the life you already have.",
  capabilities: [
    {
      title: "Train today",
      body: "What to do with the body you woke up with — not a plan from last week.",
    },
    {
      title: "Readiness",
      body: "Last night, load, and when to ease off before you overreach.",
    },
    {
      title: "What's in the way",
      body: "Talk. You don't have to know the question. I'll stay with it.",
    },
    {
      title: "Plans that fit",
      body: "I coach the life you already have — not a spreadsheet of you.",
    },
  ],
  talkCta: "Talk with ARIA",
  skipCta: "Look around first",
} as const;

export const HEALTH = {
  wrapper: "So I can keep up with you",
  body: "If you connect Apple Health, I can learn your sleep and movement with you — so I can take care of you better, not to judge.",
  hint: "Say ‘connect Health,’ ‘Calendar,’ ‘Contacts,’ ‘Reminders,’ or ‘later.’",
  continue: "Continue",
  skip: "Skip",
  later: "I’ll add it later",
  rows: [
    {
      id: "health",
      title: "Apple Health",
      subtitle: "Sleep and movement I can learn with you",
      status: "Connected",
    },
    {
      id: "calendar",
      title: "Apple Calendar",
      subtitle: "This week’s busy windows — never titles",
      status: "Connect",
    },
    {
      id: "contacts",
      title: "Contacts",
      subtitle: "First names you pick — never the whole book",
      status: "Connect",
    },
    {
      id: "reminders",
      title: "Reminders",
      subtitle: "Counts only — titles stay on this iPhone",
      status: "Connect",
    },
  ],
} as const;

export const HOW_ARE_YOU = {
  aria: `Ask me something true, ${SAMPLE_FIRST}. Sleep, training, how you show up — I’ll stay with it. Or come back later. This tab is ours.`,
  chips: [
    "How did I sleep?",
    "What should I train?",
    "How do I show up?",
    "I’ll come back.",
  ],
} as const;

export const TUTORIAL = {
  beginner: {
    welcome:
      "You downloaded Forge. I'll show you what I can actually do for you — no jargon. Home is the picture of your day. Tap Got it.",
    home: "Home is the picture of your day. Readiness, one next move. Glance — that's enough.",
    askAria: "Ask ARIA how you're doing. One question is enough. Light, adult, no quiz.",
  },
  competitor: {
    welcome:
      "You downloaded Forge. I'll walk the surfaces that keep load, sleep and the next session honest — not a sales pitch. Tap Got it.",
    home: "Home is the day's load picture: readiness, mosaic, the next honest session.",
    askAria:
      "Ask ARIA how you're doing. I'll keep it short and honest — how you live is the curriculum.",
  },
  gotIt: "Got it",
  skip: "Skip",
} as const;

export const PERSONALITIES = [
  { id: "coach", label: "Coach", pacing: "measured", tone: "even, adult, names the next move" },
  { id: "friend", label: "Friend", pacing: "unhurried", tone: "warm, wry, company not a pep rally" },
  {
    id: "drillSergeant",
    label: "Drill Sergeant",
    pacing: "short beats",
    tone: "blunt, snarky, standards without shame",
  },
] as const;

export const PERSONALITY_HINT = "Changes the next reply. No restart.";

export const MEMORY = {
  title: "Aria’s memory",
  privacy:
    "On this phone. Calendar titles, people on the invite, and places never land here. I don’t share this off-device.",
  rememberMe: "Remember me",
  rememberOn: "ARIA uses the notes below. Turn this off and I stop using them — nothing is deleted.",
  howITalk: "How I talk",
  howITalkLine: "Friend first. Not a clinician.",
  tones: ARIA_TONES,
  checkIns: "Check-ins",
  checkInValue: "A short daily hello",
  trainingModel: "Adaptive training model",
  trainingModelValue: "Intense physical and mental work — my own words, not a branded preset.",
  conditions: "Health conditions",
  conditionsValue: "On this phone. Skip was always fine.",
  conditionsNote: "Seizure-aware intensity ceiling. Lifestyle coaching only.",
} as const;

export const DISCOVERY = {
  suggest: "Here’s something new you could try with what you’ve got.",
  tried: "Tried",
  notInterested: "Not interested",
  save: "Save for later",
  move: "Landmine press",
  reason: "Fits unused catalog · Matches gym/gear · Readiness supports a new try",
} as const;

export const LIFESTYLE = {
  segments: ["Optimize", "Cook", "Places", "Nutrition", "Lifetime", "Wellbeing"] as const,
  title: "Lifestyle",
  subtitle: "Sleep, food, stress and people weighted for you. Movement is one tile, not the product.",
} as const;

export const MOSAIC = {
  label: "Today’s mosaic",
  headline: "74% · 4/5 tracks",
  ask: "Ask ARIA about this picture",
  tiles: [
    { track: "Sleep", headline: "7.2h", detail: "Last night", progress: 0.9, almost: false },
    { track: "Train", headline: "Upper", detail: "Session waiting", progress: 0.2, almost: false },
    { track: "Water", headline: "5", detail: "Almost there · 6 glasses", progress: 0.83, almost: true },
    { track: "Move", headline: "3.2k", detail: "Steps so far", progress: 0.4, almost: false },
    { track: "Habits", headline: "2", detail: "Marked today", progress: 0.66, almost: false },
  ],
} as const;

export const CHAT_SAMPLE = {
  user: "How am I doing?",
  aria: `${SAMPLE_FIRST} — readiness 82, last night rebuilt you. Upper Body Power still fits if we stay honest. One next move: start the session, or keep the day light. Lifestyle coaching only.`,
} as const;

/** Preview copy must stay on the coach rails. */
export function previewCopyViolations(blob: string): string[] {
  const hits: string[] = [];
  const banned = containsBannedPhrase(blob);
  if (banned) hits.push(banned);
  return hits;
}
