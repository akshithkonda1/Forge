"""Shared BodyModel + persona hot path for ``/ai/chat`` and ``/ai/observe``.

Law: ingest → canonicalize → personal model → stance → speak.
Python owns truth; the model owns language.

Both routes call ``fuse_turn``. Body-owned biometric domains win over a
stale client ``ARIAContext`` template. Persona stance
(protect / proceed / fuel / clarify) is the action source for the next
session — not a sidecar, and not ``/ai/router`` Bedrock answer-merge.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

from services import aria_engine
from services.biometrics import BodyModel, classify_batch
from services.biometrics.body_model import redact_snapshot
from services.biometrics.types import MetricType

# History depth before a metric is judged against *this person*, not a
# population cutoff. One week of daily samples is the floor for "robust".
MIN_PERSONAL_N = 7

_BODY_DOMAINS = ("sleep", "readiness", "activity", "body", "nutrition")
_CLIENT_KEEP_DOMAINS = (
    "training",
    "chronotype",
    "profile",
    "progress",
    "lifestyle",
    "clinical_data",
)
_DOMAIN_METRICS: dict[str, tuple[MetricType, ...]] = {
    "sleep": (
        MetricType.SLEEP_DURATION,
        MetricType.SLEEP_DEEP,
        MetricType.SLEEP_REM,
        MetricType.SLEEP_LIGHT,
        MetricType.SLEEP_EFFICIENCY,
        MetricType.HRV_SDNN,
        MetricType.RESTING_HEART_RATE,
    ),
    "readiness": (MetricType.HRV_SDNN, MetricType.RESTING_HEART_RATE),
    "activity": (MetricType.STEPS, MetricType.ACTIVE_ENERGY, MetricType.DISTANCE),
    "body": (MetricType.BODY_MASS, MetricType.BODY_FAT, MetricType.LEAN_MASS, MetricType.VO2_MAX),
    "nutrition": (MetricType.DIETARY_ENERGY, MetricType.DIETARY_PROTEIN, MetricType.WATER),
}

# Storage / parse failures around persona I/O. Never a bare Exception that
# gets relabeled as a silent cold-start.
PERSONA_IO_ERRORS = (
    OSError,
    ValueError,
    TypeError,
    KeyError,
    RuntimeError,
    AttributeError,
)


@dataclass
class PersonalBaselines:
    """Robust personal centers from BodyModel. Population cutoffs stay the floor
    until a metric has ``MIN_PERSONAL_N`` observations."""

    sleep_duration_min: float | None = None
    sleep_duration_n: int = 0
    deep_frac: float | None = None
    rem_frac: float | None = None
    efficiency: float | None = None
    sleep_n: int = 0
    hrv: float | None = None
    hrv_n: int = 0
    recovery: float | None = None
    steps: float | None = None
    steps_n: int = 0
    protein_g: float | None = None
    protein_n: int = 0
    robust: bool = False

    def personal(self, metric: str) -> bool:
        n = {
            "sleep_duration": self.sleep_duration_n,
            "sleep": self.sleep_n,
            "hrv": self.hrv_n,
            "steps": self.steps_n,
            "protein": self.protein_n,
        }.get(metric, 0)
        return n >= MIN_PERSONAL_N

    def to_dict(self) -> dict[str, Any]:
        return {
            "sleep_duration_min": self.sleep_duration_min,
            "sleep_duration_n": self.sleep_duration_n,
            "deep_frac": self.deep_frac,
            "rem_frac": self.rem_frac,
            "efficiency": self.efficiency,
            "sleep_n": self.sleep_n,
            "hrv": self.hrv,
            "hrv_n": self.hrv_n,
            "recovery": self.recovery,
            "steps": self.steps,
            "steps_n": self.steps_n,
            "protein_g": self.protein_g,
            "protein_n": self.protein_n,
            "robust": self.robust,
        }

    @classmethod
    def from_dict(cls, raw: dict[str, Any] | None) -> "PersonalBaselines":
        data = raw if isinstance(raw, dict) else {}
        return cls(
            sleep_duration_min=_num(data.get("sleep_duration_min")),
            sleep_duration_n=_int(data.get("sleep_duration_n")),
            deep_frac=_num(data.get("deep_frac")),
            rem_frac=_num(data.get("rem_frac")),
            efficiency=_num(data.get("efficiency")),
            sleep_n=_int(data.get("sleep_n")),
            hrv=_num(data.get("hrv")),
            hrv_n=_int(data.get("hrv_n")),
            recovery=_num(data.get("recovery")),
            steps=_num(data.get("steps")),
            steps_n=_int(data.get("steps_n")),
            protein_g=_num(data.get("protein_g")),
            protein_n=_int(data.get("protein_n")),
            robust=bool(data.get("robust")),
        )


@dataclass
class PersonaLoad:
    state: Any
    status: str
    error: str | None = None


@dataclass
class FusedTurn:
    context: aria_engine.ARIAContext
    snapshot: dict[str, Any] | None
    baselines: PersonalBaselines
    classification: dict[str, Any] | None
    source: str
    observation_count: int
    persona: Any
    persona_status: str
    persona_error: str | None
    owned_domains: list[str]
    restricted: list[str]

    def fusion_sidecar(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "source": self.source,
            "observation_count": self.observation_count,
            "owned_domains": list(self.owned_domains),
            "baseline_kind": "personal" if self.baselines.robust else "population",
            "persona_status": self.persona_status,
            "restricted_domains": list(self.restricted),
        }
        if self.persona_error:
            payload["persona_error"] = self.persona_error
        return payload


def load_persona(user_id: str) -> PersonaLoad:
    """Load durable learner state. Failures are named — never silent cold-start."""
    from services import contextual_learner

    try:
        state = contextual_learner.load(user_id)
    except PERSONA_IO_ERRORS as exc:
        return PersonaLoad(
            contextual_learner.PersonaState(),
            "load_failed",
            f"{exc.__class__.__name__}: {exc}",
        )
    if int(getattr(state, "n", 0) or 0) == 0 and not getattr(state, "last_stance", None):
        return PersonaLoad(state, "cold_start", None)
    return PersonaLoad(state, "loaded", None)


def fuse_turn(
    user_id: str,
    payload: dict[str, Any],
    permissions: aria_engine.DataPermissions,
    *,
    include_stored: bool | None = None,
    persist: bool = True,
    load_learner: bool = True,
) -> FusedTurn:
    """Observe-equivalent BodyModel + overlay + persona load.

    Body-owned biometric domains win over a conflicting client ``ARIAContext``.
    Client keeps training / profile / lifestyle / clinical. A prior observe
    snapshot is loaded when this turn has no fresh observations so chat cannot
    template a stale client bag.
    """
    raw = _collect_samples(user_id, payload, include_stored=include_stored)
    result = classify_batch(raw)
    client_ctx = aria_engine.ARIAContext.from_payload(payload)
    model: BodyModel | None = None
    snapshot_dict: dict[str, Any] | None = None
    baselines = PersonalBaselines()
    owned: list[str] = []
    source = "payload"
    observation_count = 0
    body_ctx: aria_engine.ARIAContext | None = None

    if result.observations:
        model = BodyModel.from_observations(result.observations, age_years=_age(payload))
        snap = model.snapshot()
        snapshot_dict = snap.to_dict()
        baselines = baselines_from_model(model)
        owned = owned_domains(model)
        # Persist the un-redacted projection so a later grant can still read it.
        # This turn's response is permission-filtered after overlay.
        body_ctx = model.to_aria_context(aria_engine.DataPermissions.allow_all())
        source = "body_model"
        observation_count = snap.observation_count
        if persist and user_id:
            save_body_snapshot(user_id, snapshot_dict, baselines, body_ctx, owned)
    else:
        stored = load_body_snapshot(user_id) if user_id else None
        if stored is not None:
            snapshot_dict = stored.get("snapshot") if isinstance(stored.get("snapshot"), dict) else None
            baselines = PersonalBaselines.from_dict(stored.get("baselines"))
            owned = [d for d in (stored.get("owned_domains") or []) if d in _BODY_DOMAINS]
            body_ctx = context_from_asdict(stored.get("aria_context"))
            source = "persisted"
            observation_count = _int(stored.get("observation_count"))

    context = overlay_context(client_ctx, body_ctx, owned)
    context, restricted = aria_engine.apply_permissions(context, permissions)
    if snapshot_dict is not None:
        snapshot_dict = redact_snapshot(dict(snapshot_dict), permissions)

    persona = None
    persona_status = "skipped"
    persona_error = None
    if load_learner:
        loaded = load_persona(user_id)
        persona = loaded.state
        persona_status = loaded.status
        persona_error = loaded.error

    classification = None
    if result.observations or result.rejects:
        classification = {
            **result.counts,
            "rejects": [r.to_dict() for r in result.rejects][:25],
        }

    return FusedTurn(
        context=context,
        snapshot=snapshot_dict,
        baselines=baselines,
        classification=classification,
        source=source,
        observation_count=observation_count,
        persona=persona,
        persona_status=persona_status,
        persona_error=persona_error,
        owned_domains=owned,
        restricted=restricted,
    )


def baselines_from_model(model: BodyModel) -> PersonalBaselines:
    from services.biometrics import statistics as st

    sleep_vals = model.values(MetricType.SLEEP_DURATION)
    deep_vals = model.values(MetricType.SLEEP_DEEP)
    rem_vals = model.values(MetricType.SLEEP_REM)
    eff_vals = model.values(MetricType.SLEEP_EFFICIENCY)
    hrv_vals = model.values(MetricType.HRV_SDNN)
    step_vals = model.values(MetricType.STEPS)
    protein_vals = model.values(MetricType.DIETARY_PROTEIN)

    sleep_n = len(sleep_vals)
    sleep_base = st.robust_baseline(sleep_vals).median if sleep_vals else None
    deep_frac = None
    rem_frac = None
    if deep_vals and sleep_vals and st.robust_baseline(sleep_vals).median > 0:
        deep_frac = st.robust_baseline(deep_vals).median / st.robust_baseline(sleep_vals).median
    if rem_vals and sleep_vals and st.robust_baseline(sleep_vals).median > 0:
        rem_frac = st.robust_baseline(rem_vals).median / st.robust_baseline(sleep_vals).median
    recovery = model._recovery_estimate().value
    robust = any(
        n >= MIN_PERSONAL_N
        for n in (sleep_n, len(hrv_vals), len(step_vals), len(protein_vals))
    )
    return PersonalBaselines(
        sleep_duration_min=sleep_base,
        sleep_duration_n=sleep_n,
        deep_frac=deep_frac,
        rem_frac=rem_frac,
        efficiency=st.robust_baseline(eff_vals).median if eff_vals else None,
        sleep_n=max(sleep_n, len(deep_vals), len(rem_vals)),
        hrv=st.robust_baseline(hrv_vals).median if hrv_vals else None,
        hrv_n=len(hrv_vals),
        recovery=recovery,
        steps=st.robust_baseline(step_vals).median if step_vals else None,
        steps_n=len(step_vals),
        protein_g=st.robust_baseline(protein_vals).median if protein_vals else None,
        protein_n=len(protein_vals),
        robust=robust,
    )


def owned_domains(model: BodyModel) -> list[str]:
    owned: list[str] = []
    for domain, metrics in _DOMAIN_METRICS.items():
        if any(model.series.get(metric) for metric in metrics):
            owned.append(domain)
    return owned


def overlay_context(
    client: aria_engine.ARIAContext,
    body: aria_engine.ARIAContext | None,
    owned: list[str],
) -> aria_engine.ARIAContext:
    """BodyModel owns ingested biometric domains; the client keeps the rest."""
    if body is None or not owned:
        return client
    merged = aria_engine.ARIAContext(
        timestamp=client.timestamp or body.timestamp,
        **{name: getattr(client, name) for name in aria_engine.ALL_DOMAINS},
    )
    merged.medication_layer = client.medication_layer
    for domain in owned:
        if domain in _BODY_DOMAINS:
            setattr(merged, domain, getattr(body, domain))
    # Client-only domains are already copied; keep medication unless clinical
    # was body-owned (it never is).
    return merged


def context_from_asdict(raw: Any) -> aria_engine.ARIAContext | None:
    if not isinstance(raw, dict):
        return None
    sleep = raw.get("sleep") if isinstance(raw.get("sleep"), dict) else {}
    readiness = raw.get("readiness") if isinstance(raw.get("readiness"), dict) else {}
    activity = raw.get("activity") if isinstance(raw.get("activity"), dict) else {}
    body = raw.get("body") if isinstance(raw.get("body"), dict) else {}
    nutrition = raw.get("nutrition") if isinstance(raw.get("nutrition"), dict) else {}
    return aria_engine.ARIAContext(
        timestamp=str(raw.get("timestamp") or ""),
        sleep=aria_engine.SleepContext(
            duration_minutes=_num(sleep.get("duration_minutes")),
            efficiency=_num(sleep.get("efficiency")),
            rem_minutes=_num(sleep.get("rem_minutes")),
            deep_minutes=_num(sleep.get("deep_minutes")),
            hrv=_num(sleep.get("hrv")),
            resting_hr=_num(sleep.get("resting_hr")),
            nights_available=_int_or_none(sleep.get("nights_available")),
        ),
        readiness=aria_engine.ReadinessContext(
            hrv_7day_trend=_num(readiness.get("hrv_7day_trend")),
            hrv_30day_baseline=_num(readiness.get("hrv_30day_baseline")),
            recovery_score=_num(readiness.get("recovery_score")),
            hrv_days_available=_int_or_none(readiness.get("hrv_days_available")),
        ),
        activity=aria_engine.ActivityContext(
            steps_3day_avg=_num(activity.get("steps_3day_avg")),
            active_calories_3day_avg=_num(activity.get("active_calories_3day_avg")),
        ),
        body=aria_engine.BodyContext(
            weight_kg=_num(body.get("weight_kg")),
            weight_trend_kg=_num(body.get("weight_trend_kg")),
            body_fat_pct=_num(body.get("body_fat_pct")),
            vo2_max=_num(body.get("vo2_max")),
        ),
        nutrition=aria_engine.NutritionContext(
            calories_in_3day_avg=_num(nutrition.get("calories_in_3day_avg")),
            protein_g_3day_avg=_num(nutrition.get("protein_g_3day_avg")),
            hydration_ml_3day_avg=_num(nutrition.get("hydration_ml_3day_avg")),
            calorie_target=_num(nutrition.get("calorie_target")),
        ),
    )


def save_body_snapshot(
    user_id: str,
    snapshot: dict[str, Any],
    baselines: PersonalBaselines,
    context: aria_engine.ARIAContext,
    owned: list[str],
) -> None:
    from storage import dynamodb, keys

    biometric = {domain: asdict(getattr(context, domain)) for domain in _BODY_DOMAINS}
    biometric["timestamp"] = context.timestamp
    dynamodb.put_item(
        {
            **keys.aria_body_snapshot_key(user_id),
            "user_id": user_id,
            "generated_at": snapshot.get("generated_at"),
            "observation_count": snapshot.get("observation_count"),
            "sources": snapshot.get("sources") or [],
            "snapshot": snapshot,
            "baselines": baselines.to_dict(),
            "aria_context": biometric,
            "owned_domains": list(owned),
        }
    )


def load_body_snapshot(user_id: str) -> dict[str, Any] | None:
    from storage import dynamodb, keys

    uid = (user_id or "").strip()
    if not uid:
        return None
    item = dynamodb.get_item(**keys.aria_body_snapshot_key(uid))
    return item if isinstance(item, dict) else None


def stance_for_plan(
    brief: Any,
    ctx: aria_engine.ARIAContext,
    baselines: PersonalBaselines | None = None,
) -> str:
    """Persona stance is the plan. A personal-model deficit can only protect.

    This is not ``/ai/router`` answer-merge: no votes, no agreement, no Bedrock.
    """
    from services import contextual_learner

    stance = str(getattr(brief, "stance", "") or "")
    if stance not in contextual_learner.STANCES:
        stance = "proceed"
    if _personal_deficit_protect(ctx, baselines):
        return "protect"
    return stance


def session_readiness_for(stance: str, recovery: float | None) -> int | None:
    """Protect/fuel change the number the session picker sees."""
    if stance == "protect":
        return 40
    if stance == "fuel":
        return int(min(recovery, 65)) if recovery is not None else 60
    if recovery is None:
        return None
    return int(recovery)


def _personal_deficit_protect(
    ctx: aria_engine.ARIAContext, baselines: PersonalBaselines | None
) -> bool:
    """Tonight well below *this person's* usual — not a population cutoff."""
    if baselines is None or not baselines.robust:
        return False
    if baselines.personal("sleep_duration") and ctx.sleep.duration_minutes is not None:
        usual = baselines.sleep_duration_min or 0.0
        if usual > 0 and ctx.sleep.duration_minutes < 0.85 * usual:
            return True
    if baselines.personal("hrv") and ctx.readiness.hrv_7day_trend is not None:
        if ctx.readiness.hrv_7day_trend <= -8:
            return True
    return False


def _collect_samples(
    user_id: str, payload: dict[str, Any], *, include_stored: bool | None
) -> list[Any]:
    incoming = payload.get("samples")
    raw: list[Any] = list(incoming) if isinstance(incoming, list) else []
    if len(raw) > 500:
        raw = raw[:500]
    flag = payload.get("include_stored") if include_stored is None else include_stored
    if flag is None:
        flag = True
    if flag and user_id:
        try:
            from storage import dynamodb, keys

            raw.extend(dynamodb.query_prefix(keys.user_pk(user_id), "METRIC#"))
        except PERSONA_IO_ERRORS:
            pass
    return raw


def _age(payload: dict[str, Any]) -> float | None:
    raw = payload.get("age_years", payload.get("age"))
    try:
        return float(raw) if raw is not None else None
    except (TypeError, ValueError):
        return None


def _num(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _int(value: Any) -> int:
    if value is None or isinstance(value, bool):
        return 0
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _int_or_none(value: Any) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None
