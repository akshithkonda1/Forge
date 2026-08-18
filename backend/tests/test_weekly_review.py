import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from services import weekly_review  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402


def event(method, path, body=None, *, user_id=None):
    payload = {
        "requestContext": {"http": {"method": method, "path": path}},
        "queryStringParameters": {},
        "headers": {},
    }
    if user_id:
        payload["requestContext"]["authorizer"] = {"jwt": {"claims": {"sub": user_id}}}
    if body is not None:
        payload["body"] = __import__("json").dumps(body)
    return payload


def body(response):
    return __import__("json").loads(response["body"])


class WeeklyReviewServiceTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()

    def test_new_user_is_due(self):
        start = weekly_review.start("user-1")
        self.assertTrue(start["due"])
        self.assertEqual(len(start["questions"]), 5)
        self.assertIn("energy", {q["id"] for q in start["questions"]})

    def test_submit_extracts_facts_and_clears_due(self):
        result = weekly_review.submit("user-1", {
            "energy": "low after two late nights",
            "sleep": "5 hours, broken",
            "body": "left knee twinge",
            "focus": "recovery",
            "remember": "I hate morning HIIT",
        })
        self.assertFalse(result["due"])
        self.assertTrue(any("knee" in f.lower() for f in result["facts"]))
        self.assertTrue(any("HIIT" in f for f in result["facts"]))
        self.assertIn("Weekly evaluation", result["summary"])

        again = weekly_review.start("user-1")
        self.assertFalse(again["due"])
        self.assertEqual(again["last_summary"], result["summary"])

    def test_due_again_after_six_days(self):
        weekly_review.submit("user-1", {"energy": "ok"})
        record = weekly_review.load("user-1")
        old = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
        record["completed_at"] = old
        from storage import keys
        dynamodb_store.put_item({**keys.weekly_review_key("user-1"), **record})
        self.assertTrue(weekly_review.is_due(weekly_review.load("user-1")))

    def test_briefing_for_chat_is_none_until_submitted(self):
        self.assertIsNone(weekly_review.briefing_for_chat("nobody"))
        weekly_review.submit("user-2", {"remember": "prefers evening lifts"})
        note = weekly_review.briefing_for_chat("user-2")
        self.assertIsNotNone(note)
        self.assertIn("evening lifts", note)

    def test_submit_sanitizes_control_characters_and_caps_length(self):
        result = weekly_review.submit("user-3", {
            "energy": "high\x00 after rest",
            "remember": "x" * 800,
        })
        self.assertTrue(any("high after rest" in f for f in result["facts"]))
        self.assertTrue(all(len(f) < 600 for f in result["facts"]))


class WeeklyReviewRouteTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"

    def tearDown(self):
        os.environ.pop("FORGE_ALLOW_ANON_TEST_USER", None)

    def test_start_and_submit_round_trip(self):
        start = handler(event("POST", "/ai/weekly-review", {"phase": "start"}, user_id="rev-user"), None)
        self.assertEqual(start["statusCode"], 200)
        self.assertTrue(body(start)["due"])

        submitted = handler(event("POST", "/ai/weekly-review", {
            "phase": "submit",
            "answers": {"energy": "high", "focus": "strength"},
        }, user_id="rev-user"), None)
        self.assertEqual(submitted["statusCode"], 200)
        payload = body(submitted)
        self.assertFalse(payload["due"])
        self.assertTrue(payload["facts"])

    def test_submit_without_answers_is_400(self):
        resp = handler(event("POST", "/ai/weekly-review", {"phase": "submit"}, user_id="rev-user"), None)
        self.assertEqual(resp["statusCode"], 400)

    def test_spoofed_user_is_403(self):
        resp = handler(event("POST", "/ai/weekly-review", {
            "phase": "start",
            "user_id": "someone-else",
        }, user_id="rev-user"), None)
        self.assertEqual(resp["statusCode"], 403)

    def test_chat_stays_healthy_after_weekly_submit(self):
        submitted = handler(event("POST", "/ai/weekly-review", {
            "phase": "submit",
            "answers": {"remember": "prefers evening lifts", "focus": "recovery"},
        }, user_id="rev-chat"), None)
        self.assertEqual(submitted["statusCode"], 200)
        self.assertIn("evening lifts", weekly_review.briefing_for_chat("rev-chat"))

        chat = handler(event("POST", "/ai/chat", {
            "user_id": "rev-chat",
            "message": "should I train today?",
            "recent_metrics": {"readiness": 70},
        }, user_id="rev-chat"), None)
        self.assertEqual(chat["statusCode"], 200)
        self.assertIn("message", body(chat))


if __name__ == "__main__":
    unittest.main()
