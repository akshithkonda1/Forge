"""Production must never serve one user's fixtures as another user's health data.

``seed_data`` was documented as a deliberate Phase-1 convenience -- "all routes
return deterministic seed data when no persisted data exists, so clients can move
from local mocks to API calls before ingestion pipelines are populated". Nothing
ever turned it off. These tests are the thing that turns it off and keeps it off.
"""

import json
import os
import unittest

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from routes import coach as coach_routes  # noqa: E402
from security import demo_data_enabled  # noqa: E402
from services import coach_context  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402

USER = "prod-user-00000001"

# Strings that only exist in seed_data.py. If one reaches a production response,
# a real account is being shown somebody else's life.
FIXTURE_MARKERS = (
    "Akshith",
    "Upper Body Power",
    "Barbell Bench Press",
    "Weighted Pull-Ups",
    "Lower Body Strength",
    "HIIT Conditioning",
    "Apple Watch",
    "Oura Ring",
    "Mile Run",
    "2026-05-06",
    "2026-04-23",
)


def event(method, path, body=None, query=None, *, user_id=USER):
    payload = {
        "requestContext": {
            "http": {"method": method, "path": path},
            "authorizer": {"jwt": {"claims": {"sub": user_id}}},
        },
        "queryStringParameters": query or {},
        "headers": {},
    }
    if body is not None:
        payload["body"] = json.dumps(body)
    return payload


def body_of(response):
    return json.loads(response["body"])


class _EnvCase(unittest.TestCase):
    """Save and restore the env keys these tests move, so ordering cannot leak."""

    ENV = "production"

    def setUp(self):
        dynamodb_store.clear_local_store()
        coach_routes.set_router_invoker(None)
        self._saved = {
            k: os.environ.get(k)
            for k in ("ENVIRONMENT", "FORGE_DEMO_DATA", "FORGE_ALLOW_ANON_TEST_USER")
        }
        os.environ["ENVIRONMENT"] = self.ENV
        os.environ.pop("FORGE_DEMO_DATA", None)
        os.environ.pop("FORGE_ALLOW_ANON_TEST_USER", None)

    def tearDown(self):
        dynamodb_store.clear_local_store()
        coach_routes.set_router_invoker(None)
        for k, v in self._saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def assertNoFixtures(self, payload):
        text = json.dumps(payload)
        for marker in FIXTURE_MARKERS:
            self.assertNotIn(marker, text, f"fixture {marker!r} leaked into a production response")


class DemoGateTests(_EnvCase):
    def test_production_like_environments_disable_demo_data(self):
        for env in ("prod", "production", "staging", "stage"):
            with self.subTest(env=env):
                os.environ["ENVIRONMENT"] = env
                self.assertFalse(demo_data_enabled())

    def test_env_var_cannot_force_demo_data_on_in_production(self):
        os.environ["ENVIRONMENT"] = "production"
        for value in ("1", "true", "yes", "on"):
            with self.subTest(value=value):
                os.environ["FORGE_DEMO_DATA"] = value
                self.assertFalse(demo_data_enabled())

    def test_dev_environments_keep_demo_data_by_default(self):
        for env in ("local", "dev", "development", "test", "ci", ""):
            with self.subTest(env=env):
                os.environ["ENVIRONMENT"] = env
                self.assertTrue(demo_data_enabled())

    def test_dev_can_opt_out_of_demo_data(self):
        os.environ["ENVIRONMENT"] = "dev"
        for value in ("0", "false", "no", "off"):
            with self.subTest(value=value):
                os.environ["FORGE_DEMO_DATA"] = value
                self.assertFalse(demo_data_enabled())


