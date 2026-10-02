"""Dummy perception: gather every signal, then judge the situation case by case.

Mirrors ``AriaSituation`` (ForgeCore) on iOS. Deterministic and local —
this module never touches the network. It reads three kinds of context:

* **measured** — the synthetic day / wearable stream (sleep, recovery, load,
  HRV presence, overtraining, streaks);
* **said** — what the person just told ARIA (how they feel, what they want,
  illness, injury, an event coming up) plus the thread of earlier turns;
* **world** — local time and, when the caller supplies it, the weather and
  air outside (``EnvironmentRead``).

``perceive`` returns a ``Situation``: every signal with where it came from,
the conflicts between them ("you feel great, but the night was short"),
one posture, concrete decisions, what ARIA does not know, and which
questions need outside knowledge. ``Situation.feed()`` is the structured
context handed to ARIA; ``Situation.brief()`` is the same thing as text for
a language model. Numbers stay out of spoken lines — words only.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from backend.scout.privacy import scrub_query

POSTURES = ("refer", "rest", "protect", "steady", "push")

_POSITIVE = (
    "feel great", "feeling great", "feel amazing", "feeling amazing", "feel good", "feeling good",
    "feel strong", "feeling strong", "full of energy", "ready to go", "pumped", "fired up",
    "feel fresh", "feeling fresh", "never felt better",
)
_NEGATIVE = (
    "exhausted", "tired", "wiped", "drained", "run down", "rundown", "burnt out", "burned out",
    "no energy", "low energy", "sluggish", "beat up", "feel awful", "feel terrible", "stressed",
)
_WANTS_HARD = (
    "go hard", "going hard", "max out", "maxing", "pr ", "personal record", "heavy", "hiit",
    "intense", "push it", "push hard", "long run", "all out", "race pace", "sprint", "crush ",
)
_TRAINING = ("train", "workout", "session", "lift", "gym", "run ", "running", "ride ", "swim", "hiit", "squat", "leg day", "cardio")
_OUTDOOR = ("run ", "running", "ride ", "hike", "bike", "outside", "outdoor", "trail", "tennis", "soccer", "golf")
_ILLNESS = (
    "fever", "flu ", "feel sick", "feeling sick", "i'm sick", "im sick", "got sick", "been sick",
    "sick with", "a cold", "covid", "sore throat", "chills", "vomit", "nausea",
    "stomach bug", "congested", "sinus infection",
)
_RED_FLAGS = (
    "chest pain", "chest tightness", "fainted", "passed out", "shortness of breath",
    "can't breathe", "cannot breathe", "numb arm", "slurred",
)
_JOINTS = ("knee", "shoulder", "back", "hip", "ankle", "wrist", "elbow", "neck")
_PAIN = ("pain", "hurt", "hurts", "injur", "tweak", "sprain", "strain", "pulled")
_EVENTS = (
    "wedding", "race ", "marathon", "half marathon", "10k", "5k", "meet ", "competition", "game",
    "tournament", "interview", "flight", "trip ", "photo shoot", "presentation",
)
_RESEARCH_CUES = (
    "how do i", "how to", "how much", "how many", "how long", "how often", "what is", "what are",
    "what does", "why do", "why does", "why is", "is it safe", "is it ok", "is it bad", "is it true",
    "should i take", "does it work", "do i need", "benefits of", "side effects", "evidence",
    "research", "studies", "science", " vs ", "versus", "supplement", "dose", "dosage",
)
_WORD_NUM = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "a couple": 2, "a few": 3}
_IN_DAYS = re.compile(r"\bin\s+(\d{1,2}|one|two|three|four|five|six|seven|a couple|a few)\s+days?\b")


@dataclass(frozen=True)
class EnvironmentRead:
    """Outside conditions. Fed by the caller (web weather / air quality), never guessed."""

    apparent_temp_c: float | None = None
    uv_index: float | None = None
    us_aqi: int | None = None
    precipitation_mm: float | None = None
    is_day: bool | None = None
    source: str = "none"

    @property
    def hot(self) -> bool:
        return self.apparent_temp_c is not None and self.apparent_temp_c >= 32

    @property
    def cold(self) -> bool:
        return self.apparent_temp_c is not None and self.apparent_temp_c <= -8

    @property
    def smoky(self) -> bool:
        return self.us_aqi is not None and self.us_aqi >= 101

    @property
    def stormy(self) -> bool:
        return self.precipitation_mm is not None and self.precipitation_mm >= 4

    @property
    def harsh_sun(self) -> bool:
        return self.uv_index is not None and self.uv_index >= 8


@dataclass(frozen=True)
class Signal:
    name: str
    band: str
    source: str  # measured | said | world | thread
    confidence: float = 0.8

    def as_dict(self) -> dict:
        return {"name": self.name, "band": self.band, "source": self.source, "confidence": self.confidence}


@dataclass(frozen=True)
class Conflict:
    kind: str
    line: str
    severity: str  # low | medium | high

    def as_dict(self) -> dict:
        return {"kind": self.kind, "line": self.line, "severity": self.severity}


@dataclass(frozen=True)
class ResearchNeed:
    query: str
    topic: str
    why: str

    def as_dict(self) -> dict:
        return {"query": self.query, "topic": self.topic, "why": self.why}


@dataclass
class Decisions:
    keep_light: bool = False
    shorten: bool = False
    move_indoors: bool = False
    ask_first: bool = False
    refer_out: bool = False
    rest: bool = False

    def as_dict(self) -> dict:
        return dict(self.__dict__)


@dataclass
class Situation:
    posture: str
    signals: list[Signal] = field(default_factory=list)
    conflicts: list[Conflict] = field(default_factory=list)
    decisions: Decisions = field(default_factory=Decisions)
    unknowns: list[str] = field(default_factory=list)
    research: list[ResearchNeed] = field(default_factory=list)
    environment: EnvironmentRead | None = None

    def signal(self, name: str) -> Signal | None:
        return next((s for s in self.signals if s.name == name), None)

    @property
    def spoken_line(self) -> str:
        """One human sentence for the sharpest conflict, or ``""``."""
        order = {"high": 0, "medium": 1, "low": 2}
        ranked = sorted(self.conflicts, key=lambda c: order.get(c.severity, 3))
        for conflict in ranked:
            if conflict.severity in ("high", "medium"):
                return conflict.line
        return ""

    def feed(self) -> dict:
        """The structured context handed to ARIA for this turn."""
        return {
            "posture": self.posture,
            "signals": [s.as_dict() for s in self.signals],
            "conflicts": [c.as_dict() for c in self.conflicts],
            "decisions": self.decisions.as_dict(),
            "unknowns": list(self.unknowns),
            "research": [r.as_dict() for r in self.research],
            "environment": (
                None
                if self.environment is None
                else {k: v for k, v in self.environment.__dict__.items() if v is not None}
            ),
        }

    def brief(self) -> str:
        """Same read as plain text for a model prompt (no raw vitals)."""
        lines = [f"Posture: {self.posture}."]
        if self.signals:
            lines.append("Signals: " + "; ".join(f"{s.name} {s.band} ({s.source})" for s in self.signals) + ".")
        for c in self.conflicts:
            lines.append(f"Conflict ({c.severity}): {c.line}")
        chosen = [k.replace("_", " ") for k, v in self.decisions.as_dict().items() if v]
        if chosen:
            lines.append("Decisions: " + ", ".join(chosen) + ".")
        if self.unknowns:
            lines.append("Unknown: " + ", ".join(self.unknowns) + ".")
        return "\n".join(lines)

    def as_dict(self) -> dict:
        return self.feed()


def _needle(n: str) -> re.Pattern:
    """Start-of-word match; a trailing space in the needle also pins the end."""
    body = re.escape(n.strip())
    tail = r"(?![a-z])" if n.endswith(" ") else ""
    return re.compile(r"(?<![a-z])" + body + tail)


_NEEDLE_CACHE: dict[str, re.Pattern] = {}


def _has(lower: str, needles: tuple[str, ...]) -> bool:
    for n in needles:
        pattern = _NEEDLE_CACHE.get(n)
        if pattern is None:
            pattern = _NEEDLE_CACHE[n] = _needle(n)
        if pattern.search(lower):
            return True
    return False


def event_days(lower: str) -> int | None:
    if not _has(lower, _EVENTS):
        return None
    if "today" in lower or "tonight" in lower:
        return 0
    if "tomorrow" in lower:
        return 1
    if "this weekend" in lower or "saturday" in lower or "sunday" in lower:
        return 3
    if "next week" in lower:
        return 7
    match = _IN_DAYS.search(lower)
    if match:
        raw = match.group(1)
        return int(raw) if raw.isdigit() else _WORD_NUM.get(raw)
    return None


def research_topic(lower: str) -> str:
    if _has(lower, _ILLNESS) or "temperature" in lower:
        return "fever"
    for topic, cues in (
        ("sleep", ("sleep", "insomnia", "nap", "melatonin")),
        ("nutrition", ("protein", "creatine", "supplement", "eat", "diet", "carb", "fat loss", "calorie", "vitamin")),
        ("cycle", ("period", "cycle", "menstru", "ovulat")),
        ("training", ("train", "workout", "lift", "run", "cardio", "muscle", "strength", "zone")),
        ("readiness", ("recover", "hrv", "soreness", "rest day")),
    ):
        if any(c in lower for c in cues):
            return topic
    return "lifestyle"


def _measured(ctx) -> list[Signal]:
    if ctx is None:
        return []
    today = getattr(ctx, "today", None)
    signals: list[Signal] = []
    sleep_h = getattr(today, "total_sleep_hours", None)
    if sleep_h is not None:
        band = "thin" if sleep_h < 6.4 else ("rebuilt" if sleep_h >= 7.4 else "decent")
        signals.append(Signal("sleep", band, "measured", 0.9))
    readiness = getattr(today, "readiness_score", None)
    debt = getattr(ctx, "sleep_debt_7d_hours", 0) or 0
    overtrained = bool(getattr(ctx, "is_overtrained", False))
    if readiness is not None:
        if readiness < 50 or debt > 5.0 or overtrained:
            band = "asking"
        elif readiness >= 75 and getattr(ctx, "readiness_trend", "") != "falling":
            band = "ready"
        else:
            band = "steady"
        signals.append(Signal("recovery", band, "measured", 0.8))
    if overtrained:
        signals.append(Signal("load", "overreached", "measured", 0.85))
    elif (getattr(ctx, "training_streak", 0) or 0) >= 3:
        signals.append(Signal("load", "on a streak", "measured", 0.8))
    elif (getattr(ctx, "days_since_last_workout", 0) or 0) >= 3:
        signals.append(Signal("load", "fresh", "measured", 0.8))
    chrono = str(getattr(ctx, "chronotype", "") or "").strip().lower()
    if chrono:
        signals.append(Signal("chronotype", chrono, "measured", 0.6))
    return signals


def perceive(
    message: str,
    *,
    ctx=None,
    prior_turns: list[str] | None = None,
    environment: EnvironmentRead | None = None,
    local_hour: int | None = None,
    private_terms: tuple[str, ...] = (),
) -> Situation:
    """Read everything available for this turn and judge it. Pure function."""
    lower = f" {str(message or '').lower().strip()} "
    signals = _measured(ctx)
    unknowns: list[str] = []
    conflicts: list[Conflict] = []
    decisions = Decisions()

    def band(name: str) -> str:
        found = next((s for s in signals if s.name == name), None)
        return found.band if found else ""

    if ctx is not None and band("sleep") == "":
        unknowns.append("last night's sleep")

    # --- said -----------------------------------------------------------
    positive = _has(lower, _POSITIVE)
    negative = _has(lower, _NEGATIVE)
    if positive:
        signals.append(Signal("feeling", "good", "said", 0.7))
    elif negative:
        signals.append(Signal("feeling", "low", "said", 0.8))
    training_ask = _has(lower, _TRAINING)
    wants_hard = _has(lower, _WANTS_HARD)
    outdoor = training_ask and _has(lower, _OUTDOOR)
    # "sick of my job" is a mood, not an illness.
    ill = _has(lower, _ILLNESS) and not re.search(r"sick (?:of|and tired)", lower)
    red_flag = _has(lower, _RED_FLAGS)
    joints = [j for j in _JOINTS if _has(lower, (j,)) and _has(lower, _PAIN)]
    days = event_days(lower)
    if ill:
        signals.append(Signal("illness", "reported", "said", 0.8))
    if joints:
        signals.append(Signal("injury", joints[0], "said", 0.8))
    if days is not None:
        signals.append(Signal("event", "today" if days == 0 else f"in {days} days" if days > 1 else "tomorrow", "said", 0.7))
    if prior_turns:
        last = str(prior_turns[-1]).lower()
        if any(w in last for w in ("slept", "sleep", "last night")):
            signals.append(Signal("thread", "sleep came up", "thread", 0.6))

    # --- world ----------------------------------------------------------
    if local_hour is not None:
        tod = "night" if local_hour >= 21 or local_hour < 5 else "morning" if local_hour < 12 else "day"
        signals.append(Signal("time", tod, "world", 1.0))
    env = environment
    if env is not None and env.source != "none":
        for flag, label in ((env.hot, "hot"), (env.cold, "freezing"), (env.smoky, "poor air"), (env.stormy, "stormy"), (env.harsh_sun, "harsh sun")):
            if flag:
                signals.append(Signal("outside", label, "world", 0.85))

    sleep = band("sleep")
    recovery = band("recovery")

    # --- evaluate, case by case -----------------------------------------
    if red_flag:
        decisions.refer_out = True
        conflicts.append(Conflict("red_flag", "That symptom needs a clinician before any training — please get it checked today.", "high"))
    if ill and training_ask:
        decisions.rest = True
        conflicts.append(Conflict("illness_vs_training", "You're sick and asking to train — today the training is rest and fluids.", "high"))
    elif ill:
        decisions.rest = True
    if positive and (sleep == "thin" or recovery == "asking"):
        decisions.keep_light = True
        conflicts.append(Conflict(
            "said_vs_measured",
            "You feel good, and your body is still paying for a short night — I'll trust the feeling and cap the ceiling.",
            "medium",
        ))
    if negative and recovery == "ready" and training_ask:
        decisions.keep_light = True
        conflicts.append(Conflict(
            "said_vs_measured",
            "The recovery read looks ready, but you don't feel it — how you feel wins today.",
            "medium",
        ))
    if wants_hard and (recovery == "asking" or band("load") == "overreached"):
        decisions.keep_light = True
        conflicts.append(Conflict(
            "intent_vs_recovery",
            "You want a hard day on a body that's asking for an easy one — we'll bank the effort instead of spending it.",
            "medium",
        ))
    if days is not None and days <= 2 and training_ask:
        decisions.keep_light = True
        decisions.shorten = True
        conflicts.append(Conflict("event_taper", "With the big day this close, we sharpen instead of load.", "medium"))
    if joints and training_ask:
        decisions.keep_light = True
        conflicts.append(Conflict("injury_vs_training", f"We train around the {joints[0]}, not through it.", "medium"))
    if outdoor and env is not None and (env.hot or env.smoky or env.stormy or env.cold):
        decisions.move_indoors = True
        why = "the air is rough" if env.smoky else "it's dangerously hot" if env.hot else "it's freezing" if env.cold else "the weather is ugly"
        conflicts.append(Conflict("world_vs_outdoor", f"Take it inside today — {why} out there.", "medium"))
    if local_hour is not None and (local_hour >= 21 or local_hour < 4) and training_ask and wants_hard:
        decisions.shorten = True
        conflicts.append(Conflict("late_vs_sleep", "This late, a hard session steals from tonight's sleep — short and easy.", "low"))
    if training_ask and ctx is not None and sleep == "":
        decisions.ask_first = True

    # --- posture --------------------------------------------------------
    if decisions.refer_out:
        posture = "refer"
    elif decisions.rest:
        posture = "rest"
    elif decisions.keep_light or recovery == "asking" or sleep == "thin":
        posture = "protect"
    elif wants_hard and recovery == "ready" and not negative:
        posture = "push"
    else:
        posture = "steady"

    # --- what needs the outside world -----------------------------------
    research: list[ResearchNeed] = []
    topic = research_topic(lower)
    if _has(lower, _RESEARCH_CUES) or ill:
        query = scrub_query(message, private_terms)
        if query:
            research.append(ResearchNeed(query=query, topic=topic, why="question needs outside knowledge"))
    if outdoor and env is not None and env.hot and not any(r.topic == "heat" for r in research):
        research.append(ResearchNeed(query="exercise in hot weather safety", topic="heat", why="training outside in heat"))

    return Situation(
        posture=posture,
        signals=signals,
        conflicts=conflicts,
        decisions=decisions,
        unknowns=unknowns,
        research=research,
        environment=env,
    )
