"""Tests for aria_core.smart_stack_relevance, the Python port of ForgeCore's
SmartStackRelevance.swift. Translated from SmartStackRelevanceTests.swift.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import unittest

import _bootstrap  # noqa: F401

from aria_core import smart_stack_relevance as ssr  # noqa: E402

NOW = datetime.fromtimestamp(3_000_000, tz=timezone.utc)


class SmartStackRelevanceTests(unittest.TestCase):
    def test_a_live_workout_outranks_everything_else(self):
        live = ssr.score(
            active_workout_phase="active",
            tonight_wind_down=NOW,
            recommended_practice="focusReset",
            now=NOW,
        )
        self.assertEqual(live.score, ssr.LIVE_SESSION)
        self.assertIsNone(live.duration_seconds)

    def test_every_live_phase_counts(self):
        for phase in ("countdown", "active", "resting", "paused"):
            self.assertEqual(
                ssr.score(active_workout_phase=phase, now=NOW).score,
                ssr.LIVE_SESSION,
                phase,
            )

    def test_an_ended_workout_does_not_hold_the_top_slot(self):
        score = ssr.score(active_workout_phase="ended", now=NOW).score
        self.assertEqual(score, ssr.AMBIENT)

    def test_wind_down_is_relevant_around_its_window(self):
        soon = NOW + timedelta(minutes=30)
        relevance = ssr.score(tonight_wind_down=soon, now=NOW)
        self.assertEqual(relevance.score, ssr.FLAGGED)
        self.assertEqual(relevance.duration_seconds, ssr.WIND_DOWN_WINDOW_MINUTES * 60)

    def test_wind_down_stays_relevant_just_after_it_opens(self):
        passed = NOW - timedelta(minutes=30)
        self.assertEqual(ssr.score(tonight_wind_down=passed, now=NOW).score, ssr.FLAGGED)

    def test_a_distant_wind_down_is_not_urgent(self):
        hours = NOW + timedelta(hours=6)
        self.assertEqual(ssr.score(tonight_wind_down=hours, now=NOW).score, ssr.AMBIENT)

    def test_a_recommended_reset_ranks_above_ambient_and_below_wind_down(self):
        reset = ssr.score(recommended_practice="focusReset", now=NOW).score
        self.assertGreater(reset, ssr.AMBIENT)
        self.assertLess(reset, ssr.FLAGGED)

    def test_an_empty_snapshot_is_still_worth_a_glance(self):
        self.assertEqual(ssr.score(now=NOW).score, ssr.AMBIENT)

    def test_the_ordering_holds_end_to_end(self):
        live = ssr.score(active_workout_phase="active", now=NOW).score
        bedtime = ssr.score(tonight_wind_down=NOW, now=NOW).score
        reset = ssr.score(recommended_practice="boxBreathing", now=NOW).score
        idle = ssr.score(now=NOW).score
        self.assertTrue(live > bedtime > reset > idle)


if __name__ == "__main__":
    unittest.main()