class ProductionDashboardTests(_EnvCase):
    def test_new_account_dashboard_carries_no_invented_data(self):
        payload = body_of(handler(event("GET", "/dashboard/today"), None))
        self.assertNoFixtures(payload)

        self.assertEqual(payload["profile"]["name"], "")
        self.assertEqual(payload["connections"], [])
        self.assertEqual(payload["recentSleep"], [])
        self.assertEqual(payload["recentWorkouts"], [])
        self.assertEqual(payload["personalRecords"], [])
        self.assertIsNone(payload["todayWorkout"])
        self.assertIsNone(payload["readiness"]["overall"])
        self.assertFalse(payload["readiness"]["available"])
        self.assertIsNone(payload["dailyMetrics"]["hrv"])
        self.assertIsNone(payload["dailyMetrics"]["steps"])
        self.assertEqual(payload["dailyMetrics"]["sources"], [])

    def test_response_shape_is_unchanged_so_clients_still_decode(self):
        payload = body_of(handler(event("GET", "/dashboard/today"), None))
        self.assertEqual(
            set(payload),
            {
                "profile",
                "readiness",
                "dailyMetrics",
                "todayWorkout",
                "recentSleep",
                "recentWorkouts",
                "personalRecords",
                "connections",
            },
        )
        self.assertEqual(
            set(payload["dailyMetrics"]),
            {
                "date",
                "steps",
                "activeCalories",
                "hrv",
                "restingHR",
                "deepSleep",
                "totalSleep",
                "sources",
            },
        )

    def test_missing_metrics_are_null_not_zero(self):
        """0 bpm is a claim about a corpse; null is the absence of a reading."""
        metrics = body_of(handler(event("GET", "/dashboard/today"), None))["dailyMetrics"]
        for field in ("steps", "activeCalories", "hrv", "restingHR"):
            with self.subTest(field=field):
                self.assertIsNone(metrics[field])


class IngestedMetricsTests(_EnvCase):
    """dailyMetrics never read storage at all -- it returned a fixture outright."""

    def _ingest(self, metrics):
        response = handler(event("POST", "/health/batch", {"metrics": metrics}), None)
        self.assertEqual(response["statusCode"], 200)
        return body_of(response)

    def _today(self):
        from seed_data import today_iso
        return today_iso()

    def test_ingested_samples_reach_the_dashboard(self):
        day = self._today()
        result = self._ingest([
            {"metricType": "steps", "source": "apple-health",
             "startedAt": f"{day}T09:00:00+00:00", "value": 4210, "unit": "count"},
            {"metricType": "hrv", "source": "oura",
             "startedAt": f"{day}T06:00:00+00:00", "value": 61, "unit": "ms"},
            {"metricType": "resting-heart-rate", "source": "oura",
             "startedAt": f"{day}T06:00:00+00:00", "value": 54, "unit": "bpm"},
        ])
        self.assertEqual(result["accepted"], 3)

        metrics = body_of(handler(event("GET", "/dashboard/today"), None))["dailyMetrics"]
        self.assertEqual(metrics["steps"], 4210)
        self.assertEqual(metrics["hrv"], 61)
        self.assertEqual(metrics["restingHR"], 54)
        self.assertEqual(metrics["sources"], ["apple-health", "oura"])

    def test_cumulative_counters_take_the_peak_not_the_sum(self):
        """A source re-uploading a running day total must not multiply it."""
        day = self._today()
        self._ingest([
            {"metricType": "steps", "source": "apple-health",
             "startedAt": f"{day}T09:00:00+00:00", "value": 2000, "unit": "count"},
            {"metricType": "steps", "source": "apple-health",
             "startedAt": f"{day}T12:00:00+00:00", "value": 5500, "unit": "count"},
            {"metricType": "steps", "source": "apple-health",
             "startedAt": f"{day}T18:00:00+00:00", "value": 8100, "unit": "count"},
        ])
        metrics = body_of(handler(event("GET", "/dashboard/today"), None))["dailyMetrics"]
        self.assertEqual(metrics["steps"], 8100)

    def test_instantaneous_readings_are_averaged(self):
        day = self._today()
        self._ingest([
            {"metricType": "hrv", "source": "oura",
             "startedAt": f"{day}T06:00:00+00:00", "value": 50, "unit": "ms"},
            {"metricType": "hrv", "source": "oura",
             "startedAt": f"{day}T07:00:00+00:00", "value": 60, "unit": "ms"},
        ])
        metrics = body_of(handler(event("GET", "/dashboard/today"), None))["dailyMetrics"]
        self.assertEqual(metrics["hrv"], 55)

    def test_sleep_minutes_come_from_the_logged_night(self):
        day = self._today()
        handler(
            event("POST", "/sleep/sessions", {
                "session": {"date": day, "source": "oura", "totalHours": 6.5,
                            "deepMinutes": 71, "score": 77},
            }),
            None,
        )
        self._ingest([
            {"metricType": "steps", "source": "oura",
             "startedAt": f"{day}T09:00:00+00:00", "value": 100, "unit": "count"},
        ])
        metrics = body_of(handler(event("GET", "/dashboard/today"), None))["dailyMetrics"]
        self.assertEqual(metrics["deepSleep"], 71)
        self.assertEqual(metrics["totalSleep"], 390)


