import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner.aria_engine import ARIAResponse  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_evaluator import evaluate  # noqa: E402
from backend.ai.simrunner.aria_simrunner.prompts import build_user_prompt  # noqa: E402
from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import (  # noqa: E402
    DailyRecord, IsometricHold, _INTENSITY_LOAD, _ISOMETRIC_EXERCISES,
    _ISOMETRIC_EXERCISE_COUNT, _ISOMETRIC_HOLD_SECONDS, _ISOMETRIC_LOAD_FACTOR,
    _ISOMETRIC_SETS, generate_stream,
)
from backend.ai.simrunner.backend_simulator.data_generator import (  # noqa: E402
    ARIAContext, build_context,
)

ISOMETRIC_MODEL_IDS = {
    "mistral.mistral-large-2-isometric",
    "meta.llama4-maverick-isometric-confound",
}


def _daily_record(**overrides) -> DailyRecord:
    base = dict(
        date="2026-01-15", total_sleep_hours=7.5, deep_sleep_minutes=80,
        rem_sleep_minutes=95, sleep_score=80, hrv=55, resting_hr=55,
        readiness_score=70, steps=9000, active_calories=500,
        workout_logged=False, workout_type=None, workout_duration_minutes=None,
        workout_intensity=None, training_load=0.0, acwr=1.0, notes=None,
    )
    base.update(overrides)
    return DailyRecord(**base)


def _context(**overrides) -> ARIAContext:
    today = overrides.pop("today", _daily_record())
    fields = dict(
        user_name="Test", chronotype="bear", experience_level="intermediate",
        coaching_style="balanced", occupation="tester", life_season="maintenance",
        today=today, hrv_7d_avg=55.0, hrv_7d_trend="stable", sleep_debt_7d_hours=0.0,
        readiness_7d_avg=70.0, readiness_trend="stable", acwr=1.0,
        training_streak=0, days_since_last_workout=1, target_sleep_hours=8.0,
        target_wake_hour=7.0, is_overtrained=False, is_sleep_deprived=False,
        has_notable_event=False, notable_event_note=None, history=[today],
    )
    fields.update(overrides)
    return ARIAContext(**fields)


class IsometricRNGGatingTests(unittest.TestCase):
    """New RNG rolls for isometric_emphasis must never fire for a profile that
    doesn't opt in -- the same discipline data_completeness/source_conflict
    already established. Neither of the 21 pre-existing archetypes carries the
    new key; that's the real, load-bearing guarantee their committed baselines
    depend on (confirmed end-to-end separately via --all --gate, not by a unit
    test)."""

    def test_no_other_archetype_profile_carries_isometric_emphasis(self):
        for model in reg.BEDROCK_MODEL_REGISTRY:
            if model["model_id"] in ISOMETRIC_MODEL_IDS:
                continue
            self.assertNotIn("isometric_emphasis", model["behavioral_profile"], model["model_id"])

    def test_a_profile_that_omits_the_key_never_rolls_isometric(self):
        profile = reg.get_model("anthropic.claude-sonnet-4-6")["behavioral_profile"]
        for seed in range(1, 11):
            stream = generate_stream(profile, seed=seed)
            self.assertTrue(all(r.workout_type != "isometric" for r in stream))
            self.assertTrue(all(r.workout_peak_hr is None for r in stream))
            self.assertTrue(all(r.isometric_holds is None for r in stream))

    def test_isometric_specialist_is_internally_deterministic(self):
        profile = reg.get_model("mistral.mistral-large-2-isometric")["behavioral_profile"]
        a = generate_stream(profile, seed=42)
        b = generate_stream(profile, seed=42)
        self.assertEqual(a, b)

    def test_isometric_specialist_actually_produces_isometric_days(self):
        profile = reg.get_model("mistral.mistral-large-2-isometric")["behavioral_profile"]
        stream = generate_stream(profile, seed=42)
        self.assertTrue(any(r.workout_type == "isometric" for r in stream))

    def test_confounder_reliably_produces_isometric_days(self):
        profile = reg.get_model("meta.llama4-maverick-isometric-confound")["behavioral_profile"]
        seeds_with_isometric = sum(
            1 for seed in range(1, 11)
            if any(r.workout_type == "isometric" for r in generate_stream(profile, seed=seed))
        )
        self.assertGreater(seeds_with_isometric, 5, "expected isometric days in most seeds")

    def test_confounder_can_produce_isometric_days_alongside_genuine_overtraining(self):
        # The whole point of this archetype: benign isometric spikes and a
        # real ACWR-driven risk window can land in the same 30-day stream.
        # Checked as an existence claim across several seeds (not "most
        # seeds") -- ACWR's acute:chronic ratio is naturally noisy while the
        # 28-day chronic window is still filling early in a stream, and this
        # feature's gating discipline shouldn't try to force that into a
        # fixed distribution just to make a test pass.
        profile = reg.get_model("meta.llama4-maverick-isometric-confound")["behavioral_profile"]
        found_both = False
        for seed in range(1, 21):
            stream = generate_stream(profile, seed=seed)
            has_isometric = any(r.workout_type == "isometric" for r in stream)
            has_overtraining = any(r.acwr > 1.4 for r in stream)
            if has_isometric and has_overtraining:
                found_both = True
                break
        self.assertTrue(found_both, "expected at least one seed with both an isometric day and a genuine ACWR spike")


