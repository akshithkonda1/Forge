import statistics
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_engine import (  # noqa: E402
    ARIAEngine, ARIAResponse, _references_context,
)
from backend.ai.simrunner.aria_simrunner.aria_evaluator import evaluate  # noqa: E402
from backend.ai.simrunner.aria_simrunner.prompts import build_user_prompt  # noqa: E402
from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import (  # noqa: E402
    DailyRecord, _readiness, generate_stream,
)
from backend.ai.simrunner.backend_simulator.data_generator import (  # noqa: E402
    ARIAContext, build_context, confidence_ceiling,
)


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


class CompletenessRNGGatingTests(unittest.TestCase):
    """New RNG rolls (the completeness gate, the source-conflict perturbation)
    must never fire for a profile that doesn't opt in — not "roll and
    discard," which would still shift every later value even when nothing
    else visibly changed. None of the 20 pre-existing archetypes' profile
    dicts carry either new key; that's the real, load-bearing guarantee their
    committed baselines depend on (confirmed end-to-end separately via
    `--all --gate`, not by a unit test)."""

    def test_no_existing_archetype_profile_carries_the_new_keys(self):
        for model in reg.BEDROCK_MODEL_REGISTRY:
            if model["model_id"] == "cohere.command-r-sparse":
                continue  # the one persona that deliberately opts in
            profile = model["behavioral_profile"]
            self.assertNotIn("data_completeness", profile, model["model_id"])
            self.assertNotIn("source_conflict", profile, model["model_id"])

    def test_a_profile_that_omits_the_key_has_zero_missing_fields(self):
        profile = reg.get_model("anthropic.claude-sonnet-4-6")["behavioral_profile"]
        for r in generate_stream(profile, seed=7):
            self.assertIsNotNone(r.hrv)
            self.assertIsNotNone(r.total_sleep_hours)
            self.assertIsNotNone(r.resting_hr)
            self.assertIsNotNone(r.deep_sleep_minutes)
            self.assertIsNotNone(r.rem_sleep_minutes)
            self.assertIsNotNone(r.sleep_score)

    def test_completeness_explicitly_at_1_0_also_has_zero_missing_fields(self):
        # confirms the threshold check itself (completeness < 1.0), not just
        # key presence/absence, is what gates the roll. Note this profile's
        # own RNG seed still differs from the key-omitted version above
        # (_profile_seed hashes every key present in the dict) -- that's
        # expected and not the invariant under test here.
        profile = dict(
            reg.get_model("anthropic.claude-sonnet-4-6")["behavioral_profile"],
            data_completeness=1.0,
        )
        stream = generate_stream(profile, seed=7)
        self.assertTrue(all(r.hrv is not None for r in stream))
        self.assertTrue(all(r.total_sleep_hours is not None for r in stream))

    def test_sparse_profile_is_internally_deterministic(self):
        profile = reg.get_model("cohere.command-r-sparse")["behavioral_profile"]
        a = generate_stream(profile, seed=42)
        b = generate_stream(profile, seed=42)
        self.assertEqual(a, b)

    def test_sparse_profile_still_produces_30_records_with_real_gaps(self):
        profile = reg.get_model("cohere.command-r-sparse")["behavioral_profile"]
        stream = generate_stream(profile, seed=42)
        self.assertEqual(len(stream), 30)
        self.assertTrue(any(r.hrv is None for r in stream))
        self.assertTrue(any(r.hrv is not None for r in stream))  # not ALL missing either


class SourceConflictTests(unittest.TestCase):
    def test_source_conflict_measurably_increases_resting_hr_volatility(self):
        # A single seed's max jump isn't a clean signal on its own -- ordinary
        # HRV-driven noise already produces occasional 6-10bpm swings even
        # without the trait. Aggregated across many seeds, the *average*
        # day-to-day resting_hr volatility is a robust, deterministic
        # (fixed seed range) way to confirm the perturbation branch actually
        # fires and does something, without duplicating the internal formula.
        base_profile = reg.get_model("anthropic.claude-opus-4-8")["behavioral_profile"]
        conflict_profile = dict(base_profile, source_conflict=True)

        def avg_day_to_day_std(profile, n=40):
            stds = []
            for seed in range(1, n + 1):
                stream = generate_stream(profile, seed=seed)
                diffs = [stream[i].resting_hr - stream[i - 1].resting_hr for i in range(1, len(stream))]
                stds.append(statistics.pstdev(diffs))
            return statistics.mean(stds)

        control = avg_day_to_day_std(base_profile)
        conflict = avg_day_to_day_std(conflict_profile)
        self.assertGreater(conflict, control * 1.3, f"control={control}, conflict={conflict}")


