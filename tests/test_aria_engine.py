import sys
import unittest
from pathlib import Path

LAMBDA_DIR = Path(__file__).resolve().parents[1] / "infra" / "terraform" / "lambda"
sys.path.insert(0, str(LAMBDA_DIR))

from services import aria_engine  # noqa: E402
from services.aria_engine import (  # noqa: E402
    ARIAContext,
    ActivityContext,
    ChronotypeContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
)


CANONICAL_KEYS = {
    "schema_version",
    "response_type",
    "confidence",
    "confidence_reason",
    "prose_summary",
    "card",
}


def full_context(**overrides) -> ARIAContext:
    """A fully-populated, coherent (all-negative) context."""
    ctx = ARIAContext(
        sleep=SleepContext(
            duration_minutes=440,
            efficiency=0.9,
            rem_minutes=95,
            deep_minutes=70,  # 15.9% -> low deep
            hrv=58,
            resting_hr=52,
            nights_available=14,
        ),
        readiness=ReadinessContext(
            hrv_7day_trend=-12,
            hrv_30day_baseline=62,
            recovery_score=58,
            hrv_days_available=7,
        ),
        training=TrainingContext(
            last_workout_type="strength",
            last_workout_duration_minutes=60,
            hours_since_last_workout=14,
            weekly_load_score=70,
        ),
        activity=ActivityContext(steps_3day_avg=8200, active_calories_3day_avg=540),
        chronotype=ChronotypeContext(
            typical_sleep_onset="23:30", typical_wake_time="07:00", consistency_score=0.82
        ),
    )
    for key, value in overrides.items():
        setattr(ctx, key, value)
    return ctx


def has_digit(text: str) -> bool:
    return any(ch.isdigit() for ch in text)


class EnvelopeContractTests(unittest.TestCase):
    def test_every_response_carries_the_versioned_envelope(self):
        for message in ("how did I sleep?", "should I train today?", "hey"):
            resp = aria_engine.generate_response(message, full_context())
            self.assertTrue(CANONICAL_KEYS.issubset(resp.keys()), msg=message)
            self.assertEqual(resp["schema_version"], "1.0", msg=message)

    def test_prose_summary_is_mandatory_and_non_empty(self):
        for ctx in (full_context(), ARIAContext()):
            resp = aria_engine.generate_response("what should I do today?", ctx)
            self.assertIn("prose_summary", resp)
            self.assertTrue(resp["prose_summary"].strip())

    def test_low_confidence_always_has_a_reason(self):
        # Spec rule: confidence below 0.5 must carry a non-empty confidence_reason.
        resp = aria_engine.generate_response("how did I sleep?", ARIAContext(
            sleep=SleepContext(duration_minutes=400, deep_minutes=60, rem_minutes=80,
                               efficiency=0.88, nights_available=2),
            readiness=ReadinessContext(recovery_score=70),
        ))
        self.assertLess(resp["confidence"], 0.5)
        self.assertTrue(resp["confidence_reason"].strip())


class QualityBarTests(unittest.TestCase):
    def test_response_references_a_concrete_metric(self):
        # "If ARIA's response could have been generated without reading the
        # user's data, it failed."
        resp = aria_engine.generate_response("how did I sleep?", full_context())
        self.assertTrue(has_digit(resp["prose_summary"]))
        self.assertTrue(has_digit(resp["message"]))

    def test_confidence_is_calibrated_not_constant(self):
        coherent = aria_engine.generate_response("should I train?", full_context())
        # Good sleep but a sharp HRV drop -> signals conflict -> lower confidence.
        conflicted_ctx = full_context(
            sleep=SleepContext(duration_minutes=470, deep_minutes=100, rem_minutes=110,
                               efficiency=0.92, hrv=70, resting_hr=50, nights_available=14),
            readiness=ReadinessContext(hrv_7day_trend=-15, hrv_30day_baseline=62,
                                       recovery_score=70, hrv_days_available=7),
        )
        conflicted = aria_engine.generate_response("should I train?", conflicted_ctx)
        self.assertNotEqual(coherent["confidence"], 0.9)
        self.assertLess(conflicted["confidence"], coherent["confidence"])
        self.assertIn("diverge", conflicted["confidence_reason"])
        for resp in (coherent, conflicted):
            self.assertGreaterEqual(resp["confidence"], 0.1)
            self.assertLessEqual(resp["confidence"], 0.92)


class DegradedDataTests(unittest.TestCase):
    def test_under_three_nights_caps_confidence_at_point_four(self):
        ctx = ARIAContext(
            sleep=SleepContext(duration_minutes=410, deep_minutes=70, rem_minutes=85,
                               efficiency=0.9, nights_available=2),
            readiness=ReadinessContext(recovery_score=72),
        )
        resp = aria_engine.generate_response("how did I sleep?", ctx)
        self.assertLessEqual(resp["confidence"], 0.4)
        self.assertTrue(resp["confidence_reason"].strip())

    def test_no_hrv_disables_readiness_and_says_so(self):
        ctx = full_context(
            sleep=SleepContext(duration_minutes=450, deep_minutes=95, rem_minutes=100,
                               efficiency=0.9, nights_available=12),
            readiness=ReadinessContext(recovery_score=72),  # no HRV trend, no sleep hrv
        )
        ctx.sleep.hrv = None
        resp = aria_engine.generate_response("how's my readiness?", ctx)
        self.assertLessEqual(resp["confidence"], 0.65)
        self.assertIn("hrv", resp["confidence_reason"].lower())
        self.assertIn("readiness", resp["confidence_reason"].lower())

    def test_no_workout_history_asks_one_calibrating_question(self):
        ctx = full_context(training=TrainingContext())  # all None
        resp = aria_engine.generate_response("should I train hard today?", ctx)
        self.assertEqual(resp["response_type"], "recommendation")
        self.assertLessEqual(resp["confidence"], 0.7)
        self.assertTrue(any("Tell ARIA" in a for a in resp["suggested_actions"]))
        self.assertIn("last", resp["message"].lower())

    def test_no_usable_data_returns_clarification(self):
        resp = aria_engine.generate_response("hey", ARIAContext())
        self.assertEqual(resp["response_type"], "clarification")
        self.assertTrue(resp["suggested_actions"])
        self.assertTrue(resp["prose_summary"].strip())
        self.assertLess(resp["confidence"], 0.5)


