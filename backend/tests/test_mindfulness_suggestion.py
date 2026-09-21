"""Tests for aria_core.mindfulness_suggestion, the Python port of ForgeCore's
MindfulnessSuggestionEngine.swift. Translated from
MindfulnessSuggestionEngineTests.swift (breathing-pattern Canvas tests stay
on the client).
"""

from __future__ import annotations

from datetime import datetime, timezone
import unittest

import _bootstrap  # noqa: F401

from aria_core import aria_day_brief  # noqa: E402
from aria_core import mindfulness_suggestion as ms  # noqa: E402
from aria_core.watch_context import WatchContext  # noqa: E402


def context(hour: int) -> WatchContext:
    stamp = datetime(2026, 9, 20, hour, 0, tzinfo=timezone.utc)
    return WatchContext(
        timestamp=stamp,
        readiness_overall=75,
        readiness_confidence=0.9,
    )


class MindfulnessSuggestionTests(unittest.TestCase):
    def test_long_desk_block_with_hrv_dip_suggests_90_second_sigh(self):
        ctx = context(14)
        ctx.lifestyle_mode = "deskCoding"
        ctx.minutes_in_current_mode = 95
        ctx.hrv_trend_ms = -8
        rec = ms.suggest(ctx)
        self.assertEqual(rec.practice, "physiologicalSigh")
        self.assertEqual(rec.duration, 90)
        self.assertEqual(rec.trigger, "desk-block-hrv-dip")

    def test_long_desk_block_without_dip_suggests_focus_reset(self):
        ctx = context(14)
        ctx.lifestyle_mode = "deepFocus"
        ctx.minutes_in_current_mode = 120
        rec = ms.suggest(ctx)
        self.assertEqual(rec.practice, "focusReset")
        self.assertEqual(rec.trigger, "desk-block-90m")

    def test_short_desk_block_does_not_trigger_desk_rule(self):
        ctx = context(14)
        ctx.lifestyle_mode = "deskCoding"
        ctx.minutes_in_current_mode = 30
        rec = ms.suggest(ctx)
        self.assertNotEqual(rec.trigger, "desk-block-90m")

    def test_post_workout_wins_over_everything(self):
        ctx = context(14)
        ctx.hours_since_last_workout = 0.25
        ctx.lifestyle_mode = "deskCoding"
        ctx.minutes_in_current_mode = 200
        ctx.hrv_trend_ms = -10
        rec = ms.suggest(ctx)
        self.assertEqual(rec.practice, "bodyScan")
        self.assertEqual(rec.trigger, "post-workout-reset")

    def test_elevated_wrist_temperature_suggests_ease_not_diagnosis(self):
        ctx = context(14)
        ctx.wrist_temperature_deviation_c = 0.7
        rec = ms.suggest(ctx)
        self.assertEqual(rec.trigger, "elevated-temperature")
        self.assertIn("clinician", rec.reason.lower())
        self.assertNotIn("you have a fever", rec.reason.lower())

    def test_post_workout_still_wins_over_high_temperature(self):
        ctx = context(14)
        ctx.hours_since_last_workout = 0.25
        ctx.body_temperature_f = 100.6
        self.assertEqual(ms.suggest(ctx).trigger, "post-workout-reset")

    def test_greeting_mentions_high_wrist_temperature(self):
        ctx = context(9)
        ctx.readiness_overall = 70
        ctx.readiness_confidence = 0.9
        ctx.wrist_temperature_deviation_c = 0.9
        line = ms.greeting(ctx, user_name="Sam")
        self.assertIn("temperature", line.lower())

    def test_evening_suggests_wind_down(self):
        rec = ms.suggest(context(21))
        self.assertEqual(rec.practice, "windDown")

    def test_evening_after_poor_sleep_extends_wind_down(self):
        poor = context(21)
        poor.sleep_quality_score = 40
        good = context(21)
        good.sleep_quality_score = 90
        self.assertGreater(ms.suggest(poor).duration, ms.suggest(good).duration)

    def test_low_readiness_morning_is_gentle(self):
        ctx = context(7)
        ctx.readiness_overall = 42
        rec = ms.suggest(ctx)
        self.assertEqual(rec.practice, "morningGrounding")
        self.assertEqual(rec.trigger, "low-readiness-morning")

    def test_low_confidence_readiness_is_not_treated_as_fact(self):
        ctx = context(15)
        ctx.readiness_overall = 30
        ctx.readiness_confidence = 0.1
        rec = ms.suggest(ctx)
        self.assertNotEqual(rec.trigger, "low-readiness")

    def test_every_recommendation_has_supportive_non_empty_reason(self):
        contexts = []
        for hour in (7, 12, 15, 21):
            ctx = context(hour)
            contexts.append(ctx)
            desk = context(hour)
            desk.lifestyle_mode = "deskCoding"
            desk.minutes_in_current_mode = 100
            contexts.append(desk)
            dip = context(hour)
            dip.lifestyle_mode = "deskCoding"
            dip.minutes_in_current_mode = 100
            dip.hrv_trend_ms = -9
            contexts.append(dip)
        for ctx in contexts:
            rec = ms.suggest(ctx)
            self.assertTrue(rec.reason)
            sentences = [s for s in rec.reason.replace("!", ".").replace("?", ".").split(".") if s.strip()]
            self.assertLessEqual(len(sentences), 2, rec.reason)
            lowered = rec.reason.lower()
            for banned in ("should have", "failed", "lazy", "guilt", "missed your"):
                self.assertNotIn(banned, lowered)

    def test_greeting_without_data_is_honest(self):
        ctx = context(9)
        ctx.readiness_overall = None
        ctx.readiness_confidence = None
        greeting = ms.greeting(ctx)
        self.assertIn("still gathering", greeting)

    def test_recent_skip_too_busy_shortens_suggestion(self):
        ctx = context(14)
        ctx.lifestyle_mode = "deskCoding"
        ctx.minutes_in_current_mode = 120
        ctx.recent_skip_reason = "tooBusy"
        rec = ms.suggest(ctx)
        self.assertLessEqual(rec.duration, 90)
        self.assertIn("short-after-skip", rec.trigger)

    def test_recent_skip_already_did_one_acknowledges_without_guilt(self):
        ctx = context(14)
        ctx.recent_skip_reason = "alreadyDidOne"
        rec = ms.suggest(ctx)
        self.assertEqual(rec.practice, "focusReset")
        self.assertIn("counts", rec.reason.lower())
        self.assertNotIn("should have", rec.reason.lower())

    def test_day_brief_includes_readiness_and_next_action(self):
        ctx = context(9)
        ctx.readiness_overall = 72
        ctx.readiness_confidence = 0.9
        ctx.sleep_quality_score = 82
        rec = ms.suggest(ctx)
        brief = aria_day_brief.line(ctx, rec)
        self.assertIn("Readiness 72", brief)
        self.assertIn("sleep", brief.lower())
        self.assertIn("Next:", brief)


if __name__ == "__main__":
    unittest.main()
