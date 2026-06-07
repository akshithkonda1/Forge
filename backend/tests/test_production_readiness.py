import json
import os
import unittest
from unittest import mock

from _support import ensure_api_on_path

ensure_api_on_path()

from core.auth import extract_user_id  # noqa: E402
from handler import handler  # noqa: E402
from core.production_health import collect_readiness_checks, health_status  # noqa: E402
from core.responses import RouteError  # noqa: E402
from core.runtime import allow_seed_fallback  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402


def event(method, path, body=None, query=None, *, sub=None):
    payload = {
        "requestContext": {
            "http": {
                "method": method,
                "path": path,
            },
            "authorizer": {
                "jwt": {
                    "claims": {"sub": sub} if sub else {},
                }
            },
        },
        "queryStringParameters": query or {},
    }
    if body is not None:
        payload["body"] = json.dumps(body)
    return payload


def body(response):
    return json.loads(response["body"])


class ProductionReadinessTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        self._env = mock.patch.dict(
            os.environ,
            {
                "ENVIRONMENT": "production",
                "APP_DATA_TABLE_NAME": "forge-prod-data",
                "AI_PROVIDER_SECRET_ARN": "arn:aws:secretsmanager:us-east-1:123:secret:ai",
                "TERRA_SECRET_ARN": "arn:aws:secretsmanager:us-east-1:123:secret:terra",
                "FORGE_ALLOW_SEED_FALLBACK": "",
                "FORGE_TEST_USER_ID": "",
            },
            clear=False,
        )
        self._env.start()
        self.addCleanup(self._env.stop)

    def test_allow_seed_fallback_disabled_with_dynamodb(self):
        self.assertFalse(allow_seed_fallback())

    def test_extract_user_id_requires_auth_in_production(self):
        with self.assertRaises(RouteError) as ctx:
            extract_user_id(event("GET", "/me"))
        self.assertEqual(ctx.exception.status_code, 401)

    def test_extract_user_id_accepts_authorizer_sub(self):
        user_id = extract_user_id(event("GET", "/me", sub="user-prod-123"))
        self.assertEqual(user_id, "user-prod-123")

    def test_dashboard_returns_empty_state_without_seed(self):
        response = handler(event("GET", "/dashboard/today", sub="user-prod-123"), None)

        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["profile"]["name"], "")
        self.assertEqual(payload["readiness"]["overall"], 0)
        self.assertEqual(payload["recentSleep"], [])
        self.assertEqual(payload["personalRecords"], [])

    def test_health_reports_degraded_until_fully_production_ready(self):
        with mock.patch("core.production_health.terra_config.is_configured", return_value=True):
            checks = collect_readiness_checks()
        self.assertFalse(checks["seedFallbackEnabled"])
        self.assertTrue(checks["authEnforced"])
        self.assertEqual(checks["dataStore"], "dynamodb")
        self.assertTrue(checks["productionReady"])
        self.assertEqual(health_status(checks), "ok")

    def test_health_includes_self_healing_summary(self):
        response = handler(event("GET", "/health"), None)

        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertIn(payload["status"], {"ok", "degraded"})
        self.assertIn("readiness", payload)
        self.assertIn("selfHealing", payload)
        self.assertTrue(payload["selfHealing"]["apiHealthProbe"])


if __name__ == "__main__":
    unittest.main()