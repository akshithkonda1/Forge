"""Stability analyzer — aggregate EvaluationResults into stability metrics."""

from __future__ import annotations

from dataclasses import dataclass, field

from .aria_evaluator import DimensionScores, EvaluationResult, grade


@dataclass
class TierSummary:
    tier: int
    run_count: int
    avg_composite: float
    grade: str
    pass_rate: float       # % of runs scoring >= 72 (B threshold)
    failure_count: int     # runs scoring < 72


@dataclass
class StabilityReport:
    total_runs: int
    by_tier: dict[int, TierSummary]
    overall_composite: float
    overall_grade: str
    dimension_averages: DimensionScores
    critical_failures: list[str]
    top_failure_patterns: list[str]
    top_recommendations: list[str]
    consumer_stability_grade: str
    epistemic_rigor_grade: str
    models_used: dict[str, int] = field(default_factory=dict)


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _top(items: list[str], n: int) -> list[str]:
    counts: dict[str, int] = {}
    first_seen: dict[str, int] = {}
    for index, item in enumerate(items):
        if item not in counts:
            first_seen[item] = index
            counts[item] = 0
        counts[item] += 1
    ranked = sorted(counts, key=lambda k: (-counts[k], first_seen[k]))
    return [f"{key}  (×{counts[key]})" for key in ranked[:n]]


def _latency_score(latency_ms: float) -> float:
    return max(0.0, min(100.0, 100.0 - (latency_ms - 500.0) / 20.0))


def analyze(results: list[EvaluationResult]) -> StabilityReport:
    if not results:
        zero = DimensionScores(0, 0, 0, 0, 0, 0)
        return StabilityReport(0, {}, 0.0, "F", zero, [], [], [], "F", "F")

    composites = [r.composite_score for r in results]
    overall = round(_mean(composites), 1)

    dims = DimensionScores(
        context_utilization=round(_mean([r.scores.context_utilization for r in results]), 1),
        directional_correctness=round(_mean([r.scores.directional_correctness for r in results]), 1),
        chronotype_alignment=round(_mean([r.scores.chronotype_alignment for r in results]), 1),
        actionability=round(_mean([r.scores.actionability for r in results]), 1),
        epistemic_honesty=round(_mean([r.scores.epistemic_honesty for r in results]), 1),
        tone_compliance=round(_mean([r.scores.tone_compliance for r in results]), 1),
    )

    by_tier: dict[int, TierSummary] = {}
    for tier in sorted({r.tier for r in results}):
        tier_results = [r for r in results if r.tier == tier]
        tier_comps = [r.composite_score for r in tier_results]
        passes = sum(1 for c in tier_comps if c >= 72)
        avg = round(_mean(tier_comps), 1)
        by_tier[tier] = TierSummary(
            tier=tier, run_count=len(tier_results), avg_composite=avg, grade=grade(avg),
            pass_rate=round(100.0 * passes / len(tier_results), 1),
            failure_count=len(tier_results) - passes,
        )

    critical_failures = [
        f"[Tier {r.tier}] composite {r.composite_score} — query: {r.query!r} | "
        f"readiness={r.context_snapshot['readiness']}, acwr={r.context_snapshot['acwr']} | "
        + "; ".join(f for f in r.failures if "Directional correctness" in f)
        for r in results
        if r.scores.directional_correctness == 0.0
    ]

    all_failures = [f for r in results for f in r.failures]
    all_recs = [rec for r in results for rec in r.recommendations]

    consumer = round(_mean([
        0.4 * r.scores.actionability + 0.3 * r.scores.tone_compliance
        + 0.3 * _latency_score(r.response.latency_ms)
        for r in results
    ]), 1)
    epistemic = round(_mean([
        0.6 * r.scores.directional_correctness + 0.4 * r.scores.epistemic_honesty
        for r in results
    ]), 1)

    models_used: dict[str, int] = {}
    for r in results:
        mid = r.response.model_used
        models_used[mid] = models_used.get(mid, 0) + 1

    return StabilityReport(
        total_runs=len(results), by_tier=by_tier,
        overall_composite=overall, overall_grade=grade(overall),
        dimension_averages=dims,
        critical_failures=critical_failures,
        top_failure_patterns=_top([_generalize(f) for f in all_failures], 5),
        top_recommendations=_top(all_recs, 5),
        consumer_stability_grade=grade(consumer),
        epistemic_rigor_grade=grade(epistemic),
        models_used=models_used,
    )


def _generalize(failure: str) -> str:
    """Strip run-specific numbers so patterns aggregate."""
    import re
    head = failure.split(":", 1)[0]
    detail = failure.split(":", 1)[1] if ":" in failure else ""
    detail = re.sub(r"=\-?\d+(\.\d+)?", "=N", detail)
    detail = re.sub(r"\d+(\.\d+)?h", "Nh", detail)
    return (head + ":" + detail).strip() if detail else head
