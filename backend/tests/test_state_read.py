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
        # recentPatterns is user-authored — fuse_turn must not rewrite it.
        self.assertIn(joined, fused.context.lifestyle.recent_patterns)
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


class ScoutEqualUsualAndDedupeTests(unittest.TestCase):
    """Nyx Scout day-14: equal 7.3 h called short, sentence twice, digits, Why."""

    def test_equal_and_near_usual_are_never_short(self):
        from services.aria_engine import SLEEP_SHORT_MARGIN_MIN, _interpret_sleep

        class _Base:
            sleep_duration_min = 7.3 * 60
            sleep_duration_n = 14
            deep_frac = None
            rem_frac = None
            efficiency = None

            def personal(self, metric):
                return metric in {"sleep_duration", "sleep"}

        usual = 7.3 * 60
        for night in (usual, usual - 1.0, usual + 1.0, usual - SLEEP_SHORT_MARGIN_MIN + 1):
            ctx = _health_ctx(
                sleep=SleepContext(
                    duration_minutes=night,
                    rem_minutes=95,
                    deep_minutes=90,
                    nights_available=14,
                )
            )
            sig = _interpret_sleep(ctx, _Base())
            self.assertIsNotNone(sig)
            low = sig.interpretation.lower()
            self.assertNotIn("short night", low, (night, sig.interpretation))
            self.assertNotIn("short for you", low, (night, sig.interpretation))
            self.assertNotEqual(sig.direction, "negative", (night, sig.interpretation))

    def test_state_read_clause_never_has_digits_across_grid(self):
        from services.aria_engine import _interpret_sleep

        class _Base:
            def __init__(self, usual_min):
                self.sleep_duration_min = usual_min
                self.sleep_duration_n = 14
                self.deep_frac = None
                self.rem_frac = None
                self.efficiency = None

            def personal(self, metric):
                return metric in {"sleep_duration", "sleep"}

        markers = (
            "short night",
            "short for you",
            "around your usual",
            "below your usual",
            "solid night",
        )
        for night in range(300, 541, 20):
            for usual in range(360, 541, 20):
                ctx = _health_ctx(
                    sleep=SleepContext(
                        duration_minutes=night,
                        rem_minutes=95,
                        deep_minutes=90,
                        nights_available=14,
                        baseline_median_minutes=usual,
                        baseline_mad_minutes=15,
                    )
                )
                clause = state_read._state_read(ctx, seed=night + usual)
                if clause:
                    self.assertFalse(_DIGIT.search(clause), clause)
                sig = _interpret_sleep(ctx, _Base(usual))
                if sig is None:
                    continue
                for bit in sig.interpretation.split(";"):
                    if any(m in bit.lower() for m in markers):
                        self.assertFalse(_DIGIT.search(bit), bit)

    def test_read_sentence_never_appears_twice(self):
        ctx = _health_ctx()
        resp = aria_engine.generate_response("Should I train today?", ctx, seed=0)
        speech = f"{resp.get('prose_summary') or ''} {resp.get('message') or ''}"
        hits = _read_hits(speech)
        self.assertTrue(hits, speech)
        for hit in set(hits):
            self.assertEqual(speech.lower().count(hit), 1, speech)
        doubled = speak_guard.dedupe_envelope_speech(
            {
                "prose_summary": "7.3 h is below your usual 7.3 h — a personal short night.",
                "message": "7.3 h is below your usual 7.3 h — a personal short night. Keep it easy.",
            }
        )
        blob = f"{doubled['prose_summary']} {doubled['message']}"
        self.assertEqual(
            blob.lower().count("personal short night"),
            1,
            blob,
        )

    def test_no_bare_section_labels_in_speech(self):
        cleaned = speak_guard.guard_speak(
            "a personal short night. Why. Sync HealthKit."
        )
        self.assertNotRegex(cleaned, r"(?i)\bWhy\.")
        self.assertNotRegex(cleaned, r"(?i)\bTiming\.")
        joined = speak_guard._join_with_step(
            "a personal short night. Why",
            "Sync HealthKit",
        )
        self.assertNotRegex(joined, r"(?i)\bWhy\.")
        self.assertIn("Sync HealthKit", joined)
        ctx = _health_ctx()
        resp = aria_engine.generate_response("Should I train today?", ctx, seed=0)
        speech = speak_guard.user_visible(resp)
        for label in ("Why.", "Timing.", "Rationale.", "What I notice."):
            self.assertNotIn(label, speech, speech)

    def test_dummy_personas_short_night_clause_has_no_digits(self):
        """Fail if any Dummy persona/seed speaks a short-night clause with a digit."""
        os.environ.setdefault("SIMRUNNER_TODAY", "2026-01-15")
        from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy
        from backend.ai.simrunner.backend_simulator import model_registry as reg
        from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream
        from backend.ai.simrunner.backend_simulator.data_generator import build_context
        from services import fusion as fusion_mod
        from services import aria_engine as engine_mod

        permissions = engine_mod.DataPermissions.allow_all()
        markers = ("short night", "short for you", "around your usual", "below your usual")
        models = []
        for tier in (1, 2, 3):
            models.extend(reg.get_models_by_tier(tier) or [])
        self.assertTrue(models)
        for model in models:
            stream = generate_stream(model["behavioral_profile"], seed=14)
            ctx = build_context(stream, model["behavioral_profile"], 14)
            payload = dummy.sim_context_to_chat_payload(ctx)
            fused = fusion_mod.fuse_turn(
                "test-user-00000000",
                payload,
                permissions,
                persist=False,
                include_stored=False,
                load_learner=False,
            )
            resp = engine_mod.generate_response(
                "Should I train today?",
                fused.context,
                permissions=permissions,
                baselines=fused.baselines,
                seed=14,
            )
            speech = speak_guard.user_visible(resp)
            self.assertIsNone(
                re.search(
                    r"(?i)\d+(?:\.\d+)?\s*h\s+is\s+(?:below|around)\s+your\s+usual",
                    speech,
                ),
                speech,
            )
            for phrase in markers:
                for match in re.finditer(re.escape(phrase), speech, flags=re.I):
                    window = speech[max(0, match.start() - 24): match.end() + 8]
                    self.assertFalse(
                        re.search(r"\d+(?:\.\d+)?\s*h\b", window, flags=re.I),
                        window,
                    )


