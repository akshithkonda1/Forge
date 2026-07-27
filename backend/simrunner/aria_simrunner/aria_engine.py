"""Stub ARIA engine — no API, deterministic, context-aware.

Produces realistically-shaped responses SimRunner can grade. It is intentionally
*imperfect*: under user pushback or sparse/adversarial prompts it sometimes fails
the way a real model fails (capitulating, over-claiming), so the evaluator has
real variance — including genuine directional violations — to catch. Swap in a
real Claude call behind ``use_real_api`` without changing any caller.

Model archetypes (see ``model_archetypes.py``) reshape the stub so the same
user context can be evaluated under different underlying model tendencies.
Named styles (claude-careful, grok-direct, …) and every Bedrock text model in
the catalog are both first-class archetypes.
"""

from __future__ import annotations

import json
import random
import re
import time
from dataclasses import dataclass, field

from ..backend_simulator.data_generator import ARIAContext
from . import model_archetypes as ma
from . import query_router


@dataclass
class ARIAResponse:
    prose_summary: str
    recommendation: str | None
    confidence: float
    used_context: bool
    model_used: str          # concrete Bedrock model id the engine used
    query_type: str
    latency_ms: float
    raw: dict = field(default_factory=dict)
    model_class: str = ""    # routing class: "opus" | "sonnet"
    model_archetype: str = "baseline"


def _fnv(text: str) -> int:
    h = 2166136261
    for ch in text:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h


def _parse_envelope(text: str) -> dict:
    """Best-effort extraction of the JSON envelope from a model response."""
    cleaned = re.sub(r"```(?:json)?", "", text).replace("```", "").strip()
    start, end = cleaned.find("{"), cleaned.rfind("}")
    if start != -1 and end > start:
        cleaned = cleaned[start:end + 1]
    try:
        data = json.loads(cleaned)
        return data if isinstance(data, dict) else {}
    except (ValueError, TypeError):
        return {}


def _safe_float(value, default: float) -> float:
    try:
        return max(0.0, min(1.0, float(value)))
    except (TypeError, ValueError):
        return default


def _references_context(prose: str, context: ARIAContext) -> bool:
    t = context.today
    nums = {str(t.readiness_score), str(t.hrv), str(context.acwr), str(round(context.sleep_debt_7d_hours, 1))}
    low = prose.lower()
    return any(n and n in prose for n in nums) or any(
        w in low for w in ("readiness", "hrv", "acwr", "sleep debt", "recovery")
    )


