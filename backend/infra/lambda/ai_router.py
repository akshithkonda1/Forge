from __future__ import annotations

import hashlib
import logging
import math
import os
import re
import threading
import time
from dataclasses import dataclass, field
from queue import Empty, Queue
from typing import Any

_log = logging.getLogger("forge.ai_router")


MAX_PACKAGE_BYTES = 10 * 1024 * 1024 * 1024
DEFAULT_MODEL_TIMEOUT_SECONDS = 5.0
DEFAULT_OVERALL_TIMEOUT_SECONDS = 14.0
DEFAULT_CONSENSUS_WINDOW_SECONDS = 1.0
DEFAULT_MAX_TOKENS = 512
HARD_MAX_TOKENS = 512
MAX_QUESTION_CHARS = 4_000
MAX_CONTEXT_CHARS = 4_000
DEFAULT_TEMPERATURE = 0.2
DEFAULT_PREVIEW_BYTES = 1024
DEFAULT_MAX_PROMPT_CHARS = 6000
DEFAULT_CONSENSUS_INPUT_CHARS = 12000
DEFAULT_BEDROCK_CONNECT_TIMEOUT_SECONDS = 3.0
DEFAULT_BEDROCK_READ_TIMEOUT_SECONDS = max(10.0, DEFAULT_OVERALL_TIMEOUT_SECONDS * 2)
MIN_CONSENSUS_BUDGET_SECONDS = 0.2
CONSENSUS_TIMEOUT_BUFFER_SECONDS = 0.25
# Word-overlap Jaccard thresholds for _answer_agreement — deliberately loose:
# two honest paraphrases of the same finding still share most content words,
# so only real topical divergence should read as "low".
AGREEMENT_HIGH_THRESHOLD = 0.35
AGREEMENT_LOW_THRESHOLD = 0.15
# Upper bound for client-supplied model/overall timeouts. Must stay comfortably
# under the Lambda's own platform timeout (15s, backend/infra/variables.tf) —
# see the comment in RouteSettings.from_payload.
MAX_CLIENT_TIMEOUT_SECONDS = 10.0

# Bedrock is opt-in. Mirrors aria_core.aria_engine.bedrock_enabled() so the router
# shares one flag with /ai/chat, but kept local so importing this module (early,
# from handler) never pulls in the full ARIA engine. When the flag is off the
# router must never reach Amazon Bedrock, even on a deployed Lambda with JWT+IAM.
# Model ID/region table is not encoded here — services.provider_capabilities
# is a design stub until Quill's table lands. Dummy/offline remains default.
_BEDROCK_TRUE_FLAGS = {"1", "true", "yes", "on"}


def bedrock_enabled() -> bool:
    """True when the live Bedrock path is enabled via ARIA_BEDROCK_ENABLED."""
    return os.getenv("ARIA_BEDROCK_ENABLED", "").strip().lower() in _BEDROCK_TRUE_FLAGS


# --- Per-model request shape ---------------------------------------------------
#
# Newer Claude models reject sampling parameters: Opus 4.7 / 4.8 and every 5.x
# model return a 400 for a non-default `temperature`. Sending one meant every
# live call to those models failed and quietly fell back to the deterministic
# envelope. The 5.x models also think on every turn (adaptive thinking cannot
# be switched off on Opus 5.5); `effort` is the control, and thinking tokens
# count toward `maxTokens`, so the cap needs headroom above the reply budget.
_CLAUDE_NO_SAMPLING = re.compile(r"claude-(?:opus-4-[78]|opus-5|sonnet-5|haiku-5|fable|mythos)")
_CLAUDE_ADAPTIVE_DEFAULT = re.compile(r"claude-(?:opus-5|sonnet-5|haiku-5|fable|mythos)")
_EFFORT_LEVELS = {"low", "medium", "high", "xhigh", "max"}
# Chat replies are short and latency-bound (5 s per-model budget); low effort
# keeps thinking brief. Override per environment with ARIA_BEDROCK_EFFORT.
DEFAULT_BEDROCK_EFFORT = "low"
THINKING_TOKEN_HEADROOM = 1024
PROMPT_CACHE_MIN_CHARS = 4000
RESPONSE_CACHE_TTL_SECONDS = 120.0
RESPONSE_CACHE_MAX_ENTRIES = 64


def _model_family(model_id: str) -> str:
    """`global.anthropic.claude-opus-5-5` -> `claude-opus-5-5`."""
    return str(model_id or "").strip().lower().rsplit(".", 1)[-1] if "anthropic" in str(model_id or "").lower() else ""


def accepts_sampling_params(model_id: str) -> bool:
    """False for Claude models that 400 on `temperature` / `top_p`."""
    family = _model_family(model_id)
    return not (family and _CLAUDE_NO_SAMPLING.search(family))


def thinks_by_default(model_id: str) -> bool:
    """True for Claude models that run adaptive thinking on every turn."""
    family = _model_family(model_id)
    return bool(family and _CLAUDE_ADAPTIVE_DEFAULT.search(family))


def bedrock_effort() -> str:
    raw = os.getenv("ARIA_BEDROCK_EFFORT", "").strip().lower()
    return raw if raw in _EFFORT_LEVELS else DEFAULT_BEDROCK_EFFORT


def converse_request_shape(model_id: str, *, max_tokens: int, temperature: float) -> tuple[dict[str, Any], dict[str, Any] | None]:
    """(inferenceConfig, additionalModelRequestFields) for one Converse call."""
    inference: dict[str, Any] = {"maxTokens": int(max_tokens)}
    additional: dict[str, Any] | None = None
    if accepts_sampling_params(model_id):
        inference["temperature"] = temperature
    if thinks_by_default(model_id):
        inference["maxTokens"] = int(max_tokens) + THINKING_TOKEN_HEADROOM
        additional = {"output_config": {"effort": bedrock_effort()}}
    return inference, additional


