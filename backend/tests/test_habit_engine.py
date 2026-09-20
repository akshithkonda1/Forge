"""Tests for aria_core.habit_engine, the Python port of ForgeCore's
HabitEngine.swift (task #18 of the Swift->Python port list -- see
ARIA_INTELLIGENCE_PLAN.md). The two Swift tests in HabitEngineTests.swift
(HabitEngineSleepTests) are translated directly; the rest is this port's
own coverage of each rule, the top-3 truncation, and the companion_line/
lifestyle_tags/constraints helpers.
"""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core import habit_engine as he  # noqa: E402


def _signals(**overrides) -> he.HabitSignals:
    base = dict(
        sleep_average=7.5,
        steps=9000,
        protein=180,
        water_glasses=8,
        total_calories=2200,
    )
    base.update(overrides)
    return he.HabitSignals(**base)


class SwiftTranslatedTests(unittest.TestCase):
    def test_sleep_variance_companion_is_identity_not_streak(self):
        signals = _signals(sleep_average=6.2, sleep_variance_minutes=95, nights_available=7)
        habits = he.analyze(signals)
        self.assertEqual(habits[0].id, "sleep_variance")
        line = he.companion_line(habits) or ""
        self.assertIn("becoming someone", line.lower())
        self.assertNotIn("streak", line.lower())

    def test_low_qol_emits_protect_habit_and_constraint(self):
        signals = _signals(quality_of_life_score=55)
        habits = he.analyze(signals)
        self.assertTrue(any(h.id == "qol_protect" for h in habits))
        cs = he.constraints(habits)
        self.assertTrue(any(c.startswith("habit:qol_protect:") for c in cs))


class NoSignalTests(unittest.TestCase):
    def test_clean_signals_emit_nothing(self):
        """Every threshold cleared, no variance measured, no social, good
        QoL -- zero habits, not an empty-evidence habit."""
        habits = he.analyze(_signals())
        self.assertEqual(habits, [])
        self.assertIsNone(he.companion_line(habits))
        self.assertEqual(he.lifestyle_tags(habits), [])
        self.assertEqual(he.constraints(habits), [])


class SleepVarianceRuleTests(unittest.TestCase):
    def test_variance_none_never_fires_even_with_low_sleep_average(self):
        """The Swift source gates this entire rule on sleepVarianceMinutes
        being present at all -- a low sleep_average alone, with variance
        unmeasured, must not fire it."""
        habits = he.analyze(_signals(sleep_average=4.0, sleep_variance_minutes=None))
        self.assertFalse(any(h.id == "sleep_variance" for h in habits))

    def test_low_variance_still_fires_on_low_sleep_average(self):
        habits = he.analyze(_signals(sleep_average=6.0, sleep_variance_minutes=10))
        self.assertTrue(any(h.id == "sleep_variance" for h in habits))

    def test_evidence_branches_and_confidence(self):
        high_variance = he.analyze(_signals(sleep_average=7.5, sleep_variance_minutes=95))[0]
        self.assertIn("Bedtime moved 95m", high_variance.evidence)
        self.assertEqual(high_variance.confidence, 0.85)

        low_sleep = he.analyze(_signals(sleep_average=6.5, sleep_variance_minutes=65))[0]
        self.assertIn("under target", low_sleep.evidence)
        self.assertEqual(low_sleep.confidence, 0.65)

        moderate = he.analyze(_signals(sleep_average=7.5, sleep_variance_minutes=65))[0]
        self.assertIn("enough to cut deep sleep", moderate.evidence)
        self.assertEqual(moderate.confidence, 0.65)