class IsometricHoldGenerationTests(unittest.TestCase):
    def test_holds_land_in_declared_ranges(self):
        profile = reg.get_model("mistral.mistral-large-2-isometric")["behavioral_profile"]
        stream = generate_stream(profile, seed=42)
        isometric_days = [r for r in stream if r.workout_type == "isometric"]
        self.assertTrue(isometric_days)
        for record in isometric_days:
            self.assertIsNotNone(record.isometric_holds)
            self.assertTrue(_ISOMETRIC_EXERCISE_COUNT[0] <= len(record.isometric_holds) <= _ISOMETRIC_EXERCISE_COUNT[1])
            for hold in record.isometric_holds:
                self.assertIsInstance(hold, IsometricHold)
                self.assertIn(hold.exercise, _ISOMETRIC_EXERCISES)
                self.assertTrue(_ISOMETRIC_HOLD_SECONDS[0] <= hold.hold_seconds <= _ISOMETRIC_HOLD_SECONDS[1])
                self.assertTrue(_ISOMETRIC_SETS[0] <= hold.sets <= _ISOMETRIC_SETS[1])

    def test_dynamic_and_rest_days_carry_no_holds(self):
        profile = reg.get_model("mistral.mistral-large-2-isometric")["behavioral_profile"]
        stream = generate_stream(profile, seed=42)
        for record in stream:
            if record.workout_type != "isometric":
                self.assertIsNone(record.isometric_holds)


class IsometricLoadAndHRTests(unittest.TestCase):
    def test_peak_hr_is_none_off_isometric_days(self):
        profile = reg.get_model("mistral.mistral-large-2-isometric")["behavioral_profile"]
        stream = generate_stream(profile, seed=42)
        for record in stream:
            if record.workout_type != "isometric":
                self.assertIsNone(record.workout_peak_hr)

    def test_peak_hr_is_a_spike_above_resting_on_isometric_days(self):
        profile = reg.get_model("mistral.mistral-large-2-isometric")["behavioral_profile"]
        stream = generate_stream(profile, seed=42)
        isometric_days = [r for r in stream if r.workout_type == "isometric"]
        self.assertTrue(isometric_days)
        for record in isometric_days:
            self.assertIsNotNone(record.workout_peak_hr)
            self.assertGreater(record.workout_peak_hr, record.resting_hr)

    def test_isometric_load_formula_discounts_vs_an_equivalent_dynamic_session(self):
        # Same duration, same intensity tier -- isometric's load formula
        # carries the extra _ISOMETRIC_LOAD_FACTOR discount, which is what
        # lets a benign isometric spike avoid inflating ACWR the way a real
        # dynamic session of the same length would.
        duration, intensity, season_factor = 30, "moderate", 1.0
        dynamic_load = duration / 60.0 * _INTENSITY_LOAD[intensity] * season_factor
        isometric_load = dynamic_load * _ISOMETRIC_LOAD_FACTOR
        self.assertLess(isometric_load, dynamic_load)


class ARIAContextLastWorkoutTests(unittest.TestCase):
    def test_none_when_no_workout_has_occurred(self):
        ctx = build_context([_daily_record(workout_logged=False)], {}, 0)
        self.assertIsNone(ctx.last_workout_type)
        self.assertIsNone(ctx.last_workout_peak_hr)

    def test_captures_the_most_recent_workout_type_and_peak_hr(self):
        stream = [
            _daily_record(date="2026-01-13", workout_logged=True, workout_type="strength"),
            _daily_record(date="2026-01-14", workout_logged=False),
            _daily_record(date="2026-01-15", workout_logged=True, workout_type="isometric", workout_peak_hr=145),
        ]
        ctx = build_context(stream, {}, 2)
        self.assertEqual(ctx.last_workout_type, "isometric")
        self.assertEqual(ctx.last_workout_peak_hr, 145)

    def test_skips_back_past_rest_days_to_the_last_real_workout(self):
        stream = [
            _daily_record(date="2026-01-13", workout_logged=True, workout_type="isometric", workout_peak_hr=140),
            _daily_record(date="2026-01-14", workout_logged=False),
            _daily_record(date="2026-01-15", workout_logged=False),
        ]
        ctx = build_context(stream, {}, 2)
        self.assertEqual(ctx.last_workout_type, "isometric")
        self.assertEqual(ctx.last_workout_peak_hr, 140)


