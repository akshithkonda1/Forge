"""Respiratory/metabolic/BP vitals domain — payload parsing, interpretation,
BodyModel projection, permission redaction, and persistence round-trip."""

from __future__ import annotations

import datetime
import unittest

import _bootstrap  # noqa: F401

from services import aria_engine, fusion  # noqa: E402
from services.aria_engine import ARIAContext, DataPermissions, VitalsContext  # noqa: E402
from services.biometrics import BodyModel  # noqa: E402
from services.biometrics.types import MetricType, Observation  # noqa: E402


def _now():
    return datetime.datetime.now(datetime.timezone.utc)


class PayloadParsingTests(unittest.TestCase):
    def test_from_payload_parses_vitals_block(self):
        ctx = ARIAContext.from_payload({
            "context": {
                "vitals": {
                    "respiratoryRate": 18,
                    "oxygenSaturationPct": 97,
                    "bloodPressureSystolic": 118,
                    "bloodPressureDiastolic": 76,
                    "bloodGlucoseMgDl": 92,
                    "bodyTemperatureC": 36.8,
                }
            }
        })
        self.assertEqual(ctx.vitals.respiratory_rate, 18.0)
        self.assertEqual(ctx.vitals.oxygen_saturation_pct, 97.0)
        self.assertEqual(ctx.vitals.blood_pressure_systolic, 118.0)
        self.assertEqual(ctx.vitals.blood_pressure_diastolic, 76.0)
        self.assertEqual(ctx.vitals.blood_glucose_mg_dl, 92.0)
        self.assertEqual(ctx.vitals.body_temperature_c, 36.8)

    def test_derives_map_when_not_sent_explicitly(self):
        ctx = ARIAContext.from_payload({
            "context": {"vitals": {"bloodPressureSystolic": 118, "bloodPressureDiastolic": 76}}
        })
        self.assertEqual(ctx.vitals.mean_arterial_pressure, 90.0)

    def test_missing_vitals_stay_none(self):
        ctx = ARIAContext.from_payload({"context": {}})
        self.assertIsNone(ctx.vitals.respiratory_rate)
        self.assertFalse(ctx.has_vitals)
        self.assertIn("vitals.respiratory_rate", ctx.missing_fields)

    def test_has_vitals_true_with_any_one_signal(self):
        ctx = ARIAContext.from_payload({"context": {"vitals": {"bodyTemperatureC": 37.0}}})
        self.assertTrue(ctx.has_vitals)


class InterpreterTests(unittest.TestCase):
    def test_no_signal_when_all_vitals_missing(self):
        ctx = ARIAContext()
        signals = aria_engine._gather_signals(ctx)
        self.assertFalse(any(s.domain == "vitals" for s in signals))

    def test_normal_readings_yield_neutral_low_priority(self):
        ctx = ARIAContext(vitals=VitalsContext(
            respiratory_rate=15, oxygen_saturation_pct=98,
            blood_pressure_systolic=115, blood_pressure_diastolic=75,
            blood_glucose_mg_dl=90, body_temperature_c=36.7,
        ))
        signal = aria_engine._interpret_vitals(ctx)
        self.assertIsNotNone(signal)
        self.assertEqual(signal.direction, "neutral")
        self.assertEqual(signal.priority, "low")
        self.assertIn("typical range", signal.interpretation)

    def test_low_spo2_is_high_priority_negative(self):
        ctx = ARIAContext(vitals=VitalsContext(oxygen_saturation_pct=90))
        signal = aria_engine._interpret_vitals(ctx)
        self.assertEqual(signal.direction, "negative")
        self.assertEqual(signal.priority, "high")

    def test_low_glucose_is_high_priority(self):
        ctx = ARIAContext(vitals=VitalsContext(blood_glucose_mg_dl=60))
        signal = aria_engine._interpret_vitals(ctx)
        self.assertEqual(signal.priority, "high")
        self.assertIn("eat something", signal.interpretation)

    def test_elevated_bp_never_reads_as_a_diagnosis(self):
        """Suggest-not-prescribe: name the reading, never assert a condition."""
        ctx = ARIAContext(vitals=VitalsContext(
            blood_pressure_systolic=150, blood_pressure_diastolic=95,
        ))
        signal = aria_engine._interpret_vitals(ctx)
        text = signal.interpretation.lower()
        for banned in ("hypertension", "you have"):
            self.assertNotIn(banned, text)
        self.assertIn("clinician", text)
        self.assertIn("self-diagnose", text)  # explicitly disclaims, doesn't assert

    def test_fever_never_reads_as_a_diagnosis(self):
        ctx = ARIAContext(vitals=VitalsContext(body_temperature_c=39.1))
        signal = aria_engine._interpret_vitals(ctx)
        self.assertIn("fever", signal.interpretation.lower())
        self.assertNotIn("diagnos", signal.interpretation.lower())

    def test_focus_domain_recognizes_vitals_keywords(self):
        for q in ("how is my blood pressure?", "what's my oxygen saturation?", "check my vitals"):
            self.assertEqual(aria_engine._focus_domain(q), "vitals", q)

    def test_vitals_alone_makes_context_usable(self):
        """A context with only vitals data must not fall back to clarification."""
        ctx = ARIAContext(vitals=VitalsContext(blood_pressure_systolic=150, blood_pressure_diastolic=95))
        self.assertEqual(aria_engine.classify_request("how are my vitals?", ctx), "insight")


