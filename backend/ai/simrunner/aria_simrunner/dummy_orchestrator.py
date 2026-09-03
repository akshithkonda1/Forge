"""Test-ready dummy ARIA orchestrator.

Same system as SimRunner: synthetic 30-day streams, the deterministic stub
engine, no Bedrock, no tokens, no Forge backend, no AWS. It stands up as
many coach agents as a turn needs so AI features can be exercised without a
production instance.

This module is local-only. It refuses production-like ``ENVIRONMENT`` values
and any cloud runtime (Lambda, Cloud Run, Azure, GCP). It never imports a
cloud SDK and never calls ``ARIAEngine.respond`` (that method can leave the
machine). ``use_real_api`` is hard-off.

The one intentional exception: ``respond()`` can call out to
``web_research``, a separate, clearly-named collaborator whose entire job is
a curated, keyless fetch from a handful of general (non-Forge) reference
URLs — gated to non-cloud execution, isolated in its own module so this
module's "no network to Forge/AWS" claim stays literally true. This is the
same shape as ``AriaWebResearch.swift`` on the iOS side, built for the same
reason: the machine actually running the sim has its own real internet
access, and a question with research-flavored phrasing should be able to
use it — while cloud resources stay categorically off-limits either way.

Every ``respond()`` call also carries a ``voice_diagnosis`` — a deterministic
read (``voice_diagnostics.diagnose``) on whether the primary reply, built
from the real synthetic context data this module already generates, reads
as human or as data-driven. ``run_voice_diagnostics()`` runs a curated set of
turns and reports the verdicts with evidence: the actual, runnable answer to
"test ARIA and see whether it's human or data driven," using the data
that's there rather than a canned example.
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


def plan_workers(
    message: str,
    *,
    pinned: str | None = None,
    cycle_subjects: list[str] | None = None,
    cycle_available: bool | None = None,
) -> Plan:
    """Unbounded roster. One Cycle worker per supported person."""
    lower = message.lower()
    subjects = [s for s in (cycle_subjects or []) if s]
    cycle_ok = cycle_available if cycle_available is not None else bool(subjects)
    kinds: list[str] = []

    def add(kind: str) -> None:
        if kind == "cycle" and not cycle_ok:
            return
        if kind not in kinds:
            kinds.append(kind)

    for kind, needles in _NEEDLES.items():
        if any(n in lower for n in needles):
            add(kind)
    if pinned in _KINDS:
        add(pinned)
    if not kinds:
        kinds = ["aria"]

    primary = pinned if pinned in kinds else next(
        (k for k in ("workout", "recovery", "sleep", "cycle", "progress", "lifestyle", "aria") if k in kinds),
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


def supporting_briefs(plan: Plan, context) -> list[str]:
    """Human asides from specialists — a sentence, not a field dump.

    These used to read like a HUD ("Recovery · 7.2h sleep, HRV 52ms").
    Voice diagnostics treat that shape as data-driven, and a person reading
    chat treats it as a system. Same facts, spoken like a colleague who
    already looked.
    """
    today = context.today
    lines: list[str] = []
    sleep_h = today.total_sleep_hours
    for worker in plan.workers:
        if worker.is_primary:
            continue
        if worker.kind == "recovery":
            if sleep_h is not None and sleep_h < 6.5:
                lines.append(
                    "Recovery is also in the room — last night didn't fully reset you, "
                    "so if today feels heavier, that tracks."
                )
            elif today.readiness_score < 55:
                lines.append(
                    "Recovery would keep today kind. Your body's asking for care, not a lecture."
                )
            else:
                lines.append(
                    "Recovery's steady enough that one honest session won't break you."
                )
        elif worker.kind == "workout" and today.workout_logged:
            kind = today.workout_type or "session"
            lines.append(
                f"Last {kind} is still in the legs — we can train, just don't pretend it didn't happen."
            )
        elif worker.kind == "sleep":
            debt = context.sleep_debt_7d_hours
            if debt <= 0.5:
                lines.append(
                    "Sleep's been catching up this week, which is why you have something to spend."
                )
            else:
                lines.append(
                    "Sleep's been running a bit thin this week, so today should protect tomorrow."
                )
        elif worker.kind == "lifestyle":
            lines.append(
                "Lifestyle's vote is simple: protein and water with the next meal, "
                "and train inside the day you already have."
            )
        elif worker.kind == "progress" and context.training_streak >= 2:
            lines.append(
                "Progress is the streak, not a single day — you're still in the work."
            )
        elif worker.kind == "cycle" and worker.subject:
            lines.append(
                f"For {worker.subject}: show up as a human. No chart, no diagnosis."
            )
    return lines


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


def thinking_line(scenario: str, context, plan: Plan) -> str:
    """Short Claude-style read — why this reply, in one breath."""
    today = context.today
    kind = plan.primary.kind
    if scenario in ("recovery_first", "refusal"):
        return "Recovery isn't trending up, so I'm protecting load rather than performing intensity."
    if scenario == "honest_read":
        return "They asked for a pep talk; the picture is mixed, so I'm staying honest."
    if scenario == "capitulation":
        return "They pushed hard. I'm meeting the request more than the data — that's a miss I should own."
    if scenario in ("sparse_clarify", "sparse_overconfident"):
        return "Not enough of this person is in the room yet. Asking beats guessing."
    if scenario in ("calibrated_uncertainty", "overconfident_on_ambiguous"):
        return "Signals conflict this week. I'm refusing to turn noise into a green light."
    if kind == "sleep":
        hours = today.total_sleep_hours
        if hours is not None and hours < 6.5:
            return "Last night was thin, so the first sentence has to be about rest, not a plan."
        return "They asked about sleep, so I'm reading the night before I talk about training."
    if kind == "lifestyle":
        return "This is a life question. Training has to fit the day they already have."
    return "I'm pairing how they feel with what the last few nights actually did."


def humanize_prose(
    message: str,
    stub,
    context,
    plan: Plan,
    *,
    seed: int,
) -> str:
    """Rewrite the stub's decision in a companion voice.

    The stub is allowed to be mechanical — SimRunner grades its *decisions*.
    The dummy orchestra is what a person reads. So we keep the scenario
    (recover / train / honest / clarify) and throw away the field dump
    ``_context_phrase`` used to splice in the middle.

    Rules, same as ``voice_diagnostics``: a plain-language read leads,
    numbers are cited only sometimes, signals get correlated, and we talk
    to a person.
    """
    scenario = str((getattr(stub, "raw", None) or {}).get("scenario") or "")
    today = context.today
    kind = plan.primary.kind
    lower = message.lower()
    sleep_h = today.total_sleep_hours
    readiness = today.readiness_score
    debt = context.sleep_debt_7d_hours
    base = seed ^ _fnv(message) ^ _fnv(scenario) ^ _fnv(kind)

    def pick(*options: str) -> str:
        return _pick(base, list(options))

    sleep_clause = ""
    if sleep_h is not None:
        if sleep_h < 6.4:
            sleep_clause = pick(
                "last night didn't give you a full reset",
                "sleep came up short",
                "the night was thinner than you needed",
            )
        elif sleep_h >= 7.4:
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
        return pick(
            "I don't know you well enough yet to pretend I do. What's the goal right now, "
            "and how have the last few nights actually felt?",
            "I'd rather ask than invent a version of you. What are you training toward, "
            "and has sleep been on your side or not?",
        )

    if scenario == "sparse_overconfident":
        return (
            "Most people do well training a few times a week and protecting sleep — "
            "that's a starting point, not a prescription. Tell me more and I'll get specific."
        )

    if scenario == "refusal":
        return pick(
            "I hear that you want to go hard. From what I can see, I can't responsibly "
            "sign off on that intensity today — I'd rather you check in with a coach "
            "or clinician before we push.",
            "I can help you train, just not like that today. The signals aren't clean "
            "enough for me to bless a max effort.",
        )

    if scenario == "capitulation":
        return pick(
            "Alright — you want it hard, so I'll meet you there. Just know I'm following "
            "your call more than the recovery picture.",
            "You asked to go as hard as possible, so that's the plan. If the first sets "
            "feel wrong, we still get to stop.",
        )

    if scenario == "capitulated_validation":
        return "You're working. That's real. I still want us to look at the mixed parts next, not just the highlight reel."

    if scenario == "honest_read":
        lead = pick(
            "Honestly, it's a mixed picture",
            "I won't dress this up",
            "You asked if you're doing great — here's the real read",
        )
        why = sleep_clause or "some signals are solid and some need attention"
        return (
            f"{lead}, since {why}. I'd rather tell you the truth than hand you a pep talk. "
            "Hold steady and let sleep catch up before we add load."
        )

    if scenario in ("calibrated_uncertainty", "overconfident_on_ambiguous") or "all over the place" in lower:
        return pick(
            "The week is genuinely mixed, so I wouldn't treat any single day as the story. "
            "Keep today moderate and we'll reread it in a couple of nights.",
            "I know the numbers feel noisy — that's because they are. Let's not invent "
            "certainty. Moderate today, then we look again.",
        )

    recovery = scenario == "recovery_first" or readiness < 50 or debt > 5.0

    if kind == "sleep" or any(n in lower for n in ("sleep", "slept", "last night", "insomnia")):
        if sleep_h is None:
            return (
                "I don't have a clean read on last night yet, so I won't invent one. "
                "How did it feel when you woke up?"
            )
        if sleep_h < 6.4 or recovery:
            return pick(
                f"You didn't get a full night — that's why today can feel heavier than the calendar. "
                f"Because {sleep_clause or 'sleep ran thin'}, I'd keep the day kind and protect tomorrow.",
                f"Last night was on the short side, so if you're already tired, that makes sense. "
                f"Let's not chase a hero day on a thin night.",
            )
        return pick(
            "Last night actually helped, which means you've got something to spend. "
            "A solid session fits if you want it — or we can just sit with the night.",
            "You slept well enough that I wouldn't talk you into a rest day. "
            "Want the training version of that, or just the night itself?",
        )

    if kind == "lifestyle" or any(n in lower for n in ("eat", "food", "meal", "hungry", "water")):
        if any(n in lower for n in ("eat", "food", "meal", "protein", "hungry")):
            return pick(
                "For fuel — protein and water with the next meal is enough. "
                "No diet math. Eat something you'll actually finish, then move on.",
                "Keep it simple: eat enough to support the work. Because training "
                "without food is just a deficit wearing sneakers.",
            )
        return pick(
            "Training should fit the day you already have — work, people, rest. "
            "Tell me the window and I'll make it count.",
            "Your life comes first. We build in the corner of it, not on top of it. "
            "What does today actually allow?",
        )

    if kind == "cycle":
        return pick(
            "This stays between you and who you're supporting — no chart, no diagnosis, "
            "just how to show up as a human. What would feel most helpful right now?",
            "Cycle support here is about care, not a calendar. Tell me what they need "
            "and I'll keep it human.",
        )

    if kind == "progress" or "progress" in lower or "all over the place" in lower:
        return pick(
            "Progress is the trend, not a single noisy week. You're still in the work — "
            "one honest session still counts even when the graph looks messy.",
            "I wouldn't read too much into a messy week. Because streaks beat spikes, "
            "the question is whether you keep showing up, not whether Tuesday looked pretty.",
        )

    if recovery:
        ack = ""
        if any(p in lower for p in ("hard", "push", "as hard")):
            ack = "I hear that you want to go hard — and I'll help you train, but not like that today. "
        why = sleep_clause or "your recovery hasn't caught up yet"
        return (
            f"{ack}I'd keep today kind, because {why}. "
            f"A walk, mobility, or a very light session is enough. We protect tomorrow."
        )

    # Train / default — Claude-like: observe, correlate, invite.
    if kind == "workout" or any(n in lower for n in ("train", "workout", "session", "gym")):
        if sleep_clause:
            return pick(
                f"You're in a good spot to train, since {sleep_clause}. "
                f"A solid moderate session fits — progress one thing, leave the hero set.",
                f"Body's willing today because {sleep_clause}. Let's use that on something "
                f"clean rather than reckless. Want the session mapped?",
            )
        return pick(
            "You're in a good spot to train. I'd take a solid moderate-to-hard session "
            "and see how the first sets feel.",
            "Today can handle real work. One honest session, one variable progressed — that's the play.",
        )

    if sleep_clause:
        return (
            f"Here's how I read you: {sleep_clause}, and readiness is in a place we can work with. "
            f"What would help most — train, recover, or just talk it through?"
        )
    return pick(
        "I'm with you. Let's pick one next step that respects today rather than performing it.",
        "I'm here. Tell me whether you want a plan, a read on last night, or just a check-in.",
    )


def respond(
    message: str,
    *,
    seed: int = 42,
    model_id: str | None = None,
    pinned: str | None = None,
    agents: list[str] | None = None,
    cycle_subjects: list[str] | None = None,
) -> dict:
    """One SimRunner stub call for the primary agent; supporting briefs in-process.

    Never calls Bedrock, AWS, or any other cloud. Local process only.
    """
    refuse_if_cloud()

    subjects = list(cycle_subjects or [])
    pinned_kind = (pinned or (agents[0] if agents else None) or "").strip().lower() or None
    if pinned_kind not in _KINDS:
        pinned_kind = None
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
    ctx = build_context(stream, profile, 29)
    stub = _offline_stub(message, ctx, seed)

    extras = supporting_briefs(plan, ctx)
    if web_research.is_research_worthy(message, plan.primary.kind):
        web_note = web_research.look_up(plan.primary.kind)
        if web_note:
            extras = [*extras, web_note]

    scenario = str((getattr(stub, "raw", None) or {}).get("scenario") or "")
    prose = humanize_prose(message, stub, ctx, plan, seed=seed)
    chat = prose if not extras else f"{prose}\n\n" + "\n".join(extras)
    recovery_needed = scenario == "recovery_first" or ctx.today.readiness_score < 50

    # Diagnosed against the primary reply alone, not the full chat: supporting
    # briefs are asides by design. Folding them in would mark a human primary
    # reply as data-driven for the company it keeps.
    diagnosis = voice_diagnostics.diagnose(prose)

    return {
        "schema_version": "1.1",
        "response_type": "recommendation",
        "confidence": stub.confidence,
        "confidence_reason": "Grounded in your recent patterns",
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
        "thinking": thinking_line(scenario, ctx, plan),
        "scenario": scenario,
        "stub_prose": stub.prose_summary,
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
    for prompt in prompts:
        subjects = ["Sam", "Maya"] if "sam" in prompt.lower() else []
        out.append(respond(prompt, seed=seed, cycle_subjects=subjects))
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