def _sleep_samples(nights: int, *, last_min: float = 300.0, usual_min: float = 450.0) -> list[dict]:
    samples = []
    for i in range(nights):
        value = last_min if i == nights - 1 else usual_min
        samples.append(
            {
                "type": "sleep",
                "value": value,
                "unit": "min",
                "timestamp": f"2026-01-{i + 1:02d}T08:00:00Z",
                "source": "apple-health",
            }
        )
    return samples


class PartBBaselineBackfillTests(unittest.TestCase):
    """fuse_turn copies BodyModel sleep median onto ctx so Dummy/iOS can read."""

    def test_dummy_14_sleep_samples_reach_state_read(self):
        os.environ.setdefault("SIMRUNNER_TODAY", "2026-01-15")
        from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy
        from backend.ai.simrunner.backend_simulator import model_registry as reg
        from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream
        from backend.ai.simrunner.backend_simulator.data_generator import build_context
        from services import fusion as fusion_mod
        from services.aria_engine import DataPermissions

        model = reg.get_models_by_tier(1)[0]
        stream = generate_stream(model["behavioral_profile"], seed=14)
        ctx = build_context(stream, model["behavioral_profile"], 14)
        payload = dummy.sim_context_to_chat_payload(ctx)
        sleep_n = sum(1 for s in payload["samples"] if s.get("type") == "sleep")
        self.assertGreaterEqual(sleep_n, 14)
        fused = fusion_mod.fuse_turn(
            "test-user-00000000",
            payload,
            DataPermissions.allow_all(),
            persist=False,
            include_stored=False,
            load_learner=False,
        )
        self.assertIsNotNone(fused.baselines.sleep_duration_min)
        self.assertGreaterEqual(fused.baselines.sleep_duration_n, 14)
        self.assertIsNotNone(fused.context.sleep.baseline_median_minutes)
        self.assertGreaterEqual(fused.context.sleep.nights_available or 0, 7)
        fused.context.sleep.duration_minutes = (
            fused.context.sleep.baseline_median_minutes - 90
        )
        clause = state_read._state_read(fused.context, seed=0)
        self.assertIn(clause, state_read.SHORT_NIGHT, clause)

    def test_ios_shaped_payload_with_enough_nights_produces_a_sleep_read(self):
        """Real iOS chat goes through fuse_turn (routes/aria.py:231).

        ARIAContextPayload sleep has durationMinutes + nightsAvailable, no
        baselineMedianMinutes. Remote chat does not send samples
        (AriaOnDeviceHealthPolicy); nights are the /ai/observe snapshot
        fuse_turn reloads when this turn has none.
        """
        from services import fusion as fusion_mod
        from services.aria_engine import DataPermissions

        uid = "ios-chat-user"
        fusion_mod.fuse_turn(
            uid,
            {
                "include_stored": False,
                "samples": _sleep_samples(14, last_min=300, usual_min=450),
            },
            DataPermissions.allow_all(),
            persist=True,
            include_stored=False,
            load_learner=False,
        )
        payload = {
            "include_stored": False,
            "context": {
                "sleep": {"durationMinutes": 300, "nightsAvailable": 14},
                "training": {"weeklyLoadScore": 180},
            },
        }
        self.assertNotIn("baselineMedianMinutes", payload["context"]["sleep"])
        self.assertNotIn("samples", payload)
        fused = fusion_mod.fuse_turn(
            uid,
            payload,
            DataPermissions.allow_all(),
            persist=False,
            include_stored=False,
            load_learner=False,
        )
        self.assertEqual(fused.source, "persisted")
        self.assertIsNotNone(fused.context.sleep.baseline_median_minutes)
        self.assertGreaterEqual(fused.context.sleep.nights_available or 0, 7)
        clause = state_read._state_read(fused.context, seed=0)
        self.assertIn(clause, state_read.SHORT_NIGHT, clause)

    def test_ios_shaped_payload_with_too_few_nights_stays_silent(self):
        from services import fusion as fusion_mod
        from services.aria_engine import DataPermissions

        uid = "ios-chat-thin"
        fusion_mod.fuse_turn(
            uid,
            {
                "include_stored": False,
                "samples": _sleep_samples(3, last_min=300, usual_min=450),
            },
            DataPermissions.allow_all(),
            persist=True,
            include_stored=False,
            load_learner=False,
        )
        fused = fusion_mod.fuse_turn(
            uid,
            {
                "include_stored": False,
                "context": {
                    "sleep": {"durationMinutes": 300, "nightsAvailable": 3},
                    "training": {"weeklyLoadScore": 180},
                },
            },
            DataPermissions.allow_all(),
            persist=False,
            include_stored=False,
            load_learner=False,
        )
        self.assertLess(fused.context.sleep.nights_available or 0, 7)
        self.assertEqual(state_read._state_read(fused.context, seed=0), "")

    def test_to_aria_context_and_asdict_preserve_baseline(self):
        from datetime import datetime, timezone

        from aria_core.biometrics.body_model import BodyModel
        from aria_core.biometrics.types import MetricType, Observation
        from services import fusion as fusion_mod
        from services.aria_engine import DataPermissions

        obs = [
            Observation(
                MetricType.SLEEP_DURATION,
                450.0 if i < 13 else 300.0,
                "min",
                datetime(2026, 1, i + 1, 8, tzinfo=timezone.utc),
                source="apple-health",
            )
            for i in range(14)
        ]
        model = BodyModel.from_observations(obs)
        body_ctx = model.to_aria_context(DataPermissions.allow_all())
        self.assertIsNotNone(body_ctx.sleep.baseline_median_minutes)
        restored = fusion_mod.context_from_asdict(
            {
                "sleep": {
                    "duration_minutes": 300,
                    "baseline_median_minutes": 480,
                    "nights_available": 10,
                }
            }
        )
        self.assertEqual(restored.sleep.baseline_median_minutes, 480)
        self.assertEqual(restored.sleep.nights_available, 10)

    def test_overlay_keeps_a_client_sent_baseline(self):
        from services import fusion as fusion_mod
        from services.aria_engine import DataPermissions

        payload = {
            "include_stored": False,
            "samples": _sleep_samples(2, last_min=300, usual_min=450),
            "context": {
                "sleep": {
                    "durationMinutes": 300,
                    "baselineMedianMinutes": 480,
                    "nightsAvailable": 10,
                }
            },
        }
        fused = fusion_mod.fuse_turn(
            "client-baseline-user",
            payload,
            DataPermissions.allow_all(),
            persist=False,
            include_stored=False,
            load_learner=False,
        )
        self.assertIsNotNone(fused.context.sleep.baseline_median_minutes)


