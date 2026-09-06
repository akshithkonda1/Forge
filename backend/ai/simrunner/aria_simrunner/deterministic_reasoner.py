"""Deterministic reasoner for the dummy ARIA orchestrator. No Bedrock."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

Action = Literal["recover", "train", "hold", "clarify", "honest", "fuel", "support", "talk"]
Topic = Literal["life", "train", "sleep", "fuel", "support", "mixed"]

_FEEL = ("slept badly", "slept terrible", "awful night", "didn't sleep", "didnt sleep", "rough night", "bad night", "woke up wrecked")
_PUSH = ("hard", "push", "as hard", "max effort", "pr", "heavy")
_FUEL = ("eat", "food", "meal", "protein", "hungry", "water", "hydrat")
_SLEEP = ("sleep", "slept", "last night", "insomnia", "wind down")
_CYCLE = ("show up", "cycle", "period", "luteal", "pms")
_WORK = ("work", "job", "boss", "meeting", "meetings", "school", "students", "shift", "office", "deadline")
_PEOPLE = ("partner", "wife", "husband", "girlfriend", "boyfriend", "kids", "kid", "family", "sam", "maya", "show up for")
_STRESS = ("stress", "stressed", "overwhelmed", "anxious", "anxiety", "mental load", "burned out", "too much", "long day", "brutal day")
_DAY = ("how was my day", "my day", "today was", "this week", "life")
_MOOD = ("don't want to", "dont want to", "unmotivated", "what's the point", "feeling off")
_OCC = {
    "teacher": "a teacher's week already spends you",
    "student": "a student week doesn't leave a clean block",
    "engineer": "a sitting-all-day job still costs the body",
    "triathlete": "the training is the job, so the rest has to be real rest",
    "founder": "the company will take every hour you don't defend",
}


@dataclass(frozen=True)
class TypedSignals:
    sleep_hours: float | None
    sleep_quality: str
    readiness: float
    readiness_trend: str
    hrv: float | None
    hrv_trend: str
    sleep_debt_7d: float
    acwr: float
    is_overtrained: bool
    training_streak: int
    days_since_last_workout: int
    load: str
    has_sleep: bool
    has_hrv: bool
    is_data_sparse: bool
    occupation: str
    life_clause: str
    last_session: str
    notable: str
    felt_bad: bool
    wants_push: bool
    asked_fuel: bool
    asked_sleep: bool
    asked_cycle: bool
    asked_train: bool
    topic: Topic = "mixed"
    work_talk: bool = False
    people_talk: bool = False
    stress_talk: bool = False
    mood_talk: bool = False
    heard: str = ""
    target_sleep: float | None = None
    deep_sleep_minutes: float | None = None
    rem_sleep_minutes: float | None = None
    resting_hr: float | None = None


@dataclass(frozen=True)
class Decision:
    action: Action
    confidence: float
    reasons: tuple[str, ...] = field(default_factory=tuple)
    signals: TypedSignals | None = None

    def as_dict(self) -> dict:
        payload = {"action": self.action, "confidence": round(self.confidence, 2), "reasons": list(self.reasons)}
        if self.signals is not None:
            payload["data"] = {
                "sleep_hours": self.signals.sleep_hours,
                "readiness": self.signals.readiness,
                "hrv": self.signals.hrv,
                "sleep_debt_7d": self.signals.sleep_debt_7d,
                "acwr": round(self.signals.acwr, 2),
                "missing": [n for n, p in (("sleep", self.signals.has_sleep), ("hrv", self.signals.has_hrv)) if not p],
            }
        return payload


def _hours(v: float) -> str:
    return f"{v:.1f}".rstrip("0").rstrip(".") + " hours"


def extract_signals(context, message: str) -> TypedSignals:
    today = context.today
    sleep_h = today.total_sleep_hours
    if sleep_h is None:
        sq = "unknown"
    elif sleep_h < 6.4:
        sq = "thin"
    elif sleep_h >= 7.4:
        sq = "rebuilt"
    else:
        sq = "decent"
    if context.training_streak >= 3:
        load = "on_a_streak"
    elif today.workout_logged or context.days_since_last_workout == 0:
        load = "in_the_legs"
    elif context.days_since_last_workout >= 3:
        load = "fresh"
    else:
        load = "quiet"
    occ = str(getattr(context, "occupation", "") or "").strip().lower()
    last_type = getattr(context, "last_workout_type", None) or today.workout_type
    last = str(last_type).replace("_", " ") if last_type and last_type != "rest" else ""
    notable = ""
    if getattr(context, "has_notable_event", False) and context.notable_event_note:
        notable = str(context.notable_event_note).strip()
    lower = message.lower()
    work = any(c in lower for c in _WORK)
    people = any(c in lower for c in _PEOPLE)
    stress = any(c in lower for c in _STRESS)
    mood = any(c in lower for c in _MOOD)
    day = any(c in lower for c in _DAY)
    asked_fuel = any(c in lower for c in _FUEL)
    asked_sleep = any(c in lower for c in _SLEEP)
    asked_cycle = any(c in lower for c in _CYCLE)
    asked_train = any(c in lower for c in ("train", "workout", "session", "gym", "lift"))
    life_heavy = work or people or stress or day or mood or asked_cycle
    if life_heavy and not asked_train and not asked_sleep and not asked_fuel:
        topic = "life"
    elif asked_train:
        topic = "train"
    elif asked_fuel:
        topic = "fuel"
    elif asked_sleep:
        topic = "sleep"
    else:
        topic = "life" if life_heavy else "mixed"
    heard = ", ".join([x for x, on in (("work", work), ("the people around you", people), ("stress", stress), ("how you are feeling", mood), ("how to show up", asked_cycle)) if on]) or "what you just said"
    return TypedSignals(
        sleep_hours=sleep_h, sleep_quality=sq, readiness=float(today.readiness_score),
        readiness_trend=str(getattr(context, "readiness_trend", "stable")), hrv=today.hrv,
        hrv_trend=str(getattr(context, "hrv_7d_trend", "stable")),
        sleep_debt_7d=float(getattr(context, "sleep_debt_7d_hours", 0) or 0),
        acwr=float(getattr(context, "acwr", None) or getattr(today, "acwr", 1.0) or 1.0),
        is_overtrained=bool(getattr(context, "is_overtrained", False)),
        training_streak=int(context.training_streak),
        days_since_last_workout=int(context.days_since_last_workout),
        load=load,
        has_sleep=bool(getattr(context, "has_sleep", sleep_h is not None)),
        has_hrv=bool(getattr(context, "has_hrv", today.hrv is not None)),
        is_data_sparse=bool(getattr(context, "is_data_sparse", False)),
        occupation=occ, life_clause=_OCC.get(occ, ""), last_session=last, notable=notable,
        felt_bad=any(c in lower for c in _FEEL), wants_push=any(c in lower for c in _PUSH),
        asked_fuel=asked_fuel, asked_sleep=asked_sleep, asked_cycle=asked_cycle, asked_train=asked_train,
        topic=topic, work_talk=work, people_talk=people, stress_talk=stress, mood_talk=mood, heard=heard,
        target_sleep=float(getattr(context, "target_sleep_hours", 8) or 8),
        deep_sleep_minutes=getattr(today, "deep_sleep_minutes", None),
        rem_sleep_minutes=getattr(today, "rem_sleep_minutes", None),
        resting_hr=getattr(today, "resting_hr", None),
    )


def decide(signals: TypedSignals) -> Decision:
    if signals.topic == "life" and not signals.asked_train:
        return Decision("talk", 0.74, ("they came to talk about life, not a session",), signals)
    if signals.asked_cycle and not signals.asked_train:
        return Decision("support", 0.68, ("support question",), signals)
    if signals.is_data_sparse or (not signals.has_sleep and not signals.has_hrv):
        return Decision("clarify", 0.30, ("not enough of this person is in the room yet",), signals)
    if signals.felt_bad and signals.sleep_quality in ("rebuilt", "decent"):
        return Decision("recover", 0.78, ("feeling outranks the chart",), signals)
    if signals.is_overtrained and signals.wants_push:
        return Decision("recover", 0.82, ("load is already running hot",), signals)
    reasons = []
    if signals.readiness < 50 or signals.sleep_debt_7d > 5.0 or signals.sleep_quality == "thin" or signals.hrv_trend == "falling":
        if signals.readiness < 50: reasons.append("readiness is low")
        if signals.sleep_debt_7d > 5.0: reasons.append("the week is carrying real sleep debt")
        if signals.sleep_quality == "thin": reasons.append("last night was thin")
        if signals.hrv_trend == "falling": reasons.append("recovery trend is falling")
        return Decision("recover", 0.80, tuple(reasons), signals)
    if signals.asked_fuel and not signals.asked_train:
        return Decision("fuel", 0.72, ("fuel question first",), signals)
    if signals.readiness >= 70 and signals.sleep_quality in ("rebuilt", "decent"):
        return Decision("train", 0.85, ("readiness is willing", f"sleep quality is {signals.sleep_quality}"), signals)
    return Decision("hold", 0.60, ("signals are steady but not clearly green",), signals)


def compose_reply(decision: Decision, s: TypedSignals) -> str:
    if decision.action in ("talk", "support") and not s.asked_train:
        heard = f"I heard you. This is about {s.heard}. Showing up is the work. The session can wait."
        body = "When the week is loud, subtract. Food and a cutoff beat a workout. One honest check-in beats a perfect plan."
        if s.life_clause:
            body += f" And specifically: {s.life_clause}."
        sleep = _hours(s.sleep_hours) if s.sleep_hours is not None else "not logged"
        data = f"What the body is doing in the background: last night was {sleep}, readiness sits at {s.readiness:.0f}, trend {s.readiness_trend}, load ratio {s.acwr:.2f}. That colors the day. It does not change the subject."
        close = "What would showing up well look like in the next hour — a text, a meal, or just being in the room without fixing anything?"
        return "\n\n".join([heard, body, data, close])
    sleep_line = "On the night: sleep duration is not on the board."
    if s.sleep_hours is not None:
        extra = ""
        if s.deep_sleep_minutes is not None:
            extra += f" Deep sleep logged {int(s.deep_sleep_minutes)} minutes."
        if s.rem_sleep_minutes is not None:
            extra += f" REM logged {int(s.rem_sleep_minutes)} minutes."
        debt = f" Across seven nights you are about {_hours(s.sleep_debt_7d)} short." if s.sleep_debt_7d > 0 else ""
        feel = " You said it felt rough. That feeling outranks the chart." if s.felt_bad else ""
        sleep_line = f"On the night: the log says {_hours(s.sleep_hours)} against a target of {_hours(s.target_sleep or 8)}.{extra}{debt}{feel}"
    rec = f"On recovery: readiness sits at {s.readiness:.0f}, trend {s.readiness_trend}."
    rec += " Heart-rate variability is not on the board." if s.hrv is None else f" Heart-rate variability is {s.hrv:.0f} milliseconds, trend {s.hrv_trend}."
    if s.resting_hr is not None:
        rec += f" Resting heart rate is {s.resting_hr:.0f}."
    load = f"On load: streak {s.training_streak}, {s.days_since_last_workout} days since last session, load ratio {s.acwr:.2f}."
    if s.last_session:
        load += f" Last session was {s.last_session}."
    life = f"On the rest of the day: {s.life_clause}." if s.life_clause else "On the rest of the day: training has to fit the life you already have."
    why = "; ".join(decision.reasons)
    land = f"So here is where I land: {decision.action}, because {why}. I am grounding this in readiness {s.readiness:.0f}"
    if s.sleep_hours is not None:
        land += f", {_hours(s.sleep_hours)} last night"
    land += f", load ratio {s.acwr:.2f}."
    close = "If you want the session mapped, say so. If you just needed the read, you have it."
    return "\n\n".join(["Here is how I am reading you, in full — not a slogan, the actual picture.", sleep_line, rec, load, life, land, close])


def reason(context, message: str, seed: int = 42):
    signals = extract_signals(context, message)
    decision = decide(signals)
    _ = seed
    return decision, compose_reply(decision, signals)
