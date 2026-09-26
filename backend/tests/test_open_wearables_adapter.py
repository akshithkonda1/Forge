"""Open Wearables adapter: fixture-backed mapping onto Forge ingest shapes."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

import _bootstrap  # noqa: F401

from services.biometrics import classify_batch
from services.open_wearables import adapt_webhook, map_open_wearables_type
from services.open_wearables.vocabulary import FORGE_METRICS

_FIXTURES = Path(__file__).resolve().parent / "fixtures" / "open_wearables"
_COGNITO_SUB = "us-east-1:11111111-2222-3333-4444-555555555555"


def _load(name: str) -> dict:
    return json.loads((_FIXTURES / name).read_text())


class OpenWearablesVocabularyTests(unittest.TestCase):
    def test_forge_metric_names_are_kebab_case(self):
        for name in FORGE_METRICS:
            self.assertEqual(name, name.lower())
            self.assertNotIn("_", name)

    def test_open_wearables_snake_types_map_to_kebab(self):
        spec = map_open_wearables_type("heart_rate")
        self.assertIsNotNone(spec)
        self.assertEqual(spec.name, "heart-rate")
        self.assertEqual(spec.unit, "bpm")
        self.assertEqual(spec.batch_name, "heart-rate")

    def test_hrv_variants_stay_distinct(self):
        sdnn = map_open_wearables_type("heart_rate_variability_sdnn")
        rmssd = map_open_wearables_type("heart_rate_variability_rmssd")
        self.assertEqual(sdnn.name, "hrv-sdnn")
        self.assertEqual(sdnn.batch_name, "hrv")
        self.assertEqual(rmssd.name, "hrv-rmssd")
        self.assertIsNone(rmssd.batch_name)

    def test_unknown_type_is_none(self):
        self.assertIsNone(map_open_wearables_type("nike_fuel"))


class OpenWearablesAdapterTests(unittest.TestCase):
    def test_cognito_sub_is_required_and_is_the_user_key(self):
        event = _load("heart_rate.created.json")
        with self.assertRaises(ValueError):
            adapt_webhook(event, cognito_sub="")
        adapted = adapt_webhook(event, cognito_sub=_COGNITO_SUB)
        self.assertEqual(adapted.cognito_sub, _COGNITO_SUB)
        self.assertEqual(adapted.observe["user_id"], _COGNITO_SUB)
        self.assertEqual(adapted.external_user_id, "550e8400-e29b-41d4-a716-446655440000")
        self.assertNotEqual(adapted.cognito_sub, adapted.external_user_id)

    def test_heart_rate_timeseries_maps_to_batch_and_observe(self):
        adapted = adapt_webhook(_load("heart_rate.created.json"), cognito_sub=_COGNITO_SUB)
        self.assertEqual(len(adapted.observe["samples"]), 3)
        self.assertEqual(len(adapted.health_batch["metrics"]), 3)
        first = adapted.observe["samples"][0]
        self.assertEqual(first["metricType"], "heart-rate")
        self.assertEqual(first["unit"], "bpm")
        self.assertEqual(first["value"], 62)
        self.assertEqual(first["source"], "garmin")
        self.assertEqual(first["device"], "Forerunner 255")
        batch = adapted.health_batch["metrics"][0]
        self.assertEqual(batch["metricType"], "heart-rate")
        self.assertEqual(batch["source"], "garmin")
        self.assertEqual(batch["startedAt"], first["startedAt"])
        self.assertEqual(adapted.rejected, [])

    def test_weight_converts_pounds_to_kilograms(self):
        adapted = adapt_webhook(_load("body_composition.created.json"), cognito_sub=_COGNITO_SUB)
        self.assertEqual(len(adapted.observe["samples"]), 2)
        kg, lb = adapted.observe["samples"]
        self.assertEqual(kg["metricType"], "body-mass")
        self.assertEqual(kg["unit"], "kg")
        self.assertAlmostEqual(kg["value"], 72.4)
        self.assertEqual(lb["source"], "withings")
        self.assertAlmostEqual(lb["value"], 159.6 * 0.453592, places=3)
        batch_names = {m["metricType"] for m in adapted.health_batch["metrics"]}
        self.assertEqual(batch_names, {"body-weight"})
        self.assertTrue(all(m["unit"] == "kg" for m in adapted.health_batch["metrics"]))

    def test_sleep_session_and_stage_samples(self):
        adapted = adapt_webhook(_load("sleep.created.json"), cognito_sub=_COGNITO_SUB)
        session = adapted.sleep_session
        self.assertIsNotNone(session)
        self.assertEqual(session["date"], "2025-12-19")
        self.assertEqual(session["source"], "oura")
        self.assertAlmostEqual(session["totalHours"], 29400.0 / 3600.0, places=4)
        self.assertEqual(session["deepMinutes"], 95)
        self.assertEqual(session["score"], 87.0)
        duration = next(s for s in adapted.observe["samples"] if s["metricType"] == "sleep-duration")
        self.assertEqual(duration["unit"], "s")
        self.assertEqual(duration["value"], 29400.0)
        deep_stages = [
            s for s in adapted.observe["samples"]
            if s["metricType"] == "sleep-stage" and s.get("stage") == "deep"
        ]
        self.assertGreaterEqual(len(deep_stages), 2)  # nightly total + one interval
        classified = classify_batch(adapted.observe["samples"])
        self.assertEqual(classified.counts["rejected"], 0)
        self.assertGreaterEqual(classified.counts["accepted"], 5)
        batch_stages = [m for m in adapted.health_batch["metrics"] if m["metricType"] == "sleep-stage"]
        self.assertTrue(batch_stages)
        self.assertEqual(batch_stages[0]["unit"], "minutes")
        self.assertIn(batch_stages[0]["stage"], {"deep", "rem", "light", "awake"})

    def test_workout_maps_duration_minutes_and_si_metrics(self):
        adapted = adapt_webhook(_load("workout.created.json"), cognito_sub=_COGNITO_SUB)
        workout = adapted.workout
        self.assertEqual(workout["type"], "running")
        self.assertEqual(workout["duration"], 60.0)
        self.assertEqual(workout["distance"], 10200.0)
        self.assertEqual(workout["source"], "garmin")
        energy = next(s for s in adapted.observe["samples"] if s["metricType"] == "active-energy")
        self.assertEqual(energy["unit"], "kcal")
        self.assertEqual(energy["value"], 480.0)
        batch_types = {m["metricType"] for m in adapted.health_batch["metrics"]}
        self.assertIn("active-calories", batch_types)
        self.assertIn("distance", batch_types)

    def test_connection_uses_provider_status_not_metrics(self):
        adapted = adapt_webhook(_load("connection.created.json"), cognito_sub=_COGNITO_SUB)
        self.assertEqual(adapted.connection["provider"], "garmin")
        self.assertEqual(adapted.connection["status"], "connected")
        self.assertEqual(adapted.health_batch["metrics"], [])
        self.assertEqual(adapted.observe["samples"], [])

    def test_unknown_types_are_rejected_known_types_kept(self):
        adapted = adapt_webhook(_load("unknown_type.json"), cognito_sub=_COGNITO_SUB)
        self.assertEqual(len(adapted.observe["samples"]), 1)
        self.assertEqual(adapted.observe["samples"][0]["metricType"], "steps")
        self.assertEqual(adapted.observe["samples"][0]["source"], "whoop")
        self.assertTrue(any("nike_fuel" in r["reason"] for r in adapted.rejected))
        self.assertEqual(adapted.health_batch["metrics"][0]["isDailyTotal"], False)

    def test_observe_samples_classify_onto_aria_taxonomy(self):
        adapted = adapt_webhook(_load("heart_rate.created.json"), cognito_sub=_COGNITO_SUB)
        result = classify_batch(adapted.observe["samples"])
        self.assertEqual(result.counts["accepted"], 3)
        self.assertEqual(result.counts["rejected"], 0)
        self.assertEqual({o.metric.value for o in result.observations}, {"heart_rate"})

    def test_unhandled_event_does_not_raise(self):
        adapted = adapt_webhook(
            {"type": "menstrual_cycle.created", "data": {"user_id": "ow-1"}},
            cognito_sub=_COGNITO_SUB,
        )
        self.assertEqual(adapted.health_batch["metrics"], [])
        self.assertTrue(adapted.rejected)


if __name__ == "__main__":
    unittest.main()