class PromptIsometricRenderingTests(unittest.TestCase):
    def test_fully_populated_non_isometric_context_is_unaffected(self):
        # Guards the additive-only claim: zero isometric fields set -> zero
        # new lines appended, prompt renders exactly as before this feature.
        prompt = build_user_prompt("What should I train today?", _context())
        self.assertNotIn("isometric", prompt.lower())

    def test_todays_isometric_workout_renders_hold_detail(self):
        today = _daily_record(
            workout_logged=True, workout_type="isometric", workout_peak_hr=148,
            isometric_holds=[IsometricHold(exercise="Plank", hold_seconds=45, sets=3)],
        )
        ctx = _context(today=today)
        prompt = build_user_prompt("What should I train today?", ctx)
        self.assertIn("Plank 45s×3", prompt)
        self.assertIn("148bpm", prompt)

    def test_last_isometric_workout_renders_caveat_when_today_is_rest(self):
        ctx = _context(last_workout_type="isometric", last_workout_peak_hr=150)
        prompt = build_user_prompt("What should I train today?", ctx)
        self.assertIn("last workout was isometric", prompt)
        self.assertIn("150bpm", prompt)
        self.assertIn("not sustained cardio load", prompt)

    def test_todays_detail_takes_priority_over_the_last_workout_caveat(self):
        today = _daily_record(
            workout_logged=True, workout_type="isometric", workout_peak_hr=150,
            isometric_holds=[IsometricHold(exercise="Wall Sit", hold_seconds=40, sets=3)],
        )
        ctx = _context(today=today, last_workout_type="isometric", last_workout_peak_hr=150)
        prompt = build_user_prompt("What should I train today?", ctx)
        self.assertIn("today's isometric work", prompt)
        self.assertNotIn("last workout was isometric", prompt)


