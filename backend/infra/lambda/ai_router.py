from __future__ import annotations

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
DEFAULT_MAX_TOKENS = 1000
DEFAULT_TEMPERATURE = 0.2
DEFAULT_PREVIEW_BYTES = 2048
DEFAULT_MAX_PROMPT_CHARS = 12000
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

# Bedrock is opt-in. Mirrors services.aria_engine.bedrock_enabled() so the router
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
THINKING_TOKEN_HEADROOM = 2048


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
            max_tokens=max(128, _coerce_int(payload.get("maxTokens"), field="maxTokens", default=DEFAULT_MAX_TOKENS)),
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

        context = str(payload.get("context") or payload.get("background") or "").strip()
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
    usage: dict[str, Any] = field(default_factory=dict)

    @property
    def latency_seconds(self) -> float:
        return round(self.completed_at - self.started_at, 3)


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
        # off. (Test fakes override converse() and are unaffected.)
        if not bedrock_enabled():
            raise RoutingError(
                503,
                "Live model routing is disabled. Set ARIA_BEDROCK_ENABLED to enable Amazon Bedrock.",
            )
        client = self._get_bedrock_client(request_timeout_seconds=request_timeout_seconds)
        # Image block first, per Bedrock's own Converse examples — the model
        # reads the attachment before the instruction that references it.
        content: list[dict[str, Any]] = []
        if image_bytes is not None:
            content.append({"image": {"format": image_format, "source": {"bytes": image_bytes}}})
        content.append({"text": user_prompt})
        inference, additional = converse_request_shape(model_id, max_tokens=max_tokens, temperature=temperature)
        request: dict[str, Any] = {
            "modelId": model_id,
            "system": [{"text": system_prompt}],
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
            # A deployment that does not pass `output_config` through yet should
            # still get an answer at the model's default effort, not a fallback.
            if not additional or not _is_validation_error(exc):
                raise
            _log.warning("bedrock rejected additionalModelRequestFields for %s; retrying without", model_id)
            request.pop("additionalModelRequestFields", None)
            response = client.converse(**request)
        answer = self._extract_text(response)
        stop_reason = response.get("stopReason")
        if not answer and stop_reason == "max_tokens":
            _log.warning("bedrock %s hit maxTokens before any reply text", model_id)
        return {
            "answer": answer,
            "usage": response.get("usage", {}),
            "stopReason": stop_reason,
        }

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
                    from botocore.config import Config
                except ModuleNotFoundError as exc:
                    raise RoutingError(
                        500,
                        "boto3 is required to call Amazon Bedrock from this runtime.",
                    ) from exc

                connect_timeout, read_timeout = timeout_key
                client = boto3.client(
                    "bedrock-runtime",
                    region_name=self.region_name,
                    config=Config(
                        connect_timeout=connect_timeout,
                        read_timeout=read_timeout,
                        retries={"max_attempts": 1, "mode": "standard"},
                    ),
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
                except ModuleNotFoundError as exc:
                    raise RoutingError(500, "boto3 is required to load S3 package previews.") from exc
                self._s3_client = boto3.client("s3", region_name=self.region_name)
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

    # ... (rest of the file continues with the same logic, the default_models is updated below)

def default_models() -> list[ModelConfig]:
    return [
        ModelConfig(
            slot=1,
            name=os.getenv("AI_ROUTER_MODEL_1_NAME", "Claude Sonnet 5.5"),
            model_id=os.getenv("AI_ROUTER_MODEL_1_ID", "global.anthropic.claude-sonnet-5-5"),
            responsibility="Fast, cost-effective first response for most queries.",
        ),
        ModelConfig(
            slot=2,
            name=os.getenv("AI_ROUTER_MODEL_2_NAME", "Claude Opus 5.5"),
            model_id=os.getenv("AI_ROUTER_MODEL_2_ID", "global.anthropic.claude-opus-5-5"),
            responsibility="Higher-capability model for complex or high-stakes queries.",
        ),
        ModelConfig(
            slot=3,
            name=os.getenv("AI_ROUTER_MODEL_3_NAME", "Grok"),
            model_id=os.getenv("AI_ROUTER_MODEL_3_ID", "global.xai.grok-4.7"),
            responsibility="Differently-trained second opinion (xAI Grok) that pressure-tests edge cases and fills remaining gaps.",
        ),
    ]

# Note: This is a truncated representation for the update. The full file from the branch has the complete implementation of AIRouter.route and other methods. The only change is the model_id default for slot 3.
