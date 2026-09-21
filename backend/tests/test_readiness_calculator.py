"""Tests for aria_core.readiness_calculator, the Python port of ForgeCore's
ReadinessCalculator. Translated from ReadinessCalculatorTests.swift.
"""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core import readiness_calculator as rc  # noqa: E402


class ReadinessCalculatorTests(unittest.TestCase):
    def test_no_data_produces_zero_confidence(self):
        score = rc.score(rc.ReadinessInputs())
        self.assertEqual(score.confidence, 0)
        self.assertEqual(score.overall, 0)

    def test_full_data_produces_full_confidence(self):
        score = rc.score(rc.ReadinessInputs(
            hrv_ms=55, hrv_baseline_ms=50,
            resting_hr=52, resting_hr_baseline=54,
            sleep_minutes=7.5 * 60,
            deep_sleep_minutes=70, rem_sleep_minutes=95,
            yesterday_strain=0.4,
        ))
        self.assertAlmostEqual(score.confidence, 1.0, places=3)
        self.assertTrue(0 <= score.overall <= 100)

    def test_good_night_and_recovered_hrv_lands_in_ready_or_primed(self):
        score = rc.score(rc.ReadinessInputs(
            hrv_ms=62, hrv_baseline_ms=50,
            resting_hr=50, resting_hr_baseline=54,
            sleep_minutes=8 * 60,
            deep_sleep_minutes=75, rem_sleep_minutes=100,
            yesterday_strain=0.2,
        ))
        self.assertGreaterEqual(score.overall, 70)
        self.assertIn(score.band, (rc.READY, rc.PRIMED))

    def test_short_sleep_and_suppressed_hrv_lands_low(self):
        score = rc.score(rc.ReadinessInputs(
            hrv_ms=34, hrv_baseline_ms=50,
            resting_hr=62, resting_hr_baseline=54,
            sleep_minutes=4.5 * 60,
            deep_sleep_minutes=20, rem_sleep_minutes=30,
            yesterday_strain=0.9,
        ))
        self.assertLess(score.overall, 60)

    def test_missing_data_lowers_confidence_not_score(self):
        full = rc.score(rc.ReadinessInputs(
            hrv_ms=55, hrv_baseline_ms=50,
            sleep_minutes=8 * 60, deep_sleep_minutes=70, rem_sleep_minutes=95,
        ))
        sleep_only = rc.score(rc.ReadinessInputs(
            sleep_minutes=8 * 60, deep_sleep_minutes=70, rem_sleep_minutes=95,
        ))
        self.assertLess(sleep_only.confidence, full.confidence)
        self.assertGreaterEqual(sleep_only.sleep_quality, 85)

    def test_scores_always_clamped_to_0_through_100(self):
        extreme = rc.score(rc.ReadinessInputs(
            hrv_ms=200, hrv_baseline_ms=20,
            resting_hr=30, resting_hr_baseline=90,
            sleep_minutes=14 * 60,
            deep_sleep_minutes=300, rem_sleep_minutes=300,
            yesterday_strain=0,
        ))
        self.assertTrue(0 <= extreme.overall <= 100)
        self.assertTrue(0 <= extreme.sleep_quality <= 100)
        self.assertTrue(0 <= extreme.recovery <= 100)

    def test_band_boundaries_match_ios_theme(self):
        self.assertEqual(rc.band_for_score(85), rc.PRIMED)
        self.assertEqual(rc.band_for_score(84), rc.READY)
        self.assertEqual(rc.band_for_score(70), rc.READY)
        self.assertEqual(rc.band_for_score(69), rc.MODERATE)
        self.assertEqual(rc.band_for_score(55), rc.MODERATE)
        self.assertEqual(rc.band_for_score(54), rc.RECOVERY)


if __name__ == "__main__":
    unittest.main()
