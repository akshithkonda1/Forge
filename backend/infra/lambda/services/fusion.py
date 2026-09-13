"""One ingested truth for a coaching turn.

``/ai/observe`` already classifies samples into a ``BodyModel`` and projects
that onto ``ARIAContext``. ``/ai/chat`` used to template ``generate_response``
off the client bag — a second, stale picture of the same body — and observe
coached without a persona. This module is the shared hot path both routes
must call:

    samples + stored metrics + last snapshot
        → BodyModel
        → personal baselines
        → overlay client-only domains (training, profile, lifestyle, …)
        → persona stance
        → reconciled coaching action

Generation packages that action. This is **not** the Bedrock ``/ai/router``
path: that router merges multi-model *answers* and stays kill-switch gated.
Coaching reconcile here is BodyModel + persona, deterministic, no AWS.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
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

# Router-style safest common ground when BodyModel and persona disagree.
# protect is the conservative call; proceed is the most aggressive.
_SAFETY_RANK = {"protect": 0, "fuel": 1, "clarify": 2, "proceed": 3}


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
class CoachingAction:
    """The plan the coach ships this turn. Stance is the source, not a sidecar."""

    stance: str
    intensity: str
    action: str
    timing: str
    rationale: str
    expected_effect: str
    suggested_actions: list[str] = field(default_factory=list)
    session_readiness: int | None = None
    votes: dict[str, str] = field(default_factory=dict)
    agreement: str = "agree"
    baseline_kind: str = "population"

    def to_dict(self) -> dict[str, Any]:
        return {
            "stance": self.stance,
            "intensity": self.intensity,
            "action": self.action,
            "timing": self.timing,
            "rationale": self.rationale,
            "expected_effect": self.expected_effect,
            "suggested_actions": list(self.suggested_actions),
            "session_readiness": self.session_readiness,
            "votes": dict(self.votes),
            "agreement": self.agreement,
            "baseline_kind": self.baseline_kind,
        }


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

    def fusion_sidecar(self, plan: CoachingAction | None = None) -> dict[str, Any]:
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
        if plan is not None:
            payload["plan"] = plan.to_dict()
            payload["stance"] = plan.stance
            payload["agreement"] = plan.agreement
        return payload


def load_persona(user_id: str) -> PersonaLoad:
    """Load durable learner state. Failures are named — never silent cold-start."""
    from services import contextual_learner

    try:
        state = contextual_learner.load(user_id)
    except Exception as exc:  # noqa: BLE001 — caller must see the class of failure
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


def reconcile_action(
    message: str,
    ctx: aria_engine.ARIAContext,
    signals: list[Any],
    brief: Any,
    baselines: PersonalBaselines | None,
    restricted: list[str],
    *,
    recovery_score: float | None = None,
) -> CoachingAction:
    """Deterministic BodyModel + persona reconcile.

    Same maturity idea as the router finalizer — keep what agrees, and on
    disagreement take the safest common-ground call — but the votes are
    biometric + learned stance, not Bedrock answers. No AWS.
    """
    from services import contextual_learner

    stance_persona = str(getattr(brief, "stance", "") or "")
    if stance_persona not in contextual_learner.STANCES:
        stance_persona = "proceed"

    sleep_first = _sleep_first(ctx, restricted)
    body_vote = _body_vote(ctx, signals, baselines, sleep_first)
    baseline_vote = _baseline_vote(ctx, baselines)
    votes = {"body": body_vote, "persona": stance_persona}
    if baseline_vote:
        votes["baseline"] = baseline_vote

    training_ask = _is_training_ask(message)
    stance, agreement = _pick_stance(votes, training_ask=training_ask)
    baseline_kind = "personal" if baselines is not None and baselines.robust else "population"
    recovery = recovery_score
    if recovery is None:
        raw = ctx.readiness.recovery_score
        recovery = float(raw) if isinstance(raw, (int, float)) else None

    intensity, action, timing, rationale, expected, suggestions, session_readiness = _plan_for_stance(
        stance,
        ctx,
        signals,
        brief,
        sleep_first=sleep_first,
        recovery=recovery,
    )
    return CoachingAction(
        stance=stance,
        intensity=intensity,
        action=action,
        timing=timing,
        rationale=rationale,
        expected_effect=expected,
        suggested_actions=suggestions,
        session_readiness=session_readiness,
        votes=votes,
        agreement=agreement,
        baseline_kind=baseline_kind,
    )


def _pick_stance(votes: dict[str, str], *, training_ask: bool) -> tuple[str, str]:
    unique = {v for v in votes.values() if v in _SAFETY_RANK}
    if not unique:
        return "proceed", "agree"
    if len(unique) == 1:
        return unique.pop(), "agree"
    if "protect" in unique:
        return "protect", "safest_common_ground"
    if "fuel" in unique:
        return "fuel", "safest_common_ground"
    if training_ask and "proceed" in unique:
        return "proceed", "ask_wins_over_clarify"
    return min(unique, key=lambda s: _SAFETY_RANK[s]), "safest_common_ground"


def _sleep_first(ctx: aria_engine.ARIAContext, restricted: list[str]) -> bool:
    hrv_falling = ctx.readiness.hrv_7day_trend is not None and ctx.readiness.hrv_7day_trend <= -8
    sleep_debt_h = 0.0
    if ctx.sleep.duration_minutes is not None:
        sleep_debt_h = max(0.0, 8 - (ctx.sleep.duration_minutes or 0) / 60.0)
    return bool(hrv_falling and sleep_debt_h > 2 and "sleep" not in restricted)


def _body_vote(
    ctx: aria_engine.ARIAContext,
    signals: list[Any],
    baselines: PersonalBaselines | None,
    sleep_first: bool,
) -> str:
    if sleep_first:
        return "protect"
    high_neg = [
        s
        for s in signals
        if getattr(s, "direction", None) == "negative" and getattr(s, "priority", "") == "high"
    ]
    if high_neg:
        if any(getattr(s, "domain", "") == "nutrition" for s in high_neg):
            return "fuel"
        return "protect"
    if any(getattr(s, "domain", "") == "nutrition" and getattr(s, "direction", None) == "negative" for s in signals):
        return "fuel"
    if any(getattr(s, "direction", None) == "positive" for s in signals):
        return "proceed"
    if not signals and not ctx.has_sleep and ctx.readiness.recovery_score is None:
        return "clarify"
    return "proceed"


def _baseline_vote(ctx: aria_engine.ARIAContext, baselines: PersonalBaselines | None) -> str | None:
    """Protect when tonight is well below *this person's* usual, not the population floor."""
    if baselines is None or not baselines.robust:
        return None
    if baselines.personal("sleep_duration") and ctx.sleep.duration_minutes is not None:
        usual = baselines.sleep_duration_min or 0.0
        if usual > 0 and ctx.sleep.duration_minutes < 0.85 * usual:
            return "protect"
    if baselines.personal("hrv") and ctx.readiness.hrv_7day_trend is not None:
        if ctx.readiness.hrv_7day_trend <= -8:
            return "protect"
    return None


