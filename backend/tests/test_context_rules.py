"""Tests for aria_core.context_rules, the Python port of ForgeCore's
ContextRules.swift. Translated from ContextRulesTests.swift.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import unittest

import _bootstrap  # noqa: F401

from aria_core import context_rules as cr  # noqa: E402


def at_hour(hour: int, minute: int = 0) -> datetime:
    return datetime(2026, 9, 20, hour, minute, tzinfo=timezone.utc)


class ContextRulesTests(unittest.TestCase):
    def test_desk_nudge_fires_at_90_minutes_once_per_block(self):
        self.assertTrue(cr.desk_block_nudge_due("deskCoding", 90, False))
        self.assertTrue(cr.desk_block_nudge_due("deepFocus", 120, False))
        self.assertFalse(cr.desk_block_nudge_due("deskCoding", 89, False))
        self.assertFalse(cr.desk_block_nudge_due("deskCoding", 200, True))
        self.assertFalse(cr.desk_block_nudge_due("gym", 200, False))
        self.assertFalse(cr.desk_block_nudge_due(None, 200, False))

    def test_evening_falls_back_to_9pm_without_prediction(self):
        self.assertFalse(cr.evening_wind_down_due(at_hour(20, 59), None, None, None))
        self.assertTrue(cr.evening_wind_down_due(at_hour(21), None, None, None))

    def test_predicted_wind_down_overrides_fixed_hour(self):
        predicted = at_hour(22, 15)
        self.assertFalse(cr.evening_wind_down_due(at_hour(21, 30), predicted, None, None))
        self.assertTrue(cr.evening_wind_down_due(at_hour(22, 20), predicted, None, None))

    def test_no_wind_down_when_already_winding_down(self):
        self.assertFalse(cr.evening_wind_down_due(at_hour(23), None, "windDown", None))
        self.assertFalse(cr.evening_wind_down_due(at_hour(23), None, None, "windDown"))

    def test_desk_mode_likely_only_during_work_hours_when_unset(self):
        self.assertTrue(cr.desk_mode_likely(0.9, 14, None, None))
        self.assertFalse(cr.desk_mode_likely(0.5, 14, None, None))
        self.assertFalse(cr.desk_mode_likely(0.9, 22, None, None))
        self.assertFalse(cr.desk_mode_likely(0.9, 14, "gym", None))
        self.assertFalse(cr.desk_mode_likely(0.9, 14, None, "windDown"))

    def test_gym_needs_elevated_heart_rate(self):
        self.assertFalse(cr.gym_suggestion_allowed(None))
        self.assertFalse(cr.gym_suggestion_allowed(72))
        self.assertTrue(cr.gym_suggestion_allowed(112))

    def test_a_fresh_reading_is_usable(self):
        now = at_hour(14)
        reading = cr.HeartRateReading(bpm=128, taken_at=now - timedelta(seconds=60))
        self.assertEqual(cr.usable_heart_rate(reading, now), 128)

    def test_a_stale_reading_is_not(self):
        now = at_hour(14)
        reading = cr.HeartRateReading(bpm=128, taken_at=now - timedelta(hours=3))
        self.assertIsNone(cr.usable_heart_rate(reading, now))

    def test_the_boundary_is_inclusive(self):
        now = at_hour(14)
        edge = cr.HeartRateReading(bpm=110, taken_at=now - timedelta(seconds=cr.HEART_RATE_FRESHNESS_SECONDS))
        self.assertEqual(cr.usable_heart_rate(edge, now), 110)
        past = cr.HeartRateReading(
            bpm=110,
            taken_at=now - timedelta(seconds=cr.HEART_RATE_FRESHNESS_SECONDS + 1),
        )
        self.assertIsNone(cr.usable_heart_rate(past, now))

    def test_no_reading_is_not_usable(self):
        self.assertIsNone(cr.usable_heart_rate(None, at_hour(14)))

    def test_a_future_dated_reading_is_not_treated_as_infinitely_fresh(self):
        now = at_hour(14)
        ahead = cr.HeartRateReading(bpm=140, taken_at=now + timedelta(hours=3))
        self.assertIsNone(cr.usable_heart_rate(ahead, now))

    def test_the_gym_rule_fires_once_the_loop_has_a_fresh_reading(self):
        now = at_hour(14)
        training = cr.HeartRateReading(bpm=132, taken_at=now - timedelta(seconds=120))
        self.assertTrue(cr.gym_suggestion_allowed(cr.usable_heart_rate(training, now)))
        resting = cr.HeartRateReading(bpm=68, taken_at=now - timedelta(seconds=120))
        self.assertFalse(cr.gym_suggestion_allowed(cr.usable_heart_rate(resting, now)))


if __name__ == "__main__":
    unittest.main()