class JoinAndPhraseTests(unittest.TestCase):
    def test_neutral_step_is_own_sentence_not_still(self):
        joined = state_read._join_read(
            "Try a 20 minute walk.",
            "right around your usual",
            ack=False,
            direction="usual",
        )
        self.assertEqual(joined, "Right around your usual. Try a 20 minute walk.")
        self.assertNotIn("Still,", joined)

        synced = state_read._join_read(
            "Sync HealthKit so I can size today.",
            "right around your usual",
            ack=False,
            direction="usual",
        )
        self.assertEqual(
            synced,
            "Right around your usual. Sync HealthKit so I can size today.",
        )
        self.assertNotIn("Still,", synced)

    def test_around_usual_read_is_own_sentence(self):
        ctx = _health_ctx(
            sleep=SleepContext(
                duration_minutes=440,
                baseline_median_minutes=450,
                nights_available=7,
            ),
            readiness=ReadinessContext(),
            progress=ProgressContext(),
        )
        out = state_read.apply_to_envelope(
            {
                "prose_summary": "Try a 20 minute walk.",
                "message": "Try a 20 minute walk.",
            },
            ctx,
            seed=0,
            message="hey",
        )
        self.assertRegex(
            out["prose_summary"], r"(?i)right around your usual\.\s+Try a 20 minute walk"
        )
        self.assertNotIn("Still,", out["prose_summary"])

        synced = state_read.apply_to_envelope(
            {
                "prose_summary": "Sync HealthKit so I can size today.",
                "message": "Sync HealthKit so I can size today.",
            },
            ctx,
            seed=0,
            message="hey",
        )
        self.assertEqual(
            synced["prose_summary"],
            "Right around your usual. Sync HealthKit so I can size today.",
        )
        self.assertNotIn("Still,", synced["prose_summary"])

    def test_joins_never_capitalize_after_comma_except_i(self):
        steps = (
            "Try a 20 minute walk.",
            "Keep today easy, then call it.",
            "Sync HealthKit so I can size today.",
            "I will keep it easy.",
        )
        directions = (
            "short",
            "better",
            "usual",
            "down",
            "up",
            "bigger",
            "lighter",
            "steady",
        )
        for phrase in state_read.phrase_bank():
            for step in steps:
                for direction in directions:
                    joined = state_read._join_read(
                        step, phrase, ack=False, direction=direction
                    )
                    self.assertIsNone(
                        re.search(r", (?!I )[A-Z]", joined),
                        joined,
                    )

    def test_every_short_night_phrase_names_sleep(self):
        self.assertEqual(state_read.SHORT_NIGHT[0], "short night")
        self.assertNotIn("a bit under your usual", state_read.SHORT_NIGHT)
        self.assertIn("a bit under your usual", state_read.READY_DOWN)
        for phrase in state_read.SHORT_NIGHT:
            self.assertRegex(phrase.lower(), r"\b(night|sleep)\b", phrase)

    def test_user_note_with_embedded_phrase_survives_fuse_and_stamp(self):
        from aria_core import contextual_learner, fusion
        from services.aria_engine import DataPermissions

        note = "Had a lighter week than usual because of travel"
        payload = {"context": {"lifestyle": {"recentPatterns": [note]}}}
        fused = fusion.fuse_turn(
            "test-user-00000000",
            payload,
            DataPermissions.allow_all(),
            persist=False,
            include_stored=False,
            load_learner=False,
        )
        self.assertEqual(fused.context.lifestyle.recent_patterns, [note])

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
        self.assertEqual(stamped.lifestyle.recent_patterns, [note])


