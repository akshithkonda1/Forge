"""Python twin of ForgeCore FakeHealthPack.

Days are oldest-first so SimRunner snapshot_days (7, 14, 21, 29) match
generate_stream. Field names match the Swift pack / fake_health_bridge.
"""

from __future__ import annotations

from datetime import date, timedelta

DAY_COUNT = 30
DEFAULT_SEED = 0xF0A6E
PERSONA_LABELS = (
    "balanced", "athlete", "stressed", "nightOwl", "lightSleeper", "highEnergy",
)

_WORKOUTS = {
    2: ("Lower Body Strength", "strength", 62, "high", 22400),
    4: ("Push / Pull", "strength", 50, "moderate", 16800),
    5: ("Zone 2 + strides", "cardio", 40, "moderate", 0),
}


class _Rng:
    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFFFFFFFFFFFFFF or 0x9E3779B97F4A7C15

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        return z ^ (z >> 31)

    def randint(self, lo: int, hi: int) -> int:
        return lo + (self.next() % (hi - lo + 1))


def generate(
    *,
    today: date | None = None,
    days: int = DAY_COUNT,
    seed: int = DEFAULT_SEED,
    persona: str = "balanced",
) -> dict:
    rng = _Rng(seed)
    count = max(7, days)
    end = today or date(2026, 8, 25)
    built: list[dict] = []
    for age in range(count - 1, -1, -1):
        day = end - timedelta(days=age)
        built.append(_day(offset=age, day=day, rng=rng, persona=persona))
    _stamp_debt(built)
    return {
        "days": built,
        "seed": seed,
        "personaLabel": persona if persona in PERSONA_LABELS else "balanced",
        "generatedOn": end.isoformat(),
    }


def today_day(pack: dict) -> dict:
    return pack["days"][-1]


def _day(*, offset: int, day: date, rng: _Rng, persona: str) -> dict:
    short = offset in (3, 10)
    late = offset == 6
    hard = offset in (1, 8)
    if short:
        asleep = 5 * 60 + rng.randint(20, 50)
    elif late:
        asleep = 6 * 60 + rng.randint(10, 35)
    else:
        asleep = 7 * 60 + rng.randint(5, 50)
    if persona == "athlete":
        asleep += 20
    elif persona in ("stressed", "lightSleeper"):
        asleep -= 25
    asleep = max(4 * 60, asleep)

    deep = max(12, int(asleep * 0.18))
    rem = max(10, int(asleep * 0.16))
    hrv = 52 + rng.randint(-6, 8)
    rhr = 58 + rng.randint(-4, 5)
    if short or hard:
        hrv -= rng.randint(8, 14)
        rhr += rng.randint(3, 7)
    hrv = min(95, max(28, hrv))
    rhr = min(78, max(48, rhr))

    workout = None
    if offset != 0:
        spec = _WORKOUTS.get(offset % 7)
        if spec:
            name, kind, mins, intensity, volume = spec
            workout = {
                "name": name,
                "type": kind,
                "durationMinutes": mins,
                "intensity": intensity,
                "volume": volume,
            }

    steps = 7400 + rng.randint(-1800, 2600)
    calories = 380 + rng.randint(-80, 140)
    if workout:
        steps += 2400 if workout["type"] == "cardio" else 900
        calories += workout["durationMinutes"] * 6
    if offset == 0:
        steps = min(steps, 8600)

    score = min(100, max(40, int((asleep / 480) * 45 + (deep / 90) * 30 + (rem / 90) * 25)))
    return {
        "isoDate": day.isoformat(),
        "sleepMinutes": asleep,
        "night": {
            "totalMinutes": float(asleep),
            "deepMinutes": float(deep),
            "remMinutes": float(rem),
        },
        "sleepScore": score,
        "hrvMs": hrv,
        "restingHR": rhr,
        "steps": max(2000, steps),
        "activeCalories": max(120, calories),
        "hydrationMl": float(1180 + rng.randint(0, 900)),
        "workout": workout,
        "felt": "spent" if short else "steady",
        "storyLine": "",
        "personaLabel": persona,
    }


def _stamp_debt(days: list[dict]) -> None:
    for i, day in enumerate(days):
        window = days[max(0, i - 6) : i + 1]
        debt = 0.0
        for item in window:
            hours = float(item["night"]["totalMinutes"]) / 60.0
            debt += max(0.0, 8.0 - hours)
        day["sleepDebtHours"] = round(debt, 2)
        hrvs = [d["hrvMs"] for d in window]
        day["hrv7dAvg"] = round(sum(hrvs) / len(hrvs), 1)
        day["hrvTrend"] = "falling" if hrvs[-1] < hrvs[0] - 4 else "stable"
        scores = [d["sleepScore"] for d in window]
        day["readiness7dAvg"] = round(sum(scores) / len(scores), 1)
        day["readinessTrend"] = "stable"
