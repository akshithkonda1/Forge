"""Bridge between SimRunner's synthetic ARIAContext/ARIAResponse and
production's real aria_core.aria_engine.

SimRunner's own ``ARIAContext`` (``backend_simulator/data_generator.py``) is a
flat, purpose-built shape for grading — structurally different from
production's nested, domain-object ``ARIAContext``
(``aria_core/aria_engine.py``). This module converts one way (SimRunner
context -> production context, so ``generate_response()`` has something real
to reason over) and the other way (production's response envelope dict ->
SimRunner's typed ``ARIAResponse``, so ``aria_evaluator.evaluate()`` — and the
whole isometric/directional/tone test suite built against that typed shape —
keeps working completely unchanged).

Import of the Lambda package (``aria_core``) is lazy, inside
``to_production_context``, matching the same "SimRunner stays stdlib-only
until something explicitly opts into the bridge" discipline
``aria_evaluator._guidance()`` already uses for the same reason.

Two structural gaps are real, not smoothed over:

1. Production has no field for a workout's peak heart rate, so it has no way
   to reason about an isometric session's brief HR spike the way SimRunner's
   evaluator specifically checks for
   (``data_generator.ARIAContext.last_workout_peak_hr`` has no production
   analog at all). It is genuinely impossible for the bridged production
   engine to make that particular mistake, since it never sees the number
   that would cause it — the isometric-misread evaluator check should be
   expected to auto-pass under the bridge, not read as proof the bridge
   caught anything there.
2. Production models chronotype as clock times
   (``typical_sleep_onset``/``typical_wake_time``), not a
   wolf/lion/bear/dolphin archetype label, so the archetype is converted into
   representative onset/wake times using the same per-archetype targets
   ``data_generator.py`` itself already uses (duplicated here rather than
   imported, so this module's only real dependency stays the ``ARIAContext``
   type — not ``data_generator``'s private module-level tables).
"""

from __future__ import annotations

import time
from typing import TYPE_CHECKING, Any

from ..backend_simulator.data_generator import ARIAContext as SimContext
from .aria_engine import ARIAResponse, _references_context

if TYPE_CHECKING:
    from aria_core.aria_engine import ARIAContext as ProdContext

_CHRONO_WAKE_HOUR = {"bear": 7.0, "lion": 6.0, "wolf": 8.5, "dolphin": 6.5}
_CHRONO_SLEEP_HOURS = {"bear": 8.0, "lion": 7.5, "wolf": 7.5, "dolphin": 6.5}


def _clock(hour: float) -> str:
    h = int(hour) % 24
    m = int(round((hour - int(hour)) * 60))
    return f"{h:02d}:{m:02d}"


def _chronotype_times(chrono: str) -> tuple[str | None, str | None]:
    wake = _CHRONO_WAKE_HOUR.get(chrono)
    sleep_hours = _CHRONO_SLEEP_HOURS.get(chrono)
    if wake is None or sleep_hours is None:
        return None, None
    onset = (wake - sleep_hours) % 24
    return _clock(onset), _clock(wake)


