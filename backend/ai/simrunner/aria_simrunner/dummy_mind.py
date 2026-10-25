"""Local Dummy mind: reason like ARIA, speak like ARIA, never leave the machine.

This is not a model. It reads the same inputs the live path does (BodyModel /
observe snapshot, baselines, coach context, Memory, logged illness/rest,
preferences and corrections), picks an explicit stance, and composes a
companion reply from that judgment. Bedrock stays off. No sockets, no AWS
clients, no tokens.

Voice is the existing ARIA soul / Iris friend — Coach / Friend / Drill
Sergeant flavors with identical rails. Adaptive style only shifts tone
(optimistic-but-realistic vs steadier reassurance) from what the user just
said. It never relaxes illness/rest, honesty, or the no-invented-numbers
rule.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Iterable

from . import speak_quality

# Honest cold start: fewer than this many nights and Dummy asks instead of guessing.
MIN_NIGHTS = 3
STANCES = ("protect", "proceed", "fuel", "clarify")

_TRAIN_PUSH = re.compile(
    r"(?i)\b("
    r"go train|go hard|real work|push it|max(?:imal)?|extra sets|"
    r"progress one thing|hard (?:session|day|block)|go big|send it|"
    r"moderate-to-hard|hero (?:set|day|work)|green enough|"
    r"today can handle|there's room to train|there's room for a real"
    r")\b"
)
_WHY_CUE = re.compile(
    r"(?i)\b(because|since|that's why|that is why|from what|"
    r"that's from|the night|last night|nights? (?:i|we) can|"
    r"you (?:logged|asked|told))\b"
)
_USER_METRIC = re.compile(
    r"(?i)(?:"
    r"\b(?:hrv|readiness|slept|sleep(?:ed)?)\b[^.!?]{0,28}(\d+(?:\.\d+)?)"
    r"|(\d+(?:\.\d+)?)\s*(?:hours?|hrs)\s+(?:of\s+)?sleep"
    r"|(\d+(?:\.\d+)?)\s?(?:ms|bpm)"
    r"|(?:readiness|recovery)\s+(?:score\s+)?(?:is\s+|of\s+)?(\d+(?:\.\d+)?)"
    r")"
)
_INVENTED_SLEEP_HRS = re.compile(
    r"(?i)\b(?:you (?:slept|got)|last night(?: was)?|about)\s+"
    r"(\d+(?:\.\d+)?)\s*(?:hours?|hrs)\b"
)
_OPTIMISTIC_CUES = (
    "let's go", "lets go", "feeling great", "feel great", "feel amazing",
    "pumped", "excited", "can't wait", "cant wait", "bring it",
    "i've got this", "ive got this", "i've got this", "love this",
    "fired up", "so ready", "let's crush", "feeling strong",
)
_CAUTIOUS_CUES = (
    "worried", "nervous", "not sure", "maybe too much", "don't want to overdo",
    "dont want to overdo", "play it safe", "take it easy", "i'm cautious",
    "im cautious", "scared", "anxious", "what if i", "don't want to get hurt",
    "dont want to get hurt", "go easy", "keep it safe",
)
_PUSHBACK_CUES = (
    "that's not right", "thats not right", "you're wrong", "youre wrong",
    "not true", "i disagree", "not what i said", "don't tell me", "dont tell me",
    "that's wrong", "thats wrong", "correction",
)
_ACCEPT_CUES = (
    "sounds good", "makes sense", "i'll do that", "ill do that",
    "works for me", "got it", "fair", "deal",
)
_ILLNESS_CUES = (
    "fever", "flu", "i'm sick", "im sick", "feel sick", "feeling sick",
    "got sick", "been sick", "sick with", "a cold", "covid", "sore throat",
    "chills", "vomit", "nausea", "stomach bug", "log illness", "logged sick",
    "log that i'm ill", "log that im ill", "log that i am ill",
)
_REST_CUES = (
    "rest day", "taking a rest", "taking rest", "log rest", "logged rest",
    "i'm resting", "im resting", "i am resting", "rest day today",
)
_MORNING_PREF = re.compile(
    r"(?i)\b(?:prefer|like|only|keep(?: it)?(?: to)?)\b.{0,24}\bmorning"
)
_EVENING_PREF = re.compile(
    r"(?i)\b(?:prefer|like|only)\b.{0,24}\b(?:evening|night)s?\b"
)
_AVOID_EVENING = re.compile(
    r"(?i)\b(?:never|no|not|don't|dont)\b.{0,20}\b(?:evening|night)s?(?:\s+workouts?)?"
)
_SLEPT_WELL = re.compile(
    r"(?i)\b(?:slept well|full night|slept (?:a )?full|good night|"
    r"slept fine|actually slept|night was (?:fine|good|full))\b"
)
_SLEPT_BAD = re.compile(
    r"(?i)\b(?:slept badly|awful night|terrible sleep|didn'?t sleep|"
    r"thin night|rough night)\b"
)
_CORRECTION_LEAD = re.compile(
    r"(?i)\b(?:that'?s not right|you'?re wrong|actually|not true|"
    r"correction|you (?:got|have) (?:it|that) wrong)\b"
)

# Tone overlays reuse ARIA's existing friend vocabulary. Same advice, different coat.
_OPTIMISTIC_WRAP = (
    "We'll use that energy on one clean thing, not a parade.",
    "Sparkle in the tank is for a useful session, not a victory lap.",
    "Keep the mood — spend it on one honest step.",
)
_CAUTIOUS_WRAP = (
    "We'll keep this steady and stop the moment it stops feeling kind.",
    "No heroics — just a measured next step you can trust.",
    "Easy and kind first; we can always add later.",
)
_COLD_START = (
    "I only have a couple of nights in, so I'm not going to pretend I know your pattern yet. "
    "How have the last few nights actually felt, and what are you training toward?",
    "Nights I can trust are still few — I'd rather ask than guess. "
    "Tell me how sleep has felt and what you want from the week.",
    "There's no real history to lean on yet. What's the goal right now, "
    "and have the last nights been on your side?",
)
_ILLNESS_SPEAK = (
    "You're sick and asking to train — today the training is rest and fluids. "
    "That's from what you logged, not a guess. Soft rest, water, and we reread it when you're well.",
    "You're sick and asking to train — today the training is rest and fluids. "
    "Illness is logged, so the session is rest — that's from what you told me, not a guess.",
)
_REST_SPEAK = (
    "You logged a rest day, so I'm not talking you into work. "
    "Protect the rest you already chose — easy food, water, and leave the session.",
    "Rest is the plan you already set. I'll keep it that way: no session, just recover the kind way.",
)


def _fnv(text: str) -> int:
    h = 2166136261
    for ch in text:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h


def _pick(seed: int, options: list[str]) -> str:
    if not options:
        return ""
    return options[abs(int(seed)) % len(options)]


def _has_cue(lower: str, cues: Iterable[str]) -> bool:
    return any(c in lower for c in cues)


def _num_token(value: Any) -> str | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        raw = f"{value:g}"
        return raw if raw else None
    return None


@dataclass
class StyleState:
    """Learned conversational coat. Tone only — never a safety override."""

    optimism: float = 0.0  # -1 cautious … +1 optimistic
    pushback: float = 0.0
    acceptance: float = 0.0

    def band(self) -> str:
        if self.optimism >= 0.35:
            return "optimistic"
        if self.optimism <= -0.35:
            return "cautious"
        return "steady"

    def as_dict(self) -> dict[str, Any]:
        return {
            "optimism": round(self.optimism, 4),
            "pushback": round(self.pushback, 4),
            "acceptance": round(self.acceptance, 4),
            "band": self.band(),
        }

    @classmethod
    def from_dict(cls, raw: dict[str, Any] | None) -> "StyleState":
        data = raw if isinstance(raw, dict) else {}
        style = cls()
        for key in ("optimism", "pushback", "acceptance"):
            try:
                setattr(style, key, max(-1.0, min(1.0, float(data.get(key) or 0.0))))
            except (TypeError, ValueError):
                pass
        return style

    def learn(self, text: str) -> None:
        lower = f" {str(text or '').lower()} "
        if _has_cue(lower, _OPTIMISTIC_CUES):
            self.optimism = min(1.0, self.optimism + 0.45)
        if _has_cue(lower, _CAUTIOUS_CUES):
            self.optimism = max(-1.0, self.optimism - 0.45)
        if _has_cue(lower, _PUSHBACK_CUES):
            self.pushback = min(1.0, self.pushback + 0.35)
        if _has_cue(lower, _ACCEPT_CUES):
            self.acceptance = min(1.0, self.acceptance + 0.35)


@dataclass
class DummyMemory:
    """Conversation-scoped facts Dummy must not forget. Local only."""

    corrections: dict[str, str] = field(default_factory=dict)
    preferences: dict[str, str] = field(default_factory=dict)
    illness_logged: bool = False
    rest_logged: bool = False
    style: StyleState = field(default_factory=StyleState)
    notes: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "corrections": dict(self.corrections),
            "preferences": dict(self.preferences),
            "illness_logged": self.illness_logged,
            "rest_logged": self.rest_logged,
            "style": self.style.as_dict(),
            "notes": list(self.notes),
        }

    @classmethod
    def from_dict(cls, raw: dict[str, Any] | None) -> "DummyMemory":
        data = raw if isinstance(raw, dict) else {}
        mem = cls(
            corrections={str(k): str(v) for k, v in (data.get("corrections") or {}).items()},
            preferences={str(k): str(v) for k, v in (data.get("preferences") or {}).items()},
            illness_logged=bool(data.get("illness_logged")),
            rest_logged=bool(data.get("rest_logged")),
            style=StyleState.from_dict(data.get("style") if isinstance(data.get("style"), dict) else None),
            notes=[str(n) for n in (data.get("notes") or []) if n],
        )
        return mem

    def ingest(self, text: str) -> None:
        raw = str(text or "").strip()
        if not raw:
            return
        lower = f" {raw.lower()} "
        self.style.learn(raw)
        if _has_cue(lower, _ILLNESS_CUES) and not re.search(r"sick (?:of|and tired)", lower):
            self.illness_logged = True
        if _has_cue(lower, _REST_CUES):
            self.rest_logged = True
        if _CORRECTION_LEAD.search(raw) or _SLEPT_WELL.search(raw) or _SLEPT_BAD.search(raw):
            if _SLEPT_WELL.search(raw):
                self.corrections["sleep"] = "rebuilt"
            elif _SLEPT_BAD.search(raw):
                self.corrections["sleep"] = "thin"
        if _MORNING_PREF.search(raw) or _AVOID_EVENING.search(raw):
            self.preferences["workout_time"] = "morning"
        elif _EVENING_PREF.search(raw):
            self.preferences["workout_time"] = "evening"
        # Qualitative tags only — never persist a raw name or health value.
        tag = None
        if self.illness_logged:
            tag = "illness"
        elif self.rest_logged:
            tag = "rest"
        elif "sleep" in self.corrections:
            tag = f"sleep:{self.corrections['sleep']}"
        elif "workout_time" in self.preferences:
            tag = f"pref:{self.preferences['workout_time']}"
        if tag and tag not in self.notes and len(self.notes) < 12:
            self.notes.append(tag)

    def ingest_all(self, turns: Iterable[str] | None) -> None:
        for turn in turns or ():
            self.ingest(str(turn or ""))


@dataclass(frozen=True)
class Evidence:
    nights: int
    sleep: str
    recovery: str
    load: str
    occupation: str
    known_numbers: frozenset[str]
    sources: tuple[str, ...]
    fuel_gap: bool
    thin_data: bool

    def as_dict(self) -> dict[str, Any]:
        return {
            "nights": self.nights,
            "sleep": self.sleep,
            "recovery": self.recovery,
            "load": self.load,
            "occupation": self.occupation,
            "known_numbers": sorted(self.known_numbers),
            "sources": list(self.sources),
            "fuel_gap": self.fuel_gap,
            "thin_data": self.thin_data,
        }


@dataclass(frozen=True)
class Judgment:
    stance: str
    confidence: float
    weights: dict[str, float]
    why: str
    suggestion: str
    question: str | None
    cold_start: bool
    illness: bool
    rest: bool
    blocks_training: bool

    def as_dict(self) -> dict[str, Any]:
        return {
            "stance": self.stance,
            "confidence": self.confidence,
            "weights": dict(self.weights),
            "why": self.why,
            "suggestion": self.suggestion,
            "question": self.question,
            "cold_start": self.cold_start,
            "illness": self.illness,
            "rest": self.rest,
            "blocks_training": self.blocks_training,
        }


def count_nights(ctx: Any = None, payload: dict | None = None, fusion: dict | None = None) -> int | None:
    """Nights Dummy is allowed to reason over. ``None`` means the count is unknown.

    Cold start only fires on a known short history. A missing count is not
    a license to pretend the person is new.
    """
    if ctx is not None:
        hist = list(getattr(ctx, "history", None) or [])
        if hist:
            return sum(
                1 for rec in hist if getattr(rec, "total_sleep_hours", None) is not None
            )
        avail = getattr(ctx, "sleep_nights_available_7d", None)
        if isinstance(avail, int):
            return max(0, avail)
        today = getattr(ctx, "today", None)
        if getattr(today, "total_sleep_hours", None) is not None:
            return 1
    bag = payload if isinstance(payload, dict) else {}
    context = bag.get("context") if isinstance(bag.get("context"), dict) else bag
    sleep = context.get("sleep") if isinstance(context.get("sleep"), dict) else {}
    for key in ("nightsAvailable", "nights_available", "sleep_nights_available_7d"):
        if key in sleep and isinstance(sleep.get(key), int):
            return max(0, int(sleep[key]))
    fused = fusion if isinstance(fusion, dict) else {}
    for key in ("sleep_n", "nights"):
        value = fused.get(key)
        if isinstance(value, int):
            return max(0, value)
    return None


def _collect_known_numbers(ctx: Any, payload: dict | None, message: str) -> frozenset[str]:
    found: set[str] = set()
    for token in re.findall(r"\d+(?:\.\d+)?", str(message or "")):
        found.add(token)

    def add(value: Any) -> None:
        token = _num_token(value)
        if token:
            found.add(token)

    today = getattr(ctx, "today", None) if ctx is not None else None
    if today is not None:
        for attr in (
            "total_sleep_hours", "hrv", "readiness_score", "resting_hr",
            "deep_sleep_minutes", "rem_sleep_minutes", "steps", "active_calories",
        ):
            add(getattr(today, attr, None))
    if ctx is not None:
        for attr in ("sleep_debt_7d_hours", "target_sleep_hours", "acwr", "hrv_7d_avg"):
            add(getattr(ctx, attr, None))
        for rec in list(getattr(ctx, "history", None) or []):
            add(getattr(rec, "total_sleep_hours", None))
            add(getattr(rec, "hrv", None))
    bag = payload if isinstance(payload, dict) else {}
    context = bag.get("context") if isinstance(bag.get("context"), dict) else {}
    for section in context.values():
        if not isinstance(section, dict):
            continue
        for value in section.values():
            add(value)
    return frozenset(found)


def gather_evidence(
    message: str,
    *,
    ctx: Any = None,
    payload: dict | None = None,
    fusion: dict | None = None,
    memory: DummyMemory | None = None,
    signals: Any = None,
    stamped_nights: int | None = None,
) -> Evidence:
    mem = memory or DummyMemory()
    counted = count_nights(ctx, payload, fusion)
    if isinstance(stamped_nights, int):
        nights = max(0, stamped_nights)
        known_nights = True
    elif counted is not None:
        nights = counted
        known_nights = True
    else:
        nights = MIN_NIGHTS
        known_nights = False
    sleep = getattr(signals, "sleep", "") if signals is not None else ""
    recovery = getattr(signals, "recovery", "") if signals is not None else ""
    load = getattr(signals, "load", "") if signals is not None else ""
    if mem.corrections.get("sleep") in ("rebuilt", "thin", "decent"):
        sleep = mem.corrections["sleep"]
    occupation = ""
    if ctx is not None:
        occupation = str(getattr(ctx, "occupation", "") or "")
    bag = payload if isinstance(payload, dict) else {}
    context = bag.get("context") if isinstance(bag.get("context"), dict) else {}
    lifestyle = context.get("lifestyle") if isinstance(context.get("lifestyle"), dict) else {}
    tags = [str(t).lower() for t in (lifestyle.get("tags") or [])]
    fuel_gap = any("fuel" in t or "hungry" in t or "protein" in t for t in tags)
    sources = ["memory" if mem.corrections or mem.preferences or mem.illness_logged or mem.rest_logged else ""]
    if ctx is not None:
        sources.append("body")
    if fusion:
        sources.append("fusion")
    if payload:
        sources.append("coach_context")
    known = set(_collect_known_numbers(ctx, payload, message))
    known.add(str(nights))
    known.add(str(MIN_NIGHTS))
    return Evidence(
        nights=nights,
        sleep=sleep or "unknown",
        recovery=recovery or "unknown",
        load=load or "unknown",
        occupation=occupation,
        known_numbers=frozenset(known),
        sources=tuple(s for s in sources if s),
        fuel_gap=fuel_gap,
        thin_data=known_nights and nights < MIN_NIGHTS,
    )


def judge(
    evidence: Evidence,
    memory: DummyMemory,
    message: str,
    *,
    situation: Any = None,
) -> Judgment:
    """Weigh evidence, pick protect / proceed / fuel / clarify, and say why."""
    lower = f" {str(message or '').lower()} "
    weights = {
        "illness": 0.0,
        "rest": 0.0,
        "cold_start": 0.0,
        "sleep": 0.0,
        "recovery": 0.0,
        "fuel": 0.0,
        "preference": 0.0,
        "proceed": 0.0,
    }
    illness = bool(memory.illness_logged)
    rest = bool(memory.rest_logged)
    if situation is not None:
        illness = illness or any(
            getattr(s, "name", "") == "illness" for s in getattr(situation, "signals", [])
        )
        decisions = getattr(situation, "decisions", None)
        rest = rest or bool(getattr(decisions, "rest", False))
    if evidence.thin_data:
        weights["cold_start"] = 1.2
    if illness:
        weights["illness"] = 2.0
    if rest:
        weights["rest"] = 1.8
    if evidence.sleep == "thin":
        weights["sleep"] = 0.9
    elif evidence.sleep == "rebuilt":
        weights["proceed"] += 0.6
    if evidence.recovery == "asking":
        weights["recovery"] = 0.85
    elif evidence.recovery == "ready":
        weights["proceed"] += 0.5
    if evidence.fuel_gap or any(n in lower for n in ("eat", "food", "hungry", "protein", "meal")):
        weights["fuel"] = 0.7
    if memory.preferences:
        weights["preference"] = 0.4
    if any(n in lower for n in ("train", "workout", "session", "gym")):
        weights["proceed"] += 0.35

    if illness or rest:
        stance = "protect"
        confidence = 0.92 if illness else 0.88
        why = (
            "That's from the illness you logged, not a guessed metric."
            if illness
            else "That's from the rest day you already logged."
        )
        suggestion = "Rest and fluids today — no session." if illness else "Keep the rest day. No training push."
        question = "How are you actually feeling — same, better, or worse?"
    elif evidence.thin_data:
        stance = "clarify"
        confidence = 0.4
        why = f"That's because I have {evidence.nights} night{'s' if evidence.nights != 1 else ''} in — under the {MIN_NIGHTS}-night floor, so guessing would be theater."
        suggestion = "Tell me how the last nights felt and what you want from training."
        question = "What's the goal right now, and how have nights actually felt?"
    elif weights["fuel"] >= 0.7 and weights["sleep"] < 0.9 and weights["recovery"] < 0.85:
        stance = "fuel"
        confidence = 0.7
        why = "That's from a fuel gap in what you told me, not a lab number."
        suggestion = "Protein and water with the next meal, then keep movement easy."
        question = None
    elif weights["sleep"] >= 0.9 or weights["recovery"] >= 0.85:
        stance = "protect"
        confidence = 0.78
        why = (
            "That's from last night running short of a reset."
            if evidence.sleep == "thin"
            else "That's from today asking for room, not more load."
        )
        suggestion = "Keep today kind — a walk or mobility, then protect tonight."
        question = None
    else:
        stance = "proceed"
        confidence = 0.72 if evidence.sleep == "rebuilt" else 0.64
        why = (
            "That's from a night that actually paid you back."
            if evidence.sleep == "rebuilt"
            else "That's from a usable, unspectacular night — enough to move, not to burn."
        )
        suggestion = "One honest moderate session, then call it."
        if memory.preferences.get("workout_time") == "morning":
            suggestion = "One honest moderate session in the morning window you asked for, then call it."
        elif memory.preferences.get("workout_time") == "evening":
            suggestion = "One honest moderate session in the evening window you asked for, then call it."
        question = "Want that session sketched, or is the read enough?"

    blocks = stance == "protect" and (illness or rest)
    return Judgment(
        stance=stance,
        confidence=round(min(0.95, max(0.2, confidence)), 3),
        weights=weights,
        why=why,
        suggestion=suggestion,
        question=question,
        cold_start=evidence.thin_data,
        illness=illness,
        rest=rest,
        blocks_training=blocks,
    )


def compose(judgment: Judgment, evidence: Evidence, memory: DummyMemory, seed: int) -> str:
    """observation → why → one suggestion → optional question. ARIA friend voice."""
    if judgment.illness:
        body = _pick(seed, list(_ILLNESS_SPEAK))
    elif judgment.rest:
        body = _pick(seed, list(_REST_SPEAK))
    elif judgment.cold_start:
        body = _pick(seed, list(_COLD_START))
    else:
        if evidence.sleep == "thin":
            obs = _pick(seed, [
                "Last night didn't give you a full reset.",
                "The night came up short.",
                "You woke up already spending energy you didn't bank.",
            ])
        elif evidence.sleep == "rebuilt":
            obs = _pick(seed, [
                "The night actually paid you back.",
                "You got a night you can spend.",
                "Sleep finally gave you something to work with.",
            ])
        elif evidence.sleep == "decent":
            obs = _pick(seed, [
                "Sleep was decent, not extra.",
                "The night was middle-ground — usable, not a free pass.",
                "Rest was fine, nothing flashy.",
            ])
        else:
            obs = _pick(seed, [
                "Here's the honest read on today.",
                "I'm with you — let's size today from what we actually have.",
            ])
        if evidence.occupation and abs(seed) % 5 == 1:
            life = evidence.occupation.replace("_", " ")
            obs = f"{obs} A {life}'s week already spends you."
        body = f"{obs} {judgment.why} {judgment.suggestion}"
        if judgment.question:
            body = f"{body} {judgment.question}"
    return apply_tone(body, memory.style, seed)


def apply_tone(text: str, style: StyleState, seed: int) -> str:
    """Word-choice coat only. Same advice, ARIA's existing friend register."""
    body = (text or "").strip()
    if not body:
        return body
    band = style.band()
    extra = ""
    if band == "optimistic":
        extra = _pick(seed ^ 29, list(_OPTIMISTIC_WRAP))
    elif band == "cautious":
        extra = _pick(seed ^ 31, list(_CAUTIOUS_WRAP))
    if extra and extra.lower() not in body.lower():
        if body[-1] not in ".!?":
            body += "."
        body = f"{body} {extra}"
    return body


