import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import _bootstrap  # noqa: F401

from services import aria_engine  # noqa: E402
from services.biometrics import (  # noqa: E402
    BodyModel,
    MetricType,
    classify_batch,
    classify_sample,
    estimators,
)
from services.biometrics import statistics as st  # noqa: E402
from services.biometrics.classify import Reject  # noqa: E402
from services.biometrics.types import Observation, System, spec  # noqa: E402

BASE = datetime(2026, 6, 10, tzinfo=timezone.utc)


def sample(**kw):
    kw.setdefault("timestamp", BASE.isoformat())
    return kw


class ClassificationTests(unittest.TestCase):
    def test_naming_conventions_collapse_to_one_type(self):
        for ident in ("heart-rate", "HKQuantityTypeIdentifierHeartRate", "hr", "BPM"):
            out = classify_sample(sample(type=ident, value=60, unit="bpm"))
            self.assertIsInstance(out, Observation, ident)
            self.assertEqual(out.metric, MetricType.HEART_RATE, ident)

    def test_unit_normalization(self):
        cases = [
            (sample(type="hrv", value=0.05, unit="s"), MetricType.HRV_SDNN, 50.0),
            (sample(type="glucose", value=5.0, unit="mmol/L"), MetricType.BLOOD_GLUCOSE, 90.091),
            (sample(type="weight", value=100, unit="lb"), MetricType.BODY_MASS, 45.3592),
            (sample(type="spo2", value=97, unit="%"), MetricType.OXYGEN_SATURATION, 0.97),
            (sample(type="temperature", value=98.6, unit="F"), MetricType.BODY_TEMPERATURE, 37.0),
            (sample(type="distance", value=5, unit="km"), MetricType.DISTANCE, 5000.0),
        ]
        for raw, metric, expected in cases:
            out = classify_sample(raw)
            self.assertIsInstance(out, Observation, raw)
            self.assertEqual(out.metric, metric)
            self.assertAlmostEqual(out.value, expected, places=2, msg=raw)
            self.assertEqual(out.unit, spec(metric).unit)  # normalized to canonical unit

    def test_out_of_range_is_rejected(self):
        self.assertIsInstance(classify_sample(sample(type="heart_rate", value=900, unit="bpm")), Reject)
        self.assertIsInstance(classify_sample(sample(type="spo2", value=0.2, unit="fraction")), Reject)

    def test_unknown_type_is_rejected_with_reason(self):
        out = classify_sample(sample(type="vibe_level", value=5))
        self.assertIsInstance(out, Reject)
        self.assertIn("unrecognized", out.reason)

    def test_sleep_stage_mapping(self):
        self.assertEqual(classify_sample(sample(type="sleep-stage", stage="deep", value=60)).metric, MetricType.SLEEP_DEEP)
        self.assertEqual(classify_sample(sample(type="sleep-stage", stage="rem", value=90)).metric, MetricType.SLEEP_REM)

    def test_batch_sorts_chronologically_and_counts(self):
        res = classify_batch([
            sample(type="hr", value=70, unit="bpm", timestamp=(BASE + timedelta(days=2)).isoformat()),
            sample(type="hr", value=60, unit="bpm", timestamp=BASE.isoformat()),
            sample(type="nope", value=1),
        ])
        self.assertEqual(res.counts, {"accepted": 2, "rejected": 1})
        self.assertEqual([o.value for o in res.observations], [60, 70])  # sorted by time


class StatisticsTests(unittest.TestCase):
    def test_robust_baseline_resists_outliers(self):
        base = st.robust_baseline([50, 51, 49, 50, 200])  # one wild outlier
        self.assertAlmostEqual(base.median, 50, places=0)
        self.assertTrue(base.is_anomaly(200))
        self.assertFalse(base.is_anomaly(51))

    def test_linear_trend_directions(self):
        self.assertEqual(st.linear_trend([1, 2, 3, 4, 5]).direction, "rising")
        self.assertEqual(st.linear_trend([5, 4, 3, 2, 1]).direction, "falling")
        self.assertEqual(st.linear_trend([3, 3, 3, 3]).direction, "flat")
        self.assertAlmostEqual(st.linear_trend([1, 2, 3, 4, 5]).r2, 1.0, places=6)

    def test_online_matches_batch(self):
        data = [2, 4, 4, 4, 5, 5, 7, 9]
        online = st.OnlineStat()
        for x in data:
            online.update(x)
        self.assertAlmostEqual(online.mean, st.mean(data), places=6)
        self.assertAlmostEqual(online.std, st.stdev(data), places=6)
        self.assertEqual(online.n, len(data))

    def test_coefficient_of_variation(self):
        self.assertAlmostEqual(st.coefficient_of_variation([10, 10, 10]), 0.0, places=6)
        self.assertGreater(st.coefficient_of_variation([1, 10, 100]), 0.5)