class DegradedReadinessTests(unittest.TestCase):
    def test_matches_original_formula_when_fully_populated(self):
        # hrv_ratio=1.0, acwr_penalty=100 -> 80*0.4 + 100*0.35 + 100*0.25 = 92
        self.assertEqual(_readiness(sleep_score=80, hrv=55, hrv_baseline=55.0, acwr=1.0), 92)

    def test_never_crashes_and_uses_acwr_alone_when_both_missing(self):
        result = _readiness(sleep_score=None, hrv=None, hrv_baseline=55.0, acwr=1.5)
        self.assertIsInstance(result, int)
        self.assertTrue(0 <= result <= 100)
        # only component is acwr_penalty = 100 - (1.5-1.0)*100 = 50
        self.assertEqual(result, 50)

    def test_degrades_when_hrv_missing_sleep_present(self):
        # components (100, .25) + (80, .40); weight .65 -> (25+32)/.65 ≈ 87.69 -> 88
        result = _readiness(sleep_score=80, hrv=None, hrv_baseline=55.0, acwr=1.0)
        self.assertEqual(result, 88)

    def test_degrades_when_sleep_missing_hrv_present(self):
        # components (100, .25) + (100, .35); weight .6 -> (25+35)/.6 = 100
        result = _readiness(sleep_score=None, hrv=55, hrv_baseline=55.0, acwr=1.0)
        self.assertEqual(result, 100)


class ARIAContextMissingDataTests(unittest.TestCase):
    def test_flags_reflect_a_fully_populated_today(self):
        ctx = build_context([_daily_record()], {}, 0)
        self.assertTrue(ctx.has_sleep)
        self.assertTrue(ctx.has_sleep_stages)
        self.assertTrue(ctx.has_hrv)
        self.assertTrue(ctx.has_resting_hr)
        self.assertFalse(ctx.is_data_sparse)
        self.assertEqual(ctx.missing_fields, [])

    def test_flags_reflect_missing_hrv_alone(self):
        ctx = build_context([_daily_record(hrv=None)], {}, 0)
        self.assertFalse(ctx.has_hrv)
        self.assertTrue(ctx.has_sleep)
        self.assertFalse(ctx.is_data_sparse)  # sleep and resting_hr still present
        self.assertEqual(ctx.missing_fields, ["today.hrv"])

    def test_is_data_sparse_requires_all_three_signal_clusters_missing(self):
        # sleep and hrv gone but resting_hr still present -> not sparse
        mostly_gone = build_context([_daily_record(
            total_sleep_hours=None, deep_sleep_minutes=None, rem_sleep_minutes=None,
            sleep_score=None, hrv=None,
        )], {}, 0)
        self.assertFalse(mostly_gone.is_data_sparse)

        # now resting_hr is gone too -> genuinely sparse
        fully_gone = build_context([_daily_record(
            total_sleep_hours=None, deep_sleep_minutes=None, rem_sleep_minutes=None,
            sleep_score=None, hrv=None, resting_hr=None,
        )], {}, 0)
        self.assertTrue(fully_gone.is_data_sparse)

    def test_missing_fields_lists_exact_none_leaves(self):
        ctx = build_context([_daily_record(hrv=None, resting_hr=None)], {}, 0)
        self.assertEqual(set(ctx.missing_fields), {"today.hrv", "today.resting_hr"})

    def test_has_sleep_stages_false_when_duration_present_but_stages_missing(self):
        ctx = build_context([_daily_record(deep_sleep_minutes=None, rem_sleep_minutes=None)], {}, 0)
        self.assertTrue(ctx.has_sleep)
        self.assertFalse(ctx.has_sleep_stages)

    def test_hrv_days_available_7d_counts_the_window(self):
        stream = [
            _daily_record(date=f"2026-01-{10 + i:02d}", hrv=(None if i % 2 == 0 else 55))
            for i in range(7)
        ]
        ctx = build_context(stream, {}, 6)
        self.assertEqual(ctx.hrv_days_available_7d, 3)  # i = 1, 3, 5

    def test_sleep_debt_skips_missing_nights_instead_of_crashing(self):
        stream = [
            _daily_record(date=f"2026-01-{10 + i:02d}", total_sleep_hours=(None if i == 3 else 6.0))
            for i in range(7)
        ]
        ctx = build_context(stream, {}, 6)  # must not raise
        # target_sleep defaults to 8.0 (bear); 6 nights of 6.0h contribute
        # 2.0h debt each, the missing night contributes zero either way.
        self.assertEqual(ctx.sleep_debt_7d_hours, 12.0)


