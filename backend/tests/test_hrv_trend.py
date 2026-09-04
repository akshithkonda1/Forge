"""HRV trend — the signal ARIA's recovery reasoning is built on.

`aria_engine._interpret_readiness` has two carefully-written branches keyed on
`hrv_7day_trend` (<= -8 for autonomic load, >= 5 for recovery trending up).
Neither could ever fire from a real device, because the iOS client computed the
trend like this:

    store.sleepData.prefix(7).map { _ in Double(store.dailyMetrics.hrv) }

The `_ in` discarded each day and substituted today's single reading seven times,
so the baseline always equalled today's value and the trend was always exactly
0.0 — which lands in the `else` branch, "HRV is tracking near baseline", for
every user forever.

The server was already computing this correctly from dated samples. These tests
pin both halves: that a real dated series produces a real trend, and that the
degenerate single-sample shape produces the 0.0 that started all this — so
nobody re-introduces it by sending one snapshot per refresh again.
"""

import datetime as dt
import json
import unittest

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from services import aria_engine  # noqa: E402


def _observe(samples, user):
    event = {
        "requestContext": {
            "http": {"method": "POST", "path": "/ai/observe"},
            "authorizer": {"jwt": {"claims": {"sub": user}}},
        },
        "queryStringParameters": {},
        "headers": {},
        "body": json.dumps(
            {"samples": samples, "include_stored": False, "message": "how am I recovering?"}
        ),
    }
    response = handler(event, None)
    body = json.loads(response["body"])
    return response["statusCode"], (body.get("aria_context") or {}).get("readiness") or {}


def _hrv_series(values):
    """One dated sample per day, oldest first — what the client sends now."""
    now = dt.datetime.now(dt.timezone.utc)
    return [
        {
            "metric": "hrv",
            "value": float(v),
            "unit": "ms",
            "timestamp": (now - dt.timedelta(days=days_ago)).isoformat(),
            "source": "apple-health",
        }
        for days_ago, v in zip(range(len(values) - 1, -1, -1), values)
    ]


class HRVTrendTests(unittest.TestCase):

    def test_a_dated_series_produces_a_real_trend(self):
        status, readiness = _observe(_hrv_series([58, 57, 56, 52, 48, 45, 42]), "u-decline")
        self.assertEqual(status, 200)
        self.assertEqual(readiness["hrv_days_available"], 7)
        self.assertLess(readiness["hrv_7day_trend"], 0)
        self.assertNotEqual(readiness["hrv_7day_trend"], 0.0)
        # Median-based, so the baseline is the middle of the week, not today.
        self.assertGreater(readiness["hrv_30day_baseline"], 42)

    def test_one_snapshot_stamped_now_is_structurally_incapable_of_a_trend(self):
        status, readiness = _observe(_hrv_series([42]), "u-single")
        self.assertEqual(status, 200)
        self.assertEqual(readiness["hrv_days_available"], 1)
        self.assertEqual(readiness["hrv_7day_trend"], 0.0)
        self.assertEqual(readiness["hrv_30day_baseline"], 42.0)

    def test_a_rising_series_trends_positive(self):
        _, readiness = _observe(_hrv_series([40, 42, 45, 48, 52, 55, 58]), "u-rising")
        self.assertGreater(readiness["hrv_7day_trend"], 0)


class ReadinessBranchReachabilityTests(unittest.TestCase):
    """The branches that were dead code in practice."""

    def _signal(self, trend):
        ctx = aria_engine.ARIAContext.from_payload(
            {"user_id": "u1",
             "context": {"readiness": {"hrv7DayTrend": trend, "recoveryScore": 70}}}
        )
        return aria_engine._interpret_readiness(ctx)

    def test_a_steep_decline_reaches_the_autonomic_load_branch(self):
        signal = self._signal(-10.3)
        self.assertEqual(signal.direction, "negative")
        self.assertEqual(signal.priority, "high")
        self.assertIn("autonomic system is still carrying load", signal.interpretation)

    def test_a_clear_rise_reaches_the_recovery_branch(self):
        signal = self._signal(6.5)
        self.assertEqual(signal.direction, "positive")
        self.assertIn("recovery is trending up", signal.interpretation)

    def test_zero_lands_in_the_near_baseline_branch(self):
        # What every user got, every time, before this was fixed.
        signal = self._signal(0.0)
        self.assertIn("tracking near baseline", signal.interpretation)
        self.assertNotEqual(signal.priority, "high")
