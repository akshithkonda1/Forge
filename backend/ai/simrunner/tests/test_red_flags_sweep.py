"""Sweep perception._RED_FLAGS through assess() and Dummy /ai/chat."""

from __future__ import annotations

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

from aria_core import guidance  # noqa: E402
from backend.ai.aria_chat import logging as chatlog  # noqa: E402
from backend.ai.aria_chat.session import ChatSession, run_turn  # noqa: E402
from backend.ai.simrunner.aria_simrunner import perception as p  # noqa: E402

CLINICIAN_LINE = (
    "That symptom needs a clinician before any training — please get it checked today."
)
_PENDING_CHEST_AFTER_BENCH = "chest pain after bench"
_PENDING_CHEST_REASON = "pending owner decision"
_MEMORY_KEYS = ("memory", "memory_reference")


def _boom(*_args, **_kwargs):
    raise AssertionError("live model called")


class RedFlagsSweepTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
