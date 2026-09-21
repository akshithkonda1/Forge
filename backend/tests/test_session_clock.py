"""Tests for aria_core.session_clock, the Python port of ForgeCore's
SessionClock.swift. Translated from SessionClockTests.swift.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import unittest

import _bootstrap  # noqa: F401

from aria_core.session_clock import SessionClock  # noqa: E402

T0 = datetime.fromtimestamp(1_000_000, tz=timezone.utc)


def at(seconds: float) -> datetime:
    return T0 + timedelta(seconds=seconds)


class SessionClockTests(unittest.TestCase):
    def test_elapsed_is_zero_before_anything_starts(self):
        clock = SessionClock()
        self.assertEqual(clock.elapsed(T0), 0)
        self.assertFalse(clock.is_running)

    def test_running_clock_accumulates_real_time(self):
        clock = SessionClock.started(T0)
        self.assertTrue(clock.is_running)
        self.assertEqual(clock.elapsed(at(30)), 30)

    def test_paused_clock_stops(self):
        clock = SessionClock.started(T0).paused(at(30))
        self.assertFalse(clock.is_running)
        self.assertEqual(clock.elapsed(at(300)), 30)

    def test_resume_continues_from_where_it_stopped(self):
        clock = SessionClock.started(T0).paused(at(30)).resumed(at(300))
        self.assertEqual(clock.elapsed(at(310)), 40)

    def test_several_pauses_compose(self):
        clock = SessionClock.started(T0)
        clock = clock.paused(at(10))
        clock = clock.resumed(at(100))
        clock = clock.paused(at(120))
        clock = clock.resumed(at(200))
        self.assertEqual(clock.elapsed(at(205)), 35)

    def test_pausing_twice_does_not_double_count(self):
        once = SessionClock.started(T0).paused(at(30))
        twice = once.paused(at(90))
        self.assertEqual(twice, once)
        self.assertEqual(twice.elapsed(at(90)), 30)

    def test_resuming_a_running_clock_does_not_discard_the_segment(self):
        clock = SessionClock.started(T0)
        again = clock.resumed(at(30))
        self.assertEqual(again, clock)
        self.assertEqual(again.elapsed(at(30)), 30)

    def test_backwards_clock_cannot_subtract_practised_time(self):
        clock = SessionClock(accumulated=60, segment_started_at=T0)
        self.assertEqual(clock.elapsed(at(-45)), 60)

    def test_stopped_banks_the_running_segment(self):
        clock = SessionClock.started(T0).stopped(at(42))
        self.assertEqual(clock.accumulated, 42)
        self.assertFalse(clock.is_running)

    def test_completed_credits_the_plan_not_the_tick(self):
        clock = SessionClock.started(T0).completed(180)
        self.assertEqual(clock.accumulated, 180)
        self.assertFalse(clock.is_running)

    def test_remaining_and_completion(self):
        clock = SessionClock.started(T0)
        self.assertEqual(clock.remaining(at(60), 180), 120)
        self.assertFalse(clock.is_complete(at(179), 180))
        self.assertTrue(clock.is_complete(at(180), 180))
        self.assertEqual(clock.remaining(at(500), 180), 0)

    def test_thirty_second_logging_bar_survives_a_pause(self):
        clock = (
            SessionClock.started(T0)
            .paused(at(20))
            .resumed(at(3600))
            .stopped(at(3615))
        )
        self.assertEqual(clock.accumulated, 35)
        self.assertGreaterEqual(clock.accumulated, 30)


if __name__ == "__main__":
    unittest.main()
