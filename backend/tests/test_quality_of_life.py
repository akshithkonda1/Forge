"""Tests for aria_core.quality_of_life, the Python port of ForgeCore's
QualityOfLifeCalculator.swift (task #11 of the Swift->Python port list --
see ARIA_INTELLIGENCE_PLAN.md). Every numeric expectation here was checked
against the Swift source line-for-line (QualityOfLifeCalculator.swift,
HydrationEngine.swift) rather than re-derived from the port itself, so a
transcription slip on either side would fail a test, not just agree with
itself.
"""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core import quality_of_life as qol  # noqa: E402


def _full_inputs(**overrides) -> qol.QualityOfLifeInputs:
    """Every pillar backed by a comfortably "good" value, so overall coverage
    is 1.0 and confidence is high -- a baseline every test can override from."""
    base = dict(
        sleep_hours=8.0,
        deep_sleep_minutes=60.0,
        rem_sleep_minutes=90.0,
        steps=8_000,
        active_calories=500,
        exercise_minutes=30.0,
        protein_grams=130.0,
        total_calories=2_400,
        fiber_grams=30.0,
        added_sugar_grams=0.0,
        water_glasses=11.0,
        hrv_ms=55.0,
        resting_hr=55.0,
        vo2_max=42.5,
        oxygen_saturation_percent=99.0,
        respiratory_rate=15.0,
        mindful_minutes=10.0,
        stress_level_0to1=0.0,
        self_reported_mood_0to10=10.0,
        social_connection_0to10=10.0,
        meaningful_social_interactions=5,
        calendar_busyness_0to1=0.0,
        weekly_mood_0to10=10.0,
        work_strain_0to10=0.0,
    )
    base.update(overrides)
    return qol.QualityOfLifeInputs(**base)


class ResponseCurveTests(unittest.TestCase):
    def test_rising_zero_at_zero_and_below(self):
        self.assertEqual(qol.rising(0), 0.0)
        self.assertEqual(qol.rising(-1), 0.0)

    def test_rising_hits_100_exactly_at_ratio_1(self):
        self.assertEqual(qol.rising(1.0), 100.0)

    def test_rising_soft_caps_overshoot_at_60(self):
        self.assertEqual(qol.rising(10.0), 60.0)
        self.assertAlmostEqual(qol.rising(1.5), 90.0)

    def test_optimum_peaks_at_ratio_1(self):
        self.assertAlmostEqual(qol.optimum(1.0, sigma=0.16), 100.0)

    def test_optimum_falls_off_symmetrically(self):
        under = qol.optimum(0.8, sigma=0.16)
        over = qol.optimum(1.2, sigma=0.16)
        self.assertAlmostEqual(under, over)
        self.assertLess(under, 100.0)

    def test_descending_full_marks_at_zero_zero_at_target(self):
        self.assertEqual(qol.descending(0.0, zero_at=60.0), 100.0)
        self.assertEqual(qol.descending(60.0, zero_at=60.0), 0.0)
        self.assertEqual(qol.descending(30.0, zero_at=60.0), 50.0)

    def test_descending_guards_against_non_positive_zero_at(self):
        self.assertEqual(qol.descending(10.0, zero_at=0.0), 0.0)


class PersonalizedTargetTests(unittest.TestCase):
    def test_sleep_need_prefers_explicit_preference_in_range(self):
        self.assertEqual(qol._sleep_need_hours(age=30, preference=6.5), 6.5)

    def test_sleep_need_ignores_out_of_range_preference(self):
        self.assertEqual(qol._sleep_need_hours(age=30, preference=12.0), 8.0)

    def test_sleep_need_by_age_band(self):
        self.assertEqual(qol._sleep_need_hours(age=None), 8.0)
        self.assertEqual(qol._sleep_need_hours(age=15), 9.0)
        self.assertEqual(qol._sleep_need_hours(age=70), 7.5)
        self.assertEqual(qol._sleep_need_hours(age=40), 8.0)

    def test_protein_target_scales_with_mass_and_floors_at_60(self):
        self.assertEqual(qol._protein_target_grams(50.0), 80.0)
        self.assertEqual(qol._protein_target_grams(10.0), 60.0)
        self.assertEqual(qol._protein_target_grams(None), 130.0)

    def test_calorie_target_scales_with_mass_and_falls_back_by_sex(self):
        self.assertEqual(qol._calorie_target(80.0, None), 2_480.0)
        self.assertEqual(qol._calorie_target(None, True), 2_000.0)
        self.assertEqual(qol._calorie_target(None, False), 2_400.0)
        self.assertEqual(qol._calorie_target(None, None), 2_400.0)