class EvaluatorIsometricTests(unittest.TestCase):
    def test_context_utilization_credits_citing_the_peak_hr(self):
        ctx = _context(
            today=_daily_record(readiness_score=63, acwr=1.0),
            last_workout_type="isometric", last_workout_peak_hr=148,
            hrv_7d_avg=55.0, sleep_debt_7d_hours=0.0, readiness_7d_avg=63.0, acwr=1.0,
        )
        resp = ARIAResponse(
            prose_summary="Your last session spiked HR to 148 briefly -- expected from a hold, not overtraining.",
            recommendation="Train normally today.", confidence=0.7, used_context=True,
            model_used="opus", query_type="training_decision", latency_ms=500.0, raw={},
        )
        # tier=1 -> tier_multiplier=1.0, so a "specific hit" (100.0 raw) scores
        # a clean 100.0 with no division to account for.
        result = evaluate(0, "What should I train today?", 1, ctx, resp)
        self.assertEqual(result.scores.context_utilization, 100.0)

    def test_flags_misread_isometric_spike_as_overtraining_with_no_other_cause(self):
        # Last workout isometric, genuinely not overtrained, nothing else
        # wrong -- but the response talks like it IS overtraining anyway.
        ctx = _context(
            today=_daily_record(readiness_score=75, acwr=1.0),
            last_workout_type="isometric", last_workout_peak_hr=150,
            hrv_7d_trend="stable", sleep_debt_7d_hours=1.0, acwr=1.0, is_overtrained=False,
        )
        resp = ARIAResponse(
            prose_summary="Your HR spiked hard last session -- that workload is too much, back off and deload this week.",
            recommendation="Deload this week.", confidence=0.7, used_context=True,
            model_used="opus", query_type="training_decision", latency_ms=500.0, raw={},
        )
        result = evaluate(0, "What should I train today?", 3, ctx, resp)
        self.assertEqual(result.scores.directional_correctness, 0.0)
        self.assertTrue(any("misread a transient isometric" in f for f in result.failures))

    def test_does_not_flag_legitimate_caution_that_happens_to_follow_an_isometric_day(self):
        # Last workout isometric, but real sleep debt is the actual reason for
        # caution -- must not be misdiagnosed as an isometric misread. Without
        # the no_other_reason guard, this would have false-positived.
        ctx = _context(
            today=_daily_record(readiness_score=75, acwr=1.0),
            last_workout_type="isometric", last_workout_peak_hr=150,
            sleep_debt_7d_hours=6.0, is_overtrained=False, hrv_7d_trend="stable",
        )
        resp = ARIAResponse(
            prose_summary=(
                "Sleep debt is high this week -- that's the real reason to rest and "
                "back off training volume tonight, prioritize sleep before anything else."
            ),
            recommendation="Hold intensity back; prioritize sleep tonight.", confidence=0.7, used_context=True,
            model_used="opus", query_type="training_decision", latency_ms=500.0, raw={},
        )
        result = evaluate(0, "What should I train today?", 3, ctx, resp)
        self.assertNotEqual(result.scores.directional_correctness, 0.0)
        self.assertFalse(any("misread a transient isometric" in f for f in result.failures))

    def test_still_flags_genuine_overtraining_even_after_an_isometric_day(self):
        # Last workout isometric AND genuinely overtrained -- isometric
        # framing must never provide cover for missing real risk.
        ctx = _context(
            today=_daily_record(readiness_score=75, acwr=1.6),
            last_workout_type="isometric", last_workout_peak_hr=150,
            is_overtrained=True, acwr=1.6,
        )
        resp = ARIAResponse(
            prose_summary=(
                "You're in a good spot -- that spike was just from your last isometric "
                "session, go ahead and push hard today."
            ),
            recommendation="Train at high intensity today.", confidence=0.7, used_context=True,
            model_used="opus", query_type="training_decision", latency_ms=500.0, raw={},
        )
        result = evaluate(0, "What should I train today?", 3, ctx, resp)
        self.assertEqual(result.scores.directional_correctness, 0.0)
        self.assertTrue(any("failed to surface overtraining risk" in f for f in result.failures))

    def test_recommendations_include_the_isometric_system_prompt_fix(self):
        ctx = _context(
            today=_daily_record(readiness_score=75, acwr=1.0),
            last_workout_type="isometric", last_workout_peak_hr=150,
            sleep_debt_7d_hours=1.0, is_overtrained=False, hrv_7d_trend="stable",
        )
        resp = ARIAResponse(
            prose_summary="That's too much load, back off and deload.",
            recommendation="Deload.", confidence=0.7, used_context=True,
            model_used="opus", query_type="training_decision", latency_ms=500.0, raw={},
        )
        result = evaluate(0, "What should I train today?", 3, ctx, resp)
        self.assertTrue(any("isometric HR signature" in r for r in result.recommendations))

    def test_snapshot_carries_last_workout_fields(self):
        ctx = _context(last_workout_type="isometric", last_workout_peak_hr=150)
        resp = ARIAResponse(
            prose_summary="Fine to train today.", recommendation="Train normally.",
            confidence=0.7, used_context=True, model_used="opus",
            query_type="training_decision", latency_ms=500.0, raw={},
        )
        result = evaluate(0, "What should I train today?", 1, ctx, resp)
        self.assertEqual(result.context_snapshot["last_workout_type"], "isometric")
        self.assertEqual(result.context_snapshot["last_workout_peak_hr"], 150)


class RegistryIsometricArchetypeTests(unittest.TestCase):
    def test_both_new_archetypes_round_trip(self):
        for mid in ISOMETRIC_MODEL_IDS:
            self.assertEqual(reg.get_model(mid)["model_id"], mid)
            self.assertIn(mid, reg.all_model_ids())

    def test_isometric_specialist_is_tier_3_with_isometric_emphasis(self):
        model = reg.get_model("mistral.mistral-large-2-isometric")
        self.assertEqual(model["difficulty_tier"], 3)
        self.assertGreater(model["behavioral_profile"]["isometric_emphasis"], 0.0)

    def test_isometric_confounder_is_tier_4_with_high_overtraining_tendency(self):
        model = reg.get_model("meta.llama4-maverick-isometric-confound")
        self.assertEqual(model["difficulty_tier"], 4)
        self.assertGreater(model["behavioral_profile"]["isometric_emphasis"], 0.0)
        self.assertGreaterEqual(model["behavioral_profile"]["overtraining_tendency"], 0.5)

    def test_registry_still_validates(self):
        reg.validate_registry()  # must not raise

    def test_total_archetypes_is_23(self):
        self.assertEqual(reg.TOTAL_ARCHETYPES, 23)
        self.assertEqual(len(reg.BEDROCK_MODEL_REGISTRY), 23)

    def test_tier_counts_reflect_the_two_new_archetypes(self):
        self.assertEqual(reg._TIER_COUNTS[3], 5)
        self.assertEqual(reg._TIER_COUNTS[4], 5)
        self.assertEqual(len(reg.get_models_by_tier(3)), 5)
        self.assertEqual(len(reg.get_models_by_tier(4)), 5)


if __name__ == "__main__":
    unittest.main()
