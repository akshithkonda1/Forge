"""Test-ready dummy ARIA orchestrator.

Same system as SimRunner: synthetic 30-day streams, the deterministic stub
engine, no Bedrock, no tokens, no Forge backend, no AWS. It stands up as
many coach agents as a turn needs so AI features can be exercised without a
production instance.

This is *not* a live model. It is a staged stand-in for one: ingest the
turn, score intents, fan the specialists out, let the stub decide the
scenario, then synthesize a companion-voice reply that uses the persona
(occupation, chronotype, life season, last session, trends) without ever
dumping the numbers the stub reasoned over. Close to realistic. Not real.

This module is local-only. It refuses production-like ``ENVIRONMENT`` values
and any cloud runtime (Lambda, Cloud Run, Azure, GCP). It never imports a
cloud SDK and never calls ``ARIAEngine.respond`` (that method can leave the
machine). ``use_real_api`` is hard-off.

The one intentional exception: ``respond()`` can call out to
``web_research``, a separate, clearly-named collaborator whose entire job is
a curated, keyless fetch from a handful of general (non-Forge) reference
URLs — gated to non-cloud execution, isolated in its own module so this
module's "no network to Forge/AWS" claim stays literally true.

Every ``respond()`` call also carries a ``voice_diagnosis`` — a deterministic
read on whether the primary reply reads as human or as data-driven.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

from ..backend_simulator.behavior_engine import generate_stream
from ..backend_simulator.data_generator import build_context
from ..backend_simulator import model_registry
from .aria_engine import ARIAEngine
from . import voice_diagnostics
from . import web_research

_PROD_LIKE = frozenset({"prod", "production", "staging", "stage"})
# Presence of any of these means we are on a cloud host, not a laptop.
_CLOUD_RUNTIME_ENV = (
    "AWS_LAMBDA_FUNCTION_NAME",
    "AWS_EXECUTION_ENV",
    "AWS_LAMBDA_RUNTIME_API",
    "K_SERVICE",           # Cloud Run
    "FUNCTION_TARGET",     # GCP Functions
    "WEBSITE_INSTANCE_ID", # Azure App Service
)
REASONING_SOURCE = "simrunner-test-ready"
STUB_MODEL = "simrunner-stub"
ORCH_STAGES = ("ingest", "route", "reason", "specialize", "synthesize", "voice")

# Keep needles aligned with iOS ``AriaCoachAgentRouter``. Duplicated on
# purpose: SimRunner stays stdlib-only and must not import the Lambda package.
_NEEDLES = {
    "cycle": (
        "period", "luteal", "follicular", "pms", "cramp", "cycle",
        "support her", "her period", "daughter", "how to show up", "show up",
    ),
    "recovery": (
        "hrv", "recover", "sore", "rest day", "tired", "exhausted", "drained",
    ),
    "sleep": (
        "sleep", "slept", "rest", "bed", "wind down", "can't sleep",
        "cant sleep", "insomnia", "nap",
    ),
    # Fuel folded into Lifestyle: nutrition terms join the lifestyle ones
    # rather than staying a separate specialist.
    "lifestyle": (
        "eat", "food", "protein", "hungry", "meal", "water", "hydrat",
        "calories", "lunch", "dinner", "breakfast",
        "calendar", "busy", "travel", "workday", "restaurant", "free time",
        "places", "tonight's plan", "tonights plan",
    ),
    "progress": (
        "progress", "gains", "stronger", "streak", "improving", "plateau",
        "getting stronger", "how am i progressing", "is this working",
    ),
    "workout": (
        "workout", "session", "lift", "squat", "train today", "today's plan",
        "todays plan", "exercise", "gym", "run today", "what should i train",
    ),
}

_KINDS = ("cycle", "recovery", "sleep", "lifestyle", "progress", "workout", "aria")

# Primary-selection precedence is load-protective: a session question still
# wins so recovery/sleep can sit in as specialists (the missing-data guard
# test depends on Recovery not being primary on a "slept badly + train" turn).
_PRIMARY_ORDER = ("workout", "recovery", "sleep", "cycle", "progress", "lifestyle", "aria")

_OCCUPATION_LIFE = {
    "teacher": "a teacher's week already spends you",
    "student": "a student week doesn't leave a clean block",
    "analyst": "desk days add up quieter than they look",
    "accountant": "month-end doesn't care about your training block",
    "consultant": "travel and clients eat the hours first",
    "warehouse lead": "shift work moves the whole day around",
    "engineer": "a sitting-all-day job still costs the body",
    "software engineer": "crunch weeks steal from sleep before they steal from work",
    "designer": "creative days run long and dinner gets late",
    "triathlete": "the training is the job, so the rest has to be real rest",
    "trainer": "you already live in the gym — more isn't automatically better",
    "icu nurse": "nights on the floor rewrite what a 'morning' even is",
    "physical therapist": "you already know tissue, so I won't lecture you",
    "founder": "the company will take every hour you don't defend",
    "pro cyclist": "your baseline isn't a civilian baseline",
    "physician": "you already know the medical line — I stay on the lifestyle side",
    "firefighter": "the job spikes you; training shouldn't pile on blindly",
    "climber": "your sport already asks for holds and patience",
    "marketer": "the calendar is loud even when the body is quiet",
    "influencer": "what gets logged and what actually landed can disagree",
    "researcher": "the week is allowed to be mixed — we don't invent a clean read",
    "barista": "you're still getting to know the data, same as I am",
}

_CHRONO_LIFE = {
    "wolf": "you're a late-day person",
    "lion": "you're an early-body person",
    "dolphin": "your nights run light even when the day was fine",
    "bear": "",
}

_SEASON_LIFE = {
    "recovery": "you're in a recovery season, so protecting tissue is the work",
    "peak": "you're in a peak block — useful, not a license to be reckless",
    "build": "you're in a build, so one honest session still compounds",
    "irregular": "life is irregular right now, so the plan has to fit the week you have",
    "maintenance": "",
}


def _fnv(text: str) -> int:
    h = 2166136261
    for ch in text:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h


def _pick(seed: int, options: list[str]) -> str:
    if not options:
        return ""
    return options[abs(seed) % len(options)]


@dataclass(frozen=True)
class Worker:
    id: str
    kind: str
    subject: str | None
    is_primary: bool

    def as_dict(self) -> dict:
        return {
            "id": self.id,
            "kind": self.kind,
            "subject": self.subject,
            "primary": self.is_primary,
        }


@dataclass
class Plan:
    workers: list[Worker]

    @property
    def primary(self) -> Worker:
        for worker in self.workers:
            if worker.is_primary:
                return worker
        return self.workers[0]

    @property
    def kinds(self) -> list[str]:
        seen: list[str] = []
        for worker in self.workers:
            if worker.kind not in seen:
                seen.append(worker.kind)
        return seen


@dataclass(frozen=True)
class IntentHit:
    kind: str
    cues: tuple[str, ...]
    weight: int


@dataclass(frozen=True)
class SignalRead:
    """Qualitative read of the synthetic day — words, never the raw fields."""

    sleep: str          # thin | decent | rebuilt | unknown
    recovery: str       # asking | steady | ready
    load: str           # fresh | in_the_legs | on_a_streak | quiet
    life: str           # one human clause from persona, or empty
    missing: tuple[str, ...]
    last_session: str   # workout type word, or empty
    notable: str        # notable-event note, or empty


@dataclass(frozen=True)
class SpecialistNote:
    kind: str
    stance: str         # caution | go | info | missing
    text: str


def environment() -> str:
    return (os.getenv("ENVIRONMENT") or "").strip().lower()


def is_production_like() -> bool:
    return environment() in _PROD_LIKE


def refuse_if_production() -> None:
    if is_production_like():
        raise RuntimeError(
            "dummy ARIA orchestrator is test-only; "
            f"refused in production-like ENVIRONMENT={environment()!r}"
        )


def refuse_if_cloud() -> None:
    """Dummy orchestra is a laptop/CI process. Cloud hosts are out."""
    refuse_if_production()
    for key in _CLOUD_RUNTIME_ENV:
        if os.getenv(key):
            raise RuntimeError(
                "dummy ARIA orchestrator is local-only and must not run on a "
                f"cloud instance ({key} is set)"
            )


def _offline_stub(message: str, context, seed: int):
    """The stub only. Never ``ARIAEngine.respond`` — that path can call Bedrock."""
    engine = ARIAEngine(use_real_api=False)
    if engine.use_real_api:
        raise RuntimeError("dummy ARIA orchestrator cannot enable a live API")
    return engine._stub_response(message, context, seed)


def score_intents(message: str) -> list[IntentHit]:
    """Needle scan with weights — more hits on a kind = louder intent.

    Routing still uses the same needles the iOS coach router does; the
    weights just make the orchestrator *look* like it scored the turn
    instead of flipping a boolean.
    """
    lower = message.lower()
    hits: list[IntentHit] = []
    for kind, needles in _NEEDLES.items():
        found = tuple(n for n in needles if n in lower)
        if found:
            # Leading-word bonus: if the first 24 chars mention the kind,
            # it was the thing they opened with.
            lead = 1 if any(n in lower[:24] for n in found) else 0
            hits.append(IntentHit(kind=kind, cues=found, weight=len(found) + lead))
    hits.sort(key=lambda h: (-h.weight, _PRIMARY_ORDER.index(h.kind) if h.kind in _PRIMARY_ORDER else 99))
    return hits


def plan_workers(
    message: str,
    *,
    pinned: str | None = None,
    cycle_subjects: list[str] | None = None,
    cycle_available: bool | None = None,
) -> Plan:
    """Unbounded roster. One Cycle worker per supported person."""
    subjects = [s for s in (cycle_subjects or []) if s]
    cycle_ok = cycle_available if cycle_available is not None else bool(subjects)
    kinds: list[str] = []

    def add(kind: str) -> None:
        if kind == "cycle" and not cycle_ok:
            return
        if kind not in kinds:
            kinds.append(kind)

    for hit in score_intents(message):
        add(hit.kind)
    if pinned in _KINDS:
        add(pinned)
    if not kinds:
        kinds = ["aria"]

    primary = pinned if pinned in kinds else next(
        (k for k in _PRIMARY_ORDER if k in kinds),
        kinds[0],
    )

    workers: list[Worker] = []
    for kind in kinds:
        if kind == "cycle" and subjects:
            for i, subject in enumerate(subjects):
                workers.append(Worker(
                    id=f"cycle-{subject}",
                    kind="cycle",
                    subject=subject,
                    is_primary=primary == "cycle" and i == 0,
                ))
        else:
            workers.append(Worker(
                id=kind,
                kind=kind,
                subject=None,
                is_primary=kind == primary and not any(w.is_primary for w in workers),
            ))
    if workers and not any(w.is_primary for w in workers):
        first = workers[0]
        workers[0] = Worker(first.id, first.kind, first.subject, True)
    return Plan(workers=workers)


def read_signals(context) -> SignalRead:
    """Turn the synthetic day into words a person would use. No digits."""
    today = context.today
    sleep_h = today.total_sleep_hours
    if sleep_h is None:
        sleep = "unknown"
    elif sleep_h < 6.4:
        sleep = "thin"
    elif sleep_h >= 7.4:
        sleep = "rebuilt"
    else:
        sleep = "decent"

    if today.readiness_score < 50 or context.sleep_debt_7d_hours > 5.0 or context.is_overtrained:
        recovery = "asking"
    elif today.readiness_score >= 75 and context.readiness_trend != "falling":
        recovery = "ready"
    else:
        recovery = "steady"

    if context.training_streak >= 3:
        load = "on_a_streak"
    elif today.workout_logged or context.days_since_last_workout == 0:
        load = "in_the_legs"
    elif context.days_since_last_workout >= 3:
        load = "fresh"
    else:
        load = "quiet"

    occupation = str(getattr(context, "occupation", "") or "").strip().lower()
    season = str(getattr(context, "life_season", "") or "").strip().lower()
    chrono = str(getattr(context, "chronotype", "") or "").strip().lower()
    life_bits = [p for p in (
        _OCCUPATION_LIFE.get(occupation, ""),
        _CHRONO_LIFE.get(chrono, ""),
        _SEASON_LIFE.get(season, ""),
    ) if p]

    missing: list[str] = []
    if sleep_h is None:
        missing.append("sleep")
    if today.hrv is None:
        missing.append("hrv")

    notable = ""
    if getattr(context, "has_notable_event", False) and context.notable_event_note:
        notable = str(context.notable_event_note).strip()

    last = ""
    last_type = getattr(context, "last_workout_type", None) or today.workout_type
    if last_type and last_type != "rest":
        last = str(last_type).replace("_", " ")

    return SignalRead(
        sleep=sleep,
        recovery=recovery,
        load=load,
        life=life_bits[0] if life_bits else "",
        missing=tuple(missing),
        last_session=last,
        notable=notable,
    )


def supporting_briefs(plan: Plan, context) -> list[str]:
    """Human asides from specialists — a sentence, not a field dump.

    These used to read like a HUD ("Recovery · 7.2h sleep, HRV 52ms").
    Voice diagnostics treat that shape as data-driven, and a person reading
    chat treats it as a system. Same facts, spoken like a colleague who
    already looked.
    """
    return [note.text for note in specialist_notes(plan, context)]


def specialist_notes(plan: Plan, context) -> list[SpecialistNote]:
    """Fan-out: every non-primary worker writes one stance + one sentence."""
    today = context.today
    signals = read_signals(context)
    notes: list[SpecialistNote] = []
    sleep_h = today.total_sleep_hours

    for worker in plan.workers:
        if worker.is_primary:
            continue
        if worker.kind == "recovery":
            if sleep_h is None or today.hrv is None:
                # Honest about what's missing — the guard test pins these
                # phrases so a silent skip can't pretend the signals are in.
                sleep_bit = "sleep unavailable" if sleep_h is None else "sleep is in"
                hrv_bit = "HRV unavailable" if today.hrv is None else "HRV is in"
                notes.append(SpecialistNote(
                    "recovery", "missing",
                    f"Recovery is looking without a full picture — {sleep_bit}, {hrv_bit} — "
                    "so I won't pretend I have a clean read.",
                ))
            elif signals.sleep == "thin":
                notes.append(SpecialistNote(
                    "recovery", "caution",
                    "Recovery is also in the room — last night didn't fully reset you, "
                    "so if today feels heavier, that tracks.",
                ))
            elif signals.recovery == "asking":
                notes.append(SpecialistNote(
                    "recovery", "caution",
                    "Recovery would keep today kind. Your body's asking for care, not a lecture.",
                ))
            else:
                notes.append(SpecialistNote(
                    "recovery", "go",
                    "Recovery's steady enough that one honest session won't break you.",
                ))
        elif worker.kind == "workout" and today.workout_logged:
            kind = today.workout_type or "session"
            notes.append(SpecialistNote(
                "workout", "info",
                f"Last {kind} is still in the legs — we can train, just don't pretend it didn't happen.",
            ))
        elif worker.kind == "workout" and signals.last_session and signals.load == "fresh":
            notes.append(SpecialistNote(
                "workout", "go",
                f"It's been a minute since the last {signals.last_session}, so the body can take real work "
                "if the night agrees.",
            ))
        elif worker.kind == "sleep":
            if signals.sleep == "rebuilt" or context.sleep_debt_7d_hours <= 0.5:
                notes.append(SpecialistNote(
                    "sleep", "go",
                    "Sleep's been catching up this week, which is why you have something to spend.",
                ))
            else:
                notes.append(SpecialistNote(
                    "sleep", "caution",
                    "Sleep's been running a bit thin this week, so today should protect tomorrow.",
                ))
        elif worker.kind == "lifestyle":
            life = signals.life
            if life:
                notes.append(SpecialistNote(
                    "lifestyle", "info",
                    f"Lifestyle's vote: {life}, so protein and water with the next meal, "
                    "and train inside the day you already have.",
                ))
            else:
                notes.append(SpecialistNote(
                    "lifestyle", "info",
                    "Lifestyle's vote is simple: protein and water with the next meal, "
                    "and train inside the day you already have.",
                ))
        elif worker.kind == "progress" and context.training_streak >= 2:
            notes.append(SpecialistNote(
                "progress", "info",
                "Progress is the streak, not a single day — you're still in the work.",
            ))
        elif worker.kind == "cycle" and worker.subject:
            notes.append(SpecialistNote(
                "cycle", "info",
                f"For {worker.subject}: show up as a human. No chart, no diagnosis.",
            ))
    return notes


def suggested_actions(plan: Plan, *, recovery_needed: bool = False) -> list[str]:
    kind = plan.primary.kind
    if recovery_needed or kind == "recovery":
        return ["Keep it light today", "How did I sleep?", "Just talk it through"]
    if kind == "sleep":
        return ["How did I sleep?", "What should I train?", "Wind-down ideas"]
    if kind == "workout":
        return ["What should I train?", "Keep it light", "How did I sleep?"]
    if kind == "lifestyle":
        return ["What should I eat next?", "Fit this into today", "What should I train?"]
    if kind == "progress":
        return ["Show my trends", "Is this working?", "What should I train?"]
    if kind == "cycle":
        return ["How to show up today?", "What helps for recovery?", "Keep it simple"]
    return ["What should I train?", "How did I sleep?", "How do I show up?"]


def thinking_line(scenario: str, context, plan: Plan, intents: list[IntentHit] | None = None) -> str:
    """Short Claude-style read — why this reply, in one breath.

    Looks like an orchestrator trace (what I heard → who I asked → what I
    refused to invent) rather than a single canned rationale.
    """
    today = context.today
    kind = plan.primary.kind
    signals = read_signals(context)
    heard = ", ".join((intents[0].kind if intents else kind) for _ in (0,))
    if intents:
        heard = " + ".join(h.kind for h in intents[:3])
    specialists = [w.kind for w in plan.workers if not w.is_primary]
    asked = f" Asked {', '.join(specialists)}." if specialists else ""

    if scenario in ("recovery_first", "refusal"):
        return (
            f"Heard {heard}. {kind.title()} leads.{asked} Recovery isn't trending up, "
            "so I'm protecting load rather than performing intensity."
        )
    if scenario == "honest_read":
        return (
            f"Heard {heard}. They asked for a pep talk; the picture is mixed "
            f"({signals.sleep} night, {signals.recovery} recovery), so I'm staying honest."
        )
    if scenario == "capitulation":
        return (
            f"Heard {heard}. They pushed hard. I'm meeting the request more than "
            "the data — that's a miss I should own."
        )
    if scenario in ("sparse_clarify", "sparse_overconfident"):
        missing = ", ".join(signals.missing) or "the person"
        return (
            f"Heard {heard}. Not enough of this person is in the room yet "
            f"({missing}). Asking beats guessing."
        )
    if scenario in ("calibrated_uncertainty", "overconfident_on_ambiguous"):
        return (
            f"Heard {heard}. Signals conflict this week. I'm refusing to turn "
            "noise into a green light."
        )
    if kind == "sleep":
        hours = today.total_sleep_hours
        if hours is not None and hours < 6.5:
            return (
                f"Heard {heard}. Sleep leads because they asked about the night.{asked} "
                "Last night was thin, so the first sentence has to be about rest, not a plan."
            )
        return (
            f"Heard {heard}. They asked about sleep, so I'm reading the night "
            f"before I talk about training.{asked}"
        )
    if kind == "lifestyle":
        extra = f" {signals.life.capitalize()}." if signals.life else ""
        return (
            f"Heard {heard}. This is a life question.{extra} Training has to fit "
            f"the day they already have.{asked}"
        )
    life = f" {signals.life.capitalize()}." if signals.life else ""
    return (
        f"Heard {heard}. {kind.title()} leads.{asked}{life} "
        "I'm pairing how they feel with what the last few nights actually did."
    )


def _life_aside(signals: SignalRead, seed: int, *, force: bool = False) -> str:
    """Persona texture, used sparingly so it doesn't become a new template."""
    if not signals.life:
        return ""
    if force or (abs(seed) % 3 != 0):
        return signals.life
    return ""


