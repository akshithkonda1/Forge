"""Tests for aria_core.schedule_corrector, the Python port of ForgeCore's
ScheduleCorrector.swift + ScheduleGoalParser (task #15 of the Swift->Python
port list -- see ARIA_INTELLIGENCE_PLAN.md). Translated directly from
ScheduleCorrectorTests.swift, checked against the same fixtures and
expected values.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta

import _bootstrap  # noqa: F401

from aria_core import circadian_rhythm as cr  # noqa: E402
from aria_core import schedule_corrector as sc  # noqa: E402


def _habitual_nights(wake_hour: float, count: int, ending: datetime,
                      asleep: float = 8.0) -> list[cr.Night]:
    nights = []
    for offset in range(count):
        wake_day = ending - timedelta(days=(count - 1 - offset))
        whole = int(wake_hour)
        minute = sc._swift_round((wake_hour - whole) * 60)
        wake = wake_day.replace(hour=whole, minute=minute, second=0, microsecond=0)
        onset = wake - timedelta(hours=asleep)
        nights.append(cr.Night(onset=onset, wake=wake, asleep_hours=asleep))
    return nights


class SignedHourDeltaTests(unittest.TestCase):
    def test_prefers_the_short_way_around_midnight(self):
        self.assertAlmostEqual(sc.signed_hour_delta(23, 1), 2, places=2)
        self.assertAlmostEqual(sc.signed_hour_delta(1, 23), -2, places=2)


class ClockLabelTests(unittest.TestCase):
    def test_formats_morning_and_evening(self):
        self.assertEqual(sc.clock_label(6.0), "6:00 am")
        self.assertEqual(sc.clock_label(18.5), "6:30 pm")

    def test_midnight_and_noon(self):
        self.assertEqual(sc.clock_label(0.0), "12:00 am")
        self.assertEqual(sc.clock_label(12.0), "12:00 pm")


class ScheduleGoalTests(unittest.TestCase):
    def test_target_wake_hour_is_normalized(self):
        goal = sc.ScheduleGoal(target_wake_hour=-1.5, cutover_start=datetime(2026, 9, 1))
        self.assertAlmostEqual(goal.target_wake_hour, 22.5, places=4)

    def test_max_shift_is_clamped_to_five_through_twenty(self):
        too_low = sc.ScheduleGoal(target_wake_hour=6, cutover_start=datetime(2026, 9, 1),
                                   max_shift_minutes_per_night=1)
        too_high = sc.ScheduleGoal(target_wake_hour=6, cutover_start=datetime(2026, 9, 1),
                                    max_shift_minutes_per_night=99)
        self.assertEqual(too_low.max_shift_minutes_per_night, 5.0)
        self.assertEqual(too_high.max_shift_minutes_per_night, sc.HARD_MAX_SHIFT_MINUTES)


class ParserTests(unittest.TestCase):
    def test_reads_six_am_starting_monday(self):
        saturday = datetime(2026, 9, 12, 18, 0)
        goal = sc.parse("I need to be up at 6am starting Monday", now=saturday)
        self.assertIsNotNone(goal)
        self.assertEqual(goal.target_wake_hour, 6.0)
        self.assertEqual(goal.cutover_start.weekday(), 0)  # Monday
        self.assertEqual(goal.cutover_start.day, 14)

    def test_bare_six_is_morning(self):
        goal = sc.parse("wake me at 6 starting Tuesday", now=datetime(2026, 9, 10, 12, 0))
        self.assertIsNotNone(goal)
        self.assertEqual(goal.target_wake_hour, 6.0)

    def test_ignores_training_asks(self):
        self.assertIsNone(sc.parse("what should I train today"))
        self.assertIsNone(sc.parse("what's up at the gym"))

    def test_reads_evening_clock(self):
        goal = sc.parse("wake me at 6:30pm", now=datetime(2026, 9, 13, 12, 0))
        self.assertIsNotNone(goal)
        self.assertEqual(goal.target_wake_hour, 18.5)

    def test_is_schedule_ask_matches_parse(self):
        self.assertTrue(sc.is_schedule_ask("wake me at 6am"))
        self.assertFalse(sc.is_schedule_ask("what should I train today"))

    def test_no_weekday_cue_uses_now_as_cutover(self):
        now = datetime(2026, 9, 13, 12, 0)
        goal = sc.parse("wake me at 6am", now=now)
        self.assertEqual(goal.cutover_start, now)


class CorrectorTests(unittest.TestCase):
    def test_coaching_reply_keeps_up_at_stem(self):
        nights = _habitual_nights(8.0, 7, datetime(2026, 9, 13, 8, 0))
        goal = sc.ScheduleGoal(target_wake_hour=6.0, cutover_start=datetime(2026, 9, 1, 0, 0))
        step = sc.tonight(goal, nights, now=datetime(2026, 9, 13, 21, 0))
        self.assertIsNotNone(step)
        self.assertIn("up at", step.coaching_reply)
        self.assertIn("sleep", step.coaching_reply)
        self.assertIn("earlier", step.guidance_line)

    def test_ratchet_caps_at_fifteen_minutes(self):
        """8h habitual wake, 6am target, cutover already passed (Sept 10,
        now is Sept 13): with no cutover runway left, the shift falls
        straight back to the capped max (15min), not a fraction of the
        2h gap."""
        nights = _habitual_nights(8.0, 7, datetime(2026, 9, 13, 8, 0))
        goal = sc.ScheduleGoal(target_wake_hour=6.0, cutover_start=datetime(2026, 9, 10, 0, 0),
                                created_at=datetime(2026, 9, 10, 0, 0))
        step = sc.tonight(goal, nights, now=datetime(2026, 9, 13, 21, 0))
        self.assertIsNotNone(step)
        self.assertFalse(step.reached_target)
        self.assertAlmostEqual(step.shift_minutes_tonight, -15, delta=0.6)
        self.assertAlmostEqual(step.recommended_wake_hour, 7.75, delta=0.05)

    def test_spreads_shift_across_nights_until_cutover(self):
        """60min gap, 2 nights until the Monday cutover -> 30min planned,
        capped at 15."""
        nights = _habitual_nights(8.0, 7, datetime(2026, 9, 11, 8, 0))
        saturday = datetime(2026, 9, 12, 20, 0)
        goal = sc.ScheduleGoal(target_wake_hour=7.0, cutover_start=datetime(2026, 9, 14, 0, 0),
                                created_at=saturday)
        step = sc.tonight(goal, nights, now=saturday)
        self.assertIsNotNone(step)
        self.assertAlmostEqual(step.shift_minutes_tonight, -15, delta=0.6)

    def test_reached_when_already_on_target(self):
        nights = _habitual_nights(6.0, 7, datetime(2026, 9, 13, 6, 0))
        goal = sc.ScheduleGoal(target_wake_hour=6.0, cutover_start=datetime(2026, 9, 10, 0, 0))
        step = sc.tonight(goal, nights, now=datetime(2026, 9, 13, 21, 0))
        self.assertTrue(step.reached_target)
        self.assertAlmostEqual(step.shift_minutes_tonight, 0, delta=0.6)
        self.assertIn("on it", step.guidance_line)

    def test_bedtime_is_need_hours_before_wake(self):
        nights = _habitual_nights(8.0, 7, datetime(2026, 9, 13, 8, 0), asleep=8.0)
        goal = sc.ScheduleGoal(target_wake_hour=6.0, cutover_start=datetime(2026, 9, 1, 0, 0))
        step = sc.tonight(goal, nights, now=datetime(2026, 9, 13, 21, 0))
        self.assertIsNotNone(step)
        span = cr.normalized_hour(step.recommended_wake_hour - step.recommended_onset_hour)
        self.assertAlmostEqual(span, 8.0, delta=0.15)

    def test_inactive_goal_returns_none(self):
        nights = _habitual_nights(8.0, 7, datetime(2026, 9, 13, 8, 0))
        goal = sc.ScheduleGoal(target_wake_hour=6.0, cutover_start=datetime(2026, 9, 1, 0, 0),
                                is_active=False)
        self.assertIsNone(sc.tonight(goal, nights, now=datetime(2026, 9, 13, 21, 0)))

    def test_no_nights_means_no_phase_means_none(self):
        goal = sc.ScheduleGoal(target_wake_hour=6.0, cutover_start=datetime(2026, 9, 1, 0, 0))
        self.assertIsNone(sc.tonight(goal, [], now=datetime(2026, 9, 13, 21, 0)))


if __name__ == "__main__":
    unittest.main()
