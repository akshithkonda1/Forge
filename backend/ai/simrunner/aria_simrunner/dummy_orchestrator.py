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
    today = context.today
    lines: list[str] = []
    for worker in plan.workers:
        if worker.is_primary:
            continue
        if worker.kind == "recovery":
            hrv_bit = f"{today.hrv}ms" if today.hrv is not None else "unavailable"
            if today.total_sleep_hours is not None:
                lines.append(
                    f"Recovery · {today.total_sleep_hours:.1f}h sleep, HRV {hrv_bit}, "
                    f"readiness {today.readiness_score}."
                )
            else:
                lines.append(f"Recovery · sleep unavailable, HRV {hrv_bit}, readiness {today.readiness_score}.")
        elif worker.kind == "workout" and today.workout_logged:
            lines.append(
                f"Workout · last {today.workout_type} {today.workout_duration_minutes} min."
            )
        elif worker.kind == "sleep":
            debt = context.sleep_debt_7d_hours
            if debt <= 0.5:
                lines.append("Sleep · squared away over the last week.")
            else:
                lines.append(f"Sleep · {debt:.1f}h of debt over the last week.")
        elif worker.kind == "lifestyle":
            lines.append(
                f"Lifestyle · {today.active_calories} active cal today — water and "
                "the next meal still count."
            )
        elif worker.kind == "progress" and context.training_streak >= 2:
            lines.append(
                f"Progress · a {context.training_streak}-day training streak — "
                "the trend that matters."
            )
        elif worker.kind == "cycle" and worker.subject:
            lines.append(f"Cycle · {worker.subject}: show up, don’t diagnose.")
    return lines


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

    prose = stub.prose_summary
    chat = prose if not extras else f"{prose}\n\n" + "\n".join(extras)

    # Diagnosed against the primary reply alone, not the full chat: supporting
    # briefs ("Workout · 45 min") are deliberately terse tags by design, not
    # attempts at organic prose, so folding them in would unfairly mark a
    # genuinely human primary reply as data-driven for the company it keeps.
    diagnosis = voice_diagnostics.diagnose(prose)

    return {
        "schema_version": "1.1",
        "response_type": "recommendation",
        "confidence": stub.confidence,
        "confidence_reason": "simrunner stub on synthetic data — test-ready, not production",
        "prose_summary": prose,
        "message": chat,
        "suggested_actions": ["What should I train?", "How did I sleep?", "How do I show up?"],
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
