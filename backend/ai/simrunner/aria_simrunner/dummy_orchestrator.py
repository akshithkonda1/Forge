"""Test-ready dummy ARIA orchestrator.

This is a *testing* engine, not the live backend. It stands up synthetic
streams and a stub so ARIA features can be exercised on a laptop. The
long-term learner is ``services.contextual_learner`` on the Lambda hot path.
``respond()`` may *consume* that module in-process so dummy tests exercise
the same policy a real backend will; it must never own Q-tables, persona
storage, or teaching copy. With ``engine="lambda"`` it also consumes
``services.fusion.fuse_turn`` and ``aria_engine.generate_response`` (Bedrock
off) so hypertune reads fused product speak. Every turn also runs
``services.aria_swarm`` — a deterministic read/evaluate/write pass over
WHOOP, Apple Watch, and Oura / RRA — without calling a model. Provider
ID/region table awaits Quill (``services.provider_capabilities``). Deleting this
file must leave the learner, fusion, Swarm, and ``POST /ai/chat`` intact.

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
module's "no network to Forge/AWS" claim stays literally true. The lambda
engine is in-process only: fusion + deterministic ``generate_response``,
never ``generate_response_live`` and never a cloud SDK.

Every ``respond()`` call also carries a ``voice_diagnosis`` — a deterministic
read on whether the primary reply reads as human or as data-driven.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass

from ..backend_simulator import model_registry
from ..backend_simulator.behavior_engine import generate_stream
from ..backend_simulator.data_generator import build_context
from .aria_engine import ARIAEngine
from . import speak_quality
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
LAMBDA_REASONING_SOURCE = "lambda-fused"
LAMBDA_MODEL = "lambda-deterministic"
ENGINE_STUB = "stub"
ENGINE_LAMBDA = "lambda"
ORCH_STAGES = ("ingest", "route", "reason", "specialize", "synthesize", "voice")

# Wearable attribution for the dummy stream. The old ``simrunner`` tag made
# Swarm unable to tell WHOOP from Watch from Oura / RRA.
_SWARM_SAMPLE_SOURCE = {
    "sleep": "oura",
    "sleep-stage": "oura",
    "hrv": "whoop",
    "resting-heart-rate": "apple-watch",
    "steps": "apple-watch",
    "active-calories": "apple-watch",
}

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
    "aging": (
        "training age", "biological age", "fitness age", "calendar age",
        "vascular age", "inner age", "metabolic age", "phenotypic age",
        "vo2 max", "cardiorespiratory", "how old am i", "age comparison",
    ),
    "workout": (
        "workout", "session", "lift", "squat", "train today", "today's plan",
        "todays plan", "exercise", "gym", "run today", "what should i train",
    ),
}

# Lockstep with iOS AriaCoachAgent.rawValue / first_bond.IOS_AGENT_KINDS.
# Aging is a Dummy routing lane (not an iOS coach pin) but stays in the roster.
_KINDS = ("cycle", "recovery", "sleep", "lifestyle", "progress", "aging", "workout", "aria")

# Aging first so "training age" is never stolen by workout/lifestyle.
# Then load-protective: a session question still wins so recovery/sleep
# can sit in as specialists.
_PRIMARY_ORDER = ("aging", "workout", "recovery", "sleep", "cycle", "progress", "lifestyle", "aria")

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


def _production_learner():
    """Import the live learner for tests. Dummy must not own this module.

    Function-level on purpose: this file stays free of cloud SDKs, and the
    learner keeps working after this orchestrator is deleted.
    """
    try:
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import contextual_learner

        return contextual_learner
    except Exception:
        return None


def _production_swarm():
    """Import live Swarm. Dummy must not own the policy."""
    try:
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import aria_swarm

        return aria_swarm
    except Exception:
        return None


def _consume_learner(message: str, ctx, plan: Plan):
    """Run the production policy in memory. Never Dynamo, never Bedrock."""
    learn = _production_learner()
    if learn is None:
        return None, plan
    try:
        persona = learn.PersonaState()
        hist = getattr(ctx, "history", None) or []
        learn.pretrain_from_history(persona, hist[-14:] if hist else [])
        brief = learn.apply_chat_turn(persona, message=message, ctx=ctx)
        # Extra specialists on the roster only — do not add supporting briefs
        # (those would change ``message`` and fail the voice/prose contract).
        for spec in brief.specialists:
            key = str(spec).strip().lower()
            if key in _KINDS and key not in plan.kinds:
                plan.workers.append(Worker(key, key, None, False))
        return brief, plan
    except Exception:
        return None, plan


def _attach_swarm(row: dict, ctx, *, samples: list[dict] | None = None) -> dict:
    """Background Swarm pass — read/evaluate/write the wearable dataset.

    Sidecar only: never woven into spoken prose (voice/speak-quality gates).
    """
    swarm_mod = _production_swarm()
    if swarm_mod is None:
        return row
    try:
        picture = swarm_mod.run_swarm(
            context=ctx,
            samples=samples if samples is not None else _stream_samples(ctx),
        )
    except Exception:
        return row
    row["swarm"] = picture
    orch = dict(row.get("orchestration") or {})
    orch["swarm"] = True
    orch["swarm_sources"] = [s.get("id") for s in picture.get("sources") or [] if s.get("present")]
    orch["swarm_stance"] = (picture.get("picture") or {}).get("stance")
    orch["swarm_slot"] = picture.get("slot_name")
    row["orchestration"] = orch
    thinking = str(row.get("thinking") or "").rstrip()
    labels = [
        s.get("label") for s in picture.get("sources") or [] if s.get("present") and s.get("label")
    ]
    if labels:
        extra = f" Swarm read {', '.join(labels)}."
        if extra.strip() not in thinking:
            row["thinking"] = f"{thinking}{extra}".strip()
    return row


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
    if kind == "aging":
        return ["What's my training age?", "How did I sleep?", "What should I train?"]
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
    """Multi-turn memory that sounds like a person, not a thread picker.

    Only fires when this turn still overlaps the last one — a cycle question
    after a sleep question is a new thread, not a follow-up. Prefers short
    spoken bridges ("Yeah — after that night…") over meta narration
    ("Following on from your previous message").
    """
    if not prior_turns:
        return ""
    last = (prior_turns[-1] or "").strip()
    if not last:
        return ""
    # Reach one more turn back when the last message was a tiny follow-up.
    earlier = ""
    if len(prior_turns) >= 2 and len(last.split()) <= 4:
        earlier = (prior_turns[-2] or "").strip()
    prior_kinds = {h.kind for h in score_intents(last)}
    if earlier:
        prior_kinds |= {h.kind for h in score_intents(earlier)}
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
    earlier_lower = earlier.lower()
    sleepish = any(n in lower or n in earlier_lower for n in ("sleep", "slept", "last night", "insomnia"))
    trainish = any(n in lower or n in earlier_lower for n in ("train", "workout", "session", "gym"))
    if sleepish and trainish:
        return _pick(seed, [
            "Yeah — after that night, ",
            "Right, with the night still in play — ",
            "You were asking about the night — so for training, ",
            "Picking up from last night into the session: ",
            "Okay, night first then the work — ",
        ])
    if sleepish:
        return _pick(seed, [
            "Yeah — about that night, ",
            "You were asking about the night — ",
            "Picking up from last night: ",
            "Still thinking about the sleep piece — ",
            "Right, the night you mentioned — ",
            "After what you said about sleeping — ",
        ])
    if trainish:
        return _pick(seed, [
            "Still on the session — ",
            "Yeah, for the training side — ",
            "From the training side of what you asked: ",
            "On the workout question — ",
            "Okay, back to what you'd train — ",
        ])
    # Soft recall without announcing "I am continuing a thread."
    snippet = [w for w in last.replace("?", "").split() if w.lower() not in {"i", "a", "the", "to", "and"}][:3]
    if snippet:
        bit = " ".join(snippet)
        return _pick(seed, [
            f"Yeah — about “{bit}” — ",
            f"Still with you on “{bit}” — ",
            f"Okay, on “{bit}” — ",
        ])
    return _pick(seed, ["Yeah — ", "Okay — ", "Right — "])


def _follow_up_reply(
    message: str,
    prior_turns: list[str] | None,
    signals: SignalRead,
    seed: int,
) -> str:
    """Handle short discourse moves the way a real coach would mid-thread."""
    if not prior_turns:
        return ""
    text = (message or "").strip().lower()
    if len(text.split()) > 10:
        return ""
    easier = any(p in text for p in (
        "easier", "make it easy", "too hard", "lighter", "gentler", "dial it back",
    ))
    shorter = any(p in text for p in ("shorter", "quicker", "less time", "15 min", "ten min"))
    skip = any(p in text for p in ("skip it", "skip that", "never mind", "nvm", "forget it"))
    if not (easier or shorter or skip):
        return ""
    if skip:
        return _pick(seed, [
            "Got it — we drop that. Want a walk instead, or just leave today alone?",
            "Okay, scratched. Rest is a plan too — or I can swap in something tiny.",
            "Fair. We park it. Soft movement, or a clean rest day?",
        ])
    if shorter and easier:
        return _pick(seed, [
            "Alright — shorter and lighter. Ten to fifteen minutes, easy effort, done.",
            "We cut it down and soft: a brief mobility or Zone-2 stroll, then stop.",
            "Yep — compress it. Short, kind, no hero finish.",
        ])
    if shorter:
        return _pick(seed, [
            "Shorter works. Cap it at fifteen minutes and keep the quality high.",
            "We trim it — fewer sets, same intent, then you're out.",
            "Okay, time-box it. Short session, clean reps, no linger.",
        ])
    # easier
    thin = signals.sleep == "thin" or signals.recovery == "asking"
    if thin:
        return _pick(seed, [
            "Yeah — we ease it. Keep the work gentle and protect the night you already spent.",
            "Lighter it is. Easy movement only; the night still owns the day.",
            "Makes sense. Soft session, no ego sets — recovery is still in the room.",
        ])
    return _pick(seed, [
        "Sure — we dial it back. Same idea, less intensity, stop while it still feels good.",
        "Easier works. Drop the load, keep the pattern, leave something in the tank.",
        "Okay, soft mode. Honest movement without the push.",
    ])


# User-visible Dummy speak never dumps vitals/metrics. Orchestration notes may
# still name missing HRV for guard tests; those tokens must not reach prose.
_VITALS_SPEAK = re.compile(
    r"\b(hrv|bpm|ms|mmhg|vo2|spo2|recovery score|sleep[- ]?debt)\b"
    r"|%\s*(?:below|above|under|over)\s+baseline",
    re.I,
)
_SPEAK_FALLBACK = (
    "I'm with you. Let's pick one next step that respects today rather than performing it."
)
_CHEER_SLUDGE = re.compile(
    r"\b("
    r"crushing it|you're killing it|you got this|you've got this|"
    r"so proud of you|amazing work|great job|keep slaying|beast mode|"
    r"you're a machine|keep up the great|so inspiring"
    r")\b",
    re.I,
)
# Soft-wit (Iris): witty + insightful = one funny take + one useful improve.
# Throughline is friend — bubbly / kind / taking-care. Not dry trainer bark,
# not diagnose/treat/cure, not vitals dumps. Seed-indexed via ``_pick``.
_WIT_PROTECT = (
    "Your body's hung a cute 'back soon' sign — easy walk, then protect bedtime like it's the real session.",
    "I'm with you, and I'm tucking the hero set in a drawer — keep it gentle and get to bed on purpose.",
    "Cozy-sweater day, not montage day — ten easy minutes, water nearby, lights out a little earlier.",
    "Even sparkly people need a restock — skip the extra work and steal a kinder wind-down tonight.",
    "Today whispered please-be-nice — so we will: keep it kind, light movement, protein with the next meal, real sleep.",
    "Friend vote: let's not pick a fight with a tired body — soft loop, then earlier lights-out.",
    "I love the ambition and I'm still tucking it in — keep today kind and light and make bedtime the workout.",
    "Your tank's on the cute low-power glow — easy movement only, then we guard the night.",
    "I'm taking care of you, not casting you as the montage hero — short and kind, then wind down.",
    "The loud plan can wait in drafts — an easy walk, a simple meal, and an honest bedtime will do more.",
    "You're not failing, you're just a little crispy — keep it easy and get under the covers on time.",
    "Hug first: restock day — easy body, water with the next meal, protect sleep like a friend would.",
)
_WIT_PROCEED = (
    "You've got a little sparkle in the tank, and I'm with you — spend it on one clean session, then stop while it still feels good.",
    "I'm in, sweetly — keep it easy: sharp work, water nearby, encore left in the bag.",
    "Green-enough day, not fireworks — pick one thing to progress, keep it easy, then you're done, I promise.",
    "Yes to the session and yes to taking care of you in it — keep it focused, skip the encore finish.",
    "You've got enough to spend, just don't spend it like a double-dare — keep it easy: one honest block, then a real meal you actually finish.",
    "I'm cheering, not shoving — a focused session, protein and water after, then we call it easy.",
    "The day's saying go-play, not go-prove-it — train one thing well, keep it easy, and stop on quality.",
    "Usable spark, friend — keep it sharp and kind, and don't turn it into an all-day parade.",
    "I'm excited for you, friend, and I'm still the one who says stop — clean easy work, then you're free.",
    "There's room to move and we'll keep it gentle — one quality session, water in reach, no encore.",
    "Today can handle real work if we unwrap it kindly — progress one thing, leave extra sets.",
    "Friend mode is on, sparkle included — go train, keep it cute and kind, then eat something you'll actually finish.",
)
_WIT_HONEST = (
    "Mixed isn't a villain origin story — hold the load kind and steady and steal twenty extra minutes of wind-down.",
    "I can be kind and sweet and still tell you the weather's meh — same effort as yesterday, protein and water with the next meal.",
    "The plot got interesting, not doomed — keep one honest session size and protect bedtime.",
    "Hug with a point — stay kind and moderate, make the next meal simple, and get to bed on purpose.",
    "The day's a maybe, and that's allowed — easy-moderate work, then a softer night.",
    "I'm with you in the messy middle — don't add load, do add a kinder wind-down.",
    "Funny thing, friend: mixed days are where the care shows — hold steady and lights-out a little earlier.",
    "You don't need a speech, you need a kind friend with a snack plan — same-size session, earlier bedtime.",
    "Today's neither fireworks nor a flop — keep the work kind and honest and the bedtime real.",
    "I'll keep you company, friend, and keep you honest — no extra volume, yes to water and a gentler night.",
    "Hold-steady chapter, not a villain lecture — one familiar session, then protect sleep like it matters (it does).",
    "The mix is just the plot getting interesting — stay kind to the load and sneak in extra wind-down.",
)
_WIT_ALREADY = tuple(
    dict.fromkeys(
        [
            *[
                line.split("—", 1)[0].strip().lower()
                for line in (_WIT_PROTECT + _WIT_PROCEED + _WIT_HONEST)
                if "—" in line
            ],
            "clap you into",
            "victory-lap",
            "spend it like it's a dare",
            "plot getting interesting",
            "hold-steady chapter",
            "don't-pick-a-fight",
            "not a pep talk",
        ]
    )
)
_THIN_SPEAK = re.compile(r"^[\s.,;:—–\-]*$")
# Mid-thread discourse already sounds like a person — don't sticker a closer on it.
_FOLLOW_UP_LEADS = (
    "got it", "okay, scratched", "fair.", "alright — shorter", "we cut it",
    "yep — compress", "shorter works", "we trim it", "okay, time-box",
    "yeah — we ease", "lighter it is", "makes sense. soft",
    "sure — we dial", "easier works", "okay, soft mode",
)


def _dumps_user_speak(text: str) -> bool:
    """Iris token scrub plus the Dummy FAIL GATES (scores, bark, clinic, sludge)."""
    raw = str(text or "")
    if not raw.strip():
        return False
    if _VITALS_SPEAK.search(raw):
        return True
    return bool(
        speak_quality.vitals_hits(raw)
        or speak_quality.bark_hits(raw)
        or speak_quality.medical_hits(raw)
        or speak_quality.sludge_hits(raw)
    )


def _scrub_speak_vitals(text: str) -> str:
    """Drop banned vitals tokens in place so a research cite can keep its source label.

    All-or-nothing `_speak_without_vitals` would otherwise discard a whole
    ``From MedlinePlus: … / VO2: …`` note and lose the provenance the person
    is supposed to see.
    """
    scrubbed = _VITALS_SPEAK.sub("", str(text or ""))
    scrubbed = re.sub(r"\s*/\s*(?=:)", "", scrubbed)
    scrubbed = re.sub(r"\s*:\s*:", ":", scrubbed)
    scrubbed = re.sub(r"\s{2,}", " ", scrubbed)
    return scrubbed.strip(" :/,-")


def _speak_without_vitals(*candidates: str) -> str:
    """Return the first candidate that does not dump banned vitals tokens."""
    for text in candidates:
        text = str(text or "").strip()
        if text and not _dumps_user_speak(text):
            return text
    return _SPEAK_FALLBACK


def _collapse_spoken(text: str) -> str:
    """One spoken reply — product cards use labeled \\n\\n sections."""
    body = str(text or "")
    body = re.sub(r"\bWhat I notice\s+", "", body)
    body = re.sub(r"\bOne next step\s+", " ", body)
    body = re.sub(r"\bWhy\s+", " — ", body)
    body = re.sub(r"\n{2,}", " ", body)
    return re.sub(r"\s+", " ", body).strip()


def _wit_line(seed: int, stance: str = "", signals: SignalRead | None = None) -> str:
    """One seed-indexed bank line. Same banks as PR #284 — no parallel system."""
    sleep = getattr(signals, "sleep", "") if signals is not None else ""
    if stance == "protect" or sleep == "thin":
        bank = _WIT_PROTECT
    elif stance == "proceed":
        bank = _WIT_PROCEED
    else:
        bank = _WIT_HONEST
    return _pick(seed ^ 17, list(bank))


