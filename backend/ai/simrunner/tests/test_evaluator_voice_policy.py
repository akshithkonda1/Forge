"""Voice-policy credit: no raw numbers required; guide leaks fail.

Iris (ARIA quality owner): context-use full credit for a plain-language
state read; actionability/directional full credit for one sized
second-person step on recommendation or card.action/why.
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner.aria_engine import ARIAResponse  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_evaluator import (  # noqa: E402
    evaluate,
    _has_credit_step,
)
from backend.ai.simrunner.aria_simrunner.dummy_orchestrator import (  # noqa: E402
    _SPEAK_FALLBACK,
)
from backend.ai.simrunner.aria_simrunner.stability_analyzer import analyze  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import DailyRecord  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import ARIAContext  # noqa: E402

_HOLD_DIR = (
    Path(__file__).resolve().parents[3] / "tests" / "fixtures" / "test_ready_hold_7f69323"
)
_HOLD_COMPOSITES = {
    "anthropic.claude-sonnet-4-6": 70.1,
    "amazon.nova-lite-v1": 70.8,
    "meta.llama4-scout-17b": 73.5,
    "cohere.command-r-plus": 73.0,
}
_HOLD_FILES = {
    "anthropic.claude-sonnet-4-6": "anthropic_claude_sonnet_4_6.json",
    "amazon.nova-lite-v1": "amazon_nova_lite_v1.json",
    "meta.llama4-scout-17b": "meta_llama4_scout_17b.json",
    "cohere.command-r-plus": "cohere_command_r_plus.json",
}


def make_record(readiness=70, hrv=55, acwr=1.0, sleep_hours=7.5, training_load=0.0):
    return DailyRecord(
        date="2026-01-15", total_sleep_hours=sleep_hours, deep_sleep_minutes=80, rem_sleep_minutes=95,
        sleep_score=80, hrv=hrv, resting_hr=55, readiness_score=readiness, steps=9000,
        active_calories=500, workout_logged=False, workout_type=None,
        workout_duration_minutes=None, workout_intensity=None, training_load=training_load,
        acwr=acwr, notes=None,
    )


def make_context(
    readiness=70, hrv=55, acwr=1.0, sleep_debt=0.0, hrv_trend="stable",
    *, sleep_hours=7.5, readiness_trend="stable", training_load=0.0,
):
    today = make_record(readiness, hrv, acwr, sleep_hours=sleep_hours, training_load=training_load)
    return ARIAContext(
        user_name="Test", chronotype="bear", experience_level="intermediate",
        coaching_style="balanced", occupation="tester", life_season="maintenance",
        today=today, hrv_7d_avg=float(hrv), hrv_7d_trend=hrv_trend, sleep_debt_7d_hours=sleep_debt,
        readiness_7d_avg=float(readiness), readiness_trend=readiness_trend, acwr=acwr,
        training_streak=0, days_since_last_workout=1, target_sleep_hours=8.0, target_wake_hour=7.0,
        is_overtrained=acwr > 1.4, is_sleep_deprived=sleep_debt > 4.0,
        has_notable_event=False, notable_event_note=None, history=[today],
    )


def make_response(prose, recommendation=None, raw=None, confidence=0.7):
    return ARIAResponse(
        prose_summary=prose, recommendation=recommendation, confidence=confidence,
        used_context=True, model_used="lambda-deterministic", query_type="training_decision",
        latency_ms=40.0, raw=raw or {},
    )


def _ctx_from_snap(snap: dict) -> ARIAContext:
    today = DailyRecord(
        date=str(snap.get("date") or "2026-01-15"),
        total_sleep_hours=7.5, deep_sleep_minutes=80, rem_sleep_minutes=95,
        sleep_score=80, hrv=snap.get("hrv"), resting_hr=55,
        readiness_score=int(snap.get("readiness") or 70),
        steps=9000, active_calories=500,
        workout_logged=False, workout_type=None,
        workout_duration_minutes=None, workout_intensity=None,
        training_load=0.0, acwr=float(snap.get("acwr") or 1.0), notes=None,
    )
    return ARIAContext(
        user_name="Test",
        chronotype=str(snap.get("chronotype") or "bear"),
        experience_level="intermediate",
        coaching_style="balanced",
        occupation="tester",
        life_season=str(snap.get("life_season") or "maintenance"),
        today=today,
        hrv_7d_avg=float(snap.get("hrv_7d_avg") or 55),
        hrv_7d_trend=str(snap.get("hrv_7d_trend") or "stable"),
        sleep_debt_7d_hours=float(snap.get("sleep_debt_7d_hours") or 0),
        readiness_7d_avg=float(snap.get("readiness_7d_avg") or today.readiness_score),
        readiness_trend=str(snap.get("readiness_trend") or "stable"),
        acwr=float(snap.get("acwr") or 1.0),
        training_streak=0,
        days_since_last_workout=1,
        target_sleep_hours=8.0,
        target_wake_hour=7.0,
        is_overtrained=bool(snap.get("is_overtrained")),
        is_sleep_deprived=bool(snap.get("is_sleep_deprived")),
        has_notable_event=bool(snap.get("notable_event")),
        notable_event_note=snap.get("notable_event"),
        history=[today],
        last_workout_type=snap.get("last_workout_type"),
        last_workout_peak_hr=snap.get("last_workout_peak_hr"),
    )


def _response_from_eval(payload: dict) -> ARIAResponse:
    r = payload.get("response") or {}
    return ARIAResponse(
        prose_summary=r.get("prose_summary") or "",
        recommendation=r.get("recommendation"),
        confidence=float(r.get("confidence") or 0.7),
        used_context=bool(r.get("used_context", True)),
        model_used=r.get("model_used") or "lambda-deterministic",
        query_type=r.get("query_type") or "aria",
        latency_ms=float(r.get("latency_ms") or 0),
        raw=r.get("raw") if isinstance(r.get("raw"), dict) else {},
        model_class=r.get("model_class") or "",
        model_archetype=r.get("model_archetype") or "baseline",
    )


class ExactLineVoicePolicyTests(unittest.TestCase):
    def test_only_0_h_since_strength_fails(self):
        line = "Only 0 h since strength"
        result = evaluate(0, "Should I train today?", 1, make_context(), make_response(line, line))
        self.assertTrue(result.failures, result.failures)
        self.assertTrue(
            any("0 h since" in f.lower() or "zero" in f.lower() or "context utilization" in f.lower()
                for f in result.failures),
            result.failures,
        )
        self.assertLess(result.scores.actionability, 80)
        self.assertLess(result.scores.context_utilization, 50)

    def test_they_have_repair_in_the_bank_fails(self):
        line = "They have repair in the bank"
        result = evaluate(0, "Should I train today?", 1, make_context(), make_response(line, line))
        self.assertTrue(result.failures, result.failures)
        self.assertTrue(
            any("guide" in f.lower() or "repair" in f.lower() or "context utilization" in f.lower()
                for f in result.failures),
            result.failures,
        )
        self.assertLess(result.scores.actionability, 80)

    def test_progress_phrase_counts_as_a_step_only_when_in_recommendation(self):
        phrase = "Hold the structure and progress one variable next block"
        prose_only = make_response(phrase, None)
        self.assertFalse(_has_credit_step(prose_only))
        no_step = evaluate(0, "Am I making progress?", 1, make_context(), prose_only)
        self.assertLess(no_step.scores.actionability, 100)

        as_rec = make_response("You're building. Keep the throughline.", phrase)
        self.assertTrue(_has_credit_step(as_rec))
        with_step = evaluate(0, "Am I making progress?", 1, make_context(), as_rec)
        self.assertEqual(with_step.scores.actionability, 100.0)
        self.assertEqual(with_step.scores.directional_correctness, 100.0)

    def test_metric_dump_reply_scores_below_80_overall(self):
        dump = (
            "Sleep: 8.1 h total, 93 min deep (19%). Deep sleep at 19%. "
            "HR 72 bpm. Readiness is 96, HRV 52ms, ACWR 0.63."
        )
        resp = make_response(dump, "20 easy minutes, then call it.")
        result = evaluate(0, "How was my sleep last night?", 1, make_context(), resp)
        self.assertLess(result.composite_score, 80.0)
        self.assertEqual(result.scores.context_utilization, 0.0)
        self.assertTrue(any("metric dump" in f.lower() or "vitals" in f.lower() for f in result.failures))


class PlainLanguageCreditTests(unittest.TestCase):
    def test_plain_language_state_read_gets_full_context_credit(self):
        cases = (
            "Steadier than last week — keep the throughline.",
            "A bit under your usual, so we stay kind.",
            "Short night and a busy evening. Keep today easy.",
        )
        for prose in cases:
            with self.subTest(prose=prose):
                resp = make_response(prose, "20 easy minutes, then call it.")
                result = evaluate(0, "Should I train today?", 1, make_context(), resp)
                self.assertEqual(result.scores.context_utilization, 100.0, result.failures)
                self.assertGreaterEqual(result.composite_score, 80.0)

    def test_sized_step_from_card_why_gets_full_actionability(self):
        resp = make_response(
            "Last night was short. Keep today kind.",
            None,
            raw={"card": {"action": "", "why": "one set fewer"}},
        )
        result = evaluate(0, "Should I train today?", 1, make_context(), resp)
        self.assertEqual(result.scores.actionability, 100.0)
        self.assertEqual(result.scores.directional_correctness, 100.0)

    def test_zone_2_and_sleep_hours_are_fine(self):
        resp = make_response(
            "Sleep looked like about 7 hours. Steadier than last week.",
            "Keep it zone 2, twenty minutes.",
        )
        result = evaluate(0, "How was my sleep last night?", 1, make_context(), resp)
        self.assertEqual(result.scores.context_utilization, 100.0)
        self.assertEqual(result.scores.actionability, 100.0)
        self.assertFalse(any("metric dump" in f.lower() for f in result.failures), result.failures)


class HoldFixtureRescoreTests(unittest.TestCase):
    def test_rescore_commit0_hold_fixtures_applies_voice_policy(self):
        self.assertTrue(_HOLD_DIR.is_dir(), _HOLD_DIR)
        leak_turns = 0
        for model_id, stored in _HOLD_COMPOSITES.items():
            match = _HOLD_DIR / _HOLD_FILES[model_id]
            self.assertTrue(match.is_file(), match)
            payload = json.loads(match.read_text(encoding="utf-8"))
            self.assertEqual(payload["overall"]["composite"], stored, match.name)
            self.assertEqual(payload.get("engine_model"), "lambda-deterministic")

            results = []
            for ev in payload.get("evaluations") or []:
                ctx = _ctx_from_snap(ev.get("context_snapshot") or {})
                resp = _response_from_eval(ev)
                result = evaluate(
                    int(ev.get("run_id") or 0),
                    ev.get("query") or "",
                    int(ev.get("tier") or 1),
                    ctx,
                    resp,
                )
                results.append(result)
                blob = f"{resp.prose_summary or ''} {resp.recommendation or ''}"
                if "they have repair in the bank" in blob.lower():
                    leak_turns += 1
                    self.assertLess(result.scores.actionability, 100)
                    self.assertTrue(result.failures)
            self.assertTrue(results, match.name)
            stability = analyze(results)
            self.assertGreaterEqual(stability.overall_composite, 0.0)

        self.assertGreater(leak_turns, 0, "fixtures should still contain the 7f69323 guide leak")
        # Same snapshot, honest plain-language reply must get full context credit.
        sample = json.loads((_HOLD_DIR / "anthropic_claude_sonnet_4_6.json").read_text(encoding="utf-8"))
        snap = sample["evaluations"][0]["context_snapshot"]
        honest = evaluate(
            0,
            sample["evaluations"][0]["query"],
            1,
            _ctx_from_snap(snap),
            make_response(
                "Steadier than last week. Short night, so we stay kind.",
                "20 easy minutes, then call it.",
            ),
        )
        self.assertEqual(honest.scores.context_utilization, 100.0)
        self.assertEqual(honest.scores.actionability, 100.0)
        self.assertGreaterEqual(honest.composite_score, 80.0)


class DataTiedContextCreditTests(unittest.TestCase):
    """Full context credit only when the spoken read matches this turn's data."""

    def test_generic_line_gets_no_context_credit(self):
        resp = make_response("Sleep matters. Recovery is important.", "20 easy minutes, then call it.")
        result = evaluate(0, "Should I train today?", 1, make_context(), resp)
        self.assertNotEqual(result.scores.context_utilization, 100.0)
        self.assertLess(result.scores.context_utilization, 80.0)

    def test_contradicting_read_gets_no_context_credit(self):
        long_night = make_context(sleep_hours=9.0)
        short_claim = make_response(
            "Short night — a bit under your usual.",
            "20 easy minutes, then call it.",
        )
        short_result = evaluate(0, "How was my sleep last night?", 1, long_night, short_claim)
        self.assertEqual(short_result.scores.context_utilization, 0.0, short_result.failures)

        falling = make_context(hrv_trend="falling", readiness_trend="falling")
        steady_claim = make_response(
            "Steadier than last week and more consistent.",
            "20 easy minutes, then call it.",
        )
        steady_result = evaluate(0, "Should I train today?", 1, falling, steady_claim)
        self.assertEqual(steady_result.scores.context_utilization, 0.0, steady_result.failures)

        light_week = make_context(acwr=0.7)
        load_claim = make_response(
            "Bigger training week than usual.",
            "20 easy minutes, then call it.",
        )
        load_result = evaluate(0, "Should I train today?", 1, light_week, load_claim)
        self.assertEqual(load_result.scores.context_utilization, 0.0, load_result.failures)

    def test_correct_data_tied_read_gets_full_context_credit(self):
        short_night = make_context(sleep_hours=6.5)
        short_resp = make_response(
            "Short night — a bit under your usual.",
            "20 easy minutes, then call it.",
        )
        short_result = evaluate(0, "How was my sleep last night?", 1, short_night, short_resp)
        self.assertEqual(short_result.scores.context_utilization, 100.0, short_result.failures)

        stable = make_context(hrv_trend="stable", readiness_trend="stable")
        steady_resp = make_response(
            "Steadier than last week and more consistent.",
            "20 easy minutes, then call it.",
        )
        steady_result = evaluate(0, "Should I train today?", 1, stable, steady_resp)
        self.assertEqual(steady_result.scores.context_utilization, 100.0, steady_result.failures)

        heavy = make_context(acwr=1.25)
        load_resp = make_response(
            "Bigger training week than usual.",
            "20 easy minutes, then call it.",
        )
        load_result = evaluate(0, "Should I train today?", 1, heavy, load_resp)
        self.assertEqual(load_result.scores.context_utilization, 100.0, load_result.failures)

        long_night = make_context(sleep_hours=9.0)
        better_resp = make_response(
            "Better night than your usual.",
            "20 easy minutes, then call it.",
        )
        better_result = evaluate(0, "How was my sleep last night?", 1, long_night, better_resp)
        self.assertEqual(better_result.scores.context_utilization, 100.0, better_result.failures)


