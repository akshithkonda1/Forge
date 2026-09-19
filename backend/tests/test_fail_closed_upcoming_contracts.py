"""Fail-closed gates ahead of RMSSD baseline versioning / memory edit.

TEST-ONLY. These lock the bar upcoming impl PRs must turn green. They do not
ship RMSSD versioning, user-facing delete-all, or editable persona.

Design (tip 0bde95e):
- classify.py aliases ``rmssd`` → MetricType.HRV_SDNN and has no HRV_RMSSD
  type. Personal baselines are keyed by MetricType (BodyModel.series) with no
  schema version, so RMSSD history would silently join the SDNN bucket.
  That classify API exists today, so the RMSSD identity test ASSERTS (it is
  allowed to be red on tip).
- forget_short_term + lifestyle-restricted memory-off already exist and stay
  locked here. User-facing delete-all / persona edit+clear do not exist, so
  those tests skip with an explicit fail-closed note until impl PRs add hooks
  and un-skip them.

Bedrock stays off. No AWS credentials. Stdlib unittest only.
"""

from __future__ import annotations

import json
import unittest
from datetime import datetime, timedelta, timezone

import _bootstrap  # noqa: F401

from services.aria_context import CoachContextEngine, UserContext  # noqa: E402
from services.biometrics import (  # noqa: E402
    BodyModel,
    MetricType,
    classify_sample,
    estimators,
)
from services.biometrics.classify import Reject  # noqa: E402
from services.biometrics.types import Observation  # noqa: E402
from services.fusion import PersonalBaselines  # noqa: E402
from services import contextual_learner  # noqa: E402
from storage import dynamodb  # noqa: E402
from routes.aria import handle_post_ai_chat  # noqa: E402

BASE = datetime(2026, 6, 10, tzinfo=timezone.utc)
USER = "fail-closed-user"


def _sample(**kw):
    kw.setdefault("timestamp", BASE.isoformat())
    return kw


def hrv_baseline_bucket(obs: Observation) -> tuple[str, str | None]:
    """Identity used for personal HRV baselines.

    RMSSD and SDNN must not collide. Distinct MetricType values satisfy this.
    A baseline_version on the observation (attribute or meta) is the other
    honest discriminator if an impl keeps one HRV metric type.
    """
    version = getattr(obs, "baseline_version", None)
    if version is None and isinstance(obs.meta, dict):
        version = obs.meta.get("baseline_version")
    return (obs.metric.value, None if version is None else str(version))


