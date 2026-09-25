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
_THEN_CALL_IT = re.compile(r"then call it\.?$", re.I)
_EM_EN_DASH = re.compile(r"[—–]|\s-\s")
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
    "honest",
)


def _all_day_banks() -> tuple[str, ...]:
    return (
        aria_engine._PROTECT_DAY_STEPS
        + aria_engine._PROCEED_DAY_STEPS
        + aria_engine._CLARIFY_DAY_STEPS
    )


def _assert_line_clean(test: unittest.TestCase, line: str) -> None:
    test.assertTrue(line.endswith("."), line)
    test.assertIsNone(_DIGIT.search(line), line)
    test.assertIsNone(_EM_EN_DASH.search(line), line)
    test.assertFalse(re.search(r",\s+[A-Z]", line), line)
    test.assertNotIn("honest", line.lower(), line)
    for word in _BANNED:
        test.assertNotIn(word, line.lower(), line)
    fails = speak_quality.speak_failures(
        {"prose_summary": line, "message": line, "card": {"action": line}}
    )
    test.assertEqual(fails, [], (line, fails))
    test.assertEqual(speak_quality.clinical_hits(line), [])
    test.assertEqual(speak_quality.vitals_hits(line), [])
    test.assertEqual(speak_quality.label_hits(line), [])
    test.assertEqual(speak_quality.bare_label_hits(line), [])
    test.assertEqual(speak_quality.dash_capital_hits(line), [])


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
            _assert_line_clean(self, line)

    def test_different_seeds_rotate_protect_lines(self):
        picked = [aria_engine._protect_day_step(seed) for seed in (0, 1, 2)]
        self.assertEqual(set(picked), set(aria_engine._PROTECT_DAY_STEPS))
        self.assertEqual(aria_engine._protect_day_step(0), aria_engine._protect_day_step(3))
        self.assertNotEqual(aria_engine._protect_day_step(1), aria_engine._protect_day_step(2))


class DayStepBankQualityTests(unittest.TestCase):
    def test_every_line_in_all_three_banks_passes_speak_quality(self):
        self.assertEqual(len(aria_engine._PROTECT_DAY_STEPS), 3)
        self.assertEqual(len(aria_engine._PROCEED_DAY_STEPS), 3)
        self.assertEqual(len(aria_engine._CLARIFY_DAY_STEPS), 3)
        for line in _all_day_banks():
            _assert_line_clean(self, line)

    def test_then_call_it_appears_at_most_once_across_banks(self):
        endings = [line for line in _all_day_banks() if _THEN_CALL_IT.search(line.strip())]
        self.assertLessEqual(len(endings), 1, endings)

    def test_no_honest_and_no_digits_in_any_bank(self):
        for line in _all_day_banks():
            self.assertNotIn("honest", line.lower(), line)
            self.assertIsNone(_DIGIT.search(line), line)

    def test_banks_rotate_by_seed(self):
        protect = [aria_engine._protect_day_step(seed) for seed in (0, 1, 2)]
        proceed = [aria_engine._proceed_day_step(seed) for seed in (0, 1, 2)]
        clarify = [aria_engine._clarify_day_step(seed) for seed in (0, 1, 2)]
        self.assertEqual(set(protect), set(aria_engine._PROTECT_DAY_STEPS))
        self.assertEqual(set(proceed), set(aria_engine._PROCEED_DAY_STEPS))
        self.assertEqual(set(clarify), set(aria_engine._CLARIFY_DAY_STEPS))
        self.assertNotEqual(protect[0], protect[1])
        self.assertNotEqual(proceed[1], proceed[2])
        self.assertNotEqual(clarify[0], clarify[2])


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


class ProceedDayGuideLeakRescueTests(unittest.TestCase):
    """Sonnet / Command-R+ fallbacks: same guide-leak, proceed/clarify stance."""

    def test_proceed_dirty_acwr_action_becomes_proceed_line(self):
        envelope = {
            "prose_summary": "Signals look steady.",
            "message": "Signals look steady.",
            "confidence": 0.7,
            "card": {"action": "ACWR 0.63 is light — room to progress load."},
            "fusion": {"stance": "proceed"},
        }
        ctx = ARIAContext()
        out = aria_engine._finish_spoken_envelope(
            envelope, ctx, "Should I train today?", seed=0
        )
        action = (out.get("card") or {}).get("action")
        self.assertIn(action, aria_engine._PROCEED_DAY_STEPS)
        self.assertNotEqual(action, aria_engine._DUMMY_SPEAK_FALLBACK)

    def test_clarify_sleep_stage_action_becomes_clarify_line(self):
        envelope = {
            "prose_summary": "Last night is on the page.",
            "message": "Last night is on the page.",
            "confidence": 0.6,
            "card": {
                "action": (
                    "Sleep: deep sleep is 12% of the night, under your usual — "
                    "protect your 23:00 wind-down tonight."
                )
            },
            "fusion": {"stance": "clarify"},
        }
        ctx = ARIAContext()
        out = aria_engine._finish_spoken_envelope(
            envelope, ctx, "Should I train today?", seed=1
        )
        action = (out.get("card") or {}).get("action")
        self.assertIn(action, aria_engine._CLARIFY_DAY_STEPS)
        self.assertNotIn(action, aria_engine._PROCEED_DAY_STEPS)
        self.assertFalse(any(ch.isdigit() for ch in action))

    def test_clarify_turn_never_reuses_a_proceed_line(self):
        ctx = ARIAContext()
        dirty = (
            "Sleep: deep sleep is 12% of the night, under your usual — "
            "protect your 23:00 wind-down tonight."
        )
        picked = []
        for seed in (0, 1, 2, 3, 4, 5):
            envelope = {
                "prose_summary": "Last night is on the page.",
                "message": "Last night is on the page.",
                "confidence": 0.6,
                "card": {"action": dirty},
                "fusion": {"stance": "clarify"},
            }
            out = aria_engine._finish_spoken_envelope(
                envelope, ctx, "Should I train today?", seed=seed
            )
            action = (out.get("card") or {}).get("action")
            picked.append(action)
            self.assertIn(action, aria_engine._CLARIFY_DAY_STEPS)
            self.assertNotIn(action, aria_engine._PROCEED_DAY_STEPS)
            self.assertNotIn(action, aria_engine._PROTECT_DAY_STEPS)
        self.assertEqual(set(picked), set(aria_engine._CLARIFY_DAY_STEPS))

    def test_proceed_lines_pass_speak_quality(self):
        for line in aria_engine._PROCEED_DAY_STEPS:
            _assert_line_clean(self, line)

    def test_clarify_lines_pass_speak_quality(self):
        for line in aria_engine._CLARIFY_DAY_STEPS:
            _assert_line_clean(self, line)

    def test_different_seeds_rotate_proceed_and_clarify_lines(self):
        self.assertNotEqual(
            aria_engine._proceed_day_step(0), aria_engine._proceed_day_step(1)
        )
        self.assertNotEqual(
            aria_engine._clarify_day_step(0), aria_engine._clarify_day_step(1)
        )
        self.assertEqual(
            aria_engine._clarify_day_step(0), aria_engine._clarify_day_step(3)
        )


if __name__ == "__main__":
    unittest.main()
