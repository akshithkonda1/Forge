"""Canonical user model — single builder for every ARIA path.

Collapses the three parallel context builders into one:
  - ARIAContext.from_payload (request body)
  - BodyModel.to_aria_context (biometrics projection)
  - coach_context.gather_user_context (DynamoDB history)

Every route (/ai/chat, /ai/observe, coach/*) should call build_user_model().
Derived values have one definition — no more weight-trend vs HRV label drift.
"""

from __future__ import annotations

from typing import Any

from services import aria_engine
from services.biometrics.body_model import BodyModel
from services.biometrics.types import MetricType, Observation, utcnow
from storage import dynamodb, keys


def _observations_from_history(recent_sleep: list[dict[str, Any]], recent_workouts: list[dict[str, Any]]) -> list[Observation]:
    """Coerce DynamoDB history rows into Observations for BodyModel."""
    obs: list[Observation] = []
    for row in recent_sleep[:14]:
        try:
            dur = row.get("totalHours")
            if isinstance(dur, (int, float)):
                obs.append(Observation(MetricType.SLEEP_DURATION, float(dur) * 60, source="history"))
            deep = row.get("deepMinutes")
            if isinstance(deep, (int, float)):
                obs.append(Observation(MetricType.SLEEP_DEEP, float(deep), source="history"))
            rem = row.get("remMinutes")
            if isinstance(rem, (int, float)):
                obs.append(Observation(MetricType.SLEEP_REM, float(rem), source="history"))
            awake = row.get("awakeMinutes")
            if isinstance(awake, (int, float)):
                total = float(dur) * 60 if isinstance(dur, (int, float)) else 0
                efficiency = (total - float(awake)) / total if total > 0 else None
                if efficiency is not None:
                    obs.append(Observation(MetricType.SLEEP_EFFICIENCY, float(efficiency), source="history"))
            score = row.get("score")
            if isinstance(score, (int, float)):
                obs.append(Observation(MetricType.SLEEP_REM, float(score), source="history"))  # proxy, not used for sleep calc
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
            model = BodyModel.from_observations(obs)
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
        stm = engine.short_term_memories(uid)
        stm_texts = [m.text for m in stm if m.is_active(engine._utcnow() if hasattr(engine, "_utcnow") else __import__("datetime").datetime.now(__import__("datetime").timezone.utc))]  # type: ignore
        # Active STM texts become lifestyle tags (event-anchored, auto-expiring via ttl)
        if stm_texts and perms.allows("lifestyle"):
            # Lazily ensure merged exists
            target_ctx = body_ctx if body_ctx is not None else payload_ctx
            for t in stm_texts[:6]:
                tag = f"stm:{t[:80]}"
                if tag not in target_ctx.lifestyle.tags:
                    target_ctx.lifestyle.tags.append(tag)
        # Long-term life_facts → lifestyle tags as durable takeaways
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