class EstimatorTests(unittest.TestCase):
    def test_physiological_formulas(self):
        self.assertAlmostEqual(estimators.mean_arterial_pressure(120, 80).value, 93.3, places=1)
        self.assertEqual(estimators.pulse_pressure(120, 80).value, 40)
        self.assertAlmostEqual(estimators.estimate_max_hr(30), 187.0, places=1)
        self.assertAlmostEqual(estimators.estimate_vo2max_from_rhr(30, 55).value, 52.0, places=0)

    def test_autonomic_stress_rises_when_hrv_drops(self):
        calm = estimators.autonomic_stress_index(60, 60).value
        stressed = estimators.autonomic_stress_index(40, 60).value
        self.assertGreater(stressed, calm)

    def test_recovery_fusion_reweights_on_missing_inputs(self):
        full = estimators.estimate_recovery(
            hrv_today=60, hrv_baseline=55, rhr_today=52, rhr_baseline=54,
            sleep_minutes=450, sleep_efficiency=0.9)
        partial = estimators.estimate_recovery(hrv_today=60, hrv_baseline=55)
        self.assertIsNotNone(full.value)
        self.assertIsNotNone(partial.value)
        self.assertGreater(full.confidence, partial.confidence)  # more signals → more confident

    def test_baseline_estimator_flags_anomaly_and_grows_confidence(self):
        est = estimators.default_estimator(MetricType.HEART_RATE)
        anomaly = est.estimate([60, 61, 59, 60, 62, 120])
        self.assertEqual(anomaly.state, "anomalous")
        few = est.estimate([60, 61]).confidence
        many = est.estimate([60, 61, 59, 60, 62, 61, 60, 59, 61, 60, 62, 60, 61, 59]).confidence
        self.assertGreater(many, few)


class _FakeBackend:
    def __init__(self, prediction=None, raises=False):
        self.prediction = prediction
        self.raises = raises
        self.calls = []

    def predict(self, metric, features):
        self.calls.append((metric, features))
        if self.raises:
            raise RuntimeError("inference exploded")
        return self.prediction


class ModelEstimatorTests(unittest.TestCase):
    def tearDown(self):
        from services.biometrics import reset_estimators
        reset_estimators()

    def test_model_prediction_is_used_when_backend_answers(self):
        from services.biometrics import ModelEstimator
        backend = _FakeBackend({"value": 99, "state": "modeled", "confidence": 0.91, "method": "model:test"})
        out = ModelEstimator(MetricType.HEART_RATE, backend).estimate([60, 61, 62])
        self.assertEqual(out.value, 99)
        self.assertEqual(out.method, "model:test")
        self.assertEqual(out.confidence, 0.91)
        self.assertTrue(backend.calls)

    def test_falls_back_when_backend_abstains_or_raises(self):
        from services.biometrics import ModelEstimator
        for backend in (_FakeBackend(None), _FakeBackend(raises=True)):
            out = ModelEstimator(MetricType.HEART_RATE, backend).estimate([60, 61, 62])
            self.assertEqual(out.method, "robust_baseline")  # graceful, deterministic fallback

    def test_enable_registers_and_body_model_uses_it_transparently(self):
        from services.biometrics import ModelEstimator, default_estimator, enable_model_estimators
        backend = _FakeBackend({"value": 123, "state": "modeled", "method": "model:test"})
        switched = enable_model_estimators(backend, metrics=[MetricType.HEART_RATE])
        self.assertIn(MetricType.HEART_RATE, switched)
        self.assertIsInstance(default_estimator(MetricType.HEART_RATE), ModelEstimator)
        snap = BodyModel.from_observations(
            [Observation(MetricType.HEART_RATE, 60, "bpm", BASE + timedelta(hours=h)) for h in range(4)]
        ).snapshot()
        self.assertEqual(snap.systems["cardiovascular"].metrics["heart_rate"].estimate.method, "model:test")

    def test_enable_is_noop_without_a_backend(self):
        from services.biometrics import enable_model_estimators
        self.assertEqual(enable_model_estimators(None), [])

    def test_feature_vector_exposes_expected_features(self):
        from services.biometrics import feature_vector
        feats = feature_vector(MetricType.HRV_SDNN, [50, 52, 48, 51])
        for key in ("latest", "mean", "ewma", "robust_z", "trend_slope", "n"):
            self.assertIn(key, feats)


