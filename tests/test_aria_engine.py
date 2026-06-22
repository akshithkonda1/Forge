import json
import os
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
    "restricted_domains",
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
            self.assertEqual(resp["schema_version"], aria_engine.SCHEMA_VERSION, msg=message)

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


class DataPermissionParsingTests(unittest.TestCase):
    def test_per_domain_bool_map(self):
        perms = aria_engine.DataPermissions.from_payload({"sleep": False, "training": True})
        self.assertFalse(perms.allows("sleep"))
        self.assertTrue(perms.allows("training"))
        self.assertEqual(perms.restricted(), ["sleep"])

    def test_allow_list_denies_everything_else(self):
        perms = aria_engine.DataPermissions.from_payload(["sleep", "readiness"])
        self.assertTrue(perms.allows("sleep"))
        self.assertTrue(perms.allows("readiness"))
        self.assertFalse(perms.allows("nutrition"))

    def test_explicit_allow_deny_object(self):
        perms = aria_engine.DataPermissions.from_payload({"deny": ["training"]})
        self.assertFalse(perms.allows("training"))
        self.assertTrue(perms.allows("sleep"))  # default allow for the rest

    def test_aliases_map_to_canonical_domains(self):
        perms = aria_engine.DataPermissions.from_payload({"workouts": False, "recovery": False})
        self.assertFalse(perms.allows("training"))
        self.assertFalse(perms.allows("readiness"))
        self.assertIsNone(aria_engine.normalize_domain("not-a-domain"))
        self.assertEqual(aria_engine.normalize_domain("weight"), "body")

    def test_default_is_allow_all_when_unspecified(self):
        perms = aria_engine.DataPermissions.from_payload(None)
        self.assertEqual(perms.restricted(), [])


class PermissionEnforcementTests(unittest.TestCase):
    def test_denied_domain_is_redacted_before_reasoning(self):
        ctx = full_context()
        perms = aria_engine.DataPermissions.from_payload({"training": False})
        sanitized, restricted = aria_engine.apply_permissions(ctx, perms)
        self.assertEqual(restricted, ["training"])
        self.assertIsNone(sanitized.training.weekly_load_score)
        self.assertIsNone(sanitized.training.last_workout_type)
        # original context is untouched
        self.assertEqual(ctx.training.weekly_load_score, 70)

    def test_restricted_domain_values_never_leak_into_response(self):
        resp = aria_engine.generate_response(
            "should I train today?", full_context(),
            permissions=aria_engine.DataPermissions.from_payload({"training": False}),
        )
        blob = json.dumps(resp).lower()
        self.assertNotIn("strength", blob)      # last_workout_type
        self.assertNotIn("weekly load", blob)   # load score phrasing
        self.assertNotIn("since strength", blob)
        self.assertEqual(resp["restricted_domains"], ["training"])

    def test_confidence_reason_distinguishes_restricted_from_missing(self):
        resp = aria_engine.generate_response(
            "should I train today?", full_context(),
            permissions=aria_engine.DataPermissions.from_payload({"training": False}),
        )
        self.assertIn("training is off (permission)", resp["confidence_reason"])

    def test_restricted_domains_reported_in_envelope(self):
        resp = aria_engine.generate_response(
            "how am I today?", full_context(),
            permissions=aria_engine.DataPermissions.from_payload({"body": False, "nutrition": False}),
        )
        self.assertEqual(set(resp["restricted_domains"]), {"body", "nutrition"})

    def test_asking_about_a_restricted_domain_is_declined_clearly(self):
        ctx = full_context(body=aria_engine.BodyContext(weight_trend_kg=-1.2))
        resp = aria_engine.generate_response(
            "how's my weight trend?", ctx,
            permissions=aria_engine.DataPermissions.from_payload({"body": False}),
        )
        self.assertEqual(resp["response_type"], "clarification")
        self.assertIn("off", resp["prose_summary"].lower())
        self.assertNotIn("1.2", json.dumps(resp))

    def test_no_permissions_means_nothing_restricted(self):
        resp = aria_engine.generate_response("how did I sleep?", full_context())
        self.assertEqual(resp["restricted_domains"], [])


