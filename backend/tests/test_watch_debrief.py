import json
import sys
import unittest
from pathlib import Path

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from services import watch_debrief  # noqa: E402


def event(method, path, body=None):
    payload = {
        "requestContext": {"http": {"method": method, "path": path}},
        "queryStringParameters": {},
    }
    if body is not None:
        payload["body"] = json.dumps(body)
    return payload


def response_body(response):
    return json.loads(response["body"])


_BANNED_PHRASES = (
    "should have", "failed", "lazy", "guilt", "no excuses", "missed your",
)


def _sentence_count(message: str) -> int:
    return len([s for s in message.replace("!", ".").replace("?", ".").split(".") if s.strip()])


class WatchDebriefEngineTests(unittest.TestCase):
    """Unit tests directly on the deterministic engine (no HTTP)."""

    def _context(self, **overrides):
        base = {
            "readinessOverall": 75,
            "readinessConfidence": 0.9,
            "lifestyleMode": None,
            "sleepFactors": [],
            "hoursSinceLastWorkout": None,
        }
        base.update(overrides)
        return base

    def test_post_workout_body_scan_wins_priority(self):
        result = watch_debrief.generate_debrief(
            self._context(lifestyleMode="deskCoding", hoursSinceLastWorkout=0.25),
            "bodyScan", 5.0, None,
        )
        self.assertEqual(result["trigger"], "post-workout-debrief")

    def test_desk_mode_debrief_when_not_post_workout(self):
        result = watch_debrief.generate_debrief(
            self._context(lifestyleMode="deepFocus"), "focusReset", 1.5, None,
        )
        self.assertEqual(result["trigger"], "desk-block-debrief")

    def test_recovery_band_debrief(self):
        result = watch_debrief.generate_debrief(
            self._context(readinessOverall=42, readinessConfidence=0.8),
            "bodyScan", 5.0, None,
        )
        self.assertEqual(result["trigger"], "recovery-day-debrief")

    def test_low_confidence_readiness_never_triggers_recovery_band(self):
        result = watch_debrief.generate_debrief(
            self._context(readinessOverall=30, readinessConfidence=0.1),
            "stressRelease", 3.0, None,
        )
        self.assertNotEqual(result["trigger"], "recovery-day-debrief")

    def test_sleep_factor_debrief(self):
        result = watch_debrief.generate_debrief(
            self._context(sleepFactors=["lateCaffeine"]), "windDown", 4.0, None,
        )
        self.assertEqual(result["trigger"], "sleep-factor-debrief")

    def test_default_debrief_fallback(self):
        result = watch_debrief.generate_debrief(self._context(), "morningGrounding", 3.0, None)
        self.assertEqual(result["trigger"], "default-debrief")

    def test_positive_biofeedback_is_reported(self):
        result = watch_debrief.generate_debrief(self._context(), "boxBreathing", 3.0, 5.0)
        self.assertIn("bpm", result["message"])

    def test_negative_biofeedback_is_never_reported(self):
        result = watch_debrief.generate_debrief(self._context(), "boxBreathing", 3.0, -4.0)
        self.assertNotIn("bpm", result["message"])
        # Falls back to the philosophy line instead of a negative verdict.
        self.assertIn("live your best life", result["message"])

    def test_neutral_biofeedback_reports_easing(self):
        result = watch_debrief.generate_debrief(self._context(), "boxBreathing", 3.0, 1.5)
        self.assertIn("eased", result["message"])

    def test_missing_context_fields_do_not_crash(self):
        result = watch_debrief.generate_debrief({}, "focusReset", 2.0, None)
        self.assertTrue(result["message"])
        self.assertEqual(result["trigger"], "default-debrief")

    def test_unknown_practice_falls_back_to_generic_label(self):
        result = watch_debrief.generate_debrief(self._context(), "somethingNew", 2.0, None)
        self.assertIn("reset", result["message"])

    def test_every_branch_is_exactly_two_sentences_and_guilt_free(self):
        contexts = [
            (self._context(lifestyleMode="deskCoding", hoursSinceLastWorkout=0.1), "bodyScan"),
            (self._context(lifestyleMode="deepFocus"), "focusReset"),
            (self._context(readinessOverall=40, readinessConfidence=0.9), "bodyScan"),
            (self._context(sleepFactors=["stress"]), "windDown"),
            (self._context(), "morningGrounding"),
        ]
        for ctx, practice in contexts:
            for bpm in (None, 5.0, -3.0, 1.2):
                result = watch_debrief.generate_debrief(ctx, practice, 3.0, bpm)
                message = result["message"]
                self.assertEqual(_sentence_count(message), 2, msg=message)
                lowered = message.lower()
                for banned in _BANNED_PHRASES:
                    self.assertNotIn(banned, lowered, msg=message)


class WatchDebriefRouteTests(unittest.TestCase):
    """Integration tests through the Lambda handler dispatch."""

    def test_post_watch_aria_suggest_happy_path(self):
        response = handler(
            event(
                "POST",
                "/watch/aria/suggest",
                {
                    "practice": "physiologicalSigh",
                    "minutes": 1.5,
                    "context": {
                        "readinessOverall": 78,
                        "readinessConfidence": 0.85,
                        "lifestyleMode": "deskCoding",
                        "sleepFactors": [],
                    },
                },
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = response_body(response)
        self.assertIn("message", payload)
        self.assertIn("trigger", payload)
        self.assertTrue(payload["message"])

    def test_missing_practice_returns_400(self):
        response = handler(
            event("POST", "/watch/aria/suggest", {"context": {}}),
            None,
        )
        self.assertEqual(response["statusCode"], 400)

    def test_missing_context_returns_400(self):
        response = handler(
            event("POST", "/watch/aria/suggest", {"practice": "focusReset"}),
            None,
        )
        self.assertEqual(response["statusCode"], 400)

    def test_context_must_be_an_object(self):
        response = handler(
            event("POST", "/watch/aria/suggest", {"practice": "focusReset", "context": "nope"}),
            None,
        )
        self.assertEqual(response["statusCode"], 400)

    def test_non_numeric_optional_fields_degrade_gracefully(self):
        response = handler(
            event(
                "POST",
                "/watch/aria/suggest",
                {
                    "practice": "boxBreathing",
                    "minutes": "not-a-number",
                    "heartRateSettleBPM": "also-not-a-number",
                    "context": {},
                },
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)


if __name__ == "__main__":
    unittest.main()
