"""Raw-data supervision plan — what ARIA stores as context and then follows.

This is the data engine sitting under ARIA the coach: take raw signals
(recovery, sleep, HRV, calendar kinds/busy windows, what they said, aging
pace, stress, social load, socioeconomic load), evaluate them, and write a
compact **plan**. ARIA uses that plan as context for the next piece of
advice and for how to guide the person. Later outcomes (complete, skip,
thumbs, "that helped") credit the plan's choice retroactively so the next
plan is learned, not only the stance.

Dummy must never import this module. Persistence stays on ``ARIA#PERSONA``
and living ``UserContext.supervision_plan``. Deleting dummy leaves this file.

Aging pace is a **lifestyle wear/repair read**, not a diagnosis or a
biological-age number. "Faster" means the body is taking more wear than it
is repairing lately; "slower" means recovery is holding. A faster/slower
call is only allowed when it has **named factors** (sleep, stress, a
wedding, work load, a surprise visit). Forge never says "you aged two
years" or "your biological age is 30". Map the person with the right
amount of data — one next ask, never a fishing trip. Never invent a
calendar title. Never prescribe.

Stdlib only. Deterministic. Lambda hot path.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Iterable

AGING_PACES = ("faster", "on_pace", "slower", "unknown")
PLAN_CHOICES = (
    "protect_load",
    "sleep_first",
    "train_through",
    "fuel",
    "clarify",
)
CHOICE_TO_STANCE = {
    "protect_load": "protect",
    "sleep_first": "protect",
    "train_through": "proceed",
    "fuel": "fuel",
    "clarify": "clarify",
}
LANES = ("physiological", "social", "socioeconomic", "sex_aware")
SOCIAL_KINDS = frozenset({"wedding", "social", "dinner", "family", "game", "surprise"})
WORK_KINDS = frozenset({"work"})
HEADLINE_KINDS = frozenset({"wedding", "game", "flight", "travel"})
BETTER_LIFE_PILLARS = ("restore", "move", "fuel", "connect", "work_life")

_AGING_PRIOR = {pace: 1.0 for pace in ("faster", "on_pace", "slower")}

_FASTER_CUES = (
    "aging faster",
    "getting older",
    "don't recover",
    "dont recover",
    "used to recover",
    "recovery is slower",
    "feeling older",
    "wear and tear",
    "bounce back slower",
)
_SLOWER_CUES = (
    "aging slower",
    "feeling younger",
    "recovering well",
    "bounce back fast",
    "bounce back quickly",
    "i bounce back",
)
_STRESS_CUES = (
    "stressed",
    "overwhelmed",
    "burned out",
    "burnt out",
    "too much on my plate",
    "can't switch off",
    "cant switch off",
)
_SURPRISE_CUES = (
    "surprise visit",
    "surprise visits",
    "dropped by",
    "dropped in",
    "showed up unannounced",
    "unannounced",
    "friends showed up",
)
_GATHERING_CUES = (
    "social gathering",
    "hanging with friends",
    "friends coming",
    "friends over",
    "dinner party",
    "people over",
)
_YEAR_CLAIM = re.compile(
    r"(?:your |their )?biological[- ]age is \d|"
    r"bio[- ]age is \d|"
    r"aged (?:one|two|three|\d+) years|"
    r"you (?:have )?aged \d|"
    r"\byou are \d{2}\b",
    re.IGNORECASE,
)

_CHOICE_PRIOR = {
    "faster": {
        "sleep_first": 1.25,
        "protect_load": 1.05,
        "train_through": 0.15,
        "fuel": 0.45,
        "clarify": 0.35,
    },
    "on_pace": {
        "train_through": 0.95,
        "protect_load": 0.65,
        "sleep_first": 0.55,
        "fuel": 0.50,
        "clarify": 0.40,
    },
    "slower": {
        "train_through": 1.30,
        "protect_load": 0.30,
        "sleep_first": 0.25,
        "fuel": 0.55,
        "clarify": 0.30,
    },
    "unknown": {
        "clarify": 1.15,
        "protect_load": 0.55,
        "train_through": 0.50,
        "sleep_first": 0.40,
        "fuel": 0.40,
    },
}


def default_aging() -> dict[str, float]:
    return dict(_AGING_PRIOR)


def _clip(value: float, lo: float, hi: float) -> float:
    return lo if value < lo else hi if value > hi else value


def _num(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


def _clean_speak(text: str) -> str:
    """Drop any accidental year/bio-age claim from generated copy."""
    raw = str(text or "").strip()
    if not raw or not _YEAR_CLAIM.search(raw):
        return raw[:240]
    return _YEAR_CLAIM.sub("wear and repair", raw)[:240]


def _sleep_hours(ctx: Any) -> float | None:
    minutes = getattr(getattr(ctx, "sleep", None), "duration_minutes", None)
    hours = _num(minutes)
    if hours is not None:
        return hours / 60.0
    today = getattr(ctx, "today", None)
    raw = getattr(today, "total_sleep_hours", None) if today is not None else None
    return _num(raw)


def _recovery(ctx: Any) -> float | None:
    score = getattr(getattr(ctx, "readiness", None), "recovery_score", None)
    parsed = _num(score)
    if parsed is not None:
        return parsed / 100.0 if parsed > 1.5 else parsed
    today = getattr(ctx, "today", None)
    raw = getattr(today, "readiness_score", None) if today is not None else None
    parsed = _num(raw)
    return parsed / 100.0 if parsed is not None and parsed > 1.5 else parsed


def _hrv_trend(ctx: Any) -> float | None:
    return _num(getattr(getattr(ctx, "readiness", None), "hrv_7day_trend", None))


def _resting_hr(ctx: Any) -> float | None:
    return _num(getattr(getattr(ctx, "sleep", None), "resting_hr", None))


def _occupation(ctx: Any) -> str:
    for obj in (ctx, getattr(ctx, "profile", None), getattr(ctx, "persona", None)):
        if obj is None:
            continue
        raw = getattr(obj, "occupation", None)
        if isinstance(raw, str) and raw.strip():
            return raw.strip().lower()
    return ""


def _sex(ctx: Any) -> str:
    """Known sex only. Never infer from a name or a voice."""
    for obj in (getattr(ctx, "profile", None), getattr(ctx, "body", None), ctx):
        if obj is None:
            continue
        for key in ("biological_sex", "biologicalSex", "sex"):
            raw = getattr(obj, key, None)
            if isinstance(raw, str) and raw.strip():
                token = raw.strip().lower()
                if token in ("female", "woman", "f"):
                    return "female"
                if token in ("male", "man", "m"):
                    return "male"
    return ""


def _cycle_tracking(ctx: Any) -> bool:
    if getattr(ctx, "cycle_tracking_available", None) is True:
        return True
    profile = getattr(ctx, "profile", None)
    if getattr(profile, "cycle_tracking_available", None) is True:
        return True
    return False


def _calendar_snapshot(ctx: Any) -> dict[str, Any]:
    try:
        from .contextual_learner import parse_calendar, _lifestyle_tags

        cal = parse_calendar(_lifestyle_tags(ctx))
        return {
            "kinds": tuple(cal.kinds),
            "headlines": tuple(cal.headlines),
            "evening_busy": bool(cal.evening_busy),
            "morning_busy": bool(cal.morning_busy),
            "busy_today": int(cal.busy_today or 0),
        }
    except Exception:
        tags = getattr(getattr(ctx, "lifestyle", None), "tags", None) or []
        kinds: list[str] = []
        evening = False
        morning = False
        busy = 0
        for raw in tags:
            tag = str(raw)
            if tag == "calendar:evening:busy":
                evening = True
            elif tag == "calendar:morning:busy":
                morning = True
            elif tag.startswith("calendar:busy:"):
                tail = tag[len("calendar:busy:") :]
                if tail.isdigit():
                    busy = int(tail)
            elif tag.startswith("calendar:kind:"):
                kinds.append(tag[len("calendar:kind:") :])
        headlines = tuple(k for k in kinds if k in HEADLINE_KINDS)
        return {
            "kinds": tuple(kinds),
            "headlines": headlines,
            "evening_busy": evening,
            "morning_busy": morning,
            "busy_today": busy,
        }


@dataclass(frozen=True)
class AgingFactor:
    """One attributable reason. Never a year count."""

    id: str
    lane: str
    contribution: float
    why: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "lane": self.lane,
            "contribution": round(self.contribution, 4),
            "why": _clean_speak(self.why),
        }


@dataclass(frozen=True)
class AgingRead:
    """Lifestyle wear/repair — not a clinical biological age."""

    pace: str = "unknown"
    wear: float = 0.0
    signals: tuple[str, ...] = ()
    reason: str = "no body signal yet — not guessing an aging pace"
    factors: tuple[AgingFactor, ...] = ()
    stress_state: str = "unknown"
    stress_load: float = 0.0
    coverage: tuple[tuple[str, float], ...] = ()
    ask_next: str = ""
    ask_why: str = ""
    years_claimed: None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "pace": self.pace,
            "wear": round(self.wear, 4),
            "signals": list(self.signals),
            "reason": _clean_speak(self.reason),
            "factors": [f.as_dict() for f in self.factors],
            "stress": {"state": self.stress_state, "load": round(self.stress_load, 4)},
            "coverage": {lane: round(score, 4) for lane, score in self.coverage},
            "ask_next": _clean_speak(self.ask_next),
            "ask_why": _clean_speak(self.ask_why),
            "years_claimed": None,
        }


def _factor(fid: str, lane: str, contribution: float, why: str) -> AgingFactor:
    return AgingFactor(fid, lane, round(contribution, 4), _clean_speak(why))


def _stress_algorithm(
    *,
    hrv_trend: float | None,
    recovery: float | None,
    rhr: float | None,
    kinds: Iterable[str],
    evening_busy: bool,
    busy_today: int,
    text: str,
) -> tuple[float, str, list[AgingFactor]]:
    """Body + life + spoken stress. Named factors, not a mystery score."""
    factors: list[AgingFactor] = []
    body_parts: list[float] = []
    if hrv_trend is not None:
        # Falling HRV vs their recent trend is sympathetic load, not a diagnosis.
        body_parts.append(_clip((-hrv_trend) / 16.0, 0.0, 1.0))
    if recovery is not None:
        body_parts.append(_clip(1.0 - recovery, 0.0, 1.0))
    if rhr is not None:
        body_parts.append(_clip((rhr - 58.0) / 24.0, 0.0, 1.0))
    body = sum(body_parts) / len(body_parts) if body_parts else 0.0

    kind_set = set(kinds)
    life = 0.0
    if kind_set & WORK_KINDS:
        life += 0.28
    if evening_busy:
        life += 0.20
    if "surprise" in kind_set:
        life += 0.30
    social_n = len(kind_set & SOCIAL_KINDS)
    if social_n:
        life += min(0.36, 0.12 * social_n)
    if busy_today >= 4:
        life += 0.12
    life = _clip(life, 0.0, 1.0)

    spoken = 0.0
    if any(cue in text for cue in _STRESS_CUES):
        spoken += 0.45
    if any(cue in text for cue in _SURPRISE_CUES):
        spoken += 0.30
        factors.append(
            _factor(
                "surprise",
                "social",
                0.22,
                "an unplanned visit is load — protect the day, don't name who",
            )
        )
    if any(cue in text for cue in _GATHERING_CUES):
        spoken += 0.18
        factors.append(
            _factor(
                "gathering",
                "social",
                0.14,
                "a social gathering is on the week — fit training around it",
            )
        )
    spoken = _clip(spoken, 0.0, 1.0)

    weights: list[tuple[float, float]] = []
    if body_parts:
        weights.append((body, 0.45))
    if life > 0:
        weights.append((life, 0.35))
    if spoken > 0:
        weights.append((spoken, 0.20))
    if not weights:
        return 0.0, "unknown", factors
    total_w = sum(w for _, w in weights)
    load = sum(val * w for val, w in weights) / total_w
    if load >= 0.62:
        state = "high"
        factors.append(
            _factor(
                "stress",
                "physiological" if body >= life else "socioeconomic",
                0.28,
                "stress is stacked — body, the day they have, or both — not a year count",
            )
        )
    elif load <= 0.28:
        state = "low"
    else:
        state = "moderate"
        if load >= 0.45:
            factors.append(
                _factor(
                    "stress",
                    "physiological" if body >= life else "social",
                    0.14,
                    "stress is in the picture — name it, don't turn it into an age",
                )
            )
    return round(_clip(load, 0.0, 1.0), 4), state, factors


def _right_sized_ask(
    *,
    pace: str,
    coverage: dict[str, float],
    has_phys: bool,
    has_life: bool,
    text: str,
    sex: str,
    cycle_on: bool,
) -> tuple[str, str]:
    """One next signal, or nothing. Never more data for its own sake."""
    asked_cycle = any(w in text for w in ("cycle", "period", "luteal"))
    asked_train = any(w in text for w in ("train", "workout", "session"))
    if pace != "unknown" and has_phys:
        if (
            cycle_on
            and sex != "male"
            and asked_cycle
            and coverage.get("sex_aware", 0.0) < 0.6
        ):
            return (
                "whether this is a high-symptom cycle day",
                "that one fact changes load; do not invent a chart",
            )
        return "", "enough to coach — do not fish for more"
    if not has_phys and has_life:
        return (
            "how last night actually slept",
            "to tell body wear from a stacked social or work day",
        )
    if not has_phys and not has_life:
        if asked_train or "should i" in text:
            return (
                "last night's sleep or how stacked today is — pick one",
                "one signal changes the call; both is more than we need",
            )
        return "", "don't invent a body or a calendar they did not give"
    if asked_cycle and sex != "male" and coverage.get("sex_aware", 0.0) < 0.5:
        return (
            "whether cycle tracking is even on",
            "only because they asked; never guess sex or a phase",
        )
    return "", "enough to coach — do not fish for more"


def _reason_from_factors(pace: str, factors: tuple[AgingFactor, ...]) -> str:
    if pace == "unknown":
        return "no body signal yet — not guessing an aging pace"
    names = []
    for factor in factors:
        if factor.id not in names:
            names.append(factor.id)
    named = ", ".join(names[:4]) if names else "the signals we actually have"
    if pace == "faster":
        return (
            f"wear is outrunning repair because {named} — "
            "name those reasons, never a biological-age number"
        )
    if pace == "slower":
        return (
            f"repair is holding ({named}) — they can spend readiness on quality work, "
            "not because of a younger age number"
        )
    return (
        f"wear and repair are even ({named}) — keep the day honest, "
        "don't invent urgency or years"
    )


def evaluate_aging(ctx: Any, message: str = "") -> AgingRead:
    """Are they taking more wear than they are repairing, lately — and why?"""
    text = (message or "").lower()
    cal = _calendar_snapshot(ctx)
    kinds = tuple(str(k) for k in cal["kinds"])
    kind_set = set(kinds)
    wear = 0.0
    found: list[AgingFactor] = []
    n_body = 0

    trend = _hrv_trend(ctx)
    if trend is not None:
        n_body += 1
        if trend <= -8:
            wear += 0.35
            found.append(_factor("hrv", "physiological", 0.35, "HRV trend is down — repair is lagging"))
        elif trend >= 5:
            wear -= 0.20
            found.append(_factor("hrv", "physiological", -0.20, "HRV trend is holding — repair is available"))

    recovery = _recovery(ctx)
    if recovery is not None:
        n_body += 1
        if recovery < 0.50:
            wear += 0.30
            found.append(_factor("recovery", "physiological", 0.30, "recovery is thin"))
        elif recovery >= 0.75:
            wear -= 0.22
            found.append(_factor("recovery", "physiological", -0.22, "recovery is in the bank"))

    sleep_h = _sleep_hours(ctx)
    if sleep_h is not None:
        n_body += 1
        if sleep_h < 6.5:
            wear += 0.25
            found.append(_factor("sleep", "physiological", 0.25, "last night ran short"))
        elif sleep_h >= 7.5:
            wear -= 0.12
            found.append(_factor("sleep", "physiological", -0.12, "sleep actually landed"))

    # Accumulated debt across the week, not just tonight -- one so-so night
    # alone shouldn't call "faster", but a week of them should, even if
    # tonight happened to be fine. 5.0h mirrors aria_evidence.SLEEP_DEBT_7D_H
    # (duplicated rather than imported: this module is deliberately
    # stdlib-only with no cross-import of aria_evidence). Before this, a
    # genuinely high 7-day debt with an unremarkable single night could pick
    # "train_through" here even while aria_evidence's own evidence graph
    # (and, after fusion.stance_for_plan's matching fix, the fused stance)
    # correctly called it a protect day -- and whichever of the two produced
    # the actual spoken next_step text was a coin flip, not a decision.
    debt_7d = _num(getattr(getattr(ctx, "sleep", None), "sleep_debt_7d_hours", None))
    if debt_7d is not None and debt_7d > 5.0:
        n_body += 1
        wear += 0.35
        found.append(
            _factor(
                "sleep_debt_7d",
                "physiological",
                0.35,
                f"{debt_7d:.1f}h of sleep debt has built up over the week",
            )
        )

    rhr = _resting_hr(ctx)
    if rhr is not None:
        n_body += 1
        if rhr >= 72:
            wear += 0.12
            found.append(_factor("rhr", "physiological", 0.12, "resting heart rate is running high"))
        elif rhr <= 58:
            wear -= 0.08
            found.append(_factor("rhr", "physiological", -0.08, "resting heart rate is quiet"))

    n_fast = sum(1 for cue in _FASTER_CUES if cue in text)
    n_slow = sum(1 for cue in _SLOWER_CUES if cue in text)
    if n_fast > n_slow:
        wear += 0.18
        found.append(
            _factor("conversation", "physiological", 0.18, "they said they don't bounce back like they used to")
        )
    elif n_slow > n_fast:
        wear -= 0.18
        found.append(
            _factor("conversation", "physiological", -0.18, "they said repair is actually holding")
        )

    if kind_set & SOCIAL_KINDS:
        social_n = len(kind_set & SOCIAL_KINDS)
        bump = min(0.22, 0.10 + 0.04 * (social_n - 1))
        wear += bump
        label = "wedding" if "wedding" in kind_set else "social"
        found.append(
            _factor(
                label,
                "social",
                bump,
                "a classified gathering is on the week — that is life load, never a guest list",
            )
        )
    if kind_set & WORK_KINDS:
        bump = 0.16 + (0.10 if cal["evening_busy"] else 0.0)
        wear += bump
        found.append(
            _factor(
                "work",
                "socioeconomic",
                bump,
                "work is on the calendar — socioeconomic load, not a personality flaw",
            )
        )
    elif cal["evening_busy"]:
        wear += 0.10
        found.append(
            _factor("evening", "social", 0.10, "evening is already spoken for")
        )
    if "surprise" in kind_set:
        # extra to social bump — unplanned visits hit harder than a planned dinner
        wear += 0.12
        found.append(
            _factor("surprise", "social", 0.12, "a surprise visit is unplanned load")
        )

    occ = _occupation(ctx)
    constraints = list(getattr(ctx, "constraints", None) or [])
    profile = getattr(ctx, "profile", None)
    constraints.extend(list(getattr(profile, "constraints", None) or []))
    joined_c = " ".join(str(c).lower() for c in constraints)
    if any(token in joined_c for token in ("night shift", "two jobs", "double shift", "money tight")):
        wear += 0.16
        found.append(
            _factor(
                "shift_load",
                "socioeconomic",
                0.16,
                "how they earn a living is stacking wear — name that, not years",
            )
        )

    sex = _sex(ctx)
    cycle_on = _cycle_tracking(ctx)
    cycle_talk = any(w in text for w in ("period", "luteal", "cycle day", "pms"))
    if (cycle_on or sex == "female") and cycle_talk and (recovery is not None and recovery < 0.55):
        wear += 0.10
        found.append(
            _factor(
                "cycle",
                "sex_aware",
                0.10,
                "they named a cycle day with thin recovery — coach the day, don't invent a chart",
            )
        )

    stress_load, stress_state, stress_factors = _stress_algorithm(
        hrv_trend=trend,
        recovery=recovery,
        rhr=rhr,
        kinds=kinds,
        evening_busy=bool(cal["evening_busy"]),
        busy_today=int(cal["busy_today"] or 0),
        text=text,
    )
    for factor in stress_factors:
        if all(existing.id != factor.id for existing in found):
            found.append(factor)
            wear += max(0.0, factor.contribution)

    qol = _num(getattr(getattr(ctx, "lifestyle", None), "quality_of_life_score", None))
    if qol is not None:
        band = getattr(getattr(ctx, "lifestyle", None), "quality_of_life_band", None)
        if not isinstance(band, str) or not band:
            if qol >= 85:
                band = "thriving"
            elif qol >= 70:
                band = "steady"
            elif qol >= 50:
                band = "strained"
            else:
                band = "depleted"
        if band == "depleted" or qol < 50:
            wear += 0.10
            found.append(
                _factor(
                    "life_rhythm",
                    "social",
                    0.10,
                    "life rhythm is depleted — a better-life plan, not a biological-age lecture",
                )
            )
        elif band == "strained" or qol < 70:
            wear += 0.06
            found.append(
                _factor(
                    "life_rhythm",
                    "social",
                    0.06,
                    "life rhythm is strained — ease the day, not a biological-age lecture",
                )
            )

    coverage = {
        "physiological": 1.0 if n_body else 0.0,
        "social": 1.0 if (kind_set & SOCIAL_KINDS or any(c in text for c in _GATHERING_CUES + _SURPRISE_CUES)) else (0.4 if cal["evening_busy"] else 0.0),
        "socioeconomic": min(
            1.0,
            (0.45 if occ else 0.0)
            + (0.45 if kind_set & WORK_KINDS else 0.0)
            + (0.25 if "shift" in joined_c else 0.0),
        ),
        "sex_aware": (
            1.0 if sex == "male" else
            (0.8 if (cycle_on and cycle_talk) else (0.4 if (cycle_on or sex == "female") else 0.0))
        ),
    }

    unique: list[AgingFactor] = []
    seen_ids: set[str] = set()
    for factor in found:
        if factor.id in seen_ids:
            continue
        seen_ids.add(factor.id)
        unique.append(factor)

    n_spoken = n_fast + n_slow
    has_life = bool(kind_set or cal["evening_busy"] or cal["morning_busy"])
    if n_body == 0 and n_spoken == 0 and not unique:
        ask, why = _right_sized_ask(
            pace="unknown",
            coverage=coverage,
            has_phys=False,
            has_life=has_life,
            text=text,
            sex=sex,
            cycle_on=cycle_on,
        )
        return AgingRead(ask_next=ask, ask_why=why, coverage=tuple(coverage.items()))

    pace = "on_pace"
    if n_body == 0 and n_fast > n_slow:
        pace = "faster"
    elif n_body == 0 and n_slow > n_fast:
        pace = "slower"
    elif wear >= 0.40:
        pace = "faster"
    elif wear <= -0.15:
        pace = "slower"

    # A faster/slower call without named reasons is not a claim Forge may make.
    if pace in ("faster", "slower") and not unique:
        pace = "unknown"

    ask, why = _right_sized_ask(
        pace=pace,
        coverage=coverage,
        has_phys=n_body > 0,
        has_life=has_life,
        text=text,
        sex=sex,
        cycle_on=cycle_on,
    )
    signals = tuple(f.id for f in unique)
    return AgingRead(
        pace=pace,
        wear=round(_clip(wear, -1.0, 1.5), 4),
        signals=signals,
        reason=_reason_from_factors(pace, tuple(unique)),
        factors=tuple(unique),
        stress_state=stress_state,
        stress_load=stress_load,
        coverage=tuple(coverage.items()),
        ask_next=ask,
        ask_why=why,
        years_claimed=None,
    )


def _better_life(aging: AgingRead, choice: str, headline: bool) -> dict[str, Any]:
    """Structural plan for a better life — restore, move, fuel, connect, work."""
    ids = {f.id for f in aging.factors}
    stress_high = aging.stress_state == "high"
    restore = "pressing" if aging.pace == "faster" or "sleep" in ids or stress_high else (
        "steady" if aging.pace == "slower" else "unknown"
    )
    move = "protect" if choice in ("protect_load", "sleep_first") or headline else (
        "quality" if choice == "train_through" else "unknown"
    )
    fuel = "pressing" if choice == "fuel" else "steady"
    connect = "event" if ids & {"wedding", "social", "gathering", "surprise", "family"} or headline else "steady"
    work = "pressing" if ids & {"work", "shift_load"} else "steady"

    moves = {
        "restore": (
            "Protect tonight. Sleep and stress are the levers — not a younger number."
            if restore == "pressing"
            else "Keep the night honest so repair can keep up."
        ),
        "move": (
            "Fit a shorter session around the life they actually have."
            if move == "protect"
            else "Spend readiness on one session they can finish."
        ),
        "fuel": (
            "Protein and water with the next meal, then the session."
            if fuel == "pressing"
            else "Eat the day they already have — don't add a diet lecture."
        ),
        "connect": (
            "Protect load around the gathering. Do not name titles, people, or places."
            if connect == "event"
            else "Keep connection in the week without stacking a hero session on it."
        ),
        "work_life": (
            "Work is load. Train inside the windows that are actually free."
            if work == "pressing"
            else "Keep work and training from fighting for the same hour."
        ),
    }
    pillars = []
    for name in BETTER_LIFE_PILLARS:
        status = {"restore": restore, "move": move, "fuel": fuel, "connect": connect, "work_life": work}[name]
        pillars.append(
            {
                "id": name,
                "status": status,
                "move": _clean_speak(moves[name]),
            }
        )
    why = [_clean_speak(f.why) for f in aging.factors[:5]]
    return {
        "pillars": pillars,
        "why": why,
        "ask_next": _clean_speak(aging.ask_next),
        "years_claimed": None,
    }


@dataclass
class SupervisionPlan:
    """The plan ARIA stores as context, then coaches from."""

    aging_pace: str = "unknown"
    aging_reason: str = ""
    choice: str = "clarify"
    next_advice: str = ""
    guide: str = ""
    signals: tuple[str, ...] = ()
    stance_hint: str = "clarify"
    wear: float = 0.0
    factors: tuple[AgingFactor, ...] = ()
    stress_state: str = "unknown"
    stress_load: float = 0.0
    coverage: tuple[tuple[str, float], ...] = ()
    ask_next: str = ""
    ask_why: str = ""
    better_life: dict[str, Any] | None = None
    years_claimed: None = None

    def as_dict(self) -> dict[str, Any]:
        life = dict(self.better_life or {})
        life["years_claimed"] = None
        return {
            "aging_pace": self.aging_pace,
            "aging_reason": _clean_speak(self.aging_reason),
            "choice": self.choice,
            "next_advice": _clean_speak(self.next_advice),
            "guide": _clean_speak(self.guide),
            "signals": list(self.signals),
            "stance_hint": self.stance_hint,
            "wear": round(self.wear, 4),
            "factors": [f.as_dict() if isinstance(f, AgingFactor) else f for f in self.factors],
            "stress": {"state": self.stress_state, "load": round(self.stress_load, 4)},
            "coverage": {lane: round(score, 4) for lane, score in self.coverage},
            "ask_next": _clean_speak(self.ask_next),
            "ask_why": _clean_speak(self.ask_why),
            "better_life": life,
            "years_claimed": None,
        }


def _factors_from_raw(raw: Any) -> tuple[AgingFactor, ...]:
    if not isinstance(raw, list):
        return ()
    out: list[AgingFactor] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        fid = str(item.get("id") or "").strip()
        lane = str(item.get("lane") or "physiological")
        if not fid or lane not in LANES:
            continue
        try:
            contrib = float(item.get("contribution") or 0.0)
        except (TypeError, ValueError):
            contrib = 0.0
        why = _clean_speak(str(item.get("why") or "")[:240])
        out.append(AgingFactor(fid, lane, contrib, why))
    return tuple(out)


def plan_from_dict(raw: Any) -> SupervisionPlan | None:
    if not isinstance(raw, dict):
        return None
    choice = str(raw.get("choice") or "clarify")
    if choice not in PLAN_CHOICES:
        choice = "clarify"
    pace = str(raw.get("aging_pace") or "unknown")
    if pace not in AGING_PACES:
        pace = "unknown"
    signals = raw.get("signals")
    sig_tuple = tuple(str(s) for s in signals) if isinstance(signals, list) else ()
    advice = _clean_speak(str(raw.get("next_advice") or "")[:240])
    guide = _clean_speak(str(raw.get("guide") or "")[:240])
    reason = _clean_speak(str(raw.get("aging_reason") or "")[:240])
    hint = str(raw.get("stance_hint") or CHOICE_TO_STANCE.get(choice, "clarify"))
    wear = 0.0
    try:
        wear = float(raw.get("wear") or 0.0)
    except (TypeError, ValueError):
        wear = 0.0
    stress = raw.get("stress") if isinstance(raw.get("stress"), dict) else {}
    stress_state = str(stress.get("state") or "unknown")
    try:
        stress_load = float(stress.get("load") or 0.0)
    except (TypeError, ValueError):
        stress_load = 0.0
    cov_raw = raw.get("coverage") if isinstance(raw.get("coverage"), dict) else {}
    coverage = tuple(
        (str(k), float(v))
        for k, v in cov_raw.items()
        if k in LANES and isinstance(v, (int, float))
    )
    life = raw.get("better_life") if isinstance(raw.get("better_life"), dict) else None
    return SupervisionPlan(
        aging_pace=pace,
        aging_reason=reason,
        choice=choice,
        next_advice=advice,
        guide=guide,
        signals=sig_tuple,
        stance_hint=hint if hint in ("protect", "proceed", "fuel", "clarify") else "clarify",
        wear=wear,
        factors=_factors_from_raw(raw.get("factors")),
        stress_state=stress_state if stress_state in ("high", "moderate", "low", "unknown") else "unknown",
        stress_load=stress_load,
        coverage=coverage,
        ask_next=_clean_speak(str(raw.get("ask_next") or "")[:240]),
        ask_why=_clean_speak(str(raw.get("ask_why") or "")[:240]),
        better_life=life,
        years_claimed=None,
    )


def _plan_q(state: Any, pace: str, choice: str) -> float:
    table = getattr(state, "plan_q", None) or {}
    row = table.get(pace) if isinstance(table, dict) else None
    if not isinstance(row, dict):
        return 0.0
    try:
        return float(row.get(choice, 0.0) or 0.0)
    except (TypeError, ValueError):
        return 0.0


def _set_plan_q(state: Any, pace: str, choice: str, value: float) -> None:
    table = getattr(state, "plan_q", None)
    if not isinstance(table, dict):
        table = {}
        state.plan_q = table
    row = table.get(pace)
    if not isinstance(row, dict):
        row = {c: 0.0 for c in PLAN_CHOICES}
        table[pace] = row
    row[choice] = round(float(value), 4)


def _pick_choice(
    state: Any,
    aging: AgingRead,
    *,
    headline: bool,
    evening_busy: bool,
    asked_to_train: bool,
    asked_to_eat: bool,
    missing: bool,
    stress_high: bool,
    surprise: bool,
) -> str:
    pace = aging.pace
    priors = _CHOICE_PRIOR.get(pace, _CHOICE_PRIOR["unknown"])
    scores: dict[str, float] = {}
    for choice in PLAN_CHOICES:
        scores[choice] = float(priors.get(choice, 0.4)) + 1.8 * _plan_q(state, pace, choice)
    if headline or evening_busy:
        scores["protect_load"] = scores.get("protect_load", 0.0) + 1.1
        scores["train_through"] = scores.get("train_through", 0.0) - 0.7
    if stress_high:
        scores["protect_load"] = scores.get("protect_load", 0.0) + 0.45
        scores["sleep_first"] = scores.get("sleep_first", 0.0) + 0.25
        scores["train_through"] = scores.get("train_through", 0.0) - 0.35
    if surprise:
        scores["protect_load"] = scores.get("protect_load", 0.0) + 0.30
    if asked_to_eat:
        scores["fuel"] = scores.get("fuel", 0.0) + 0.9
    if asked_to_train and pace != "faster":
        scores["train_through"] = scores.get("train_through", 0.0) + 0.55
    if missing and pace == "unknown":
        scores["clarify"] = scores.get("clarify", 0.0) + 0.8
    return max(PLAN_CHOICES, key=lambda c: (scores.get(c, 0.0), c))


def _advice(choice: str, aging: AgingRead, headline: bool) -> str:
    if headline:
        return (
            "Fit today's work around the life event and busy windows. "
            "Protect load; do not name titles. Do not turn this into a biological-age number."
        )
    if aging.ask_next and choice == "clarify":
        return f"Ask for {aging.ask_next}. {aging.ask_why or 'One signal. Not a form.'}"
    if choice == "sleep_first":
        return "Sleep is the lever. Keep tonight protected before adding training load."
    if choice == "protect_load":
        if aging.stress_state == "high":
            return "Stress is a named reason to protect load — shorter session, not a hero day, not an age."
        return "Guide toward a shorter, lighter session that still counts — not a hero day."
    if choice == "train_through":
        return "They have repair in the bank. Spend it on one quality session in the slot they actually use."
    if choice == "fuel":
        return "Protein and water with the next meal, then train inside the day they already have."
    return "Say what is missing. Do not invent an aging pace, a year gap, or a body you were not given."


def _guide(choice: str, aging: AgingRead) -> str:
    if aging.pace == "faster":
        named = ", ".join(f.id for f in aging.factors[:3]) or "the signals we have"
        return (
            f"Supervise like a coach who noticed wear outrunning repair because {named}. "
            "Steer them to the choice that restores. Never say they aged a number of years."
        )
    if aging.stress_state == "high":
        return "Name stress as load. Protect the day. Do not diagnose. Do not quote a biological age."
    if choice == "train_through":
        return (
            "Guide them into the session they can finish. "
            "Suggest the work; do not command it."
        )
    if choice == "fuel":
        return "Steer the next meal first, then the session. Habit, not a diet lecture."
    if choice == "clarify":
        if aging.ask_next:
            return f"Ask only: {aging.ask_next}. Do not fill gaps with a story about aging."
        return "Ask for the one missing signal. Do not fill gaps with a story about aging."
    return "Keep them on the better-life plan: protect load, then learn from whether they actually did."


def draft_plan(message: str, ctx: Any, persona: Any) -> SupervisionPlan:
    """Pure: raw data + learned persona → today's supervision plan."""
    aging = evaluate_aging(ctx, message)
    cal = _calendar_snapshot(ctx)
    headline = bool(cal["headlines"])
    evening_busy = bool(cal["evening_busy"])
    missing = False
    try:
        from .contextual_learner import _missing_ratio

        missing = _missing_ratio(ctx) >= 0.55
    except Exception:
        missing = False

    text = (message or "").lower()
    asked_to_train = any(w in text for w in ("train", "workout", "session"))
    asked_to_eat = any(w in text for w in ("eat", "food", "protein", "meal"))
    surprise = "surprise" in set(cal["kinds"]) or any(cue in text for cue in _SURPRISE_CUES)
    choice = _pick_choice(
        persona,
        aging,
        headline=headline,
        evening_busy=evening_busy,
        asked_to_train=asked_to_train,
        asked_to_eat=asked_to_eat,
        missing=missing,
        stress_high=aging.stress_state == "high",
        surprise=surprise,
    )
    return SupervisionPlan(
        aging_pace=aging.pace,
        aging_reason=aging.reason,
        choice=choice,
        next_advice=_advice(choice, aging, headline),
        guide=_guide(choice, aging),
        signals=aging.signals,
        stance_hint=CHOICE_TO_STANCE.get(choice, "clarify"),
        wear=aging.wear,
        factors=aging.factors,
        stress_state=aging.stress_state,
        stress_load=aging.stress_load,
        coverage=aging.coverage,
        ask_next=aging.ask_next,
        ask_why=aging.ask_why,
        better_life=_better_life(aging, choice, headline),
        years_claimed=None,
    )


