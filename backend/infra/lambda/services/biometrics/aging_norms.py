"""Public cardiorespiratory-fitness norms for training age.

Lifestyle comparison only — never a medical biological-age diagnosis.

The FRIEND-style 50th-percentile VO₂ table is always available (accuracy
without a network). A successful fetch of a curated .gov / MedlinePlus
page marks ``web_confirmed`` so fitness-age confidence rises. Fail-open:
timeouts, unittest (unless ``FORGE_AGING_WEB=1``), and blocked egress
leave the on-device table untouched.
"""

from __future__ import annotations

import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# MedlinePlus VO2 / stress-test page + CDC intensity — same URLs as
# ``AriaReferenceCatalog`` aging sources on iOS.
CONFIRM_URLS: tuple[tuple[str, str], ...] = (
    (
        "MedlinePlus: Exercise Stress Test / VO2",
        "https://medlineplus.gov/ency/article/003394.htm",
    ),
    (
        "CDC: Measuring Physical Activity Intensity",
        "https://www.cdc.gov/physical-activity-basics/measuring/index.html",
    ),
)

# FRIEND-style 50th-percentile VO₂ (ml/kg/min) by age band.
_MALE_BANDS = ((20, 47.6), (30, 42.8), (40, 37.8), (50, 32.6), (60, 28.2), (70, 23.1))
_FEMALE_BANDS = ((20, 37.6), (30, 31.0), (40, 27.4), (50, 24.2), (60, 20.7), (70, 18.3))
_MIXED_BANDS = ((20, 42.6), (30, 36.9), (40, 32.6), (50, 28.4), (60, 24.5), (70, 20.7))

_web_confirmed = False
_web_source_title: str | None = None
_attempted = False


def web_confirmed() -> bool:
    return _web_confirmed


def web_source_title() -> str | None:
    return _web_source_title


def fitness_confidence() -> float:
    return 0.72 if _web_confirmed else 0.58


def mark_web_confirmed(title: str = "MedlinePlus: Exercise Stress Test / VO2") -> None:
    global _web_confirmed, _web_source_title
    _web_confirmed = True
    _web_source_title = title


def reset_for_tests() -> None:
    global _web_confirmed, _web_source_title, _attempted
    _web_confirmed = False
    _web_source_title = None
    _attempted = False


def _interpolate(age: float, table: tuple[tuple[float, float], ...]) -> float:
    if age <= table[0][0]:
        return table[0][1]
    if age >= table[-1][0]:
        return table[-1][1]
    for left, right in zip(table, table[1:]):
        if age <= right[0]:
            t = (age - left[0]) / (right[0] - left[0])
            return round(left[1] + (right[1] - left[1]) * t, 1)
    return table[-1][1]


def expected_vo2(age_years: float, sex_female: bool | None = None) -> float:
    """FRIEND-style 50th-percentile VO₂ (ml/kg/min) at a calendar age."""
    age = max(18.0, age_years)
    if sex_female is True:
        table = _FEMALE_BANDS
    elif sex_female is False:
        table = _MALE_BANDS
    else:
        table = _MIXED_BANDS
    return _interpolate(age, table)


def _running_under_unittest() -> bool:
    return "unittest" in sys.modules and not os.environ.get("FORGE_AGING_WEB")


def confirm(*, timeout: float = 4.0) -> bool:
    """Fetch a public cardio-fitness page. Fail-open. Cached per process."""
    global _attempted
    if _web_confirmed:
        return True
    if _attempted or _running_under_unittest():
        return False
    _attempted = True
    for title, url in CONFIRM_URLS:
        try:
            request = Request(url, headers={"User-Agent": "Forge-AgingNorms/1.0"})
            with urlopen(request, timeout=timeout) as response:
                status = getattr(response, "status", 200)
                if status != 200:
                    continue
                body = response.read(12000).decode("utf-8", errors="replace").lower()
            if any(token in body for token in ("vo2", "oxygen", "intensity", "physical activity")):
                mark_web_confirmed(title)
                return True
        except (HTTPError, URLError, TimeoutError, OSError, ValueError):
            continue
    return False
