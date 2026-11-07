"""Health leak gate: canaries never persist; destroy stays dry-run."""

from __future__ import annotations

import json
import os
import unittest

import _bootstrap  # noqa: F401

from handler import handler
from services import health_leak_guard
from storage import dynamodb, keys


def _event(method, path, body, user="leak-user"):
    return {
        "requestContext": {
            "http": {"method": method, "path": path},
            "authorizer": {"jwt": {"claims": {"sub": user}}},
        },
        "body": json.dumps(body),
    }


class HealthLeakGateTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        for key in (
            "FORGE_HEALTH_LEAK_DESTROY",
            "FORGE_HEALTH_LEAK_QUARANTINE",
            "FORGE_HEALTH_LEAK_APPLY",
            "FORGE_HEALTH_LEAK_AUTO_BLOCK",
            "FORGE_HEALTH_QUARANTINE_BLOCK",
        ):
            os.environ.pop(key, None)

    def test_flags_default_off(self):
        self.assertFalse(health_leak_guard.destroy_enabled())
        self.assertFalse(health_leak_guard.quarantine_enabled())
        self.assertFalse(health_leak_guard.apply_live_aws())
        self.assertFalse(health_leak_guard.auto_block_enabled())

    def test_observe_canary_is_not_stored(self):
        resp = handler(
            _event(
                "POST",
                "/ai/observe",
                {"samples": [{"type": "hrv", "value": 188, "unit": "ms"}]},
            ),
            None,
        )
        self.assertEqual(resp["statusCode"], 200)
        self.assertEqual(dynamodb.query_prefix(keys.user_pk("leak-user"), "METRIC#"), [])
        self.assertIsNone(dynamodb.get_item(**keys.aria_body_snapshot_key("leak-user")))

    def test_planted_store_row_is_detected_and_destroy_stays_dry_run(self):
        dynamodb.put_item(
            {
                **keys.metric_key("leak-user", "hrv", "2026-10-24T00:00:00Z"),
                "metricType": "hrv",
                "value": 188,
            }
        )
        reports = health_leak_guard.scan_local_store()
        self.assertTrue(reports)
        self.assertTrue(reports[0]["dry_run"])
        self.assertFalse(reports[0]["destroyed"])
        # Dry-run leaves the row; APPLY is off.
        self.assertTrue(dynamodb.query_prefix(keys.user_pk("leak-user"), "METRIC#"))
        audits = dynamodb.query_prefix(health_leak_guard.AUDIT_PK, "EVENT#")
        self.assertTrue(audits)
        self.assertIsNone(audits[0].get("values"))
        blob = json.dumps(audits[0])
        self.assertNotIn("188", blob)

    def test_destroy_in_test_mode_deletes_local_only_when_flagged(self):
        os.environ["FORGE_HEALTH_LEAK_DESTROY"] = "1"
        os.environ["FORGE_HEALTH_LEAK_APPLY"] = "1"
        dynamodb.put_item(
            {
                **keys.metric_key("leak-user", "hrv", "2026-10-24T00:00:00Z"),
                "metricType": "hrv",
                "value": 188,
            }
        )
        reports = health_leak_guard.scan_local_store()
        self.assertTrue(reports[0]["destroyed"])
        self.assertEqual(dynamodb.query_prefix(keys.user_pk("leak-user"), "METRIC#"), [])

    def test_auto_block_refuses_later_writes(self):
        os.environ["FORGE_HEALTH_LEAK_AUTO_BLOCK"] = "1"
        health_leak_guard.handle_finding(None, ["samples"], reason="test")
        self.assertTrue(health_leak_guard.writes_blocked())
        resp = handler(
            _event("POST", "/ai/chat", {"message": "hi"}),
            None,
        )
        self.assertEqual(resp["statusCode"], 423)
        self.assertIn("quarantine", json.loads(resp["body"])["message"].lower())

    def test_deploy_gate_fails_while_blocked(self):
        os.environ["FORGE_HEALTH_QUARANTINE_BLOCK"] = "1"
        with self.assertRaises(SystemExit):
            health_leak_guard.deploy_gate()

    def test_form_check_rejects_a_frame(self):
        resp = handler(
            _event(
                "POST",
                "/workouts/form-check",
                {
                    "mode": "vision",
                    "context": {"exerciseName": "Squat"},
                    "image_base64": "aaaa",
                },
            ),
            None,
        )
        self.assertIn(resp["statusCode"], (400, 451))
        self.assertIn("on device", json.loads(resp["body"])["message"].lower())
