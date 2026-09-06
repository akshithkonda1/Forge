"""Vitals safety monitor — deterministic life-threatening-state detection.

During an active session Forge watches incoming vitals. If it detects a
plausibly real, life-threatening pattern — sustained severe hypoxemia, no
detectable heartbeat, or vitals lost while the device is still worn after a
normal baseline — it raises an ``EscalationIntent`` so the app can trigger
emergency escalation (Emergency SOS / a certified dispatch provider).

Two hard design constraints, because a false 911 call is its own harm:

  * Artifact rejection. Wearable SpO2/HR routinely glitch to 0 or absurd values
    from motion or lost skin contact. A physiologically implausible single
    reading (e.g. SpO2 0%/20%) is treated as *no reading*, never as a real
    measurement to act on. Escalation requires the danger to be *sustained*
    across several readings.
  * The backend never dials 911 itself. It decides and fires an intent through
    an injectable dispatcher. The real call belongs to a certified integration
    (RapidSOS / Apple Emergency SOS / carrier); the default dispatcher only
    records the intent so tests and dev never place real calls.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable

_log = logging.getLogger("forge.emergency")

# --- Thresholds (SpO2 as a fraction 0-1). Documented and tunable. -----------
WARNING_SPO2 = 0.90        # hypoxemia watch
CRITICAL_SPO2 = 0.80       # severe hypoxemia — escalate if valid AND sustained
# Readings at/below this floor are physiologically implausible as a *valid*
# measurement to act on; treat as sensor dropout, not a real 0%/20%.
MIN_PLAUSIBLE_SPO2 = 0.50

MIN_PLAUSIBLE_HR = 20      # bpm
MAX_PLAUSIBLE_HR = 240     # bpm

# How many consecutive dangerous readings make a pattern "sustained".
SUSTAINED_SAMPLES = 3

# Severity levels.
NONE = "none"
WARNING = "warning"
CRITICAL = "critical"

# Per-signal states.
_OK = "ok"
_WARN = "warning"
_CRIT = "critical"
_ABSENT = "absent"          # 0 with good contact (no pulse / no O2)
_NO_READING = "no_reading"  # None / lost contact / motion / implausible


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _norm_spo2(value: float | None) -> float | None:
    if value is None:
        return None
    v = float(value)
    return v / 100.0 if v > 1.5 else v  # accept 0-100% or 0-1 fraction


@dataclass
class VitalsSample:
    spo2: float | None = None          # fraction 0-1 (percent auto-normalized)
    heart_rate: float | None = None    # bpm
    at: datetime = field(default_factory=_utcnow)
    sensor_contact: bool | None = None  # True = on-body/good contact
    motion_artifact: bool | None = None

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> VitalsSample:
        at = data.get("at") or data.get("timestamp")
        parsed = _utcnow()
        if isinstance(at, datetime):
            parsed = at if at.tzinfo else at.replace(tzinfo=timezone.utc)
        elif isinstance(at, str) and at.strip():
            try:
                p = datetime.fromisoformat(at.strip().replace("Z", "+00:00"))
                parsed = p if p.tzinfo else p.replace(tzinfo=timezone.utc)
            except ValueError:
                parsed = _utcnow()

        def _num(key: str, *alts: str) -> float | None:
            for k in (key, *alts):
                if k in data and data[k] is not None:
                    try:
                        return float(data[k])
                    except (TypeError, ValueError):
                        return None
            return None

        def _bool(key: str) -> bool | None:
            return bool(data[key]) if key in data and data[key] is not None else None

        return cls(
            spo2=_num("spo2", "oxygen_saturation", "blood_oxygen"),
            heart_rate=_num("heart_rate", "hr", "bpm", "heartRate"),
            at=parsed,
            sensor_contact=_bool("sensor_contact"),
            motion_artifact=_bool("motion_artifact"),
        )

    def _trustworthy(self) -> bool:
        return not (self.sensor_contact is False or self.motion_artifact is True)

    def spo2_state(self) -> str:
        if self.spo2 is None or not self._trustworthy():
            return _NO_READING
        v = _norm_spo2(self.spo2)
        if v is None or v <= 0.0:
            return _ABSENT if self._trustworthy() and self.spo2 == 0 else _NO_READING
        if v < MIN_PLAUSIBLE_SPO2:
            return _NO_READING  # implausible as a valid reading — artifact
        if v < CRITICAL_SPO2:
            return _CRIT
        if v < WARNING_SPO2:
            return _WARN
        return _OK

    def hr_state(self) -> str:
        if self.heart_rate is None or not self._trustworthy():
            return _NO_READING
        hr = float(self.heart_rate)
        if hr == 0:
            return _ABSENT  # no pulse detected while worn
        if hr < MIN_PLAUSIBLE_HR or hr > MAX_PLAUSIBLE_HR:
            return _NO_READING
        return _OK

    def _plausible(self) -> bool:
        return self.hr_state() == _OK and self.spo2_state() in (_OK, _WARN, _CRIT)


@dataclass
class EmergencyAssessment:
    severity: str
    escalate: bool
    reasons: list[str] = field(default_factory=list)
    spo2_state: str = _NO_READING
    hr_state: str = _NO_READING
    sustained: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "severity": self.severity,
            "escalate": self.escalate,
            "reasons": self.reasons,
            "spo2_state": self.spo2_state,
            "hr_state": self.hr_state,
            "sustained_samples": self.sustained,
        }


def _tail(window: list[VitalsSample]) -> list[VitalsSample]:
    return window[-SUSTAINED_SAMPLES:]


def _fmt_pct(sample: VitalsSample) -> str:
    v = _norm_spo2(sample.spo2)
    return f"{round(v * 100)}%" if v is not None else "n/a"


def assess_vitals(
    window: list[VitalsSample],
    *,
    session_active: bool = True,
) -> EmergencyAssessment:
    """Assess the most-recent vitals window (oldest→newest) for a life threat.

    Escalation requires a *sustained* dangerous pattern (``SUSTAINED_SAMPLES``
    consecutive readings), never a single glitchy sample. The "vitals lost" and
    "no pulse" patterns additionally require a prior plausible baseline in the
    window, so a device that simply isn't reading doesn't trip a 911 call.
    """
    if not window:
        return EmergencyAssessment(NONE, False, ["no vitals provided"])

    latest = window[-1]
    s_state, h_state = latest.spo2_state(), latest.hr_state()
    tail = _tail(window)
    have_tail = len(tail) >= SUSTAINED_SAMPLES
    baseline = any(s._plausible() for s in window[:-1]) or any(s._plausible() for s in window)

    reasons: list[str] = []
    escalate = False
    severity = NONE

    if session_active and have_tail:
        # 1) Sustained, *valid* severe hypoxemia (0.50–0.80). No baseline needed —
        #    these are real measurements.
        if all(s.spo2_state() == _CRIT for s in tail):
            escalate = True
            severity = CRITICAL
            reasons.append(
                f"SpO2 critically low ({_fmt_pct(latest)}) across "
                f"{SUSTAINED_SAMPLES} readings"
            )
        # 2) No detectable heartbeat while the device is worn, after a baseline.
        if baseline and all(s.hr_state() == _ABSENT for s in tail):
            escalate = True
            severity = CRITICAL
            reasons.append(f"no heartbeat detected across {SUSTAINED_SAMPLES} readings")
        # 3) Vitals lost while still worn after a normal baseline (collapse
        #    pattern): sustained no-reading/absent on BOTH signals with contact.
        if baseline and all(
            s.spo2_state() in (_NO_READING, _ABSENT)
            and s.hr_state() in (_NO_READING, _ABSENT)
            and s.sensor_contact is not False
            for s in tail
        ):
            escalate = True
            severity = CRITICAL
            reasons.append("vitals lost while device still worn (possible collapse)")

    if not escalate:
        # Non-escalating warnings (surface, don't call).
        if s_state == _CRIT:
            severity = WARNING
            reasons.append(f"SpO2 low ({_fmt_pct(latest)}) — watching, not yet sustained")
        elif s_state == _WARN:
            severity = WARNING
            reasons.append(f"SpO2 below normal ({_fmt_pct(latest)})")
        elif h_state == _ABSENT:
            severity = WARNING
            reasons.append("single reading with no heartbeat — watching, not yet sustained")
        else:
            reasons.append("vitals within safe range" if s_state == _OK else "no actionable vitals")

    return EmergencyAssessment(
        severity=severity,
        escalate=escalate,
        reasons=reasons,
        spo2_state=s_state,
        hr_state=h_state,
        sustained=len(tail) if have_tail else len(window),
    )


@dataclass
class EscalationIntent:
    """An auditable decision to summon emergency help. Not a phone call — the
    signal a certified dispatch integration or the client's Emergency SOS acts on."""

    user_id: str
    reasons: list[str]
    severity: str
    at: datetime = field(default_factory=_utcnow)
    action: str = "Contact emergency services (911) and share the user's location."
    source: str = "forge-vitals-monitor"

    def to_dict(self) -> dict[str, Any]:
        return {
            "user_id": self.user_id,
            "reasons": self.reasons,
            "severity": self.severity,
            "at": self.at.isoformat(),
            "action": self.action,
            "source": self.source,
        }


Dispatcher = Callable[[EscalationIntent], None]


def default_dispatcher(intent: EscalationIntent) -> None:
    """SAFE default: record the intent, never place a real call.

    Replace with a certified integration (RapidSOS / Apple Emergency SOS /
    carrier) to actually dispatch. Wiring a live dialer here is intentionally
    out of scope — it requires regulatory approval and platform entitlements.
    """
    _log.critical("EMERGENCY ESCALATION INTENT: %s", intent.to_dict())


def maybe_escalate(
    assessment: EmergencyAssessment,
    *,
    user_id: str,
    dispatcher: Dispatcher | None = None,
    now: datetime | None = None,
) -> EscalationIntent | None:
    """Fire an escalation intent through the dispatcher when the assessment says so."""
    if not assessment.escalate:
        return None
    intent = EscalationIntent(
        user_id=user_id,
        reasons=list(assessment.reasons),
        severity=assessment.severity,
        at=now or _utcnow(),
    )
    (dispatcher or default_dispatcher)(intent)
    return intent
