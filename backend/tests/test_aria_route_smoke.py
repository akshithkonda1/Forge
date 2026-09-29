"""Smoke: one real /ai/chat and /ai/observe turn. No phrase_key / history mocks."""

from __future__ import annotations

import hashlib
import io
import json
import logging
import os
import unittest

import _bootstrap  # noqa: F401

from aria_core import state_read  # noqa: E402
from routes.aria import handle_post_ai_chat  # noqa: E402
from routes.biometrics import handle_post_observe  # noqa: E402
from storage import dynamodb  # noqa: E402


def _capture_logs(fn):
    buf = io.StringIO()
    handler = logging.StreamHandler(buf)
    handler.setLevel(logging.DEBUG)
    root = logging.getLogger()
    previous = root.level
    root.addHandler(handler)
    root.setLevel(logging.DEBUG)
    try:
        result = fn()
    finally:
        root.removeHandler(handler)
        root.setLevel(previous)
    return result, buf.getvalue()


def _uid_hashes(uid: str, turn: int) -> list[str]:
    needles = [
        hashlib.sha256(uid.encode("utf-8")).hexdigest(),
        hashlib.sha256(f"{uid}\0{turn}".encode("utf-8")).hexdigest(),
    ]
    extra: list[str] = []
    for item in needles:
        extra.append(item[:16])
        extra.append(item[:12])
    return needles + extra


def _assert_no_key_leak(
    test: unittest.TestCase,
    *,
    uid: str,
    turn: int,
    http: dict,
    parsed: dict,
    logs: str,
    spoken_root: dict,
) -> None:
    key = state_read.phrase_key(uid, turn)
    key_needles = {str(key), hex(key), f"{key:x}", f"{key:#x}"}
    spoken = str(spoken_root.get("message") or "").strip()
    prose = spoken_root.get("prose_summary")
    prose_text = "" if prose is None else str(prose)
    raw_body = http.get("body") if isinstance(http.get("body"), str) else json.dumps(parsed)
    surfaces = (
        ("response_body", raw_body),
        ("logs", logs),
        ("message", spoken),
        ("prose_summary", prose_text),
    )
    for label, blob in surfaces:
        for needle in key_needles:
            test.assertNotIn(needle, blob, f"{label} leaked phrase_key {needle!r}")
        for digest in _uid_hashes(uid, turn):
            test.assertNotIn(digest, blob, f"{label} leaked uid-derived hash")
        if label != "response_body":
            # Existing /ai/chat and /ai/observe envelopes echo user_id as a
            # field. Spoken text, prose, and captured logs must not.
            test.assertNotIn(uid, blob, f"{label} leaked user_id")


class ChatObserveRouteSmokeTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"

    def test_chat_and_observe_return_200_with_spoken_reply(self):
        uid = "route-smoke-user"
        chat, chat_logs = _capture_logs(
            lambda: handle_post_ai_chat({"message": "Should I train today?"}, user_id=uid)
        )
        self.assertEqual(chat["statusCode"], 200)
        chat_body = json.loads(chat["body"])
        spoken_chat = str(
            chat_body.get("message") or chat_body.get("prose_summary") or ""
        ).strip()
        self.assertTrue(spoken_chat)
        _assert_no_key_leak(
            self,
            uid=uid,
            turn=0,
            http=chat,
            parsed=chat_body,
            logs=chat_logs,
            spoken_root=chat_body,
        )

        observe, obs_logs = _capture_logs(
            lambda: handle_post_observe(
                {"message": "how did I sleep last night?", "samples": []},
                user_id=uid,
            )
        )
        self.assertEqual(observe["statusCode"], 200)
        obs_body = json.loads(observe["body"])
        aria = obs_body.get("aria_response")
        self.assertIsInstance(aria, dict)
        spoken_obs = str(aria.get("message") or aria.get("prose_summary") or "").strip()
        self.assertTrue(spoken_obs)
        _assert_no_key_leak(
            self,
            uid=uid,
            turn=0,
            http=observe,
            parsed=obs_body,
            logs=obs_logs,
            spoken_root=aria,
        )
