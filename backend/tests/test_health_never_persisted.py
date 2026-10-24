"""Health payloads are not accepted or written. On-device BodyModel owns them."""

from __future__ import annotations

import json
import os
import unittest
from datetime import datetime, timezone

import _bootstrap  # noqa: F401

from handler import handler
from storage import dynamodb, keys


def _event(method, path, body, user="health-lock-user"):
    return {
        "requestContext": {
            "http": {"method": method, "path": path},
            "authorizer": {"jwt": {"claims": {"sub": user}}},
        },
        "body": json.dumps(body),
    }


class HealthNeverPersistedTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"

    def _post(self, path, body, user="health-lock-user"):
        resp = handler(_event("POST", path, body, user), None)
        return resp["statusCode"], json.loads(resp["body"])

    def test_observe_rejects_health_samples_and_writes_nothing(self):
        uid = "observe-no-store"
        status, payload = self._post(
            "/ai/observe",
            {
                "user_id": uid,
                "samples": [
                    {
                        "type": "hrv",
                        "value": 188,
                        "unit": "ms",
                        "source": "apple-health",
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    }
                ],
            },
            user=uid,
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["classification"]["accepted"], 0)
        self.assertGreaterEqual(payload["classification"]["rejected"], 1)
        self.assertEqual(payload["snapshot"], {})
        self.assertTrue(payload["notice"].startswith("Health data always stays on device"))
        self.assertIsNone(dynamodb.get_item(**keys.aria_body_snapshot_key(uid)))
        self.assertEqual(dynamodb.query_prefix(keys.user_pk(uid), "METRIC#"), [])

    def test_observe_ignores_vitals_and_does_not_audit(self):
        uid = "vitals-no-store"
        status, payload = self._post(
            "/ai/observe",
            {
                "user_id": uid,
                "vitals": [
                    {"spo2": 0.0, "heart_rate": 0, "sensor_contact": True},
                    {"spo2": 0.0, "heart_rate": 0, "sensor_contact": True},
                    {"spo2": 0.0, "heart_rate": 0, "sensor_contact": True},
                ],
                "session_active": True,
            },
            user=uid,
        )
        self.assertEqual(status, 200)
        self.assertNotIn("emergency", payload)
        self.assertEqual(dynamodb.query_prefix(keys.user_pk(uid), "EMERGENCY#"), [])
        self.assertEqual(dynamodb.query_prefix(keys.user_pk(uid), "METRIC#"), [])

    def test_health_batch_rejects_and_writes_nothing(self):
        uid = "batch-no-store"
        status, payload = self._post(
            "/health/batch",
            {
                "metrics": [
                    {
                        "source": "apple-health",
                        "metricType": "hrv",
                        "startedAt": "2026-05-06T08:00:00+00:00",
                        "value": 188,
                        "unit": "ms",
                    },
                    {
                        "source": "apple-health",
                        "metricType": "body-weight",
                        "startedAt": "2026-05-06T08:00:00+00:00",
                        "value": 99.3,
                        "unit": "kg",
                    },
                ]
            },
            user=uid,
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["accepted"], 0)
        self.assertEqual(payload["rejected"], 2)
        self.assertEqual(dynamodb.query_prefix(keys.user_pk(uid), "METRIC#"), [])
        for err in payload["errors"]:
            self.assertIn("Health data always stays on device", err["message"])
