"""Smoke: one real /ai/chat and /ai/observe turn. No phrase_key / history mocks."""

from __future__ import annotations

import json
import os
import unittest

import _bootstrap  # noqa: F401

from routes.aria import handle_post_ai_chat  # noqa: E402
from routes.biometrics import handle_post_observe  # noqa: E402
from storage import dynamodb  # noqa: E402


class ChatObserveRouteSmokeTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"

    def test_chat_and_observe_return_200_with_spoken_reply(self):
        uid = "route-smoke-user"
        chat = handle_post_ai_chat({"message": "Should I train today?"}, user_id=uid)
        self.assertEqual(chat["statusCode"], 200)
        chat_body = json.loads(chat["body"])
        spoken_chat = str(
            chat_body.get("message") or chat_body.get("prose_summary") or ""
        ).strip()
        self.assertTrue(spoken_chat)

        observe = handle_post_observe(
            {"message": "how did I sleep last night?", "samples": []},
            user_id=uid,
        )
        self.assertEqual(observe["statusCode"], 200)
        obs_body = json.loads(observe["body"])
        aria = obs_body.get("aria_response")
        self.assertIsInstance(aria, dict)
        spoken_obs = str(aria.get("message") or aria.get("prose_summary") or "").strip()
        self.assertTrue(spoken_obs)
