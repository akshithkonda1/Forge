"""Tests for aria_core.sleep_depth_scorer, the Python port of ForgeCore's
SleepDepthScorer.swift (task #13 of the Swift->Python port list -- see
ARIA_INTELLIGENCE_PLAN.md). Translated directly from
SleepDepthScorerTests.swift's SleepDepthScorerTests class, checked against
the same fixtures and expected values (the OnlineStat-specific tests from
that file live in test_biometrics.py's StatisticsTests, next to the fix
they cover).
"""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core import sleep_depth_scorer as sds  # noqa: E402


def _bear() -> sds.SleepChronotypeTargets:
    return sds.SleepChronotypeTargets(target_hours=8, deep_goal_minutes=90, rem_goal_minutes=90)


def _typical_night(hours: float = 8, deep: float = 90, rem: float = 90,
                    efficiency: float = 90, consistency: float = 80) -> sds.SleepNightMetrics:
    return sds.SleepNightMetrics(
        total_hours=hours, deep_minutes=deep, rem_minutes=rem,
        efficiency_percent=efficiency, wake_consistency=consistency,
    )


class ColdStartTests(unittest.TestCase):
    def test_cold_start_matches_chronotype_formula(self):
        metrics = _typical_night(hours=8, deep=90, rem=90, efficiency=90, consistency=80)
        bear = _bear()
        chrono = sds.chronotype_score(metrics, bear)
        result = sds.score(metrics, bear, sds.SleepDepthBaselines())
        self.assertEqual(result.score, chrono)
        self.assertEqual(result.personal_blend, 0)
        self.assertEqual(result.source, "chronotype")
        self.assertEqual(result.unusual_flags, [])
        self.assertGreaterEqual(chrono, 90)


class EfficiencyTests(unittest.TestCase):
    def test_honest_efficiency_uses_time_in_bed(self):
        percent = sds.efficiency_percent(asleep_hours=7, awake_minutes=60)
        self.assertAlmostEqual(percent, 87.5, places=2)


class ObserveTests(unittest.TestCase):
    def test_idempotent_for_the_same_night(self):
        baselines = sds.SleepDepthBaselines()
        night = _typical_night()
        sds.observe(baselines, night, "2026-09-01")
        sds.observe(baselines, _typical_night(hours=5), "2026-09-01")
        self.assertEqual(baselines.sample_count, 1)
        self.assertEqual(baselines.duration.last, 8)


class UnusualFlagTests(unittest.TestCase):
    def test_short_night_is_unusual_after_a_stable_baseline(self):
        baselines = sds.SleepDepthBaselines()
        bear = _bear()
        for day in range(1, 11):
            sds.observe(baselines, _typical_night(hours=8, deep=90, rem=90, efficiency=92),
                        f"2026-09-{day:02d}")
        short = _typical_night(hours=5.0, deep=40, rem=40, efficiency=70)
        result = sds.score(short, bear, baselines)
        self.assertGreater(result.personal_blend, 0)
        self.assertTrue(result.unusual_flags, result.unusual_flags)
        self.assertTrue(any("shorter" in f.lower() for f in result.unusual_flags), result.unusual_flags)
        self.assertLess(result.score, sds.chronotype_score(short, bear) + 5)

    def test_typical_night_against_self_is_not_flagged(self):
        baselines = sds.SleepDepthBaselines()
        bear = _bear()
        for day in range(1, 9):
            sds.observe(baselines, _typical_night(hours=7.8 + (day % 2) * 0.2), f"2026-09-{day:02d}")
        result = sds.score(_typical_night(hours=7.9), bear, baselines)
        self.assertEqual(result.unusual_flags, [], result.unusual_flags)

    def test_flags_stay_qualitative_with_no_stage_percent(self):
        baselines = sds.SleepDepthBaselines()
        bear = _bear()
        for day in range(1, 11):
            sds.observe(baselines, _typical_night(hours=8, deep=90, rem=90, efficiency=92),
                        f"2026-09-{day:02d}")
        short = _typical_night(hours=5.0, deep=40, rem=40, efficiency=70)
        result = sds.score(short, bear, baselines)
        blob = " ".join(result.unusual_flags)
        self.assertNotIn("%", blob)
        import re
        self.assertIsNone(re.search(r"\b(?:deep|rem|light)\s+sleep\s+at\s+\d", blob, re.IGNORECASE))


class BlendAndSourceTests(unittest.TestCase):
    """Not directly in the Swift suite, but the blend/source contract
    (Swift L118-134) deserves its own coverage: 0 below cold start, linear
    ramp to 1 at full-personal, and the source label tracking it."""

    def _baselines_with_n(self, n: int) -> sds.SleepDepthBaselines:
        baselines = sds.SleepDepthBaselines()
        for day in range(1, n + 1):
            sds.observe(baselines, _typical_night(), f"2026-01-{day:02d}")
        return baselines

    def test_blend_is_zero_below_cold_start(self):
        baselines = self._baselines_with_n(sds.COLD_START_NIGHTS - 1)
        result = sds.score(_typical_night(), _bear(), baselines)
        self.assertEqual(result.personal_blend, 0.0)
        self.assertEqual(result.source, "chronotype")

    def test_blend_is_one_at_full_personal_nights(self):
        baselines = self._baselines_with_n(sds.FULL_PERSONAL_NIGHTS)
        result = sds.score(_typical_night(), _bear(), baselines)
        self.assertEqual(result.personal_blend, 1.0)
        self.assertEqual(result.source, "personal")

    def test_blend_is_between_at_the_midpoint(self):
        midpoint = (sds.COLD_START_NIGHTS + sds.FULL_PERSONAL_NIGHTS) // 2
        baselines = self._baselines_with_n(midpoint)
        result = sds.score(_typical_night(), _bear(), baselines)
        self.assertGreater(result.personal_blend, 0.0)
        self.assertLess(result.personal_blend, 1.0)
        self.assertEqual(result.source, "blended")


class ObservedKeyCapTests(unittest.TestCase):
    def test_key_list_caps_and_drops_oldest(self):
        baselines = sds.SleepDepthBaselines()
        for day in range(1, sds.OBSERVED_KEY_CAP + 11):
            sds.observe(baselines, _typical_night(), f"night-{day}")
        self.assertEqual(len(baselines.observed_night_keys), sds.OBSERVED_KEY_CAP)
        self.assertNotIn("night-1", baselines.observed_night_keys)
        self.assertIn(f"night-{sds.OBSERVED_KEY_CAP + 10}", baselines.observed_night_keys)
        # Sample count itself is never capped -- only the dedup-key list is.
        self.assertEqual(baselines.sample_count, sds.OBSERVED_KEY_CAP + 10)


class HeadlineTests(unittest.TestCase):
    def test_headline_is_first_flag_or_none(self):
        self.assertIsNone(sds.SleepDepthResult(score=90, personal_blend=0, unusual_flags=[],
                                                source="chronotype").headline)
        flagged = sds.SleepDepthResult(score=70, personal_blend=1, unusual_flags=["a", "b"], source="personal")
        self.assertEqual(flagged.headline, "a")


class SwiftRoundingParityTests(unittest.TestCase):
    def test_rounds_half_away_from_zero(self):
        self.assertEqual(sds._swift_round(2.5), 3)
        self.assertEqual(sds._swift_round(-2.5), -3)
        self.assertEqual(sds._swift_round(0.4), 0)


if __name__ == "__main__":
    unittest.main()
