"""Zero-leakage TTS sanitizer — canaries never leave toward a voice API."""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from services import tts_privacy  # noqa: E402


class TTSPrivacyTests(unittest.TestCase):
    def test_qualitative_coaching_is_safe(self):
        cleaned = tts_privacy.sanitize_tts_text(
            "I'm ARIA. Let's look at how you actually slept and what that means for training today."
        )
        self.assertTrue(cleaned.can_send_to_cloud)
        self.assertIn("ARIA", cleaned.text)

    def test_canary_name_email_and_health_values_are_blocked(self):
        line = (
            f"{tts_privacy.CANARY_NAME} ({tts_privacy.CANARY_EMAIL}, "
            f"{tts_privacy.CANARY_PHONE}) {tts_privacy.CANARY_HRV}, "
            f"{tts_privacy.CANARY_READINESS}, {tts_privacy.CANARY_SLEEP_HOURS}, "
            f"{tts_privacy.CANARY_HEART_RATE}."
        )
        cleaned = tts_privacy.sanitize_tts_text(
            line, names=[tts_privacy.CANARY_NAME]
        )
        self.assertFalse(cleaned.safe)
        self.assertEqual(cleaned.reason, "privacy")
        blob = cleaned.text
        for canary in (
            tts_privacy.CANARY_NAME,
            tts_privacy.CANARY_EMAIL,
            tts_privacy.CANARY_PHONE,
            "HRV 32",
            "readiness 88",
            "6.5 hours of sleep",
            "142 bpm",
        ):
            self.assertNotIn(canary, blob)

    def test_assert_cloud_payload_refuses_canaries(self):
        with self.assertRaises(ValueError):
            tts_privacy.assert_cloud_payload_is_clean(
                "https://api.fish.audio/v1/tts",
                {"Authorization": "Bearer x", "model": "s2.1-pro-free"},
                f"Hello {tts_privacy.CANARY_NAME}",
                names=[tts_privacy.CANARY_NAME],
            )
        tts_privacy.assert_cloud_payload_is_clean(
            "https://api.fish.audio/v1/tts",
            {"model": "s2.1-pro-free"},
            "I'm ARIA.",
        )


if __name__ == "__main__":
    unittest.main()
