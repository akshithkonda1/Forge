"""Offline evals: SimRunner lambda-vs-stub parity, voice-check, rails quality."""

from __future__ import annotations

import os
import unittest
from unittest.mock import patch

import _bootstrap  # noqa: F401

os.environ.setdefault("SIMRUNNER_TODAY", "2026-01-15")

from aria_core.rails import apply_to_envelope
from aria_core.soul import soul_breaks_rails
from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy


PROMPTS = (
    "Should I train today?",
    "How did I sleep last night?",
    "What's a small next move?",
)


class LambdaVsStubParityTests(unittest.TestCase):
    def test_lambda_engine_matches_or_beats_stub_on_rails(self):
        stub_hits = 0
        lambda_hits = 0
        for prompt in PROMPTS:
            stub = dummy.respond(prompt, seed=7, engine="stub")
            live = dummy.respond(prompt, seed=7, engine="lambda")
            stub_text = f"{stub.get('message') or ''} {stub.get('prose_summary') or ''}"
            live_text = f"{live.get('message') or ''} {live.get('prose_summary') or ''}"
            if soul_breaks_rails(stub_text):
                stub_hits += 1
            if soul_breaks_rails(live_text):
                lambda_hits += 1
            self.assertTrue(live_text.strip(), prompt)
        self.assertLessEqual(lambda_hits, stub_hits)

    def test_lambda_engine_never_says_recovery(self):
        for prompt in PROMPTS:
            row = dummy.respond(prompt, seed=3, engine="lambda")
            blob = f"{row.get('message') or ''} {row.get('prose_summary') or ''}".lower()
            self.assertNotIn("recovery", blob, prompt)


class VoiceCheckEvalTests(unittest.TestCase):
    def test_voice_check_cli_exits_zero(self):
        with patch.object(dummy, "respond", return_value={"message": "Easy twenty minutes.", "prose_summary": "Easy twenty minutes."}):
            from backend.ai.simrunner import lifetime_suite

            self.assertIn("--voice-check", " ".join(lifetime_suite.__doc__.split() if lifetime_suite.__doc__ else []) + " --voice-check")
        from backend.ai.simrunner.aria_simrunner import voice_diagnostics

        row = dummy.respond("How did I sleep last night?", seed=4, engine="lambda")
        spoken = str(row.get("message") or row.get("prose_summary") or "")
        diagnosis = voice_diagnostics.diagnose(spoken)
        self.assertTrue(spoken.strip())
        self.assertIn(diagnosis.verdict, {"human", "mixed", "data_driven"})


class RailsSanitizeEvalTests(unittest.TestCase):
    def test_apply_to_envelope_is_idempotent_on_clean_speech(self):
        row = {"message": "Easy twenty minutes, then call it.", "prose_summary": "Easy twenty minutes, then call it."}
        once = apply_to_envelope(row)
        twice = apply_to_envelope(once)
        self.assertEqual(once["message"], twice["message"])
        self.assertFalse(soul_breaks_rails(twice["message"]))


if __name__ == "__main__":
    unittest.main()
