"""Raw-data supervision plan — what ARIA stores as context and then follows.

This is the data engine sitting under ARIA the coach: take raw signals
(recovery, sleep, HRV, calendar kinds/busy windows, what they said, aging
pace), evaluate them, and write a compact **plan**. ARIA uses that plan as
context for the next piece of advice and for how to guide the person. Later
outcomes (complete, skip, thumbs, "that helped") credit the plan's choice
retroactively so the next plan is learned, not only the stance.

Dummy must never import this module. Persistence stays on ``ARIA#PERSONA``
and living ``UserContext.supervision_plan``. Deleting dummy leaves this file.

Aging pace is a **lifestyle wear/repair read**, not a diagnosis or a
biological-age number. "Faster" means the body is taking more wear than it
is repairing lately; "slower" means recovery is holding. Never invent a
calendar title. Never prescribe.

Stdlib only. Deterministic. Lambda hot path.
"""

from __future__ import annotations

from dataclasses import dataclass, field
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


@dataclass(frozen=True)
class AgingRead:
    """Lifestyle wear/repair — not a clinical biological age."""

    pace: str = "unknown"
    wear: float = 0.0
    signals: tuple[str, ...] = ()
    reason: str = "no body signal yet — not guessing an aging pace"

    def as_dict(self) -> dict[str, Any]:
        return {
            "pace": self.pace,
            "wear": round(self.wear, 4),
            "signals": list(self.signals),
            "reason": self.reason,
        }


def evaluate_aging(ctx: Any, message: str = "") -> AgingRead:
    """Are they taking more wear than they are repairing, lately?"""
    text = (message or "").lower()
    wear = 0.0
    found: list[str] = []
    n_body = 0

    trend = _hrv_trend(ctx)
    if trend is not None:
        n_body += 1
        if trend <= -8:
            wear += 0.35
            found.append("hrv")
        elif trend >= 5:
            wear -= 0.20
            found.append("hrv")

    recovery = _recovery(ctx)
    if recovery is not None:
        n_body += 1
        if recovery < 0.50:
            wear += 0.30
            found.append("recovery")
        elif recovery >= 0.75:
            wear -= 0.22
            found.append("recovery")

    sleep_h = _sleep_hours(ctx)
    if sleep_h is not None:
        n_body += 1
        if sleep_h < 6.5:
            wear += 0.25
            found.append("sleep")
        elif sleep_h >= 7.5:
            wear -= 0.12
            found.append("sleep")

    rhr = _resting_hr(ctx)
    if rhr is not None:
        n_body += 1
        if rhr >= 72:
            wear += 0.12
            found.append("rhr")
        elif rhr <= 58:
            wear -= 0.08
            found.append("rhr")

    n_fast = sum(1 for cue in _FASTER_CUES if cue in text)
    n_slow = sum(1 for cue in _SLOWER_CUES if cue in text)
    if n_fast > n_slow:
        wear += 0.18
        found.append("conversation")
    elif n_slow > n_fast:
        wear -= 0.18
        found.append("conversation")

    if n_body == 0 and n_fast == 0 and n_slow == 0:
        return AgingRead()

    pace = "on_pace"
    if n_body == 0 and n_fast > n_slow:
        pace = "faster"
    elif n_body == 0 and n_slow > n_fast:
        pace = "slower"
    elif wear >= 0.40:
        pace = "faster"
    elif wear <= -0.15:
        pace = "slower"

    if pace == "faster":
        reason = "wear is outrunning repair lately — guide toward recovery, not a harder session"
    elif pace == "slower":
        reason = "repair is holding — they can spend readiness on quality work"
    else:
        reason = "wear and repair are even — keep the day honest, don't invent urgency"

    unique: list[str] = []
    for name in found:
        if name not in unique:
            unique.append(name)
    return AgingRead(pace, round(_clip(wear, -1.0, 1.5), 4), tuple(unique), reason)


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

    def as_dict(self) -> dict[str, Any]:
        return {
            "aging_pace": self.aging_pace,
            "aging_reason": self.aging_reason,
            "choice": self.choice,
            "next_advice": self.next_advice,
            "guide": self.guide,
            "signals": list(self.signals),
            "stance_hint": self.stance_hint,
            "wear": round(self.wear, 4),
        }


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
    advice = str(raw.get("next_advice") or "")[:240]
    guide = str(raw.get("guide") or "")[:240]
    reason = str(raw.get("aging_reason") or "")[:240]
    hint = str(raw.get("stance_hint") or CHOICE_TO_STANCE.get(choice, "clarify"))
    wear = 0.0
    try:
        wear = float(raw.get("wear") or 0.0)
    except (TypeError, ValueError):
        wear = 0.0
    return SupervisionPlan(
        aging_pace=pace,
        aging_reason=reason,
        choice=choice,
        next_advice=advice,
        guide=guide,
        signals=sig_tuple,
        stance_hint=hint if hint in ("protect", "proceed", "fuel", "clarify") else "clarify",
        wear=wear,
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
) -> str:
    pace = aging.pace
    priors = _CHOICE_PRIOR.get(pace, _CHOICE_PRIOR["unknown"])
    scores: dict[str, float] = {}
    for choice in PLAN_CHOICES:
        scores[choice] = float(priors.get(choice, 0.4)) + 1.8 * _plan_q(state, pace, choice)
    if headline or evening_busy:
        scores["protect_load"] = scores.get("protect_load", 0.0) + 1.1
        scores["train_through"] = scores.get("train_through", 0.0) - 0.7
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
            "Protect load; do not name titles."
        )
    if choice == "sleep_first":
        return "Sleep is the lever. Keep tonight protected before adding training load."
    if choice == "protect_load":
        return "Guide toward a shorter, lighter session that still counts — not a hero day."
    if choice == "train_through":
        return "They have repair in the bank. Spend it on one quality session in the slot they actually use."
    if choice == "fuel":
        return "Protein and water with the next meal, then train inside the day they already have."
    return "Say what is missing. Do not invent an aging pace or a body you were not given."