class HydrationTargetParityTests(unittest.TestCase):
    """Mirrors HydrationEngine.targetMilliliters(weightKilograms:)/
    glasses(fromMilliliters:) exactly: mass = max(35, kg ?? 70), target =
    clamp(mass * 33, 1500, 5000), glasses = target / 237."""

    def test_default_weight_70kg(self):
        inputs = _full_inputs(body_mass_kg=None, water_glasses=None)
        target_ml = min(5_000.0, max(1_500.0, 70.0 * 33.0))
        need_glasses = target_ml / 237.0
        result = qol._hydration_pillar(qol.QualityOfLifeInputs(water_glasses=need_glasses))
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result.score, 100.0, places=6)

    def test_light_mass_floors_at_1500ml(self):
        need_glasses = 1_500.0 / 237.0
        result = qol._hydration_pillar(
            qol.QualityOfLifeInputs(water_glasses=need_glasses, body_mass_kg=20.0)
        )
        self.assertAlmostEqual(result.score, 100.0, places=6)

    def test_heavy_mass_caps_at_5000ml(self):
        need_glasses = 5_000.0 / 237.0
        result = qol._hydration_pillar(
            qol.QualityOfLifeInputs(water_glasses=need_glasses, body_mass_kg=500.0)
        )
        self.assertAlmostEqual(result.score, 100.0, places=6)


class SleepPillarGuardTests(unittest.TestCase):
    def test_implausible_hours_ignored_not_zeroed(self):
        self.assertIsNone(qol._sleep_pillar(qol.QualityOfLifeInputs(sleep_hours=0.0)))
        self.assertIsNone(qol._sleep_pillar(qol.QualityOfLifeInputs(sleep_hours=20.0)))
        self.assertIsNone(qol._sleep_pillar(qol.QualityOfLifeInputs(sleep_hours=None)))

    def test_plausible_hours_scored(self):
        result = qol._sleep_pillar(qol.QualityOfLifeInputs(sleep_hours=8.0))
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result.score, 100.0, places=6)

    def test_deep_and_rem_add_depth_but_stay_minor_weight(self):
        base = qol._sleep_pillar(qol.QualityOfLifeInputs(sleep_hours=8.0))
        with_extras = qol._sleep_pillar(
            qol.QualityOfLifeInputs(sleep_hours=8.0, deep_sleep_minutes=60.0, rem_sleep_minutes=90.0)
        )
        self.assertLess(base.depth, with_extras.depth)
        self.assertAlmostEqual(base.score, with_extras.score, places=6)  # all three already at their optimum


class VitalsBaselineScoringTests(unittest.TestCase):
    def test_hrv_scored_against_own_baseline_when_present(self):
        result = qol._vitals_pillar(qol.QualityOfLifeInputs(hrv_ms=71.5, hrv_baseline_ms=55.0))
        self.assertIsNotNone(result)
        # +30% over baseline -> 100 exactly, per the +-30% -> 50..100 model.
        self.assertAlmostEqual(result.score, 100.0, places=1)

    def test_hrv_falls_back_to_population_curve_without_baseline(self):
        with_baseline = qol._vitals_pillar(qol.QualityOfLifeInputs(hrv_ms=55.0, hrv_baseline_ms=55.0))
        without_baseline = qol._vitals_pillar(qol.QualityOfLifeInputs(hrv_ms=55.0))
        # At-baseline (ratio 1.0) scores 75 on the baseline curve, not 100 --
        # a different curve than the population "rising" fallback.
        self.assertNotAlmostEqual(with_baseline.score, without_baseline.score, places=3)

    def test_implausible_vitals_ignored(self):
        result = qol._vitals_pillar(
            qol.QualityOfLifeInputs(hrv_ms=1000.0, resting_hr=5.0, vo2_max=200.0,
                                     oxygen_saturation_percent=10.0, respiratory_rate=1.0)
        )
        self.assertIsNone(result)


