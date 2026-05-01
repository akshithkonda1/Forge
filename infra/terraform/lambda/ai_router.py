from __future__ import annotations

import math
import os
import threading
import time
from dataclasses import dataclass, field
from queue import Empty, Queue
from typing import Any


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
            model_timeout_seconds=max(0.1, float(payload.get("modelTimeoutSeconds", DEFAULT_MODEL_TIMEOUT_SECONDS))),
            overall_timeout_seconds=max(0.5, float(payload.get("overallTimeoutSeconds", DEFAULT_OVERALL_TIMEOUT_SECONDS))),
            consensus_window_seconds=max(
                0.0, float(payload.get("consensusWindowSeconds", DEFAULT_CONSENSUS_WINDOW_SECONDS))
            ),
            max_tokens=max(128, int(payload.get("maxTokens", DEFAULT_MAX_TOKENS))),
            temperature=max(0.0, min(1.0, float(payload.get("temperature", DEFAULT_TEMPERATURE)))),
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
        size_bytes = int(payload.get("bytes") or payload.get("sizeBytes") or 0)
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
        declared_size = int(payload.get("packageSizeBytes") or 0)
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

    def converse(
        self,
        *,
        model_id: str,
        system_prompt: str,
        user_prompt: str,
        max_tokens: int,
        temperature: float,
        request_timeout_seconds: float | None = None,
    ) -> dict[str, Any]:
        client = self._get_bedrock_client(request_timeout_seconds=request_timeout_seconds)
        response = client.converse(
            modelId=model_id,
            system=[{"text": system_prompt}],
            messages=[
                {
                    "role": "user",
                    "content": [{"text": user_prompt}],
                }
            ],
            inferenceConfig={
                "maxTokens": max_tokens,
                "temperature": temperature,
            },
        )
        return {
            "answer": self._extract_text(response),
            "usage": response.get("usage", {}),
            "stopReason": response.get("stopReason"),
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
        if timeout_key not in self._bedrock_clients:
            try:
                import boto3
                from botocore.config import Config
            except ModuleNotFoundError as exc:
                raise RoutingError(
                    500,
                    "boto3 is required to call Amazon Bedrock from this runtime.",
                ) from exc

            connect_timeout, read_timeout = timeout_key
            self._bedrock_clients[timeout_key] = boto3.client(
                "bedrock-runtime",
                region_name=self.region_name,
                config=Config(
                    connect_timeout=connect_timeout,
                    read_timeout=read_timeout,
                    retries={"max_attempts": 1, "mode": "standard"},
                ),
            )
        return self._bedrock_clients[timeout_key]

    def _get_s3_client(self):
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

    def route(self, request: RouteRequest) -> dict[str, Any]:
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

        initial_parallelism = self.model_count_for_package_size(effective_package_size_bytes)
        package_summaries = self._hydrate_package_summaries(request.packages, route_warnings)
        result_queue: Queue[ModelResult] = Queue()
        launched_slots: list[ModelConfig] = []
        results: list[ModelResult] = []
        launched_indexes: set[int] = set()
        first_success_received_at: float | None = None

        next_launch_index = 0

        def launch_model(index: int) -> None:
            if index in launched_indexes or index >= len(self.models):
                return

            model = self.models[index]
            launched_indexes.add(index)
            launched_slots.append(model)

            system_prompt = self._build_system_prompt(model, initial_parallelism)
            user_prompt = self._build_user_prompt(
                request=request,
                package_size_bytes=effective_package_size_bytes,
                package_summaries=package_summaries,
                launched_parallelism=max(initial_parallelism, len(launched_slots)),
            )

            def worker() -> None:
                model_started_at = time.monotonic()
                remaining_budget_seconds = max(0.1, deadline_seconds - model_started_at)
                try:
                    payload = self.gateway.converse(
                        model_id=model.model_id,
                        system_prompt=system_prompt,
                        user_prompt=user_prompt,
                        max_tokens=request.settings.max_tokens,
                        temperature=request.settings.temperature,
                        request_timeout_seconds=remaining_budget_seconds,
                    )
                    result_queue.put(
                        ModelResult(
                            model=model,
                            success=bool(payload.get("answer")),
                            answer=str(payload.get("answer") or ""),
                            usage=payload.get("usage", {}),
                            started_at=model_started_at,
                            completed_at=time.monotonic(),
                        )
                    )
                except Exception as exc:  # pragma: no cover - exercised through fake gateway in tests
                    result_queue.put(
                        ModelResult(
                            model=model,
                            success=False,
                            error=str(exc),
                            started_at=model_started_at,
                            completed_at=time.monotonic(),
                        )
                    )

            thread = threading.Thread(target=worker, daemon=True, name=f"ai-router-slot-{model.slot}")
            thread.start()

        while next_launch_index < initial_parallelism:
            launch_model(next_launch_index)
            next_launch_index += 1

        initial_launch_at = time.monotonic()
        next_escalation_at = (
            initial_launch_at + request.settings.model_timeout_seconds
            if next_launch_index < len(self.models)
            else None
        )

        while True:
            now = time.monotonic()
            remaining_overall_seconds = deadline_seconds - now
            if remaining_overall_seconds <= 0:
                break

            wait_candidates = [remaining_overall_seconds]
            if next_escalation_at is not None:
                wait_candidates.append(max(0.0, next_escalation_at - now))
            if first_success_received_at is not None:
                wait_candidates.append(
                    max(
                        0.0,
                        first_success_received_at + request.settings.consensus_window_seconds - now,
                    )
                )
            wait_timeout = min(wait_candidates) if wait_candidates else 0.1

            try:
                result = result_queue.get(timeout=max(0.01, wait_timeout))
                results.append(result)
                if result.success and first_success_received_at is None:
                    first_success_received_at = time.monotonic()
            except Empty:
                pass

            now = time.monotonic()
            if (
                first_success_received_at is not None
                and now >= first_success_received_at + request.settings.consensus_window_seconds
            ):
                break

            if next_escalation_at is not None and now >= next_escalation_at and not any(item.success for item in results):
                launch_model(next_launch_index)
                next_launch_index += 1
                next_escalation_at = (
                    now + request.settings.model_timeout_seconds if next_launch_index < len(self.models) else None
                )

            if launched_indexes and len(results) == len(launched_indexes) and any(item.success for item in results):
                break

        successes = [result for result in results if result.success and result.answer.strip()]
        if not successes:
            raise RoutingError(
                504,
                "No model returned a successful answer within the router timeout window.",
                details={
                    "launchedModels": [self._model_descriptor(model) for model in launched_slots],
                    "results": [self._serialize_result(result) for result in results],
                },
            )

        used_results = sorted(successes, key=lambda item: (item.completed_at, item.model.slot))
        primary = used_results[0]
        final_answer, finalization = self._build_final_answer(
            request=request,
            used_results=used_results,
            deadline_seconds=deadline_seconds,
        )
        supporting = [
            self._serialize_result(result)
            for result in used_results
            if result.model.slot != primary.model.slot
        ]

        response: dict[str, Any] = {
            "status": "ok",
            "answer": final_answer,
            "finalAnswer": final_answer,
            "selectedModel": self._model_descriptor(primary.model),
            "finalAnswerSource": finalization,
            "routing": {
                "packageSizeBytes": effective_package_size_bytes,
                "packageSizeHuman": humanize_bytes(effective_package_size_bytes),
                "initialParallelism": initial_parallelism,
                "launchedModelCount": len(launched_slots),
                "launchedModels": [self._model_descriptor(model) for model in launched_slots],
                "timeoutPolicy": {
                    "perModelSeconds": request.settings.model_timeout_seconds,
                    "overallSeconds": request.settings.overall_timeout_seconds,
                    "consensusWindowSeconds": request.settings.consensus_window_seconds,
                },
            },
            "results": [self._serialize_result(result) for result in results],
            "supportingAnswers": supporting,
        }

        warnings = list(route_warnings)
        fallback_reason = finalization.get("fallbackReason")
        if fallback_reason == "timeout_budget_exhausted":
            warnings.append(
                "Consensus finalization skipped because the remaining time budget was too small; returning the fastest successful model answer."
            )
        elif fallback_reason == "consensus_failed":
            warnings.append(
                "Consensus finalization failed, so the router fell back to the fastest successful model answer."
            )
        if warnings:
            response["warnings"] = warnings

        return response

    def model_count_for_package_size(self, package_size_bytes: int) -> int:
        if package_size_bytes <= 0:
            return 1
        per_model_band = MAX_PACKAGE_BYTES / len(self.models)
        return max(1, min(len(self.models), math.ceil(package_size_bytes / per_model_band)))

    def _enrich_packages_with_s3_metadata(self, packages: list[DataPackage], warnings: list[str]) -> None:
        for package in packages:
            if package.size_bytes > 0 or not package.s3_key:
                continue
            try:
                package.size_bytes = max(0, self.gateway.head_object_size(s3_key=package.s3_key))
            except Exception:
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
                except Exception:
                    preview = ""
                    preview_source = "unavailable"
                    warnings.append(
                        f"Could not load preview for package '{package.package_id}' from S3; routing continued with package metadata only."
                    )

            preview = normalize_excerpt(preview, min(remaining_chars, 1600))
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
        return (
            "You are part of Forge's multi-model Bedrock router. "
            f"You are slot {model.slot} of {len(self.models)} and your responsibility is: {model.responsibility}. "
            f"The router activated {initial_parallelism} model(s) immediately for this request. "
            "Respond directly to the user question using the supplied package metadata and previews only. "
            "If the evidence is incomplete, say what is missing instead of inventing facts."
        )

    def _build_user_prompt(
        self,
        *,
        request: RouteRequest,
        package_size_bytes: int,
        package_summaries: list[dict[str, Any]],
        launched_parallelism: int,
    ) -> str:
        sections = [
            f"Question:\n{request.question}",
            (
                "Routing context:\n"
                f"- Package size: {humanize_bytes(package_size_bytes)} ({package_size_bytes} bytes)\n"
                f"- Active model fanout: {launched_parallelism}\n"
                f"- Max supported package size: {humanize_bytes(MAX_PACKAGE_BYTES)}"
            ),
        ]

        if request.context:
            sections.append(f"Shared context:\n{normalize_excerpt(request.context, 4000)}")

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
        if len(used_results) == 1:
            only_result = used_results[0]
            return only_result.answer, {
                "mode": "single-model",
                "usedModelCount": 1,
                "usedModels": [self._model_descriptor(only_result.model)],
                "usedResults": [self._serialize_result(only_result)],
                "finalizedByModel": self._model_descriptor(only_result.model),
                "fallbackUsed": False,
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
                }
        except Exception:
            pass

        return finalizer.answer, {
            "mode": f"{len(used_results)}-model-consensus",
            "usedModelCount": len(used_results),
            "usedModels": [self._model_descriptor(result.model) for result in used_results],
            "usedResults": [self._serialize_result(result) for result in used_results],
            "finalizedByModel": self._model_descriptor(finalizer.model),
            "fallbackUsed": True,
            "fallbackReason": "consensus_failed",
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
        }


def default_models() -> list[ModelConfig]:
    return [
        ModelConfig(
            slot=1,
            name="Claude Sonnet 4.6",
            model_id=os.getenv("AI_ROUTER_MODEL_1_ID", "anthropic.claude-sonnet-4-6"),
            responsibility="Primary responder focused on fast, high-quality first-pass answers.",
        ),
        ModelConfig(
            slot=2,
            name="Claude Opus 4.7",
            model_id=os.getenv("AI_ROUTER_MODEL_2_ID", "anthropic.claude-opus-4-7"),
            responsibility="Fallback and verifier when the first model misses the latency window or needs backup.",
        ),
        ModelConfig(
            slot=3,
            name=os.getenv("AI_ROUTER_MODEL_3_NAME", "Kimi K2.5"),
            model_id=os.getenv("AI_ROUTER_MODEL_3_ID", "moonshotai.kimi-k2.5"),
            responsibility="Second fallback that pressure-tests edge cases and fills remaining gaps.",
        ),
    ]


def normalize_excerpt(text: str, max_chars: int) -> str:
    if max_chars <= 0:
        return ""
    compact = " ".join(str(text).split())
    if len(compact) <= max_chars:
        return compact
    return compact[: max_chars - 3].rstrip() + "..."


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