class AllDomainParsingTests(unittest.TestCase):
    def test_rich_payload_parses_every_domain(self):
        ctx = aria_engine.ARIAContext.from_payload({"context": {
            "body": {"weightKg": 80, "weightTrendKg": -1.4, "vo2Max": 48},
            "nutrition": {"proteinG3DayAvg": 150, "calorieTarget": 2200},
            "profile": {"primaryGoal": "lose-fat", "experienceLevel": "intermediate",
                        "coachingStyle": "data-driven", "constraints": ["left knee"]},
            "progress": {"workoutsCompleted30d": 18, "newPersonalRecords": 2, "trainingLoadTrend": "rising"},
            "lifestyle": {"recentPatterns": ["late_caffeine"], "tags": ["founder"]},
        }})
        self.assertEqual(ctx.body.weight_trend_kg, -1.4)
        self.assertEqual(ctx.nutrition.protein_g_3day_avg, 150)
        self.assertEqual(ctx.profile.primary_goal, "lose-fat")
        self.assertEqual(ctx.profile.constraints, ["left knee"])
        self.assertEqual(ctx.progress.workouts_completed_30d, 18)
        self.assertEqual(ctx.lifestyle.recent_patterns, ["late_caffeine"])
        self.assertIn("body.body_fat_pct", ctx.missing_fields)


class NewDomainReasoningTests(unittest.TestCase):
    def test_weight_question_answers_with_body_not_highest_priority_signal(self):
        # Low deep sleep is higher priority, but the question is about weight.
        ctx = full_context(
            profile=aria_engine.ProfileContext(primary_goal="lose-fat"),
            body=aria_engine.BodyContext(weight_trend_kg=-1.5, vo2_max=46),
        )
        resp = aria_engine.generate_response("how's my weight trend?", ctx)
        self.assertEqual(resp["response_type"], "insight")
        self.assertEqual(resp["card"]["metric"], "Body")
        self.assertIn("1.5", resp["card"]["current_value"])
        self.assertIn("fat-loss", resp["card"]["interpretation"].lower())

    def test_domain_question_with_generic_word_stays_an_insight(self):
        # "weight trend" must answer about body, not get hijacked into a progress
        # summary just because it contains the word "trend".
        ctx = full_context(
            body=aria_engine.BodyContext(weight_trend_kg=-1.3),
            progress=aria_engine.ProgressContext(workouts_completed_30d=18, training_load_trend="rising"),
        )
        resp = aria_engine.generate_response("how's my weight trend?", ctx)
        self.assertEqual(resp["response_type"], "insight")
        self.assertEqual(resp["card"]["metric"], "Body")

    def test_progress_question_produces_a_summary(self):
        ctx = full_context(progress=aria_engine.ProgressContext(
            workouts_completed_30d=18, new_personal_records=2, training_load_trend="rising"))
        resp = aria_engine.generate_response("how's my progress this month?", ctx)
        self.assertEqual(resp["response_type"], "summary")
        self.assertEqual(resp["model"], aria_engine.MODEL_PRIMARY)
        self.assertIn("18", resp["message"])
        self.assertIn("period_days", resp["card"])

    def test_nutrition_low_protein_flags_a_shortfall(self):
        signal = aria_engine._interpret_nutrition(aria_engine.ARIAContext(
            body=aria_engine.BodyContext(weight_kg=80),
            nutrition=aria_engine.NutritionContext(protein_g_3day_avg=90),
        ))
        self.assertIsNotNone(signal)
        self.assertEqual(signal.direction, "negative")
        self.assertIn("under", signal.interpretation)

    def test_recommendation_is_shaped_by_profile(self):
        ctx = full_context(profile=aria_engine.ProfileContext(
            primary_goal="lose-fat", experience_level="beginner", constraints=["left knee"]))
        resp = aria_engine.generate_response("should I train today?", ctx)
        self.assertEqual(resp["response_type"], "recommendation")
        self.assertIn("deficit", resp["card"]["expected_effect"])
        self.assertIn("knee", resp["message"].lower())
        self.assertIn("consistency", resp["message"].lower())