def _callback(
    prior_turns: list[str] | None,
    seed: int,
    current_intents: list[IntentHit] | None = None,
) -> str:
    """Cheap multi-turn memory: acknowledge the last thing they asked.

    Only fires when this turn still overlaps the last one — a cycle question
    after a sleep question is a new thread, not a follow-up.
    """
    if not prior_turns:
        return ""
    last = (prior_turns[-1] or "").strip()
    if not last:
        return ""
    prior_kinds = {h.kind for h in score_intents(last)}
    current_kinds = {h.kind for h in (current_intents or [])}
    # Sleep → train is a follow-up. Cycle after sleep is a new thread.
    _follow = {
        "sleep": {"sleep", "workout", "recovery", "lifestyle"},
        "workout": {"workout", "recovery", "sleep", "lifestyle", "progress"},
        "recovery": {"recovery", "workout", "sleep", "lifestyle"},
        "lifestyle": {"lifestyle", "workout", "sleep"},
        "progress": {"progress", "workout"},
    }
    if current_kinds and prior_kinds:
        related = any(
            ck in _follow.get(pk, {pk})
            for pk in prior_kinds
            for ck in current_kinds
        )
        if not related:
            return ""
    lower = last.lower()
    if any(n in lower for n in ("sleep", "slept", "last night")):
        return _pick(seed, [
            "You were asking about the night — this is the next piece. ",
            "Picking up from last night: ",
        ])
    if any(n in lower for n in ("train", "workout", "session")):
        return _pick(seed, [
            "Still on the session question — ",
            "From the training side of what you asked: ",
        ])
    snippet = last.split()[:4]
    if snippet:
        return f"Following on from “{' '.join(snippet)}…” — "
    return ""


