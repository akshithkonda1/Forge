"""Dummy-only ARIA chat: routing, memory-off, redaction, small talk, medical."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from backend.ai.aria_chat import conversation  # noqa: E402
from backend.ai.aria_chat import logging as chatlog  # noqa: E402
from backend.ai.aria_chat.session import (  # noqa: E402
    ChatSession,
    assert_dummy_engine,
    run_turn,
)
from backend.ai import aria_cli  # noqa: E402
from handler import handler  # noqa: E402
from routes.aria import (  # noqa: E402
    _turn_from_history,
    handle_post_ai_chat_local,
    local_dummy_chat_allowed,
    sanitize_inbound_chat_payload,
)
from services import guidance  # noqa: E402
from storage import dynamodb  # noqa: E402


def _payload() -> dict:
    return {"context": aria_cli.PROFILES["depleted"]["context"]}


def _event(body, *, user_id="local-founder"):
    return {
        "requestContext": {
            "http": {"method": "POST", "path": "/ai/chat/local"},
            "authorizer": {"jwt": {"claims": {"sub": user_id}}},
        },
        "headers": {},
        "body": json.dumps(body),
    }


class RoutingGateTests(unittest.TestCase):
    def test_dummy_engine_never_constructs_remote_client(self):
        self.assertEqual(assert_dummy_engine("dummy"), "dummy")
        self.assertEqual(assert_dummy_engine(None), "dummy")
        with patch(
            "backend.ai.aria_chat.session._construct_remote_client",
            side_effect=RuntimeError("no bedrock"),
        ) as factory:
            result = run_turn(
                "hey, how's it going?",
                payload=_payload(),
                persist_log=False,
            )
            factory.assert_not_called()
        self.assertEqual(result["engine"], "dummy")
        self.assertTrue(result["message"])

    def test_non_dummy_engine_hits_patched_client_and_raises(self):
        with patch(
            "backend.ai.aria_chat.session._construct_remote_client",
            side_effect=RuntimeError("no bedrock"),
        ):
            with self.assertRaises(RuntimeError) as ctx:
                assert_dummy_engine("bedrock")
            self.assertIn("no bedrock", str(ctx.exception))

    def test_run_turn_refuses_live_engine(self):
        with patch(
            "backend.ai.aria_chat.session._construct_remote_client",
            side_effect=RuntimeError("no remote"),
        ):
            with self.assertRaises(RuntimeError):
                run_turn("hi", payload=_payload(), engine="claude", persist_log=False)

    def test_local_endpoint_refused_without_flag(self):
        os.environ.pop("ARIA_LOCAL_CHAT", None)
        os.environ.pop("FORGE_ARIA_LOCAL_CHAT", None)
        os.environ["ENVIRONMENT"] = "test"
        self.assertFalse(local_dummy_chat_allowed())
        with self.assertRaises(Exception) as ctx:
            handle_post_ai_chat_local({"message": "hi"}, user_id="local-founder")
        self.assertEqual(getattr(ctx.exception, "status_code", None), 403)

    def test_local_endpoint_dummy_when_flag_set(self):
        os.environ["ARIA_LOCAL_CHAT"] = "1"
        os.environ["ENVIRONMENT"] = "local"
        os.environ["FORGE_ALLOW_DEV_OVERRIDE"] = "true"
        try:
            self.assertTrue(local_dummy_chat_allowed())
            with patch(
                "backend.ai.aria_chat.session._construct_remote_client",
                side_effect=RuntimeError("no bedrock"),
            ) as factory:
                response = handler(
                    _event({"message": "hey", "persist_log": False, "context": _payload()["context"]}),
                    None,
                )
                factory.assert_not_called()
            self.assertEqual(response["statusCode"], 200)
            body = json.loads(response["body"])
            self.assertEqual(body.get("engine"), "dummy")
        finally:
            os.environ.pop("ARIA_LOCAL_CHAT", None)

    def test_production_like_refuses_even_with_flag(self):
        os.environ["ARIA_LOCAL_CHAT"] = "1"
        os.environ["ENVIRONMENT"] = "production"
        try:
            self.assertFalse(local_dummy_chat_allowed())
        finally:
            os.environ["ENVIRONMENT"] = "test"
            os.environ.pop("ARIA_LOCAL_CHAT", None)


class MemoryOffTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_memory_off_identical_and_no_memory_reads(self):
        payload = _payload()
        payload["context"]["last_insights"] = ["SECRET_INSIGHT_DO_NOT_READ"]
        payload["calendar_events"] = [{"title": "Sister's wedding"}]
        calls = {"snapshot": 0, "stm": 0, "living": 0, "stamp": 0}

        def boom_snapshot(*_a, **_k):
            calls["snapshot"] += 1
            raise AssertionError("load_body_snapshot")

        def boom_stm(*_a, **_k):
            calls["stm"] += 1
            raise AssertionError("remember_short_term")

        def boom_living(*_a, **_k):
            calls["living"] += 1
            raise AssertionError("get_or_create_context")

        def boom_stamp(*_a, **_k):
            calls["stamp"] += 1
            raise AssertionError("stamp_living_context")

        with (
            patch("services.fusion.load_body_snapshot", side_effect=boom_snapshot),
            patch(
                "services.aria_context.CoachContextEngine.remember_short_term",
                side_effect=boom_stm,
            ),
            patch(
                "services.aria_context.CoachContextEngine.get_or_create_context",
                side_effect=boom_living,
            ),
            patch(
                "services.contextual_learner.stamp_living_context",
                side_effect=boom_stamp,
            ),
        ):
            a = run_turn(
                "how am I doing?",
                payload=payload,
                memory_enabled=False,
                persist_log=False,
                user_id="mem-off-user",
            )
            b = run_turn(
                "how am I doing?",
                payload=payload,
                memory_enabled=False,
                persist_log=False,
                user_id="mem-off-user",
            )
        self.assertEqual(a["message"], b["message"])
        self.assertNotIn("SECRET_INSIGHT_DO_NOT_READ", a["message"])
        self.assertEqual(calls, {"snapshot": 0, "stm": 0, "living": 0, "stamp": 0})


class RedactionLogTests(unittest.TestCase):
    def test_log_has_no_calendar_title_or_partner_cycle(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = _payload()
            payload["calendar_events"] = [
                {"title": "Sister's wedding", "name": "PII Party"}
            ]
            payload["context"]["lifestyle"] = {
                "tags": ["partner_cycle:day14", "partner_name:sam", "late_caffeine"],
            }
            result = run_turn(
                "hey, how's the weekend?",
                payload=payload,
                memory_enabled=False,
                log_dir=tmp,
                session_id="redact-sess",
            )
            path = Path(result["log_path"])
            blob = path.read_text(encoding="utf-8")
            self.assertNotIn("Sister's wedding", blob)
            self.assertNotIn("PII Party", blob)
            self.assertNotIn("partner_cycle", blob)
            self.assertNotIn("partner_name:sam", blob)
            row = json.loads(blob.strip().splitlines()[0])
            self.assertEqual(row["engine"], "dummy")
            self.assertEqual(row["schema_version"], 1)
            reply = row["reply"]["message"] + " " + row["reply"]["prose_summary"]
            self.assertFalse(chatlog.contains_spoken_metric_digits(reply), reply)
            self.assertNotRegex(reply, r"(?i)\b\d+\s*(bpm|ms|mmhg|hrv)\b")


class SmallTalkAndHistoryTests(unittest.TestCase):
    def test_off_topic_small_talk_in_voice(self):
        result = run_turn(
            "hey, how's it going?",
            payload=_payload(),
            persist_log=False,
        )
        text = result["message"]
        self.assertTrue(text.strip())
        self.assertRegex(text, r"\bI\b")
        self.assertFalse(conversation._COACH_RE.search("hey, how's it going?"))
        self.assertTrue(conversation.is_small_talk("hey, how's it going?"))
        low = text.lower()
        self.assertNotRegex(low, r"\b(diagnose|prescribe|cure|crush it)\b")
        self.assertNotRegex(text, r"\d")

    def test_multi_turn_history_changes_reply_deterministically(self):
        payload = _payload()
        first = run_turn("hey", payload=payload, persist_log=False, user_id="hist-user")
        history = [
            {"role": "user", "content": "hey"},
            {"role": "assistant", "content": first["message"]},
        ]
        second = run_turn(
            "hey", payload=payload, history=history, persist_log=False, user_id="hist-user"
        )
        again = run_turn(
            "hey", payload=payload, history=history, persist_log=False, user_id="hist-user"
        )
        self.assertNotEqual(first["message"], second["message"])
        self.assertEqual(second["message"], again["message"])
        self.assertEqual(second["seed"], again["seed"])
        self.assertEqual(_turn_from_history(history)[0], 1)

    def test_turn_from_history_ignores_persisted_shape(self):
        turn, prior = _turn_from_history(
            [
                {"role": "user", "content": "hello"},
                {"role": "assistant", "content": "Hi."},
                {"role": "user", "content": "how am I doing?"},
            ]
        )
        self.assertEqual(turn, 2)
        self.assertEqual(len(prior), 3)


class MedicalBoundaryTests(unittest.TestCase):
    def test_refer_out_still_escalates(self):
        result = run_turn(
            "do I have diabetes?",
            payload=_payload(),
            persist_log=False,
        )
        self.assertEqual(result.get("guidance_band"), guidance.REFER_OUT)
        low = (result["message"] or "").lower()
        self.assertIn("not a doctor", low)
        self.assertIn("clinician", low)
        self.assertNotRegex(low, r"\byou (probably |likely )?have diabetes\b")

    def test_emergency_still_escalates(self):
        result = run_turn(
            "he's not breathing — call 911",
            payload=_payload(),
            persist_log=False,
        )
        self.assertEqual(result.get("guidance_band"), guidance.EMERGENCY)
        self.assertTrue(result.get("emergency_escalation"))
        self.assertIn("911", result["message"])


class FeedbackHookTests(unittest.TestCase):
    def test_thumbs_down_and_note_by_turn_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = ChatSession(
                payload=_payload(),
                log_dir=tmp,
                session_id="fb-sess",
                memory_enabled=False,
            )
            session.turn("hey")
            tid = session.last_turn_id
            self.assertTrue(tid)
            row = session.rate("down", note="too stiff — wanted more warmth")
            self.assertIsNotNone(row)
            self.assertEqual(row["feedback"]["rating"], "down")
            self.assertIn("warmth", row["feedback"]["note"])
            logged = chatlog.iter_records("fb-sess", log_dir=tmp)
            self.assertEqual(logged[0]["feedback"]["rating"], "down")


class SanitizerStillUsedTests(unittest.TestCase):
    def test_inbound_payload_redacts_before_fuse(self):
        raw = {
            "calendar_events": [{"title": "Sister's wedding"}],
            "context": {"lifestyle": {"tags": ["partner_cycle:day14"]}},
        }
        clean = sanitize_inbound_chat_payload(raw)
        self.assertEqual(clean["calendar_events"][0]["title"], "Busy window")
        self.assertNotIn("partner_cycle:day14", clean["context"]["lifestyle"]["tags"])


if __name__ == "__main__":
    unittest.main()