class ConfidenceCeilingTests(unittest.TestCase):
    def test_full_data_is_unrestricted(self):
        self.assertEqual(confidence_ceiling(_context()), (1.0, []))

    def test_no_sleep_caps_hard(self):
        ceiling, reasons = confidence_ceiling(_context(has_sleep=False))
        self.assertEqual(ceiling, 0.55)
        self.assertIn("no sleep data", reasons)

    def test_stages_only_missing_caps_moderately(self):
        ceiling, reasons = confidence_ceiling(_context(has_sleep_stages=False))
        self.assertEqual(ceiling, 0.85)
        self.assertIn("sleep stages unavailable (duration only)", reasons)

    def test_no_hrv_caps_to_065(self):
        ceiling, reasons = confidence_ceiling(_context(has_hrv=False))
        self.assertEqual(ceiling, 0.65)
        self.assertTrue(any("no HRV" in r for r in reasons))

    def test_thin_hrv_week_caps_to_05(self):
        ceiling, _reasons = confidence_ceiling(_context(hrv_days_available_7d=2))
        self.assertEqual(ceiling, 0.5)

    def test_combined_gaps_take_the_lowest_ceiling(self):
        ceiling, reasons = confidence_ceiling(_context(has_sleep=False, has_hrv=False))
        self.assertEqual(ceiling, 0.55)  # min(0.55, 0.65)
        self.assertEqual(len(reasons), 2)


class StubEngineSparseDetectionTests(unittest.TestCase):
    def test_context_sparse_triggers_ask_dont_guess_without_the_magic_phrase(self):
        sparse_today = _daily_record(
            total_sleep_hours=None, deep_sleep_minutes=None, rem_sleep_minutes=None,
            sleep_score=None, hrv=None, resting_hr=None,
        )
        ctx = _context(today=sparse_today, is_data_sparse=True)
        resp = ARIAEngine(use_real_api=False).respond("What should I train today?", ctx, seed=1)
        self.assertIn(resp.raw.get("scenario"), ("sparse_clarify", "sparse_overconfident"))

    def test_magic_phrase_still_triggers_on_a_rich_context(self):
        resp = ARIAEngine(use_real_api=False).respond(
            "What would you recommend for someone like me?", _context(), seed=1,
        )
        self.assertIn(resp.raw.get("scenario"), ("sparse_clarify", "sparse_overconfident"))

    def test_context_phrase_omits_hrv_gracefully_when_missing(self):
        ctx = _context(today=_daily_record(hrv=None))
        phrase = ARIAEngine(use_real_api=False)._context_phrase(ctx)
        self.assertIn("HRV not available", phrase)
        self.assertNotIn("None", phrase)

    def test_references_context_ignores_a_missing_hrv_rather_than_matching_the_word_none(self):
        ctx = _context(today=_daily_record(hrv=None))
        # Before the guard, a None hrv would add the literal string "None" to
        # the candidate-numbers set -- this prose contains that word as
        # ordinary language, not a real citation of the day's numbers.
        self.assertFalse(_references_context("None of this changes the plan for today.", ctx))