class InsightTakeawayTests(unittest.TestCase):
    def test_decimal_first_sentence_is_not_stored(self):
        from routes.aria import _insight_takeaway

        self.assertEqual(
            _insight_takeaway("Your sleep came in at 6.5 h, a bit short. Keep today easy."),
            "",
        )

    def test_digit_free_first_sentence_is_stored_whole(self):
        from routes.aria import _insight_takeaway

        self.assertEqual(
            _insight_takeaway("Keep today easy and protect bedtime. Extra later."),
            "Keep today easy and protect bedtime.",
        )

    def test_chat_route_never_saves_truncated_decimal_insight(self):
        from unittest.mock import patch

        from routes.aria import handle_post_ai_chat
        from services.aria_context import CoachContextEngine

        uid = f"insight-digit-{id(self)}"
        prose = "Your sleep came in at 6.5 h, a bit short. Keep today easy."
        envelope = {
            "prose_summary": prose,
            "message": prose,
            "response_type": "recommendation",
            "confidence": 0.5,
            "card": {},
            "contextualization": {},
        }
        with patch("routes.aria.aria_engine.generate_response", return_value=envelope):
            result = handle_post_ai_chat({"message": "how did I sleep?"}, user_id=uid)
        self.assertEqual(result["statusCode"], 200)
        insights = CoachContextEngine().get_or_create_context(uid).last_insights
        blob = " ".join(insights)
        self.assertNotIn("at 6", blob)
        self.assertNotIn("6.5", blob)

    def test_chat_route_saves_digit_free_first_sentence_whole(self):
        from unittest.mock import patch

        from routes.aria import handle_post_ai_chat
        from services.aria_context import CoachContextEngine

        uid = f"insight-clean-{id(self)}"
        prose = "Keep today easy and protect bedtime. Extra later."
        envelope = {
            "prose_summary": prose,
            "message": prose,
            "response_type": "recommendation",
            "confidence": 0.5,
            "card": {},
            "contextualization": {},
        }
        with patch("routes.aria.aria_engine.generate_response", return_value=envelope):
            result = handle_post_ai_chat({"message": "should I train?"}, user_id=uid)
        self.assertEqual(result["statusCode"], 200)
        insights = CoachContextEngine().get_or_create_context(uid).last_insights
        self.assertTrue(any("Keep today easy and protect bedtime." in i for i in insights))
        self.assertFalse(any("Extra later" in i for i in insights))


