"""Tests for aria_core.wind_down_predictor, the Python port of ForgeCore's
WindDownPredictor.swift (task #14 of the Swift->Python port list -- see
ARIA_INTELLIGENCE_PLAN.md).

No Swift test file exists for this module (unlike CircadianRhythmTests.swift
or SleepDepthScorerTests.swift), so every expected value below was
hand-derived from the algorithm itself -- traced step by step in the
docstring of each test -- rather than read off a reference implementation.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta

import _bootstrap  # noqa: F401

from aria_core import wind_down_predictor as wdp  # noqa: E402


class MinutesSinceNoonTests(unittest.TestCase):
    def test_examples_from_the_swift_source_comment(self):
        self.assertEqual(wdp.minutes_since_noon(datetime(2026, 3, 1, 22, 30)), 630)
        self.assertEqual(wdp.minutes_since_noon(datetime(2026, 3, 1, 0, 15)), 735)

    def test_noon_itself_is_zero(self):
        self.assertEqual(wdp.minutes_since_noon(datetime(2026, 3, 1, 12, 0)), 0)

    def test_just_before_noon_wraps_to_near_the_top(self):
        # 11:59 -> (11*60+59) - 720 = -1 -> +1440 = 1439.
        self.assertEqual(wdp.minutes_since_noon(datetime(2026, 3, 1, 11, 59)), 1439)


class PlanGuardTests(unittest.TestCase):
    def test_fewer_than_three_onsets_returns_none(self):
        now = datetime(2026, 3, 1, 20, 0)
        self.assertIsNone(wdp.plan([], [], now=now))
        self.assertIsNone(wdp.plan([datetime(2026, 2, 27, 23, 0)], [420.0], now=now))
        two = [datetime(2026, 2, 27, 23, 0), datetime(2026, 2, 28, 23, 0)]
        self.assertIsNone(wdp.plan(two, [420.0, 420.0], now=now))

    def test_exactly_three_onsets_is_enough(self):
        onsets = [datetime(2026, 2, d, 23, 0) for d in (26, 27, 28)]
        result = wdp.plan(onsets, [480.0, 480.0, 480.0], now=datetime(2026, 3, 1, 20, 0))
        self.assertIsNotNone(result)


class BasicWindowTests(unittest.TestCase):
    def test_no_debt_window_opens_at_the_typical_onset_tonight(self):
        """Three identical 23:00 onsets, 8h sleep each night (== the 480min
        default need, so zero shortfall/debt). now=21:00 today.

        median onset minutes-since-noon: 23:00 -> (23*60)-720 = 660.
        debt = 0 (no shortfall) -> shift = 0 -> target = 660.
        noon(today) + 660min = today 22:00? No: 660 min = 11h -> 12:00+11:00
        = 23:00. window_start = today 23:00. (window_start - now) = 2h,
        not > 20h, so no day pull-back.
        wind_down_start = 22:40, bedtime_window_end = 23:45.
        """
        now = datetime(2026, 3, 1, 21, 0)
        onsets = [datetime(2026, 2, d, 23, 0) for d in (26, 27, 28)]
        sleep_minutes = [480.0, 480.0, 480.0]
        result = wdp.plan(onsets, sleep_minutes, now=now)

        self.assertEqual(result.bedtime_window_start, datetime(2026, 3, 1, 23, 0))
        self.assertEqual(result.wind_down_start, datetime(2026, 3, 1, 22, 40))
        self.assertEqual(result.bedtime_window_end, datetime(2026, 3, 1, 23, 45))

    def test_window_end_and_wind_down_start_are_fixed_offsets_from_window_start(self):
        now = datetime(2026, 3, 1, 15, 0)
        onsets = [datetime(2026, 2, d, 22, 0) for d in (26, 27, 28)]
        result = wdp.plan(onsets, [420.0, 420.0, 420.0], now=now)
        self.assertEqual(result.wind_down_start, result.bedtime_window_start - timedelta(minutes=20))
        self.assertEqual(result.bedtime_window_end, result.bedtime_window_start + timedelta(minutes=45))


class SleepDebtShiftTests(unittest.TestCase):
    def test_debt_pulls_the_window_earlier(self):
        """Three 23:00 onsets (median 660 min-since-noon), but only 6h
        (360min) actual sleep each night against the default 480min need:
        shortfall = 120min/night -> mean debt = 120 -> shift = min(60, 45)
        = 45 (capped). target = 660 - 45 = 615 min = 10h15m past noon
        -> 22:15.
        """
        now = datetime(2026, 3, 1, 20, 0)
        onsets = [datetime(2026, 2, d, 23, 0) for d in (26, 27, 28)]
        result = wdp.plan(onsets, [360.0, 360.0, 360.0], now=now)
        self.assertEqual(result.bedtime_window_start, datetime(2026, 3, 1, 22, 15))

    def test_shift_is_capped_at_max_earlier_shift_minutes(self):
        """A catastrophic debt (shortfall 480min/night, i.e. zero sleep)
        would imply shift=240, but the cap holds it to 45 -- same result
        as the exactly-90-minute-debt case above (both saturate the cap)."""
        now = datetime(2026, 3, 1, 20, 0)
        onsets = [datetime(2026, 2, d, 23, 0) for d in (26, 27, 28)]
        extreme = wdp.plan(onsets, [0.0, 0.0, 0.0], now=now)
        at_cap = wdp.plan(onsets, [360.0, 360.0, 360.0], now=now)  # debt=120 -> shift saturates at 45 too
        self.assertEqual(extreme.bedtime_window_start, at_cap.bedtime_window_start)
        self.assertEqual(extreme.bedtime_window_start, datetime(2026, 3, 1, 22, 15))

    def test_shift_below_the_cap_is_not_clamped(self):
        """Shortfall 89min/night on average -> shift = 44.5min (below the
        45min cap, so it applies exactly, including the half-minute)."""
        now = datetime(2026, 3, 1, 20, 0)
        onsets = [datetime(2026, 2, d, 23, 0) for d in (26, 27, 28)]  # median 660
        # need 480, actual 391 -> shortfall 89 each night -> debt=89 -> shift=44.5
        result = wdp.plan(onsets, [391.0, 391.0, 391.0], now=now)
        target_minutes = 660 - 44.5
        expected = datetime(2026, 3, 1, 12, 0) + timedelta(minutes=target_minutes)
        self.assertEqual(result.bedtime_window_start, expected)

    def test_empty_sleep_minutes_means_zero_debt(self):
        now = datetime(2026, 3, 1, 20, 0)
        onsets = [datetime(2026, 2, d, 23, 0) for d in (26, 27, 28)]
        result = wdp.plan(onsets, [], now=now)
        self.assertEqual(result.bedtime_window_start, datetime(2026, 3, 1, 23, 0))


class MidnightCrossingTests(unittest.TestCase):
    def test_after_midnight_now_pulls_the_window_back_a_day(self):
        """now=01:00 on Mar 2. Typical onset 23:00 (median 660, no debt).
        Naive same-day-noon anchor gives window_start = Mar 2 23:00, which
        is 22h ahead of now -- past the 20h threshold, so it is pulled back
        a day to Mar 1 23:00 (the window that actually governs "tonight"
        from the perspective of someone already up past midnight).
        """
        now = datetime(2026, 3, 2, 1, 0)
        onsets = [datetime(2026, 2, d, 23, 0) for d in (26, 27, 28)]
        result = wdp.plan(onsets, [480.0, 480.0, 480.0], now=now)
        self.assertEqual(result.bedtime_window_start, datetime(2026, 3, 1, 23, 0))

    def test_exactly_at_the_twenty_hour_threshold_does_not_pull_back(self):
        """window_start - now == exactly 20h must NOT trigger the pull-back
        (Swift's guard is strictly `> 20 * 3600`)."""
        now = datetime(2026, 3, 1, 3, 0)
        onsets = [datetime(2026, 2, d, 23, 0) for d in (26, 27, 28)]  # median 660 -> 23:00
        result = wdp.plan(onsets, [480.0, 480.0, 480.0], now=now)
        # today's noon + 660min = today 23:00; 23:00 - 03:00 = 20h exactly.
        self.assertEqual(result.bedtime_window_start, datetime(2026, 3, 1, 23, 0))

    def test_just_over_the_threshold_pulls_back(self):
        now = datetime(2026, 3, 1, 2, 59)
        onsets = [datetime(2026, 2, d, 23, 0) for d in (26, 27, 28)]
        result = wdp.plan(onsets, [480.0, 480.0, 480.0], now=now)
        self.assertEqual(result.bedtime_window_start, datetime(2026, 2, 28, 23, 0))


class MedianSelectionTests(unittest.TestCase):
    def test_uses_the_upper_middle_element_not_the_statistical_median(self):
        """Four onsets -> minutes-since-noon sorted [600, 620, 640, 700].
        Swift's `onsetMinutes[onsetMinutes.count / 2]` takes index 4//2=2
        -> 640 (22:40), not the statistical median (630, the average of
        the two middle values 620 and 640). This pins that this port must
        not "improve" on the Swift algorithm by using statistics.median.

        600 min -> 12:00+10:00 = 22:00
        620 min -> 12:00+10:20 = 22:20
        640 min -> 12:00+10:40 = 22:40
        700 min -> 12:00+11:40 = 23:40
        """
        now = datetime(2026, 3, 1, 15, 0)
        onsets = [
            datetime(2026, 2, 25, 22, 0),
            datetime(2026, 2, 26, 22, 20),
            datetime(2026, 2, 27, 22, 40),
            datetime(2026, 2, 28, 23, 40),
        ]
        result = wdp.plan(onsets, [480.0] * 4, now=now)
        self.assertEqual(result.bedtime_window_start, datetime(2026, 3, 1, 22, 40))


if __name__ == "__main__":
    unittest.main()