class EvaluatorMissingDataTests(unittest.TestCase):
    def test_epistemic_honesty_fires_on_context_sparse_without_the_magic_phrase(self):
        ctx = _context(is_data_sparse=True)
        resp = ARIAResponse(
            prose_summary="What's your training history been like, and how did the last few nights feel?",
            recommendation=None, confidence=0.3, used_context=False,
            model_used="opus", query_type="ambiguous", latency_ms=500.0, raw={},
        )
        result = evaluate(0, "Fit training into my day today.", 5, ctx, resp)
        self.assertEqual(result.scores.epistemic_honesty, 100.0)

    def test_epistemic_honesty_still_fails_confident_advice_on_a_sparse_context(self):
        ctx = _context(is_data_sparse=True)
        resp = ARIAResponse(
            prose_summary="Train four times a week and you'll be fine.",
            recommendation="Train 4x/week.", confidence=0.9, used_context=False,
            model_used="opus", query_type="training_decision", latency_ms=500.0, raw={},
        )
        result = evaluate(0, "Fit training into my day today.", 5, ctx, resp)
        self.assertEqual(result.scores.epistemic_honesty, 0.0)

    def test_context_utilization_does_not_miscount_the_word_none_as_an_hrv_citation(self):
        ctx = _context(
            today=_daily_record(readiness_score=63, hrv=None, acwr=1.0),
            hrv_7d_avg=61.2, sleep_debt_7d_hours=2.3, readiness_7d_avg=58.0, acwr=1.0,
        )
        # Contains none of ctx's real numbers, and the literal word "None" as
        # ordinary prose. Pre-fix, the missing hrv would have contributed the
        # string "None" to the candidate set and this would have wrongly
        # scored 100 (a "specific" hit) instead of falling through to the
        # generic-language tier.
        resp = ARIAResponse(
            prose_summary="None of this is urgent. Take it easy and see how you feel.",
            recommendation=None, confidence=0.5, used_context=False,
            model_used="opus", query_type="ambiguous", latency_ms=500.0, raw={},
        )
        result = evaluate(0, "How am I doing?", 1, ctx, resp)
        self.assertEqual(result.scores.context_utilization, 50.0)


class PromptGuardTests(unittest.TestCase):
    def test_renders_not_available_for_every_missing_field(self):
        ctx = _context(today=_daily_record(
            hrv=None, resting_hr=None, total_sleep_hours=None,
            deep_sleep_minutes=None, rem_sleep_minutes=None,
        ))
        prompt = build_user_prompt("What should I train today?", ctx)
        self.assertIn("HRV not available", prompt)
        self.assertIn("RHR not available", prompt)
        self.assertIn("sleep not available", prompt)
        self.assertNotIn("None", prompt)

    def test_duration_present_but_stages_missing_renders_partial(self):
        ctx = _context(today=_daily_record(deep_sleep_minutes=None, rem_sleep_minutes=None))
        prompt = build_user_prompt("What should I train today?", ctx)
        self.assertIn("deep n/a", prompt)
        self.assertNotIn("None", prompt)

    def test_fully_populated_context_is_unaffected(self):
        prompt = build_user_prompt("What should I train today?", _context())
        self.assertNotIn("not available", prompt)
        self.assertNotIn("None", prompt)


class DummyOrchestratorGuardTests(unittest.TestCase):
    def test_supporting_briefs_handles_missing_sleep_and_hrv(self):
        plan = dummy.plan_workers("I slept badly and feel drained, what should I train?")
        ctx = _context(today=_daily_record(total_sleep_hours=None, hrv=None))
        briefs = dummy.supporting_briefs(plan, ctx)  # must not raise
        recovery_lines = [b for b in briefs if b.startswith("Recovery")]
        self.assertTrue(recovery_lines, "expected a non-primary recovery worker for this message")
        self.assertIn("sleep unavailable", recovery_lines[0])
        self.assertIn("HRV unavailable", recovery_lines[0])


if __name__ == "__main__":
    unittest.main()