class SocialRuleTests(unittest.TestCase):
    def test_two_drink_night_fires(self):
        social = [he.SocialEvent(drinks=2, ran_late=False)]
        habits = he.analyze(_signals(social=social))
        self.assertTrue(any(h.id == "social_late" for h in habits))

    def test_two_late_nights_fires_without_drinks(self):
        social = [he.SocialEvent(ran_late=True), he.SocialEvent(ran_late=True)]
        habits = he.analyze(_signals(social=social))
        social_habit = next(h for h in habits if h.id == "social_late")
        self.assertEqual(social_habit.confidence, 0.82)

    def test_one_late_night_alone_does_not_fire(self):
        social = [he.SocialEvent(ran_late=True)]
        habits = he.analyze(_signals(social=social))
        self.assertFalse(any(h.id == "social_late" for h in habits))

    def test_counts_and_confidence(self):
        social = [
            he.SocialEvent(drinks=3, ran_late=True),
            he.SocialEvent(drinks=2, ran_late=False),
            he.SocialEvent(drinks=0, ran_late=False),
        ]
        habit = he.analyze(_signals(social=social))[0]
        self.assertEqual(habit.id, "social_late")
        self.assertIn("2 evenings with 5 drinks, 1 ran past midnight", habit.routine)
        self.assertEqual(habit.confidence, 0.62)  # only 1 late night, < 2


class HydrationRuleTests(unittest.TestCase):
    def test_fires_under_six_glasses(self):
        habit = he.analyze(_signals(water_glasses=3))[0]
        self.assertEqual(habit.id, "hydration")
        self.assertIn("3 glasses today", habit.evidence)
        self.assertEqual(habit.confidence, 0.78)

    def test_does_not_fire_at_six(self):
        self.assertFalse(any(h.id == "hydration" for h in he.analyze(_signals(water_glasses=6))))


class ProteinGapRuleTests(unittest.TestCase):
    def test_fires_when_gap_exceeds_thirty(self):
        habit = he.analyze(_signals(protein=140))[0]  # gap = 40
        self.assertEqual(habit.id, "protein_gap")
        self.assertIn("40g short", habit.evidence)
        self.assertEqual(habit.confidence, 0.6)

    def test_higher_confidence_above_fifty_gap(self):
        habit = he.analyze(_signals(protein=100))[0]  # gap = 80
        self.assertEqual(habit.confidence, 0.8)

    def test_surplus_protein_floors_gap_at_zero_and_does_not_fire(self):
        habits = he.analyze(_signals(protein=250))
        self.assertFalse(any(h.id == "protein_gap" for h in habits))


class SedentaryRuleTests(unittest.TestCase):
    def test_fires_under_six_thousand_steps(self):
        habit = he.analyze(_signals(steps=5000))[0]
        self.assertEqual(habit.id, "sedentary")
        self.assertEqual(habit.confidence, 0.6)

    def test_higher_confidence_under_thirty_five_hundred(self):
        habit = he.analyze(_signals(steps=2000))[0]
        self.assertEqual(habit.confidence, 0.78)


class HrvDipRuleTests(unittest.TestCase):
    def test_fires_when_hrv_drops_more_than_eight_below_baseline(self):
        habit = he.analyze(_signals(hrv=40, hrv_baseline=55))[0]  # drop=15
        self.assertEqual(habit.id, "hrv_dip")
        self.assertIn("−15ms", habit.routine)  # U+2212 minus sign, matching the Swift source
        self.assertEqual(habit.confidence, 0.62)

    def test_higher_confidence_above_fifteen_drop(self):
        habit = he.analyze(_signals(hrv=30, hrv_baseline=55))[0]  # drop=25
        self.assertEqual(habit.confidence, 0.82)

    def test_missing_baseline_never_fires(self):
        habits = he.analyze(_signals(hrv=30, hrv_baseline=None))
        self.assertFalse(any(h.id == "hrv_dip" for h in habits))

    def test_zero_baseline_never_fires(self):
        habits = he.analyze(_signals(hrv=30, hrv_baseline=0))
        self.assertFalse(any(h.id == "hrv_dip" for h in habits))

    def test_small_drop_does_not_fire(self):
        habits = he.analyze(_signals(hrv=50, hrv_baseline=55))  # drop=5, < 8
        self.assertFalse(any(h.id == "hrv_dip" for h in habits))


