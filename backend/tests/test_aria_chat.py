"""Dummy-only ARIA chat: routing pin, Iris voice, privacy, medical."""

from __future__ import annotations

import hashlib
import json
import os
import re
import socket
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from backend.ai.aria_chat import conversation  # noqa: E402
from backend.ai.aria_chat import logging as chatlog  # noqa: E402
from backend.ai.aria_chat.endpoint import (  # noqa: E402
    handle_post_ai_chat_local,
    local_dummy_chat_allowed,
)
from backend.ai.aria_chat.session import (  # noqa: E402
    ChatSession,
    assert_dummy_engine,
    run_turn,
)
from backend.ai.simrunner.aria_simrunner.dummy_orchestrator import (  # noqa: E402
    ENGINE_LAMBDA,
    respond as dummy_respond,
)
from backend.ai import aria_cli  # noqa: E402
from aria_core import state_read  # noqa: E402
from handler import handler  # noqa: E402
from routes.aria import (  # noqa: E402
    _DENIED_LIFESTYLE,
    _turn_from_history,
    sanitize_inbound_chat_payload,
)
from services import guidance  # noqa: E402
from storage import dynamodb  # noqa: E402

_PSEUDO = "inst-test-aria-chat"
_DIGIT = re.compile(r"\d")
_MEDICAL = re.compile(r"(?i)\b(overtraining|fatigue|insomnia|deficiency)\b")
_ROBOT = re.compile(r"(?i)\b(great question|as an ai|i(?:'| a)?d be happy to)\b")


def _payload(profile: str = "depleted") -> dict:
    return {"context": aria_cli.PROFILES[profile]["context"]}


def _event(body, *, user_id="local-founder"):
    return {
        "requestContext": {
            "http": {"method": "POST", "path": "/ai/chat/local"},
            "authorizer": {"jwt": {"claims": {"sub": user_id}}},
        },
        "headers": {},
        "body": json.dumps(body),
    }


def _turn(message: str, **kwargs):
    kwargs.setdefault("payload", _payload())
    kwargs.setdefault("install_pseudonym", _PSEUDO)
    if "persist_log" not in kwargs:
        kwargs["persist_log"] = kwargs.get("log_dir") is not None
    return run_turn(message, **kwargs)


def _sentences(text: str) -> list[str]:
    return [p.strip() for p in re.split(r"(?<=[.!?])\s+", (text or "").strip()) if p.strip()]


def _spoken_digits(text: str) -> bool:
    return bool(_DIGIT.search((text or "").replace("911", "")))