class LiveBedrockTests(unittest.TestCase):
    """The opt-in Bedrock path: overlay real reasoning, always degrade safely."""

    def _good_envelope(self) -> str:
        return json.dumps({
            "schema_version": aria_engine.SCHEMA_VERSION,
            "response_type": "recommendation",
            "confidence": 0.71,
            "confidence_reason": "full sleep + HRV-trend data, signals coherent",
            "prose_summary": "HRV is 12% under baseline at recovery 58 — keep today easy.",
            "recommendation": "Zone 2 only; reassess tomorrow.",
            "card": {"action": "Zone 2 only", "model_note": "from the live model"},
            "restricted_domains": [],
        })

    def test_live_overlays_model_reasoning_onto_the_envelope(self):
        captured = {}

        def fake_converse(model_id, system_prompt, user_prompt):
            captured.update(model_id=model_id, system=system_prompt, user=user_prompt)
            return "```json\n" + self._good_envelope() + "\n```"

        resp = aria_engine.generate_response_live(
            "should I train today?", full_context(), converse=fake_converse)

        self.assertEqual(resp["reasoning_source"], "bedrock")
        self.assertTrue(CANONICAL_KEYS.issubset(resp.keys()))
        self.assertIn("58", resp["prose_summary"])
        self.assertEqual(resp["message"], resp["prose_summary"])
        self.assertEqual(resp["confidence"], 0.71)
        self.assertEqual(resp["confidence_reason"], "full sleep + HRV-trend data, signals coherent")
        # recommendation routes to the primary model; reported as the concrete Bedrock id.
        self.assertEqual(resp["model"], "anthropic.claude-opus-4-8")
        # the model received the canonical ARIA system prompt + ground-truth block.
        self.assertEqual(captured["system"], aria_engine.ARIA_SYSTEM_PROMPT)
        self.assertIn("USER MODEL", captured["user"])
        self.assertIn("should I train today?", captured["user"])
        # the model card is merged over the deterministic card, not dropped.
        self.assertEqual(resp["card"]["model_note"], "from the live model")

    def test_live_falls_back_to_deterministic_on_error(self):
        def boom(*_args):
            raise RuntimeError("bedrock unavailable")

        resp = aria_engine.generate_response_live(
            "should I train today?", full_context(), converse=boom)
        deterministic = aria_engine.generate_response("should I train today?", full_context())

        self.assertEqual(resp["reasoning_source"], "deterministic")
        self.assertIn("bedrock unavailable", resp["reasoning_error"])
        self.assertEqual(resp["prose_summary"], deterministic["prose_summary"])
        self.assertEqual(resp["card"], deterministic["card"])
        self.assertEqual(resp["confidence"], deterministic["confidence"])

    def test_live_falls_back_on_unparseable_response(self):
        resp = aria_engine.generate_response_live(
            "should I train today?", full_context(), converse=lambda *a: "not json at all")
        self.assertEqual(resp["reasoning_source"], "deterministic")

    def test_live_falls_back_when_prose_is_missing(self):
        payload = json.dumps({"response_type": "insight", "confidence": 0.5})
        resp = aria_engine.generate_response_live(
            "how did I sleep?", full_context(), converse=lambda *a: payload)
        self.assertEqual(resp["reasoning_source"], "deterministic")

    def test_live_keeps_base_confidence_when_model_value_is_invalid(self):
        base = aria_engine.generate_response("how did I sleep?", full_context())
        payload = json.dumps({"prose_summary": "Sleep looks solid.", "confidence": "high"})
        resp = aria_engine.generate_response_live(
            "how did I sleep?", full_context(), converse=lambda *a: payload)
        self.assertEqual(resp["confidence"], base["confidence"])

    def test_live_clamps_out_of_range_confidence(self):
        payload = json.dumps({"prose_summary": "Sleep looks solid.", "confidence": 1.9})
        resp = aria_engine.generate_response_live(
            "how did I sleep?", full_context(), converse=lambda *a: payload)
        self.assertEqual(resp["confidence"], 1.0)

    def test_live_voice_mode_suppresses_card_and_routes_to_fast_model(self):
        payload = json.dumps({"prose_summary": "Keep it easy today.", "card": {"x": 1}})
        resp = aria_engine.generate_response_live(
            "should I train?", full_context(), voice_mode=True, converse=lambda *a: payload)
        self.assertIsNone(resp["card"])
        self.assertEqual(resp["message"], resp["prose_summary"])
        self.assertEqual(resp["model"], "anthropic.claude-sonnet-4-6")

    def test_live_respects_permissions_in_the_prompt_and_envelope(self):
        captured = {}

        def fake_converse(model_id, system_prompt, user_prompt):
            captured["user"] = user_prompt
            return json.dumps({"prose_summary": "Holding off on training reads.",
                               "response_type": "clarification"})

        resp = aria_engine.generate_response_live(
            "should I train today?", full_context(),
            permissions=aria_engine.DataPermissions.from_payload({"training": False}),
            converse=fake_converse)

        self.assertEqual(resp["restricted_domains"], ["training"])
        # the restricted domain is declared and its values are redacted from the prompt.
        self.assertIn("restricted_domains: training", captured["user"])
        self.assertIn("training.weekly_load_score: null", captured["user"])

    def test_bedrock_enabled_reads_env(self):
        original = os.environ.get("ARIA_BEDROCK_ENABLED")
        try:
            os.environ["ARIA_BEDROCK_ENABLED"] = "true"
            self.assertTrue(aria_engine.bedrock_enabled())
            os.environ["ARIA_BEDROCK_ENABLED"] = "0"
            self.assertFalse(aria_engine.bedrock_enabled())
            os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            self.assertFalse(aria_engine.bedrock_enabled())
        finally:
            if original is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = original


if __name__ == "__main__":
    unittest.main()
