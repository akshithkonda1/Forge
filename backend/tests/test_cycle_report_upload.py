import json
import os
import unittest
from datetime import datetime, timezone

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from responses import RouteError  # noqa: E402
from routes import cycle as cycle_routes  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402
from test_backend_handler import body, event  # noqa: E402


class FakeS3:
    def __init__(self):
        self.calls = []

    def generate_presigned_url(self, ClientMethod, Params, ExpiresIn):
        self.calls.append((ClientMethod, Params, ExpiresIn))
        key = Params["Key"]
        return f"https://uploads.test/{key}?{ClientMethod}={ExpiresIn}"


class CycleReportUploadTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        os.environ["UPLOADS_BUCKET_NAME"] = "forge-uploads-test"

    def test_mints_expiring_urls_without_dynamo(self):
        fake = FakeS3()
        now = datetime(2026, 9, 5, 12, 0, tzinfo=timezone.utc)
        response = cycle_routes.handle_post_cycle_report_upload(
            "user-abc",
            {"contentType": "application/pdf", "byteLength": 12_000, "windowMonths": 12},
            s3_client=fake,
            bucket_name="forge-uploads-test",
            now=now,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = json.loads(response["body"])
        self.assertTrue(payload["objectKey"].startswith("cycle-reports/user-abc/"))
        self.assertTrue(payload["objectKey"].endswith(".pdf"))
        self.assertEqual(payload["expiresAt"], "2026-09-06T12:00:00Z")
        self.assertEqual(payload["expiresInSeconds"], 24 * 60 * 60)
        methods = [c[0] for c in fake.calls]
        self.assertEqual(methods, ["put_object", "get_object"])
        self.assertEqual(dynamodb_store._local_store, {})

    def test_rejects_non_pdf_and_oversize(self):
        fake = FakeS3()
        with self.assertRaises(RouteError) as too_wide:
            cycle_routes.handle_post_cycle_report_upload(
                "user-abc",
                {"contentType": "text/plain", "byteLength": 100},
                s3_client=fake,
            )
        self.assertEqual(too_wide.exception.status_code, 400)
        with self.assertRaises(RouteError) as huge:
            cycle_routes.handle_post_cycle_report_upload(
                "user-abc",
                {"contentType": "application/pdf", "byteLength": 9_000_000},
                s3_client=fake,
            )
        self.assertEqual(huge.exception.status_code, 400)

    def test_handler_route_is_authenticated(self):
        # Anonymous test principal is allowed in this env, but the path must exist.
        os.environ["UPLOADS_BUCKET_NAME"] = ""
        response = handler(
            event("POST", "/cycle/report-upload", {"contentType": "application/pdf", "byteLength": 100}),
            None,
        )
        self.assertEqual(response["statusCode"], 503)
        self.assertEqual(body(response)["code"], "uploads_unconfigured")
        self.assertEqual(dynamodb_store._local_store, {})


if __name__ == "__main__":
    unittest.main()