class RoutingGateTests(unittest.TestCase):
    def test_dummy_engine_never_constructs_remote_client(self):
        self.assertEqual(assert_dummy_engine("dummy"), "dummy")
        self.assertEqual(assert_dummy_engine(None), "dummy")
        with patch(
            "backend.ai.aria_chat.session._construct_remote_client",
            side_effect=RuntimeError("no bedrock"),
        ) as factory:
            result = _turn("hey, how's it going?")
            factory.assert_not_called()
        self.assertEqual(result["engine"], "dummy")
        self.assertEqual(result["dummy_engine"], ENGINE_LAMBDA)
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
                _turn("hi", engine="claude")

    def test_engine_pin_calls_dummy_respond_lambda(self):
        with patch(
            "backend.ai.aria_chat.session.dummy_respond",
            wraps=dummy_respond,
        ) as spy:
            result = _turn("hey, how's it going?")
        spy.assert_called()
        kwargs = spy.call_args.kwargs
        self.assertEqual(kwargs.get("engine"), ENGINE_LAMBDA)
        self.assertIsInstance(kwargs.get("chat_payload"), dict)
        self.assertEqual(result["dummy_engine"], ENGINE_LAMBDA)

    def test_bedrock_enabled_true_does_not_construct_boto3_client(self):
        import sys
        import types

        created = []

        def capture_client(*args, **kwargs):
            created.append((args, kwargs))
            raise AssertionError("boto3.client constructed")

        fake_boto = types.ModuleType("boto3")
        fake_boto.client = capture_client  # type: ignore[attr-defined]
        fake_boto.resource = capture_client  # type: ignore[attr-defined]
        with patch.dict(os.environ, {"ARIA_BEDROCK_ENABLED": "true"}):
            with patch.dict(sys.modules, {"boto3": fake_boto}):
                result = _turn("hey, how's it going?")
        self.assertEqual(created, [])
        self.assertEqual(result["engine"], "dummy")
        self.assertEqual(result["dummy_engine"], ENGINE_LAMBDA)

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
        try:
            self.assertTrue(local_dummy_chat_allowed())
            with patch(
                "backend.ai.aria_chat.session._construct_remote_client",
                side_effect=RuntimeError("no bedrock"),
            ) as factory:
                body = handle_post_ai_chat_local(
                    {
                        "message": "hey",
                        "persist_log": False,
                        "context": _payload()["context"],
                    },
                    user_id="local-founder",
                )
                factory.assert_not_called()
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

    def test_handler_does_not_register_local_chat(self):
        response = handler(
            _event({"message": "hey", "persist_log": False, "context": _payload()["context"]}),
            None,
        )
        self.assertEqual(response["statusCode"], 404)

    def test_local_chat_not_in_terraform_or_handler_source(self):
        infra = Path(__file__).resolve().parents[1] / "infra"
        hits = []
        for path in infra.rglob("*"):
            if not path.is_file() or path.suffix not in {".tf", ".py", ".json", ".yml", ".yaml"}:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            if "/ai/chat/local" in text or "handle_post_ai_chat_local" in text:
                hits.append(str(path))
        self.assertEqual(hits, [])


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
            a = _turn(
                "how am I doing?",
                payload=payload,
                memory_enabled=False,
                user_id="mem-off-user",
            )
            b = _turn(
                "how am I doing?",
                payload=payload,
                memory_enabled=False,
                user_id="mem-off-user",
            )
        self.assertEqual(a["message"], b["message"])
        self.assertNotIn("SECRET_INSIGHT_DO_NOT_READ", a["message"])
        self.assertEqual(calls, {"snapshot": 0, "stm": 0, "living": 0, "stamp": 0})
        self.assertNotRegex(a["message"], r"(?i)\bi remember\b")


