"""Biometrics substrate — classify, model, and fuse health data of any type
from any source into a real-time + over-time picture of how the body functions,
then project it onto the ARIA coaching context.

Pipeline:
    raw samples  ──classify──▶  typed Observations
                 ──BodyModel──▶ per-system state + cross-signal estimates
                 ──snapshot──▶  BodySnapshot (over time and in real time)
                 ──to_aria_context──▶ ARIAContext (permission-aware) ──▶ ARIA
"""

from __future__ import annotations

from .body_model import BodyModel, BodySnapshot, MetricState, SystemState
from .classify import ClassificationResult, Reject, classify_batch, classify_sample
from .estimators import (
    BaselineEstimator,
    Estimate,
    Estimator,
    default_estimator,
    estimate_recovery,
    reset_estimators,
    set_estimator,
)
from .inference import (
    BedrockInferenceBackend,
    InferenceBackend,
    ModelEstimator,
    enable_model_estimators,
    feature_vector,
    resolve_backend,
)
from .types import (
    METRIC_REGISTRY,
    Agg,
    Kind,
    MetricSpec,
    MetricType,
    Observation,
    System,
    metrics_for_system,
    spec,
)

__all__ = [
    "BodyModel",
    "BodySnapshot",
    "MetricState",
    "SystemState",
    "ClassificationResult",
    "Reject",
    "classify_batch",
    "classify_sample",
    "BaselineEstimator",
    "Estimate",
    "Estimator",
    "default_estimator",
    "estimate_recovery",
    "reset_estimators",
    "set_estimator",
    "ModelEstimator",
    "InferenceBackend",
    "BedrockInferenceBackend",
    "enable_model_estimators",
    "feature_vector",
    "resolve_backend",
    "METRIC_REGISTRY",
    "MetricType",
    "MetricSpec",
    "Observation",
    "System",
    "Agg",
    "Kind",
    "metrics_for_system",
    "spec",
]