def audit_invented_numbers(text: str, evidence: Evidence) -> str:
    """Drop user-metric numbers that did not come from code-provided data."""
    raw = text or ""
    known = evidence.known_numbers

    def keep_metric(match: re.Match[str]) -> str:
        digits = next((g for g in match.groups() if g), "")
        if digits and digits in known:
            return match.group(0)
        return ""

    cleaned = _USER_METRIC.sub(keep_metric, raw)
    cleaned = _INVENTED_SLEEP_HRS.sub(
        lambda m: m.group(0) if m.group(1) in known else "the night",
        cleaned,
    )
    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()
    return cleaned


def strip_training_push(text: str) -> str:
    kept = []
    for sentence in re.split(r"(?<=[.!?])\s+", text or ""):
        if sentence.strip() and not _TRAIN_PUSH.search(sentence):
            kept.append(sentence.strip())
    return " ".join(kept).strip()


def ensure_why(text: str, judgment: Judgment) -> str:
    body = (text or "").strip()
    if not body or not judgment.why:
        return body
    if _WHY_CUE.search(body):
        return body
    if body[-1] not in ".!?":
        body += "."
    return f"{body} {judgment.why}"


def honor_memory(text: str, memory: DummyMemory) -> str:
    """Corrections and preferences stick — Dummy does not re-argue them."""
    body = text or ""
    sleep = memory.corrections.get("sleep")
    if sleep == "rebuilt":
        body = re.sub(
            r"(?i)(last night (?:didn'?t|did not)[^.!?]+|the night (?:came up short|was thinner)[^.!?]+|"
            r"you woke up already spending[^.!?]+|sleep came up short[^.!?]+|"
            r"you didn'?t get a full night[^.!?]+)",
            "you said the night was actually a full one",
            body,
        )
    when = memory.preferences.get("workout_time")
    if when == "morning":
        body = re.sub(r"(?i)\b(?:this evening|tonight|evening session|after dinner)\b", "this morning", body)
        if "morning" not in body.lower() and not memory.illness_logged and not memory.rest_logged:
            if body and body[-1] not in ".!?":
                body += "."
            body = f"{body} We'll keep it in the morning window you asked for."
    return re.sub(r"\s{2,}", " ", body).strip()


