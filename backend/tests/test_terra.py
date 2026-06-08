import hashlib
import hmac
import json
import os
import time
import unittest
from unittest.mock import patch

from _support import ensure_api_on_path

ensure_api_on_path()

from handler import handler  # noqa: E402
from integrations import terra_config, terra_webhooks  # noqa: E402
from storage import dynamodb  # noqa: E402


def _terra_signature(raw_body: str, secret: str) -> str:
    timestamp = str(int(time.time()))
    signed_payload = f"{timestamp}.{raw_body}"
    digest = hmac.new(
        secret.encode("utf-8"),
        signed_payload.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"t={timestamp},v1={digest}"


def _webhook_event(raw_body: str, signature: str):
    return {
        "requestContext": {"http": {"method": "POST", "path": "/integrations/terra/webhook"}},
        "headers": {"terra-signature": signature},
        "body": raw_body,
    }


class TerraIntegrationTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        terra_config._load_secret.cache_clear()
        self._env = {
            "TERRA_DEV_ID": os.environ.pop("TERRA_DEV_ID", None),
            "TERRA_API_KEY": os.environ.pop("TERRA_API_KEY", None),
            "TERRA_WEBHOOK_SECRET": os.environ.pop("TERRA_WEBHOOK_SECRET", None),
            "TERRA_SECRET_ARN": os.environ.pop("TERRA_SECRET_ARN", None),
        }

    def tearDown(self):
        for key, value in self._env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        terra_config._load_secret.cache_clear()

    def test_verify_signature_accepts_valid_header(self):
        body = '{"type":"daily"}'
        secret = "terra-test-secret"
        signature = _terra_signature(body, secret)

        terra_webhooks.verify_signature(
            raw_body=body,
            signature_header=signature,
            signing_secret=secret,
        )

    def test_verify_signature_rejects_invalid_header(self):
        with self.assertRaises(terra_webhooks.WebhookVerificationError):
            terra_webhooks.verify_signature(
                raw_body='{"type":"daily"}',
                signature_header="t=1,v1=bad",
                signing_secret="terra-test-secret",
            )

    def test_auth_webhook_links_user_and_connection(self):
        os.environ["TERRA_WEBHOOK_SECRET"] = "terra-test-secret"
        terra_config._load_secret.cache_clear()

        user_id = "test-user-00000000"
        dynamodb.put_item(
            {
                "pk": f"REF#{user_id}",
                "sk": "USER",
                "userId": user_id,
            }
        )

        payload = {
            "type": "auth",
            "user": {
                "reference_id": user_id,
                "user_id": "terra-user-123",
                "provider": "OURA",
            },
        }
        raw_body = json.dumps(payload)
        response = handler(_webhook_event(raw_body, _terra_signature(raw_body, "terra-test-secret")), None)

        self.assertEqual(response["statusCode"], 200)
        result = json.loads(response["body"])
        self.assertTrue(result["handled"])
        self.assertEqual(result["provider"], "OURA")

        connection = dynamodb.get_item(pk=f"USER#{user_id}", sk="CONNECTION#oura")
        self.assertIsNotNone(connection)
        self.assertEqual(connection["status"], "connected")
        self.assertEqual(connection["middleware"], "terra")

    def test_sleep_webhook_persists_normalized_session(self):
        os.environ["TERRA_WEBHOOK_SECRET"] = "terra-test-secret"
        terra_config._load_secret.cache_clear()

        user_id = "test-user-00000000"
        dynamodb.put_item(
            {
                "pk": "TERRA#USER#terra-user-456",
                "sk": "MAPPING",
                "userId": user_id,
            }
        )

        payload = {
            "type": "sleep",
            "user": {"user_id": "terra-user-456", "provider": "OURA"},
            "data": [
                {
                    "metadata": {"start_time": "2026-06-01T00:00:00Z", "end_time": "2026-06-01T08:00:00Z"},
                    "sleep_durations_data": {
                        "asleep": {
                            "duration_asleep_state_seconds": 25200,
                            "duration_deep_sleep_state_seconds": 5400,
                            "duration_REM_sleep_state_seconds": 3600,
                            "duration_light_sleep_state_seconds": 16200,
                        },
                        "awake": {"duration_awake_state_seconds": 1800},
                        "other": {"duration_in_bed_seconds": 27000},
                    },
                    "sleep_score": 88,
                }
            ],
        }
        raw_body = json.dumps(payload)
        response = handler(_webhook_event(raw_body, _terra_signature(raw_body, "terra-test-secret")), None)

        self.assertEqual(response["statusCode"], 200)
        sleep_item = dynamodb.get_item(pk=f"USER#{user_id}", sk="SLEEP#2026-06-01#oura")
        self.assertIsNotNone(sleep_item)
        self.assertEqual(sleep_item["score"], 88)
        self.assertEqual(sleep_item["middleware"], "terra")

    def test_widget_returns_503_when_not_configured(self):
        response = handler(
            {
                "requestContext": {"http": {"method": "POST", "path": "/integrations/terra/widget"}},
                "body": json.dumps(
                    {
                        "successRedirectUrl": "https://app.example/success",
                        "failureRedirectUrl": "https://app.example/failure",
                    }
                ),
            },
            None,
        )

        self.assertEqual(response["statusCode"], 503)
        self.assertEqual(json.loads(response["body"])["code"], "terra_not_configured")

    @patch("integrations.terra_client._request")
    def test_widget_returns_session_when_configured(self, mock_request):
        os.environ["TERRA_DEV_ID"] = "dev-id"
        os.environ["TERRA_API_KEY"] = "api-key"
        terra_config._load_secret.cache_clear()
        mock_request.return_value = {
            "session_id": "sess-1",
            "url": "https://widget.tryterra.co/session/sess-1",
            "expires_at": "2026-06-05T12:00:00Z",
        }

        response = handler(
            {
                "requestContext": {"http": {"method": "POST", "path": "/integrations/terra/widget"}},
                "body": json.dumps(
                    {
                        "successRedirectUrl": "https://app.example/success",
                        "failureRedirectUrl": "https://app.example/failure",
                    }
                ),
            },
            None,
        )

        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertEqual(payload["sessionId"], "sess-1")
        self.assertIn("widget.tryterra.co", payload["url"])

    def test_status_reports_connection_state(self):
        user_id = "test-user-00000000"
        dynamodb.put_item(
            {
                **{"pk": f"USER#{user_id}", "sk": "TERRA#REF"},
                "terraUserId": "terra-user-789",
                "provider": "GARMIN",
                "updatedAt": "2026-06-05T00:00:00Z",
            }
        )

        response = handler(
            {"requestContext": {"http": {"method": "GET", "path": "/integrations/terra/status"}}},
            None,
        )

        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertTrue(payload["connected"])
        self.assertEqual(payload["provider"], "GARMIN")
        self.assertNotIn("terraUserId", payload)
        self.assertNotIn("middleware", payload)


if __name__ == "__main__":
    unittest.main()