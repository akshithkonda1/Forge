import json
import os
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from _support import ensure_api_on_path

ensure_api_on_path()

from handler import handler  # noqa: E402
from integrations import terra_config, terra_self_healing, terra_self_integration  # noqa: E402
from storage import dynamodb, keys  # noqa: E402


class TerraSelfHealingTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        terra_config.clear_cache()
        self._token = os.environ.get("OPS_SELF_HEAL_TOKEN")
        os.environ["OPS_SELF_HEAL_TOKEN"] = "test-ops-token"

    def tearDown(self):
        if self._token is None:
            os.environ.pop("OPS_SELF_HEAL_TOKEN", None)
        else:
            os.environ["OPS_SELF_HEAL_TOKEN"] = self._token
        terra_config.clear_cache()

    def test_bootstrap_persists_integration_state(self):
        with patch("integrations.terra_client.ping_api", return_value={"ok": True, "message": "ok"}):
            os.environ["TERRA_DEV_ID"] = "dev"
            os.environ["TERRA_API_KEY"] = "key"
            os.environ["TERRA_WEBHOOK_SECRET"] = "secret"
            terra_config.clear_cache()

            result = terra_self_integration.bootstrap()

        self.assertEqual(result["status"], "ready")
        stored = dynamodb.get_item(**keys.terra_system_key())
        self.assertIsNotNone(stored)
        self.assertTrue(stored["apiReachable"])

    def test_auth_webhook_triggers_backfill(self):
        os.environ["TERRA_WEBHOOK_SECRET"] = "terra-test-secret"
        terra_config.clear_cache()

        user_id = "test-user-00000000"
        dynamodb.put_item({"pk": f"REF#{user_id}", "sk": "USER", "userId": user_id})
        dynamodb.put_item(
            {
                **keys.terra_ref_key(user_id),
                "terraUserId": "terra-user-999",
                "provider": "OURA",
            }
        )

        payload = {
            "type": "auth",
            "user": {
                "reference_id": user_id,
                "user_id": "terra-user-999",
                "provider": "OURA",
            },
        }
        raw_body = json.dumps(payload)

        with patch("integrations.terra_client.is_configured", return_value=True):
            with patch("integrations.terra_client.request_historical_data", return_value={"status": "queued"}):
                from integrations.terra_webhooks import handle_webhook_event

                result = handle_webhook_event(raw_body)

        self.assertTrue(result["handled"])
        self.assertTrue(result["backfill"]["queued"])
        connection = dynamodb.get_item(pk=f"USER#{user_id}", sk="CONNECTION#oura")
        self.assertEqual(connection["status"], "syncing")

    def test_heal_requeues_stale_connection(self):
        user_id = "test-user-00000000"
        stale_time = (datetime.now(timezone.utc) - timedelta(hours=48)).isoformat()
        dynamodb.put_item({**keys.terra_ref_key(user_id), "terraUserId": "terra-1", "provider": "OURA"})
        dynamodb.put_item(
            {
                **keys.connection_key(user_id, "oura"),
                "provider": "oura",
                "displayName": "Oura Ring",
                "status": "connected",
                "lastSyncedAt": stale_time,
                "middleware": "terra",
            }
        )

        with patch("integrations.terra_client.is_configured", return_value=True):
            with patch("integrations.terra_client.request_historical_data", return_value={"status": "queued"}):
                summary = terra_self_healing.heal(max_repairs=5)

        self.assertEqual(summary["repairedCount"], 1)
        self.assertEqual(summary["assessment"]["staleConnections"], 1)

    def test_self_heal_endpoint_requires_ops_token(self):
        response = handler(
            {
                "requestContext": {"http": {"method": "POST", "path": "/integrations/terra/self-heal"}},
                "body": "{}",
            },
            None,
        )
        self.assertEqual(response["statusCode"], 401)

    def test_scheduled_self_heal_event(self):
        with patch("integrations.terra_self_healing.heal", return_value={"assessment": {"healthy": 1.0}, "repairedCount": 0, "failureCount": 0, "healedAt": "now"}):
            response = handler({"forgeAction": "terra-self-heal"}, None)

        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["source"], "scheduled")


if __name__ == "__main__":
    unittest.main()