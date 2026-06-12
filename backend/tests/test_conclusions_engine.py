import unittest

from _support import ensure_api_on_path

ensure_api_on_path()

from services import conclusions_engine, conclusions_store, data_fusion, phi_deidentify, timeseries_rollups
from storage import dynamodb, keys


class ConclusionsEngineTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def tearDown(self):
        dynamodb.clear_local_store()

    def _seed_user(self, user_id: str = "test-user") -> None:
        dynamodb.put_item({
            **keys.metric_key(user_id, "steps", "2026-06-11T08:00:00+00:00"),
            "metricType": "steps",
            "source": "apple-health",
            "startedAt": "2026-06-11T08:00:00+00:00",
            "value": 12000,
        })
        dynamodb.put_item({
            **keys.metric_key(user_id, "hrv", "2026-06-11T08:00:00+00:00"),
            "metricType": "hrv",
            "source": "apple-health",
            "startedAt": "2026-06-11T08:00:00+00:00",
            "value": 30,
        })
        dynamodb.put_item({
            **keys.sleep_key(user_id, "2026-06-11", "apple-health"),
            "date": "2026-06-11",
            "source": "apple-health",
            "totalHours": 6.0,
            "deepMinutes": 45,
            "score": 62,
        })
        dynamodb.put_item({
            **keys.workout_log_key(user_id, "2026-06-10T10:00:00+00:00"),
            "date": "2026-06-10",
            "name": "Strength",
            "type": "strength",
            "duration": 60,
            "volume": 100,
            "intensity": "high",
            "source": "apple-health",
        })

    def test_build_data_conclusions_has_required_fields(self):
        self._seed_user()
        conclusions = conclusions_engine.build_data_conclusions("test-user", date="2026-06-11")
        self.assertIn("coveragePct", conclusions)
        self.assertIn("coachingBrief", conclusions)
        self.assertIn("compoundFlags", conclusions)
        self.assertIn("offlineTemplates", conclusions)
        self.assertGreaterEqual(conclusions["coveragePct"], 0.0)

    def test_load_wellness_snapshot_includes_oxygen_field(self):
        self._seed_user()
        snapshot = data_fusion.load_wellness_snapshot("test-user", date="2026-06-11", days=3)
        self.assertIn("today", snapshot)
        self.assertIn("oxygenSaturation", snapshot["today"])

    def test_timeseries_rollups_window_stats(self):
        rows = [
            {"date": "2026-06-09", "steps": 8000, "hrv": 40},
            {"date": "2026-06-10", "steps": 9000, "hrv": 38},
            {"date": "2026-06-11", "steps": 10000, "hrv": 35},
        ]
        rollups = timeseries_rollups.build_metric_rollups(rows, end_date="2026-06-11", windows=(3,))
        self.assertIn("3", rollups["windows"])
        self.assertIn("steps", rollups["windows"]["3"])

    def test_phi_deidentify_strips_name(self):
        payload = conclusions_engine.build_data_conclusions("test-user", date="2026-06-11")
        payload["profile"] = {"name": "Jane Doe", "email": "jane@example.com"}
        scrubbed = phi_deidentify.deidentify_conclusions(payload)
        self.assertNotIn("name", scrubbed)
        self.assertIn("coachingBrief", scrubbed)

    def test_conclusions_store_round_trip(self):
        self._seed_user()
        refreshed = conclusions_store.refresh_conclusions("test-user")
        loaded = conclusions_store.load_conclusions("test-user")
        self.assertIsNotNone(loaded)
        self.assertEqual(loaded["coachingBrief"], refreshed["coachingBrief"])


if __name__ == "__main__":
    unittest.main()