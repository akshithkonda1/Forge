"""ARIA lifestyle habit tags: interpreter, prose, confidence, user-model block.

Locks the contract that ``habit:<id>:<domain>:<score>`` tags (at least
``sleep_variance``) reach ``generate_response``. The sleep-first gate is a
separate path (short night + falling HRV) and must not be the reason a habit
tag appears to "work".
"""
import unittest

import _bootstrap  # noqa: F401

from services import aria_engine
from services.aria_engine import (
    SLEEP_VARIANCE_HABIT_CONFIDENCE_CAP,
    _INTERPRETERS,
    _interpret_lifestyle,
)


SLEEP_VARIANCE_TAG = "habit:sleep_variance:sleep:85"


def _ctx_with_sleep_and_hrv(
    sleep_minutes: int,
    hrv_trend: float,
    hrv_days: int = 7,
    *,
    tags: list[str] | None = None,
    with_training: bool = False,
):
    training = (
        aria_engine.TrainingContext(
            last_workout_type="strength",
            last_workout_duration_minutes=55,
            hours_since_last_workout=36,
            weekly_load_score=60,
        )
        if with_training
        else aria_engine.TrainingContext()
    )
    return aria_engine.ARIAContext(
        sleep=aria_engine.SleepContext(
            duration_minutes=sleep_minutes,
            deep_minutes=90,
            rem_minutes=100,
            efficiency=0.90,
            hrv=58,
            resting_hr=58,
            nights_available=7,
        ),
        readiness=aria_engine.ReadinessContext(
            hrv_7day_trend=hrv_trend,
            hrv_30day_baseline=62,
            recovery_score=72,
            hrv_days_available=hrv_days,
        ),
        training=training,
        lifestyle=aria_engine.LifestyleContext(
            tags=list(tags or ["founder"]),
            recent_patterns=["late_caffeine"],
        ),
        profile=aria_engine.ProfileContext(
            primary_goal="general-fitness",
            experience_level="intermediate",
            coaching_style="balanced",
        ),
        progress=aria_engine.ProgressContext(),
    )


def _mentions_variance_or_irregular(text: str) -> bool:
    lowered = (text or "").lower()
    return "variance" in lowered or "irregular" in lowered


class LifestyleHabitInterpreterTests(unittest.TestCase):
    def test_interpret_lifestyle_is_registered(self):
        self.assertIn(_interpret_lifestyle, _INTERPRETERS)

    def test_sleep_variance_tag_emits_lifestyle_signal(self):
        ctx = _ctx_with_sleep_and_hrv(480, 0.0, tags=[SLEEP_VARIANCE_TAG], with_training=True)
        signal = _interpret_lifestyle(ctx)
        self.assertIsNotNone(signal)
        self.assertEqual(signal.domain, "lifestyle")
        self.assertEqual(signal.direction, "negative")
        self.assertTrue(_mentions_variance_or_irregular(signal.interpretation))

    def test_non_habit_tags_do_not_emit_a_signal(self):
        ctx = _ctx_with_sleep_and_hrv(480, 0.0, tags=["founder", "qol:62"])
        self.assertIsNone(_interpret_lifestyle(ctx))


class SleepVarianceHabitSteersProseTests(unittest.TestCase):
    """8h sleep + HRV ~0: the sleep-first gate cannot fire. Only the tag should."""

    def test_sleep_variance_habit_mentions_variance_and_caps_confidence(self):
        ctx = _ctx_with_sleep_and_hrv(
            480, 0.0, tags=[SLEEP_VARIANCE_TAG, "qol:62"], with_training=True
        )
        resp = aria_engine.generate_response("should I train hard today?", ctx)
        self.assertTrue(
            _mentions_variance_or_irregular(resp["prose_summary"]),
            msg=resp["prose_summary"],
        )
        self.assertLessEqual(resp["confidence"], SLEEP_VARIANCE_HABIT_CONFIDENCE_CAP)
        self.assertTrue(_mentions_variance_or_irregular(resp["confidence_reason"]))
        # Sleep-first gate needs short sleep + falling HRV — this path must not use it.
        self.assertNotIn("sleep debt", resp["confidence_reason"].lower())
        self.assertNotIn("sleep first", resp["prose_summary"].lower())

    def test_same_metrics_without_habit_tag_do_not_claim_variance(self):
        ctx = _ctx_with_sleep_and_hrv(480, 0.0, tags=["founder"], with_training=True)
        resp = aria_engine.generate_response("should I train hard today?", ctx)
        self.assertFalse(
            _mentions_variance_or_irregular(resp["prose_summary"]),
            msg=resp["prose_summary"],
        )
        self.assertFalse(_mentions_variance_or_irregular(resp.get("confidence_reason", "")))
        self.assertGreater(resp["confidence"], SLEEP_VARIANCE_HABIT_CONFIDENCE_CAP)
        self.assertNotIn("sleep debt", resp.get("confidence_reason", "").lower())

    def test_user_model_block_includes_lifestyle_tags(self):
        ctx = _ctx_with_sleep_and_hrv(480, 0.0, tags=[SLEEP_VARIANCE_TAG, "qol:62"])
        block = ctx.user_model_block()
        self.assertIn("lifestyle.tags:", block)
        self.assertIn(SLEEP_VARIANCE_TAG, block)
        self.assertIn("qol:62", block)
        self.assertIn("lifestyle.patterns:", block)
        self.assertIn("late_caffeine", block)


class SleepFirstGateTests(unittest.TestCase):
    def test_sleep_gate_fires_for_falling_hrv(self):
        ctx = _ctx_with_sleep_and_hrv(sleep_minutes=300, hrv_trend=-12)  # 5h + falling HRV
        resp = aria_engine.generate_response("should I train hard today?", ctx)
        self.assertEqual(resp["response_type"], "recommendation")
        self.assertIn("sleep", resp["prose_summary"].lower())
        self.assertIn("sleep first", resp["prose_summary"].lower())
        self.assertLessEqual(resp["confidence"], 0.60)

    def test_no_gate_when_sleep_ok(self):
        ctx = _ctx_with_sleep_and_hrv(sleep_minutes=480, hrv_trend=-12)  # 8h, falling HRV, no debt
        resp = aria_engine.generate_response("should I train hard today?", ctx)
        self.assertNotIn("sleep debt", resp.get("confidence_reason", "").lower())


if __name__ == "__main__":
    unittest.main()
