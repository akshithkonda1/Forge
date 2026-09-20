"""Tests for aria_core.hydration_engine, the Python port of ForgeCore's
HydrationEngine.swift (task #16 of the Swift->Python port list -- see
ARIA_INTELLIGENCE_PLAN.md). Translated directly from
HydrationEngineTests.swift, checked against the same fixtures and expected
values.
"""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core import hydration_engine as he  # noqa: E402


class TargetMillilitersTests(unittest.TestCase):
    def test_scales_with_body_mass(self):
        light = he.target_milliliters(55)
        heavy = he.target_milliliters(90)
        self.assertGreater(heavy, light)
        self.assertAlmostEqual(light, 55 * he.MILLILITERS_PER_KILOGRAM, places=1)

    def test_falls_back_to_default_weight(self):
        fallback = he.target_milliliters(None)
        explicit = he.target_milliliters(he.DEFAULT_WEIGHT_KILOGRAMS)
        self.assertAlmostEqual(fallback, explicit, places=1)

    def test_clamped_to_physiological_range(self):
        tiny = he.target_milliliters(20)
        self.assertGreaterEqual(tiny, he.MINIMUM_TARGET_MILLILITERS)
        huge = he.target_milliliters(140, active_calories=4_000, hot_environment=True)
        self.assertLessEqual(huge, he.MAXIMUM_TARGET_MILLILITERS)

    def test_activity_adds_milliliter_per_kilocalorie(self):
        rest = he.target_milliliters(70, active_calories=0)
        session = he.target_milliliters(70, active_calories=500)
        self.assertAlmostEqual(session - rest, 500, places=1)

    def test_activity_bonus_is_capped(self):
        rest = he.target_milliliters(70, active_calories=0)
        long = he.target_milliliters(70, active_calories=5_000)
        self.assertAlmostEqual(long - rest, 1_200, places=1)

    def test_cycle_adjustments_raise_need(self):
        base = he.target_milliliters(70, cycle=he.CYCLE_NONE)
        luteal = he.target_milliliters(70, cycle=he.CYCLE_LUTEAL)
        period = he.target_milliliters(70, cycle=he.CYCLE_MENSTRUATION)
        self.assertAlmostEqual(luteal - base, he.LUTEAL_BONUS_MILLILITERS, places=1)
        self.assertAlmostEqual(period - base, he.MENSTRUATION_BONUS_MILLILITERS, places=1)
        self.assertGreater(period, luteal)


class ConversionTests(unittest.TestCase):
    def test_glass_conversion_round_trips(self):
        glasses = he.glasses_from_milliliters(474)
        self.assertAlmostEqual(glasses, 2, places=2)
        self.assertAlmostEqual(he.milliliters_from_glasses(2), 474, places=2)

    def test_ounce_conversion_matches_us_fluid_ounce(self):
        ml = he.milliliters_from_fluid_ounces(8)
        self.assertAlmostEqual(ml, 8 * he.MILLILITERS_PER_FLUID_OUNCE, places=2)
        self.assertAlmostEqual(he.fluid_ounces_from_milliliters(ml), 8, places=2)


class ExpectedMillilitersTests(unittest.TestCase):
    def test_zero_just_after_wake(self):
        expected = he.expected_milliliters(7.2, target=2_000.0, wake_hour=7, onset_hour=23)
        self.assertAlmostEqual(expected, 0, places=1)

    def test_reaches_target_before_evening_taper(self):
        target = 2_000.0
        at_taper = he.expected_milliliters(21, target=target, wake_hour=7, onset_hour=23)
        self.assertAlmostEqual(at_taper, target, places=1)
        late = he.expected_milliliters(22.5, target=target, wake_hour=7, onset_hour=23)
        self.assertAlmostEqual(late, target, places=1)

    def test_climbs_through_the_waking_day(self):
        target = 2_000.0
        morning = he.expected_milliliters(10, target=target, wake_hour=7, onset_hour=23)
        afternoon = he.expected_milliliters(15, target=target, wake_hour=7, onset_hour=23)
        self.assertGreater(afternoon, morning)
        self.assertGreater(morning, 0)
        self.assertLess(afternoon, target)

    def test_holds_for_a_night_owl(self):
        target = 2_000.0
        early = he.expected_milliliters(10.2, target=target, wake_hour=10, onset_hour=2)
        self.assertAlmostEqual(early, 0, places=1, msg="twelve minutes after a 10am wake is still the ramp")
        done = he.expected_milliliters(0, target=target, wake_hour=10, onset_hour=2)
        self.assertAlmostEqual(done, target, places=1, msg="midnight is inside a 2am-onset taper")


class StatusTests(unittest.TestCase):
    def test_behind_on_track_met_over(self):
        self.assertEqual(he.status(consumed=400, target=2_000, expected=1_000), he.STATUS_BEHIND)
        self.assertEqual(he.status(consumed=950, target=2_000, expected=1_000), he.STATUS_ON_TRACK)
        self.assertEqual(he.status(consumed=2_000, target=2_000, expected=2_000), he.STATUS_MET)
        self.assertEqual(he.status(consumed=2_400, target=2_000, expected=2_000), he.STATUS_OVER)

    def test_zero_target_reads_on_track(self):
        self.assertEqual(he.status(consumed=0, target=0, expected=0), he.STATUS_ON_TRACK)


class GuidanceTests(unittest.TestCase):
    def test_names_the_gap_when_behind(self):
        text = he.guidance(he.STATUS_BEHIND, remaining=500, hours_until_onset=8)
        self.assertIn("glass", text.lower())
        self.assertTrue(text)

    def test_tapers_late_even_when_behind(self):
        text = he.guidance(he.STATUS_BEHIND, remaining=800, hours_until_onset=1.5)
        self.assertTrue("late" in text.lower() or "small" in text.lower())

    def test_singular_glass_is_not_pluralized(self):
        text = he.guidance(he.STATUS_BEHIND, remaining=he.GLASS_MILLILITERS - 1, hours_until_onset=8)
        self.assertIn("1 glass ", text)
        self.assertNotIn("1 glasses", text)

    def test_met_and_over_and_on_track_each_have_copy(self):
        self.assertTrue(he.guidance(he.STATUS_MET, remaining=0, hours_until_onset=8))
        self.assertTrue(he.guidance(he.STATUS_OVER, remaining=0, hours_until_onset=8))
        self.assertTrue(he.guidance(he.STATUS_ON_TRACK, remaining=0, hours_until_onset=8))
        self.assertIn("taper", he.guidance(he.STATUS_ON_TRACK, remaining=0, hours_until_onset=1.0))


class ResolvedTargetTests(unittest.TestCase):
    def test_prefers_a_user_goal(self):
        suggested = 2_310.0
        self.assertAlmostEqual(he.resolved_target_milliliters(3_000, suggested), 3_000, places=1)
        self.assertAlmostEqual(he.resolved_target_milliliters(None, suggested), suggested, places=1)

    def test_clamps_a_wild_user_goal(self):
        self.assertAlmostEqual(he.resolved_target_milliliters(50, 2_000), he.MINIMUM_TARGET_MILLILITERS, places=1)
        self.assertAlmostEqual(he.resolved_target_milliliters(80_000, 2_000), he.MAXIMUM_TARGET_MILLILITERS, places=1)


class PresetTests(unittest.TestCase):
    def test_positive_and_ordered(self):
        mls = [p.milliliters for p in he.PRESETS]
        self.assertEqual(len(he.PRESETS), 4)
        self.assertEqual(mls, sorted(mls))
        self.assertTrue(all(m > 0 for m in mls))


if __name__ == "__main__":
    unittest.main()
