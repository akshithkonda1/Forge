"""Plain-language state read against the user's own health baseline.

Bedrock stays off. Live-path tests inject a mocked converse only.
"""

from __future__ import annotations

import json
import os
import re
import unittest

import _bootstrap  # noqa: F401

from aria_core import aria_engine, speak_guard, state_read  # noqa: E402
from services.aria_engine import (  # noqa: E402
    ARIAContext,
    LifestyleContext,
    ProgressContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
)


_DIGIT = re.compile(r"\d")
_BANNED = (
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
    "hrv",
    "readiness",
    "acwr",
    "busier",
)

_SPEAK_QUALITY = None
_SPEAK_QUALITY_NOTE = (
    "Nyx speak_quality is present on this branch; each phrase is gated with "
    "vitals/bark/medical/sludge hits."
)
try:
    from backend.ai.simrunner.aria_simrunner import speak_quality as _SPEAK_QUALITY
except Exception:  # pragma: no cover - equivalent check lives below
    _SPEAK_QUALITY_NOTE = (
        "Nyx speak_quality was not importable; tests use the local "
        "banned-word/digit check only."
    )


def _health_ctx(**overrides) -> ARIAContext:
    ctx = ARIAContext(
        timestamp="2026-01-15T08:00:00+00:00",
        sleep=SleepContext(
            duration_minutes=300,
            rem_minutes=95,
            deep_minutes=90,
            hrv=58,
            baseline_median_minutes=450,
            nights_available=14,
        ),
        readiness=ReadinessContext(
            hrv_7day_trend=-12,
            hrv_30day_baseline=62,
            recovery_score=48,
            hrv_days_available=7,
        ),
        training=TrainingContext(
            last_workout_type="strength",
            hours_since_last_workout=14,
            weekly_load_score=60,
        ),
        progress=ProgressContext(),
        lifestyle=LifestyleContext(),
    )
    for key, value in overrides.items():
        setattr(ctx, key, value)
    return ctx


def _speech(envelope: dict) -> str:
    return speak_guard.user_visible(envelope)


def _read_hits(text: str) -> list[str]:
    low = (text or "").lower()
    return [p for p in state_read.phrase_bank() if p in low]


class PhraseBankTests(unittest.TestCase):
    def test_every_phrase_is_clean_and_passes_speak_quality(self):
        self.assertTrue(state_read.phrase_bank())
        for phrase in state_read.phrase_bank():
            self.assertFalse(_DIGIT.search(phrase), phrase)
            self.assertNotIn("your body is", phrase.lower())
            for word in _BANNED:
                self.assertIsNone(
                    re.search(rf"\b{re.escape(word)}\b", phrase, flags=re.I),
                    f"{word!r} in {phrase!r}",
                )
            if _SPEAK_QUALITY is not None:
                self.assertEqual(_SPEAK_QUALITY.vitals_hits(phrase), [], phrase)
                self.assertEqual(_SPEAK_QUALITY.bark_hits(phrase), [], phrase)
                self.assertEqual(_SPEAK_QUALITY.medical_hits(phrase), [], phrase)
                self.assertEqual(_SPEAK_QUALITY.sludge_hits(phrase), [], phrase)