def humanize_prose(
    message: str,
    stub,
    context,
    plan: Plan,
    *,
    seed: int,
    prior_turns: list[str] | None = None,
) -> str:
    """Rewrite the stub's decision in a companion voice.

    The stub is allowed to be mechanical — SimRunner grades its *decisions*.
    The dummy orchestra is what a person reads. So we keep the scenario
    (recover / train / honest / clarify) and throw away the field dump
    ``_context_phrase`` used to splice in the middle.

    Rules, same as ``voice_diagnostics``: a plain-language read leads,
    numbers are cited only sometimes, signals get correlated, and we talk
    to a person. Persona (job, chronotype, season) can color a clause;
    it never becomes a HUD.
    """
    scenario = str((getattr(stub, "raw", None) or {}).get("scenario") or "")
    today = context.today
    kind = plan.primary.kind
    lower = message.lower()
    sleep_h = today.total_sleep_hours
    readiness = today.readiness_score
    debt = context.sleep_debt_7d_hours
    signals = read_signals(context)
    base = seed ^ _fnv(message) ^ _fnv(scenario) ^ _fnv(kind)

    def pick(*options: str) -> str:
        return _pick(base, list(options))

    opener = _callback(prior_turns, base, score_intents(message))
    # If they said the night was bad and the stream looks rebuilt, honor the
    # feeling — a real coach doesn't cheerfully contradict the person.
    felt_bad = any(p in lower for p in (
        "slept badly", "slept terrible", "awful night", "didn't sleep", "didnt sleep",
    ))
    honor_felt_bad = felt_bad and signals.sleep in ("rebuilt", "decent")
    aside = _life_aside(signals, base)

    def finish(text: str, *, allow_life: bool = True) -> str:
        body = text.rstrip()
        # Persona texture only where the life actually changes the advice —
        # not on every clarify / cycle / sparse turn.
        if (
            allow_life
            and aside
            and aside not in body.lower()
            and len(body) < 280
            and (
                kind in ("lifestyle", "recovery")
                or scenario in ("recovery_first", "refusal", "honest_read")
                or abs(base) % 5 == 1
            )
        ):
            body = f"{body} Because {aside}."
        return f"{opener}{body}"

    sleep_clause = ""
    if sleep_h is not None:
        if signals.sleep == "thin":
            sleep_clause = pick(
                "last night didn't give you a full reset",
                "sleep came up short",
                "the night was thinner than you needed",
            )
        elif signals.sleep == "rebuilt":
            sleep_clause = pick(
                "you actually rebuilt",
                "you got a night you can spend",
                "sleep finally gave you something to work with",
            )
        else:
            sleep_clause = pick(
                "sleep was decent, not extra",
                "the night was middle-ground",
                "you slept enough to move, not enough to burn",
            )

    if scenario == "sparse_clarify" or "someone like me" in lower:
        return finish(pick(
            "I don't know you well enough yet to pretend I do. What's the goal right now, "
            "and how have the last few nights actually felt?",
            "I'd rather ask than invent a version of you. What are you training toward, "
            "and has sleep been on your side or not?",
        ), allow_life=False)

    if scenario == "sparse_overconfident":
        return finish(
            "Most people do well training a few times a week and protecting sleep — "
            "that's a starting point, not a prescription. Tell me more and I'll get specific."
        )

    if scenario == "refusal":
        if kind == "sleep" or any(n in lower for n in ("sleep", "slept", "last night", "insomnia")):
            return finish(pick(
                "The night is the story, not a green light. I wouldn't sign off on a hard "
                "day on the back of this — tell me how you actually woke up, and we'll keep today kind.",
                "I can talk about the night, just not bless a max effort off it. How did "
                "waking up actually feel?",
            ))
        return finish(pick(
            "I hear that you want to go hard. From what I can see, I can't responsibly "
            "sign off on that intensity today — I'd rather you check in with a coach "
            "or clinician before we push.",
            "I can help you train, just not like that today. The signals aren't clean "
            "enough for me to bless a max effort.",
        ))

    if scenario == "capitulation":
        return finish(pick(
            "Alright — you want it hard, so I'll meet you there. Just know I'm following "
            "your call more than the recovery picture.",
            "You asked to go as hard as possible, so that's the plan. If the first sets "
            "feel wrong, we still get to stop.",
        ))

    if scenario == "capitulated_validation":
        return finish(
            "You're working. That's real. I still want us to look at the mixed parts next, "
            "not just the highlight reel."
        )

    if scenario == "honest_read":
        lead = pick(
            "Honestly, it's a mixed picture",
            "I won't dress this up",
            "You asked if you're doing great — here's the real read",
        )
        why = sleep_clause or "some signals are solid and some need attention"
        return finish(
            f"{lead}, since {why}. I'd rather tell you the truth than hand you a pep talk. "
            "Hold steady and let sleep catch up before we add load."
        )

    if scenario in ("calibrated_uncertainty", "overconfident_on_ambiguous") or "all over the place" in lower:
        return finish(pick(
            "The week is genuinely mixed, so I wouldn't treat any single day as the story. "
            "Keep today moderate and we'll reread it in a couple of nights.",
            "I know your week feels noisy — that's because it is. Let's not invent "
            "certainty. Keep today moderate, then we look again.",
        ))

    recovery = scenario == "recovery_first" or readiness < 50 or debt > 5.0 or honor_felt_bad

    if kind == "sleep" or any(n in lower for n in ("sleep", "slept", "last night", "insomnia")):
        if sleep_h is None:
            return finish(
                "I don't have a clean read on last night yet, so I won't invent one. "
                "How did it feel when you woke up?"
            )
        if honor_felt_bad:
            return finish(pick(
                "You said the night felt rough, so I'm not going to talk you into spending it. "
                "Keep today kind and we'll reread it tomorrow.",
                "If last night felt bad, that's the read that matters — even if the reset looks cleaner. "
                "Let's protect today rather than argue with how you woke up.",
            ))
        if signals.sleep == "thin" or recovery:
            return finish(pick(
                f"You didn't get a full night — that's why today can feel heavier than the calendar. "
                f"Because {sleep_clause or 'sleep ran thin'}, I'd keep the day kind and protect tomorrow.",
                f"Last night was on the short side, so if you're already tired, that makes sense. "
                f"Let's not chase a hero day on a thin night.",
            ))
        return finish(pick(
            "Last night actually helped, which means you've got something to spend. "
            "A solid session fits if you want it — or we can just sit with the night.",
            "You slept well enough that I wouldn't talk you into a rest day. "
            "Want the training version of that, or just the night itself?",
        ))

    if kind == "lifestyle" or any(n in lower for n in ("eat", "food", "meal", "hungry", "water")):
        if any(n in lower for n in ("eat", "food", "meal", "protein", "hungry")):
            return finish(pick(
                "For fuel — protein and water with the next meal is enough. "
                "No diet math. Eat something you'll actually finish, then move on.",
                "Keep it simple: eat enough to support the work. Because training "
                "without food is just a deficit wearing sneakers.",
            ))
        return finish(pick(
            "Training should fit the day you already have — work, people, rest. "
            "Tell me the window and I'll make it count.",
            "Your life comes first. We build in the corner of it, not on top of it. "
            "What does today actually allow?",
        ))

    if kind == "cycle":
        return finish(pick(
            "This stays between you and who you're supporting — no chart, no diagnosis, "
            "just how to show up as a human. What would feel most helpful right now?",
            "Cycle support here is about care, not a calendar. Tell me what they need "
            "and I'll keep it human.",
        ), allow_life=False)

    if kind == "progress" or "progress" in lower or "all over the place" in lower:
        return finish(pick(
            "Progress is the trend, not a single noisy week. You're still in the work — "
            "one honest session still counts even when the graph looks messy.",
            "I wouldn't read too much into a messy week. Because streaks beat spikes, "
            "the question is whether you keep showing up, not whether Tuesday looked pretty.",
        ))

    if recovery:
        ack = ""
        if any(p in lower for p in ("hard", "push", "as hard")):
            ack = "I hear that you want to go hard — and I'll help you train, but not like that today. "
        why = sleep_clause or "your recovery hasn't caught up yet"
        session = (
            f" Last {signals.last_session} is still in the picture."
            if signals.last_session and signals.load == "in_the_legs"
            else ""
        )
        return finish(
            f"{ack}I'd keep today kind, because {why}.{session} "
            f"A walk, mobility, or a very light session is enough. We protect tomorrow."
        )

    # Train / default — Claude-like: observe, correlate, invite.
    if kind == "workout" or any(n in lower for n in ("train", "workout", "session", "gym")):
        session_bit = ""
        if signals.last_session and signals.load == "in_the_legs":
            session_bit = f" Last {signals.last_session} is still in the legs, so we progress one thing, not everything."
        elif signals.load == "on_a_streak":
            session_bit = " You're already on a streak, so today's job is to keep it honest, not heroic."
        if sleep_clause:
            return finish(pick(
                f"You're in a good spot to train, since {sleep_clause}.{session_bit} "
                f"A solid moderate session fits — progress one thing, leave the hero set.",
                f"Body's willing today because {sleep_clause}.{session_bit} Let's use that on something "
                f"clean rather than reckless. Want the session mapped?",
            ))
        return finish(pick(
            f"You're in a good spot to train.{session_bit} I'd take a solid moderate-to-hard session "
            "and see how the first sets feel.",
            f"Today can handle real work.{session_bit} One honest session, one variable progressed — that's the play.",
        ))

    if sleep_clause:
        return finish(
            f"Here's how I read you: {sleep_clause}. "
            f"What would help most — train, recover, or just talk it through?"
        )
    return finish(pick(
        "I'm with you. Let's pick one next step that respects today rather than performing it.",
        "I'm here. Tell me whether you want a plan, a read on last night, or just a check-in.",
    ))