class ProductionProfileTests(_EnvCase):
    def test_me_returns_no_fixture_identity_or_connections(self):
        payload = body_of(handler(event("GET", "/me"), None))
        self.assertNoFixtures(payload)
        self.assertEqual(payload["profile"]["name"], "")
        self.assertEqual(payload["profile"]["connectedDevices"], [])
        self.assertEqual(payload["connections"], [])

    def test_first_save_persists_only_what_the_user_entered(self):
        """The merge base was the fixture, so a first save wrote it into the account.

        That is the one defect in this set that survives its own fix: it does not
        just display someone else's data, it stores it under a real user id.
        """
        saved = body_of(handler(
            event("PUT", "/me/profile", {"profile": {"name": "Taylor", "coachingStyle": "balanced"}}),
            None,
        ))["profile"]

        self.assertEqual(saved["name"], "Taylor")
        self.assertEqual(saved["coachingStyle"], "balanced")
        self.assertNotIn("fitnessGoals", saved)
        self.assertNotIn("connectedDevices", saved)

        # And it is durable: re-reading must not resurrect the fixture either.
        reread = body_of(handler(event("GET", "/me"), None))["profile"]
        self.assertEqual(reread, saved)
        self.assertNoFixtures(reread)

    def test_later_saves_still_merge_onto_the_users_own_record(self):
        handler(event("PUT", "/me/profile", {"profile": {"name": "Taylor"}}), None)
        saved = body_of(handler(
            event("PUT", "/me/profile", {"profile": {"experienceLevel": "beginner"}}),
            None,
        ))["profile"]
        self.assertEqual(saved["name"], "Taylor")
        self.assertEqual(saved["experienceLevel"], "beginner")


class ProductionCollectionTests(_EnvCase):
    def test_sleep_is_empty_for_a_new_account(self):
        payload = body_of(handler(event("GET", "/sleep", query={"days": "7"}), None))
        self.assertEqual(payload["sleep"], [])

    def test_workouts_today_has_no_invented_plan(self):
        payload = body_of(handler(event("GET", "/workouts/today"), None))
        self.assertIsNone(payload["workout"])

    def test_workout_history_and_records_are_empty(self):
        payload = body_of(handler(event("GET", "/workouts/history"), None))
        self.assertEqual(payload["workouts"], [])
        self.assertEqual(payload["personalRecords"], [])

    def test_personal_records_are_derived_from_real_logs(self):
        handler(
            event("POST", "/workouts/logs", {"workout": {
                "id": "log-1",
                "startedAt": "2026-08-24T18:00:00+00:00",
                "date": "2026-08-24",
                "name": "Push",
                "type": "strength",
                "duration": 45,
                "intensity": "high",
                "exercises": [{"name": "Bench Press", "weight": 145}],
            }}),
            None,
        )
        payload = body_of(handler(event("GET", "/workouts/history"), None))
        self.assertEqual(
            payload["personalRecords"],
            [{"exercise": "Bench Press", "value": 145.0, "unit": "lbs", "date": "2026-08-24"}],
        )

    def test_progress_summary_says_there_is_nothing_rather_than_reporting_zeros(self):
        payload = body_of(handler(event("GET", "/progress/summary"), None))
        self.assertEqual(payload["workoutsCompleted"], 0)
        self.assertEqual(payload["newPersonalRecords"], [])
        self.assertEqual(payload["summary"], "Nothing logged yet, so there is no trend to report.")

    def test_chat_thread_starts_empty(self):
        payload = body_of(handler(event("GET", "/chat/threads/current"), None))
        self.assertEqual(payload["messages"], [])


class ProductionChatReplyTests(_EnvCase):
    def _reply(self, content):
        response = handler(
            event("POST", "/chat/threads/current/messages", {"content": content}), None
        )
        self.assertEqual(response["statusCode"], 200)
        return body_of(response)["trainerMessage"]

    def test_training_reply_does_not_quote_a_readiness_it_never_measured(self):
        reply = self._reply("How should I train today?")
        self.assertNotIn("82/100", reply["content"])
        self.assertNotIn("52 ms", reply["content"])
        self.assertNotIn("richCard", reply)

    def test_sleep_reply_does_not_quote_a_night_that_was_never_logged(self):
        reply = self._reply("How was my sleep?")
        self.assertNotIn("7.2", reply["content"])
        self.assertNotIn("102", reply["content"])
        self.assertNotIn("richCard", reply)

    def test_progress_reply_does_not_claim_sessions_that_do_not_exist(self):
        reply = self._reply("Show me my progress")
        self.assertNotIn("8 logged", reply["content"])
        self.assertNotIn("225", reply["content"])

    def test_replies_use_real_data_once_it_exists(self):
        handler(
            event("POST", "/sleep/sessions", {"session": {
                "date": "2026-08-24", "source": "oura",
                "totalHours": 8.1, "deepMinutes": 119, "score": 93,
            }}),
            None,
        )
        reply = self._reply("How was my sleep?")
        self.assertIn("8.1", reply["content"])
        self.assertIn("119", reply["content"])


