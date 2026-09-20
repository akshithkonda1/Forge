"""Tests for aria_core.metabolic_health_snapshot, the Python port of
ForgeCore's MetabolicHealthSnapshot.swift meal/glucose pairing (task #19
of the Swift->Python port list -- see ARIA_INTELLIGENCE_PLAN.md).
Translated directly from MetabolicHealthSnapshotTests.swift, checked
against the same fixtures and expected values.

One adaptation: the Swift suite's testSelectedSteloWithoutReadingsStays
SoldSeparately passes raw connectedDeviceIDs and relies on
HealthDeviceCatalog to resolve "dexcom-stelo" -> "Dexcom Stelo" -- that
catalog is deliberately out of scope for this port (see the module's own
docstring), so the translated test below passes the already-resolved
device name directly, matching this port's accessory_line() signature.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

import _bootstrap  # noqa: F401

from aria_core import metabolic_health_snapshot as mhs  # noqa: E402

NOW = datetime.fromtimestamp(1_700_000_000, tz=timezone.utc)


class NoDataTests(unittest.TestCase):
    def test_no_data_keeps_sold_separately_honesty(self):
        snap = mhs.evaluate(meals=[], glucose=[], now=NOW)
        self.assertFalse(snap.has_glucose)
        self.assertEqual(snap.meal_count, 0)
        self.assertIn("sold separately", snap.accessory_line)
        self.assertIn("sold separately", snap.story_line.lower())
        self.assertEqual(snap.bullets, mhs.METABOLIC_BULLETS)
        self.assertEqual(len(snap.bullets), 4)


class GlucoseWithoutMealsTests(unittest.TestCase):
    def test_asks_for_a_meal(self):
        snap = mhs.evaluate(
            meals=[],
            glucose=[mhs.GlucosePoint(date=NOW - timedelta(minutes=20), mgdl=102, source_name="Dexcom Stelo")],
            now=NOW,
        )
        self.assertEqual(snap.latest_mgdl, 102)
        self.assertEqual(snap.latest_source, "Dexcom Stelo")
        self.assertEqual(snap.story_line, "Latest glucose 102 mg/dL. Log a meal to see how food lands.")
        self.assertIn("Dexcom Stelo", snap.accessory_line)
        self.assertIn("Apple Health", snap.accessory_line)
        self.assertNotIn("sold separately", snap.accessory_line)


class MealPairingTests(unittest.TestCase):
    def test_meal_plus_post_meal_rise_tells_the_landing(self):
        lunch = NOW - timedelta(minutes=90)
        meals = [mhs.MetabolicMealEvent(name="Lunch", date=lunch, calories=640, carbs=64, protein=38, fat=18)]
        glucose = [
            mhs.GlucosePoint(date=lunch - timedelta(minutes=10), mgdl=98, source_name="Stelo"),
            mhs.GlucosePoint(date=lunch + timedelta(minutes=55), mgdl=129, source_name="Stelo"),
        ]
        snap = mhs.evaluate(meals=meals, glucose=glucose, now=NOW)
        self.assertEqual(len(snap.pairs), 1)
        self.assertEqual(snap.pairs[0].delta_mgdl, 31)
        self.assertEqual(snap.story_line, "Lunch · 64g carbs · glucose rose 31 mg/dL after.")
        self.assertEqual(snap.meal_count, 1)
        self.assertEqual(snap.carbs_grams, 64)

    def test_stable_post_meal_does_not_invent_a_spike(self):
        lunch = NOW - timedelta(minutes=80)
        snap = mhs.evaluate(
            meals=[mhs.MetabolicMealEvent(name="Oats", date=lunch, calories=310, carbs=48)],
            glucose=[
                mhs.GlucosePoint(date=lunch - timedelta(minutes=5), mgdl=104, source_name="Libre"),
                mhs.GlucosePoint(date=lunch + timedelta(minutes=50), mgdl=107, source_name="Libre"),
            ],
            now=NOW,
        )
        self.assertEqual(snap.pairs[0].line, "Oats · 48g carbs · glucose held near 107 mg/dL after.")

    def test_no_post_meal_reading_does_not_invent_a_pair(self):
        lunch = NOW - timedelta(minutes=10)
        snap = mhs.evaluate(
            meals=[mhs.MetabolicMealEvent(name="Lunch", date=lunch, calories=500, carbs=50)],
            glucose=[mhs.GlucosePoint(date=lunch - timedelta(minutes=15), mgdl=99, source_name="Stelo")],
            now=NOW,
        )
        self.assertEqual(snap.pairs, ())
        self.assertIn("waiting on a post-meal reading", snap.story_line)

    def test_glucose_eases_when_delta_is_strongly_negative(self):
        lunch = NOW - timedelta(minutes=90)
        snap = mhs.evaluate(
            meals=[mhs.MetabolicMealEvent(name="Salad", date=lunch, calories=300, carbs=20)],
            glucose=[
                mhs.GlucosePoint(date=lunch - timedelta(minutes=5), mgdl=140, source_name="Stelo"),
                mhs.GlucosePoint(date=lunch + timedelta(minutes=60), mgdl=115, source_name="Stelo"),
            ],
            now=NOW,
        )
        self.assertIn("glucose eased 25 mg/dL after", snap.pairs[0].line)

    def test_peak_without_baseline_reports_peak_only(self):
        lunch = NOW - timedelta(minutes=90)
        snap = mhs.evaluate(
            meals=[mhs.MetabolicMealEvent(name="Snack", date=lunch, calories=150, carbs=15)],
            glucose=[mhs.GlucosePoint(date=lunch + timedelta(minutes=60), mgdl=118, source_name="Stelo")],
            now=NOW,
        )
        self.assertEqual(snap.pairs[0].line, "Snack · 15g carbs · 118 mg/dL after the meal.")
        self.assertIsNone(snap.pairs[0].delta_mgdl)

    def test_empty_meal_name_falls_back_to_meal(self):
        lunch = NOW - timedelta(minutes=90)
        snap = mhs.evaluate(
            meals=[mhs.MetabolicMealEvent(name="   ", date=lunch, calories=150, carbs=0)],
            glucose=[mhs.GlucosePoint(date=lunch + timedelta(minutes=60), mgdl=118, source_name="Stelo")],
            now=NOW,
        )
        self.assertTrue(snap.pairs[0].line.startswith("Meal"))
        self.assertNotIn("carbs", snap.pairs[0].line)  # carbs==0 -> no carbBit


class AccessoryLineTests(unittest.TestCase):
    def test_selected_device_without_readings_stays_sold_separately(self):
        """Adapted: passes the already-resolved device name directly
        (this port's accessory_line() doesn't resolve raw device IDs --
        see the module docstring)."""
        line = mhs.accessory_line(connected_metabolic_device_name="Dexcom Stelo", latest_source=None)
        self.assertIn("Stelo", line)
        self.assertIn("sold separately", line)
        self.assertIn("Apple Health", line)

    def test_cgm_source_wins_over_a_connected_device_name(self):
        line = mhs.accessory_line(connected_metabolic_device_name="Dexcom Stelo", latest_source="Libre")
        self.assertIn("coming from Libre", line)


class ImplausibleGlucoseTests(unittest.TestCase):
    def test_implausible_glucose_is_ignored(self):
        snap = mhs.evaluate(meals=[], glucose=[mhs.GlucosePoint(date=NOW, mgdl=12, source_name="Stelo")], now=NOW)
        self.assertFalse(snap.has_glucose)
        self.assertIn("sold separately", snap.accessory_line)

    def test_glucose_above_four_hundred_is_ignored(self):
        snap = mhs.evaluate(meals=[], glucose=[mhs.GlucosePoint(date=NOW, mgdl=450, source_name="Stelo")], now=NOW)
        self.assertFalse(snap.has_glucose)


class CopyNeverClaimsDiagnosisTests(unittest.TestCase):
    def test_no_banned_medical_terms(self):
        lunch = NOW - timedelta(minutes=90)
        snap = mhs.evaluate(
            meals=[mhs.MetabolicMealEvent(name="Pasta", date=lunch, calories=820, carbs=110)],
            glucose=[
                mhs.GlucosePoint(date=lunch - timedelta(minutes=8), mgdl=95, source_name="Dexcom G7"),
                mhs.GlucosePoint(date=lunch + timedelta(minutes=70), mgdl=168, source_name="Dexcom G7"),
            ],
            now=NOW,
        )
        blob = f"{snap.story_line} {snap.accessory_line} {' '.join(snap.bullets)}".lower()
        for banned in ("diagnos", "diabet", "disease", "patient", "insulin", "a1c", "hypergly", "hypogly"):
            self.assertNotIn(banned, blob, banned)


class DayTotalOverrideTests(unittest.TestCase):
    def test_day_totals_override_meal_sums(self):
        lunch = NOW - timedelta(minutes=90)
        snap = mhs.evaluate(
            meals=[mhs.MetabolicMealEvent(name="Lunch", date=lunch, calories=500, carbs=50, protein=20, fat=10)],
            glucose=[],
            day_carbs=200, day_protein=90, day_fat=60, day_calories=2200,
            now=NOW,
        )
        self.assertEqual(snap.carbs_grams, 200)
        self.assertEqual(snap.protein_grams, 90)
        self.assertEqual(snap.fat_grams, 60)
        self.assertEqual(snap.calories, 2200)


class DayWindowTests(unittest.TestCase):
    def test_meals_before_today_are_excluded(self):
        yesterday = NOW - timedelta(days=1)
        snap = mhs.evaluate(
            meals=[mhs.MetabolicMealEvent(name="Old", date=yesterday, calories=400, carbs=40)],
            glucose=[],
            now=NOW,
        )
        self.assertEqual(snap.meal_count, 0)

    def test_meals_in_the_future_are_excluded(self):
        later = NOW + timedelta(hours=2)
        snap = mhs.evaluate(
            meals=[mhs.MetabolicMealEvent(name="Later", date=later, calories=400, carbs=40)],
            glucose=[],
            now=NOW,
        )
        self.assertEqual(snap.meal_count, 0)


if __name__ == "__main__":
    unittest.main()
