"""Canonical user model — single builder for every ARIA path.

Collapses the three parallel context builders into one:
  - ARIAContext.from_payload (request body)
  - BodyModel.to_aria_context (biometrics projection)
  - coach_context.gather_user_context (DynamoDB SLEEP#/WORKOUT# session logs)

Not yet wired into any route — this module exists and is now tested in
isolation (see test_aria_user_model.py), but nothing calls it yet. Before
that test coverage existed, the sleep/workout-history path was silently
dead: every Observation() construction was missing required unit/timestamp
arguments, raised, and was swallowed by a broad except, so build_user_model
always fell back to payload-only context whenever real history was present
— fixed, along with a permission-check gap that let life_facts tags leak
into the context even when the caller denied the "lifestyle" domain.

**Update 2026-09-20 — re-scoped after reading routes/coach.py and ai_router.py
closely, not just this module's own prior docstring.** The original plan here
was "swap coach.py's gather_user_context() call for build_user_model()." That
turns out to be the wrong fix, for a reason deeper than "the call sites need
rewriting": routes/coach.py's four handlers don't consume an ARIAContext at
all. They build a prompt for ai_router.AIRouter().route() — a separate,
general multi-model consensus router for open-ended Q&A — using a flat JSON
dict (coach_context.context_to_prompt_block) and deterministic fallback text
that reads structured trend fields (trainingLoad.trend/current/previous,
recoveryTrend.delta/current/previous) ARIAContext.progress doesn't carry
(build_user_model() already collapses trainingLoad to a bare string, which is
lossy for exactly this). /ai/chat and /ai/observe, by contrast, use
aria_engine.ARIAContext + the *interpreter/signal* reasoning system, via
fusion.fuse_turn — which is also more complete than this module (persona
loading, a persisted-snapshot fallback when a turn has no fresh observations,
permission overlay applied once inside the call). Forcing build_user_model()
into either family would mean rebuilding a router it doesn't fit, or
duplicating work fuse_turn already does better.

The real, concrete bug behind "two sources" was narrower and lower-risk to
fix: gather_user_context() only ever reads SLEEP#/WORKOUT# session-log rows,
so a user with real sleep data already flowing through /ai/observe's
METRIC#{type}#{timestamp} stream (and persisted by fusion.save_body_snapshot)
could still be told "you have no sleep logged" by /coach/sleep-insight,
purely because that route never looked at the source that actually has their
data. Fixed directly in coach_context.gather_user_context() (see
_sleep_rows_from_body_snapshot there): when no session-log night exists, it
now falls back to the latest night from the persisted body snapshot for
*display* fields only — never fed into recovery_trend()'s 7-vs-7 comparison,
since that needs a "score" field BodyModel doesn't compute, and defaulting
that to 0 would fabricate a trend instead of honestly saying there isn't
enough history yet. routes/coach.py's sleep-insight handler now reads a new
``hasLoggedSleep`` flag to tell "nothing anywhere" apart from "synced data
exists, just not enough of it yet" and says so accordingly. Because
build_user_model() already calls gather_user_context() internally, it
inherits this fix automatically even though it is still called from nowhere.

This module remains real, tested, and available as the canonical ARIAContext
builder for any *future* consumer that wants payload + SLEEP#/WORKOUT#
history + two-tier memory merged into one ARIAContext — it just isn't the
fix for either of today's two existing consumers, which is why it stays
unwired by design rather than as an open TODO.

Derived values have one definition here — no more weight-trend vs HRV label
drift — for whichever future route ends up calling it.
"""

from __future__ import annotations

from typing import Any

from services import aria_engine
from services.biometrics.body_model import BodyModel
from services.biometrics.classify import _timestamp
from services.biometrics.types import MetricType, Observation, spec
from storage import dynamodb, keys


def _obs(metric: MetricType, value: float, row: dict[str, Any]) -> Observation:
    return Observation(metric, value, spec(metric).unit, _timestamp(row), source="history")


def _observations_from_history(recent_sleep: list[dict[str, Any]], recent_workouts: list[dict[str, Any]]) -> list[Observation]:
    """Coerce DynamoDB history rows into Observations for BodyModel.

    Each Observation requires unit + timestamp (no defaults on those fields —
    a prior version omitted both, so every construction here raised and was
    silently swallowed by the broad except below, meaning this function
    always returned an empty list and build_user_model() never actually
    pulled sleep/workout history into the fused context)."""
    obs: list[Observation] = []
    for row in recent_sleep[:14]:
        try:
            dur = row.get("totalHours")
            if isinstance(dur, (int, float)):
                obs.append(_obs(MetricType.SLEEP_DURATION, float(dur) * 60, row))
            deep = row.get("deepMinutes")
            if isinstance(deep, (int, float)):
                obs.append(_obs(MetricType.SLEEP_DEEP, float(deep), row))
            rem = row.get("remMinutes")
            if isinstance(rem, (int, float)):
                obs.append(_obs(MetricType.SLEEP_REM, float(rem), row))
            awake = row.get("awakeMinutes")
            if isinstance(awake, (int, float)):
                total = float(dur) * 60 if isinstance(dur, (int, float)) else 0
                efficiency = (total - float(awake)) / total if total > 0 else None
                if efficiency is not None:
                    obs.append(_obs(MetricType.SLEEP_EFFICIENCY, float(efficiency), row))
        except Exception:
            continue
    # Workouts contribute load/trend via training context, not biometrics series
    return obs


