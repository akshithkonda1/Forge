import os
import sys
import unittest
from pathlib import Path

LAMBDA_DIR = Path(__file__).resolve().parents[1] / "infra" / "terraform" / "lambda"
sys.path.insert(0, str(LAMBDA_DIR))

from handler import handler  # noqa: E402
from services import cycle_partner, daily_decision, household  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402


def event(method, path, body=None, query=None, *, user_id="test-user"):
    payload = {
        "requestContext": {
            "http": {"method": method, "path": path},
            "authorizer": {"jwt": {"claims": {"sub": user_id}}},
        },
        "queryStringParameters": query or {},
        "headers": {},
    }
    if body is not None:
        import json

        payload["body"] = json.dumps(body)
    return payload


def body(response):
    import json

    return json.loads(response["body"])


class PhaseTwoTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"

    def _ingest(self):
        handler(
            event(
                "POST",
                "/sleep/sessions",
                {"session": {"date": "2026-08-12", "source": "oura", "totalHours": 7.4, "score": 88}},
            ),
            None,
        )
        handler(
            event(
                "POST",
                "/health/batch",
                {
                    "metrics": [
                        {
                            "source": "larq",
                            "metricType": "dietary-water",
                            "startedAt": "2026-08-13T08:00:00+00:00",
                            "value": 1400,
                            "unit": "ml",
                        },
                        {
                            "source": "apple-watch",
                            "metricType": "hrv",
                            "startedAt": "2026-08-13T08:05:00+00:00",
                            "value": 52,
                            "unit": "ms",
                        },
                    ]
                },
            ),
            None,
        )

    def test_health_batch_persists_readiness_and_source_map(self):
        self._ingest()
        sources = body(handler(event("GET", "/sources"), None))
        labels = {row["source"] for row in sources["sources"]}
        self.assertIn("oura", labels)
        self.assertIn("larq", labels)
        self.assertTrue(any("LARQ" in line or "water" in line.lower() for line in sources["lines"]))

        dashboard = body(handler(event("GET", "/dashboard/today"), None))
        self.assertEqual(dashboard["coach"], "ARIA")
        self.assertTrue(dashboard["readiness"].get("persisted") or dashboard["readiness"].get("overall"))
        self.assertIn(dashboard["decision"]["call"], {"train", "easy", "recover"})

    def test_low_sleep_forces_recover(self):
        handler(
            event(
                "POST",
                "/sleep/sessions",
                {"session": {"date": "2026-08-12", "source": "oura", "score": 48, "totalHours": 4.5}},
            ),
            None,
        )
        decision = body(handler(event("GET", "/today/decision"), None))
        self.assertEqual(decision["call"], "recover")
        self.assertIn("ARIA", decision["why"] + decision["coach"])

    def test_briefs_and_notifications_are_six_and_six(self):
        self._ingest()
        morning = body(handler(event("GET", "/today/brief", query={"slot": "morning"}), None))
        self.assertEqual(morning["title"], "ARIA · morning")
        evening = body(handler(event("GET", "/today/brief", query={"slot": "evening"}), None))
        self.assertIn("question", evening)
        notes = body(handler(event("GET", "/notifications/due"), None))
        hours = {n["slot"]: n["hour"] for n in notes["notifications"]}
        self.assertEqual(hours["morning"], 6)
        self.assertEqual(hours["evening"], 18)

    def test_adaptive_week_never_trains_when_recovering(self):
        handler(
            event(
                "POST",
                "/sleep/sessions",
                {"session": {"date": "2026-08-12", "source": "oura", "score": 40}},
            ),
            None,
        )
        plan = body(handler(event("GET", "/week/plan"), None))
        self.assertEqual(len(plan["days"]), 7)
        self.assertTrue(all(day["intent"] != "train" for day in plan["days"]))

    def test_watch_companion_and_water_log(self):
        self._ingest()
        snap = body(handler(event("GET", "/watch/companion"), None))
        self.assertEqual(snap["coach"], "ARIA")
        self.assertIn("complications", snap)
        logged = body(handler(event("POST", "/watch/log", {"type": "water", "value": 300}), None))
        self.assertGreaterEqual(logged["tracking"]["water"] or 0, 0)

    def test_household_and_partner_mindset_are_first_class(self):
        saved = body(
            handler(
                event(
                    "PUT",
                    "/household",
                    {
                        "members": [
                            {"id": "maya", "name": "Maya", "role": "partner"},
                            {"id": "priya", "name": "Priya", "role": "child", "earlyCycles": True},
                        ]
                    },
                ),
                None,
            )
        )
        self.assertEqual(len(saved["members"]), 2)
        child = cycle_partner.mindset(
            {"role": "child", "name": "Priya", "phase": "bleeding", "earlyCycles": True}
        )
        self.assertIn("First-year", child["headline"])
        self.assertFalse(any("welcome to womanhood" in line.lower() for line in child["doThis"]))
        self.assertTrue(any("womanhood" in line.lower() for line in child["notThis"]))
        partner = cycle_partner.mindset({"role": "partner", "name": "Maya", "phase": "bleeding"})
        self.assertIn("body under load", partner["mindset"])
        briefing = household.briefing_for_chat("test-user")
        self.assertIn("Priya", briefing)
        self.assertIn("Maya", briefing)
        self.assertNotIn("great", (briefing or "").lower())

    def test_evening_answer_does_not_close_weekly_review(self):
        from services import weekly_review

        handler(event("POST", "/today/brief/evening", {"answer": "Went for a walk instead."}), None)
        start = weekly_review.start("test-user")
        self.assertTrue(start["due"])
        self.assertTrue(any("walk" in str(f).lower() for f in start["facts"]))


if __name__ == "__main__":
    unittest.main()