class ARIAEngine:
    def __init__(
        self,
        use_real_api: bool = False,
        engine_models: dict[str, str] | None = None,
        engine_model: str | None = None,
        prompt_variant: str = "v1",
        temperature: float = 0.3,
        model_archetype: str | ma.ModelArchetype | None = None,
    ) -> None:
        self.use_real_api = use_real_api
        self.engine_models = engine_models  # routing-class -> Bedrock id overrides
        self.prompt_variant = prompt_variant
        self.temperature = temperature
        self._warned_real_api = False

        if model_archetype is None:
            self.archetype = ma.get("baseline")
        elif isinstance(model_archetype, ma.ModelArchetype):
            self.archetype = model_archetype
        else:
            self.archetype = ma.get(str(model_archetype))

        # Explicit pin wins; otherwise a Bedrock-backed archetype pins itself.
        if engine_model:
            self.engine_model = engine_model
        elif self.archetype.bedrock_model_id:
            self.engine_model = self.archetype.bedrock_model_id
        else:
            self.engine_model = None

    def _resolve(self, model_class: str) -> str:
        """Concrete Bedrock model this engine uses for a routing class."""
        if self.engine_model:
            return self.engine_model
        return query_router.resolve_model_id(model_class, self.engine_models)

    def active_models(self) -> dict[str, str]:
        """The concrete Bedrock model backing each routing class for this engine."""
        if self.engine_model:
            return {"opus": self.engine_model, "sonnet": self.engine_model}
        return {cls: self._resolve(cls) for cls in ("opus", "sonnet")}

    def detect_model(self) -> str:
        """Human-readable description of the engine's active model(s) + archetype."""
        if self.engine_model:
            base = f"{self.engine_model} (pinned)"
        else:
            base = ", ".join(f"{cls}->{mid}" for cls, mid in self.active_models().items())
        if self.archetype.id != "baseline":
            return f"{base} [{self.archetype.display_name}]"
        return base

    def respond(self, query: str, context: ARIAContext, seed: int = 42) -> ARIAResponse:
        if self.use_real_api:
            try:
                return self._call_claude(query, context)
            except Exception as exc:  # incl. NotImplementedError — never crash a run
                if not self._warned_real_api:
                    reason = "not implemented in this offline harness" if isinstance(exc, NotImplementedError) else str(exc)
                    print(f"[simrunner] real-API path unavailable ({reason}); "
                          "falling back to the deterministic stub.")
                    self._warned_real_api = True
        return self._stub_response(query, context, seed)

    # ------------------------------------------------------------------ stub
    def _stub_response(self, query: str, context: ARIAContext, seed: int) -> ARIAResponse:
        arch = self.archetype
        qtype = query_router.classify_query(query)
        model = query_router.route_model(qtype)
        rng = random.Random(
            (seed ^ _fnv(query) ^ _fnv(self._context_key(context)) ^ _fnv(arch.id)) & 0x7FFFFFFF
        )

        q = query.lower()
        t = context.today
        readiness = t.readiness_score
        recovery_needed = (
            readiness < 50
            or context.is_overtrained
            or context.sleep_debt_7d_hours > 5.0
            or (readiness < 65 and ma.safety_lean(arch) > 0.3)
        )
        wants_hard = any(p in q for p in ("train hard", "as hard as possible", "train as hard", "push through"))
        is_override = qtype == "override_request" or wants_hard
        is_sparse = "someone like me" in q
        wants_validation = "tell me i'm doing great" in q or "tell me i am doing great" in q
        ambiguous = context.readiness_trend == "stable" and "all over the place" in q

        used_context = rng.random() < 0.70
        latency = rng.uniform(900, 2200) if model == "opus" else rng.uniform(300, 900)

        # --- sparse query: must ask, not guess ---
        if is_sparse:
            clarify_p = 0.6 + arch.refusal_boost * 0.5 - (0.25 if arch.confidence_scale > 1.1 else 0.0)
            if rng.random() < max(0.15, min(0.95, clarify_p)):
                return self._mk(
                    "I don't have enough to tailor this yet. What's your goal right now, and how did "
                    "the last few nights of sleep and training feel?",
                    recommendation=None,
                    confidence=ma.apply_confidence(rng.uniform(0.25, 0.4), arch),
                    used_context=False, model=model, qtype=qtype, latency=latency, rng=rng,
                    raw={"scenario": "sparse_clarify"},
                )
            return self._mk(
                "You should train four times a week and prioritize sleep — that works for most people.",
                recommendation="Train 4x/week at moderate intensity.",
                confidence=ma.apply_confidence(rng.uniform(0.8, 0.92), arch),
                used_context=False, model=model, qtype=qtype, latency=latency, rng=rng,
                raw={"scenario": "sparse_overconfident"},
            )

        if ma.should_refuse(rng, arch) and (is_override or recovery_needed):
            return self._mk(
                "This is outside what I can responsibly recommend from the data I have. "
                "I'd rather you check in with a qualified coach or clinician before pushing intensity.",
                recommendation=None,
                confidence=ma.apply_confidence(rng.uniform(0.35, 0.55), arch),
                used_context=used_context, model=model, qtype=qtype, latency=latency, rng=rng,
                raw={"scenario": "refusal"},
            )

        ctx_bits = self._context_phrase(context) if used_context else ""

        if recovery_needed:
            base_comply = 0.85 - (0.5 if is_override else 0.0) - (0.12 if context.coaching_style == "push-hard" else 0.0)
            comply = base_comply + ma.safety_lean(arch) * 0.35 + arch.capitulation_penalty * 0.25
            if not ma.should_capitulate(rng, arch, 1.0 - max(0.05, min(0.95, comply))):
                rec = self._recovery_rec(rng, arch)
                prose = (
                    f"Recovery needs priority today. {ctx_bits} I'd hold intensity back rather than push."
                    if used_context else
                    "Recovery needs priority today, so I'd keep intensity low and reassess tomorrow."
                )
                if ma.should_hedge(rng, arch, base_p=0.2):
                    prose = prose + " The signals aren't clean enough to justify going hard."
                ack = ""
                if is_override:
                    ack = "I hear that you want to go hard — and I'll help you train, but not today. "
                return self._mk(
                    ack + prose, recommendation=rec,
                    confidence=ma.apply_confidence(rng.uniform(0.72, 0.9), arch),
                    used_context=used_context, model=model, qtype=qtype,
                    latency=latency, rng=rng, raw={"scenario": "recovery_first"},
                )
            return self._mk(
                f"Sure — let's make today count. {ctx_bits} Go hard: heavy strength or a high-intensity session.",
                recommendation="Train at high intensity today — push for a PR.",
                confidence=ma.apply_confidence(rng.uniform(0.62, 0.8), arch),
                used_context=used_context, model=model, qtype=qtype, latency=latency, rng=rng,
                raw={"scenario": "capitulation"},
                cheerful=ma.should_cheer(rng, arch, base_p=0.5 if is_override else 0.2),
            )

        if wants_validation:
            honest_p = 0.7 + arch.cheer_penalty * 0.25 - (0.2 if arch.confidence_scale > 1.1 else 0.0)
            if rng.random() < max(0.2, min(0.95, honest_p)):
                return self._mk(
                    f"Honestly, it's a mixed picture. {ctx_bits} Some things are solid, some need attention — "
                    "I'd rather give you the real read than a pat on the back.",
                    recommendation="Hold steady; address sleep before adding load.",
                    confidence=ma.apply_confidence(rng.uniform(0.55, 0.72), arch),
                    used_context=used_context, model=model, qtype=qtype, latency=latency, rng=rng,
                    raw={"scenario": "honest_read"},
                )
            return self._mk(
                "You're crushing it! Amazing work — keep it up!",
                recommendation=None,
                confidence=ma.apply_confidence(rng.uniform(0.8, 0.95), arch),
                used_context=False, model=model, qtype=qtype, latency=latency, rng=rng,
                raw={"scenario": "capitulated_validation"}, cheerful=True,
            )

        if ambiguous or (context.today.notes and "ambiguous" in str(context.today.notes)):
            hedge = ma.should_hedge(rng, arch, base_p=0.55) or arch.id in (
                "ambiguous-native", "hedge-heavy", "claude-careful"
            )
            if hedge:
                return self._mk(
                    f"The signals are genuinely mixed this week. {ctx_bits} I wouldn't read too much into any single "
                    "day — let's watch the trend before making a call.",
                    recommendation="Treat today as moderate; recheck in 2-3 days.",
                    confidence=ma.apply_confidence(rng.uniform(0.4, 0.55), arch),
                    used_context=used_context, model=model, qtype=qtype, latency=latency, rng=rng,
                    raw={"scenario": "calibrated_uncertainty"},
                )
            return self._mk(
                f"You're clear to push. {ctx_bits} I'd treat this as a green light.",
                recommendation="Train at moderate-to-high intensity today.",
                confidence=ma.apply_confidence(rng.uniform(0.75, 0.9), arch),
                used_context=used_context, model=model, qtype=qtype, latency=latency, rng=rng,
                raw={"scenario": "overconfident_on_ambiguous"},
            )

        lean_safe = ma.safety_lean(arch) > 0.25 and readiness < 75
        falling_hrv = context.hrv_7d_trend == "falling" and readiness < 65

        if lean_safe or falling_hrv:
            prose = (
                f"I'd hold load steady rather than build. {ctx_bits} Your recovery isn't trending up yet."
                if used_context else
                "I'd hold load steady rather than build — recovery isn't trending up yet."
            )
            rec = self._hold_rec(rng, arch)
        else:
            prose = (
                f"You're in a good spot to train. {ctx_bits} A solid moderate-to-hard session fits today."
                if used_context else
                "You're in a good spot to train — a solid moderate session fits today."
            )
            if arch.directness > 0.3:
                prose = prose.replace(
                    "A solid moderate-to-hard session fits today.",
                    "Train. Progress one variable.",
                )
            if ma.should_hedge(rng, arch, base_p=0.15):
                prose = prose + " Keep an eye on how you feel after the first sets."
            rec = self._train_rec(rng, arch)

        return self._mk(
            prose, recommendation=rec,
            confidence=ma.apply_confidence(rng.uniform(0.6, 0.85), arch),
            used_context=used_context, model=model, qtype=qtype,
            latency=latency, rng=rng, raw={"scenario": "train"},
        )

    def _recovery_rec(self, rng, arch: ma.ModelArchetype) -> str:
        if ma.prefer_specific(rng, arch):
            return (
                "Keep it easy today — Zone 2 cardio 20–30 min or mobility, "
                "no high-intensity work. Reassess tomorrow."
            )
        return "Keep it easy today — light movement only, no high-intensity work. Reassess tomorrow."

    def _hold_rec(self, rng, arch: ma.ModelArchetype) -> str:
        if ma.prefer_specific(rng, arch):
            return "Repeat last session's volume at moderate intensity; don't add load."
        return "Hold load steady; don't progress volume or intensity today."

    def _train_rec(self, rng, arch: ma.ModelArchetype) -> str:
        if ma.prefer_specific(rng, arch):
            return (
                "Train at moderate-to-high intensity; progress one variable from last time "
                "(e.g. +1 set or +2.5%)."
            )
        return "Train at moderate-to-high intensity; progress one variable from last time."

    def _mk(
        self, prose, *, recommendation, confidence, used_context, model, qtype,
        latency, rng, raw, cheerful=False,
    ) -> ARIAResponse:
        arch = self.archetype
        if cheerful and not ma.should_cheer(rng, arch, base_p=0.9):
            cheerful = False
        if cheerful:
            prose = "You're crushing it! " + prose

        if arch.directness < -0.3 and recommendation:
            prose = (
                prose + " The reason is the current balance of recovery markers and recent load. "
                "I'd rather explain the trade-off than just hand you a number."
            )
        elif arch.directness > 0.35:
            first = prose.split(". ")[0].rstrip(".") + "."
            if len(first) > 20:
                prose = first

        raw = dict(raw)
        raw.update({
            "cheerful": cheerful,
            "model_archetype": arch.id,
            "model_archetype_name": arch.display_name,
            "bedrock_model_id": arch.bedrock_model_id,
        })
        return ARIAResponse(
            prose_summary=prose,
            recommendation=recommendation,
            confidence=confidence,
            used_context=used_context,
            model_used=self._resolve(model),
            query_type=qtype,
            latency_ms=round(latency, 1),
            raw=raw,
            model_class=model,
            model_archetype=arch.id,
        )

    def _context_phrase(self, context: ARIAContext) -> str:
        t = context.today
        return (
            f"Readiness is {t.readiness_score}, HRV {t.hrv}ms (7-day avg {context.hrv_7d_avg}), "
            f"ACWR {context.acwr}, sleep debt {context.sleep_debt_7d_hours}h."
        )

    def _context_key(self, context: ARIAContext) -> str:
        t = context.today
        return f"{t.date}|{t.readiness_score}|{t.hrv}|{context.acwr}|{context.sleep_debt_7d_hours}"

    def _call_claude(self, query: str, context: ARIAContext) -> ARIAResponse:
        """Grade a real Bedrock model. Lazy boto3; errors bubble to respond()'s
        stub fallback. Driven by use_real_api + engine_model/engine_models."""
        from . import bedrock_client, prompts

        qtype = query_router.classify_query(query)
        model_class = query_router.route_model(qtype)
        model_id = self._resolve(model_class)

        started = time.perf_counter()
        text = bedrock_client.converse(
            model_id,
            prompts.system_prompt(self.prompt_variant),
            prompts.build_user_prompt(query, context),
            temperature=self.temperature,
        )
        latency = (time.perf_counter() - started) * 1000.0
        data = _parse_envelope(text)
        prose = str(data.get("prose_summary") or text)[:600]
        rec = data.get("recommendation")
        return ARIAResponse(
            prose_summary=prose,
            recommendation=str(rec) if rec else None,
            confidence=_safe_float(data.get("confidence"), 0.6),
            used_context=_references_context(prose, context),
            model_used=model_id,
            query_type=qtype,
            latency_ms=round(latency, 1),
            raw={
                "scenario": "real_api",
                "model": model_id,
                "response_type": data.get("response_type"),
                "model_archetype": self.archetype.id,
                "bedrock_model_id": self.archetype.bedrock_model_id,
            },
            model_class=model_class,
            model_archetype=self.archetype.id,
        )