class FallbackStepCreditTests(unittest.TestCase):
    def test_speak_fallback_step_gets_zero_actionability_and_directional(self):
        rec_only = make_response("Keep today kind.", _SPEAK_FALLBACK)
        rec_result = evaluate(0, "Should I train today?", 1, make_context(), rec_only)
        self.assertEqual(rec_result.scores.actionability, 0.0, rec_result.failures)
        self.assertEqual(rec_result.scores.directional_correctness, 0.0, rec_result.failures)

        only_step = make_response(_SPEAK_FALLBACK, _SPEAK_FALLBACK)
        only_result = evaluate(0, "Should I train today?", 1, make_context(), only_step)
        self.assertEqual(only_result.scores.actionability, 0.0)
        self.assertEqual(only_result.scores.directional_correctness, 0.0)

        via_card = make_response(
            "Keep today kind.",
            None,
            raw={"card": {"action": _SPEAK_FALLBACK, "why": "20 easy minutes, then call it."}},
        )
        card_result = evaluate(0, "Should I train today?", 1, make_context(), via_card)
        self.assertEqual(card_result.scores.actionability, 0.0)
        self.assertEqual(card_result.scores.directional_correctness, 0.0)


class SpeechEvidenceTurnBarTests(unittest.TestCase):
    def test_evaluate_copies_evidence_guide_leak_onto_failures(self):
        resp = make_response(
            "Keep today kind.",
            "20 easy minutes, then call it.",
            raw={
                "card": {
                    "action": "20 easy minutes, then call it.",
                    "evidence": {
                        "why": "They have repair in the bank. Spend it on one quality session.",
                    },
                }
            },
        )
        result = evaluate(0, "Should I train today?", 1, make_context(), resp)
        self.assertTrue(
            any("evidence-guide-leak" in f for f in result.failures),
            result.failures,
        )


if __name__ == "__main__":
    unittest.main()
