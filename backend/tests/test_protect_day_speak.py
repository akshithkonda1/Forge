"""Protect-day lambda speak: a real step, not the vitals-scrub fallback.

When stance is protect, card.why often carries an ACWR dump. speak_guard
promotes that into card.action after stripping a context_plan guide phrase,
and Dummy's scrub then drops every candidate to _SPEAK_FALLBACK. The engine
must emit one of the seeded protect-day lines instead.
"""

from __future__ import annotations

import re
import unittest

import _bootstrap  # noqa: F401

from services import aria_engine  # noqa: E402
from services.aria_engine import (  # noqa: E402
    ARIAContext,
    ActivityContext,
    ChronotypeContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
)

from backend.ai.simrunner.aria_simrunner import speak_quality  # noqa: E402


_DIGIT = re.compile(r"\d")
_BANNED = (
    "recover",
    "recovery",
    "rest your body",
    "injury",
    "strain",
    "poor",
    "bad",
    "debt",
    "deficit",
    "exhausted",
    "fatigued",
    "stressed",
    "under-recovered",
    "overtrained",
    "abnormal",
    "elevated",
    "your body is",
    "hrv",
    "readiness",
    "acwr",
)


def _hot_load_ctx() -> ARIAContext:
    """ACWR above the sweet spot — fusion stance is protect, pattern is overreaching."""
    return ARIAContext(
        sleep=SleepContext(
            duration_minutes=336,
            efficiency=0.9,
            rem_minutes=60,
            deep_minutes=60,
            hrv=42,
            resting_hr=54,
            nights_available=14,
        ),
        readiness=ReadinessContext(
            hrv_7day_trend=-4,
            hrv_30day_baseline=55,
            recovery_score=72,
            hrv_days_available=7,
        ),
        training=TrainingContext(
            last_workout_type="strength",
            last_workout_duration_minutes=60,
            hours_since_last_workout=18,
            weekly_load_score=80,
            acwr=1.32,
        ),
        activity=ActivityContext(steps_3day_avg=8200, active_calories_3day_avg=540),
        chronotype=ChronotypeContext(
            typical_sleep_onset="22:30", typical_wake_time="06:00", consistency_score=0.82
        ),
    )


class ProtectDayPhraseBankTests(unittest.TestCase):
    def test_every_protect_line_passes_speak_quality_with_no_banned_word_or_digit(self):
        self.assertEqual(len(aria_engine._PROTECT_DAY_STEPS), 3)
        for line in aria_engine._PROTECT_DAY_STEPS:
            self.assertTrue(line.endswith("."), line)
            self.assertIsNone(_DIGIT.search(line), line)
            self.assertFalse(re.search(r",\s+[A-Z]", line), line)
            low = line.lower()
            for word in _BANNED:
                self.assertNotIn(word, low, line)
            fails = speak_quality.speak_failures(
                {"prose_summary": line, "message": line, "card": {"action": line}}
            )
            self.assertEqual(fails, [], (line, fails))
            self.assertEqual(speak_quality.clinical_hits(line), [])
            self.assertEqual(speak_quality.vitals_hits(line), [])

    def test_different_seeds_rotate_protect_lines(self):
        picked = [aria_engine._protect_day_step(seed) for seed in (0, 1, 2)]
        self.assertEqual(set(picked), set(aria_engine._PROTECT_DAY_STEPS))
        self.assertEqual(aria_engine._protect_day_step(0), aria_engine._protect_day_step(3))
        self.assertNotEqual(aria_engine._protect_day_step(1), aria_engine._protect_day_step(2))


class ProtectDayLambdaTurnTests(unittest.TestCase):
    def test_protect_day_turn_returns_a_protect_line_not_fallback(self):
        ctx = _hot_load_ctx()
        resp = aria_engine.generate_response("Should I train today?", ctx, seed=1)
        self.assertEqual(resp["fusion"]["stance"], "protect")
        action = (resp.get("card") or {}).get("action")
        self.assertIn(action, aria_engine._PROTECT_DAY_STEPS)
        self.assertNotEqual(action, aria_engine._SPEAK_FALLBACK)
        self.assertNotEqual(action, aria_engine._DUMMY_SPEAK_FALLBACK)
        self.assertNotIn("let's pick one next step", (action or "").lower())
        self.assertNotIn("acwr", (action or "").lower())

    def test_protect_day_turn_seed_rotates_the_step(self):
        ctx = _hot_load_ctx()
        first = aria_engine.generate_response("Should I train today?", ctx, seed=0)["card"]["action"]
        second = aria_engine.generate_response("Should I train today?", ctx, seed=1)["card"]["action"]
        self.assertIn(first, aria_engine._PROTECT_DAY_STEPS)
        self.assertIn(second, aria_engine._PROTECT_DAY_STEPS)
        self.assertNotEqual(first, second)


if __name__ == "__main__":
    unittest.main()
