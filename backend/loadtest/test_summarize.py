"""Stdlib checks for stress error splits and abort-threshold math."""

from __future__ import annotations

import unittest

from backend.loadtest.summarize import (
    STRESS_CEILING_RPS,
    classify_status,
    _derive_stress_breaking_point,
    _interpolated_arrival_rate,
)


class ClassifyStatusTests(unittest.TestCase):
    def test_splits_429_from_5xx_and_other(self):
        self.assertEqual(classify_status("200"), "ok")
        self.assertEqual(classify_status("204"), "ok")
        self.assertEqual(classify_status("429"), "429")
        self.assertEqual(classify_status("500"), "5xx")
        self.assertEqual(classify_status("503"), "5xx")
        self.assertEqual(classify_status("0"), "other")
        self.assertEqual(classify_status("400"), "other")


class StressThresholdTests(unittest.TestCase):
    def test_ceiling_is_1000(self):
        self.assertEqual(STRESS_CEILING_RPS, 1000.0)

    def test_interpolates_into_late_stages(self):
        # 20+20+20 = 60s lands at the start of the 100→200 stage.
        mid = _interpolated_arrival_rate(70.0)
        self.assertEqual(mid["stage_target_rps"], 200.0)
        self.assertGreater(mid["interpolated_arrival_rps"], 100.0)
        self.assertLess(mid["interpolated_arrival_rps"], 200.0)

    def test_429_alone_is_not_a_break(self):
        report = {
            "duration_seconds": 180.0,
            "error_rate_non_429": 0.0,
            "error_rate_overall": 0.5,
            "errors_429": 100,
            "latency_ms": {"p95": 5.0},
            "per_route": {
                "POST /ai/chat": {"status_codes": {"429": 100, "200": 100}},
            },
            "peak_rps": {"peak_1s_http_reqs": 40},
        }
        series = [
            {
                "t": 1_000,
                "requests": 40,
                "p95_ms": 5.0,
                "errors_5xx": 0,
                "errors_429": 20,
                "errors_other": 0,
                "errors_non_429": 0,
            }
            for _ in range(180)
        ]
        for i, slot in enumerate(series):
            slot["t"] = 1_000 + i
        point = _derive_stress_breaking_point(report, series)
        self.assertTrue(point["never_broke_by_ceiling"])
        self.assertIn("never broke", point["note"])

    def test_p95_crossing_is_the_first_break(self):
        report = {
            "duration_seconds": 40.0,
            "error_rate_non_429": 0.0,
            "latency_ms": {"p95": 2500.0},
            "per_route": {},
            "peak_rps": {"peak_1s_http_reqs": 80},
        }
        series = []
        for i in range(40):
            series.append(
                {
                    "t": 5_000 + i,
                    "requests": 20 + i,
                    "p95_ms": 10.0 if i < 25 else 2500.0,
                    "errors_5xx": 0,
                    "errors_429": 0,
                    "errors_other": 0,
                    "errors_non_429": 0,
                }
            )
        point = _derive_stress_breaking_point(report, series)
        self.assertFalse(point["never_broke_by_ceiling"])
        self.assertEqual(point["first_break"]["elapsed_seconds"], 25)
        self.assertGreaterEqual(point["first_break"]["p95_ms"], 2000)


if __name__ == "__main__":
    unittest.main()
