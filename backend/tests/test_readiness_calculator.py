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

    def test_good_night_and_recovered_hrv_lands_in_good_or_peak(self):
        score = rc.score(rc.ReadinessInputs(
            hrv_ms=62, hrv_baseline_ms=50,
            resting_hr=50, resting_hr_baseline=54,
            sleep_minutes=8 * 60,
            deep_sleep_minutes=75, rem_sleep_minutes=100,
            yesterday_strain=0.2,
        ))
        self.assertGreaterEqual(score.overall, 70)
        self.assertIn(score.band, (rc.GOOD, rc.PEAK))

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

    def test_band_boundaries_match_home_tokens(self):
        # shared/readiness.json and ReadinessBand in Readiness.swift: 85/70/50.
        self.assertEqual(rc.band_for_score(85), rc.PEAK)
        self.assertEqual(rc.band_for_score(84), rc.GOOD)
        self.assertEqual(rc.band_for_score(70), rc.GOOD)
        self.assertEqual(rc.band_for_score(69), rc.FAIR)
        self.assertEqual(rc.band_for_score(50), rc.FAIR)
        self.assertEqual(rc.band_for_score(49), rc.LOW)
        self.assertEqual(rc.BAND_LABEL[rc.band_for_score(40)], "Low")

    def test_bands_match_shared_readiness_tokens(self):
        import json
        from pathlib import Path

        tokens = json.loads(
            (Path(__file__).resolve().parents[2] / "shared" / "readiness.json").read_text()
        )
        for band in tokens["bands"]:
            self.assertEqual(rc.BAND_MIN_SCORE[band["id"]], band["min"], band["id"])
            self.assertEqual(rc.BAND_LABEL[band["id"]], band["label"], band["id"])


class PersonalNormTests(unittest.TestCase):
    """HRV and resting HR are read against the person's own normal range."""

    def test_at_baseline_hrv_scores_center(self):
        self.assertAlmostEqual(rc.hrv_component(50, 50), rc.HRV_CENTER)
        self.assertAlmostEqual(rc.resting_hr_component(55, 55), rc.RESTING_HR_CENTER)

    def test_hrv_is_symmetric_in_log_space(self):
        # Half and double are equally unusual; a linear % band says otherwise.
        center = rc.HRV_CENTER
        # 40 is 0.8x and 62.5 is 1.25x of 50: equal distance in log space.
        self.assertAlmostEqual(rc.hrv_component(40, 50) + rc.hrv_component(62.5, 50), 2 * center, places=6)

    def test_same_dip_matters_more_for_a_steady_person(self):
        steady = rc.hrv_component(42, 50, baseline_sd_ln=0.10)
        noisy = rc.hrv_component(42, 50, baseline_sd_ln=0.40)
        self.assertLess(steady, noisy)
        steady_rhr = rc.resting_hr_component(58, 54, baseline_sd=2.0)
        noisy_rhr = rc.resting_hr_component(58, 54, baseline_sd=6.0)
        self.assertLess(steady_rhr, noisy_rhr)

    def test_spread_is_clamped(self):
        # A near-zero SD would make a 1 ms wobble look like a crisis.
        tiny = rc.hrv_component(49, 50, baseline_sd_ln=0.001)
        floor = rc.hrv_component(49, 50, baseline_sd_ln=rc.HRV_SD_LN_FLOOR)
        self.assertAlmostEqual(tiny, floor)

    def test_low_hrv_person_at_their_normal_is_not_penalised(self):
        # 22 ms is normal for many people; a population table would call it poor.
        score = rc.score(rc.ReadinessInputs(hrv_ms=22, hrv_baseline_ms=22))
        self.assertEqual(score.overall, 75)

    def test_unknown_or_nonpositive_inputs_are_missing(self):
        self.assertIsNone(rc.hrv_component(0, 50))
        self.assertIsNone(rc.hrv_component(50, 0))
        self.assertIsNone(rc.hrv_component(None, 50))
        self.assertIsNone(rc.resting_hr_component(60, None))

    def test_oversleeping_earns_no_extra_credit(self):
        at_need = rc.score(rc.ReadinessInputs(sleep_minutes=480))
        over = rc.score(rc.ReadinessInputs(sleep_minutes=600))
        self.assertEqual(at_need.sleep_quality, over.sleep_quality)

    def test_personal_baseline_needs_five_real_days(self):
        self.assertIsNone(rc.personal_baseline([50, 52, 0, 48], log_scaled=True))
        base = rc.personal_baseline([40, 50, 60, 50, 50], log_scaled=True)
        self.assertIsNotNone(base)
        self.assertEqual(base.days, 5)
        # Geometric mean sits at or below the arithmetic mean.
        self.assertLessEqual(base.mean, 50.0)
        self.assertGreater(base.spread, 0)

    def test_personal_baseline_linear(self):
        base = rc.personal_baseline([54, 55, 56, 55, 55], log_scaled=False)
        self.assertAlmostEqual(base.mean, 55.0)
        self.assertAlmostEqual(base.spread, (2 / 4) ** 0.5)

    def test_swift_parity_vectors(self):
        # Same vectors as ReadinessCalculatorTests.testParityVectors in Swift.
        cases = [
            (rc.ReadinessInputs(hrv_ms=62, hrv_baseline_ms=50, resting_hr=50, resting_hr_baseline=54,
                                sleep_minutes=480, deep_sleep_minutes=75, rem_sleep_minutes=100,
                                yesterday_strain=0.2), 95),
            (rc.ReadinessInputs(hrv_ms=34, hrv_baseline_ms=50, resting_hr=62, resting_hr_baseline=54,
                                sleep_minutes=270, deep_sleep_minutes=20, rem_sleep_minutes=30,
                                yesterday_strain=0.9), 49),
            (rc.ReadinessInputs(hrv_ms=45, hrv_baseline_ms=50, hrv_baseline_sd_ln=0.12,
                                resting_hr=57, resting_hr_baseline=54, resting_hr_baseline_sd=2.0,
                                sleep_minutes=420), 71),
        ]
        for inputs, expected in cases:
            self.assertEqual(rc.score(inputs).overall, expected, inputs)

if __name__ == "__main__":
    unittest.main()
