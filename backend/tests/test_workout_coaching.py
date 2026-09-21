"""Tests for aria_core.workout_coaching, the Python port of ForgeCore's
WorkoutCoaching.swift. Translated from WorkoutCoachingTests.swift.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import unittest

import _bootstrap  # noqa: F401

from aria_core import hr_zones  # noqa: E402
from aria_core import workout_coaching as wc  # noqa: E402

T0 = datetime.fromtimestamp(2_000_000, tz=timezone.utc)
DISTANT = datetime.fromtimestamp(0, tz=timezone.utc)

_BPM = {0: 100, 1: 100, 2: 120, 3: 140, 4: 155, 5: 175}


def zone(n: int):
    return hr_zones.zone_for_bpm(_BPM.get(n, 100))


class WorkoutCoachingTests(unittest.TestCase):
    def test_no_cue_without_a_zone_change(self):
        self.assertIsNone(wc.cue(zone(3), 3, 3, DISTANT, T0))

    def test_first_zone_reading_cues(self):
        decision = wc.cue(zone(3), None, 3, DISTANT, T0)
        self.assertIsNotNone(decision)
        self.assertEqual(decision.fired_at, T0)

    def test_throttle_suppresses_a_rapid_second_cue(self):
        self.assertIsNone(wc.cue(zone(4), 3, 3, T0, T0 + timedelta(seconds=10)))

    def test_throttle_releases_after_the_window(self):
        later = T0 + timedelta(seconds=wc.THROTTLE_SECONDS + 1)
        self.assertIsNotNone(wc.cue(zone(4), 3, 3, T0, later))

    def test_well_above_target_suggests_easing_without_instructing(self):
        cue = wc.cue(zone(5), 3, 3, DISTANT, T0).cue
        self.assertIn("easing off", cue)
        self.assertIn("Your call", cue)

    def test_well_below_target_offers_headroom(self):
        cue = wc.cue(zone(1), 3, 4, DISTANT, T0).cue
        self.assertIn("Plenty in reserve", cue)
        self.assertIn("No rush", cue)

    def test_mobility_and_yoga_are_never_told_to_go_harder(self):
        cue = wc.cue(zone(1), 3, 4, DISTANT, T0, allows_building_up=False).cue
        self.assertNotIn("Plenty in reserve", cue)

    def test_one_zone_off_target_is_still_just_the_zone_line(self):
        cue = wc.cue(zone(4), 2, 3, DISTANT, T0).cue
        self.assertEqual(cue, zone(4).coaching_line)

    def test_fired_at_is_the_instant_to_carry_forward(self):
        now = T0 + timedelta(seconds=500)
        decision = wc.cue(zone(2), 1, 3, T0, now)
        self.assertEqual(decision.fired_at, now)


class HRZoneTests(unittest.TestCase):
    def test_thresholds_match_swift(self):
        self.assertEqual(hr_zones.zone_for_bpm(109).zone, 1)
        self.assertEqual(hr_zones.zone_for_bpm(110).zone, 2)
        self.assertEqual(hr_zones.zone_for_bpm(129).zone, 2)
        self.assertEqual(hr_zones.zone_for_bpm(130).zone, 3)
        self.assertEqual(hr_zones.zone_for_bpm(165).zone, 5)

    def test_zone_for_number(self):
        self.assertEqual(hr_zones.zone_for_number(1).zone, 1)
        self.assertEqual(hr_zones.zone_for_number(2).zone, 2)
        self.assertEqual(hr_zones.zone_for_number(5).zone, 5)


if __name__ == "__main__":
    unittest.main()
