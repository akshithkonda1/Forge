"""Tests for aria_core.aria_health_risk_monitor, the Python port of
ForgeCore's AriaHealthRiskMonitor.swift (task #20, the last of the
Swift->Python port list -- see ARIA_INTELLIGENCE_PLAN.md). The Swift
suite's tests (AriaHealthRiskMonitorTests, excluding
testVitalsPayloadRoundTripAndInbox -- WatchVitalsPayload/Inbox is a
separate, UserDefaults-backed file this port deliberately excludes, same
reasoning as every earlier "Store" exclusion) are translated directly;
the rest is this port's own boundary/ranking coverage.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta

import _bootstrap  # noqa: F401

from aria_core import aria_health_risk_monitor as arm  # noqa: E402

NOW = datetime(2026, 3, 1, 12, 0, 0)


def _reading(**overrides) -> arm.AriaVitalReading:
    base = dict(sampled_at=NOW)
    base.update(overrides)
    return arm.AriaVitalReading(**base)


class SwiftTranslatedTests(unittest.TestCase):
    def test_normal_readings_produce_no_findings(self):
        reading = _reading(
            body_temperature_f=98.2, wrist_temperature_deviation_c=0.1,
            resting_heart_rate=54, resting_heart_rate_baseline=55,
            hrv_ms=52, hrv_baseline_ms=50,
        )
        self.assertEqual(arm.evaluate(reading, now=NOW), [])

    def test_slightly_high_temperature_is_watch_not_diagnosis(self):
        reading = _reading(body_temperature_f=99.7)
        findings = arm.evaluate(reading, now=NOW)
        self.assertEqual(findings[0].kind, arm.ELEVATED_TEMPERATURE)
        self.assertEqual(findings[0].severity, arm.WATCH)
        self.assertNotIn("you have", findings[0].body.lower())
        self.assertIn("99.7", findings[0].chat_opener)

    def test_fever_range_temperature_is_concern_and_still_not_a_diagnosis(self):
        reading = _reading(body_temperature_f=101.2)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertEqual(finding.severity, arm.CONCERN)
        self.assertIn("clinician", finding.coach_line.lower())
        self.assertNotIn("influenza", finding.title.lower())

    def test_wrist_deviation_uses_watch_sleeping_reading(self):
        reading = _reading(wrist_temperature_deviation_c=0.85)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertEqual(finding.kind, arm.WRIST_TEMPERATURE_RISE)
        self.assertEqual(finding.severity, arm.CONCERN)
        self.assertIn("wrist", finding.body.lower())

    def test_recent_workout_does_not_flag_body_temperature(self):
        reading = _reading(body_temperature_f=100.8, hours_since_last_workout=0.4)
        self.assertEqual(arm.evaluate(reading, now=NOW), [])

    def test_resting_heart_rate_spike_and_hrv_drop(self):
        reading = _reading(
            resting_heart_rate=72, resting_heart_rate_baseline=55,
            hrv_ms=28, hrv_baseline_ms=55,
        )
        kinds = {f.kind for f in arm.evaluate(reading, now=NOW)}
        self.assertIn(arm.RESTING_HEART_RATE_SPIKE, kinds)
        self.assertIn(arm.HRV_DROP, kinds)

    def test_stale_sample_is_ignored(self):
        reading = _reading(sampled_at=NOW - timedelta(hours=20), body_temperature_f=102)
        self.assertEqual(arm.evaluate(reading, now=NOW), [])

    def test_cooldown(self):
        self.assertTrue(arm.should_notify(None, now=NOW))
        self.assertFalse(arm.should_notify(NOW, now=NOW))
        self.assertTrue(arm.should_notify(NOW - timedelta(hours=9), now=NOW))

    def test_chat_surface_needles(self):
        self.assertTrue(arm.should_surface_in_chat("why is my temperature high"))
        self.assertFalse(arm.should_surface_in_chat("what should I eat for dinner"))


class TemperatureBoundaryTests(unittest.TestCase):
    def test_just_below_slightly_high_does_not_fire(self):
        reading = _reading(body_temperature_f=99.4)
        self.assertEqual(arm.evaluate(reading, now=NOW), [])

    def test_exactly_slightly_high_fires_as_watch(self):
        reading = _reading(body_temperature_f=99.5)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertEqual(finding.severity, arm.WATCH)

    def test_exactly_fever_range_is_concern(self):
        reading = _reading(body_temperature_f=100.4)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertEqual(finding.severity, arm.CONCERN)

    def test_workout_over_the_ignore_window_does_not_suppress(self):
        reading = _reading(body_temperature_f=100.8, hours_since_last_workout=1.5)
        self.assertNotEqual(arm.evaluate(reading, now=NOW), [])


class WristBoundaryTests(unittest.TestCase):
    def test_just_below_watch_threshold_does_not_fire(self):
        reading = _reading(wrist_temperature_deviation_c=0.49)
        self.assertEqual(arm.evaluate(reading, now=NOW), [])

    def test_exactly_watch_threshold_fires_as_watch(self):
        reading = _reading(wrist_temperature_deviation_c=0.5)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertEqual(finding.severity, arm.WATCH)


class RestingHeartRateTests(unittest.TestCase):
    def test_missing_or_zero_baseline_never_fires(self):
        self.assertEqual(arm.evaluate(_reading(resting_heart_rate=80), now=NOW), [])
        self.assertEqual(arm.evaluate(_reading(resting_heart_rate=80, resting_heart_rate_baseline=0), now=NOW), [])

    def test_just_below_watch_delta_does_not_fire(self):
        reading = _reading(resting_heart_rate=62.9, resting_heart_rate_baseline=55)
        self.assertEqual(arm.evaluate(reading, now=NOW), [])

    def test_exactly_watch_delta_fires_as_watch(self):
        reading = _reading(resting_heart_rate=63, resting_heart_rate_baseline=55)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertEqual(finding.severity, arm.WATCH)

    def test_exactly_concern_delta_fires_as_concern(self):
        reading = _reading(resting_heart_rate=67, resting_heart_rate_baseline=55)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertEqual(finding.severity, arm.CONCERN)

    def test_negative_delta_never_fires(self):
        reading = _reading(resting_heart_rate=40, resting_heart_rate_baseline=55)
        self.assertEqual(arm.evaluate(reading, now=NOW), [])


class HrvDropTests(unittest.TestCase):
    def test_missing_or_zero_baseline_never_fires(self):
        self.assertEqual(arm.evaluate(_reading(hrv_ms=30), now=NOW), [])
        self.assertEqual(arm.evaluate(_reading(hrv_ms=30, hrv_baseline_ms=0), now=NOW), [])

    def test_fractional_drop_alone_fires_without_absolute_drop(self):
        """25% fractional drop with an absolute drop under 15ms still
        fires: base=40, hrv=29 -> drop=11 (< 15 absolute), but
        hrv <= base*0.75=30 is true."""
        reading = _reading(hrv_ms=29, hrv_baseline_ms=40)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertIsNotNone(finding)
        self.assertEqual(finding.kind, arm.HRV_DROP)

    def test_small_drop_neither_absolute_nor_fractional_does_not_fire(self):
        reading = _reading(hrv_ms=54, hrv_baseline_ms=60)  # drop=6, ratio=0.9
        self.assertEqual(arm.evaluate(reading, now=NOW), [])

    def test_concern_threshold_via_absolute_drop(self):
        # drop=21 >= 15*1.4=21 -> concern
        reading = _reading(hrv_ms=39, hrv_baseline_ms=60)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertEqual(finding.severity, arm.CONCERN)

    def test_concern_threshold_via_fractional_drop_alone(self):
        """Isolates the fractional-concern path from the absolute one:
        base=50, hrv=32 -> drop=18 (< 15*1.4=21, so NOT concern via the
        absolute-drop test), but hrv=32 <= base*0.65=32.5 (concern via
        the fractional test). Still fires at all because drop=18 >= 15."""
        reading = _reading(hrv_ms=32, hrv_baseline_ms=50)
        finding = arm.primary(arm.evaluate(reading, now=NOW))
        self.assertEqual(finding.severity, arm.CONCERN)


class RankingTests(unittest.TestCase):
    def test_findings_sorted_by_rank_descending(self):
        reading = _reading(
            body_temperature_f=101.2,  # concern elevatedTemperature -> 40
            hrv_ms=28, hrv_baseline_ms=55,  # concern hrvDrop -> 28
        )
        findings = arm.evaluate(reading, now=NOW)
        ranks = [f.rank for f in findings]
        self.assertEqual(ranks, sorted(ranks, reverse=True))
        self.assertEqual(findings[0].kind, arm.ELEVATED_TEMPERATURE)

    def test_rank_table_matches_the_swift_switch(self):
        table = {
            (arm.CONCERN, arm.ELEVATED_TEMPERATURE): 40,
            (arm.CONCERN, arm.WRIST_TEMPERATURE_RISE): 36,
            (arm.CONCERN, arm.RESTING_HEART_RATE_SPIKE): 32,
            (arm.CONCERN, arm.HRV_DROP): 28,
            (arm.WATCH, arm.ELEVATED_TEMPERATURE): 24,
            (arm.WATCH, arm.WRIST_TEMPERATURE_RISE): 20,
            (arm.WATCH, arm.RESTING_HEART_RATE_SPIKE): 16,
            (arm.WATCH, arm.HRV_DROP): 12,
        }
        for (severity, kind), expected_rank in table.items():
            finding = arm.AriaHealthRiskFinding(kind=kind, severity=severity, title="", body="",
                                                 chat_opener="", coach_line="")
            self.assertEqual(finding.rank, expected_rank)


class PrimaryTests(unittest.TestCase):
    def test_primary_of_empty_is_none(self):
        self.assertIsNone(arm.primary([]))


class StorageKeyTests(unittest.TestCase):
    def test_storage_key_uses_the_exact_swift_raw_values(self):
        self.assertEqual(arm.storage_key(arm.ELEVATED_TEMPERATURE), "forge.aria.risk.lastNotified.elevatedTemperature")
        self.assertEqual(arm.storage_key(arm.HRV_DROP), "forge.aria.risk.lastNotified.hrvDrop")


if __name__ == "__main__":
    unittest.main()
