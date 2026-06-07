import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
import sys

sys.path.insert(0, str(SCRIPTS))

from generate_client_config import generate, validate_config  # noqa: E402

EXAMPLE_CONFIG = {
    "apiBaseUrl": "https://example.execute-api.us-east-1.amazonaws.com",
    "cognito": {
        "region": "us-east-1",
        "userPoolId": "us-east-1_EXAMPLE",
        "webClientId": "example-web-client-id",
        "iosClientId": "example-ios-client-id",
        "identityPoolId": "us-east-1:example-identity-pool",
    },
    "storage": {
        "uploadsBucket": "forge-uploads-example",
        "accessLevel": "private",
        "keyPrefixPattern": "private/{identityId}/",
    },
}


class ClientConfigGeneratorTests(unittest.TestCase):
    def test_validate_config_normalizes_api_url(self):
        payload = dict(EXAMPLE_CONFIG)
        payload["apiBaseUrl"] = "https://example.execute-api.us-east-1.amazonaws.com/"
        normalized = validate_config(payload)
        self.assertEqual(
            normalized["apiBaseUrl"],
            "https://example.execute-api.us-east-1.amazonaws.com",
        )

    def test_validate_config_rejects_localhost(self):
        payload = dict(EXAMPLE_CONFIG)
        payload["apiBaseUrl"] = "http://127.0.0.1:3001"
        with self.assertRaises(ValueError):
            validate_config(payload)

    def test_validate_config_requires_cognito_fields(self):
        payload = dict(EXAMPLE_CONFIG)
        payload["cognito"] = {"region": "us-east-1"}
        with self.assertRaises(ValueError):
            validate_config(payload)

    def test_generate_writes_web_and_ios_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            input_path = Path(tmp) / "client-configuration.json"
            web_output = Path(tmp) / "web.env"
            ios_output = Path(tmp) / "ios.xcconfig"
            input_path.write_text(json.dumps(EXAMPLE_CONFIG), encoding="utf-8")

            outputs = generate(
                input_path,
                web_output=web_output,
                ios_output=ios_output,
                write=True,
            )

            self.assertTrue(web_output.is_file())
            self.assertTrue(ios_output.is_file())

            web_text = web_output.read_text(encoding="utf-8")
            ios_text = ios_output.read_text(encoding="utf-8")

            self.assertIn(
                "NEXT_PUBLIC_API_URL=https://example.execute-api.us-east-1.amazonaws.com",
                web_text,
            )
            self.assertIn("NEXT_PUBLIC_COGNITO_CLIENT_ID=example-web-client-id", web_text)
            self.assertIn(
                "NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-1_EXAMPLE",
                web_text,
            )
            self.assertIn(
                "NEXT_PUBLIC_COGNITO_IDENTITY_POOL_ID=us-east-1:example-identity-pool",
                web_text,
            )

            self.assertIn("FORGE_API_BASE_URL = https:", ios_text)
            self.assertIn("example.execute-api.us-east-1.amazonaws.com", ios_text)
            self.assertIn("FORGE_COGNITO_CLIENT_ID = example-ios-client-id", ios_text)
            self.assertIn("FORGE_USE_AUTH = true", ios_text)

            self.assertEqual(outputs["web"], web_text)
            self.assertEqual(outputs["ios"], ios_text)

    def test_example_json_matches_generator(self):
        example_path = ROOT / "client-configuration.example.json"
        example = json.loads(example_path.read_text(encoding="utf-8"))
        normalized = validate_config(example)
        self.assertEqual(
            normalized["cognito"]["iosClientId"],
            example["cognito"]["iosClientId"],
        )


if __name__ == "__main__":
    unittest.main()