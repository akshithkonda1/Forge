"""Tests for aria_core.sleep_wake_adaptation, the Python port of the pure
pieces of ForgeCore's SleepWakeAdaptation.swift. Store tests stay on iOS.
Translated from SleepWakeAdaptationTests.swift.
"""

from __future__ import annotations

from datetime import datetime, timezone
import unittest

import _bootstrap  # noqa: F401

from aria_core import sleep_wake_adaptation as swa  # noqa: E402


def dt(y, m, d, h, minute) -> datetime:
    return datetime(y, m, d, h, minute, tzinfo=timezone.utc)


class SleepWakeAdaptationTests(unittest.TestCase):
    def test_low_score_widens_the_window(self):
        self.assertEqual(swa.smart_alarm_minutes(30, 60, 0, swa.BEAR), 45)

    def test_high_score_and_lion_narrow(self):
        self.assertEqual(swa.smart_alarm_minutes(30, 90, 0, swa.LION), 15)

    def test_strugglers_widen_further(self):
        calm = swa.smart_alarm_minutes(30, 80, 0, swa.BEAR, struggle_average_snoozes=0)
        hard = swa.smart_alarm_minutes(30, 80, 0, swa.BEAR, struggle_average_snoozes=2.0)
        self.assertEqual(calm, 30)
        self.assertEqual(hard, 40)

    def test_clamps_to_fifteen_forty_five(self):
        wide = swa.smart_alarm_minutes(45, 40, 8, swa.DOLPHIN, struggle_average_snoozes=3)
        self.assertEqual(wide, 45)

    def test_snooze_history_averages_across_mornings(self):
        days = swa.record_snooze_day([], day_key="2026-09-14", snoozes=2)
        days = swa.record_snooze_day(days, day_key="2026-09-15", snoozes=0)
        counts = [n for _, n in days]
        self.assertAlmostEqual(swa.average_snoozes(counts), 1.0, places=2)
        self.assertFalse(swa.is_repeat_struggler(counts))
        days = swa.record_snooze_day(days, day_key="2026-09-15", snoozes=2)
        counts = [n for _, n in days]
        self.assertAlmostEqual(swa.average_snoozes(counts), 2.0, places=2)
        self.assertTrue(swa.is_repeat_struggler(counts))

    def test_core_sleep_in_the_window_fires_early(self):
        self.assertEqual(
            swa.decide_early_fire(
                dt(2026, 9, 14, 6, 40),
                dt(2026, 9, 14, 6, 30),
                dt(2026, 9, 14, 7, 0),
                dt(2026, 9, 14, 6, 38),
                "core",
            ),
            swa.FIRE_EARLY,
        )

    def test_deep_sleep_in_the_window_is_ignored(self):
        self.assertEqual(
            swa.decide_early_fire(
                dt(2026, 9, 14, 6, 40),
                dt(2026, 9, 14, 6, 30),
                dt(2026, 9, 14, 7, 0),
                dt(2026, 9, 14, 6, 38),
                "deep",
            ),
            swa.IGNORE,
        )

    def test_stale_sample_is_ignored(self):
        self.assertEqual(
            swa.decide_early_fire(
                dt(2026, 9, 14, 6, 55),
                dt(2026, 9, 14, 6, 30),
                dt(2026, 9, 14, 7, 0),
                dt(2026, 9, 14, 6, 20),
                "core",
            ),
            swa.IGNORE,
        )

    def test_past_hard_alarm_is_already_past_hard(self):
        self.assertEqual(
            swa.decide_early_fire(
                dt(2026, 9, 14, 7, 1),
                dt(2026, 9, 14, 6, 30),
                dt(2026, 9, 14, 7, 0),
                dt(2026, 9, 14, 7, 0),
                "awake",
            ),
            swa.ALREADY_PAST_HARD,
        )


if __name__ == "__main__":
    unittest.main()