class RmssdMustNotShareSdnnBaselineTests(unittest.TestCase):
    """The honesty rift: ``rmssd`` currently aliases onto HRV_SDNN."""

    def test_sdnn_aliases_stay_hrv_sdnn(self):
        """Lock today's honest SDNN identity so versioning cannot rename it."""
        for ident in (
            "sdnn",
            "hrv_sdnn",
            "hrv",
            "HeartRateVariabilitySDNN",
            "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        ):
            with self.subTest(ident=ident):
                out = classify_sample(_sample(type=ident, value=50, unit="ms"))
                self.assertIsInstance(out, Observation, ident)
                self.assertEqual(out.metric, MetricType.HRV_SDNN, ident)
                self.assertEqual(out.unit, "ms")

    def test_unknown_hrv_family_member_is_rejected_not_coerced_to_sdnn(self):
        """pNN50 is a different HRV statistic. Silent SDNN mapping is a rift."""
        out = classify_sample(_sample(type="pnn50", value=20, unit="%"))
        self.assertIsInstance(out, Reject)
        self.assertNotIsInstance(out, Observation)

    def test_observation_preserves_metric_identity_and_source(self):
        out = classify_sample(
            _sample(type="sdnn", value=80, unit="ms", source="oura")
        )
        self.assertIsInstance(out, Observation)
        payload = out.to_dict()
        self.assertEqual(payload["metric"], "hrv_sdnn")
        self.assertEqual(payload["source"], "oura")
        self.assertEqual(payload["unit"], "ms")

    def test_body_model_keeps_distinct_metric_types_on_independent_series(self):
        """The versioning mechanism (per-MetricType series) already works.
        HEART_RATE must not land in the HRV_SDNN bucket."""
        hr = classify_sample(_sample(type="hr", value=60, unit="bpm"))
        hrv = classify_sample(_sample(type="sdnn", value=80, unit="ms"))
        self.assertIsInstance(hr, Observation)
        self.assertIsInstance(hrv, Observation)
        model = BodyModel().ingest_many([hr, hrv])
        self.assertEqual(len(model.series[MetricType.HEART_RATE]), 1)
        self.assertEqual(len(model.series[MetricType.HRV_SDNN]), 1)
        self.assertAlmostEqual(model.latest(MetricType.HEART_RATE), 60)
        self.assertAlmostEqual(model.latest(MetricType.HRV_SDNN), 80)
        self.assertNotEqual(hr.metric, hrv.metric)

    def test_personal_baselines_round_trip_is_deterministic(self):
        """Migration lock: to_dict/from_dict must not drop fields."""
        orig = PersonalBaselines(hrv=52.0, hrv_n=8, robust=True, recovery=61.0)
        restored = PersonalBaselines.from_dict(orig.to_dict())
        self.assertEqual(restored.to_dict(), orig.to_dict())
        self.assertEqual(restored.hrv, 52.0)
        self.assertEqual(restored.hrv_n, 8)

    def test_hrv_sdnn_estimator_names_the_metric_it_baselined(self):
        est = estimators.default_estimator(MetricType.HRV_SDNN).estimate(
            [50.0, 52.0, 48.0, 51.0]
        )
        self.assertEqual(est.name, MetricType.HRV_SDNN.value)
        self.assertIn("hrv_sdnn", est.name)
        self.assertNotIn("rmssd", est.name.lower())

    def test_rmssd_must_not_share_sdnn_personal_baseline_bucket(self):
        """KNOWN TIP-RED until the RMSSD versioning impl PR.

        Tip aliases ``rmssd`` → HRV_SDNN and rejects HealthKit RMSSD. Personal
        baselines then mix incompatible HRV families. Impl PRs must make every
        identifier in RMSSD_IDS classify as an Observation whose
        ``hrv_baseline_bucket`` differs from SDNN.
        """
        sdnn = classify_sample(_sample(type="sdnn", value=80, unit="ms", source="oura"))
        self.assertIsInstance(sdnn, Observation)
        sdnn_bucket = hrv_baseline_bucket(sdnn)

        rmssd_ids = (
            "rmssd",
            "hrv_rmssd",
            "HeartRateVariabilityRMSSD",
            "HKQuantityTypeIdentifierHeartRateVariabilityRMSSD",
        )
        for ident in rmssd_ids:
            with self.subTest(ident=ident):
                out = classify_sample(
                    _sample(type=ident, value=40, unit="ms", source="whoop")
                )
                self.assertIsInstance(
                    out,
                    Observation,
                    f"FAIL-CLOSED: {ident!r} must classify as RMSSD, not reject "
                    f"or coerce. Got {out!r}",
                )
                self.assertNotEqual(
                    hrv_baseline_bucket(out),
                    sdnn_bucket,
                    "FAIL-CLOSED: RMSSD must not be silently treated as SDNN "
                    "for personal baseline versioning. Distinct MetricType or a "
                    "baseline_version discriminator is required. "
                    f"{ident} bucket={hrv_baseline_bucket(out)!r} "
                    f"sdnn bucket={sdnn_bucket!r}",
                )

        model = BodyModel()
        model.ingest(sdnn)
        classified_rmssd = 0
        for ident in rmssd_ids:
            out = classify_sample(
                _sample(type=ident, value=40, unit="ms", source="whoop")
            )
            if isinstance(out, Observation):
                model.ingest(out)
                classified_rmssd += 1
        extra_in_sdnn = len(model.series.get(MetricType.HRV_SDNN, [])) - 1
        self.assertEqual(
            extra_in_sdnn,
            0,
            "FAIL-CLOSED: mixing RMSSD into HRV_SDNN history is the honesty rift "
            f"(classified_rmssd={classified_rmssd}, extra_in_sdnn={extra_in_sdnn})",
        )


class PrivacyDeleteOffAndPersonaTests(unittest.TestCase):
    """Existing forget/off stay locked; delete-all / persona edit skip until hooks."""

    def setUp(self):
        dynamodb.clear_local_store()
        self.engine = CoachContextEngine()

    def test_forget_short_term_does_not_wipe_long_term_life_facts(self):
        self.engine.record_life_fact(USER, "Training for a first 10k")
        item = self.engine.remember_short_term(USER, "Feeling stressed", now=BASE)
        self.assertIsNotNone(item)
        self.engine.forget_short_term(USER, item.id)
        self.assertEqual(self.engine.short_term_memories(USER, now=BASE), [])
        ctx = self.engine.get_or_create_context(USER)
        self.assertIn("Training for a first 10k", ctx.life_facts)

    def test_lifestyle_off_does_not_write_short_term_or_life_facts(self):
        uid = "lifestyle-off-fc"
        soon = (datetime.now(timezone.utc) + timedelta(days=10)).isoformat()
        result = handle_post_ai_chat(
            {
                "message": "hey, remember I have a wedding",
                "recent_metrics": {"readiness": 80},
                "permissions": {"deny": ["lifestyle"]},
                "calendar_events": [{"title": "Sister's wedding", "start": soon}],
            },
            user_id=uid,
        )
        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        self.assertEqual(body["calendar_ingested"], [])
        self.assertIsNone(body["memory"])
        engine = CoachContextEngine()
        self.assertEqual(engine.short_term_memories(uid), [])
        self.assertEqual(engine.get_or_create_context(uid).life_facts, [])
        block = engine.memory_prompt_block(uid).lower()
        self.assertNotIn("sister", block)
        self.assertNotIn("wedding", block)

    def test_user_context_round_trip_is_deterministic(self):
        ctx = UserContext(
            user_id=USER,
            life_facts=["Training for a first 10k"],
            lifestyle_tags=["calendar:evening:busy"],
            relationship_level=3,
        )
        restored = UserContext.from_dict(ctx.to_dict())
        self.assertEqual(restored.to_dict()["life_facts"], ctx.life_facts)
        self.assertEqual(restored.to_dict()["lifestyle_tags"], ctx.lifestyle_tags)
        self.assertEqual(restored.relationship_level, 3)

    def test_persona_save_load_round_trip_is_deterministic(self):
        uid = "persona-round-trip"
        state = contextual_learner.PersonaState()
        state.n_chat = 4
        state.relationship_level = 3
        contextual_learner.save(uid, state)
        loaded = contextual_learner.load(uid)
        self.assertEqual(loaded.n_chat, 4)
        self.assertEqual(loaded.relationship_level, 3)
        self.assertEqual(loaded.as_dict()["n_chat"], 4)

    def test_privacy_delete_all_memory_contract(self):
        """Skip until a user-facing delete-all hook exists; then it must wipe both tiers."""
        names = (
            "forget_all",
            "delete_all_memory",
            "wipe_memory",
            "clear_memory",
        )
        method = next((n for n in names if hasattr(CoachContextEngine, n)), None)
        if method is None:
            self.skipTest(
                "FAIL-CLOSED: user-facing privacy delete-all is not on "
                "CoachContextEngine yet. Impl PR must add one of "
                f"{names} and un-skip this test (wipe short-term + life_facts)."
            )
        self.engine.record_life_fact(USER, "Training for a first 10k")
        self.engine.remember_short_term(USER, "Feeling stressed", now=BASE)
        getattr(self.engine, method)(USER)
        self.assertEqual(self.engine.short_term_memories(USER, now=BASE), [])
        self.assertEqual(self.engine.get_or_create_context(USER).life_facts, [])
        self.assertEqual(self.engine.memory_prompt_block(USER, now=BASE), "")

    def test_persona_clear_contract(self):
        """Skip until clear/reset_persona exists; then it must return cold-start priors."""
        names = ("clear_persona", "reset_persona")
        fn = next((getattr(contextual_learner, n) for n in names if hasattr(contextual_learner, n)), None)
        if fn is None:
            self.skipTest(
                "FAIL-CLOSED: user-facing persona clear is not on contextual_learner "
                f"yet. Impl PR must add one of {names} and un-skip this test."
            )
        uid = "persona-clear-fc"
        state = contextual_learner.PersonaState()
        state.n_chat = 9
        state.relationship_level = 7
        contextual_learner.save(uid, state)
        fn(uid)
        wiped = contextual_learner.load(uid)
        self.assertEqual(wiped.n_chat, 0)
        self.assertEqual(wiped.n, 0)

    def test_persona_edit_contract(self):
        """Skip until edit/update_persona exists; then edits must persist and be clearable."""
        names = ("edit_persona", "update_persona")
        fn = next((getattr(contextual_learner, n) for n in names if hasattr(contextual_learner, n)), None)
        if fn is None:
            self.skipTest(
                "FAIL-CLOSED: user-facing persona edit is not on contextual_learner "
                f"yet. Impl PR must add one of {names} and un-skip this test."
            )
        uid = "persona-edit-fc"
        dynamodb.clear_local_store()
        try:
            fn(uid, relationship_level=4)
        except TypeError:
            fn(uid, {"relationship_level": 4})
        loaded = contextual_learner.load(uid)
        self.assertEqual(loaded.relationship_level, 4)


if __name__ == "__main__":
    unittest.main()