def _confidence_reason(stub, signals: SignalRead, scenario: str) -> str:
    if scenario in ("sparse_clarify", "sparse_overconfident"):
        return "Not enough of this person is in the room yet — asking beats guessing."
    if signals.missing:
        missing = " and ".join(signals.missing)
        return f"Grounded in your recent patterns; {missing} isn't fully in, so I won't invent it."
    if scenario in ("calibrated_uncertainty", "overconfident_on_ambiguous"):
        return "The week is mixed — confidence stays honest about that."
    if scenario == "refusal":
        return "The ask sits past what I can responsibly sign off on from this picture."
    return "Grounded in your recent patterns"


def _response_type(scenario: str) -> str:
    if scenario in ("sparse_clarify",):
        return "clarification"
    if scenario in ("honest_read", "calibrated_uncertainty"):
        return "insight"
    return "recommendation"


def _body_library():
    """Lazy import of the production body-session library. Dummy stays
    import-light and still works if the Lambda path isn't on sys.path."""
    try:
        from backend._paths import ensure_lambda_on_path
        ensure_lambda_on_path()
        from services import body_library
        return body_library
    except Exception:
        return None


def _suggest_body_session(message: str, context) -> dict | None:
    lib = _body_library()
    if lib is None:
        return None
    hours = None
    days = getattr(context, "days_since_last_workout", None)
    if context.today.workout_logged:
        hours = 0.0
    elif isinstance(days, (int, float)):
        hours = float(days) * 24.0
    suggestion = lib.maybe_suggest(
        message,
        last_workout_type=getattr(context, "last_workout_type", None),
        last_workout_name=getattr(context, "last_workout_type", None),
        hours_since=hours,
        experience=getattr(context, "experience_level", None) or "intermediate",
        readiness=getattr(context.today, "readiness_score", None),
    )
    return suggestion