class ClassificationTests(unittest.TestCase):
    def test_single_metric_lookup_is_an_insight(self):
        resp = aria_engine.generate_response("how was my sleep last night?", full_context())
        self.assertEqual(resp["response_type"], "insight")
        self.assertIn("metric", resp["card"])

    def test_advice_request_is_a_recommendation(self):
        resp = aria_engine.generate_response("what should I do today?", full_context())
        self.assertEqual(resp["response_type"], "recommendation")
        self.assertIn("action", resp["card"])

    def test_low_recovery_coaches_even_without_an_advice_verb(self):
        ctx = full_context(readiness=ReadinessContext(recovery_score=42, hrv_7day_trend=-3,
                                                       hrv_30day_baseline=60, hrv_days_available=7))
        resp = aria_engine.generate_response("morning", ctx)
        self.assertEqual(resp["response_type"], "recommendation")


class VoiceModeTests(unittest.TestCase):
    def test_voice_mode_suppresses_card_and_uses_prose(self):
        resp = aria_engine.generate_response("should I train?", full_context(), voice_mode=True)
        self.assertIsNone(resp["card"])
        self.assertEqual(resp["message"], resp["prose_summary"])
        self.assertEqual(resp["model"], aria_engine.MODEL_FAST)

    def test_voice_prose_stays_within_token_cap(self):
        resp = aria_engine.generate_response("how did I sleep?", full_context(), voice_mode=True)
        self.assertLessEqual(
            aria_engine.estimate_tokens(resp["prose_summary"]), aria_engine.VOICE_TOKEN_CAP
        )


class ModelRoutingTests(unittest.TestCase):
    def test_routing_table(self):
        self.assertEqual(aria_engine.select_model("recommendation"), aria_engine.MODEL_PRIMARY)
        self.assertEqual(aria_engine.select_model("plan"), aria_engine.MODEL_PRIMARY)
        self.assertEqual(aria_engine.select_model("summary"), aria_engine.MODEL_PRIMARY)
        self.assertEqual(aria_engine.select_model("insight"), aria_engine.MODEL_FAST)
        self.assertEqual(aria_engine.select_model("clarification"), aria_engine.MODEL_FAST)

    def test_voice_mode_always_uses_the_fast_model(self):
        self.assertEqual(
            aria_engine.select_model("recommendation", voice_mode=True), aria_engine.MODEL_FAST
        )

    def test_no_deprecated_model_ids(self):
        for retired in ("claude-opus-4-20250514", "claude-sonnet-4-20250514"):
            self.assertNotIn(retired, (aria_engine.MODEL_PRIMARY, aria_engine.MODEL_FAST))


class ContextParsingTests(unittest.TestCase):
    def test_missing_fields_lists_every_null_leaf(self):
        ctx = ARIAContext(sleep=SleepContext(duration_minutes=420))
        missing = ctx.missing_fields
        self.assertNotIn("sleep.duration_minutes", missing)
        self.assertIn("sleep.efficiency", missing)
        self.assertIn("readiness.recovery_score", missing)
        self.assertIn("chronotype.consistency_score", missing)

    def test_legacy_metrics_map_onto_structured_context(self):
        ctx = ARIAContext.from_payload({"recent_metrics": {"readiness": 48, "sleep_score": 72}})
        self.assertEqual(ctx.readiness.recovery_score, 48)
        self.assertFalse(ctx.has_sleep)  # a sleep *score* is not a duration

    def test_rich_context_payload_is_parsed(self):
        ctx = ARIAContext.from_payload({
            "context": {
                "sleep": {"durationMinutes": 430, "deepMinutes": 80, "hrv": 55},
                "readiness": {"hrv7DayTrend": -10, "recoveryScore": 60},
            }
        })
        self.assertEqual(ctx.sleep.duration_minutes, 430)
        self.assertEqual(ctx.readiness.hrv_7day_trend, -10)
        self.assertTrue(ctx.has_hrv)


class SystemPromptTests(unittest.TestCase):
    def test_prompt_encodes_the_four_required_behaviors(self):
        prompt = aria_engine.ARIA_SYSTEM_PROMPT.lower()
        self.assertIn("aria", prompt)            # identity / voice
        self.assertIn("confidence", prompt)      # confidence behavior
        self.assertIn("missing", prompt)         # missing-data declaration
        self.assertIn("prose_summary", prompt)   # output contract
        self.assertIn(aria_engine.SCHEMA_VERSION, aria_engine.ARIA_SYSTEM_PROMPT)

    def test_user_prompt_injects_the_ground_truth_block(self):
        prompt = aria_engine.build_user_prompt("should I train?", full_context())
        self.assertIn("USER MODEL", prompt)
        self.assertIn("should I train?", prompt)


if __name__ == "__main__":
    unittest.main()