# --- Topic-aware, number-free substance for the scrub-fallback path ----------
# The lambda bridge's real prose/message routinely gets fully discarded by the
# vitals scrub below (e.g. _insight_response's own prose_summary is literally
# "{metric}: {value}. {interpretation}." and the interpretation itself often
# embeds a number too, e.g. "Deep sleep at 21% is in a healthy band" — so even
# stripping just the offending clause leaves a sentence fragment, not real
# content). Before friend_speak falls all the way back to a topic-disconnected
# wit line, try one of these: read_signals()'s own qualitative words turned
# into a sentence, same voice as humanize_prose's stub-path sleep_clause bank,
# just reusable outside that closure. No digits by construction, so it can
# never reintroduce what the scrub was trying to catch.
_SLEEP_TALK = {
    "thin": (
        "last night didn't give you a full reset",
        "sleep came up short",
        "the night was thinner than you needed",
        "you woke up already spending energy you didn't bank",
        "rest didn't stick the way it should have",
    ),
    "rebuilt": (
        "you actually rebuilt overnight",
        "you got a night you can spend",
        "sleep finally gave you something to work with",
        "you put real hours in the bank",
        "the night actually paid you back",
    ),
    "decent": (
        "sleep was decent, not extra",
        "the night was middle-ground",
        "you slept enough to move, not enough to burn",
        "it was a usable night — not a free pass",
        "rest was fine, nothing flashy",
    ),
    "unknown": (
        "I don't have last night's sleep logged yet",
        "there's no sleep sample in for last night yet",
    ),
}
_RECOVERY_TALK = {
    "asking": (
        "your body's asking for a break today",
        "recovery is asking for room, not more load",
        "today's reading as a protect day",
    ),
    "ready": (
        "you're sitting in a good spot to push",
        "recovery looks ready to spend",
        "there's real room to work with today",
    ),
    "steady": (
        "recovery is steady, nothing urgent either way",
        "you're holding a steady middle right now",
        "nothing's flashing — just an ordinary day",
    ),
}
_LOAD_TALK = {
    "on_a_streak": (
        "you've been stacking sessions lately",
        "the streak's been real the past while",
        "load's been building up over several sessions",
    ),
    "in_the_legs": (
        "yesterday's work is still in the legs",
        "there's fresh work still settling",
        "you're still carrying the last session",
    ),
    "fresh": (
        "you've had a few easy days",
        "load's been light lately",
        "you're coming in fresh off some rest",
    ),
    "quiet": (
        "training's been quiet the last few days",
        "it's been a slow stretch",
        "there's not much recent load to speak of",
    ),
}
_TOPIC_TALK = {"sleep": _SLEEP_TALK, "recovery": _RECOVERY_TALK, "workout": _LOAD_TALK, "cycle": _LOAD_TALK}
_TOPIC_SIGNAL_FIELD = {"sleep": "sleep", "recovery": "recovery", "workout": "load", "cycle": "load"}


