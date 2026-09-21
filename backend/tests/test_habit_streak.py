"""Tests for aria_core.habit_streak, the Python port of ForgeCore's
HabitStreak.swift. Translated from HabitStreakTests.swift.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
import unittest

import _bootstrap  # noqa: F401

from aria_core import habit_streak as hs  # noqa: E402

TODAY = date(2026, 9, 20)


def day(offset: int, from_day: date = TODAY) -> date:
    return from_day + timedelta(days=offset)


class HabitStreakTests(unittest.TestCase):
    def test_empty_history_is_zero(self):
        self.assertEqual(hs.length([], today=TODAY), 0)

    def test_run_ending_today_counts_every_day(self):
        days = [day(-n) for n in range(5)]
        self.assertEqual(hs.length(days, today=TODAY), 5)

    def test_run_ending_yesterday_still_counts_before_today_qualifies(self):
        days = [day(-n) for n in range(1, 4)]
        self.assertEqual(hs.length(days, today=TODAY), 3)

    def test_gap_breaks_the_run(self):
        days = [day(0), day(-1), day(-3), day(-4)]
        self.assertEqual(hs.length(days, today=TODAY), 2)

    def test_missing_today_and_yesterday_is_zero(self):
        days = [day(-2), day(-3)]
        self.assertEqual(hs.length(days, today=TODAY), 0)

    def test_time_of_day_does_not_split_a_day(self):
        morning = datetime(2026, 9, 20, 6, tzinfo=timezone.utc)
        night = datetime(2026, 9, 19, 23, tzinfo=timezone.utc)
        self.assertEqual(hs.length([morning, night], today=TODAY), 2)

    def test_qualifies_threshold(self):
        self.assertFalse(hs.qualifies(0, 0))
        self.assertFalse(hs.qualifies(3, 6))
        self.assertTrue(hs.qualifies(4, 6))
        self.assertTrue(hs.qualifies(3, 5))

    def test_recording_adds_is_idempotent_and_removes(self):
        days = hs.recording(TODAY, True, [])
        days = hs.recording(TODAY, True, days)
        self.assertEqual(len(days), 1)
        days = hs.recording(TODAY, False, days)
        self.assertEqual(days, [])

    def test_recording_trims_to_retained_window(self):
        days: list[date] = []
        for offset in range(hs.RETAINED_DAYS + 10):
            days = hs.recording(day(-offset), True, days)
        self.assertEqual(len(days), hs.RETAINED_DAYS)
        self.assertEqual(days[-1], TODAY)


if __name__ == "__main__":
    unittest.main()
