"""services.readiness.compute_readiness and services.scoring.training_load_trend.

The dashboard number is the same formula as the Watch/Home glance, read
against the person's own earlier nights — not population HRV cutoffs, not a
stand-in score for a night with no data.
"""

from __future__ import annotations

import unittest
from datetime import date

import _bootstrap  # noqa: F401

from aria_core import readiness_calculator as rc  # noqa: E402
from services import readiness, scoring  # noqa: E402


def _night(day: str, hours: float | None = 7.5, hrv: float | None = None, rhr: float | None = None, **extra):
    row = {"date": day}
    if hours is not None:
        row["totalHours"] = hours
    if hrv is not None:
        row["hrv"] = hrv
    if rhr is not None:
        row["restingHR"] = rhr
    row.update(extra)
    return row


class DashboardReadinessTests(unittest.TestCase):
    def test_matches_the_shared_calculator(self):
        rows = [_night("2026-10-09", hours=7.0, deepMinutes=55, remMinutes=80)]
        result = readiness.compute_readiness(rows)
        expected = rc.score(rc.ReadinessInputs(
            sleep_minutes=420, deep_sleep_minutes=55, rem_sleep_minutes=80,
        ))
        self.assertEqual(result["overall"], expected.overall)
        self.assertEqual(result["sleepQuality"], expected.sleep_quality)
        self.assertTrue(result["available"])

    def test_low_hrv_person_at_their_normal_is_not_penalised(self):
        # 24 ms every night is this person's normal. The old population
        # cutoff (<35 ms) docked them up to 10 points every single day; now a
        # 24 ms person and a 60 ms person at their own normals read the same.
        def at_normal(level: float) -> dict:
            history = [_night(f"2026-10-0{d}", hrv=level * (1 + ((d % 3) - 1) * 0.04)) for d in range(1, 9)]
            return readiness.compute_readiness([_night("2026-10-09", hrv=level)] + history)

        low, high = at_normal(24), at_normal(60)
        self.assertEqual(low["recoveryScore"], high["recoveryScore"])
        self.assertEqual(low["overall"], high["overall"])
        self.assertLessEqual(abs(low["recoveryScore"] - rc.HRV_CENTER), 2)
        self.assertIsNotNone(low["stressLevel"])

    def test_hrv_dip_against_own_history_lowers_recovery(self):
        history = [_night(f"2026-10-0{d}", hrv=60, rhr=52) for d in range(1, 9)]
        normal = readiness.compute_readiness([_night("2026-10-09", hrv=60, rhr=52)] + history)
        dipped = readiness.compute_readiness([_night("2026-10-09", hrv=40, rhr=58)] + history)
        self.assertLess(dipped["recoveryScore"], normal["recoveryScore"])
        self.assertLess(dipped["overall"], normal["overall"])

    def test_night_without_measurements_is_unavailable_not_75(self):
        result = readiness.compute_readiness([{"date": "2026-10-09", "score": None}])
        self.assertFalse(result["available"])
        self.assertIsNone(result["overall"])

    def test_no_physiology_means_no_derived_stress(self):
        result = readiness.compute_readiness([_night("2026-10-09")])
        self.assertIsNone(result["stressLevel"])

    def test_empty_records(self):
        self.assertFalse(readiness.compute_readiness([])["available"])


class TrainingLoadTrendWindowTests(unittest.TestCase):
    def test_windows_are_days_not_session_counts(self):
        # Two sessions a day for four days: all inside the last 7 days.
        today = date(2026, 10, 10)
        workouts = []
        for back in range(4):
            day = f"2026-10-{10 - back:02d}"
            workouts += [
                {"date": day, "duration": 30, "intensity": "moderate"},
                {"date": day, "duration": 30, "intensity": "moderate"},
            ]
        result = scoring.training_load_trend(workouts, today=today)
        self.assertEqual(result["current"], 8 * 45)
        self.assertEqual(result["previous"], 0)

    def test_quiet_week_counts_as_quiet(self):
        today = date(2026, 10, 10)
        workouts = [
            {"date": "2026-10-01", "duration": 60, "intensity": "high"},
            {"date": "2026-09-30", "duration": 60, "intensity": "high"},
        ]
        result = scoring.training_load_trend(workouts, today=today)
        self.assertEqual(result["current"], 0)
        self.assertEqual(result["previous"], 240)
        self.assertEqual(result["trend"], "falling")

    def test_undated_logs_fall_back_to_session_order(self):
        workouts = [{"duration": 60, "intensity": "high"}] * 7 + [{"duration": 30, "intensity": "low"}] * 2
        result = scoring.training_load_trend(workouts)
        self.assertEqual(result["trend"], "rising")


if __name__ == "__main__":
    unittest.main()