def to_production_context(ctx: SimContext) -> "ProdContext":
    """SimRunner's flat ARIAContext -> production's nested ARIAContext.

    Absence is carried over faithfully, not invented: when SimRunner says a
    signal is missing (``has_sleep=False`` etc.), the corresponding
    production field stays ``None`` so production's own
    ``missing_fields``/confidence-ceiling logic sees the same gap SimRunner
    does, instead of a fabricated zero.
    """
    from backend._paths import ensure_lambda_on_path

    ensure_lambda_on_path()
    from aria_core import aria_engine as prod

    t = ctx.today

    sleep_minutes = t.total_sleep_hours * 60.0 if t.total_sleep_hours is not None else None
    has_hrv_week = ctx.hrv_days_available_7d > 0
    hrv_trend_pct = None
    if t.hrv is not None and has_hrv_week and ctx.hrv_7d_avg:
        hrv_trend_pct = round((t.hrv - ctx.hrv_7d_avg) / ctx.hrv_7d_avg * 100.0, 1)

    onset, wake = _chronotype_times(ctx.chronotype)

    return prod.ARIAContext(
        sleep=prod.SleepContext(
            duration_minutes=sleep_minutes,
            deep_minutes=float(t.deep_sleep_minutes) if t.deep_sleep_minutes is not None else None,
            rem_minutes=float(t.rem_sleep_minutes) if t.rem_sleep_minutes is not None else None,
            hrv=float(t.hrv) if t.hrv is not None else None,
            resting_hr=float(t.resting_hr) if t.resting_hr is not None else None,
            nights_available=ctx.sleep_nights_available_7d,
            sleep_debt_7d_hours=ctx.sleep_debt_7d_hours,
            target_hours=ctx.target_sleep_hours,
        ),
        readiness=prod.ReadinessContext(
            hrv_7day_trend=hrv_trend_pct,
            hrv_30day_baseline=ctx.hrv_7d_avg if has_hrv_week else None,
            recovery_score=float(t.readiness_score),
            hrv_days_available=ctx.hrv_days_available_7d,
        ),
        training=prod.TrainingContext(
            last_workout_type=ctx.last_workout_type,
            hours_since_last_workout=float(ctx.days_since_last_workout * 24),
            acwr=t.acwr,
            is_overtrained=ctx.is_overtrained,
        ),
        chronotype=prod.ChronotypeContext(
            typical_sleep_onset=onset,
            typical_wake_time=wake,
        ),
        profile=prod.ProfileContext(
            experience_level=ctx.experience_level,
            coaching_style=ctx.coaching_style,
        ),
    )


def from_production_envelope(
    envelope: dict[str, Any],
    *,
    context: SimContext,
    model_used: str,
    query_type: str,
    model_class: str,
    latency_ms: float,
) -> ARIAResponse:
    """Production's response envelope dict -> SimRunner's typed ARIAResponse.

    ``recommendation`` reads the envelope card's ``action`` key, which only
    ``_recommendation_response`` populates — ``_plan_response``,
    ``_insight_response``, ``_summary_response``, and ``_clarification_response``
    all shape their cards differently and correctly yield ``recommendation=None``
    here, same as several of the stub's own scenarios (sparse_clarify,
    refusal, honest_read) already do.
    """
    prose = str(envelope.get("prose_summary") or envelope.get("message") or "")
    card = envelope.get("card")
    recommendation = card.get("action") if isinstance(card, dict) else None

    confidence = envelope.get("confidence")
    try:
        confidence = float(confidence) if confidence is not None else 0.5
    except (TypeError, ValueError):
        confidence = 0.5
    confidence = max(0.0, min(1.0, confidence))

    return ARIAResponse(
        prose_summary=prose,
        recommendation=str(recommendation) if recommendation else None,
        confidence=confidence,
        used_context=_references_context(prose, context),
        model_used=model_used,
        query_type=query_type,
        latency_ms=round(latency_ms, 1),
        raw={
            "scenario": "production_engine",
            "response_type": envelope.get("response_type"),
            "confidence_reason": envelope.get("confidence_reason"),
        },
        model_class=model_class,
        model_archetype="production",
    )


def run(
    query: str,
    context: SimContext,
    *,
    model_used: str,
    query_type: str,
    model_class: str,
) -> ARIAResponse:
    """Full round trip: SimRunner context -> production's generate_response()
    -> SimRunner ARIAResponse. The one function ARIAEngine._production_response
    calls, so aria_core stays imported only from this module, not from
    aria_engine.py too."""
    prod_ctx = to_production_context(context)
    from aria_core import aria_engine as prod

    started = time.perf_counter()
    envelope = prod.generate_response(query, prod_ctx)
    latency_ms = (time.perf_counter() - started) * 1000.0
    return from_production_envelope(
        envelope,
        context=context,
        model_used=model_used,
        query_type=query_type,
        model_class=model_class,
        latency_ms=latency_ms,
    )