def build_user_model(
    payload: dict[str, Any] | None = None,
    *,
    user_id: str | None = None,
    permissions: aria_engine.DataPermissions | None = None,
) -> tuple[aria_engine.ARIAContext, aria_engine.DataPermissions]:
    """Single canonical ARIAContext builder.

    Merge order (last wins for scalar leaves, but history is additive):
      1. Stored DynamoDB history (sleep/workouts) → BodyModel → base context
      2. Request payload context (client's live HealthKit snapshot) → overlays
      3. Permissions redaction (applied by caller via apply_permissions, but we
         return perms so caller can do it exactly once)

    If user_id is None, uses payload's user_id or a synthetic anon id.
    """
    payload = payload or {}
    uid = user_id or str(payload.get("user_id") or payload.get("userId") or "anon")
    perms = permissions or aria_engine.DataPermissions.from_payload(payload.get("permissions"))
    # Also check nested context permissions
    if payload.get("context") and isinstance(payload.get("context"), dict):
        # nested perms not supported — use top-level only
        pass

    # 1. History → BodyModel base + robust personal baselines
    body_ctx: aria_engine.ARIAContext | None = None
    try:
        from services.coach_context import gather_user_context  # local import to avoid cycle
        from services.biometrics import statistics as st

        hist = gather_user_context(uid)
        recent_sleep_rows = hist.get("recentSleep") or []
        obs = _observations_from_history(recent_sleep_rows, hist.get("recentWorkouts") or [])
        if obs:
            from services.fusion import _age, _sex_female

            model = BodyModel.from_observations(
                obs, age_years=_age(payload), sex_female=_sex_female(payload)
            )
            body_ctx = model.to_aria_context(perms)
            # Robust baseline from sleep duration history (median ± MAD) for personal band
            sleep_durs = [
                float(r.get("totalHours")) * 60
                for r in recent_sleep_rows
                if isinstance(r.get("totalHours"), (int, float))
            ]
            if len(sleep_durs) >= 7:
                baseline = st.robust_baseline(sleep_durs)
                body_ctx.sleep.baseline_median_minutes = baseline.median
                body_ctx.sleep.baseline_mad_minutes = baseline.mad
                body_ctx.sleep.nights_available = len(sleep_durs)
            # Overlay training/progress from history that BodyModel doesn't carry
            if hist.get("trainingLoad"):
                body_ctx.progress.training_load_trend = str(hist["trainingLoad"])
            if hist.get("recentWorkouts"):
                body_ctx.training.weekly_load_score = len(hist["recentWorkouts"]) * 6  # rough 0-100
    except Exception:
        body_ctx = None

    # 2. Payload → rich context (client live snapshot)
    try:
        payload_ctx = aria_engine.ARIAContext.from_payload(payload)
    except Exception:
        payload_ctx = aria_engine.ARIAContext()

    # 2a. Two-tier memory: active STM + life_facts into lifestyle tags
    try:
        from services.aria_context import CoachContextEngine

        engine = CoachContextEngine()
        # short_term_memories() already filters to active (non-expired) items
        # by default, so no separate is_active() re-check is needed here.
        stm_texts = [m.text for m in engine.short_term_memories(uid)]
        # Active STM texts become lifestyle tags (event-anchored, auto-expiring via ttl)
        if stm_texts and perms.allows("lifestyle"):
            # Lazily ensure merged exists
            target_ctx = body_ctx if body_ctx is not None else payload_ctx
            for t in stm_texts[:6]:
                tag = f"stm:{t[:80]}"
                if tag not in target_ctx.lifestyle.tags:
                    target_ctx.lifestyle.tags.append(tag)
        # Long-term life_facts → lifestyle tags as durable takeaways
        if perms.allows("lifestyle"):
            try:
                long_ctx = engine.get_or_create_context(uid)
                for fact in (long_ctx.life_facts or [])[:8]:
                    tag = f"life:{fact[:80]}"
                    target = body_ctx if body_ctx is not None else payload_ctx
                    if tag not in target.lifestyle.tags:
                        target.lifestyle.tags.append(tag)
            except Exception:
                pass
    except Exception:
        pass

    # 3. Merge: payload wins where it has a value, else keep body_ctx
    if body_ctx is None:
        merged = payload_ctx
    else:
        merged = body_ctx
        # Overlay non-None leaves from payload
        for domain in ("sleep", "readiness", "training", "activity", "chronotype", "body", "nutrition", "profile", "progress", "lifestyle"):
            p_obj = getattr(payload_ctx, domain)
            m_obj = getattr(merged, domain)
            for field_name in vars(p_obj):
                val = getattr(p_obj, field_name)
                if val is not None and (isinstance(val, list) and len(val) > 0 or not isinstance(val, list)):
                    # Only overwrite if payload actually provided something
                    if getattr(m_obj, field_name) is None or field_name in ("tags", "recent_patterns", "goals", "constraints"):
                        setattr(m_obj, field_name, val)
                    elif field_name not in ("tags",):
                        setattr(m_obj, field_name, val)
        # Lifestyle tags are additive (history + live) — already includes STM above via body_ctx
        live_tags = getattr(payload_ctx.lifestyle, "tags", []) or []
        hist_tags = getattr(merged.lifestyle, "tags", []) or []
        merged.lifestyle.tags = list(dict.fromkeys(list(hist_tags) + list(live_tags)))

    return merged, perms