class GenerateResponseTests(unittest.TestCase):
    def test_generate_response_surfaces_vitals_insight(self):
        ctx = ARIAContext(vitals=VitalsContext(oxygen_saturation_pct=91, respiratory_rate=23))
        resp = aria_engine.generate_response("how are my vitals?", ctx)
        self.assertEqual(resp["response_type"], "insight")
        self.assertIn("SpO2", resp["prose_summary"])

    def test_restricted_vitals_never_reaches_the_prompt(self):
        ctx = ARIAContext(
            timestamp="2026-01-01T00:00:00+00:00",
            vitals=VitalsContext(blood_pressure_systolic=180, blood_pressure_diastolic=120),
        )
        block = ctx.user_model_block(restricted=["vitals"])
        self.assertNotRegex(block, r"(?<!\d)180(?!\d)")
        self.assertNotRegex(block, r"(?<!\d)120(?!\d)")
        self.assertNotIn("vitals.rule", block)


class BodyModelProjectionTests(unittest.TestCase):
    def test_projects_vitals_with_unit_conversion_and_map(self):
        obs = [
            Observation(metric=MetricType.RESPIRATORY_RATE, value=19, unit="breaths/min", timestamp=_now()),
            Observation(metric=MetricType.OXYGEN_SATURATION, value=0.97, unit="fraction", timestamp=_now()),
            Observation(metric=MetricType.BLOOD_PRESSURE_SYSTOLIC, value=118, unit="mmHg", timestamp=_now()),
            Observation(metric=MetricType.BLOOD_PRESSURE_DIASTOLIC, value=76, unit="mmHg", timestamp=_now()),
            Observation(metric=MetricType.BLOOD_GLUCOSE, value=92, unit="mg/dL", timestamp=_now()),
            Observation(metric=MetricType.BODY_TEMPERATURE, value=36.8, unit="celsius", timestamp=_now()),
        ]
        model = BodyModel.from_observations(obs, age_years=35, sex_female=False)
        ctx = model.to_aria_context()
        self.assertEqual(ctx.vitals.respiratory_rate, 19)
        self.assertEqual(ctx.vitals.oxygen_saturation_pct, 97.0)  # fraction -> pct
        self.assertEqual(ctx.vitals.blood_pressure_systolic, 118)
        self.assertEqual(ctx.vitals.mean_arterial_pressure, 90.0)  # 76 + (118-76)/3
        self.assertEqual(ctx.vitals.blood_glucose_mg_dl, 92)
        self.assertEqual(ctx.vitals.body_temperature_c, 36.8)

    def test_permission_denied_vitals_projects_nothing(self):
        obs = [Observation(metric=MetricType.BODY_TEMPERATURE, value=37.0, unit="celsius", timestamp=_now())]
        model = BodyModel.from_observations(obs)
        ctx = model.to_aria_context(DataPermissions({"vitals": False}))
        self.assertIsNone(ctx.vitals.body_temperature_c)

    def test_owned_domains_includes_vitals_when_present(self):
        obs = [Observation(metric=MetricType.OXYGEN_SATURATION, value=0.96, unit="fraction", timestamp=_now())]
        model = BodyModel.from_observations(obs)
        self.assertIn("vitals", fusion.owned_domains(model))


class PersistenceRoundTripTests(unittest.TestCase):
    """save_body_snapshot serializes via _BODY_DOMAINS; context_from_asdict must
    read every one of those domains back, vitals included, or a later turn with
    no fresh observations silently loses the prior vitals reading."""

    def test_vitals_survive_the_asdict_round_trip(self):
        ctx = ARIAContext(vitals=VitalsContext(
            respiratory_rate=17, oxygen_saturation_pct=96,
            blood_pressure_systolic=122, blood_pressure_diastolic=79,
            mean_arterial_pressure=93.3, blood_glucose_mg_dl=88, body_temperature_c=36.9,
        ))
        from dataclasses import asdict

        biometric = {domain: asdict(getattr(ctx, domain)) for domain in fusion._BODY_DOMAINS}
        biometric["timestamp"] = ctx.timestamp
        restored = fusion.context_from_asdict(biometric)
        self.assertEqual(restored.vitals, ctx.vitals)


if __name__ == "__main__":
    unittest.main()