def apply_plan(state: Any, plan: SupervisionPlan) -> SupervisionPlan:
    """Store the plan on the persona so it is context for the next coaching call."""
    aging = getattr(state, "aging", None)
    if not isinstance(aging, dict) or not aging:
        aging = default_aging()
        state.aging = aging
    if plan.aging_pace in aging:
        aging[plan.aging_pace] = float(aging.get(plan.aging_pace, 1.0)) + 1.0
        try:
            state.n_aging = int(getattr(state, "n_aging", 0) or 0) + 1
        except (TypeError, ValueError):
            state.n_aging = 1
    state.last_plan = plan.as_dict()
    state.last_plan_choice = plan.choice
    state.last_aging_pace = plan.aging_pace
    return plan


def evaluate_and_store(state: Any, message: str, ctx: Any) -> SupervisionPlan:
    plan = draft_plan(message, ctx, state)
    return apply_plan(state, plan)


def credit_plan(state: Any, reward: float) -> float:
    """Retroactive TD on the plan choice that ARIA committed to."""
    choice = getattr(state, "last_plan_choice", None)
    pace = getattr(state, "last_aging_pace", None)
    if choice not in PLAN_CHOICES or pace not in AGING_PACES or pace == "unknown":
        return 0.0
    q_sa = _plan_q(state, pace, choice)
    try:
        alpha = float(getattr(state, "td_alpha", 0.28) or 0.28)
    except (TypeError, ValueError):
        alpha = 0.28
    alpha = _clip(alpha, 0.08, 0.55)
    delta = float(reward) - q_sa
    _set_plan_q(state, pace, choice, q_sa + alpha * delta)
    return round(delta, 6)
