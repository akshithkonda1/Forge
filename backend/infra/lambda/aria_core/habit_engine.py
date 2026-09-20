"""HabitEngine — ARIA's deep habit layer, the piece that turns Lifestyle
from a dashboard into a companion.

Python port of ForgeCore's ``HabitEngine.swift``
(``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/HabitEngine.swift``),
kept numerically/textually identical to it. Every rule and copy string
below mirrors the Swift source line for line, since the exact wording is
the product here, not just the numbers.

A habit is not a checkbox. It is a loop: cue -> routine -> payoff/cost,
verified against the user's actual numbers (sleep debt, HRV, markers,
social). The engine reads the signals Lifestyle already collects and
emits the 2-3 loops that actually move the needle, each with the smallest
interrupt that can break it.

Ported: ``DeepHabit``, ``HabitSignals`` (including its ``markers`` field,
present-but-unread by ``analyze()`` in the Swift source itself -- ported
as an opaque passthrough for interface fidelity, not because anything
here reads it), ``analyze()``, ``companion_line()``, ``lifestyle_tags()``,
``constraints()``.

Not ported: ``HabitFeedbackStore.swift`` (a separate file, not named in
this port's task) -- ``tried()``/``markTried()``/``pendingFeedback()``/
``submitFeedback()`` are UserDefaults persistence, the same reasoning
every earlier "Store" port (``QualityOfLifeLivingStore``,
``SleepDepthBaselineStore``, ``ScheduleGoalStore``) was excluded for.
That file also has two pure fact-builder functions
(``attemptFact``/``outcomeFact``) that build an ``AriaKnowledgeFact`` for
the two-tier memory system -- a reasonable future port, but a separate
decision from this task, not folded in here.

Stdlib only. Deterministic. Pure -- no I/O.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

# --- Category ----------------------------------------------------------
# Mirrors DeepHabit.Category (Swift L24-36).

SLEEP = "sleep"
NUTRITION = "nutrition"
MOVEMENT = "movement"
SOCIAL = "social"
RECOVERY = "recovery"

CATEGORY_ICON: dict[str, str] = {
    SLEEP: "moon.stars.fill",
    NUTRITION: "fork.knife",
    MOVEMENT: "figure.run",
    SOCIAL: "person.2.fill",
    RECOVERY: "heart.fill",
}


# --- DeepHabit -----------------------------------------------------------
# Mirrors DeepHabit (Swift L11-43).

@dataclass(frozen=True)
class DeepHabit:
    id: str
    title: str
    cue: str
    routine: str
    payoff: str
    cost: str
    category: str
    confidence: float  # 0...1 how much evidence
    evidence: str       # 1 line citing real numbers
    breaker: str         # one smallest next move
    breaker_action: str  # button label


# --- Signals -----------------------------------------------------------
# Mirrors FakeSocialEvent (FakeHealthPack.swift L75-...) reduced to the
# fields analyze() actually reads (drinks, ran_late), plus the rest of the
# shape for interface fidelity, and HabitSignals (Swift L46-67).

@dataclass(frozen=True)
class SocialEvent:
    kind: str = "dinnerOut"
    title: str = ""
    start: datetime | None = None
    minutes: int = 0
    drinks: int = 0
    # Ran past midnight. The single biggest driver of the night that follows.
    ran_late: bool = False


@dataclass
class HabitSignals:
    """Input Lifestyle already has: metrics, stats, sleep onset variance,
    markers, social."""

    sleep_average: float  # hours
    steps: int
    protein: float
    water_glasses: float
    total_calories: int
    sleep_variance_minutes: int | None = None  # std or range
    hrv: float | None = None
    hrv_baseline: float | None = None
    markers: list[Any] = field(default_factory=list)  # unread by analyze() -- see module docstring
    social: list[SocialEvent] = field(default_factory=list)
    nights_available: int = 0
    quality_of_life_score: int = 80


# --- Engine ------------------------------------------------------------
# Mirrors HabitEngine.analyze (Swift L71-222).

def analyze(s: HabitSignals) -> list[DeepHabit]:
    out: list[DeepHabit] = []

    # 1) Irregular wind-down -- the biggest lever. Gated on
    # sleep_variance_minutes being present at all: a low sleep_average
    # alone never fires this rule if variance was never measured.
    if s.sleep_variance_minutes is not None and (s.sleep_variance_minutes > 60 or s.sleep_average < 7.0):
        variance = s.sleep_variance_minutes
        if variance > 90:
            evidence = f"Bedtime moved {variance}m across the last week · avg {s.sleep_average:.1f}h (target 8h)"
        elif s.sleep_average < 7:
            evidence = f"Avg {s.sleep_average:.1f}h — {8 - s.sleep_average:.1f}h under target, variance {variance}m"
        else:
            evidence = f"Sleep variance {variance}m — enough to cut deep sleep ~18%"
        out.append(DeepHabit(
            id="sleep_variance",
            title="Wobbly wind-down",
            cue="Evening at home after 22:00",
            routine="Phone stays with you on the couch → late scroll → 00:30 sleep",
            payoff="Felt productive for 20m",
            cost="Deep sleep cut, tomorrow's readiness down",
            category=SLEEP,
            confidence=0.85 if variance > 90 else 0.65,
            evidence=evidence,
            breaker="Tonight, leave phone charging in the kitchen at 22:00. Just that.",
            breaker_action="Try kitchen-phone",
        ))

    # 2) Social -> late night -> HRV dip
    drinks_nights = [e for e in s.social if e.drinks >= 2]
    late_nights = [e for e in s.social if e.ran_late]
    if drinks_nights or len(late_nights) >= 2:
        count = len(drinks_nights)
        drinks = sum(e.drinks for e in drinks_nights)
        out.append(DeepHabit(
            id="social_late",
            title="Late social → late sleep",
            cue="Dinner or drinks out after 19:00",
            routine=f"{count} evenings with {drinks} drinks, {len(late_nights)} ran past midnight",
            payoff="Connection, fun — real",
            cost="Onset pushed ~70m, next-morning HRV down",
            category=SOCIAL,
            confidence=0.82 if len(late_nights) >= 2 else 0.62,
            evidence=f"{count} social nights, {drinks} drinks total · {len(late_nights)} late",
            breaker="Next dinner out, pick one earlier night this week. No perfection needed.",
            breaker_action="Keep one early",
        ))

    # 3) Hydration loop
    if s.water_glasses < 6:
        out.append(DeepHabit(
            id="hydration",
            title="Dehydration drag",
            cue="Morning at desk, no water in sight",
            routine=f"Coffee only until lunch → {int(s.water_glasses)} glasses by 14:00",
            payoff="None — just habit inertia",
            cost="Energy dips, recovery slows",
            category=NUTRITION,
            confidence=0.78,
            evidence=f"{int(s.water_glasses)} glasses today · need ~8",
            breaker="Put a full glass where you code. Finish it before coffee #2.",
            breaker_action="Glass first",
        ))

    # 4) Protein gap loop
    protein_gap = max(0, int(180 - s.protein))
    if protein_gap > 30:
        out.append(DeepHabit(
            id="protein_gap",
            title="Protein under-shoot",
            cue="Next meal, no protein anchor",
            routine=f"Carbs/fat first → {int(s.protein)}g by now, gap {protein_gap}g",
            payoff="Quick, tasty",
            cost="Muscle recovery throttled, hunger returns fast",
            category=NUTRITION,
            confidence=0.8 if protein_gap > 50 else 0.6,
            evidence=f"{int(s.protein)}g / 180g · {protein_gap}g short",
            breaker="Next plate: protein first, palm-sized. That's the whole rule.",
            breaker_action="Protein first",
        ))

    # 5) Sedentary day loop
    if s.steps < 6000:
        out.append(DeepHabit(
            id="sedentary",
            title="Long still stretch",
            cue="Desk 10:00–16:00 with one context",
            routine=f"{s.steps} steps by now → body stays in one mode",
            payoff="Focus preserved short-term",
            cost="Circulation, mood, and QOL dip",
            category=MOVEMENT,
            confidence=0.78 if s.steps < 3500 else 0.6,
            evidence=f"{s.steps} steps · target 10k",
            breaker="One 12-min walk between calls. No gear, no app.",
            breaker_action="12-min walk",
        ))

    # 6) HRV dip without sleep cause -- recovery loop
    if s.hrv is not None and s.hrv_baseline is not None and s.hrv_baseline > 0 and s.hrv < s.hrv_baseline - 8:
        drop = int(s.hrv_baseline - s.hrv)
        out.append(DeepHabit(
            id="hrv_dip",
            title="Recovery dip",
            cue="Yesterday's load or short night",
            routine=f"HRV {int(s.hrv)}ms vs baseline {int(s.hrv_baseline)}ms (−{drop}ms)",
            payoff="You pushed — good",
            cost="Today's window is smaller than it looks",
            category=RECOVERY,
            confidence=0.82 if drop > 15 else 0.62,
            evidence=f"HRV {int(s.hrv)} vs {int(s.hrv_baseline)} baseline · sleep {s.sleep_average:.1f}h",
            breaker="Hold load steady today; don't add volume. Reassess tomorrow.",
            breaker_action="Hold steady",
        ))

    # 7) Lifestyle QoL under pressure -- companion loop from the living grade
    if s.quality_of_life_score < 70:
        if s.sleep_average < 7.0:
            lever = (SLEEP, "sleep hours", "Protect tonight's wind-down — QoL rises when sleep does.")
        elif s.water_glasses < 6:
            lever = (NUTRITION, "hydration", "One full glass before coffee #2 — QoL needs that small win.")
        elif s.steps < 6000:
            lever = (MOVEMENT, "movement", "A 12-min walk today — QoL follows motion.")
        else:
            lever = (RECOVERY, "recovery", "Hold load steady; let Lifestyle QoL climb before adding volume.")
        out.append(DeepHabit(
            id="qol_protect",
            title="Life rhythm needs care",
            cue="Lifestyle QoL under 70",
            routine=f"Grade sitting at {s.quality_of_life_score}/100 while {lever[1]} lags",
            payoff="Pushing through feels productive short-term",
            cost="Workouts and mood stay capped until the grade recovers",
            category=lever[0],
            confidence=0.88 if s.quality_of_life_score < 50 else 0.72,
            evidence=f"Lifestyle QoL {s.quality_of_life_score}/100 · {lever[1]}",
            breaker=lever[2],
            breaker_action="Ease one lever",
        ))

    # Keep the most confident 3 -- Lifestyle wants depth, not a list.
    # Python's sorted() is stable, matching Swift 5+'s stable sort: equal-
    # confidence habits keep the order they were appended in above.
    return sorted(out, key=lambda h: h.confidence, reverse=True)[:3]


def companion_line(habits: list[DeepHabit]) -> str | None:
    """One-line ARIA insight derived from the top habit -- used for the
    header card."""
    if not habits:
        return None
    top = habits[0]
    if top.id == "sleep_variance":
        return (f"You're becoming someone with a regular night. {top.evidence} "
                f"Tonight: leave the phone in the kitchen at 22:00.")
    if top.id == "social_late":
        return (f"Late social nights are pushing your sleep {top.evidence.lower()}. "
                f"One earlier night this week would move the needle.")
    if top.id == "hydration":
        return f"Water's low {top.evidence.lower()} — one glass before coffee #2 is the smallest win."
    if top.id == "protein_gap":
        return f"Protein's {top.evidence.lower()} — next meal, protein first?"
    if top.id == "sedentary":
        return f"Steps are {top.evidence.lower()} — a 12-min walk between calls is enough."
    if top.id == "hrv_dip":
        return f"Recovery dipped {top.evidence.lower()}. Holding steady today protects tomorrow."
    if top.id == "qol_protect":
        return f"Lifestyle QoL is {top.evidence.lower()}. {top.breaker}"
    return f"{top.title}: {top.evidence} — {top.breaker}"


def lifestyle_tags(habits: list[DeepHabit]) -> list[str]:
    """LifestyleTags ARIA will see -- one tag per habit, stable id."""
    return [f"habit:{h.id}:{h.category}:{int(h.confidence * 100)}" for h in habits]


def constraints(habits: list[DeepHabit]) -> list[str]:
    """ARIA constraints derived from habits -- e.g., cross_zone sleep hygiene."""
    c: list[str] = []
    if any(h.category == SLEEP for h in habits):
        c.append("habit:sleep_hygiene: protect 22:30 wind-down")
    if any(h.category == SOCIAL for h in habits):
        c.append("habit:social: one early night this week")
    if any(h.id == "qol_protect" for h in habits):
        c.append("habit:qol_protect: ease volume until Lifestyle QoL recovers")
    return c
