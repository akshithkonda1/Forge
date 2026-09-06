"""Tests for the vitals safety monitor (services.emergency) + /ai/observe wiring.

Two things must both hold: Forge escalates a plausibly-real, sustained
life-threatening pattern, AND it does NOT escalate on sensor glitches (0%/20%
readings, lost contact, motion) or on a single dip. A false 911 call is its own
harm.
"""

from __future__ import annotations

import json
import unittest
from datetime import datetime, timezone

import _bootstrap  # noqa: F401

from services import emergency as E  # noqa: E402
from storage import dynamodb, keys  # noqa: E402

T0 = datetime(2026, 6, 1, 12, 0, tzinfo=timezone.utc)


def S(**kw):
    kw.setdefault("at", T0)
    return E.VitalsSample(**kw)


def repeat(n, **kw):
    return [S(**kw) for _ in range(n)]


class SampleStateTests(unittest.TestCase):
    def test_spo2_percent_normalized(self):
        self.assertEqual(S(spo2=98).spo2_state(), E._OK)      # percent
        self.assertEqual(S(spo2=0.98).spo2_state(), E._OK)    # fraction

    def test_implausible_spo2_is_no_reading(self):
        self.assertEqual(S(spo2=0.20, sensor_contact=True).spo2_state(), E._NO_READING)
        self.assertEqual(S(spo2=0.0, heart_rate=70).spo2_state(), E._ABSENT)

    def test_lost_contact_or_motion_is_no_reading(self):
        self.assertEqual(S(spo2=0.70, sensor_contact=False).spo2_state(), E._NO_READING)
        self.assertEqual(S(spo2=0.70, motion_artifact=True).spo2_state(), E._NO_READING)

    def test_hr_states(self):
        self.assertEqual(S(heart_rate=0, sensor_contact=True).hr_state(), E._ABSENT)
        self.assertEqual(S(heart_rate=300).hr_state(), E._NO_READING)
        self.assertEqual(S(heart_rate=120).hr_state(), E._OK)


class AssessmentTests(unittest.TestCase):
    def test_healthy_no_escalation(self):
        a = E.assess_vitals(repeat(3, spo2=0.98, heart_rate=140, sensor_contact=True))
        self.assertFalse(a.escalate)
        self.assertEqual(a.severity, E.NONE)

    def test_sustained_valid_severe_hypoxemia_escalates(self):
        window = [S(spo2=0.97, heart_rate=60)] + repeat(3, spo2=0.70, heart_rate=120, sensor_contact=True)
        a = E.assess_vitals(window)
        self.assertTrue(a.escalate)
        self.assertEqual(a.severity, E.CRITICAL)
        self.assertIn("critically low", " ".join(a.reasons))

    def test_no_pulse_after_baseline_escalates(self):
        window = [S(spo2=0.98, heart_rate=64, sensor_contact=True)] + repeat(
            3, spo2=0.0, heart_rate=0, sensor_contact=True
        )
        a = E.assess_vitals(window)
        self.assertTrue(a.escalate)
        self.assertIn("no heartbeat", " ".join(a.reasons))

    def test_collapse_vitals_lost_while_worn_escalates(self):
        window = [S(spo2=0.98, heart_rate=70, sensor_contact=True)] + repeat(
            3, spo2=None, heart_rate=None, sensor_contact=True
        )
        a = E.assess_vitals(window)
        self.assertTrue(a.escalate)
        self.assertIn("collapse", " ".join(a.reasons))

    # --- false-positive guards ---
    def test_single_dip_does_not_escalate(self):
        a = E.assess_vitals([S(spo2=0.98, heart_rate=60), S(spo2=0.72, heart_rate=61)])
        self.assertFalse(a.escalate)
        self.assertEqual(a.severity, E.WARNING)

    def test_implausible_readings_do_not_escalate(self):
        a = E.assess_vitals(repeat(3, spo2=0.20, heart_rate=70, sensor_contact=True))
        self.assertFalse(a.escalate)

    def test_watch_removed_does_not_escalate(self):
        window = [S(spo2=0.98, heart_rate=70, sensor_contact=True)] + repeat(
            3, spo2=None, heart_rate=None, sensor_contact=False
        )
        self.assertFalse(E.assess_vitals(window).escalate)

    def test_inactive_session_does_not_escalate(self):
        window = [S(spo2=0.97, heart_rate=60)] + repeat(3, spo2=0.70, heart_rate=120, sensor_contact=True)
        self.assertFalse(E.assess_vitals(window, session_active=False).escalate)

    def test_empty_window_safe(self):
        self.assertFalse(E.assess_vitals([]).escalate)