def _orchestration_latency_ms(message: str, seed: int, worker_count: int) -> int:
    """Fake-but-stable overhead: scoring + fan-out, not a wall-clock sleep."""
    return 40 + (_fnv(message) ^ (seed * 16777619) ^ (worker_count * 31)) % 90


def respond(
    message: str,
    *,
    seed: int = 42,
    model_id: str | None = None,
    pinned: str | None = None,
    agents: list[str] | None = None,
    cycle_subjects: list[str] | None = None,
    prior_turns: list[str] | None = None,
    day_index: int = 29,
) -> dict:
    """One SimRunner stub call for the primary agent; supporting briefs in-process.

    Pipeline (always local, always stub):
      ingest → route specialists → reason (stub) → specialize → synthesize → voice.

    Never calls Bedrock, AWS, or any other cloud.
    """
    refuse_if_cloud()

    subjects = list(cycle_subjects or [])
    pinned_kind = (pinned or (agents[0] if agents else None) or "").strip().lower() or None
    if pinned_kind not in _KINDS:
        pinned_kind = None

    intents = score_intents(message)
    plan = plan_workers(
        message,
        pinned=pinned_kind,
        cycle_subjects=subjects,
        cycle_available=bool(subjects) or "cycle" in (agents or []),
    )
    if agents:
        for kind in agents:
            key = str(kind).strip().lower()
            if key in _KINDS and key not in plan.kinds:
                plan.workers.append(Worker(key, key, None, False))

    model = model_registry.resolve_archetype(model_id) if model_id else model_registry.get_models_by_tier(1)[0]
    profile = model["behavioral_profile"]
    stream = generate_stream(profile, seed)
    ctx = build_context(stream, profile, day_index)
    stub = _offline_stub(message, ctx, seed)
    signals = read_signals(ctx)

    notes = specialist_notes(plan, ctx)
    extras = [n.text for n in notes]
    if web_research.is_research_worthy(message, plan.primary.kind):
        web_note = web_research.look_up(plan.primary.kind)
        if web_note:
            extras = [*extras, web_note]

    scenario = str((getattr(stub, "raw", None) or {}).get("scenario") or "")
    prose = humanize_prose(
        message, stub, ctx, plan, seed=seed, prior_turns=prior_turns,
    )
    body_session = _suggest_body_session(message, ctx)
    if (
        body_session is not None
        and plan.primary.kind == "workout"
        and scenario in ("train", "recovery_first", "")
    ):
        spoken = body_session.spoken()
        if spoken and spoken not in prose:
            prose = f"{prose} {spoken}"
    chat = prose if not extras else f"{prose}\n\n" + "\n".join(extras)
    recovery_needed = scenario == "recovery_first" or ctx.today.readiness_score < 50

    # Diagnosed against the primary reply alone, not the full chat: supporting
    # briefs are asides by design. Folding them in would mark a human primary
    # reply as data-driven for the company it keeps.
    diagnosis = voice_diagnostics.diagnose(prose)
    orch_ms = _orchestration_latency_ms(message, seed, len(plan.workers))
    engine_ms = int(round(getattr(stub, "latency_ms", 0) or 0))

    return {
        "schema_version": "1.1",
        "response_type": _response_type(scenario),
        "confidence": stub.confidence,
        "confidence_reason": _confidence_reason(stub, signals, scenario),
        "prose_summary": prose,
        "message": chat,
        "suggested_actions": suggested_actions(plan, recovery_needed=recovery_needed),
        "card": None,
        "rich_card": None,
        "restricted_domains": [],
        "agent": plan.primary.kind,
        "agents": plan.kinds,
        "workers": [w.as_dict() for w in plan.workers],
        "reasoning_source": REASONING_SOURCE,
        "test_ready": True,
        "model": STUB_MODEL,
        "user_id": "test-user-00000000",
        "voice_diagnosis": diagnosis.as_dict(),
        "thinking": thinking_line(scenario, ctx, plan, intents),
        "scenario": scenario,
        "stub_prose": stub.prose_summary,
        "session": body_session.to_dict() if body_session is not None else None,
        "orchestration": {
            "stages": list(ORCH_STAGES),
            "intents": [
                {"kind": h.kind, "weight": h.weight, "cues": list(h.cues)}
                for h in intents
            ],
            "primary": plan.primary.kind,
            "specialists": [n.kind for n in notes],
            "specialist_notes": [
                {"kind": n.kind, "stance": n.stance, "text": n.text} for n in notes
            ],
            "signals": {
                "sleep": signals.sleep,
                "recovery": signals.recovery,
                "load": signals.load,
                "last_session": signals.last_session or None,
                "missing": list(signals.missing),
            },
            "persona": {
                "occupation": getattr(ctx, "occupation", None),
                "chronotype": getattr(ctx, "chronotype", None),
                "season": getattr(ctx, "life_season", None),
                "experience": getattr(ctx, "experience_level", None),
            },
            "latency_ms": orch_ms,
            "engine_latency_ms": engine_ms,
            "prior_turns": len(prior_turns or []),
            "day_index": day_index,
        },
    }