class ProductionCoachContextTests(_EnvCase):
    """The coach's ground-truth block is what the model is told never to embellish."""

    def setUp(self):
        super().setUp()
        # Force the deterministic fallback rather than reaching for Bedrock: the
        # fabricated numbers lived in those fallback strings, so that is the path
        # worth asserting on, and a real invocation just burns 20s timing out.
        def unreachable(_payload):
            raise RuntimeError("bedrock unavailable")

        coach_routes.set_router_invoker(unreachable)

    def test_the_prompt_the_model_receives_carries_no_fixtures(self):
        captured = {}

        def capture(payload):
            captured.update(payload)
            return {"finalAnswer": "ok"}

        coach_routes.set_router_invoker(capture)
        handler(event("POST", "/coach/messages", {"content": "Should I train?"}), None)

        self.assertTrue(captured, "router was never invoked")
        self.assertNoFixtures(captured)
        self.assertFalse(json.loads(captured["context"])["hasLoggedData"])

    def test_context_package_holds_no_fixtures(self):
        context = coach_context.gather_user_context(USER)
        self.assertNoFixtures(context)
        self.assertEqual(context["recentSleep"], [])
        self.assertEqual(context["recentWorkouts"], [])
        self.assertEqual(context["personalRecords"], [])
        self.assertIsNone(context["todayPlan"])
        self.assertIsNone(context["readiness"]["overall"])

    def test_prompt_block_declares_the_absence_of_data(self):
        block = json.loads(coach_context.context_to_prompt_block(
            coach_context.gather_user_context(USER)
        ))
        self.assertFalse(block["hasLoggedData"])
        self.assertIsNone(block["lastSleepScore"])
        self.assertIsNone(block["todayPlanName"])

    def test_coach_routes_answer_instead_of_erroring_on_an_empty_account(self):
        """An unmeasured readiness used to reach arithmetic and a None subscript."""
        for path in (
            "/coach/workout-plan",
            "/coach/sleep-insight",
            "/coach/progress-review",
        ):
            with self.subTest(path=path):
                response = handler(event("POST", path, {}), None)
                self.assertEqual(response["statusCode"], 200)
                self.assertNoFixtures(body_of(response))

    def test_coach_message_answers_without_inventing_a_score(self):
        response = handler(event("POST", "/coach/messages", {"content": "Should I train?"}), None)
        self.assertEqual(response["statusCode"], 200)
        content = body_of(response)["content"]
        self.assertNotIn("None/100", content)
        self.assertNotIn("82/100", content)

    def test_unmeasured_readiness_does_not_prescribe_high_intensity(self):
        plan = body_of(handler(event("POST", "/coach/workout-plan", {}), None))
        self.assertEqual(plan["baseline"]["intensity"], "low")
        self.assertFalse(plan["baseline"]["readinessKnown"])


class DemoEnvironmentStillDemosTests(_EnvCase):
    """The fixtures still have a job; this fix must not take the demo build down."""

    ENV = "dev"

    def test_dev_dashboard_still_shows_the_seeded_story(self):
        payload = body_of(handler(event("GET", "/dashboard/today"), None))
        self.assertEqual(payload["profile"]["name"], "Akshith")
        self.assertEqual(payload["readiness"]["overall"], 82)
        self.assertEqual(payload["todayWorkout"]["name"], "Upper Body Power")
        self.assertEqual(payload["dailyMetrics"]["steps"], 3241)
        self.assertTrue(payload["personalRecords"])
        self.assertTrue(payload["connections"])

    def test_dev_opting_out_gets_the_production_shape(self):
        os.environ["FORGE_DEMO_DATA"] = "0"
        payload = body_of(handler(event("GET", "/dashboard/today"), None))
        self.assertEqual(payload["profile"]["name"], "")
        self.assertIsNone(payload["readiness"]["overall"])
        self.assertIsNone(payload["todayWorkout"])


if __name__ == "__main__":
    unittest.main()
