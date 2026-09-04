"""Tiny stdlib statistics for multi-seed confidence (no numpy)."""

from __future__ import annotations

import math
from dataclasses import dataclass


def mean(xs: list[float]) -> float:
    return sum(xs) / len(xs) if xs else 0.0


def stdev(xs: list[float]) -> float:
    n = len(xs)
    if n < 2:
        return 0.0
    mu = mean(xs)
    return math.sqrt(sum((x - mu) ** 2 for x in xs) / (n - 1))


def percentile(xs: list[float], pct: float) -> float:
    if not xs:
        return 0.0
    s = sorted(xs)
    if len(s) == 1:
        return s[0]
    rank = (pct / 100.0) * (len(s) - 1)
    lo, hi = int(math.floor(rank)), int(math.ceil(rank))
    if lo == hi:
        return s[lo]
    return s[lo] + (s[hi] - s[lo]) * (rank - lo)


def coefficient_of_variation(xs: list[float]) -> float:
    mu = mean(xs)
    return stdev(xs) / mu if abs(mu) > 1e-9 else 0.0


@dataclass
class Distribution:
    mean: float
    stdev: float
    min: float
    max: float
    p10: float
    p90: float
    n: int
    cv: float
    stable: bool   # low relative variance


def summarize(xs: list[float], stable_cv: float = 0.10) -> Distribution:
    if not xs:
        return Distribution(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0.0, True)
    cv = coefficient_of_variation(xs)
    return Distribution(
        mean=round(mean(xs), 1), stdev=round(stdev(xs), 2),
        min=round(min(xs), 1), max=round(max(xs), 1),
        p10=round(percentile(xs, 10), 1), p90=round(percentile(xs, 90), 1),
        n=len(xs), cv=round(cv, 3), stable=cv <= stable_cv,
    )
