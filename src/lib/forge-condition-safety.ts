export const BANNED_SPEECH = [
  "seizure",
  "seizures",
  "medication",
  "medications",
  "prescription",
  "prescribe",
];

export type DeclaredCondition = "epilepsy" | "seizures" | "adhd" | "diabetes" | "other";

export type SafetyDecision = {
  blockedMoves: string[];
  keptMoves: string[];
  replacements: string[];
  flags: Array<"sleepLoss" | "heat">;
  changeNote: string;
  applied: boolean;
};

const NONE: SafetyDecision = {
  blockedMoves: [],
  keptMoves: [],
  replacements: [],
  flags: [],
  changeNote: "",
  applied: false,
};

export function containsBannedSpeech(text: string): boolean {
  const lower = text.toLowerCase();
  return BANNED_SPEECH.some((token) => lower.includes(token));
}

export function isSoloSwimOrClimb(name: string): boolean {
  const lower = name.toLowerCase();
  return ["swim", "swimming", "open water", "climb", "climbing", "boulder", "rope climb"].some(
    (token) => lower.includes(token)
  );
}

export function decideSafety(input: {
  declared: DeclaredCondition[];
  sleepHours?: number | null;
  heatRisk?: boolean;
  moveNames?: string[];
}): SafetyDecision {
  const declared = input.declared;
  if (!declared.length) return NONE;
  const epilepsy = declared.includes("epilepsy") || declared.includes("seizures");
  const blocked: string[] = [];
  const kept: string[] = [];
  const replacements: string[] = [];
  const flags: SafetyDecision["flags"] = [];
  for (const name of input.moveNames ?? []) {
    if (epilepsy && isSoloSwimOrClimb(name)) {
      blocked.push(name);
      const swap = replacementFor(name);
      if (swap) replacements.push(swap);
    } else {
      kept.push(name);
    }
  }
  if (epilepsy && input.sleepHours != null && input.sleepHours < 6.5) flags.push("sleepLoss");
  if (epilepsy && input.heatRisk) flags.push("heat");
  const changeNote = buildNote(blocked, replacements, flags);
  return {
    blockedMoves: blocked,
    keptMoves: kept,
    replacements,
    flags,
    changeNote,
    applied: blocked.length > 0 || flags.length > 0,
  };
}

function replacementFor(name: string): string | null {
  const lower = name.toLowerCase();
  if (lower.includes("swim") || lower.includes("pool") || lower.includes("open water")) {
    return "Easy pool-side mobility";
  }
  if (lower.includes("climb") || lower.includes("boulder")) {
    return "Floor strength circuit";
  }
  return null;
}

function buildNote(
  blocked: string[],
  replacements: string[],
  flags: SafetyDecision["flags"]
): string {
  const bits: string[] = [];
  if (blocked.length) {
    bits.push(
      replacements.length
        ? `A safety rule swapped ${blocked.join(" and ").toLowerCase()} for ${replacements.join(" and ").toLowerCase()}.`
        : `A safety rule removed ${blocked.join(" and ").toLowerCase()} from today's plan.`
    );
  }
  if (flags.includes("sleepLoss")) {
    bits.push("Last night ran short — keep intensity grounded.");
  }
  if (flags.includes("heat")) {
    bits.push("Heat is high — keep the session cooler and shorter.");
  }
  return bits.join(" ");
}