def _plan_for_stance(
    stance: str,
    ctx: aria_engine.ARIAContext,
    signals: list[Any],
    brief: Any,
    *,
    sleep_first: bool,
    recovery: float | None,
) -> tuple[str, str, str, str, str, list[str], int | None]:
    lead = signals[0] if signals else None
    # one_next_move is written for the *persona* stance. After reconcile it
    # may disagree — never let a proceed sentence ship on a protect plan.
    learned_move = ""
    if str(getattr(brief, "stance", "") or "") == stance:
        learned_move = str(getattr(brief, "one_next_move", "") or "").strip()
    slot = str(getattr(brief, "preferred_slot", "") or "").strip()
    onset = ctx.chronotype.typical_sleep_onset

    if sleep_first:
        timing = "Protect sleep tonight; reassess training after HRV recovers"
        if onset:
            timing = f"{timing}; protect your {onset} wind-down tonight"
        return (
            "low",
            "Sleep first — protect tonight's wind-down before training volume",
            timing,
            f"HRV {ctx.readiness.hrv_7day_trend:.0f}% + sleep debt — sleep before load",
            "Prioritizing sleep should pull HRV back toward baseline within 24-48 h",
            ["Protect tonight's sleep", "Show recovery plan", "Swap to Zone 2"],
            40,
        )

    if stance == "protect":
        timing = "Fit a shorter session around the day you already have"
        if onset:
            timing = f"{timing}; protect your {onset} wind-down tonight"
        action = learned_move or "Protect load — shorter session or mobility, not a hard push"
        return (
            "low",
            action,
            timing,
            lead.interpretation if lead else "signals plus how you work say protect load",
            "Protecting today should pull readiness back toward your usual within 24-48 h",
            ["Protect tonight's sleep", "Show recovery plan", "Swap to Zone 2"],
            40,
        )

    if stance == "fuel":
        action = learned_move or "Protein and water with the next meal, then train inside the day you have"
        session_r = int(min(recovery, 65)) if recovery is not None else 60
        return (
            "moderate",
            action,
            "Eat first, then your normal training window",
            lead.interpretation if lead else "fueling is the constraint on today's session",
            "Hitting protein and water first keeps the session from digging a hole",
            ["Log the next meal", "Today's workout", "Check hydration"],
            session_r,
        )

    if stance == "clarify":
        action = learned_move or "Best-effort read from what I have, then the one missing signal"
        return (
            "ask",
            action,
            "Once that signal lands I can lock today's call",
            "usable picture is still thin",
            "One missing signal would change the call",
            ["Sync HealthKit", "Tell ARIA about last night", "Today's workout"],
            int(recovery) if recovery is not None else None,
        )

    # proceed
    window = f"in the {slot}" if slot else "in your usual window"
    if lead and getattr(lead, "direction", None) == "positive":
        action = learned_move or "Spend the readiness on one quality session"
        return (
            "high",
            action,
            f"Train {window} while readiness is high",
            lead.interpretation,
            "You can absorb a hard stimulus today without digging a recovery hole",
            ["Build a hard session", "Set a PR target", "Review readiness"],
            int(recovery) if recovery is not None else None,
        )
    action = learned_move or "Train at moderate intensity with controlled progressive overload"
    return (
        "moderate",
        action,
        f"Your normal training window works today — {window}" if slot else "Your normal training window works today",
        lead.interpretation if lead else "your signals are mid-band",
        "Steady stimulus keeps adaptation moving without overreaching",
        ["Today's workout", "Tune intensity", "Check sleep trend"],
        int(recovery) if recovery is not None else None,
    )


def _is_training_ask(message: str) -> bool:
    try:
        from services import body_library

        return body_library.is_training_ask(message)
    except Exception:
        text = (message or "").lower()
        return any(n in text for n in ("train", "workout", "session", "should i"))


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
        except Exception:
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
