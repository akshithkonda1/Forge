import json
import unittest

from _support import ensure_api_on_path

ensure_api_on_path()

from handler import handler  # noqa: E402
from routes import coach as coach_routes  # noqa: E402
from services import scoring  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402


def event(method, path, body=None, query=None):
    payload = {
        "requestContext": {
            "http": {
                "method": method,
                "path": path,
            }
        },
        "queryStringParameters": query or {},
    }
    if body is not None:
        payload["body"] = json.dumps(body)
    return payload


def body(response):
    return json.loads(response["body"])


class BackendHandlerTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        coach_routes.set_router_invoker(None)

    def test_dashboard_today_returns_phase_one_payload(self):
        response = handler(event("GET", "/dashboard/today"), None)

        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["profile"]["name"], "Akshith")
        self.assertEqual(payload["readiness"]["overall"], 82)
        self.assertEqual(payload["todayWorkout"]["name"], "Upper Body Power")
        self.assertGreaterEqual(len(payload["recentSleep"]), 7)

    def test_profile_update_merges_profile_patch(self):
        response = handler(
            event(
                "PUT",
                "/me/profile",
                {
                    "profile": {
                        "name": "Taylor",
                        "coachingStyle": "balanced",
                    }
                },
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["profile"]["name"], "Taylor")
        self.assertEqual(payload["profile"]["coachingStyle"], "balanced")
        self.assertEqual(payload["profile"]["fitnessGoals"], ["build-muscle"])

    def test_sleep_respects_days_query(self):
        response = handler(event("GET", "/sleep", query={"days": "3"}), None)

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(len(body(response)["sleep"]), 3)

    def test_chat_message_returns_seed_trainer_response(self):
        response = handler(
            event(
                "POST",
                "/chat/threads/current/messages",
                {"content": "How should I train today?"},
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["userMessage"]["role"], "user")
        self.assertEqual(payload["trainerMessage"]["role"], "trainer")
        self.assertEqual(payload["trainerMessage"]["richCard"]["type"], "workout-plan")

    def test_unknown_route_returns_not_found(self):
        response = handler(event("GET", "/not-real"), None)

        self.assertEqual(response["statusCode"], 404)
        self.assertEqual(body(response)["message"], "Route is not implemented.")


class IngestionRouteTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()

    def test_health_batch_accepts_and_normalizes_body_weight_kg(self):
        response = handler(
            event(
                "POST",
                "/health/batch",
                {
                    "metrics": [
                        {
                            "source": "apple-health",
                            "metricType": "body-weight",
                            "startedAt": "2026-05-06T08:00:00+00:00",
                            "value": 80,
                            "unit": "kg",
                        }
                    ]
                },
            ),
            None,
        )

        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["accepted"], 1)
        self.assertEqual(payload["rejected"], 0)

    def test_health_batch_rejects_unknown_metric_type(self):
        response = handler(
            event(
                "POST",
                "/health/batch",
                {
                    "metrics": [
                        {
                            "source": "apple-health",
                            "metricType": "spirit-level",
                            "startedAt": "2026-05-06T08:00:00+00:00",
                            "value": 1,
                            "unit": "count",
                        }
                    ]
                },
            ),
            None,
        )

        payload = body(response)
        self.assertEqual(payload["accepted"], 0)
        self.assertEqual(payload["rejected"], 1)

    def test_sleep_session_post_then_list_returns_persisted(self):
        post = handler(
            event(
                "POST",
                "/sleep/sessions",
                {
                    "session": {
                        "date": "2026-05-06",
                        "source": "oura",
                        "totalHours": 7.1,
                        "score": 89,
                    }
                },
            ),
            None,
        )
        self.assertEqual(post["statusCode"], 200)

        listed = handler(event("GET", "/sleep", query={"days": "5"}), None)
        sleep = body(listed)["sleep"]
        self.assertEqual(sleep[0]["score"], 89)

    def test_workout_log_post_persists(self):
        response = handler(
            event(
                "POST",
                "/workouts/logs",
                {
                    "workout": {
                        "id": "log-1",
                        "startedAt": "2026-05-06T18:00:00+00:00",
                        "name": "Push Day",
                        "type": "strength",
                        "duration": 50,
                        "intensity": "high",
                    }
                },
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)

        history = handler(event("GET", "/workouts/history"), None)
        workouts = body(history)["workouts"]
        self.assertTrue(any(w.get("id") == "log-1" for w in workouts))


class IntegrationSyncTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()

    def test_sync_known_provider_queues_job(self):
        response = handler(event("POST", "/integrations/oura/sync", {}), None)
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["provider"], "oura")
        self.assertEqual(payload["status"], "queued")
        self.assertEqual(len(payload["jobId"]), 16)

    def test_sync_unknown_provider_rejected(self):
        response = handler(event("POST", "/integrations/myspace/sync", {}), None)
        self.assertEqual(response["statusCode"], 400)


class CoachRouteTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        coach_routes.set_router_invoker(lambda payload: {"finalAnswer": "stub: " + payload["question"][:20]})

    def tearDown(self):
        coach_routes.set_router_invoker(None)

    def test_coach_message_uses_router(self):
        response = handler(
            event("POST", "/coach/messages", {"content": "Should I train today?"}),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertTrue(payload["content"].startswith("stub:"))
        self.assertEqual(payload["role"], "trainer")

    def test_coach_workout_plan_returns_baseline(self):
        response = handler(event("POST", "/coach/workout-plan", {}), None)
        payload = body(response)
        self.assertIn("baseline", payload)
        self.assertIn("focus", payload["baseline"])

    def test_coach_falls_back_when_router_raises(self):
        def failing(_payload):
            raise RuntimeError("bedrock unavailable")

        coach_routes.set_router_invoker(failing)
        response = handler(event("POST", "/coach/sleep-insight", {}), None)
        payload = body(response)
        self.assertTrue(payload["fallback"])
        self.assertIn("Sleep trend", payload["insight"])


class ScoringServiceTests(unittest.TestCase):
    def test_training_load_trend_rising(self):
        workouts = [
            {"duration": 60, "intensity": "high"},
            {"duration": 60, "intensity": "high"},
            {"duration": 60, "intensity": "high"},
            {"duration": 60, "intensity": "high"},
            {"duration": 60, "intensity": "high"},
            {"duration": 60, "intensity": "high"},
            {"duration": 60, "intensity": "high"},
            {"duration": 30, "intensity": "low"},
            {"duration": 30, "intensity": "low"},
        ]
        result = scoring.training_load_trend(workouts)
        self.assertEqual(result["trend"], "rising")
        self.assertGreater(result["current"], result["previous"])

    def test_recovery_trend_zero_when_empty(self):
        self.assertEqual(scoring.recovery_trend([])["delta"], 0)

    def test_baseline_recommendation_low_readiness_returns_recovery(self):
        result = scoring.baseline_workout_recommendation(40, "strength")
        self.assertEqual(result["focus"], "recovery")

    def test_detect_personal_records_picks_max_weight(self):
        workouts = [
            {"date": "2026-05-01", "exercises": [{"name": "Bench", "weight": 200}]},
            {"date": "2026-05-03", "exercises": [{"name": "Bench", "weight": 220}]},
            {"date": "2026-05-04", "exercises": [{"name": "Bench", "weight": 215}]},
        ]
        prs = scoring.detect_personal_records(workouts)
        self.assertEqual(prs[0]["value"], 220.0)
        self.assertEqual(prs[0]["date"], "2026-05-03")


if __name__ == "__main__":
    unittest.main()