class StateReadSelectionTests(unittest.TestCase):
    def test_short_night_below_usual(self):
        clause = state_read._state_read(_health_ctx(), seed=0)
        self.assertIn(clause, state_read.SHORT_NIGHT)

    def test_better_night_is_positive(self):
        ctx = _health_ctx(
            sleep=SleepContext(
                duration_minutes=540,
                baseline_median_minutes=420,
                nights_available=7,
            )
        )
        clause = state_read._state_read(ctx, seed=0)
        self.assertIn(clause, state_read.BETTER_NIGHT)

    def test_training_trend_without_load_score_is_not_a_baseline(self):
        ctx = ARIAContext(
            progress=ProgressContext(training_load_trend="rising"),
            training=TrainingContext(weekly_load_score=None),
        )
        self.assertEqual(state_read._state_read(ctx, seed=0), "")
        ctx.training = TrainingContext(weekly_load_score=70)
        self.assertIn(state_read._state_read(ctx, seed=0), state_read.BIGGER_LOAD)

    def test_no_baseline_gives_no_read(self):
        ctx = ARIAContext(
            sleep=SleepContext(duration_minutes=300),
            readiness=ReadinessContext(),
            progress=ProgressContext(),
        )
        self.assertEqual(state_read._state_read(ctx, seed=0), "")

    def test_not_enough_nights_gives_no_sleep_read(self):
        ctx = _health_ctx(
            sleep=SleepContext(
                duration_minutes=300,
                baseline_median_minutes=450,
                nights_available=3,
            ),
            readiness=ReadinessContext(),
            progress=ProgressContext(),
        )
        self.assertEqual(state_read._state_read(ctx, seed=0), "")

    def test_seeded_variation_is_deterministic(self):
        ctx = _health_ctx()
        a = state_read._state_read(ctx, seed=1)
        b = state_read._state_read(ctx, seed=2)
        self.assertTrue(a)
        self.assertTrue(b)
        self.assertNotEqual(a, b)
        self.assertEqual(state_read._state_read(ctx, seed=1), a)
        self.assertEqual(state_read._state_read(ctx, seed=2), b)

    def test_health_fields_only_no_leak_from_lifestyle(self):
        ctx = _health_ctx(
            lifestyle=LifestyleContext(
                tags=["partner_name:LEAK_PARTNER_SAM", "calendar:LEAK_CAL_BOARD_OFFSITE"],
                recent_patterns=["LEAK_PATTERN_LATE_CAFFEINE"],
            )
        )
        clause = state_read._state_read(ctx, seed=0)
        self.assertTrue(clause)
        blob = clause.lower()
        self.assertNotIn("leak_partner_sam", blob)
        self.assertNotIn("leak_cal_board_offsite", blob)
        self.assertNotIn("leak_pattern_late_caffeine", blob)
        resp = aria_engine.generate_response("Should I train today?", ctx, seed=0)
        speech = _speech(resp).lower()
        self.assertTrue(_read_hits(speech), speech)
        self.assertNotIn("leak_partner_sam", speech)
        self.assertNotIn("leak_cal_board_offsite", speech)
        self.assertNotIn("leak_pattern_late_caffeine", speech)

    def test_memory_off_still_yields_a_read(self):
        ctx = _health_ctx(lifestyle=LifestyleContext(recent_patterns=[]))
        ctx.last_insights = []
        ctx.current_goals = []
        self.assertTrue(state_read._state_read(ctx, seed=0))

    def test_near_usual_night_is_not_called_consistent(self):
        ctx = _health_ctx(
            sleep=SleepContext(
                duration_minutes=440,
                baseline_median_minutes=450,
                nights_available=7,
            ),
            readiness=ReadinessContext(),
            progress=ProgressContext(),
        )
        clause = state_read._state_read(ctx, seed=0)
        self.assertIn(clause, state_read.AROUND_USUAL)
        self.assertEqual(clause, "right around your usual")
        self.assertNotIn("consistent", clause)

    def test_consistent_needs_a_multiday_streak(self):
        ctx = _health_ctx(
            sleep=SleepContext(
                duration_minutes=440,
                baseline_median_minutes=450,
                nights_available=7,
            ),
            readiness=ReadinessContext(),
            progress=ProgressContext(workouts_completed_30d=18),
        )
        clause = state_read._state_read(ctx, seed=0)
        self.assertIn(clause, state_read.CONSISTENT)
        self.assertIn("consistent", clause)