def _is_validation_error(exc: Exception) -> bool:
    response = getattr(exc, "response", None)
    if not isinstance(response, dict):
        return False
    return str((response.get("Error") or {}).get("Code") or "") == "ValidationException"


class RoutingError(Exception):
    def __init__(self, status_code: int, message: str, *, details: dict[str, Any] | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message
        self.details = details or {}

    def to_response(self) -> dict[str, Any]:
        payload = {"message": self.message}
        if self.details:
            payload["details"] = self.details
        return payload


@dataclass(frozen=True)
class ModelConfig:
    slot: int
    name: str
    model_id: str
    responsibility: str
    family: str = "sonnet"


def _coerce_float(value: Any, *, field: str, default: float) -> float:
    """Same shape as `aria_engine._num`, but a client-supplied routing
    setting that fails to parse is a bad request, not data to silently
    drop — so this raises instead of returning None."""
    if value is None:
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        raise RoutingError(400, f"'{field}' must be a number.")


def _coerce_int(value: Any, *, field: str, default: int) -> int:
    if value is None:
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        raise RoutingError(400, f"'{field}' must be a whole number.")


@dataclass
class RouteSettings:
    model_timeout_seconds: float = DEFAULT_MODEL_TIMEOUT_SECONDS
    overall_timeout_seconds: float = DEFAULT_OVERALL_TIMEOUT_SECONDS
    consensus_window_seconds: float = DEFAULT_CONSENSUS_WINDOW_SECONDS
    max_tokens: int = DEFAULT_MAX_TOKENS
    temperature: float = DEFAULT_TEMPERATURE

    @classmethod
    def from_payload(cls, payload: dict[str, Any] | None) -> "RouteSettings":
        payload = payload or {}
        return cls(
            # Upper-clamped, not just lower-clamped: the Lambda's own platform
            # timeout is 15s (backend/infra/variables.tf), and AIRouter.route's
            # wait loop blocks for the full requested duration. An unclamped
            # client-supplied overallTimeoutSeconds could ask this to outrun
            # the Lambda's own hard timeout — a bare 502 with no body, instead
            # of the RoutingError this code is otherwise designed to return.
            # MAX_CLIENT_TIMEOUT_SECONDS leaves headroom under 15s for the
            # consensus finalization call that can run after the wait loop.
            model_timeout_seconds=min(MAX_CLIENT_TIMEOUT_SECONDS, max(
                0.1, _coerce_float(payload.get("modelTimeoutSeconds"), field="modelTimeoutSeconds", default=DEFAULT_MODEL_TIMEOUT_SECONDS)
            )),
            overall_timeout_seconds=min(MAX_CLIENT_TIMEOUT_SECONDS, max(
                0.5, _coerce_float(payload.get("overallTimeoutSeconds"), field="overallTimeoutSeconds", default=DEFAULT_OVERALL_TIMEOUT_SECONDS)
            )),
            consensus_window_seconds=max(
                0.0, _coerce_float(payload.get("consensusWindowSeconds"), field="consensusWindowSeconds", default=DEFAULT_CONSENSUS_WINDOW_SECONDS)
            ),
            max_tokens=min(
                HARD_MAX_TOKENS,
                max(128, _coerce_int(payload.get("maxTokens"), field="maxTokens", default=DEFAULT_MAX_TOKENS)),
            ),
            temperature=max(0.0, min(1.0, _coerce_float(
                payload.get("temperature"), field="temperature", default=DEFAULT_TEMPERATURE
            ))),
        )


@dataclass
class DataPackage:
    package_id: str
    size_bytes: int
    preview: str = ""
    s3_key: str | None = None
    media_type: str | None = None

    @classmethod
    def from_payload(cls, payload: dict[str, Any], index: int) -> "DataPackage":
        package_id = str(payload.get("id") or payload.get("name") or f"package-{index}")
        size_bytes = _coerce_int(payload.get("bytes") or payload.get("sizeBytes") or 0, field="bytes", default=0)
        return cls(
            package_id=package_id,
            size_bytes=max(0, size_bytes),
            preview=str(payload.get("preview") or payload.get("excerpt") or ""),
            s3_key=payload.get("s3Key"),
            media_type=payload.get("mediaType"),
        )


@dataclass
class RouteRequest:
    question: str
    context: str = ""
    packages: list[DataPackage] = field(default_factory=list)
    package_size_bytes: int = 0
    settings: RouteSettings = field(default_factory=RouteSettings)

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> "RouteRequest":
        question = str(payload.get("question") or payload.get("prompt") or "").strip()
        if not question:
            raise RoutingError(400, "Request must include a non-empty 'question'.")
        if len(question) > MAX_QUESTION_CHARS:
            raise RoutingError(
                413,
                "Question exceeds the routing size limit.",
                details={"maxQuestionChars": MAX_QUESTION_CHARS},
            )

        context = str(payload.get("context") or payload.get("background") or "").strip()
        if len(context) > MAX_CONTEXT_CHARS:
            context = context[:MAX_CONTEXT_CHARS]
        packages = [DataPackage.from_payload(item, index) for index, item in enumerate(payload.get("packages", []), 1)]
        declared_size = _coerce_int(payload.get("packageSizeBytes") or 0, field="packageSizeBytes", default=0)
        inferred_size = sum(package.size_bytes for package in packages)
        inline_size = len((question + context).encode("utf-8"))
        package_size_bytes = max(declared_size, inferred_size, inline_size)

        if package_size_bytes > MAX_PACKAGE_BYTES:
            raise RoutingError(
                413,
                "Package size exceeds the 10 GB routing limit.",
                details={
                    "maxPackageBytes": MAX_PACKAGE_BYTES,
                    "requestedPackageBytes": package_size_bytes,
                },
            )

        return cls(
            question=question,
            context=context,
            packages=packages,
            package_size_bytes=package_size_bytes,
            settings=RouteSettings.from_payload(payload.get("settings")),
        )


@dataclass
class ModelResult:
    model: ModelConfig
    success: bool
    started_at: float
    completed_at: float
    answer: str = ""
    error: str | None = None
    status_code: int | None = None
    usage: dict[str, Any] = field(default_factory=dict)

    @property
    def latency_seconds(self) -> float:
        return round(self.completed_at - self.started_at, 3)


_response_cache: dict[str, tuple[float, dict[str, Any]]] = {}
_response_cache_lock = threading.Lock()


def reset_response_cache() -> None:
    """Drop the in-process Converse cache. Tests call this between cases."""
    with _response_cache_lock:
        _response_cache.clear()


def _cache_key(*, model_id: str, system_prompt: str, user_prompt: str, max_tokens: int, temperature: float) -> str:
    raw = f"{model_id}\n{max_tokens}\n{temperature}\n{system_prompt}\n{user_prompt}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _cached_response(key: str) -> dict[str, Any] | None:
    now = time.monotonic()
    with _response_cache_lock:
        hit = _response_cache.get(key)
        if hit is None:
            return None
        stored_at, payload = hit
        if now - stored_at >= RESPONSE_CACHE_TTL_SECONDS:
            _response_cache.pop(key, None)
            return None
        return dict(payload)


def _store_cached_response(key: str, payload: dict[str, Any]) -> None:
    with _response_cache_lock:
        if len(_response_cache) >= RESPONSE_CACHE_MAX_ENTRIES:
            oldest = min(_response_cache.items(), key=lambda item: item[1][0])[0]
            _response_cache.pop(oldest, None)
        _response_cache[key] = (time.monotonic(), dict(payload))


class BedrockGateway:
    def __init__(self, *, region_name: str | None = None, uploads_bucket_name: str | None = None) -> None:
        self.region_name = region_name or os.getenv("AWS_REGION") or "us-east-1"
        self.uploads_bucket_name = uploads_bucket_name or os.getenv("UPLOADS_BUCKET_NAME")
        self._bedrock_clients: dict[tuple[float, float], Any] = {}
        self._s3_client = None
        # boto3/botocore client construction is not thread-safe, and route() calls
        # converse() from several worker threads at once — serialize client creation.
        self._client_lock = threading.Lock()

    def converse(
        self,
        *,
        model_id: str,
        system_prompt: str,
        user_prompt: str,
        max_tokens: int,
        temperature: float,
        request_timeout_seconds: float | None = None,
        image_bytes: bytes | None = None,
        image_format: str = "jpeg",
    ) -> dict[str, Any]:
        # Hard gate at the one place that actually talks to Bedrock: even if a
        # caller reaches the real gateway, it cannot Converse while the flag is
        # off or ARIA is paused. (Test fakes override converse() and are unaffected.)
        if not bedrock_enabled():
            raise RoutingError(
                503,
                "Live model routing is disabled. Set ARIA_BEDROCK_ENABLED to enable Amazon Bedrock.",
            )
        from aria_pause import is_aria_paused

        if is_aria_paused():
            raise RoutingError(503, "ARIA is paused", details={"error": "aria_paused"})
        capped_tokens = min(HARD_MAX_TOKENS, max(1, int(max_tokens)))
        from responses import RouteError
        from token_budget import reserve

        try:
            reserve(tokens=capped_tokens)
        except RouteError as exc:
            raise RoutingError(exc.status_code, exc.message, details={"code": exc.code}) from exc

        cache_key = None
        if image_bytes is None:
            cache_key = _cache_key(
                model_id=model_id,
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                max_tokens=capped_tokens,
                temperature=temperature,
            )
            cached = _cached_response(cache_key)
            if cached is not None:
                return cached

        client = self._get_bedrock_client(request_timeout_seconds=request_timeout_seconds)
        # Image block first, per Bedrock's own Converse examples — the model
        # reads the attachment before the instruction that references it.
        content: list[dict[str, Any]] = []
        if image_bytes is not None:
            content.append({"image": {"format": image_format, "source": {"bytes": image_bytes}}})
        content.append({"text": user_prompt})
        inference, additional = converse_request_shape(model_id, max_tokens=capped_tokens, temperature=temperature)
        system_blocks: list[dict[str, Any]] = [{"text": system_prompt}]
        used_prompt_cache = len(system_prompt) >= PROMPT_CACHE_MIN_CHARS
        if used_prompt_cache:
            system_blocks.append({"cachePoint": {"type": "default"}})
        request: dict[str, Any] = {
            "modelId": model_id,
            "system": system_blocks,
            "messages": [
                {
                    "role": "user",
                    "content": content,
                }
            ],
            "inferenceConfig": inference,
        }
        if additional:
            request["additionalModelRequestFields"] = additional
        try:
            response = client.converse(**request)
        except Exception as exc:
            # Drop optional fields (effort, prompt cache) on ValidationException
            # so a new model shape still returns an answer instead of falling back.
            retryable = additional or used_prompt_cache
            if not retryable or not _is_validation_error(exc):
                raise
            _log.warning("bedrock rejected optional converse fields for %s; retrying without", model_id)
            request.pop("additionalModelRequestFields", None)
            request["system"] = [{"text": system_prompt}]
            response = client.converse(**request)
        answer = self._extract_text(response)
        stop_reason = response.get("stopReason")
        if not answer and stop_reason == "max_tokens":
            _log.warning("bedrock %s hit maxTokens before any reply text", model_id)
        payload = {
            "answer": answer,
            "usage": response.get("usage", {}),
            "stopReason": stop_reason,
        }
        if cache_key is not None:
            _store_cached_response(cache_key, payload)
        return payload

    def load_preview(self, *, s3_key: str, max_bytes: int) -> str:
        if not self.uploads_bucket_name:
            raise RoutingError(500, "UPLOADS_BUCKET_NAME is not configured for S3-backed package previews.")

        response = self._get_s3_client().get_object(
            Bucket=self.uploads_bucket_name,
            Key=s3_key,
            Range=f"bytes=0-{max_bytes - 1}",
        )
        return response["Body"].read().decode("utf-8", errors="ignore")

    def head_object_size(self, *, s3_key: str) -> int:
        if not self.uploads_bucket_name:
            raise RoutingError(500, "UPLOADS_BUCKET_NAME is not configured for S3-backed package metadata.")

        response = self._get_s3_client().head_object(
            Bucket=self.uploads_bucket_name,
            Key=s3_key,
        )
        return int(response["ContentLength"])

    def _get_bedrock_client(self, *, request_timeout_seconds: float | None = None):
        timeout_key = self._timeout_key(request_timeout_seconds)
        # Fast path: an already-built client is safe to read without the lock.
        client = self._bedrock_clients.get(timeout_key)
        if client is not None:
            return client

        with self._client_lock:
            # Re-check under the lock: another thread may have built it while we waited.
            client = self._bedrock_clients.get(timeout_key)
            if client is None:
                try:
                    import boto3
                    from aws_clients import client_config

                    connect_timeout, read_timeout = timeout_key
                    config = client_config(
                        connect_timeout=connect_timeout,
                        read_timeout=read_timeout,
                        retries={"max_attempts": 1, "mode": "standard"},
                    )
                except ModuleNotFoundError as exc:
                    raise RoutingError(
                        500,
                        "boto3 is required to call Amazon Bedrock from this runtime.",
                    ) from exc

                client = boto3.client(
                    "bedrock-runtime",
                    region_name=self.region_name,
                    config=config,
                )
                self._bedrock_clients[timeout_key] = client
            return client

    def _get_s3_client(self):
        if self._s3_client is not None:
            return self._s3_client
        with self._client_lock:
            if self._s3_client is None:
                try:
                    import boto3
                    from aws_clients import client_config

                    config = client_config()
                except ModuleNotFoundError as exc:
                    raise RoutingError(500, "boto3 is required to load S3 package previews.") from exc
                self._s3_client = boto3.client(
                    "s3", region_name=self.region_name, config=config
                )
            return self._s3_client

    @staticmethod
    def _extract_text(response: dict[str, Any]) -> str:
        content_blocks = response.get("output", {}).get("message", {}).get("content", [])
        parts = [block.get("text", "") for block in content_blocks if isinstance(block, dict) and block.get("text")]
        return "\n".join(parts).strip()

    @staticmethod
    def _timeout_key(request_timeout_seconds: float | None) -> tuple[float, float]:
        if request_timeout_seconds is None:
            return (
                DEFAULT_BEDROCK_CONNECT_TIMEOUT_SECONDS,
                DEFAULT_BEDROCK_READ_TIMEOUT_SECONDS,
            )

        remaining_budget = max(0.1, float(request_timeout_seconds))
        read_timeout = round(min(DEFAULT_BEDROCK_READ_TIMEOUT_SECONDS, remaining_budget), 2)
        connect_timeout = round(min(DEFAULT_BEDROCK_CONNECT_TIMEOUT_SECONDS, max(0.1, read_timeout / 2)), 2)
        return connect_timeout, read_timeout


class AIRouter:
    def __init__(self, gateway: BedrockGateway | Any | None = None, *, region_name: str | None = None) -> None:
        self.gateway = gateway or BedrockGateway(region_name=region_name)
        self.models = default_models()

    def route(self, request: RouteRequest) -> dict[str, Any]:
        from aria_core.complexity import (
            TIER_ENSEMBLE,
            classify_complexity,
            escalation_log,
            next_tier,
            should_self_escalate,
        )
        from aria_core.privacy import redact_for_log
        from aria_core.rails import needs_model_verifier, validate_output
        from aria_core.suite import family_for_tier, parse_structured_reply

        started_at = time.monotonic()
        deadline_seconds = started_at + request.settings.overall_timeout_seconds
        route_warnings: list[str] = []

        self._enrich_packages_with_s3_metadata(request.packages, route_warnings)
        effective_package_size_bytes = self._effective_package_size_bytes(request)
        if effective_package_size_bytes > MAX_PACKAGE_BYTES:
            raise RoutingError(
                413,
                "Package size exceeds the 10 GB routing limit.",
                details={
                    "maxPackageBytes": MAX_PACKAGE_BYTES,
                    "requestedPackageBytes": effective_package_size_bytes,
                },
            )

        package_summaries = self._hydrate_package_summaries(request.packages, route_warnings)
        decision = classify_complexity(
            request.question,
            package_count=len(request.packages),
        )
        extra_reason = None
        results: list[ModelResult] = []
        launched: list[ModelConfig] = []

        if decision.tier == TIER_ENSEMBLE:
            launched, results, final_answer, finalization = self._route_ensemble(
                request,
                package_summaries,
                effective_package_size_bytes,
                deadline_seconds,
                route_warnings,
            )
        else:
            family = family_for_tier(decision.tier)
            model = self._model_by_family(family)
            result = self._invoke_model(
                model,
                request,
                package_summaries,
                effective_package_size_bytes,
                deadline_seconds,
                tier=decision.tier,
            )
            launched = [model]
            results = [result]
            already_escalated = 0
            if not result.success:
                bumped = next_tier(decision.tier)
                bump_family = family_for_tier(bumped)
                if bump_family != family and (deadline_seconds - time.monotonic()) > 0.2:
                    extra_reason = "timeout_escalate"
                    already_escalated = 1
                    bump_model = self._model_by_family(bump_family)
                    bump_result = self._invoke_model(
                        bump_model,
                        request,
                        package_summaries,
                        effective_package_size_bytes,
                        deadline_seconds,
                        tier=bumped,
                    )
                    launched.append(bump_model)
                    results.append(bump_result)
                    result = bump_result if bump_result.success else result
            structured = parse_structured_reply(result.answer if result.success else "")
            if result.success and should_self_escalate(
                decision,
                confidence=structured.confidence,
                needs_escalation=structured.needs_escalation,
                already_escalated=already_escalated,
            ):
                extra_reason = "self_assess"
                bumped = next_tier(decision.tier)
                bump_model = self._model_by_family(family_for_tier(bumped))
                if bump_model.model_id != model.model_id:
                    bump_result = self._invoke_model(
                        bump_model,
                        request,
                        package_summaries,
                        effective_package_size_bytes,
                        deadline_seconds,
                        tier=bumped,
                    )
                    launched.append(bump_model)
                    results.append(bump_result)
                    if bump_result.success:
                        result = bump_result
                        structured = parse_structured_reply(result.answer)
            if not result.success:
                self._raise_routing_failure(launched, results)
            final_answer = validate_output(structured.answer or result.answer)
            if needs_model_verifier(final_answer):
                extra_reason = extra_reason or "rails_verifier"
                verifier = self._model_by_family("sonnet")
                verified = self._invoke_model(
                    verifier,
                    request,
                    package_summaries,
                    effective_package_size_bytes,
                    deadline_seconds,
                    tier=1,
                    verifier=True,
                    draft=final_answer,
                )
                launched.append(verifier)
                results.append(verified)
                if verified.success:
                    final_answer = validate_output(parse_structured_reply(verified.answer).answer or verified.answer)
            primary = result
            agreement_label, agreement_score = _answer_agreement([result.answer])
            finalization = {
                "mode": "single-model",
                "usedModelCount": 1,
                "usedModels": [self._model_descriptor(primary.model)],
                "usedResults": [self._serialize_result(primary)],
                "finalizedByModel": self._model_descriptor(primary.model),
                "fallbackUsed": False,
                "agreement": agreement_label,
                "agreementScore": agreement_score,
            }

        successes = [item for item in results if item.success and item.answer.strip()]
        if not successes:
            self._raise_routing_failure(launched, results)
        primary = next((item for item in successes if item.model.slot == launched[0].slot), successes[0])
        if decision.tier == TIER_ENSEMBLE:
            pass
        supporting = [
            self._serialize_result(item)
            for item in successes
            if item.model.slot != primary.model.slot
        ]
        audit = escalation_log(
            decision,
            models=[item.model_id for item in launched],
            extra=extra_reason,
        )
        _log.info("aria suite routing %s", redact_for_log(audit))

        response: dict[str, Any] = {
            "status": "ok",
            "answer": final_answer,
            "finalAnswer": final_answer,
            "selectedModel": self._model_descriptor(primary.model),
            "finalAnswerSource": finalization,
            "suite": audit,
            "routing": {
                "packageSizeBytes": effective_package_size_bytes,
                "packageSizeHuman": humanize_bytes(effective_package_size_bytes),
                "initialParallelism": 3 if decision.tier == TIER_ENSEMBLE else 1,
                "launchedModelCount": len(launched),
                "launchedModels": [self._model_descriptor(model) for model in launched],
                "timeoutPolicy": {
                    "perModelSeconds": request.settings.model_timeout_seconds,
                    "overallSeconds": request.settings.overall_timeout_seconds,
                    "consensusWindowSeconds": request.settings.consensus_window_seconds,
                },
            },
            "results": [self._serialize_result(item) for item in results],
            "supportingAnswers": supporting,
        }
        if route_warnings:
            response["warnings"] = route_warnings
        return response

    def model_count_for_package_size(self, package_size_bytes: int) -> int:
        """Package size no longer fans out models. Complexity decides the tier."""
        return 1

    def _model_by_family(self, family: str) -> ModelConfig:
        for model in self.models:
            if model.family == family:
                return model
        return self.models[0]

    def _raise_routing_failure(self, launched: list[ModelConfig], results: list[ModelResult]) -> None:
        gated = next((item for item in results if item.status_code in {429, 503}), None)
        if gated is not None:
            raise RoutingError(
                gated.status_code,
                gated.error or "ARIA is paused",
                details={"error": "aria_paused" if gated.status_code == 503 else "aria_daily_cap"},
            )
        raise RoutingError(
            504,
            "No model returned a successful answer within the router timeout window.",
            details={
                "launchedModels": [self._model_descriptor(model) for model in launched],
                "results": [self._serialize_result(item) for item in results],
            },
        )

    def _invoke_model(
        self,
        model: ModelConfig,
        request: RouteRequest,
        package_summaries: list[dict[str, Any]],
        package_size_bytes: int,
        deadline_seconds: float,
        *,
        tier: int,
        verifier: bool = False,
        draft: str = "",
    ) -> ModelResult:
        from aria_core.suite import consensus_system_prompt, system_prompt_for_tier

        model_started_at = time.monotonic()
        remaining = max(0.1, deadline_seconds - model_started_at)
        system_prompt = (
            consensus_system_prompt()
            if verifier
            else system_prompt_for_tier(tier, family=model.family)
        )
        user_prompt = self._build_user_prompt(
            request=request,
            package_size_bytes=package_size_bytes,
            package_summaries=package_summaries,
            launched_parallelism=1,
        )
        if verifier and draft:
            user_prompt += "\n\nDraft to rewrite onto rails:\n" + draft
        try:
            payload = self.gateway.converse(
                model_id=model.model_id,
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                max_tokens=request.settings.max_tokens,
                temperature=request.settings.temperature,
                request_timeout_seconds=remaining,
            )
            return ModelResult(
                model=model,
                success=bool(payload.get("answer")),
                answer=str(payload.get("answer") or ""),
                usage=payload.get("usage", {}),
                started_at=model_started_at,
                completed_at=time.monotonic(),
            )
        except RoutingError as exc:
            return ModelResult(
                model=model,
                success=False,
                error=str(exc.message or exc),
                status_code=exc.status_code,
                started_at=model_started_at,
                completed_at=time.monotonic(),
            )
        except (OSError, RuntimeError, ValueError, TypeError, KeyError) as exc:
            return ModelResult(
                model=model,
                success=False,
                error=str(exc),
                started_at=model_started_at,
                completed_at=time.monotonic(),
            )

    def _route_ensemble(
        self,
        request: RouteRequest,
        package_summaries: list[dict[str, Any]],
        package_size_bytes: int,
        deadline_seconds: float,
        warnings: list[str],
    ) -> tuple[list[ModelConfig], list[ModelResult], str, dict[str, Any]]:
        from aria_core.complexity import TIER_ENSEMBLE
        from aria_core.rails import validate_output
        from aria_core.suite import consensus_system_prompt, isolate_drafts, parse_structured_reply

        launched = list(self.models)
        result_queue: Queue[ModelResult] = Queue()

        def worker(model: ModelConfig) -> None:
            result_queue.put(
                self._invoke_model(
                    model,
                    request,
                    package_summaries,
                    package_size_bytes,
                    deadline_seconds,
                    tier=TIER_ENSEMBLE,
                )
            )

        threads = [
            threading.Thread(target=worker, args=(model,), daemon=True, name=f"aria-suite-{model.family}")
            for model in launched
        ]
        for thread in threads:
            thread.start()
        results: list[ModelResult] = []
        remaining = max(0.1, deadline_seconds - time.monotonic())
        deadline = time.monotonic() + remaining
        for _ in launched:
            timeout = max(0.01, deadline - time.monotonic())
            try:
                results.append(result_queue.get(timeout=timeout))
            except Empty:
                break
        for thread in threads:
            thread.join(timeout=0.01)
        successes = [item for item in results if item.success and item.answer.strip()]
        if not successes:
            self._raise_routing_failure(launched, results)
        drafts = [(item.model.name, item.answer) for item in successes]
        agreement_label, agreement_score = _answer_agreement([item.answer for item in successes])
        remaining_budget = deadline_seconds - time.monotonic()
        synthesizer = self._model_by_family("sonnet")
        consensus_answer = ""
        fallback_used = False
        fallback_reason = None
        if remaining_budget <= MIN_CONSENSUS_BUDGET_SECONDS:
            fallback_used = True
            fallback_reason = "timeout_budget_exhausted"
            warnings.append(
                "Ensemble synthesis skipped because the remaining time budget was too small."
            )
        else:
            try:
                from aria_core.untrusted import isolate

                payload = self.gateway.converse(
                    model_id=synthesizer.model_id,
                    system_prompt=consensus_system_prompt(),
                    user_prompt=(
                        f"Original question:\n{isolate(request.question, kind='user_message')}\n\n"
                        "Independent drafts:\n"
                        f"{isolate_drafts(drafts)}"
                    ),
                    max_tokens=request.settings.max_tokens,
                    temperature=min(request.settings.temperature, 0.2),
                    request_timeout_seconds=max(0.1, remaining_budget - CONSENSUS_TIMEOUT_BUFFER_SECONDS),
                )
                consensus_answer = str(payload.get("answer") or "").strip()
            except (RoutingError, OSError, RuntimeError, ValueError, TypeError) as exc:
                fallback_used = True
                fallback_reason = "consensus_failed"
                warnings.append("Ensemble synthesis failed; returning the fastest successful draft.")
                _log.warning("ensemble synthesis failed: %s", exc)
        if not consensus_answer:
            consensus_answer = successes[0].answer
            fallback_used = True
            fallback_reason = fallback_reason or "consensus_failed"
            if not any("Ensemble synthesis failed" in item for item in warnings):
                warnings.append("Ensemble synthesis failed; returning the fastest successful draft.")
        final_answer = validate_output(parse_structured_reply(consensus_answer).answer or consensus_answer)
        finalization = {
            "mode": f"{len(successes)}-model-consensus",
            "usedModelCount": len(successes),
            "usedModels": [self._model_descriptor(item.model) for item in successes],
            "usedResults": [self._serialize_result(item) for item in successes],
            "finalizedByModel": self._model_descriptor(synthesizer),
            "fallbackUsed": fallback_used,
            "agreement": agreement_label,
            "agreementScore": agreement_score,
        }
        if fallback_reason:
            finalization["fallbackReason"] = fallback_reason
        return launched, results, final_answer, finalization

    def _enrich_packages_with_s3_metadata(self, packages: list[DataPackage], warnings: list[str]) -> None:
        for package in packages:
            if package.size_bytes > 0 or not package.s3_key:
                continue
            try:
                package.size_bytes = max(0, self.gateway.head_object_size(s3_key=package.s3_key))
            except (RoutingError, OSError, RuntimeError, ValueError, TypeError, KeyError):
                warnings.append(
                    f"Could not infer size for package '{package.package_id}' from S3 metadata; routing used the remaining request metadata only."
                )

    @staticmethod
    def _effective_package_size_bytes(request: RouteRequest) -> int:
        return max(request.package_size_bytes, sum(package.size_bytes for package in request.packages))

    def _hydrate_package_summaries(self, packages: list[DataPackage], warnings: list[str]) -> list[dict[str, Any]]:
        summaries: list[dict[str, Any]] = []
        remaining_chars = DEFAULT_MAX_PROMPT_CHARS

        for package in packages:
            preview_source = "inline" if package.preview else "missing"
            preview = package.preview

            if not preview and package.s3_key:
                try:
                    preview = self.gateway.load_preview(s3_key=package.s3_key, max_bytes=DEFAULT_PREVIEW_BYTES)
                    preview_source = "s3"
                except (RoutingError, OSError, RuntimeError, ValueError, TypeError, KeyError):
                    preview = ""
                    preview_source = "unavailable"
                    warnings.append(
                        f"Could not load preview for package '{package.package_id}' from S3; routing continued with package metadata only."
                    )

            from aria_core.untrusted import compress_text, isolate

            preview = isolate(
                compress_text(preview, max_chars=min(remaining_chars, 1600)),
                kind="package_preview",
                max_chars=min(remaining_chars, 1600),
            )
            remaining_chars -= len(preview)

            summaries.append(
                {
                    "id": package.package_id,
                    "sizeBytes": package.size_bytes,
                    "sizeHuman": humanize_bytes(package.size_bytes),
                    "mediaType": package.media_type,
                    "preview": preview,
                    "previewSource": preview_source,
                }
            )

            if remaining_chars <= 0:
                break

        return summaries

    def _build_system_prompt(self, model: ModelConfig, initial_parallelism: int) -> str:
        from aria_core.suite import system_prompt_for_tier
        from aria_core.complexity import TIER_SONNET

        return system_prompt_for_tier(TIER_SONNET, family=model.family)

    def _build_user_prompt(
        self,
        *,
        request: RouteRequest,
        package_size_bytes: int,
        package_summaries: list[dict[str, Any]],
        launched_parallelism: int,
    ) -> str:
        from aria_core.untrusted import isolate

        sections = [
            isolate(request.question, kind="user_message"),
            (
                "Routing context:\n"
                f"- Package size: {humanize_bytes(package_size_bytes)} ({package_size_bytes} bytes)\n"
                f"- Active model count: {launched_parallelism}\n"
                f"- Max supported package size: {humanize_bytes(MAX_PACKAGE_BYTES)}"
            ),
        ]

        if request.context:
            sections.append(isolate(request.context, kind="context", max_chars=4000))

        if package_summaries:
            package_lines = []
            for package in package_summaries:
                header = f"- {package['id']} ({package['sizeHuman']})"
                if package.get("mediaType"):
                    header += f" [{package['mediaType']}]"
                package_lines.append(header)
                if package["preview"]:
                    package_lines.append(f"  Preview ({package['previewSource']}): {package['preview']}")
                else:
                    package_lines.append("  Preview: unavailable")
            sections.append("Packages:\n" + "\n".join(package_lines))

        sections.append(
            "Response format:\n"
            "1. Give the best direct answer you can.\n"
            "2. Mention any assumptions or missing data.\n"
            "3. Keep it concise and operational."
        )
        return "\n\n".join(sections)

    def _build_final_answer(
        self,
        *,
        request: RouteRequest,
        used_results: list[ModelResult],
        deadline_seconds: float,
    ) -> tuple[str, dict[str, Any]]:
        # Agreement is about the *raw* per-model answers, independent of
        # whichever branch below ends up producing the final text — so it's
        # computed once, up front, and attached to every outcome the same way.
        agreement_label, agreement_score = _answer_agreement(
            [result.answer for result in used_results]
        )

        if len(used_results) == 1:
            only_result = used_results[0]
            return only_result.answer, {
                "mode": "single-model",
                "usedModelCount": 1,
                "usedModels": [self._model_descriptor(only_result.model)],
                "usedResults": [self._serialize_result(only_result)],
                "finalizedByModel": self._model_descriptor(only_result.model),
                "fallbackUsed": False,
                "agreement": agreement_label,
                "agreementScore": agreement_score,
            }

        finalizer = used_results[0]
        remaining_budget_seconds = deadline_seconds - time.monotonic()
        if remaining_budget_seconds <= MIN_CONSENSUS_BUDGET_SECONDS:
            return finalizer.answer, {
                "mode": f"{len(used_results)}-model-consensus",
                "usedModelCount": len(used_results),
                "usedModels": [self._model_descriptor(result.model) for result in used_results],
                "usedResults": [self._serialize_result(result) for result in used_results],
                "finalizedByModel": self._model_descriptor(finalizer.model),
                "fallbackUsed": True,
                "fallbackReason": "timeout_budget_exhausted",
                "agreement": agreement_label,
                "agreementScore": agreement_score,
            }

        try:
            payload = self.gateway.converse(
                model_id=finalizer.model.model_id,
                system_prompt=self._build_consensus_system_prompt(used_results),
                user_prompt=self._build_consensus_user_prompt(request, used_results),
                max_tokens=request.settings.max_tokens,
                temperature=min(request.settings.temperature, 0.2),
                request_timeout_seconds=max(0.1, remaining_budget_seconds - CONSENSUS_TIMEOUT_BUFFER_SECONDS),
            )
            consensus_answer = str(payload.get("answer") or "").strip()
            if consensus_answer:
                return consensus_answer, {
                    "mode": f"{len(used_results)}-model-consensus",
                    "usedModelCount": len(used_results),
                    "usedModels": [self._model_descriptor(result.model) for result in used_results],
                    "usedResults": [self._serialize_result(result) for result in used_results],
                    "finalizedByModel": self._model_descriptor(finalizer.model),
                    "fallbackUsed": False,
                    "agreement": agreement_label,
                    "agreementScore": agreement_score,
                }
        except Exception as exc:  # noqa: BLE001 — never fail the request on consensus
            # A consensus failure is recoverable (we fall back to the fastest
            # answer), but swallowing it silently hides real Bedrock/prompt
            # problems. Log it so the fallback is observable.
            _log.warning(
                "consensus finalization failed (model=%s): %s",
                finalizer.model.model_id,
                exc,
            )

        return finalizer.answer, {
            "mode": f"{len(used_results)}-model-consensus",
            "usedModelCount": len(used_results),
            "usedModels": [self._model_descriptor(result.model) for result in used_results],
            "usedResults": [self._serialize_result(result) for result in used_results],
            "finalizedByModel": self._model_descriptor(finalizer.model),
            "fallbackUsed": True,
            "fallbackReason": "consensus_failed",
            "agreement": agreement_label,
            "agreementScore": agreement_score,
        }

    def _build_consensus_system_prompt(self, used_results: list[ModelResult]) -> str:
        return (
            "You are Forge's consensus finalizer. "
            f"You must produce one final answer from the {len(used_results)} model answers provided. "
            "Use only the content in those model answers. "
            "Keep what clearly agrees across them, preserve non-conflicting useful details, "
            "and if they disagree, state the safest common-ground answer without inventing anything new."
        )

    def _build_consensus_user_prompt(self, request: RouteRequest, used_results: list[ModelResult]) -> str:
        sections = [
            f"Original question:\n{request.question}",
        ]

        if request.context:
            sections.append(f"Original context:\n{normalize_excerpt(request.context, 3000)}")

        remaining_chars = DEFAULT_CONSENSUS_INPUT_CHARS
        answer_sections: list[str] = []
        for result in used_results:
            answer_text = normalize_excerpt(result.answer, min(remaining_chars, 3500))
            remaining_chars -= len(answer_text)
            answer_sections.append(
                f"{result.model.name} (slot {result.model.slot}):\n{answer_text}"
            )
            if remaining_chars <= 0:
                break

        sections.append("Model answers to reconcile:\n" + "\n\n".join(answer_sections))
        sections.append(
            "Return format:\n"
            "1. Write one final answer only.\n"
            "2. Do not mention model names.\n"
            "3. Do not add facts that are not present in the supplied answers."
        )
        return "\n\n".join(sections)

    @staticmethod
    def _serialize_result(result: ModelResult) -> dict[str, Any]:
        payload = {
            "model": AIRouter._model_descriptor(result.model),
            "success": result.success,
            "latencySeconds": result.latency_seconds,
        }
        if result.answer:
            payload["answer"] = result.answer
        if result.error:
            payload["error"] = result.error
        if result.usage:
            payload["usage"] = result.usage
        return payload

    @staticmethod
    def _model_descriptor(model: ModelConfig) -> dict[str, Any]:
        return {
            "slot": model.slot,
            "name": model.name,
            "modelId": model.model_id,
            "family": model.family,
        }


def default_models() -> list[ModelConfig]:
    """Slot ids stay 1=Sonnet, 2=Opus, 3=Grok (Terraform / update_model_ids).

    The escalation ladder selects by ``family``, not by slot order:
    Tier 1 Sonnet, Tier 2 Grok, Tier 3 Opus, Tier 4 all three.
    """
    from aria_core.suite import TIER_RESPONSIBILITY
    from aria_core.complexity import TIER_GROK, TIER_OPUS, TIER_SONNET

    return [
        ModelConfig(
            slot=1,
            name=os.getenv("AI_ROUTER_MODEL_1_NAME", "Claude Sonnet 5.5"),
            model_id=os.getenv("AI_ROUTER_MODEL_1_ID", "global.anthropic.claude-sonnet-5-5"),
            responsibility=TIER_RESPONSIBILITY[TIER_SONNET],
            family="sonnet",
        ),
        ModelConfig(
            slot=2,
            name=os.getenv("AI_ROUTER_MODEL_2_NAME", "Claude Opus 5.5"),
            model_id=os.getenv("AI_ROUTER_MODEL_2_ID", "global.anthropic.claude-opus-5-5"),
            responsibility=TIER_RESPONSIBILITY[TIER_OPUS],
            family="opus",
        ),
        ModelConfig(
            slot=3,
            name=os.getenv("AI_ROUTER_MODEL_3_NAME", "Grok"),
            model_id=os.getenv("AI_ROUTER_MODEL_3_ID", "global.xai.grok-4.7"),
            responsibility=TIER_RESPONSIBILITY[TIER_GROK],
            family="grok",
        ),
    ]


def normalize_excerpt(text: str, max_chars: int) -> str:
    if max_chars <= 0:
        return ""
    compact = " ".join(str(text).split())
    if len(compact) <= max_chars:
        return compact
    return compact[: max_chars - 3].rstrip() + "..."


_WORD_RE = re.compile(r"[a-z0-9]+")


def _answer_agreement(answers: list[str]) -> tuple[str, float]:
    """How much the raw per-model answers agreed with each other, *before*
    the consensus finalizer smooths them into one voice.

    Deterministic word-overlap (Jaccard over content words), computed in
    Python from the source answers rather than asked of the finalizer
    itself — a finalizer that papers over real disagreement to produce one
    clean answer shouldn't also get to be the one reporting how much
    disagreement it papered over. Needs at least two non-empty answers to
    mean anything; a single-model route has nothing to compare, so "n/a".
    """
    word_sets = [set(_WORD_RE.findall(answer.lower())) for answer in answers]
    word_sets = [words for words in word_sets if words]
    if len(word_sets) < 2:
        return "n/a", 1.0

    pair_scores = []
    for i in range(len(word_sets)):
        for j in range(i + 1, len(word_sets)):
            union = word_sets[i] | word_sets[j]
            if union:
                pair_scores.append(len(word_sets[i] & word_sets[j]) / len(union))
    if not pair_scores:
        return "n/a", 1.0

    score = sum(pair_scores) / len(pair_scores)
    if score >= AGREEMENT_HIGH_THRESHOLD:
        label = "high"
    elif score >= AGREEMENT_LOW_THRESHOLD:
        label = "medium"
    else:
        label = "low"
    return label, round(score, 3)


def humanize_bytes(size_bytes: int) -> str:
    if size_bytes <= 0:
        return "0 B"
    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(size_bytes)
    for unit in units:
        if size < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(size)} {unit}"
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{size_bytes} B"