class RedactionLogTests(unittest.TestCase):
    def test_log_has_no_calendar_title_or_partner_cycle(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = _payload()
            payload["calendar_events"] = [
                {"title": "Sister's wedding", "name": "PII Party"}
            ]
            payload["context"]["lifestyle"] = {
                "tags": ["partner_cycle:day14", "partner_name:sam", "late_fee"],
            }
            result = _turn(
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
            self.assertEqual(row["schema_version"], 3)
            self.assertTrue(row["commit_sha"])
            self.assertTrue(row["user_turn_key"].startswith("utk:"))
            self.assertIn("stance", row)
            reply = row["reply"]["message"] + " " + row["reply"]["prose_summary"]
            self.assertFalse(chatlog.contains_spoken_metric_digits(reply), reply)
            self.assertFalse(_spoken_digits(reply), reply)
            self.assertEqual(row["llm_calls"], 0)
            self.assertEqual(row["network_calls"], 0)
            self.assertEqual(row["research"], [])
            self.assertGreaterEqual(row["wall_ms"], 0)
            self.assertGreaterEqual(row["cpu_ms"], 0)
            self.assertEqual(row["subagent_spawn_count"], 0)
            self.assertEqual(row["max_depth"], 0)
            self.assertFalse(row["budget_exhausted"])
            for item in row["agents_woken"]:
                self.assertIn(item["wake_reason"], chatlog.ALLOWED_WAKE_REASONS)
                self.assertTrue(item["kind"])
                self.assertNotIn("profile", item)
            for item in row["agent_writes"]:
                self.assertIsInstance(item.get("keys"), list)
                self.assertIsInstance(item.get("elapsed_ms"), int)
            self.assertNotIn("profile", json.dumps(row["research"]))

    def test_no_uid_in_log_and_replay_recomputes_phrase_key(self):
        uid = "real-user-alice-42"
        uid_sha = hashlib.sha256(uid.encode("utf-8")).hexdigest()
        with tempfile.TemporaryDirectory() as tmp:
            payload = _payload()
            payload["calendar_events"] = [{"title": "Dr. Patel follow-up"}]
            first = _turn(
                "hey about Dr. Patel follow-up",
                user_id=uid,
                payload=payload,
                log_dir=tmp,
                session_id="priv-sess",
            )
            second = _turn(
                "still on that Busy window?",
                user_id=uid,
                payload=payload,
                history=[
                    {"role": "user", "content": "hey about Dr. Patel follow-up"},
                    {"role": "assistant", "content": first["message"]},
                ],
                log_dir=tmp,
                session_id="priv-sess",
            )
            blob = Path(second["log_path"]).read_text(encoding="utf-8")
            self.assertNotIn(uid, blob)
            self.assertNotIn(uid_sha, blob)
            self.assertNotIn(uid_sha[:16], blob)
            self.assertNotIn("Dr. Patel follow-up", blob)
            self.assertNotIn("user_id", blob)
            rows = [json.loads(line) for line in blob.splitlines() if line.strip()]
            self.assertGreaterEqual(len(rows), 2)
            for row in rows:
                self.assertNotIn("user_id", row)
                self.assertEqual(row["schema_version"], 3)
                self.assertEqual(row["install_pseudonym"], _PSEUDO)
                phrase = state_read.phrase_key(
                    None,
                    row["user_turn"],
                    user_id=row["install_pseudonym"],
                    turn=row["turn"],
                )
                turn_s = state_read.turn_seed(None, row["user_turn"], seed=phrase)
                self.assertEqual(phrase, row["seed"])
                self.assertEqual(turn_s, row["turn_seed"])
                self.assertEqual(turn_s, row["seed"])
                for code in row["stance_inputs"]:
                    self.assertIn(code, chatlog.ALLOWED_STANCE_INPUTS)
            # Request history is sanitized, never the raw calendar title.
            self.assertTrue(rows[1]["request_history"])
            self.assertNotIn("Dr. Patel follow-up", json.dumps(rows[1]["request_history"]))

    def test_never_logs_memory_contents(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = _payload()
            payload["memory_prompt_block"] = "SECRET_PROMPT_BLOCK"
            payload["notes"] = ["SECRET_COMPANION_NOTE"]
            payload["persona"] = {"voice": "SECRET_PERSONA"}
            payload["context"]["last_insights"] = ["SECRET_INSIGHT"]
            payload["context"]["lifestyle"] = {
                "tags": ["late_fee"],
                "recentPatterns": ["SECRET_PATTERN"],
            }
            result = _turn(
                "hey, how's it going?",
                payload=payload,
                memory_enabled=True,
                log_dir=tmp,
                session_id="mem-log-sess",
            )
            blob = Path(result["log_path"]).read_text(encoding="utf-8")
            for secret in (
                "SECRET_PROMPT_BLOCK",
                "SECRET_COMPANION_NOTE",
                "SECRET_PERSONA",
                "SECRET_INSIGHT",
                "SECRET_PATTERN",
            ):
                self.assertNotIn(secret, blob)
            row = json.loads(blob.strip().splitlines()[0])
            for key in (
                "memory_prompt_block",
                "persona",
                "recentPatterns",
                "last_insights",
                "notes",
            ):
                self.assertNotIn(key, row)
            self.assertIn("memory_off", row)
            self.assertFalse(row["memory_off"])
            for code in row["stance_inputs"]:
                self.assertIn(code, chatlog.ALLOWED_STANCE_INPUTS)

    def test_export_rechecks_redaction(self):
        with tempfile.TemporaryDirectory() as tmp:
            session_id = "dirty-export"
            path = Path(tmp) / f"{session_id}.jsonl"
            dirty = {
                "schema_version": 2,
                "engine": "dummy",
                "user_turn": "partner_cycle:day14 at Dr. Patel follow-up",
                "request_history": ["calendar:title:Sister's wedding"],
                "feedback": {
                    "rating": "down",
                    "note": "partner_cycle:day14 at Dr. Patel follow-up",
                },
                "reply": {
                    "message": "HRV 44 and 6 hours",
                    "prose_summary": "score 88",
                },
                "last_insights": ["SECRET_INSIGHT"],
                "persona": {"voice": "SECRET_PERSONA"},
                "stance_inputs": ["protect"],
            }
            path.write_text(json.dumps(dirty) + "\n", encoding="utf-8")
            dest = Path(tmp) / "out.jsonl"
            chatlog.export_session(
                session_id,
                dest=dest,
                log_dir=tmp,
                needles=["Dr. Patel follow-up", "Sister's wedding"],
            )
            text = dest.read_text(encoding="utf-8")
            self.assertIsNone(_DENIED_LIFESTYLE.search(text), text)
            self.assertNotIn("Dr. Patel follow-up", text)
            self.assertNotIn("Sister's wedding", text)
            self.assertNotIn("partner_cycle", text)
            self.assertNotIn("SECRET_INSIGHT", text)
            self.assertNotIn("SECRET_PERSONA", text)
            row = json.loads(text.strip().splitlines()[0])
            speech = row["reply"]["message"] + " " + row["reply"]["prose_summary"]
            self.assertFalse(_spoken_digits(speech), speech)
            self.assertNotIn("last_insights", row)
            self.assertNotIn("persona", row)

    def test_leak_calendar_title_partner_and_rating_note(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = _payload()
            payload["calendar_events"] = [{"title": "Dr. Patel follow-up"}]
            payload["context"]["lifestyle"] = {
                "tags": ["partner_cycle:day14", "late_fee"],
            }
            session = ChatSession(
                payload=payload,
                log_dir=tmp,
                session_id="leak-sess",
                memory_enabled=False,
                install_pseudonym=_PSEUDO,
            )
            session.turn("hey")
            session.rate(
                "down",
                note="partner_cycle:day14 at Dr. Patel follow-up was too stiff",
            )
            raw = Path(session.log_path).read_bytes()
            self.assertNotIn(b"Dr. Patel follow-up", raw)
            self.assertNotIn(b"partner_cycle", raw)
            dest = Path(tmp) / "export.jsonl"
            exported = session.export(dest)
            out = exported.read_bytes()
            self.assertNotIn(b"Dr. Patel follow-up", out)
            self.assertNotIn(b"partner_cycle", out)
            text = exported.read_text(encoding="utf-8")
            self.assertIsNone(_DENIED_LIFESTYLE.search(text))
            row = json.loads(text.strip().splitlines()[0])
            speech = row["reply"]["message"] + " " + row["reply"]["prose_summary"]
            self.assertFalse(_spoken_digits(speech), speech)
            self.assertIn("memory_off", row)
            self.assertTrue(row["memory_off"])


class SmallTalkAndHistoryTests(unittest.TestCase):
    def test_off_topic_small_talk_in_voice(self):
        result = _turn("hey, how's it going?")
        text = result["message"]
        self.assertTrue(text.strip())
        self.assertRegex(text, r"\bI\b")
        self.assertTrue(conversation.is_small_talk("hey, how's it going?"))
        low = text.lower()
        self.assertNotRegex(low, r"\b(diagnose|prescribe|cure|crush it)\b")
        self.assertFalse(_spoken_digits(text))
        self.assertLessEqual(len(_sentences(text)), 3)
        self.assertLessEqual(text.count("?"), 1)
        self.assertIsNone(_ROBOT.search(text))

    def test_movie_stays_on_topic(self):
        result = _turn("we watched a movie last night and the ending wrecked me")
        low = result["message"].lower()
        self.assertTrue(any(w in low for w in ("movie", "film")))
        self.assertNotRegex(low, r"\b(sleep|hrv|recover|workout|train)\b")
        self.assertFalse(_spoken_digits(result["message"]))

    def test_multi_turn_history_changes_reply_deterministically(self):
        payload = _payload()
        first = _turn("hey", payload=payload, user_id="hist-user")
        history = [
            {"role": "user", "content": "hey"},
            {"role": "assistant", "content": first["message"]},
        ]
        second = _turn("hey", payload=payload, history=history, user_id="hist-user")
        again = _turn("hey", payload=payload, history=history, user_id="hist-user")
        self.assertNotEqual(first["message"], second["message"])
        self.assertEqual(second["message"], again["message"])
        self.assertEqual(second["seed"], again["seed"])
        self.assertEqual(_turn_from_history(history)[0], 1)

    def test_follow_up_refers_to_earlier_turn(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        session = ChatSession(
            payload=_payload(),
            memory_enabled=False,
            install_pseudonym=_PSEUDO,
            log_dir=tmp.name,
        )
        first = session.turn("my dog stole the couch again")
        self.assertTrue(conversation.is_small_talk("my dog stole the couch again"))
        second = session.turn("do you think he's plotting against me?")
        low = second["message"].lower()
        self.assertTrue(any(w in low for w in ("dog", "couch")))
        self.assertNotEqual(conversation.opener_key(first["message"]), conversation.opener_key(second["message"]))

    def test_turn_from_history_ignores_persisted_shape(self):
        turn, prior = _turn_from_history(
            [
                {"role": "user", "content": "hello"},
                {"role": "assistant", "content": "Hi."},
                {"role": "user", "content": "how am I doing?"},
            ]
        )
        self.assertEqual(turn, 2)
        self.assertEqual(prior, ["hello", "how am I doing?"])


class VoiceBarTests(unittest.TestCase):
    def test_no_numbers_even_when_asked(self):
        result = _turn("what's my recovery score and ACWR?")
        self.assertFalse(_spoken_digits(result["message"]), result["message"])
        self.assertIn("card", result["message"].lower())
        self.assertLessEqual(len(_sentences(result["message"])), 3)

    def test_no_medical_terms_on_coaching_or_short_sleep(self):
        for message in (
            "how am I doing?",
            "I only slept a few hours and I have a hard session today",
        ):
            result = _turn(message)
            self.assertIsNone(_MEDICAL.search(result["message"]), result["message"])
            self.assertFalse(_spoken_digits(result["message"]), result["message"])
            self.assertLessEqual(len(_sentences(result["message"])), 3)

    def test_thin_data_is_honest(self):
        result = _turn("how am I doing?", payload=_payload("sparse"))
        self.assertIn("enough to go on", result["message"].lower())
        self.assertNotRegex(result["message"].lower(), r"\bi remember\b")

    def test_never_claims_human(self):
        result = _turn("are you just a fancy toaster with opinions?")
        self.assertNotRegex(result["message"], r"(?i)\bi(?:'| a)?m (?:a )?human\b")
        self.assertTrue(conversation.is_joke("are you just a fancy toaster with opinions?"))


class MedicalBoundaryTests(unittest.TestCase):
    def test_refer_out_still_escalates(self):
        result = _turn("do I have diabetes?")
        self.assertEqual(result.get("guidance_band"), guidance.REFER_OUT)
        low = (result["message"] or "").lower()
        self.assertIn("not a doctor", low)
        self.assertIn("clinician", low)
        self.assertNotRegex(low, r"\byou (probably |likely )?have diabetes\b")

    def test_sleep_apnea_refers_out(self):
        result = _turn("do I have sleep apnea?")
        self.assertEqual(result.get("guidance_band"), guidance.REFER_OUT)
        low = (result["message"] or "").lower()
        self.assertIn("not a doctor", low)
        self.assertNotRegex(low, r"\byou (probably |likely )?have sleep apnea\b")

    def test_emergency_still_escalates(self):
        result = _turn("he's not breathing — call 911")
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
                install_pseudonym=_PSEUDO,
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


class NoNetworkSessionTests(unittest.TestCase):
    def test_sockets_blocked_across_session_including_rate_and_note(self):
        class _Blocked(socket.socket):
            def __init__(self, *args, **kwargs):
                raise OSError("network blocked for Dummy chat")

        with tempfile.TemporaryDirectory() as tmp:
            session = ChatSession(
                payload=_payload(),
                log_dir=tmp,
                session_id="net-sess",
                memory_enabled=False,
                install_pseudonym=_PSEUDO,
            )
            with patch(
                "backend.ai.simrunner.aria_simrunner.web_research.look_up",
                side_effect=AssertionError("web retrieve"),
            ):
                with patch("socket.socket", _Blocked):
                    first = session.turn("hey, how's it going?")
                    session.rate("down", note="too stiff")
                    second = session.turn("how am I doing?")
            self.assertTrue(first["message"])
            self.assertTrue(second["message"])
            row = chatlog.iter_records("net-sess", log_dir=tmp)[0]
            self.assertEqual(row["network_calls"], 0)
            self.assertEqual(row["llm_calls"], 0)
            self.assertEqual(row["research"], [])
            self.assertEqual(row["feedback"]["rating"], "down")


class SchemaTelemetryTests(unittest.TestCase):
    def test_dummy_telemetry_is_counts_and_reason_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = _turn(
                "how am I doing?",
                log_dir=tmp,
                session_id="tel-sess",
            )
            row = json.loads(Path(result["log_path"]).read_text().splitlines()[0])
            self.assertEqual(row["schema_version"], 3)
            self.assertEqual(row["llm_calls"], 0)
            self.assertEqual(row["network_calls"], 0)
            self.assertEqual(row["research"], [])
            self.assertEqual(row["subagent_spawn_count"], 0)
            self.assertEqual(row["max_depth"], 0)
            self.assertFalse(row["budget_exhausted"])
            self.assertGreaterEqual(row["wall_ms"], 0)
            self.assertGreaterEqual(row["cpu_ms"], 0)
            self.assertNotIn("profile", json.dumps(row["research"]))
            self.assertNotIn(row["install_pseudonym"], json.dumps(row["research"]))
            for item in row["agents_woken"]:
                self.assertIn("kind", item)
                self.assertIn(item["wake_reason"], chatlog.ALLOWED_WAKE_REASONS)
                self.assertNotIn("profile", item)
            for item in row["agent_writes"]:
                self.assertTrue(all(isinstance(k, str) for k in item["keys"]))
                self.assertIsInstance(item["elapsed_ms"], int)


class SixTurnSampleTests(unittest.TestCase):
    def test_six_turn_recipe_and_extras(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = ChatSession(
                payload=_payload(),
                log_dir=tmp,
                session_id="sample-sess",
                memory_enabled=True,
                install_pseudonym=_PSEUDO,
            )
            small = session.turn("my dog stole the couch again")
            follow = session.turn("do you think he's plotting against me?")
            safety = session.turn(
                "I only slept a few hours and I have a hard session today"
            )
            vague = session.turn("how am I doing?")
            medical = session.turn("do I have sleep apnea?")
            joke = session.turn("are you just a fancy toaster with opinions?")
            session.set_memory(False)
            mem_off = session.turn("remember my sister's wedding last year?")
            session.rate("down", note="too stiff — wanted more warmth")

            self.assertTrue(conversation.is_small_talk("my dog stole the couch again"))
            self.assertIn("dog", small["message"].lower())
            self.assertTrue(any(w in follow["message"].lower() for w in ("dog", "couch")))
            self.assertIsNone(_MEDICAL.search(safety["message"]))
            self.assertFalse(_spoken_digits(vague["message"]))
            self.assertEqual(medical.get("guidance_band"), guidance.REFER_OUT)
            self.assertTrue(conversation.is_joke("are you just a fancy toaster with opinions?"))
            self.assertNotRegex(mem_off["message"], r"(?i)\bi remember\b")
            self.assertIn("this chat", mem_off["message"].lower())
            for row in (small, follow, safety, vague, joke, mem_off):
                self.assertLessEqual(len(_sentences(row["message"])), 3, row["message"])
                self.assertLessEqual(row["message"].count("?"), 1, row["message"])
                self.assertIsNone(_ROBOT.search(row["message"]), row["message"])
            logged = chatlog.iter_records("sample-sess", log_dir=tmp)
            self.assertEqual(logged[-1]["feedback"]["rating"], "down")
            self.assertIn("warmth", logged[-1]["feedback"]["note"])


class PurgeTests(unittest.TestCase):
    def test_purge_deletes_logs_memory_off_does_not(self):
        with tempfile.TemporaryDirectory() as tmp:
            session = ChatSession(
                payload=_payload(),
                log_dir=tmp,
                session_id="purge-sess",
                install_pseudonym=_PSEUDO,
            )
            session.turn("hey")
            self.assertTrue(Path(session.log_path).is_file())
            session.set_memory(False)
            session.turn("how am I doing?")
            self.assertTrue(Path(tmp, "purge-sess.jsonl").is_file())
            n = session.purge()
            self.assertGreaterEqual(n, 1)
            self.assertFalse(Path(tmp, "purge-sess.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
