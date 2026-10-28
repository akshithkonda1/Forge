export const MAX_REASON_WORDS = 25;
export const MAX_ACTIONS = 3;

export type Talkativeness = "quiet" | "balanced" | "chatty";

export type SafetyFlag = "sleepLoss" | "heat";

export type MorningNumbers = {
  sleepHours?: number | null;
  readiness?: number | null;
  calendarBusyHours?: number | null;
  habitCompletion?: number | null;
};

export type MorningCardInput = {
  numbers: MorningNumbers;
  previous?: MorningNumbers | null;
  gymLabel?: string;
  patternChanges?: string[];
  safetyChange?: string;
  safetyFlags?: SafetyFlag[];
  talkativeness?: Talkativeness;
  quietMode?: boolean;
  hasLifeSignal?: boolean;
};

export type MorningCard = {
  call: string;
  actions: string[];
  reason: string;
  speak: boolean;
  spokenLine: string;
  empty: boolean;
  patternLine: string;
  ruleLine: string;
};

export function wordCount(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

export function numberMoved(
  previous: MorningNumbers | null | undefined,
  current: MorningNumbers
): boolean {
  if (!previous) return false;
  if (delta(previous.sleepHours, current.sleepHours, 0.5)) return true;
  if (
    previous.readiness != null &&
    current.readiness != null &&
    Math.abs(previous.readiness - current.readiness) >= 8
  ) {
    return true;
  }
  if (delta(previous.calendarBusyHours, current.calendarBusyHours, 1.5)) return true;
  if (delta(previous.habitCompletion, current.habitCompletion, 0.25)) return true;
  return false;
}

export function shouldSpeak(opts: {
  moved: boolean;
  talkativeness: Talkativeness;
  quietMode: boolean;
}): boolean {
  if (opts.quietMode) return false;
  if (opts.talkativeness === "quiet") return false;
  return opts.moved;
}

export function buildMorningCard(input: MorningCardInput): MorningCard {
  const numbers = input.numbers;
  const talkativeness = input.talkativeness ?? "balanced";
  const quietMode = input.quietMode ?? false;
  const hasLife = input.hasLifeSignal ?? true;
  if (!hasLife && numbers.sleepHours == null && numbers.readiness == null) {
    return {
      call: "Nothing measured yet",
      actions: ["Open Sleep after tonight", "Or train from your gym setup"],
      reason: "Need a night of sleep or a session to write today's call.",
      speak: false,
      spokenLine: "",
      empty: true,
      patternLine: "",
      ruleLine: "",
    };
  }

  const flags = input.safetyFlags ?? [];
  const call = dayCall(numbers, flags, input.gymLabel ?? "");
  const actions = uniqued(dayActions(input, flags)).slice(0, MAX_ACTIONS);
  const reason = clip(reasonLine(input), MAX_REASON_WORDS);
  const moved = numberMoved(input.previous, numbers);
  const speak = shouldSpeak({ moved, talkativeness, quietMode });
  const spokenLine = speak
    ? talkativeness === "chatty"
      ? `Hey — ${call.toLowerCase()}. ${reason}`
      : `${call}. ${reason}`
    : "";
  return {
    call,
    actions,
    reason,
    speak,
    spokenLine,
    empty: false,
    patternLine: input.patternChanges?.[0] ?? "",
    ruleLine: input.safetyChange ?? "",
  };
}

function dayCall(numbers: MorningNumbers, flags: SafetyFlag[], gymLabel: string): string {
  if (flags.includes("heat")) return "Keep it cool and short";
  if (flags.includes("sleepLoss")) return "Easy session";
  if (numbers.sleepHours != null && numbers.sleepHours < 6.5) return "Easy session";
  if ((numbers.calendarBusyHours ?? 0) >= 4) return "One small win";
  if (numbers.readiness != null && numbers.readiness < 55) return "Easy session";
  if (gymLabel) return `Train at ${gymLabel}`;
  return "Do the next honest session";
}

function dayActions(input: MorningCardInput, flags: SafetyFlag[]): string[] {
  const actions: string[] = [];
  const first = input.patternChanges?.[0];
  if (first) actions.push(first);
  if (flags.includes("sleepLoss")) actions.push("Keep today's session grounded");
  if (flags.includes("heat")) actions.push("Train cooler, stop early if you heat up");
  if (actions.length === 0) {
    if (input.numbers.sleepHours != null && input.numbers.sleepHours < 6.5) {
      actions.push("Shorter session, same structure");
    } else if (input.gymLabel) {
      actions.push(`Use ${input.gymLabel.toLowerCase()} as written`);
    } else {
      actions.push("Start the session already on Home");
    }
  }
  if ((input.numbers.calendarBusyHours ?? 0) >= 4) {
    actions.push("Protect one habit check-in");
  }
  if (actions.length < 2) actions.push("Drink water with the session");
  return actions;
}

function reasonLine(input: MorningCardInput): string {
  const bits: string[] = [];
  if (input.numbers.sleepHours != null) {
    bits.push(`${input.numbers.sleepHours.toFixed(1)} hours last night`);
  }
  if (input.numbers.readiness != null) {
    bits.push(`readiness ${input.numbers.readiness}`);
  }
  if ((input.numbers.calendarBusyHours ?? 0) >= 1) {
    bits.push(`${input.numbers.calendarBusyHours?.toFixed(0)} hours on the calendar`);
  }
  if (input.numbers.habitCompletion != null) {
    bits.push(`habits at ${Math.round(input.numbers.habitCompletion * 100)}%`);
  }
  if (bits.length === 0) return "Built from the gym you named and today's plan.";
  if (input.gymLabel) {
    return `${bits.join(", ")}, so this fits ${input.gymLabel.toLowerCase()}.`;
  }
  return `${bits.join(", ")}, so the day stays honest.`;
}

function clip(text: string, max: number): string {
  const words = text.split(/\s+/).filter(Boolean);
  return words.slice(0, max).join(" ");
}

function delta(a?: number | null, b?: number | null, threshold = 0): boolean {
  if (a == null || b == null) return false;
  return Math.abs(a - b) >= threshold;
}

function uniqued(items: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const item of items) {
    const key = item.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(item);
  }
  return out;
}