def _guide(choice: str, aging: AgingRead) -> str:
    if aging.pace == "faster":
        return (
            "Supervise like a coach who noticed wear outrunning repair. "
            "Steer them to the choice that restores, without scolding or diagnosing."
        )
    if choice == "train_through":
        return (
            "Guide them into the session they can finish. "
            "Suggest the work; do not command it."
        )
    if choice == "fuel":
        return "Steer the next meal first, then the session. Habit, not a diet lecture."
    if choice == "clarify":
        return "Ask for the one missing signal. Do not fill gaps with a story about aging."
    return "Keep them on the plan: protect load, then learn from whether they actually did."


def draft_plan(message: str, ctx: Any, persona: Any) -> SupervisionPlan:
    """Pure: raw data + learned persona → today's supervision plan."""
    aging = evaluate_aging(ctx, message)
    headline = False
    evening_busy = False
    missing = False
    try:
        from .contextual_learner import parse_calendar, _lifestyle_tags, _missing_ratio

        cal = parse_calendar(_lifestyle_tags(ctx))
        headline = bool(cal.headlines)
        evening_busy = bool(cal.evening_busy)
        missing = _missing_ratio(ctx) >= 0.55
    except Exception:
        tags = getattr(getattr(ctx, "lifestyle", None), "tags", None) or []
        joined = " ".join(str(t) for t in tags)
        headline = any(
            f"calendar:kind:{kind}" in joined
            for kind in ("wedding", "game", "flight", "travel")
        )
        evening_busy = "calendar:evening:busy" in joined

    text = (message or "").lower()
    asked_to_train = any(w in text for w in ("train", "workout", "session"))
    asked_to_eat = any(w in text for w in ("eat", "food", "protein", "meal"))
    choice = _pick_choice(
        persona,
        aging,
        headline=headline,
        evening_busy=evening_busy,
        asked_to_train=asked_to_train,
        asked_to_eat=asked_to_eat,
        missing=missing,
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
