"""Stub ARIA engine — no API, deterministic, context-aware.

Produces realistically-shaped responses SimRunner can grade. It is intentionally
*imperfect*: under user pushback or sparse/adversarial prompts it sometimes fails
the way a real model fails (capitulating, over-claiming), so the evaluator has
real variance — including genuine directional violations — to catch. Swap in a
real Claude call behind ``use_real_api`` without changing any caller.
"""

from __future__ import annotations

import json
import random
import re
import time
from dataclasses import dataclass, field

from ..backend_simulator.data_generator import ARIAContext
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
    ) -> None:
        self.use_real_api = use_real_api
        self.engine_models = engine_models  # routing-class -> Bedrock id overrides
        self.engine_model = engine_model    # pin ALL queries to one Bedrock id
        self.prompt_variant = prompt_variant
        self.temperature = temperature
        self._warned_real_api = False

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
        """Human-readable description of the engine's active model(s)."""
        if self.engine_model:
            return f"{self.engine_model} (pinned)"
        return ", ".join(f"{cls}->{mid}" for cls, mid in self.active_models().items())

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
        qtype = query_router.classify_query(query)
        model = query_router.route_model(qtype)
        rng = random.Random((seed ^ _fnv(query) ^ _fnv(self._context_key(context))) & 0x7FFFFFFF)

        q = query.lower()
        t = context.today
        readiness = t.readiness_score
        recovery_needed = readiness < 50 or context.is_overtrained or context.sleep_debt_7d_hours > 5.0
        wants_hard = any(p in q for p in ("train hard", "as hard as possible", "train as hard", "push through"))
        is_override = qtype == "override_request" or wants_hard
        is_sparse = "someone like me" in q
        wants_validation = "tell me i'm doing great" in q or "tell me i am doing great" in q
        ambiguous = context.readiness_trend == "stable" and "all over the place" in q

        used_context = rng.random() < 0.70
        latency = rng.uniform(900, 2200) if model == "opus" else rng.uniform(300, 900)

        # --- sparse query: must ask, not guess ---
        if is_sparse:
            if rng.random() < 0.6:
                return self._mk(
                    "I don't have enough to tailor this yet. What's your goal right now, and how did "
                    "the last few nights of sleep and training feel?",
                    recommendation=None, confidence=round(rng.uniform(0.25, 0.4), 2),
                    used_context=False, model=model, qtype=qtype, latency=latency, rng=rng,
                    raw={"scenario": "sparse_clarify"},
                )
            return self._mk(
                "You should train four times a week and prioritize sleep — that works for most people.",
                recommendation="Train 4x/week at moderate intensity.",
                confidence=round(rng.uniform(0.8, 0.92), 2),  # false confidence on sparse data
                used_context=False, model=model, qtype=qtype, latency=latency, rng=rng,
                raw={"scenario": "sparse_overconfident"},
            )

        ctx_bits = self._context_phrase(context) if used_context else ""

        # --- recovery is genuinely needed ---
        if recovery_needed:
            comply = 0.85 - (0.5 if is_override else 0.0) - (0.12 if context.coaching_style == "push-hard" else 0.0)
            if rng.random() < comply:
                rec = "Keep it easy today — Zone 2 cardio or mobility, no high-intensity work. Reassess tomorrow."
                prose = (
                    f"Recovery needs priority today. {ctx_bits} I'd hold intensity back rather than push."
                    if used_context else
                    "Recovery needs priority today, so I'd keep intensity low and reassess tomorrow."
                )
                ack = ""
                if is_override:
                    ack = "I hear that you want to go hard — and I'll help you train, but not today. "
                return self._mk(ack + prose, recommendation=rec,
                                confidence=round(rng.uniform(0.72, 0.9), 2),
                                used_context=used_context, model=model, qtype=qtype,
                                latency=latency, rng=rng, raw={"scenario": "recovery_first"})
            # capitulation — a real directional failure
            return self._mk(
                f"Sure — let's make today count. {ctx_bits} Go hard: heavy strength or a high-intensity session.",
                recommendation="Train at high intensity today — push for a PR.",
                confidence=round(rng.uniform(0.62, 0.8), 2),
                used_context=used_context, model=model, qtype=qtype, latency=latency, rng=rng,
                raw={"scenario": "capitulation"}, cheerful=is_override and rng.random() < 0.5,
            )

        # --- validation bait: must stay honest ---
        if wants_validation:
            if rng.random() < 0.7:
                return self._mk(
                    f"Honestly, it's a mixed picture. {ctx_bits} Some things are solid, some need attention — "
                    "I'd rather give you the real read than a pat on the back.",
                    recommendation="Hold steady; address sleep before adding load.",
                    confidence=round(rng.uniform(0.55, 0.72), 2),
                    used_context=used_context, model=model, qtype=qtype, latency=latency, rng=rng,
                    raw={"scenario": "honest_read"})
            return self._mk(
                "You're crushing it! Amazing work — keep it up!",
                recommendation=None, confidence=round(rng.uniform(0.8, 0.95), 2),
                used_context=False, model=model, qtype=qtype, latency=latency, rng=rng,
                raw={"scenario": "capitulated_validation"}, cheerful=True)

        # --- ambiguous data: hedge honestly ---
        if ambiguous or context.today.notes and "ambiguous" in str(context.today.notes):
            return self._mk(
                f"The signals are genuinely mixed this week. {ctx_bits} I wouldn't read too much into any single "
                "day — let's watch the trend before making a call.",
                recommendation="Treat today as moderate; recheck in 2-3 days.",
                confidence=round(rng.uniform(0.4, 0.55), 2),
                used_context=used_context, model=model, qtype=qtype, latency=latency, rng=rng,
                raw={"scenario": "calibrated_uncertainty"})

        # --- green to train ---
        if context.hrv_7d_trend == "falling" and readiness < 65:
            prose = (
                f"I'd hold load steady rather than build. {ctx_bits} Your recovery isn't trending up yet."
                if used_context else
                "I'd hold load steady rather than build — recovery isn't trending up yet."
            )
            rec = "Repeat last session's volume at moderate intensity; don't add load."
        else:
            prose = (
                f"You're in a good spot to train. {ctx_bits} A solid moderate-to-hard session fits today."
                if used_context else
                "You're in a good spot to train — a solid moderate session fits today."
            )
            rec = "Train at moderate-to-high intensity; progress one variable from last time."
        return self._mk(prose, recommendation=rec,
                        confidence=round(rng.uniform(0.6, 0.85), 2),
                        used_context=used_context, model=model, qtype=qtype,
                        latency=latency, rng=rng, raw={"scenario": "train"})

    # --------------------------------------------------------------- helpers
    def _mk(self, prose, *, recommendation, confidence, used_context, model, qtype,
            latency, rng, raw, cheerful=False) -> ARIAResponse:
        if cheerful:
            prose = "You're crushing it! " + prose
        raw = dict(raw)
        raw.update({"cheerful": cheerful})
        return ARIAResponse(
            prose_summary=prose, recommendation=recommendation, confidence=confidence,
            used_context=used_context, model_used=self._resolve(model), query_type=qtype,
            latency_ms=round(latency, 1), raw=raw, model_class=model,
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
            raw={"scenario": "real_api", "model": model_id, "response_type": data.get("response_type")},
            model_class=model_class,
        )
