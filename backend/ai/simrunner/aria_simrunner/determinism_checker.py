"""Determinism checker — semantic (not byte-level) consistency across 3 runs.

For each sampled prompt, run the engine 3× at the same seed. A semantic match
requires identical grade AND identical query-type classification AND directional
scores within 10 points. Reports the aggregate match rate (target ≥ 80%).
"""

from __future__ import annotations

from dataclasses import dataclass

from ..backend_simulator.data_generator import ARIAContext
from .aria_engine import ARIAEngine
from .aria_evaluator import evaluate


@dataclass
class DeterminismReport:
    semantic_determinism_rate: float
    sample_count: int
    runs_per_sample: int
    inconsistent: list[str]
    by_tier: dict[int, float]


def check_determinism(
    engine: ARIAEngine,
    samples: list[tuple[int, str, ARIAContext]],
    runs: int = 3,
    seed: int = 42,
) -> DeterminismReport:
    matches = 0
    inconsistent: list[str] = []
    tier_total: dict[int, int] = {}
    tier_match: dict[int, int] = {}

    for tier, query, context in samples:
        grades: set[str] = set()
        qtypes: set[str] = set()
        directionals: list[float] = []
        for _ in range(runs):
            response = engine.respond(query, context, seed=seed)
            result = evaluate(0, query, tier, context, response)
            grades.add(result.grade)
            qtypes.add(result.response.query_type)
            directionals.append(result.scores.directional_correctness)

        spread = (max(directionals) - min(directionals)) if directionals else 0.0
        consistent = len(grades) == 1 and len(qtypes) == 1 and spread <= 10.0

        tier_total[tier] = tier_total.get(tier, 0) + 1
        if consistent:
            matches += 1
            tier_match[tier] = tier_match.get(tier, 0) + 1
        else:
            inconsistent.append(
                f"[Tier {tier}] {query!r}: grades={sorted(grades)}, "
                f"query_types={sorted(qtypes)}, directional spread={spread:.0f}"
            )

    rate = round(100.0 * matches / len(samples), 1) if samples else 0.0
    by_tier = {t: round(100.0 * tier_match.get(t, 0) / tier_total[t], 1) for t in sorted(tier_total)}
    return DeterminismReport(rate, len(samples), runs, inconsistent, by_tier)
