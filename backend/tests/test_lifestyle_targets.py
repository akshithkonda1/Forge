"""Tests for aria_core.lifestyle_targets, the Python port of ForgeSwift's
LifestyleTargets.swift (task #17 of the Swift->Python port list -- see
ARIA_INTELLIGENCE_PLAN.md).

No Swift test file exists for this module, so every expected value below
was hand-derived from the algorithm itself (shown inline in each test's
docstring) and independently verified, not just read off a reference
implementation.
"""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core import hydration_engine as he  # noqa: E402
from aria_core import lifestyle_targets as lt  # noqa: E402


class BmrTests(unittest.TestCase):
    def test_male_female_and_other_offsets(self):
        """base = 10*80 + 6.25*175 - 5*30 = 800 + 1093.75 - 150 = 1743.75."""
        base = 1743.75
        self.assertAlmostEqual(lt._mifflin_st_jeor_bmr(80, 30, lt.MALE), base + 5, places=6)
        self.assertAlmostEqual(lt._mifflin_st_jeor_bmr(80, 30, lt.FEMALE), base - 161, places=6)
        self.assertAlmostEqual(lt._mifflin_st_jeor_bmr(80, 30, lt.OTHER), base - 78, places=6)
        self.assertAlmostEqual(lt._mifflin_st_jeor_bmr(80, 30, lt.NON_BINARY), base - 78, places=6)
        self.assertAlmostEqual(lt._mifflin_st_jeor_bmr(80, 30, lt.PREFER_NOT_TO_SAY), base - 78, places=6)


class ComputedDefaultsTests(unittest.TestCase):
    def test_beginner_no_goals(self):
        """bmr(male,80,30)=1748.75. beginner mult=1.45, no-goal factor=1.0
        -> calories = round(1748.75*1.45) = round(2535.6875) = 2536.
        protein_per_kg (no goals) = 0.8 -> protein = round(80*0.8) = 64,
        floored to the 100g minimum. steps(beginner)=8000.
        """
        computed = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset())
        self.assertEqual(computed.calorie_target, 2536)
        self.assertEqual(computed.protein_grams, 100)
        self.assertEqual(computed.step_target, 8_000)
        self.assertEqual(computed.sleep_hours_target, 8.0)
        self.assertEqual(computed.active_calorie_target, 600)

    def test_lose_fat_lowers_calories(self):
        """goal_factor(loseFat)=0.88 -> calories = round(2535.6875*0.88) =
        round(2231.405) = 2231. protein_per_kg(loseFat only)=0.95 ->
        protein = round(80*0.95) = 76, still floored to 100."""
        computed = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset({lt.LOSE_FAT}))
        self.assertEqual(computed.calorie_target, 2231)
        self.assertEqual(computed.protein_grams, 100)

    def test_build_muscle_raises_calories_and_protein(self):
        """goal_factor(buildMuscle)=1.08 -> calories = round(2535.6875*1.08)
        = round(2738.5425) = 2739. protein_per_kg(buildMuscle)=1.0 ->
        protein = round(80*1.0) = 80, still floored to 100."""
        computed = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset({lt.BUILD_MUSCLE}))
        self.assertEqual(computed.calorie_target, 2739)
        self.assertEqual(computed.protein_grams, 100)

    def test_higher_body_mass_clears_the_protein_floor(self):
        """At 150kg, buildMuscle protein = round(150*1.0) = 150, above the
        floor -- confirms the floor is a floor, not a fixed value."""
        computed = lt._computed_defaults(150, 30, lt.MALE, lt.BEGINNER, frozenset({lt.BUILD_MUSCLE}))
        self.assertEqual(computed.protein_grams, 150)

    def test_lose_fat_and_build_muscle_together_is_asymmetric(self):
        """The Swift source's own asymmetry: goal_factor checks loseFat
        FIRST (so 0.88 wins over both goals present), but protein_per_kg
        checks buildMuscle/athletic FIRST (so 1.0 wins). Same calorie
        result as lose-fat-alone, same protein result as build-muscle-alone."""
        both = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER,
                                      frozenset({lt.LOSE_FAT, lt.BUILD_MUSCLE}))
        lose_fat_only = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset({lt.LOSE_FAT}))
        build_muscle_only = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset({lt.BUILD_MUSCLE}))
        self.assertEqual(both.calorie_target, lose_fat_only.calorie_target)
        self.assertEqual(both.protein_grams, build_muscle_only.protein_grams)

    def test_experience_level_step_targets(self):
        self.assertEqual(lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset()).step_target, 8_000)
        self.assertEqual(lt._computed_defaults(80, 30, lt.MALE, lt.INTERMEDIATE, frozenset()).step_target, 10_000)
        self.assertEqual(lt._computed_defaults(80, 30, lt.MALE, lt.ADVANCED, frozenset()).step_target, 12_000)
        self.assertEqual(lt._computed_defaults(80, 30, lt.MALE, lt.ELITE, frozenset()).step_target, 12_000)

    def test_experience_level_activity_multiplier_raises_calories(self):
        beginner = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset())
        intermediate = lt._computed_defaults(80, 30, lt.MALE, lt.INTERMEDIATE, frozenset())
        advanced = lt._computed_defaults(80, 30, lt.MALE, lt.ADVANCED, frozenset())
        self.assertLess(beginner.calorie_target, intermediate.calorie_target)
        self.assertLess(intermediate.calorie_target, advanced.calorie_target)

    def test_water_glasses_matches_hydration_engine_directly(self):
        """target_milliliters(80) = clamp(80*33, 1500, 5000) = 2640.
        glasses = round(2640/237) = round(11.139...) = 11."""
        computed = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset())
        expected_ml = he.target_milliliters(80)
        expected_glasses = lt._swift_round(he.glasses_from_milliliters(expected_ml))
        self.assertEqual(computed.water_glasses_target, expected_glasses)
        self.assertEqual(computed.water_glasses_target, 11)

    def test_low_body_mass_floors_water_glasses_at_four(self):
        computed = lt._computed_defaults(20, 30, lt.MALE, lt.BEGINNER, frozenset())
        self.assertGreaterEqual(computed.water_glasses_target, 4)


