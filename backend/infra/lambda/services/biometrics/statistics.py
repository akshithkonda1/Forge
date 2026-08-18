"""Dependency-free statistical toolkit — the "statistical variation" engine.

Pure-stdlib estimators so the Lambda needs no numpy/scipy: rolling and robust
baselines, z-scores, least-squares trend, coefficient of variation, and an
``OnlineStat`` for the real-time path (Welford running moments + EWMA), which
updates in O(1) as each new sample streams in.
"""

from __future__ import annotations

import math
from dataclasses import dataclass


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def stdev(values: list[float]) -> float:
    """Sample standard deviation (n-1). 0 for fewer than two points."""
    n = len(values)
    if n < 2:
        return 0.0
    mu = mean(values)
    return math.sqrt(sum((v - mu) ** 2 for v in values) / (n - 1))


def zscore(value: float, mu: float, sigma: float) -> float:
    return (value - mu) / sigma if sigma > 1e-9 else 0.0


def coefficient_of_variation(values: list[float]) -> float:
    """SD / mean — scale-free variability. 0 when mean is ~0."""
    mu = mean(values)
    return stdev(values) / mu if abs(mu) > 1e-9 else 0.0


def percentile(values: list[float], pct: float) -> float:
    """Linear-interpolation percentile (pct in 0..100)."""
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (pct / 100.0) * (len(ordered) - 1)
    low = int(math.floor(rank))
    high = int(math.ceil(rank))
    if low == high:
        return ordered[low]
    return ordered[low] + (ordered[high] - ordered[low]) * (rank - low)


def median(values: list[float]) -> float:
    return percentile(values, 50.0)


@dataclass
class Baseline:
    median: float
    mad: float          # median absolute deviation (robust spread)
    n: int
    mean_ad: float = 0.0  # mean absolute deviation — fallback when MAD collapses to 0

    def modified_zscore(self, value: float) -> float:
        """Iglewicz–Hoaglin robust z-score.

        1.4826·MAD is a consistent sigma estimator; when MAD is 0 (a flat
        baseline) we fall back to 1.2533·MeanAD so a real outlier is still
        caught instead of dividing by zero and reporting nothing.
        """
        if self.mad > 1e-9:
            scaled = 1.4826 * self.mad
        elif self.mean_ad > 1e-9:
            scaled = 1.2533 * self.mean_ad
        else:
            # Zero spread: anything off the median is a hard outlier.
            return 0.0 if abs(value - self.median) < 1e-9 else math.copysign(1e3, value - self.median)
        return (value - self.median) / scaled

    def is_anomaly(self, value: float, threshold: float = 3.5) -> bool:
        return abs(self.modified_zscore(value)) >= threshold


def robust_baseline(values: list[float]) -> Baseline:
    """Median + MAD baseline — resistant to the outliers wearables routinely emit."""
    if not values:
        return Baseline(0.0, 0.0, 0)
    med = median(values)
    abs_dev = [abs(v - med) for v in values]
    return Baseline(med, median(abs_dev), len(values), mean(abs_dev))


def ewma(values: list[float], alpha: float = 0.3) -> float:
    """Exponentially-weighted moving average — recent samples weigh more."""
    if not values:
        return 0.0
    acc = values[0]
    for v in values[1:]:
        acc = alpha * v + (1 - alpha) * acc
    return acc


@dataclass
class Trend:
    slope: float          # units per step
    intercept: float
    r2: float             # goodness of fit, 0..1
    n: int

    @property
    def direction(self) -> str:
        if self.n < 2 or self.r2 < 0.1:
            return "flat"
        return "rising" if self.slope > 0 else "falling" if self.slope < 0 else "flat"


def linear_trend(values: list[float], xs: list[float] | None = None) -> Trend:
    """Ordinary least-squares fit over the series (x defaults to sample index)."""
    n = len(values)
    if n < 2:
        return Trend(0.0, values[0] if values else 0.0, 0.0, n)
    x = xs if xs is not None and len(xs) == n else list(range(n))
    mx, my = mean(x), mean(values)
    sxx = sum((xi - mx) ** 2 for xi in x)
    sxy = sum((xi - mx) * (yi - my) for xi, yi in zip(x, values))
    if sxx <= 1e-12:
        return Trend(0.0, my, 0.0, n)
    slope = sxy / sxx
    intercept = my - slope * mx
    ss_tot = sum((yi - my) ** 2 for yi in values)
    ss_res = sum((yi - (slope * xi + intercept)) ** 2 for xi, yi in zip(x, values))
    r2 = 1 - ss_res / ss_tot if ss_tot > 1e-12 else 1.0
    return Trend(slope, intercept, max(0.0, min(1.0, r2)), n)


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


class OnlineStat:
    """Streaming mean/variance (Welford) + EWMA for the real-time path.

    Update once per incoming sample; read ``mean``/``std``/``ewma`` any time
    without retaining the full series.
    """

    __slots__ = ("n", "_mean", "_m2", "_ewma", "_alpha", "last")

    def __init__(self, alpha: float = 0.3) -> None:
        self.n = 0
        self._mean = 0.0
        self._m2 = 0.0
        self._ewma = 0.0
        self._alpha = alpha
        self.last: float | None = None

    def update(self, value: float) -> "OnlineStat":
        self.n += 1
        delta = value - self._mean
        self._mean += delta / self.n
        self._m2 += delta * (value - self._mean)
        self._ewma = value if self.n == 1 else self._alpha * value + (1 - self._alpha) * self._ewma
        self.last = value
        return self

    @property
    def mean(self) -> float:
        return self._mean

    @property
    def variance(self) -> float:
        return self._m2 / (self.n - 1) if self.n > 1 else 0.0

    @property
    def std(self) -> float:
        return math.sqrt(self.variance)

    @property
    def ewma(self) -> float:
        return self._ewma

    def zscore(self, value: float) -> float:
        return zscore(value, self._mean, self.std)
