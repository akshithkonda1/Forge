"""Sweep perception._RED_FLAGS through assess() and Dummy /ai/chat."""

from __future__ import annotations

import copy
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend._paths import ensure_lambda_on_path  # noqa: E402

ensure_lambda_on_path()

from aria_core import contextual_learner  # noqa: E402
from aria_core import guidance  # noqa: E402
from backend.ai.aria_chat import logging as chatlog  # noqa: E402
from backend.ai.aria_chat.session import ChatSession, run_turn  # noqa: E402
from backend.ai.simrunner.aria_simrunner import perception as p  # noqa: E402
from routes.aria import _context, handle_post_ai_chat  # noqa: E402
from storage import dynamodb  # noqa: E402

CLINICIAN_LINE = (
    "That symptom needs a clinician before any training — please get it checked today."
)
_PENDING_CHEST_AFTER_BENCH = "chest pain after bench"
_PENDING_CHEST_REASON = "pending owner decision"
_MEMORY_KEYS = ("memory", "memory_reference")
_COACH_CONTROL = "What should I train today?"


def _boom(*_args, **_kwargs):
    raise AssertionError("live model called")


def _session_memory_snapshot(uid: str) -> dict:
    """Coach living context + persona — catches insights, patterns, persona."""
    living = _context.get_or_create_context(uid)
    persona = contextual_learner.load(uid)
    return {
        "last_insights": list(living.last_insights),
        "recent_patterns": list(living.recent_patterns),
        "lifestyle_tags": list(living.lifestyle_tags),
        "life_facts": list(living.life_facts),
        "relationship_level": living.relationship_level,
        "last_promoted_at": (
            living.last_promoted_at.isoformat() if living.last_promoted_at else None
        ),
        "supervision_plan": copy.deepcopy(living.supervision_plan),
        "persona": persona.as_dict(),
    }


def _dynamo_memory_snapshot() -> dict:
    """Local Dynamo minus rate-limit counters (those increment on every chat)."""
    with dynamodb._local_lock:
        return {
            key: copy.deepcopy(value)
            for key, value in dynamodb._local_store.items()
            if "RATELIMIT#" not in str(key)
        }


def _post_chat(uid: str, message: str) -> dict:
    result = handle_post_ai_chat({"message": message}, user_id=uid)
    body = result.get("body")
    if isinstance(body, str):
        body = json.loads(body)
    return body if isinstance(body, dict) else {}


class RedFlagsSweepTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_every_red_flag_phrase_through_assess_and_dummy_chat(self):
        phrases = list(p._RED_FLAGS) + [_PENDING_CHEST_AFTER_BENCH]
        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        try:
            with patch(
                "services.aria_engine._default_converse", _boom
            ), patch(
                "aria_core.aria_engine._default_converse", _boom
            ), patch(
                "services.aria_swarm.run_swarm", _boom
            ):
                for phrase in phrases:
                    with self.subTest(phrase=phrase):
                        if phrase == _PENDING_CHEST_AFTER_BENCH:
                            self.skipTest(_PENDING_CHEST_REASON)
                        assessed = guidance.assess(phrase)
                        band = (
                            assessed.band
                            if assessed is not None
                            else guidance.classify_band(phrase)
                        )
                        locked = band in guidance.SAFETY_LOCK_BANDS
                        with tempfile.TemporaryDirectory() as tmp:
                            session = ChatSession(
                                payload={"context": {}},
                                log_dir=tmp,
                                session_id=f"red-{abs(hash(phrase)) % 10_000_000}",
                                memory_enabled=True,
                                install_pseudonym="inst-red-flags",
                            )
                            body = session.turn(phrase)
                            blob = Path(session.log_path).read_text(encoding="utf-8")
                            rows = [
                                json.loads(line)
                                for line in blob.splitlines()
                                if line.strip()
                            ]
                        spoken = str(body.get("message") or "")
                        if locked:
                            self.assertEqual(body.get("guidance_band"), band, phrase)
                            self.assertTrue(body.get("safety_lock"), phrase)
                            self.assertEqual(
                                rows[0]["user_turn"], chatlog.REDACTED_USER_TURN, phrase
                            )
                            for key in _MEMORY_KEYS:
                                self.assertNotIn(key, body, phrase)
                            uid = f"lock-{abs(hash(phrase)) % 10_000_000}"
                            before_session = _session_memory_snapshot(uid)
                            before_dynamo = _dynamo_memory_snapshot()
                            posted = _post_chat(uid, phrase)
                            self.assertTrue(posted.get("safety_lock"), phrase)
                            self.assertEqual(
                                _session_memory_snapshot(uid),
                                before_session,
                                phrase,
                            )
                            self.assertEqual(
                                _dynamo_memory_snapshot(),
                                before_dynamo,
                                phrase,
                            )
                        else:
                            self.assertNotIn(CLINICIAN_LINE, spoken, phrase)
                            self.assertFalse(body.get("safety_lock"), phrase)
                            self.assertEqual(rows[0]["user_turn"], phrase, phrase)
                        if CLINICIAN_LINE in spoken and not body.get("safety_lock"):
                            self.fail(
                                f"referral line without lock: {phrase!r} -> {spoken!r}"
                            )
                        chat = run_turn(
                            phrase,
                            persist_log=False,
                            memory_enabled=False,
                        )
                        self.assertEqual(
                            chat.get("guidance_band") or guidance.COACH,
                            band,
                            phrase,
                        )
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous

        coach_uid = "coach-persist-control"
        before_session = _session_memory_snapshot(coach_uid)
        before_dynamo = _dynamo_memory_snapshot()
        coach = _post_chat(coach_uid, _COACH_CONTROL)
        self.assertFalse(coach.get("safety_lock"), _COACH_CONTROL)
        self.assertNotEqual(
            _session_memory_snapshot(coach_uid),
            before_session,
            "COACH control must save session memory",
        )
        self.assertNotEqual(
            _dynamo_memory_snapshot(),
            before_dynamo,
            "COACH control must write the local Dynamo store",
        )


if __name__ == "__main__":
    unittest.main()
