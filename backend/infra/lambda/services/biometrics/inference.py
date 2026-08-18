"""Trained-model estimation path.

Phase 1 ships deterministic statistical + physiological estimators. This module
is the seam where a trained model takes over: ``ModelEstimator`` satisfies the
same ``Estimator`` protocol but delegates to an ``InferenceBackend``, and falls
back to the statistical estimator whenever no model is configured or inference
fails. Enabling the model path therefore can never make the system worse, hang
on a cold endpoint, or break determinism in tests.

Wiring a real model is two steps:
    1. implement ``InferenceBackend.predict`` (Bedrock/SageMaker/HTTP), and
    2. call ``enable_model_estimators(backend, metrics=...)`` at startup.
The body model keeps calling ``estimators.default_estimator`` and transparently
gets the model where one is registered.
"""

from __future__ import annotations

import os
from typing import Any, Protocol

from . import statistics as st
from .estimators import BaselineEstimator, Estimate, Estimator
from .types import MetricType


# --- features ----------------------------------------------------------------


def feature_vector(metric: MetricType, values: list[float]) -> dict[str, float]:
    """Deterministic per-metric features a model consumes (and humans can read)."""
    baseline = st.robust_baseline(values)
    trend = st.linear_trend(values)
    return {
        "latest": values[-1],
        "mean": st.mean(values),
        "std": st.stdev(values),
        "ewma": st.ewma(values),
        "median": baseline.median,
        "mad": baseline.mad,
        "robust_z": baseline.modified_zscore(values[-1]),
        "trend_slope": trend.slope,
        "trend_r2": trend.r2,
        "cov": st.coefficient_of_variation(values),
        "n": float(len(values)),
    }


# --- backend -----------------------------------------------------------------


class InferenceBackend(Protocol):
    """Anything that turns features into a prediction.

    Return a dict with at least ``value``; ``state``/``confidence``/``method``/
    ``detail`` are optional. Return ``None`` to abstain (caller falls back).
    """

    def predict(self, metric: str, features: dict[str, float]) -> dict[str, Any] | None: ...


class BedrockInferenceBackend:
    """Invoke a hosted model (SageMaker endpoint) for a prediction.

    Lazily imports boto3 like the AI router, is gated on ``BIOMETRICS_MODEL_ENDPOINT``,
    and returns ``None`` on any failure so the estimator falls back cleanly.
    Inert until an endpoint is configured — safe to construct anywhere.
    """

    def __init__(self, endpoint_name: str | None = None, region_name: str | None = None) -> None:
        self.endpoint_name = endpoint_name or os.getenv("BIOMETRICS_MODEL_ENDPOINT")
        self.region_name = region_name or os.getenv("AWS_REGION") or "us-east-1"
        self._client = None

    def predict(self, metric: str, features: dict[str, float]) -> dict[str, Any] | None:
        if not self.endpoint_name:
            return None
        try:
            import json

            client = self._runtime()
            response = client.invoke_endpoint(
                EndpointName=self.endpoint_name,
                ContentType="application/json",
                Body=json.dumps({"metric": metric, "features": features}),
            )
            payload = json.loads(response["Body"].read())
            return payload if isinstance(payload, dict) and payload.get("value") is not None else None
        except Exception:
            return None

    def _runtime(self):
        if self._client is None:
            import boto3  # type: ignore[import]

            self._client = boto3.client("sagemaker-runtime", region_name=self.region_name)
        return self._client


def resolve_backend() -> InferenceBackend | None:
    """The configured backend, or None when no model endpoint is set."""
    if os.getenv("BIOMETRICS_MODEL_ENDPOINT"):
        return BedrockInferenceBackend()
    return None


# --- model estimator ---------------------------------------------------------


class ModelEstimator:
    """Estimator backed by a trained model, with a statistical fallback."""

    def __init__(self, metric: MetricType, backend: InferenceBackend, fallback: Estimator | None = None) -> None:
        self.metric = metric
        self.backend = backend
        self.fallback = fallback or BaselineEstimator(metric)

    def estimate(self, values: list[float]) -> Estimate:
        if not values:
            return self.fallback.estimate(values)
        try:
            prediction = self.backend.predict(self.metric.value, feature_vector(self.metric, values))
        except Exception:
            prediction = None
        if not prediction or prediction.get("value") is None:
            return self.fallback.estimate(values)
        return Estimate(
            name=self.metric.value,
            value=prediction["value"],
            state=str(prediction.get("state", "modeled")),
            confidence=float(prediction.get("confidence", 0.8)),
            method=str(prediction.get("method") or "model:inference"),
            detail=str(prediction.get("detail") or f"model prediction for {self.metric.value}"),
        )


def enable_model_estimators(
    backend: InferenceBackend | None = None,
    metrics: list[MetricType] | None = None,
) -> list[MetricType]:
    """Route the given metrics (default: all) through the model path.

    No-op when no backend is configured, so this is safe to call at startup.
    Returns the metrics actually switched over.
    """
    from . import estimators

    backend = backend or resolve_backend()
    if backend is None:
        return []
    targets = metrics or list(MetricType)
    for metric in targets:
        estimators.set_estimator(metric, ModelEstimator(metric, backend))
    return targets