class AttachAndPathTests(unittest.TestCase):
    def test_read_once_only_with_step_and_joined(self):
        ctx = _health_ctx()
        resp = aria_engine.generate_response(
            "Should I train today?", ctx, seed=0
        )
        speech = _speech(resp)
        hits = _read_hits(speech)
        self.assertTrue(hits, speech)
        self.assertEqual(sum(speech.lower().count(h) for h in set(hits)), 1, speech)
        self.assertRegex(speech, r"(?i)so\s+")
        self.assertTrue(
            any(cue in speech.lower() for cue in speak_guard._STEP_CUES),
            speech,
        )

    def test_no_step_skips_the_read(self):
        ctx = _health_ctx()
        envelope = {
            "prose_summary": "All good.",
            "message": "All good.",
            "confidence": 0.5,
        }
        out = state_read.apply_to_envelope(envelope, ctx, seed=0, message="hey")
        self.assertEqual(out["prose_summary"], "All good.")
        self.assertEqual(_read_hits(out["prose_summary"]), [])

    def test_skips_when_user_says_terrible_but_data_is_better_night(self):
        ctx = _health_ctx(
            sleep=SleepContext(
                duration_minutes=540,
                baseline_median_minutes=420,
                nights_available=7,
            ),
            readiness=ReadinessContext(),
            progress=ProgressContext(),
        )
        self.assertIn(state_read._state_read(ctx, seed=0), state_read.BETTER_NIGHT)
        envelope = {
            "prose_summary": "Keep today easy, then call it.",
            "message": "Keep today easy, then call it.",
        }
        out = state_read.apply_to_envelope(
            envelope, ctx, seed=0, message="I slept terribly"
        )
        self.assertEqual(out["prose_summary"], "Keep today easy, then call it.")
        self.assertEqual(_read_hits(out["prose_summary"]), [])

    def test_skips_when_user_says_great_but_data_is_short_night(self):
        ctx = _health_ctx()
        self.assertIn(state_read._state_read(ctx, seed=0), state_read.SHORT_NIGHT)
        envelope = {
            "prose_summary": "Keep today easy, then call it.",
            "message": "Keep today easy, then call it.",
        }
        out = state_read.apply_to_envelope(
            envelope, ctx, seed=0, message="I slept great"
        )
        self.assertEqual(out["prose_summary"], "Keep today easy, then call it.")
        self.assertEqual(_read_hits(out["prose_summary"]), [])

    def test_good_news_read_with_lighter_step_is_not_a_so(self):
        ctx = _health_ctx(
            sleep=SleepContext(
                duration_minutes=540,
                baseline_median_minutes=420,
                nights_available=7,
            ),
            readiness=ReadinessContext(),
            progress=ProgressContext(),
        )
        envelope = {
            "prose_summary": "Keep today easy, then call it.",
            "message": "Keep today easy, then call it.",
        }
        out = state_read.apply_to_envelope(
            envelope, ctx, seed=0, message="Should I train today?"
        )
        speech = out["prose_summary"]
        self.assertTrue(_read_hits(speech), speech)
        self.assertNotRegex(speech, r"(?i),\s+so\s+")
        self.assertRegex(speech, r"(?i)\.\s+Still,")
        self.assertIn("easy", speech.lower())
        self.assertTrue(
            any(p in speech.lower() for p in state_read.BETTER_NIGHT),
            speech,
        )

    def test_user_already_said_sleep_is_ack_not_news(self):
        ctx = _health_ctx()
        resp = aria_engine.generate_response(
            "I slept terribly — should I train?", ctx, seed=0
        )
        speech = _speech(resp)
        hits = _read_hits(speech)
        self.assertTrue(hits, speech)
        self.assertRegex(speech, r"(?i)\byeah,\s+")
        # Not presented as a fresh discovery opener without the ack.
        self.assertFalse(re.match(r"(?i)^(short night|a bit under|lighter night)", speech.strip()))

    def test_lambda_path_includes_the_read(self):
        ctx = _health_ctx()
        resp = aria_engine.generate_response("Should I train today?", ctx, seed=1)
        speech = f"{resp.get('prose_summary') or ''} {resp.get('message') or ''}"
        self.assertTrue(_read_hits(speech), speech)

    def test_mocked_live_path_includes_the_read(self):
        self.assertNotIn(
            os.environ.get("ARIA_BEDROCK_ENABLED", "").lower(), {"1", "true", "yes"}
        )
        ctx = _health_ctx()

        def converse(_model_id, _system, _user):
            return json.dumps(
                {
                    "prose_summary": "Keep today easy, then call it.",
                    "response_type": "recommendation",
                    "confidence": 0.8,
                }
            )

        resp = aria_engine.generate_response_live(
            "Should I train today?",
            ctx,
            converse=converse,
            seed=1,
        )
        self.assertEqual(resp.get("reasoning_source"), "bedrock")
        speech = f"{resp.get('prose_summary') or ''} {resp.get('message') or ''}"
        self.assertTrue(_read_hits(speech), speech)
        self.assertRegex(speech, r"(?i)so\s+")
        self.assertNotIn(
            os.environ.get("ARIA_BEDROCK_ENABLED", "").lower(), {"1", "true", "yes"}
        )

    def test_turn_leaves_recent_patterns_and_memory_block_unchanged(self):
        patterns = ["late_caffeine"]
        ctx = _health_ctx(lifestyle=LifestyleContext(recent_patterns=list(patterns)))
        ctx.last_insights = ["keep Friday nights free"]
        before_patterns = list(ctx.lifestyle.recent_patterns)
        before_block = aria_engine._memory_block_from_ctx(ctx)
        resp = aria_engine.generate_response("Should I train today?", ctx, seed=0)
        speech = _speech(resp)
        self.assertTrue(_read_hits(speech), speech)
        self.assertEqual(list(ctx.lifestyle.recent_patterns), before_patterns)
        self.assertEqual(aria_engine._memory_block_from_ctx(ctx), before_block)
        self.assertEqual(state_read.reject_memory_items(ctx.lifestyle.recent_patterns), before_patterns)

    def test_joined_read_sentence_does_not_write_memory(self):
        """A turn that speaks a joined read must not land in patterns / the block."""
        patterns = ["late_caffeine"]
        insight = "keep Friday nights free"
        ctx = _health_ctx(lifestyle=LifestyleContext(recent_patterns=list(patterns)))
        ctx.last_insights = [insight]
        before_patterns = list(ctx.lifestyle.recent_patterns)
        before_insights = list(ctx.last_insights)
        before_block = aria_engine._memory_block_from_ctx(ctx)
        resp = aria_engine.generate_response("Should I train today?", ctx, seed=0)
        speech = _speech(resp)
        self.assertTrue(_read_hits(speech), speech)
        self.assertRegex(speech, r"(?i)short night,\s+so\s+")
        self.assertEqual(list(ctx.lifestyle.recent_patterns), before_patterns)
        self.assertEqual(list(ctx.last_insights), before_insights)
        self.assertEqual(aria_engine._memory_block_from_ctx(ctx), before_block)

        # The chat route saves the first prose_summary sentence via add_insight
        # (routes/aria.py). Next-turn stamp must strip the clause, not the user note.
        takeaway = str(resp.get("prose_summary") or "").split(".")[0].strip()
        self.assertRegex(takeaway, r"(?i)short night")
        living = type("Living", (), {})()
        living.last_insights = [takeaway]
        living.recent_patterns = list(before_patterns)
        living.current_goals = []
        living.constraints = []
        living.supervision_plan = None
        from aria_core import contextual_learner

        stamped = contextual_learner.stamp_living_context(
            _health_ctx(lifestyle=LifestyleContext(recent_patterns=list(before_patterns))),
            living,
        )
        blob = " ".join(stamped.last_insights).lower()
        self.assertNotIn("short night", blob, stamped.last_insights)
        self.assertEqual(list(stamped.lifestyle.recent_patterns), before_patterns)
        block = aria_engine._memory_block_from_ctx(stamped)
        self.assertNotIn("short night", block.lower(), block)

    def test_user_vault_note_matching_a_phrase_survives(self):
        from aria_core import contextual_learner, fusion
        from services.aria_engine import DataPermissions

        note = "lighter week than usual"
        self.assertIn(note, state_read.phrase_bank())
        self.assertFalse(state_read.is_state_read_memory(note))
        payload = {
            "context": {
                "lifestyle": {"recentPatterns": [note, "late_caffeine"]},
            }
        }
        fused = fusion.fuse_turn(
            "test-user-00000000",
            payload,
            DataPermissions.allow_all(),
            persist=False,
            include_stored=False,
            load_learner=False,
        )
        self.assertIn(note, fused.context.lifestyle.recent_patterns)
        self.assertIn("late_caffeine", fused.context.lifestyle.recent_patterns)

        living = type("Living", (), {})()
        living.last_insights = ["keep Friday nights free"]
        living.recent_patterns = [note]
        living.current_goals = []
        living.constraints = []
        living.supervision_plan = None
        stamped = contextual_learner.stamp_living_context(
            _health_ctx(lifestyle=LifestyleContext(recent_patterns=[])),
            living,
        )
        self.assertIn(note, stamped.lifestyle.recent_patterns)

    def test_fuse_turn_and_stamp_drop_a_state_read_from_memory(self):
        from aria_core import contextual_learner, fusion
        from services.aria_engine import DataPermissions

        phrase = state_read.SHORT_NIGHT[0]
        joined = f"{phrase}, so keep it easy."
        payload = {
            "context": {
                "sleep": {
                    "durationMinutes": 300,
                    "baselineMedianMinutes": 450,
                    "nightsAvailable": 7,
                },
                "lifestyle": {"recentPatterns": [joined, "late_caffeine"]},
            }
        }
        fused = fusion.fuse_turn(
            "test-user-00000000",
            payload,
            DataPermissions.allow_all(),
            persist=False,
            include_stored=False,
            load_learner=False,
        )
        self.assertFalse(
            any(phrase in p.lower() for p in fused.context.lifestyle.recent_patterns)
        )
        self.assertIn("late_caffeine", fused.context.lifestyle.recent_patterns)

        living = type("Living", (), {})()
        living.last_insights = [joined, phrase]
        living.recent_patterns = [phrase, "late_caffeine"]
        living.current_goals = []
        living.constraints = []
        living.supervision_plan = None
        stamped = contextual_learner.stamp_living_context(
            _health_ctx(lifestyle=LifestyleContext(recent_patterns=["late_caffeine"])),
            living,
        )
        # Bare phrase in recentPatterns is a user note — keep it.
        self.assertIn(phrase, stamped.lifestyle.recent_patterns)
        self.assertIn("late_caffeine", stamped.lifestyle.recent_patterns)
        insight_blob = " ".join(stamped.last_insights).lower()
        self.assertNotIn(phrase, insight_blob, stamped.last_insights)

    def test_combined_speech_still_passes_vitals_scrub(self):
        ctx = _health_ctx()
        resp = aria_engine.generate_response("Should I train today?", ctx, seed=0)
        speech = _speech(resp)
        self.assertTrue(_read_hits(speech), speech)
        scrubbed = aria_engine._speak_without_vitals(speech)
        self.assertEqual(scrubbed, speech)

    def test_bedrock_flag_stays_off(self):
        self.assertNotIn(
            os.environ.get("ARIA_BEDROCK_ENABLED", "").lower(), {"1", "true", "yes"}
        )


if __name__ == "__main__":
    unittest.main()