class DispatcherTests(unittest.TestCase):
    def test_maybe_escalate_fires_injected_dispatcher(self):
        fired = []
        a = E.EmergencyAssessment(E.CRITICAL, True, ["test reason"])
        intent = E.maybe_escalate(a, user_id="u1", dispatcher=fired.append, now=T0)
        self.assertIsNotNone(intent)
        self.assertEqual(len(fired), 1)
        self.assertEqual(fired[0].user_id, "u1")
        self.assertIn("emergency services", intent.action.lower())

    def test_maybe_escalate_noop_when_not_escalating(self):
        a = E.EmergencyAssessment(E.WARNING, False, [])
        fired = []
        self.assertIsNone(E.maybe_escalate(a, user_id="u1", dispatcher=fired.append))
        self.assertEqual(fired, [])

    def test_intent_carries_client_directive(self):
        d = E.EscalationIntent(user_id="u", reasons=["r"], severity=E.CRITICAL).to_dict()
        self.assertEqual(d["client_action"], E.CLIENT_ACTION)
        self.assertIn("ios_emergency_sos", d["channels"])
        self.assertIn("provider_webhook", d["channels"])

    def test_default_dispatcher_used_without_provider_env(self):
        # No FORGE_EMERGENCY_DISPATCH_URL configured -> safe recorder, never a POST.
        self.assertFalse(E.WebhookDispatcher(url="").enabled())
        self.assertIs(E.resolve_dispatcher(), E.default_dispatcher)

    def test_webhook_dispatcher_posts_when_configured(self):
        posts = []

        def fake_poster(url, payload, *, token=None, timeout=5.0):
            posts.append((url, payload, token))
            return 200

        disp = E.WebhookDispatcher(
            url="https://provider.example/emergency", token="secret", poster=fake_poster
        )
        self.assertTrue(disp.enabled())
        intent = E.EscalationIntent(user_id="u9", reasons=["no heartbeat"], severity=E.CRITICAL)
        disp(intent)
        self.assertEqual(len(posts), 1)
        url, payload, token = posts[0]
        self.assertEqual(url, "https://provider.example/emergency")
        self.assertEqual(token, "secret")
        self.assertEqual(payload["user_id"], "u9")
        self.assertEqual(payload["client_action"], E.CLIENT_ACTION)

    def test_webhook_dispatcher_swallows_provider_errors(self):
        def boom(url, payload, *, token=None, timeout=5.0):
            raise RuntimeError("provider down")

        disp = E.WebhookDispatcher(url="https://provider.example/emergency", poster=boom)
        # Must not raise — a failed webhook can't block the client's Emergency SOS.
        disp(E.EscalationIntent(user_id="u", reasons=["r"], severity=E.CRITICAL))


class ObserveRouteWiringTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def _observe(self, uid, body):
        from routes.biometrics import handle_post_observe
        result = handle_post_observe(body, user_id=uid)
        self.assertEqual(result["statusCode"], 200)
        return json.loads(result["body"])

    def test_observe_escalates_and_audits(self):
        uid = "vitals-user"
        window = [
            {"spo2": 0.98, "heart_rate": 70, "sensor_contact": True},
            {"spo2": 0.0, "heart_rate": 0, "sensor_contact": True},
            {"spo2": 0.0, "heart_rate": 0, "sensor_contact": True},
            {"spo2": 0.0, "heart_rate": 0, "sensor_contact": True},
        ]
        out = self._observe(uid, {"vitals": window, "session_active": True})
        self.assertTrue(out["emergency"]["escalate"])
        self.assertTrue(out["escalation"]["triggered"])
        self.assertEqual(out["escalation"]["client_action"], E.CLIENT_ACTION)
        self.assertIn("ios_emergency_sos", out["escalation"]["channels"])
        # An audit record was written.
        events = dynamodb.query_prefix(keys.user_pk(uid), "EMERGENCY#")
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["intent"]["severity"], E.CRITICAL)

    def test_observe_does_not_escalate_on_glitch(self):
        uid = "vitals-user-2"
        window = [{"spo2": 0.0, "heart_rate": 0, "sensor_contact": False} for _ in range(3)]
        out = self._observe(uid, {"vitals": window, "session_active": True})
        self.assertFalse(out["emergency"]["escalate"])
        self.assertFalse(out["escalation"]["triggered"])
        self.assertEqual(dynamodb.query_prefix(keys.user_pk(uid), "EMERGENCY#"), [])

    def test_observe_without_vitals_has_no_emergency_block(self):
        out = self._observe("vitals-user-3", {"samples": []})
        self.assertNotIn("emergency", out)


if __name__ == "__main__":
    unittest.main()