class SocialPillarBusynessTests(unittest.TestCase):
    def test_busy_week_with_low_connection_reads_as_strain(self):
        busy_disconnected = qol._social_pillar(
            qol.QualityOfLifeInputs(calendar_busyness_0to1=0.9, social_connection_0to10=1.0)
        )
        busy_connected = qol._social_pillar(
            qol.QualityOfLifeInputs(calendar_busyness_0to1=0.9, social_connection_0to10=10.0)
        )
        self.assertLess(busy_disconnected.score, busy_connected.score)


class BandTests(unittest.TestCase):
    def test_thresholds_match_the_swift_source_and_life_rhythm_band(self):
        # aria_engine.life_rhythm_band already encodes the client-authored
        # thresholds this score mirrors; these must never drift apart.
        self.assertEqual(qol.band_for_score(85), "thriving")
        self.assertEqual(qol.band_for_score(84), "steady")
        self.assertEqual(qol.band_for_score(70), "steady")
        self.assertEqual(qol.band_for_score(69), "strained")
        self.assertEqual(qol.band_for_score(50), "strained")
        self.assertEqual(qol.band_for_score(49), "depleted")
        self.assertEqual(qol.band_for_score(0), "depleted")


class PersonaWeightTests(unittest.TestCase):
    def test_balanced_and_unset_use_population_weights(self):
        for archetype in ("balanced", "unset", "nonsense"):
            self.assertEqual(qol.persona_weight(archetype, qol.SLEEP), 0.22)
            self.assertEqual(qol.persona_weight(archetype, qol.HYDRATION), 0.08)

    def test_archetype_weights_sum_to_one(self):
        for archetype in ("homebody", "outdoors"):
            total = sum(qol.persona_weight(archetype, p) for p in qol.PILLARS)
            self.assertAlmostEqual(total, 1.0, places=9)

    def test_homebody_favors_sleep_and_nutrition_over_activity(self):
        self.assertGreater(qol.persona_weight("homebody", qol.SLEEP), qol.persona_weight("homebody", qol.ACTIVITY))

    def test_outdoors_favors_activity_and_vitals_over_sleep(self):
        self.assertGreater(qol.persona_weight("outdoors", qol.ACTIVITY), qol.persona_weight("outdoors", qol.SLEEP))