def _qualitative_speak(seed: int, topic: str, signals: SignalRead | None) -> str:
    """A real, on-topic, number-free sentence — what friend_speak reaches for
    before giving up on substance and handing back a disconnected wit line.
    Empty when the topic isn't one of the domains read_signals() covers, or
    signals themselves are unavailable; callers keep the existing wit-only
    fallback in that case, same as before this existed."""
    if signals is None or not topic:
        return ""
    bank = _TOPIC_TALK.get(topic)
    field = _TOPIC_SIGNAL_FIELD.get(topic)
    if not bank or not field:
        return ""
    options = bank.get(getattr(signals, field, ""))
    return _pick(seed ^ 41, list(options)) if options else ""


def _is_follow_up_speak(body: str) -> bool:
    lead = (body or "").strip().lower()
    return any(lead.startswith(p) for p in _FOLLOW_UP_LEADS)


def friend_speak(
    text: str,
    *,
    seed: int,
    stance: str = "",
    signals: SignalRead | None = None,
    guidance: str | None = None,
    short_ok: bool = False,
    topic: str = "",
) -> str:
    """Bubbly/kind friend with a point — funny take + one useful improve.

    Shared by stub phrase banks and the lambda hypertune path. Guidance /
    emergency copy is left alone. Iris vitals scrub still wins after this.

    Fused Dummy speak is often a short notice or the canned fallback; those
    still get a seed-indexed closer so hypertune doesn't read as one template.
    Short mid-thread mutations ("make it easier") stay untouched unless
    ``short_ok`` is set.
    """
    if guidance:
        return str(text or "").strip()
    body = _CHEER_SLUDGE.sub("that's real work", _collapse_spoken(text))
    body = re.sub(r"^[\s.,;:—–\-]+", "", body).strip()
    extra = _wit_line(seed, stance, signals)
    if not body or body == _SPEAK_FALLBACK or _THIN_SPEAK.match(body):
        # The real engine often DID build a substantive answer here — it just
        # got fully scrubbed for citing a raw number (see _qualitative_speak's
        # own comment). Reach for what's actually true about the day before
        # handing back pure, topic-disconnected wit.
        real = _qualitative_speak(seed, topic, signals)
        if real:
            real = real[0].upper() + real[1:]
            if extra and extra.lower() not in real.lower():
                real = f"{real} — {extra}" if real[-1] not in ".!?—" else f"{real} {extra}"
            return _speak_without_vitals(real, extra, _SPEAK_FALLBACK)
        return _speak_without_vitals(extra, _SPEAK_FALLBACK)
    if any(n in body.lower() for n in _WIT_ALREADY):
        return _speak_without_vitals(body)
    if _is_follow_up_speak(body) and not short_ok:
        return _speak_without_vitals(body)
    if extra and extra.lower() not in body.lower():
        if body[-1] not in ".!?":
            body += "."
        body = f"{body} {extra}"
    return _speak_without_vitals(body, extra, _SPEAK_FALLBACK)


