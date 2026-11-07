/** Local-only patterns, memory, and egress. Nothing here is posted. */

export type PatternNote = {
  id: string;
  title: string;
  evidence: string;
};

export type MemoryNote = {
  id: string;
  text: string;
};

export type EgressEvent = {
  id: string;
  at: string;
  what: string;
};

const MEMORY_KEY = "forge.on-device.memory";
const EGRESS_KEY = "forge.on-device.egress";

function readJson<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try {
    const raw = window.localStorage.getItem(key);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw) as T;
    return parsed ?? fallback;
  } catch {
    return fallback;
  }
}

function writeJson(key: string, value: unknown): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(key, JSON.stringify(value));
}

export function loadMemoryNotes(): MemoryNote[] {
  const rows = readJson<MemoryNote[]>(MEMORY_KEY, []);
  return Array.isArray(rows) ? rows.filter((row) => row && typeof row.text === "string") : [];
}

export function saveMemoryNotes(notes: MemoryNote[]): void {
  writeJson(MEMORY_KEY, notes);
}

export function loadEgressLog(): EgressEvent[] {
  const rows = readJson<EgressEvent[]>(EGRESS_KEY, []);
  return Array.isArray(rows) ? rows : [];
}

export function recordEgress(what: string): EgressEvent[] {
  const next = [
    { id: `e-${Date.now()}`, at: new Date().toISOString(), what },
    ...loadEgressLog(),
  ].slice(0, 20);
  writeJson(EGRESS_KEY, next);
  return next;
}

export function visiblePatterns(): PatternNote[] {
  // Web does not run the iOS pattern engine. Surface stays local and empty
  // until five on-device samples exist — same bar as AriaPersonalPatternEngine.
  return [];
}