class QolRuleTests(unittest.TestCase):
    """These scenarios deliberately also trip the hydration/sedentary rules
    (both at the same 0.78 confidence as each other, and the qol_protect
    rule reads the same underlying thresholds for its own lever choice),
    so the qol_protect habit is found by id, never assumed to be
    habits[0] -- with several rules tied on confidence, index 0 is
    whichever fired first in analyze()'s own rule order, not necessarily
    qol_protect."""

    def _qol_habit(self, **overrides):
        habits = he.analyze(_signals(**overrides))
        return next(h for h in habits if h.id == "qol_protect")

    def test_lever_prefers_sleep_first(self):
        habit = self._qol_habit(quality_of_life_score=60, sleep_average=6.0,
                                 water_glasses=2, steps=1000)
        self.assertEqual(habit.category, he.SLEEP)

    def test_lever_falls_to_hydration_next(self):
        habit = self._qol_habit(quality_of_life_score=60, sleep_average=7.5,
                                 water_glasses=2, steps=1000)
        self.assertEqual(habit.category, he.NUTRITION)

    def test_lever_falls_to_movement_next(self):
        habit = self._qol_habit(quality_of_life_score=60, sleep_average=7.5,
                                 water_glasses=8, steps=1000)
        self.assertEqual(habit.category, he.MOVEMENT)

    def test_lever_falls_to_recovery_last(self):
        habit = self._qol_habit(quality_of_life_score=60, sleep_average=7.5,
                                 water_glasses=8, steps=9000)
        self.assertEqual(habit.category, he.RECOVERY)

    def test_severe_qol_raises_confidence(self):
        habit = he.analyze(_signals(quality_of_life_score=40))[0]
        self.assertEqual(habit.confidence, 0.88)


class TopThreeTests(unittest.TestCase):
    def test_never_more_than_three_habits(self):
        signals = _signals(
            sleep_average=5.0, sleep_variance_minutes=95,
            social=[he.SocialEvent(drinks=3, ran_late=True), he.SocialEvent(ran_late=True)],
            water_glasses=2, protein=80, steps=1000,
            hrv=30, hrv_baseline=55, quality_of_life_score=40,
        )
        habits = he.analyze(signals)
        self.assertLessEqual(len(habits), 3)
        self.assertEqual(len(habits), 3)

    def test_sorted_by_confidence_descending(self):
        signals = _signals(
            sleep_average=5.0, sleep_variance_minutes=95,
            water_glasses=2, protein=80, steps=1000,
            hrv=30, hrv_baseline=55, quality_of_life_score=40,
        )
        habits = he.analyze(signals)
        confidences = [h.confidence for h in habits]
        self.assertEqual(confidences, sorted(confidences, reverse=True))


class CompanionLineTests(unittest.TestCase):
    def test_every_rule_id_has_its_own_line(self):
        cases = [
            (_signals(sleep_average=6.0, sleep_variance_minutes=95), "sleep_variance", "becoming someone"),
            (_signals(social=[he.SocialEvent(drinks=3, ran_late=True), he.SocialEvent(ran_late=True)]),
             "social_late", "late social nights"),
            (_signals(water_glasses=2), "hydration", "water's low"),
            (_signals(protein=80), "protein_gap", "protein's"),
            (_signals(steps=1000), "sedentary", "steps are"),
            (_signals(hrv=30, hrv_baseline=55), "hrv_dip", "recovery dipped"),
            (_signals(quality_of_life_score=40), "qol_protect", "lifestyle qol is"),
        ]
        for signals, expected_id, needle in cases:
            habits = he.analyze(signals)
            self.assertEqual(habits[0].id, expected_id)
            line = (he.companion_line(habits) or "").lower()
            self.assertIn(needle, line, f"{expected_id}: {line}")


class LifestyleTagsAndConstraintsTests(unittest.TestCase):
    def test_lifestyle_tags_shape(self):
        habits = he.analyze(_signals(sleep_average=6.0, sleep_variance_minutes=95))
        tags = he.lifestyle_tags(habits)
        self.assertEqual(tags, [f"habit:sleep_variance:sleep:{int(habits[0].confidence * 100)}"])

    def test_sleep_hygiene_constraint_from_sleep_category(self):
        habits = he.analyze(_signals(sleep_average=6.0, sleep_variance_minutes=95))
        cs = he.constraints(habits)
        self.assertIn("habit:sleep_hygiene: protect 22:30 wind-down", cs)

    def test_social_constraint_from_social_category(self):
        habits = he.analyze(_signals(
            social=[he.SocialEvent(drinks=3, ran_late=True), he.SocialEvent(ran_late=True)]
        ))
        cs = he.constraints(habits)
        self.assertIn("habit:social: one early night this week", cs)


if __name__ == "__main__":
    unittest.main()