def _weave_specialists(prose: str, notes: list[SpecialistNote], seed: int) -> str:
    """Fold specialist asides into one spoken reply instead of stacked briefs.

    Ultra-realistic chat does not dump a Recovery paragraph, then a Sleep
    paragraph. It keeps one voice and lets a second concern ride as a clause.
    """
    body = (prose or "").rstrip()
    if not notes or not body:
        return body
    usable = [
        n for n in notes
        if (n.text or "").strip() and not _dumps_user_speak(n.text)
    ]
    if not usable:
        return body
    # Keep at most two asides; pick by seed for determinism.
    count = 1 if len(usable) == 1 or abs(seed) % 3 else min(2, len(usable))
    chosen = usable[:count]
    clauses: list[str] = []
    for note in chosen:
        text = note.text.strip().rstrip(".")
        # Strip specialist-label openers so it doesn't sound like a meeting.
        for prefix in (
            "Recovery is also in the room — ",
            "Recovery would keep today kind. ",
            "Recovery's steady enough that ",
            "Recovery is looking without a full picture — ",
            "Sleep's been catching up this week, which is why ",
            "Sleep's been running a bit thin this week, so ",
            "Lifestyle's vote: ",
            "Lifestyle's vote is simple: ",
            "Progress is the streak, not a single day — ",
            "Last ",  # workout notes often start "Last {kind} is still…"
        ):
            if prefix == "Last ":
                continue
            if text.startswith(prefix.rstrip()):
                text = text[len(prefix.rstrip()):].lstrip(" —,-")
                break
            # Also match when the note uses a slightly different opener.
            short = prefix.rstrip(" —.")
            if text.startswith(short):
                text = text[len(short):].lstrip(" —,-.")
                break
        if not text:
            continue
        lead = _pick(seed ^ _fnv(note.kind), [
            "Also —",
            "And on the side,",
            "One more thing —",
            "Meanwhile,",
        ])
        clause = f"{lead} {text[0].lower() + text[1:] if text and text[0].isupper() else text}."
        if _dumps_user_speak(clause):
            continue
        if clause.lower() not in body.lower():
            clauses.append(clause)
    if not clauses:
        return body
    if body[-1] not in ".!?":
        body += "."
    return f"{body} {' '.join(clauses)}"


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

    # Discourse follow-ups — "make it easier", "shorter", "skip it" — mutate the
    # last plan instead of restarting a fresh coaching essay. Keep the bridge
    # tiny so we don't stack "from the training side" + a full rewrite.
    follow = _follow_up_reply(message, prior_turns, signals, base)
    if follow:
        # Avoid "Okay — Okay, …" when the follow-up already opens like speech.
        leading = follow.split(",", 1)[0].split("—", 1)[0].strip().lower()
        if leading in {"yeah", "ok", "okay", "sure", "right", "alright", "yep", "got it", "fair"}:
            soft = ""
        else:
            soft = _pick(base, ["Yeah — ", "Okay — ", "Right — ", ""])
        body = follow[0].lower() + follow[1:] if soft.endswith(("— ", ": ")) and follow[:1].isupper() and not follow.startswith(("I ", "I'm ")) else follow
        return f"{soft}{body}" if soft else follow

    def finish(text: str, *, allow_life: bool = True) -> str:
        body = text.rstrip()
        if getattr(context, "is_overtrained", False) or float(getattr(context, "acwr", 0) or 0) >= 1.5:
            low = body.lower()
            if not any(w in low for w in ("acwr", "deload", "back off", "overtrain", "too much")):
                body += " Load is high this week — back off, treat it as a deload."
        if debt > 5.0:
            low = body.lower()
            if not any(w in low for w in ("protect sleep", "protect tonight", "sleep first", "recovery needs priority")):
                body += " Protect sleep tonight rather than adding volume."
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
        # Spoken join: after an em-dash bridge, don't restart like a new essay.
        if opener.endswith(("— ", ": ")) and body[:1].isupper() and not body.startswith(("I ", "I'm ", "I'll ")):
            body = body[0].lower() + body[1:]
        return f"{opener}{body}"

    sleep_clause = ""
    if sleep_h is not None:
        if signals.sleep == "thin":
            sleep_clause = pick(
                "last night didn't give you a full reset",
                "sleep came up short",
                "the night was thinner than you needed",
                "you woke up already spending energy you didn't bank",
                "rest didn't stick the way it should have",
            )
        elif signals.sleep == "rebuilt":
            sleep_clause = pick(
                "you actually rebuilt",
                "you got a night you can spend",
                "sleep finally gave you something to work with",
                "you put real hours in the bank",
                "the night actually paid you back",
            )
        else:
            sleep_clause = pick(
                "sleep was decent, not extra",
                "the night was middle-ground",
                "you slept enough to move, not enough to burn",
                "it was a usable night — not a free pass",
                "rest was fine, nothing flashy",
            )

    if scenario == "sparse_clarify" or "someone like me" in lower:
        return finish(pick(
            "I don't know you well enough yet to pretend I do. What's the goal right now, "
            "and how have the last few nights actually felt?",
            "I'd rather ask than invent a version of you. What are you training toward, "
            "and has sleep been on your side or not?",
            "Give me two things and I'll stop guessing: what you're chasing, and whether "
            "sleep has been helping or fighting you.",
            "I'm not going to cosplay knowing your life. Tell me the goal and how nights "
            "have felt lately — then I can get specific.",
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

    # Before recovery / workout "train" nets so "training age" is never a session plan.
    if kind == "aging" or any(n in lower for n in (
        "training age", "biological age", "fitness age", "how old am i",
        "cardiorespiratory", "vo2 max",
    )):
        return finish(
            "Training age is a lifestyle comparison against the calendar — "
            "cardio fitness, recovery, resting heart, and sleep — not a diagnosis. "
            "I'll keep reading those signals as they come in."
        )

    if recovery:
        ack = ""
        if any(p in lower for p in ("hard", "push", "as hard")):
            ack = pick(
                "I hear that you want to go hard — and I'll help you train, but not like that today. ",
                "Yeah, I get the urge to push. Not today though — ",
                "Wanting hard is fine. Signing off on hard today isn't. ",
            )
        why = sleep_clause or "your recovery hasn't caught up yet"
        session = (
            f" Last {signals.last_session} is still in the picture."
            if signals.last_session and signals.load == "in_the_legs"
            else ""
        )
        return finish(pick(
            f"{ack}I'd keep today kind, because {why}.{session} "
            f"A walk, mobility, or a very light session is enough. We protect tomorrow.",
            f"{ack}Easy day. {why[0].upper() + why[1:] if why else 'Recovery needs the vote'}.{session} "
            f"Save the heavy stuff for a night that actually paid you back.",
            f"{ack}I'm not talking you into hero work while {why}.{session} "
            f"Light movement counts. Rest counts harder.",
        ))

    # Train / default — observe, correlate, invite — with spoken variety.
    if kind == "workout" or any(n in lower for n in ("train", "workout", "session", "gym")):
        session_bit = ""
        if signals.last_session and signals.load == "in_the_legs":
            session_bit = pick(
                f" Last {signals.last_session} is still in the legs, so we progress one thing, not everything.",
                f" You're still carrying yesterday's {signals.last_session} — keep the ask narrow.",
                f" That last {signals.last_session} hasn't fully left, so don't stack hero volume on it.",
            )
        elif signals.load == "on_a_streak":
            session_bit = pick(
                " You're already on a streak, so today's job is to keep it honest, not heroic.",
                " Streak's alive — protect it with clean work, not a victory lap.",
                " Consistency is already winning; don't blow it on one flashy day.",
            )
        if sleep_clause:
            return finish(pick(
                f"You've got something to spend, since {sleep_clause}.{session_bit} "
                f"A solid moderate session fits — progress one thing, leave the hero set.",
                f"Body's willing today because {sleep_clause}.{session_bit} Let's use that on something "
                f"clean rather than reckless. Want the session mapped?",
                f"Green enough to be useful — {sleep_clause}.{session_bit} I'd take a focused session and stop "
                f"while quality is still high.",
                f"Yeah, you can train. {sleep_clause[0].upper() + sleep_clause[1:]}.{session_bit} "
                f"Keep it sharp, not endless.",
            ))
        return finish(pick(
            f"There's room to train — not a parade.{session_bit} I'd take a solid moderate-to-hard session "
            "and see how the first sets feel.",
            f"Today can handle real work.{session_bit} One honest session, one variable progressed — that's the play.",
            f"Go train — just stay honest about how set one feels.{session_bit}",
            f"There's room for a real session today.{session_bit} Want me to sketch it?",
        ))

    if sleep_clause:
        return finish(pick(
            f"Here's how I read you: {sleep_clause}. "
            f"What would help most — train, recover, or just talk it through?",
            f"Short version — {sleep_clause}. Want a plan, a softer day, or just the read?",
            f"My take: {sleep_clause}. Tell me if you want the training version or the recovery one.",
        ))
    return finish(pick(
        "I'm with you. Let's pick one next step that respects today rather than performing it.",
        "I'm here. Tell me whether you want a plan, a read on last night, or just a check-in.",
        "Okay — what's the one thing you want from me right now: a plan, a call on rest, or a straight read?",
        "We can keep this simple. Plan, recover, or talk — your call.",
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


def _provider_snapshot(engine: str) -> dict:
    """Stamp the design-stub routing caps onto a Dummy turn. Never calls AWS."""
    try:
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import provider_capabilities as caps

        path = (
            caps.DEFAULT_PATH
            if (engine or ENGINE_LAMBDA).strip().lower() == ENGINE_LAMBDA
            else "dummy_stub"
        )
        snap = caps.runtime_snapshot(path=path)
        return {
            "path": snap["path"],
            "stages": snap["stages"],
            "bedrock_kill_switch_default": snap["bedrock_kill_switch_default"],
            "do_not_invoke": snap["do_not_invoke"],
            "await_quill_table": snap["await_quill_table"],
            "direction": snap["direction"],
        }
    except Exception:
        return {
            "path": "dummy_stub",
            "stages": ["truth", "personal_model", "stance", "speak"],
            "bedrock_kill_switch_default": False,
            "do_not_invoke": True,
            "await_quill_table": True,
            "direction": "grok_plus_latest_claude",
        }


def _production_fusion():
    """Lazy import of live fusion + engine. Dummy must not own these modules."""
    try:
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import aria_engine as engine_mod
        from services import fusion as fusion_mod

        return fusion_mod, engine_mod
    except Exception:
        return None, None


def _sanitize_chat_message(message: str) -> str:
    """Same inbound scrub ``POST /ai/chat`` uses. Compose, don't reimplement."""
    try:
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from security import MAX_CHAT_MESSAGE_CHARS, sanitize_user_text

        return sanitize_user_text(str(message or ""), max_chars=MAX_CHAT_MESSAGE_CHARS)
    except Exception:
        return (message or "").strip()


def _hrv_trend_points(ctx) -> float | None:
    hist = getattr(ctx, "history", None) or []
    vals = [float(r.hrv) for r in hist if getattr(r, "hrv", None) is not None]
    if len(vals) >= 4:
        half = len(vals) // 2
        early = sum(vals[:half]) / max(len(vals[:half]), 1)
        late = sum(vals[half:]) / max(len(vals[half:]), 1)
        return round(late - early, 2)
    label = str(getattr(ctx, "hrv_7d_trend", "") or "")
    return {"rising": 4.0, "falling": -8.0, "stable": 0.0}.get(label)


def _stream_samples(ctx) -> list[dict]:
    """Project the synthetic stream onto the observe/chat sample bag."""
    history = list(getattr(ctx, "history", None) or [])
    today = getattr(ctx, "today", None)
    if not history and today is not None:
        history = [today]
    samples: list[dict] = []

    def add(rec, typ: str, value, unit: str, **extra) -> None:
        if value is None:
            return
        row = {
            "type": typ,
            "value": value,
            "unit": unit,
            "timestamp": getattr(rec, "date", None) or "",
            # Swarm needs vendor slices (WHOOP / Watch / Oura), not one
            # anonymous ``simrunner`` dump. Untagged samples used to make
            # the dummy orchestra skip the dataset pass entirely.
            "source": _SWARM_SAMPLE_SOURCE.get(typ, "apple-watch"),
        }
        row.update(extra)
        samples.append(row)

    for rec in history:
        hours = getattr(rec, "total_sleep_hours", None)
        if hours is not None:
            add(rec, "sleep", float(hours) * 60.0, "min")
        add(rec, "sleep-stage", getattr(rec, "deep_sleep_minutes", None), "min", stage="deep")
        add(rec, "sleep-stage", getattr(rec, "rem_sleep_minutes", None), "min", stage="rem")
        add(rec, "hrv", getattr(rec, "hrv", None), "ms")
        add(rec, "resting-heart-rate", getattr(rec, "resting_hr", None), "bpm")
        add(rec, "steps", getattr(rec, "steps", None), "count")
        add(rec, "active-calories", getattr(rec, "active_calories", None), "kcal")
    return samples


def sim_context_to_chat_payload(
    ctx,
    *,
    lifestyle_tags: list[str] | None = None,
) -> dict:
    """Bridge SimRunner's flat day snapshot onto an ``ARIAContext`` chat bag.

    Body-owned fields ride as ``samples`` so ``fuse_turn`` can run BodyModel.
    Client-kept domains (training / profile / lifestyle) stay on ``context``.
    """
    today = ctx.today
    hist = list(getattr(ctx, "history", None) or [])
    window3 = hist[-3:] or ([today] if today is not None else [])
    steps = [r.steps for r in window3 if getattr(r, "steps", None)]
    cals = [r.active_calories for r in window3 if getattr(r, "active_calories", None)]
    hours_since = None
    days = getattr(ctx, "days_since_last_workout", None)
    if getattr(today, "workout_logged", False):
        hours_since = 0.0
    elif isinstance(days, (int, float)):
        hours_since = float(days) * 24.0
    sleep_min = None
    if getattr(today, "total_sleep_hours", None) is not None:
        sleep_min = float(today.total_sleep_hours) * 60.0
    last = getattr(ctx, "last_workout_type", None) or getattr(today, "workout_type", None)
    tags = [str(t) for t in (lifestyle_tags or []) if t]
    patterns = [p for p in (getattr(ctx, "occupation", None), getattr(ctx, "life_season", None)) if p]
    if getattr(ctx, "notable_event_note", None):
        patterns.append(str(ctx.notable_event_note))
    wake = getattr(ctx, "target_wake_hour", None)
    wake_s = f"{int(wake):02d}:00" if isinstance(wake, (int, float)) else None
    target_sleep = getattr(ctx, "target_sleep_hours", None)
    onset_s = None
    if isinstance(wake, (int, float)) and isinstance(target_sleep, (int, float)):
        onset = (wake - target_sleep) % 24
        onset_s = f"{int(onset):02d}:{int(round((onset - int(onset)) * 60)):02d}"
    return {
        "user_id": "test-user-00000000",
        "include_stored": False,
        "samples": _stream_samples(ctx),
        "context": {
            "timestamp": getattr(today, "date", None) or "",
            "sleep": {
                "durationMinutes": sleep_min,
                "deepMinutes": getattr(today, "deep_sleep_minutes", None),
                "remMinutes": getattr(today, "rem_sleep_minutes", None),
                "hrv": getattr(today, "hrv", None),
                "restingHR": getattr(today, "resting_hr", None),
                "nightsAvailable": getattr(ctx, "sleep_nights_available_7d", None),
                # These two were missing entirely -- production's sleep-debt
                # directional-safety check (aria_evidence / _recommendation_response's
                # sleep_first gate) silently saw None regardless of what the
                # synthetic day actually carried.
                "sleepDebt7dHours": getattr(ctx, "sleep_debt_7d_hours", None),
                "targetHours": target_sleep,
            },
            "readiness": {
                "hrv7DayTrend": _hrv_trend_points(ctx),
                "hrv30DayBaseline": getattr(ctx, "hrv_7d_avg", None),
                "recoveryScore": getattr(today, "readiness_score", None),
                "hrvDaysAvailable": getattr(ctx, "hrv_days_available_7d", None),
            },
            "training": {
                "lastWorkoutType": last,
                "lastWorkoutName": last,
                "lastWorkoutDurationMinutes": getattr(today, "workout_duration_minutes", None),
                "hoursSinceLastWorkout": hours_since,
                # Was silently stuffing ACWR into weeklyLoadScore (a distinct
                # field on production's TrainingContext, "normalized, null if
                # < 3 sessions") and never setting the real acwr key at all --
                # production's overtraining check (`t.acwr >= 1.5`) always saw
                # None. weeklyLoadScore has no SimRunner equivalent, so it
                # stays unset rather than carrying a wrong number.
                "acwr": getattr(today, "acwr", None),
                "isOvertrained": bool(getattr(ctx, "is_overtrained", False)),
            },
            "activity": {
                "steps3DayAvg": (sum(steps) / len(steps)) if steps else None,
                "activeCalories3DayAvg": (sum(cals) / len(cals)) if cals else None,
            },
            "chronotype": {
                "typicalSleepOnset": onset_s,
                "typicalWakeTime": wake_s,
            },
            "profile": {
                "experienceLevel": getattr(ctx, "experience_level", None),
                "coachingStyle": getattr(ctx, "coaching_style", None),
            },
            "progress": {
                "trainingLoadTrend": getattr(ctx, "readiness_trend", None),
                "workoutsCompleted30d": getattr(ctx, "training_streak", None),
            },
            "lifestyle": {
                "tags": tags,
                "recentPatterns": patterns,
            },
        },
    }


def _scrub_fused_speak(envelope: dict) -> dict:
    """Compose with the Iris vitals scrub already on this branch — don't replace it."""
    prose = _speak_without_vitals(envelope.get("prose_summary") or "")
    chat = _speak_without_vitals(envelope.get("message") or "", prose)
    envelope["prose_summary"] = prose
    envelope["message"] = chat
    card = envelope.get("card")
    if isinstance(card, dict):
        for key in ("action", "rationale", "timing", "expected_effect", "why", "interpretation"):
            if card.get(key):
                card[key] = _speak_without_vitals(str(card[key]), prose)
        envelope["card"] = card
    return envelope


def _bridge_fused_memory(
    envelope: dict,
    prior_turns: list[str] | None,
    seed: int,
    intents: list[IntentHit],
) -> dict:
    """Keep a spoken night/sleep thread on the lambda engine (single-turn product)."""
    if not prior_turns:
        return envelope
    opener = _callback(prior_turns, seed, intents)
    if not opener:
        return envelope
    prior = " ".join(t for t in prior_turns if t)
    for key in ("prose_summary", "message"):
        text = str(envelope.get(key) or "").strip()
        if not text or not speak_quality.memory_hole_hits(prior, text):
            continue
        body = text
        if opener.endswith(("— ", ": ")) and body[:1].isupper() and not body.startswith(("I ", "I'm ", "I'll ")):
            body = body[0].lower() + body[1:]
        envelope[key] = f"{opener}{body}"
    return envelope


def _respond_via_lambda(
    message: str,
    ctx,
    plan: Plan,
    intents: list[IntentHit],
    *,
    seed: int,
    day_index: int,
    prior_turns: list[str] | None,
    lifestyle_tags: list[str] | None,
) -> dict:
    """Product path: fuse the synthetic day, then deterministic generate_response."""
    fusion_mod, engine_mod = _production_fusion()
    if fusion_mod is None or engine_mod is None:
        raise RuntimeError("lambda engine requires services.fusion and services.aria_engine")

    safe = _sanitize_chat_message(message)
    payload = sim_context_to_chat_payload(ctx, lifestyle_tags=lifestyle_tags)
    payload["message"] = safe
    # Compose with the inbound sanitizer already on this branch — partner/cycle
    # PII and calendar titles never reach fuse_turn.
    try:
        from routes.aria import sanitize_inbound_chat_payload

        payload = sanitize_inbound_chat_payload(payload)
    except Exception:
        pass
    permissions = engine_mod.DataPermissions.allow_all()
    fused = fusion_mod.fuse_turn(
        "test-user-00000000",
        payload,
        permissions,
        persist=False,
        include_stored=False,
        load_learner=True,
    )
    # Deterministic speak only. generate_response_live is never on this path.
    envelope = engine_mod.generate_response(
        safe,
        fused.context,
        permissions=permissions,
        persona=fused.persona,
        baselines=fused.baselines,
    )
    envelope = _scrub_fused_speak(envelope)
    envelope = _bridge_fused_memory(envelope, prior_turns, seed, intents)
    sidecar = fused.fusion_sidecar()
    existing = envelope.get("fusion") if isinstance(envelope.get("fusion"), dict) else {}
    envelope["fusion"] = {**sidecar, **existing}
    stance = envelope["fusion"].get("stance")
    signals = read_signals(ctx)
    guidance = envelope.get("guidance_band")
    # Fused notices are often <28 words; Dummy hypertune still needs local wit.
    prose = friend_speak(
        envelope.get("prose_summary") or "",
        seed=seed,
        stance=str(stance or ""),
        signals=signals,
        guidance=guidance,
        short_ok=True,
        topic=plan.primary.kind,
    )
    chat = friend_speak(
        envelope.get("message") or prose,
        seed=seed,
        stance=str(stance or ""),
        signals=signals,
        guidance=guidance,
        short_ok=True,
        topic=plan.primary.kind,
    )
    prose = _speak_without_vitals(prose)
    chat = _speak_without_vitals(chat, prose)
    envelope["prose_summary"] = prose
    envelope["message"] = chat
    diagnosis = voice_diagnostics.diagnose(prose)
    orch_ms = _orchestration_latency_ms(message, seed, len(plan.workers))
    brief = envelope.get("contextualization") if isinstance(envelope.get("contextualization"), dict) else None

    card = envelope.get("card")
    row = {
        **envelope,
        "schema_version": envelope.get("schema_version") or "1.1",
        "prose_summary": prose,
        "message": envelope.get("message") or prose,
        "suggested_actions": list(envelope.get("suggested_actions") or suggested_actions(plan)),
        "card": card,
        "rich_card": envelope.get("rich_card"),
        # Production's envelope has no top-level "recommendation" key -- only
        # the recommendation response_type's card carries one, as card["action"]
        # (see aria_engine.py's _recommendation_response). Set it explicitly so
        # DummyARIAEngine.respond() (which reads row.get("recommendation") the
        # same way the stub row already does at "recommendation": stub.recommendation)
        # gets a real value instead of always None.
        "recommendation": card.get("action") if isinstance(card, dict) else None,
        "restricted_domains": list(envelope.get("restricted_domains") or []),
        "agent": plan.primary.kind,
        "agents": plan.kinds,
        "workers": [w.as_dict() for w in plan.workers],
        "reasoning_source": LAMBDA_REASONING_SOURCE,
        "test_ready": True,
        "model": LAMBDA_MODEL,
        "user_id": "test-user-00000000",
        "voice_diagnosis": diagnosis.as_dict(),
        "thinking": (
            f"Heard {', '.join(h.kind for h in intents[:3]) or plan.primary.kind}. "
            f"Fused {stance or 'stance'} via BodyModel ({fused.source}); Bedrock off."
        ),
        "scenario": str(envelope.get("guidance_band") or stance or envelope.get("response_type") or ""),
        "stub_prose": None,
        "session": envelope.get("session"),
        "orchestration": {
            "engine": ENGINE_LAMBDA,
            "stages": list(ORCH_STAGES),
            "intents": [
                {"kind": h.kind, "weight": h.weight, "cues": list(h.cues)}
                for h in intents
            ],
            "primary": plan.primary.kind,
            "fusion_source": fused.source,
            "owned_domains": list(fused.owned_domains),
            "observation_count": fused.observation_count,
            "stance": stance,
            "persona": {
                "occupation": getattr(ctx, "occupation", None),
                "chronotype": getattr(ctx, "chronotype", None),
                "season": getattr(ctx, "life_season", None),
                "experience": getattr(ctx, "experience_level", None),
            },
            "latency_ms": orch_ms,
            "engine_latency_ms": 0,
            "prior_turns": len(prior_turns or []),
            "day_index": day_index,
            "provider": _provider_snapshot(ENGINE_LAMBDA),
        },
    }
    if brief is not None:
        row["contextualization"] = brief
        orch = dict(row.get("orchestration") or {})
        orch.update(
            {
                "learner": "services.contextual_learner",
                "owner": "live-backend",
                "consumer": "dummy-test",
                "durable": True,
                "grounding": brief.get("grounding"),
                "prioritize": list(brief.get("prioritize") or []),
                "event": brief.get("event_bucket"),
                "learner_stages": ["observe", "plan", "rank", "adapt", "commit", "judge"],
            }
        )
        row["orchestration"] = orch
    return _attach_swarm(row, ctx, samples=payload.get("samples") if isinstance(payload, dict) else None)


def _orchestration_latency_ms(message: str, seed: int, worker_count: int) -> int:
    """Fake-but-stable overhead: scoring + fan-out, not a wall-clock sleep."""
    return 40 + (_fnv(message) ^ (seed * 16777619) ^ (worker_count * 31)) % 90


# Sentinel so a failed / empty lookup (None) is still a cached turn result.
_WEB_NOTE_UNSET = object()


def _web_note_for_turn(kind: str) -> str | None:
    """Fetch at most once per user turn. Prompt-guard retry reuses the cite.

    The live guard regenerates a turn to rephrase; it must not hit the web
    again. A missed or later-scrubbed note stays the same — do not re-fetch
    hoping for a cleaner snippet.
    """
    cached = getattr(respond, "_turn_web_note", _WEB_NOTE_UNSET)
    if cached is not _WEB_NOTE_UNSET:
        return cached
    note = web_research.look_up(kind)
    respond._turn_web_note = note
    return note


def _reset_turn_web_note() -> None:
    respond._turn_web_note = _WEB_NOTE_UNSET


def _context_for_turn(
    *,
    seed: int,
    model_id: str | None,
    day_index: int,
    context=None,
    pack_day=None,
    use_pack: bool = False,
):
    """Prefer an explicit ARIAContext; else a FakeHealthPack day; else the persona stream."""
    from . import fake_health_pack
    from .fake_health_bridge import context_from_pack_day

    model = model_registry.resolve_archetype(model_id) if model_id else model_registry.get_models_by_tier(1)[0]
    profile = model["behavioral_profile"]
    if context is not None:
        return context, model
    if pack_day is None and use_pack:
        pack = fake_health_pack.generate(seed=seed)
        days = pack["days"]
        idx = min(max(0, day_index), len(days) - 1)
        pack_day = days[idx]
    if pack_day is not None:
        ctx = context_from_pack_day(pack_day, persona=profile.get("occupation"))
        ctx.occupation = profile.get("occupation", ctx.occupation)
        ctx.chronotype = profile.get("chronotype", ctx.chronotype)
        ctx.experience_level = profile.get("experience_level", ctx.experience_level)
        ctx.life_season = profile.get("season", ctx.life_season)
        ctx.coaching_style = profile.get("coaching_style", getattr(ctx, "coaching_style", "balanced"))
        return ctx, model
    stream = generate_stream(profile, seed)
    return build_context(stream, profile, day_index), model


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
    engine: str = ENGINE_LAMBDA,
    lifestyle_tags: list[str] | None = None,
    context=None,
    pack_day=None,
    use_pack: bool = False,
) -> dict:
    """One SimRunner turn. Default ``engine="lambda"`` hypertunes against fused
    product speak (``fuse_turn`` + ``generate_response``). ``engine="stub"``
    is the SimRunner matrix path.

    Pipeline (always local, Bedrock off):
      ingest → route specialists → swarm (read/evaluate/write wearables)
      → reason → specialize → synthesize → voice.

    Never calls Bedrock, AWS, or any other cloud.
    Default body is the FakeHealthPack twin (same fields iOS writes to HealthKit).
    Pass ``context=`` to score a SimRunner persona stream instead.

    After the turn is built, SimRunner scores honesty and replays the facts
    once. If either is below 70, the turn becomes a cautious estimate —
    never the contested claim, never its reverse, and never a connection drop.
    """
    refuse_if_cloud()

    if not getattr(respond, "_replaying", False):
        _reset_turn_web_note()
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from aria_core import prompt_guard

        if prompt_guard.enabled():
            respond._replaying = True
            try:
                return prompt_guard.checked(
                    lambda: respond(
                        message,
                        seed=seed,
                        model_id=model_id,
                        pinned=pinned,
                        agents=agents,
                        cycle_subjects=cycle_subjects,
                        prior_turns=prior_turns,
                        day_index=day_index,
                        engine=engine,
                        lifestyle_tags=lifestyle_tags,
                        context=context,
                        pack_day=pack_day,
                        use_pack=use_pack,
                    )
                )
            finally:
                respond._replaying = False
                _reset_turn_web_note()

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

    ctx, _model = _context_for_turn(
        seed=seed, model_id=model_id, day_index=day_index,
        context=context, pack_day=pack_day, use_pack=use_pack,
    )
    if (engine or ENGINE_LAMBDA).strip().lower() == ENGINE_LAMBDA:
        return _respond_via_lambda(
            message,
            ctx,
            plan,
            intents,
            seed=seed,
            day_index=day_index,
            prior_turns=prior_turns,
            lifestyle_tags=lifestyle_tags,
        )
    stub = _offline_stub(message, ctx, seed)
    signals = read_signals(ctx)

    notes = specialist_notes(plan, ctx)
    scenario = str((getattr(stub, "raw", None) or {}).get("scenario") or "")
    prose = humanize_prose(
        message, stub, ctx, plan, seed=seed, prior_turns=prior_turns,
    )
    # Weave specialists into one spoken reply — not stacked \n\n briefs.
    prose = _weave_specialists(prose, notes, seed=seed ^ _fnv(message))
    body_session = _suggest_body_session(message, ctx)
    if (
        body_session is not None
        and plan.primary.kind == "workout"
        and scenario in ("train", "recovery_first", "")
        and not _is_follow_up_speak(prose)
    ):
        spoken = body_session.spoken()
        if spoken and spoken not in prose:
            prose = f"{prose} {spoken}"
    # friend_speak after the full spoken body so the closer lands on the
    # essay plus body-library line, not a truncated half-turn.
    if scenario == "recovery_first" or signals.sleep == "thin" or signals.recovery == "asking":
        stub_stance = "protect"
    elif plan.primary.kind == "workout" or "train" in message.lower() or "workout" in message.lower():
        stub_stance = "proceed"
    else:
        stub_stance = ""
    prose = friend_speak(prose, seed=seed, stance=stub_stance, signals=signals)
    # Optional web note stays as a short trailing cite — not a specialist dump.
    # Scrub vitals inside the cite first so VO2 in a MedlinePlus title cannot
    # make `_speak_without_vitals` discard the whole "From …" provenance.
    chat = prose
    if web_research.is_research_worthy(message, plan.primary.kind):
        lookup_kind = "aging" if web_research.suggests_aging(message) or plan.primary.kind == "aging" else plan.primary.kind
        web_note = _web_note_for_turn(lookup_kind)
        if web_note:
            safe_note = _scrub_speak_vitals(web_note)
            if safe_note and safe_note not in chat and not _dumps_user_speak(safe_note):
                chat = f"{chat} ({safe_note.rstrip('.')})"
    prose = _speak_without_vitals(prose)
    chat = _speak_without_vitals(chat, prose)
    recovery_needed = scenario == "recovery_first" or ctx.today.readiness_score < 50

    # Diagnosed against the primary reply alone, not the full chat: supporting
    # briefs are asides by design. Folding them in would mark a human primary
    # reply as data-driven for the company it keeps.
    diagnosis = voice_diagnostics.diagnose(prose)
    orch_ms = _orchestration_latency_ms(message, seed, len(plan.workers))
    engine_ms = int(round(getattr(stub, "latency_ms", 0) or 0))

    brief, plan = _consume_learner(message, ctx, plan)

    row = {
        "schema_version": "1.1",
        "response_type": _response_type(scenario),
        "confidence": stub.confidence,
        "confidence_reason": _confidence_reason(stub, signals, scenario),
        "prose_summary": prose,
        "recommendation": getattr(stub, "recommendation", None),
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
            "provider": _provider_snapshot(ENGINE_STUB),
        },
    }
    if brief is not None:
        row["contextualization"] = brief.as_dict()
        orch = dict(row.get("orchestration") or {})
        orch.update(
            {
                "learner": "services.contextual_learner",
                "owner": "live-backend",
                "consumer": "dummy-test",
                "durable": True,
                "grounding": brief.grounding,
                "prioritize": list(brief.prioritize),
                "event": brief.event_bucket,
                "learner_stages": ["observe", "plan", "rank", "adapt", "commit", "judge"],
            }
        )
        row["orchestration"] = orch
    return _attach_swarm(row, ctx)


class DummyARIAEngine:
    """Evaluator-facing adapter: SimRunner grades the Test-Ready dummy, not the
    imperfect model-archetype stub. Duck-types ARIAEngine.respond."""

    use_real_api = False

    def __init__(self) -> None:
        from . import model_archetypes as ma
        self.archetype = ma.get("baseline")

    def respond(self, query: str, context, seed: int = 0):
        from .aria_engine import ARIAResponse

        row = respond(query, seed=seed, context=context, engine=ENGINE_LAMBDA)
        return ARIAResponse(
            prose_summary=row["message"] or row["prose_summary"],
            recommendation=row.get("recommendation"),
            confidence=float(row.get("confidence") or 0.74),
            used_context=True,
            model_used=str(row.get("model") or LAMBDA_MODEL),
            query_type=row.get("agent") or "aria",
            latency_ms=float((row.get("orchestration") or {}).get("latency_ms") or 40),
            raw={"scenario": row.get("scenario") or "dummy", "test_ready": True},
        )

    def detect_model(self) -> str:
        return LAMBDA_MODEL

    def active_models(self) -> dict:
        return {"dummy": LAMBDA_MODEL}


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
            engine=ENGINE_STUB,
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
        row = respond(prompt, seed=seed, engine=ENGINE_STUB)
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