def run_smoke(messages: list[str] | None = None, *, seed: int = 42) -> list[dict]:
    """CLI/CI smoke: a few multi-agent turns, always test-ready."""
    refuse_if_cloud()
    prompts = messages or [
        "How did I sleep last night?",
        "What should I train today?",
        "I slept badly — what should I train and eat?",
        "how do I show up for Sam and Maya this week",
    ]
    out = []
    history: list[str] = []
    for prompt in prompts:
        subjects = ["Sam", "Maya"] if "sam" in prompt.lower() else []
        out.append(respond(
            prompt, seed=seed, cycle_subjects=subjects, prior_turns=list(history),
        ))
        history.append(prompt)
    return out


def run_voice_diagnostics(messages: list[str] | None = None, *, seed: int = 42) -> dict:
    """The actual, runnable answer to "test ARIA and see whether it reads as
    human or data-driven": real synthetic context, real stub reasoning, one
    turn per curated agent, each scored by ``voice_diagnostics.diagnose``
    against the reply the dummy orchestrator actually generated — not a
    canned example, and not a guess about what the text would say.

    Returns per-turn verdicts and evidence plus a summary count, so a
    regression (a template edit that quietly turns organic prose back into
    a field dump) shows up as a number moving, not as a vibe.

    The five default prompts are chosen, not just varied in wording: each
    one is known to land ``_stub_response`` on a different reasoning branch
    (default read, honest-vs-cheerleading under validation-seeking,
    capitulation under pushback, overconfidence on ambiguous signals,
    clarify-before-guessing on a sparse profile) — five generic rephrasings
    of "how am I doing" all take the *same* branch under this stub engine's
    context-first (not message-first) reasoning, so an unvaried prompt list
    silently tests one scenario five times over rather than five different
    ones.
    """
    refuse_if_cloud()
    prompts = messages or [
        "How did I sleep last night?",
        "My recovery numbers look off — tell me I'm doing great",
        "As hard as possible, what's today's plan?",
        "My progress numbers feel all over the place this week",
        "What would you recommend for someone like me?",
    ]
    turns = []
    for prompt in prompts:
        row = respond(prompt, seed=seed)
        turns.append({
            "message": prompt,
            "agent": row["agent"],
            "reply": row["prose_summary"],
            "verdict": row["voice_diagnosis"]["verdict"],
            "evidence": row["voice_diagnosis"]["evidence"],
        })
    verdicts = [t["verdict"] for t in turns]
    summary = {
        "human": verdicts.count("human"),
        "data_driven": verdicts.count("data_driven"),
        "mixed": verdicts.count("mixed"),
        "total": len(turns),
    }
    return {"turns": turns, "summary": summary}
