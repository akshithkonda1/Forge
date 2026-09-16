import type { CoachingStyle } from "@/types";

/** Friend-first tone. Same four CoachingStyle ids as iOS / api-contracts. */
export const ARIA_TONE_ORDER: CoachingStyle[] = [
  "balanced",
  "patient",
  "data-driven",
  "push-hard",
];

export const ARIA_TONES: Record<
  CoachingStyle,
  { title: string; line: string }
> = {
  balanced: {
    title: "Check-in",
    line: "I'll check in — trainer flavor when you want it, friend first.",
  },
  patient: {
    title: "Space",
    line: "I'll give you space and still be here.",
  },
  "data-driven": {
    title: "Patterns",
    line: "I'll notice patterns with you — not to judge.",
  },
  "push-hard": {
    title: "Honest peer",
    line: "I'll be an honest peer. Kind, and I won't flinch.",
  },
};

export type AriaMemoryFolder = "told" | "body" | "noticed";

export interface AriaMemoryNote {
  id: string;
  text: string;
  folder: AriaMemoryFolder;
  createdAt: string;
}

export const ARIA_MEMORY_FOLDERS: {
  id: AriaMemoryFolder;
  title: string;
  empty: string;
}[] = [
  {
    id: "told",
    title: "You told ARIA",
    empty: "Nothing you've asked her to keep.",
  },
  {
    id: "body",
    title: "From how you've been",
    empty: "No notes from sleep, energy, or how you felt.",
  },
  {
    id: "noticed",
    title: "ARIA noticed",
    empty: "No patterns saved yet.",
  },
];

export function memoryFolderTitle(folder: AriaMemoryFolder): string {
  return ARIA_MEMORY_FOLDERS.find((item) => item.id === folder)?.title ?? "Notes";
}

export const WEEKLY_CHECKIN_QUESTIONS: {
  id: string;
  prompt: string;
  hint: string;
}[] = [
  {
    id: "energy",
    prompt: "How has your energy been this week?",
    hint: "Low, mixed, or high — and what changed it.",
  },
  {
    id: "sleep",
    prompt: "How did you actually sleep?",
    hint: "Hours are optional. Quality and schedule matter more.",
  },
  {
    id: "body",
    prompt: "Anything hurting, lingering, or off?",
    hint: "Injuries, illness, cycle, stress. Empty is fine.",
  },
  {
    id: "focus",
    prompt: "What should next week be about?",
    hint: "Strength, recovery, consistency, or just showing up.",
  },
  {
    id: "remember",
    prompt: "Anything ARIA should remember?",
    hint: "A preference, a limit, a goal — only if you want.",
  },
  {
    id: "mood",
    prompt: "How has your mood actually been?",
    hint: "This week, not your whole life.",
  },
  {
    id: "social",
    prompt: "Did you want people around, or space?",
    hint: "Seeing family vs hiding out both count.",
  },
];

export const WEEKLY_CHECKIN_DUE_MS = 6 * 24 * 60 * 60 * 1000;

export function weeklyCheckInIsDue(
  lastCompletedAt: string | null,
  now = Date.now()
): boolean {
  if (!lastCompletedAt) return true;
  const stamp = Date.parse(lastCompletedAt);
  if (Number.isNaN(stamp)) return true;
  return now - stamp >= WEEKLY_CHECKIN_DUE_MS;
}

export function notesFromCheckIn(
  answers: Record<string, string>,
  now = new Date()
): AriaMemoryNote[] {
  const notes: AriaMemoryNote[] = [];
  const iso = now.toISOString();
  const stamp = now.getTime();
  const remember = answers.remember?.trim();
  if (remember) {
    notes.push({
      id: `chk-remember-${stamp}`,
      text: remember,
      folder: "told",
      createdAt: iso,
    });
  }
  const body = answers.body?.trim();
  if (body) {
    notes.push({
      id: `chk-body-${stamp}`,
      text: body,
      folder: "body",
      createdAt: iso,
    });
  }
  const mood = answers.mood?.trim();
  const energy = answers.energy?.trim();
  if (mood || energy) {
    const text = [energy && `Energy: ${energy}`, mood && `Mood: ${mood}`]
      .filter(Boolean)
      .join(" · ");
    notes.push({
      id: `chk-noticed-${stamp}`,
      text,
      folder: "noticed",
      createdAt: iso,
    });
  }
  return notes;
}

export const DEMO_ARIA_MEMORY: AriaMemoryNote[] = [
  {
    id: "demo-knee",
    text: "Left knee feels tender after long runs.",
    folder: "told",
    createdAt: "2026-09-10T12:00:00.000Z",
  },
  {
    id: "demo-sleep",
    text: "Later bedtimes when the week is stacked.",
    folder: "body",
    createdAt: "2026-09-12T12:00:00.000Z",
  },
];