class ScoreCoverageTests(unittest.TestCase):
    def test_zero_coverage_is_reported_honestly_not_fabricated(self):
        result = qol.score(qol.QualityOfLifeInputs())
        self.assertEqual(result.overall, 0)
        self.assertEqual(result.raw_overall, 0)
        self.assertEqual(result.confidence, 0.0)
        self.assertEqual(result.pillar_scores, {})
        self.assertEqual(result.graded_aspects, 0)

    def test_full_coverage_of_good_inputs_scores_high_with_high_confidence(self):
        result = qol.score(_full_inputs())
        self.assertGreaterEqual(result.overall, 90)
        self.assertGreaterEqual(result.confidence, 0.9)
        self.assertEqual(result.graded_aspects, 7)
        self.assertEqual(result.band, "thriving")

    def test_missing_pillar_redistributes_weight_not_zero_fills(self):
        """Dropping hydration (a real signal, not implausible) should not drag
        the overall down toward zero -- the remaining six pillars renormalize
        over the coverage they actually have."""
        full = qol.score(_full_inputs())
        without_hydration = qol.score(_full_inputs(water_glasses=None))
        self.assertEqual(without_hydration.graded_aspects, 6)
        self.assertNotIn(qol.HYDRATION, without_hydration.pillar_scores)
        # Both are near-perfect on every present pillar, so overall barely moves.
        self.assertAlmostEqual(full.overall, without_hydration.overall, delta=2)
        # But confidence must drop: one fewer pillar's weight is covered.
        self.assertLess(without_hydration.confidence, full.confidence)

    def test_partial_depth_within_a_pillar_lowers_confidence_not_score(self):
        """Sleep hours alone (no deep/REM) still scores the pillar at its
        optimum, but with less depth than all three signals present."""
        shallow = qol.score(_full_inputs(deep_sleep_minutes=None, rem_sleep_minutes=None))
        full = qol.score(_full_inputs())
        self.assertLess(shallow.confidence, full.confidence)
        self.assertEqual(shallow.pillar_scores[qol.SLEEP], full.pillar_scores[qol.SLEEP])

    def test_persona_reweights_the_same_inputs_differently(self):
        # Strong sleep/nutrition, weak everything else -- homebody weights
        # sleep+nutrition at 0.50 combined vs. balanced's 0.37, so the same
        # per-pillar scores must blend to a higher overall under homebody.
        inputs = qol.QualityOfLifeInputs(
            sleep_hours=8.0, protein_grams=130.0, total_calories=2_400,
            steps=100, active_calories=10, exercise_minutes=1,
        )
        balanced = qol.score(inputs, archetype="balanced")
        homebody = qol.score(inputs, archetype="homebody")
        outdoors = qol.score(inputs, archetype="outdoors")
        # Persona never touches per-pillar scoring, only the blend weights.
        self.assertEqual(balanced.pillar_scores, homebody.pillar_scores)
        self.assertEqual(balanced.pillar_scores, outdoors.pillar_scores)
        self.assertGreater(homebody.overall, balanced.overall)
        self.assertGreater(balanced.overall, outdoors.overall)


class SmoothingTests(unittest.TestCase):
    def test_no_previous_value_returns_self_unchanged(self):
        result = qol.score(_full_inputs())
        smoothed = result.smoothed(None)
        self.assertIs(smoothed, result)

    def test_smoothed_blends_toward_previous_scaled_by_confidence(self):
        result = qol.score(_full_inputs())  # high confidence, overall ~ raw_overall
        smoothed = result.smoothed(previous_overall=50, alpha=0.6)
        effective_alpha = 0.6 * max(0.35, result.confidence)
        expected = round(result.raw_overall * effective_alpha + 50 * (1 - effective_alpha))
        self.assertEqual(smoothed.overall, expected)
        self.assertEqual(smoothed.raw_overall, result.raw_overall)  # raw is never smoothed
        self.assertEqual(smoothed.confidence, result.confidence)

    def test_low_confidence_day_moves_the_trend_less(self):
        # Only one shallow pillar -> low confidence.
        low_conf = qol.score(qol.QualityOfLifeInputs(sleep_hours=8.0))
        smoothed = low_conf.smoothed(previous_overall=0, alpha=0.6)
        # effective_alpha floors at 0.35 regardless of how low confidence is.
        effective_alpha = 0.6 * max(0.35, low_conf.confidence)
        self.assertAlmostEqual(effective_alpha, 0.6 * 0.35, places=6)
        expected = round(low_conf.raw_overall * effective_alpha)
        self.assertEqual(smoothed.overall, expected)


class ScoreForTests(unittest.TestCase):
    def test_score_for_present_and_absent_pillar(self):
        result = qol.score(_full_inputs(water_glasses=None))
        self.assertIsInstance(result.score_for(qol.SLEEP), int)
        self.assertIsNone(result.score_for(qol.HYDRATION))


if __name__ == "__main__":
    unittest.main()