class ResolveTests(unittest.TestCase):
    def test_no_overrides_uses_computed_defaults(self):
        profile = lt.Profile(weight_kg=80, age=30, gender=lt.MALE, experience_level=lt.BEGINNER,
                              fitness_goals=frozenset())
        computed = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset())
        resolved = lt.resolve(profile)
        self.assertEqual(resolved, computed)

    def test_missing_weight_falls_back_to_75kg(self):
        profile = lt.Profile(weight_kg=None, age=30, gender=lt.MALE, experience_level=lt.BEGINNER)
        computed = lt._computed_defaults(75, 30, lt.MALE, lt.BEGINNER, frozenset())
        resolved = lt.resolve(profile)
        self.assertEqual(resolved, computed)

    def test_overrides_win_field_by_field(self):
        profile = lt.Profile(weight_kg=80, age=30, gender=lt.MALE, experience_level=lt.BEGINNER)
        overrides = lt.NutritionPreferences(protein_grams=180, calorie_target=2200, step_target=6000,
                                             sleep_hours_target=7.5, active_calorie_target=400)
        resolved = lt.resolve(profile, overrides)
        self.assertEqual(resolved.protein_grams, 180)
        self.assertEqual(resolved.calorie_target, 2200)
        self.assertEqual(resolved.step_target, 6000)
        self.assertEqual(resolved.sleep_hours_target, 7.5)
        self.assertEqual(resolved.active_calorie_target, 400)

    def test_unset_override_fields_fall_back_to_computed(self):
        profile = lt.Profile(weight_kg=80, age=30, gender=lt.MALE, experience_level=lt.BEGINNER)
        overrides = lt.NutritionPreferences(protein_grams=180)
        computed = lt._computed_defaults(80, 30, lt.MALE, lt.BEGINNER, frozenset())
        resolved = lt.resolve(profile, overrides)
        self.assertEqual(resolved.protein_grams, 180)
        self.assertEqual(resolved.calorie_target, computed.calorie_target)

    def test_water_glasses_target_override_used_directly_no_clamp(self):
        """A direct waterGlassesTarget override is NOT round-tripped
        through hydration-milliliter clamping -- it is used as-is, even
        an implausibly low value like 1."""
        profile = lt.Profile(weight_kg=80, age=30, gender=lt.MALE, experience_level=lt.BEGINNER)
        overrides = lt.NutritionPreferences(water_glasses_target=1)
        resolved = lt.resolve(profile, overrides)
        self.assertEqual(resolved.water_glasses_target, 1)

    def test_hydration_target_ml_override_wins_over_water_glasses_target(self):
        profile = lt.Profile(weight_kg=80, age=30, gender=lt.MALE, experience_level=lt.BEGINNER)
        overrides = lt.NutritionPreferences(water_glasses_target=1, hydration_target_ml=3000)
        resolved = lt.resolve(profile, overrides)
        expected = max(4, lt._swift_round(he.glasses_from_milliliters(3000)))
        self.assertEqual(resolved.water_glasses_target, expected)
        self.assertNotEqual(resolved.water_glasses_target, 1)


class HydrationMillilitersTests(unittest.TestCase):
    def test_no_overrides_uses_suggested_target(self):
        profile = lt.Profile(weight_kg=80)
        result = lt.hydration_milliliters(profile)
        self.assertEqual(result, he.target_milliliters(80))

    def test_hydration_target_ml_override_is_clamped(self):
        profile = lt.Profile(weight_kg=80)
        overrides = lt.NutritionPreferences(hydration_target_ml=3000)
        self.assertEqual(lt.hydration_milliliters(profile, overrides), 3000)

    def test_water_glasses_target_override_converts_and_clamps(self):
        """5 glasses * 237ml = 1185ml, below the 1500ml floor -> clamped up."""
        profile = lt.Profile(weight_kg=80)
        overrides = lt.NutritionPreferences(water_glasses_target=5)
        result = lt.hydration_milliliters(profile, overrides)
        self.assertEqual(result, he.MINIMUM_TARGET_MILLILITERS)

    def test_active_calories_and_cycle_pass_through(self):
        profile = lt.Profile(weight_kg=80)
        base = lt.hydration_milliliters(profile)
        with_activity = lt.hydration_milliliters(profile, active_calories=500)
        with_cycle = lt.hydration_milliliters(profile, cycle=he.CYCLE_LUTEAL)
        self.assertGreater(with_activity, base)
        self.assertGreater(with_cycle, base)


if __name__ == "__main__":
    unittest.main()
