"""Regression tests for the 2026-10-28 bug hunt (BH-01..BH-09, BH-15/16 source)."""

from __future__ import annotations

import json
import os
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from handler import handler
from responses import RouteError
from routes import coach as coach_routes
from seed_data import today_iso
from services import web_ingest
from storage import dynamodb
from storage import keys
from test_backend_handler import body, event


REPO = Path(__file__).resolve().parents[2]


class HandlerPrivacyTests(unittest.TestCase):
    def setUp(self):
        os.environ["ENVIRONMENT"] = "test"

    def test_unhandled_error_logs_safe_summary_without_traceback(self):
        from routes import profile as profile_routes

        original = profile_routes.handle_get_me

        def explode(_user_id):
            raise KeyError("dynamodb-table-forge-prod-appdata quoted-body")

        profile_routes.handle_get_me = explode
        try:
            with self.assertLogs("forge.handler", level="ERROR") as logs:
                response = handler(event("GET", "/me", user_id="auth-user-123"), None)
        finally:
            profile_routes.handle_get_me = original

        self.assertEqual(response["statusCode"], 500)
        joined = "\n".join(logs.output)
        self.assertNotIn("Traceback", joined)
        self.assertNotIn("File ", joined)
        self.assertIn("KeyError", joined)
        self.assertTrue(any("dynamodb" in line for line in logs.output))


class RouterHealthLeakTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        self.addCleanup(os.environ.pop, "ARIA_BEDROCK_ENABLED", None)

    def test_ai_router_inspects_health_payload_before_bedrock(self):
        order: list[str] = []
        real_inspect = __import__("services.health_leak_guard", fromlist=["inspect_request"]).inspect_request

        def inspect(*args, **kwargs):
            order.append("inspect")
            return real_inspect(*args, **kwargs)

        def route(_self, _request):
            order.append("route")
            return {"finalAnswer": "ok"}

        with patch("services.health_leak_guard.inspect_request", side_effect=inspect), patch(
            "ai_router.AIRouter.route", new=route
        ):
            response = handler(
                event(
                    "POST",
                    "/ai/router",
                    {"question": "summarize my data", "hrv": 188},
                    user_id="leak-router-user",
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(order[:2], ["inspect", "route"])
        audits = dynamodb.query_prefix("LEAK#AUDIT", "EVENT#")
        self.assertTrue(audits)
        self.assertTrue(any("ingress:POST:/ai/router" in str(item.get("reason")) for item in audits))


class CoachObservabilityTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        self.addCleanup(coach_routes.set_router_invoker, None)

    def test_coach_failure_logs_and_still_returns_fallback(self):
        def failing(_payload):
            raise RuntimeError("bedrock unavailable")

        coach_routes.set_router_invoker(failing)
        with self.assertLogs("forge.coach", level="ERROR") as logs:
            response = handler(event("POST", "/coach/sleep-insight", {}), None)
        payload = body(response)
        self.assertTrue(payload["fallback"])
        self.assertTrue(any("coach_route_failed" in line for line in logs.output))
        self.assertTrue(any("RuntimeError" in line for line in logs.output))

    def test_coach_routes_share_per_user_rate_limit(self):
        uid = "coach-rate-user"
        for _ in range(60):
            coach_routes._enforce_coach_rate_limit(uid)
        with self.assertRaises(RouteError) as raised:
            coach_routes._enforce_coach_rate_limit(uid)
        self.assertEqual(raised.exception.status_code, 429)


class WorkoutPlanOverwriteGuardTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["FORGE_DEMO_DATA"] = "false"
        coach_routes.set_router_invoker(lambda payload: {"finalAnswer": "ok"})
        self.addCleanup(coach_routes.set_router_invoker, None)
        self.addCleanup(lambda: os.environ.pop("FORGE_DEMO_DATA", None))

    def test_existing_plan_exercises_are_not_wiped(self):
        uid = "bh04-plan-guard"
        day = today_iso()
        dynamodb.put_item(
            {
                **keys.workout_log_key(uid, "2026-10-01T10:00:00Z"),
                "type": "strength",
                "duration": 45,
            }
        )
        existing_exercises = [{"name": "Squat", "sets": 3, "reps": "5"}]
        dynamodb.put_item(
            {
                **keys.workout_plan_key(uid, day),
                "id": "plan-keep",
                "date": day,
                "name": "Keep Me",
                "exercises": existing_exercises,
            }
        )
        posted = json.loads(coach_routes.handle_post_coach_workout_plan(uid, {})["body"])
        stored = dynamodb.get_item(**keys.workout_plan_key(uid, day))
        self.assertEqual(stored["exercises"], existing_exercises)
        self.assertEqual(stored["id"], "plan-keep")
        self.assertEqual(posted["todayPlan"]["exercises"], existing_exercises)


class IntegrationSyncHonestyTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        os.environ.pop("FORGE_TEST_USER_ID", None)

    def test_sync_finishes_in_a_terminal_state(self):
        response = handler(event("POST", "/integrations/oura/sync", {}), None)
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["provider"], "oura")
        self.assertEqual(payload["status"], "error")
        self.assertNotEqual(payload["status"], "queued")
        stored = dynamodb.get_item(**keys.connection_key("test-user-00000000", "oura"))
        self.assertEqual(stored["status"], "error")
        self.assertEqual(stored["lastSyncResult"], "not_implemented")
        self.assertNotEqual(stored["status"], "syncing")


class ChatProgressIntentTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["FORGE_DEMO_DATA"] = "false"
        self.addCleanup(lambda: os.environ.pop("FORGE_DEMO_DATA", None))

    def _reply(self, text: str) -> dict:
        from routes.chat import _trainer_response

        return _trainer_response("bh07-user", text)

    def test_false_positive_substrings_do_not_hit_progress(self):
        for text in ("improve recovery", "more protein please", "sprint workout plan", "approach the bar"):
            reply = self._reply(text)
            self.assertNotIn("no logged sessions", reply["content"], text)
            self.assertNotIn("progress to compare", reply["content"], text)

    def test_real_progress_intent_still_hits_progress(self):
        reply = self._reply("Show me my progress")
        self.assertIn("no logged sessions", reply["content"])
        pr_reply = self._reply("any new PR today?")
        self.assertIn("no logged sessions", pr_reply["content"])


class WebIngestDeadlineTests(unittest.TestCase):
    def test_read_capped_honors_fetch_deadline(self):
        class SlowResp:
            def read(self, _n):
                time.sleep(0.05)
                return b"x" * 16

        with self.assertRaises(RouteError) as raised:
            web_ingest._read_capped(SlowResp(), 512 * 1024, deadline=time.monotonic() + 0.01)
        self.assertEqual(raised.exception.status_code, 504)
        self.assertEqual(raised.exception.code, "upstream_unavailable")

    def test_default_resolver_honors_timeout(self):
        def hang(_host, *_a, **_k):
            time.sleep(2)
            return []

        with patch("services.web_ingest.socket.getaddrinfo", side_effect=hang):
            with self.assertRaises(TimeoutError):
                web_ingest._default_resolver("example.com", timeout=0.05)


class HealthKitObserverSourceTests(unittest.TestCase):
    """Would fail on 08e2eae4: completion() ran before the refresh Task."""

    def test_ios_observer_uses_gate_not_completion_before_work(self):
        text = (REPO / "ForgeSwift" / "ForgeSwift" / "HealthKitManager.swift").read_text()
        self.assertIn("HealthKitObserverGate.run", text)
        self.assertIn("performObserverRefresh", text)
        self.assertIn("recordBackgroundDeliveryFailure", text)
        self.assertNotRegex(
            text,
            r"scheduleLiveRefresh\(\)\s*\}\s*\n\s*completion\(\)",
        )

    def test_watch_observer_uses_gate_not_completion_before_work(self):
        text = (
            REPO / "ForgeSwift" / "ForgeWatch" / "Managers" / "WatchHealthKitManager.swift"
        ).read_text()
        self.assertIn("HealthKitObserverGate.run", text)
        self.assertIn("performObserverRefresh", text)
        self.assertIn("recordBackgroundDeliveryFailure", text)
        self.assertNotRegex(
            text,
            r"scheduleLiveRefresh\(\)\s*\}\s*\n\s*completion\(\)",
        )


class PutItemConditionTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_attribute_not_exists_sk_blocks_overwrite(self):
        item = {"pk": "USER#cond", "sk": "PLAN#today", "exercises": [1]}
        dynamodb.put_item(item)
        with self.assertRaises(dynamodb.ConditionalCheckFailed):
            dynamodb.put_item(
                {"pk": "USER#cond", "sk": "PLAN#today", "exercises": []},
                condition_expression="attribute_not_exists(sk)",
            )
        self.assertEqual(dynamodb.get_item("USER#cond", "PLAN#today")["exercises"], [1])


if __name__ == "__main__":
    unittest.main()