class BodyModelTests(unittest.TestCase):
    def _observations(self):
        out = []
        for d in range(7):
            out.append(Observation(MetricType.HRV_SDNN, 55 + d, "ms", BASE + timedelta(days=d)))
            out.append(Observation(MetricType.RESTING_HEART_RATE, 56 - d * 0.2, "bpm", BASE + timedelta(days=d)))
        out.append(Observation(MetricType.SLEEP_DEEP, 70, "min", BASE))
        out.append(Observation(MetricType.SLEEP_DURATION, 450, "min", BASE))
        out.append(Observation(MetricType.BLOOD_PRESSURE_SYSTOLIC, 120, "mmHg", BASE))
        out.append(Observation(MetricType.BLOOD_PRESSURE_DIASTOLIC, 78, "mmHg", BASE))
        out.append(Observation(MetricType.STEPS, 9000, "count", BASE))
        return out

    def test_realtime_ingest_matches_batch_build(self):
        observations = self._observations()
        streamed = BodyModel(age_years=33)
        for o in observations:
            streamed.ingest(o)
        batched = BodyModel.from_observations(observations, age_years=33)
        self.assertEqual(
            streamed.snapshot().observation_count, batched.snapshot().observation_count
        )
        self.assertEqual(streamed.latest(MetricType.HRV_SDNN), batched.latest(MetricType.HRV_SDNN))

    def test_snapshot_reports_systems_and_cross_signal_derivations(self):
        snap = BodyModel.from_observations(self._observations(), age_years=33).snapshot()
        self.assertIn("cardiovascular", snap.systems)
        self.assertIn("autonomic", snap.systems)
        self.assertIn("mean_arterial_pressure", snap.derived)
        self.assertIn("recovery", snap.derived)
        self.assertIsNotNone(snap.derived["recovery"].value)

    def test_anomaly_surfaces_in_snapshot(self):
        observations = [Observation(MetricType.HEART_RATE, 60, "bpm", BASE + timedelta(hours=h)) for h in range(8)]
        observations.append(Observation(MetricType.HEART_RATE, 165, "bpm", BASE + timedelta(hours=9)))
        snap = BodyModel.from_observations(observations).snapshot()
        self.assertTrue(any(a["metric"] == "heart_rate" for a in snap.anomalies))

    def test_to_aria_context_projects_real_data(self):
        ctx = BodyModel.from_observations(self._observations(), age_years=33).to_aria_context()
        self.assertEqual(ctx.sleep.deep_minutes, 70)
        self.assertEqual(ctx.sleep.duration_minutes, 450)
        self.assertIsNotNone(ctx.readiness.recovery_score)
        self.assertIsNotNone(ctx.readiness.hrv_7day_trend)
        self.assertEqual(ctx.activity.steps_3day_avg, 9000)

    def test_to_aria_context_respects_permissions(self):
        perms = aria_engine.DataPermissions.from_payload({"activity": False})
        ctx = BodyModel.from_observations(self._observations(), age_years=33).to_aria_context(perms)
        self.assertIsNone(ctx.activity.steps_3day_avg)        # redacted
        self.assertIsNotNone(ctx.readiness.recovery_score)    # still populated


class PipelineIntegrationTests(unittest.TestCase):
    def test_raw_samples_flow_all_the_way_to_an_aria_response(self):
        raw = []
        for d in range(7):
            raw.append(sample(type="hrv", value=42 - d, unit="ms", source="oura",
                              timestamp=(BASE + timedelta(days=d)).isoformat()))
        raw.append(sample(type="resting-heart-rate", value=62, unit="bpm", source="apple-health"))
        raw.append(sample(type="sleep-stage", stage="deep", value=48, unit="min", source="oura"))
        raw.append(sample(type="sleep", value=430, unit="min", source="oura"))

        result = classify_batch(raw)
        self.assertGreaterEqual(result.counts["accepted"], 9)

        ctx = BodyModel.from_observations(result.observations, age_years=35).to_aria_context()
        resp = aria_engine.generate_response("how am I recovering?", ctx)

        self.assertIn(resp["response_type"], ("insight", "recommendation"))
        self.assertTrue(any(ch.isdigit() for ch in resp["prose_summary"]))  # references real data
        self.assertEqual(resp["schema_version"], aria_engine.SCHEMA_VERSION)