class AcwrAndGuideLabelTests(unittest.TestCase):
    def test_lambda_and_dummy_never_speak_acwr(self):
        from services.aria_engine import generate_response

        contexts = {
            "protect": _health_ctx(
                training=TrainingContext(
                    acwr=1.62,
                    is_overtrained=True,
                    weekly_load_score=90,
                    hours_since_last_workout=8,
                    last_workout_type="strength",
                )
            ),
            "proceed": _health_ctx(
                sleep=SleepContext(
                    duration_minutes=450,
                    rem_minutes=95,
                    deep_minutes=90,
                    baseline_median_minutes=450,
                    nights_available=14,
                ),
                readiness=ReadinessContext(
                    hrv_7day_trend=2,
                    hrv_30day_baseline=62,
                    recovery_score=74,
                    hrv_days_available=14,
                ),
                training=TrainingContext(
                    acwr=1.0,
                    weekly_load_score=60,
                    hours_since_last_workout=40,
                    last_workout_type="strength",
                ),
            ),
            "clarify": ARIAContext(),
            "recommendation": _health_ctx(
                training=TrainingContext(
                    acwr=1.45,
                    weekly_load_score=80,
                    hours_since_last_workout=16,
                    last_workout_type="strength",
                )
            ),
        }
        seen_types = set()
        for label, ctx in contexts.items():
            resp = generate_response("Should I train today?", ctx, seed=0)
            seen_types.add(str(resp.get("response_type") or ""))
            spoken = " ".join(
                str(p)
                for p in (resp.get("prose_summary"), resp.get("message"))
                if p
            )
            card = resp.get("card") if isinstance(resp.get("card"), dict) else {}
            step = speak_guard._sized_step(
                card,
                stance=str((resp.get("fusion") or {}).get("stance") or ""),
                topic="training",
            )
            self.assertNotRegex(spoken, r"(?i)\bacwr\b", f"{label}: {spoken}")
            self.assertNotRegex(step or "", r"(?i)\bacwr\b", f"{label} step: {step}")

        os.environ.setdefault("SIMRUNNER_TODAY", "2026-01-15")
        from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy
        from backend.ai.simrunner.backend_simulator import model_registry as reg
        from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream
        from backend.ai.simrunner.backend_simulator.data_generator import build_context

        model = reg.get_models_by_tier(1)[0]
        stream = generate_stream(model["behavioral_profile"], seed=1)
        ctx = build_context(stream, model["behavioral_profile"], 14)
        ctx.today.acwr = 1.6
        ctx.acwr = 1.6
        for rtype, prompt in (
            ("protect", "Should I train today?"),
            ("proceed", "Am I making progress?"),
            ("clarify", "What should I do?"),
            ("recommendation", "Should I train today?"),
        ):
            row = dummy.respond(prompt, seed=1, engine="lambda", context=ctx)
            blob = " ".join(
                str(p)
                for p in (
                    row.get("prose_summary"),
                    row.get("message"),
                    row.get("recommendation"),
                    (row.get("card") or {}).get("action")
                    if isinstance(row.get("card"), dict)
                    else "",
                    (row.get("card") or {}).get("why")
                    if isinstance(row.get("card"), dict)
                    else "",
                )
                if p
            )
            self.assertNotRegex(blob, r"(?i)\bacwr\b", f"{rtype}: {blob}")

    def test_spoken_prose_has_no_guide_labels_or_dash_capitals(self):
        _label = re.compile(r"\b[A-Z][a-z]+ [a-z]+:")
        _dash_cap = re.compile(r"[—–-]\s+(?!I\b)[A-Z]")
        os.environ.setdefault("SIMRUNNER_TODAY", "2026-01-15")
        from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy
        from backend.ai.simrunner.backend_simulator import model_registry as reg
        from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream
        from backend.ai.simrunner.backend_simulator.data_generator import build_context

        for line in dummy._WIT_PROTECT + dummy._WIT_PROCEED + dummy._WIT_HONEST:
            self.assertNotRegex(line, _label, line)
            self.assertNotIn("Hug first:", line)
            self.assertNotIn("like a friend would", line)
            self.assertNotIn("restock day", line)
            if "protect sleep tonight" in line:
                self.assertFalse(_DIGIT.search(line), line)
                self.assertNotIn("Hug first:", line)

        models = list(reg.get_models_by_tier(1) or [])
        self.assertTrue(models)
        for model in models:
            for seed in (1, 7, 14):
                stream = generate_stream(model["behavioral_profile"], seed=seed)
                ctx = build_context(stream, model["behavioral_profile"], 14)
                row = dummy.respond(
                    "Should I train today?", seed=seed, engine="lambda", context=ctx
                )
                speech = f"{row.get('prose_summary') or ''} {row.get('message') or ''}"
                self.assertNotRegex(speech, _label, speech)
                self.assertNotRegex(speech, _dash_cap, speech)
                self.assertNotRegex(speech, r"[—–-]\s+Zone", speech)
                self.assertNotIn("Hug first:", speech)
                self.assertNotIn("Why.", speech)
                self._assert_evidence_is_clean(row.get("card"))

        for seed in range(6):
            resp = aria_engine.generate_response(
                "Should I train today?", _health_ctx(), seed=seed
            )
            speech = _speech(resp)
            self.assertNotRegex(speech, _label, speech)
            self.assertNotRegex(speech, _dash_cap, speech)
            self.assertNotRegex(speech, r"[—–-]\s+Zone", speech)
            self.assertNotIn("Hug first:", speech)
            self.assertNotIn("Why.", speech)
            self._assert_evidence_is_clean(resp.get("card"))

    def _assert_evidence_is_clean(self, card):
        ev = (card or {}).get("evidence") if isinstance(card, dict) else None
        if not isinstance(ev, dict):
            return
        blob = " ".join(str(v) for v in ev.values() if isinstance(v, (str, list)))
        low = blob.lower()
        self.assertNotIn("repair in the bank", low, blob)
        self.assertNotIn("hug first", low, blob)
        self.assertNotIn("like a friend would", low, blob)
        self.assertNotIn("restock day", low, blob)
        self.assertNotIn("sleep debt", low, blob)
        self.assertNotIn("sleep-debt", low, blob)
        self.assertNotRegex(blob, r"\bWhy\.", blob)
        if _SPEAK_QUALITY is not None:
            self.assertEqual(_SPEAK_QUALITY.medical_hits(blob), [], blob)
            self.assertEqual(_SPEAK_QUALITY.sludge_hits(blob), [], blob)
        for word in _BANNED:
            if word in {"hrv", "readiness", "acwr"}:
                continue
            self.assertIsNone(
                re.search(rf"\b{re.escape(word)}\b", low),
                f"banned {word!r} in evidence: {blob}",
            )


if __name__ == "__main__":
    unittest.main()