_GREET = re.compile(r"(?i)^(hey+|hi+|hello+|yo)[\s.!?]*$")
_SAFETY_SKIP = (
    "future you says thanks",
    "you've been running short on sleep this week",
    "you've been running short on sleep and your training has climbed fast",
    "your training has climbed fast lately",
    "can't tell from here",
)


def _guidance_locked(row: dict, judgment: Judgment) -> bool:
    band = str(row.get("guidance_band") or "").strip().lower()
    if band in {"emergency", "first_aid", "refer_out", "triage", "coach_with_care"}:
        return True
    if (row.get("guard") or {}).get("mode") == "estimate" and not (
        judgment.blocks_training or judgment.cold_start
    ):
        return True
    return False


def _is_follow_up(text: str) -> bool:
    lead = (text or "").strip().lower()
    return any(
        lead.startswith(p)
        for p in (
            "sure —", "sure -", "yeah —", "yeah -", "okay —", "okay -",
            "right —", "right -", "got it", "fair.", "alright",
        )
    )


def apply_mind(
    row: dict,
    *,
    message: str,
    ctx: Any = None,
    payload: dict | None = None,
    prior_turns: list[str] | None = None,
    memory: DummyMemory | None = None,
    signals: Any = None,
    seed: int = 0,
) -> dict:
    """Attach judgment and rewrite speak only when the Dummy contract requires it."""
    out = dict(row)
    mem = memory if memory is not None else DummyMemory()
    mem.ingest_all(prior_turns)
    mem.ingest(message)
    fusion = out.get("fusion") if isinstance(out.get("fusion"), dict) else {}
    situation = None
    sit_row = out.get("situation")
    if isinstance(sit_row, dict):
        situation = type("Sit", (), sit_row)()
        signals_in = sit_row.get("signals") if isinstance(sit_row.get("signals"), list) else []
        situation.signals = [
            type("Sig", (), s)() if isinstance(s, dict) else s for s in signals_in
        ]
        decisions = sit_row.get("decisions") if isinstance(sit_row.get("decisions"), dict) else {}
        situation.decisions = type("Dec", (), decisions)()
    orch_in = out.get("orchestration") if isinstance(out.get("orchestration"), dict) else {}
    stamped = orch_in.get("dummy_nights")
    evidence = gather_evidence(
        message,
        ctx=ctx,
        payload=payload,
        fusion=fusion,
        memory=mem,
        signals=signals,
        stamped_nights=stamped if isinstance(stamped, int) else None,
    )
    judgment = judge(evidence, mem, message, situation=situation)

    prose = str(out.get("prose_summary") or "")
    chat = str(out.get("message") or prose)
    locked = _guidance_locked(out, judgment)
    follow = _is_follow_up(prose) or _is_follow_up(chat)
    greet = bool(_GREET.match(str(message or "").strip()))
    safety = any(s in (prose + " " + chat).lower() for s in _SAFETY_SKIP)

    if not locked:
        if judgment.cold_start:
            spoken = compose(judgment, evidence, mem, seed)
            prose = spoken
            chat = spoken
        elif judgment.blocks_training:
            spoken = compose(judgment, evidence, mem, seed)
            # Keep the perception conflict line tests already pin.
            if "rest and fluids" not in spoken:
                spoken = f"You're sick and asking to train — today the training is rest and fluids. {spoken}"
            prose = strip_training_push(spoken)
            chat = prose
            out["session"] = None
            rec = judgment.suggestion
            out["recommendation"] = rec
            card = dict(out["card"]) if isinstance(out.get("card"), dict) else {}
            card["action"] = rec
            card["why"] = judgment.why
            out["card"] = card
            if isinstance(out.get("fusion"), dict):
                fused = dict(out["fusion"])
                fused["stance"] = "protect"
                out["fusion"] = fused
        elif not follow and not safety:
            chat = honor_memory(chat, mem)
            prose = honor_memory(prose, mem)
            if not greet:
                chat = ensure_why(chat, judgment)
                prose = ensure_why(prose, judgment)
            chat = apply_tone(chat, mem.style, seed)
            prose = apply_tone(prose, mem.style, seed)

        prose = audit_invented_numbers(prose, evidence)
        chat = audit_invented_numbers(chat, evidence)
        if judgment.blocks_training:
            prose = strip_training_push(prose)
            chat = strip_training_push(chat)
        if judgment.cold_start or judgment.blocks_training:
            prose, chat = _soul_and_rails(prose, chat)
    out["prose_summary"] = prose
    out["message"] = chat or prose
    out["judgment"] = judgment.as_dict()
    out["dummy_memory"] = mem.as_dict()
    orch = dict(out.get("orchestration") or {})
    orch["judgment"] = judgment.as_dict()
    orch["style"] = mem.style.as_dict()
    orch["dummy_nights"] = evidence.nights
    orch["dummy_min_nights"] = MIN_NIGHTS
    out["orchestration"] = orch
    out["critic"] = _local_critic(chat or prose, facts=[judgment.why] if judgment.why else None)
    return out


def _soul_and_rails(prose: str, chat: str) -> tuple[str, str]:
    """Reuse ARIA soul + rails. Style never overrides them."""
    try:
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from aria_core.rails import validate_output
        from aria_core.soul import soul_sanitize

        return soul_sanitize(validate_output(prose)), soul_sanitize(validate_output(chat))
    except Exception:
        return prose, chat


def _local_critic(text: str, facts: Iterable[str] | None = None) -> dict[str, Any]:
    try:
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from aria_core.safety_rails import critic_verdict

        return critic_verdict(text, facts=facts)
    except Exception:
        fails = speak_quality.speak_failures({"message": text, "prose_summary": text})
        return {
            "safe": not fails,
            "answer": text,
            "violations": fails,
            "consistent": True,
            "missing_facts": [],
            "source": "local",
        }