class ObserveRouteTests(unittest.TestCase):
    def setUp(self):
        import json
        from handler import handler
        from storage import dynamodb as ddb
        self._json = json
        self._handler = handler
        ddb.clear_local_store()

    def _post(self, path, body, *, as_user=None):
        """POST to a route, optionally as an authenticated principal.

        `/ai/observe` became an authenticated route, with identity taken from
        the JWT authorizer rather than the request body. These tests predate
        that and posted anonymously, which is why they failed two different ways
        depending on the environment: 401 locally (no principal at all) and 403
        in CI (FORGE_TEST_USER_ID supplies a principal, and the body's `user_id`
        then does not match it).

        Same authorizer shape as `tests/test_backend_handler.py`.
        """
        ev = {"requestContext": {"http": {"method": "POST", "path": path}},
              "body": self._json.dumps(body)}
        if as_user:
            ev["requestContext"]["authorizer"] = {"jwt": {"claims": {"sub": as_user}}}
        resp = self._handler(ev, None)
        return resp["statusCode"], self._json.loads(resp["body"])

    @staticmethod
    def _without_test_identity():
        """Context manager clearing the non-production auth escape hatches.

        `extract_user_id` falls back to FORGE_TEST_USER_ID outside production, so
        a test asserting that anonymous access is rejected has to remove that
        fallback or it silently asserts nothing.
        """
        import os
        from contextlib import contextmanager

        @contextmanager
        def _ctx():
            saved = {k: os.environ.pop(k, None)
                     for k in ("FORGE_TEST_USER_ID",
                               "FORGE_ALLOW_TEST_USER",
                               # The one that actually bit: other modules set
                               # this in setUp without clearing it, so it leaks
                               # across the suite and hands out an anonymous
                               # test user. A test asserting that anonymous
                               # access is refused has to remove all three or it
                               # passes while proving nothing.
                               "FORGE_ALLOW_ANON_TEST_USER")}
            try:
                yield
            finally:
                for k, v in saved.items():
                    if v is not None:
                        os.environ[k] = v

        return _ctx()

    def test_observe_classifies_models_and_answers(self):
        samples = [{"type": "hrv", "value": 40 - d, "unit": "ms", "source": "oura",
                    "timestamp": (BASE + timedelta(days=d)).isoformat()} for d in range(5)]
        samples += [
            {"type": "resting-heart-rate", "value": 60, "unit": "bpm", "source": "apple-health", "timestamp": BASE.isoformat()},
            {"type": "sleep", "value": 430, "unit": "min", "source": "oura", "timestamp": BASE.isoformat()},
            {"type": "made-up-metric", "value": 1, "timestamp": BASE.isoformat()},
        ]
        status, payload = self._post("/ai/observe", {
            "user_id": "obs-user", "age_years": 34, "samples": samples,
            "message": "how am I recovering?",
        }, as_user="obs-user")
        self.assertEqual(status, 200)
        self.assertEqual(payload["classification"]["accepted"], 7)
        self.assertEqual(payload["classification"]["rejected"], 1)
        self.assertIn("autonomic", payload["snapshot"]["systems"])
        self.assertIsNotNone(payload["aria_context"]["readiness"]["recovery_score"])
        self.assertEqual(payload["aria_response"]["schema_version"], aria_engine.SCHEMA_VERSION)

    def test_observe_fuses_stored_metrics_with_incoming(self):
        from storage import dynamodb as ddb, keys
        uid = "fuse-user"
        # Seed stored metrics directly, as /health/batch would have persisted them.
        for d in range(3):
            ts = (BASE + timedelta(days=d)).isoformat()
            ddb.put_item({**keys.metric_key(uid, "hrv", ts), "metricType": "hrv",
                          "value": 50, "unit": "ms", "source": "apple-health", "startedAt": ts})

        fused = self._post("/ai/observe", {
            "user_id": uid, "include_stored": True,
            "samples": [{"type": "hrv", "value": 48, "unit": "ms",
                         "timestamp": (BASE + timedelta(days=3)).isoformat()}]},
            as_user=uid)[1]
        self.assertEqual(fused["classification"]["accepted"], 4)  # 3 stored + 1 incoming

        incoming_only = self._post("/ai/observe", {
            "user_id": uid, "include_stored": False,
            "samples": [{"type": "hrv", "value": 48, "unit": "ms", "timestamp": BASE.isoformat()}]},
            as_user=uid)[1]
        self.assertEqual(incoming_only["classification"]["accepted"], 1)

    def test_observe_rejects_anonymous_requests(self):
        # Replaces `test_observe_requires_user_id`, whose premise is gone: the
        # body no longer has to carry a user_id, because identity comes from the
        # token. What must hold now is that no identity at all is refused.
        with self._without_test_identity():
            status, _ = self._post("/ai/observe", {"samples": []})
        self.assertIn(status, (401, 403), f"anonymous access returned {status}")

    def test_observe_binds_to_the_token_identity_when_body_omits_it(self):
        status, payload = self._post(
            "/ai/observe",
            {"samples": [{"type": "hrv", "value": 48, "unit": "ms",
                          "timestamp": BASE.isoformat()}]},
            as_user="token-user")
        self.assertEqual(status, 200)
        self.assertEqual(payload["classification"]["accepted"], 1)

    def test_observe_refuses_a_body_claiming_another_user(self):
        # The privilege-escalation guard `assert_body_user_matches_auth` exists
        # for, and which had no test on this route. A client that authenticates
        # as one principal must not be able to read or write as another by
        # putting a different id in the body.
        status, _ = self._post("/ai/observe",
                               {"user_id": "someone-else", "samples": []},
                               as_user="token-user")
        self.assertEqual(status, 403)


if __name__ == "__main__":
    unittest.main()
