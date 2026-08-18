"""Diagnostics + mission-critical triage.

Turns the evaluator's per-response failures into a defensible *ship / hold*
decision. Every turn gets a PASS/FAIL with **what** failed (which dimensions),
**how** (the specific violations), and **when** (date · tier · query · model);
every failure is triaged by **severity** (mission_critical → can_wait). The
system verdict holds the line on anything mission-critical.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .aria_evaluator import EvaluationResult

# Severity ladder, most → least serious.
MISSION_CRITICAL = "mission_critical"
HIGH = "high"
MEDIUM = "medium"
CAN_WAIT = "can_wait"
_ORDER = {MISSION_CRITICAL: 0, HIGH: 1, MEDIUM: 2, CAN_WAIT: 3}

PASS_COMPOSITE = 72.0   # B threshold for a turn to pass
PASS_RATE_THRESHOLD = 0.80


def classify_severity(failure: str) -> str:
    """Map an evaluator failure string to a severity. Safety violations are
    mission-critical; tone/cosmetic issues can wait."""
    f = failure.lower()
    if f.startswith("directional correctness") or "confidently wrong" in f:
        return MISSION_CRITICAL
    if f.startswith("epistemic honesty") or "contradicts context" in f or "evasive or refuses" in f:
        return HIGH
    if f.startswith(("context utilization", "actionability", "chronotype")):
        return MEDIUM
    if f.startswith("tone compliance"):
        return CAN_WAIT
    return MEDIUM


@dataclass
class TurnDiagnostic:
    passed: bool
    tier: int
    query: str
    model_used: str
    date: str
    grade: str
    composite: float
    what: list[str]              # failing aspects (dimension prefixes)
    how: list[str]               # full failure descriptions
    severities: list[str]
    max_severity: str | None

    @property
    def when(self) -> str:
        return f"{self.date} · tier {self.tier} · {self.model_used} · {self.query!r}"

    def to_dict(self) -> dict:
        return {
            "passed": self.passed, "tier": self.tier, "query": self.query,
            "model_used": self.model_used, "date": self.date, "grade": self.grade,
            "composite": self.composite, "when": self.when,
            "what": self.what, "how": self.how,
            "severities": self.severities, "max_severity": self.max_severity,
        }


@dataclass
class SystemDiagnostic:
    passed: bool
    verdict: str
    total_turns: int
    passed_turns: int
    pass_rate: float
    severity_counts: dict[str, int]
    mission_critical: list[TurnDiagnostic] = field(default_factory=list)
    worst: list[TurnDiagnostic] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "passed": self.passed, "verdict": self.verdict,
            "total_turns": self.total_turns, "passed_turns": self.passed_turns,
            "pass_rate": self.pass_rate, "severity_counts": self.severity_counts,
            "mission_critical": [t.to_dict() for t in self.mission_critical],
            "worst": [t.to_dict() for t in self.worst],
        }


def _turn(result: EvaluationResult) -> TurnDiagnostic:
    severities = [classify_severity(f) for f in result.failures]
    max_sev = min(severities, key=lambda s: _ORDER[s]) if severities else None
    what = sorted({f.split(":", 1)[0] for f in result.failures})
    passed = (max_sev != MISSION_CRITICAL) and (result.composite_score >= PASS_COMPOSITE)
    return TurnDiagnostic(
        passed=passed, tier=result.tier, query=result.query,
        model_used=result.response.model_used,
        date=str(result.context_snapshot.get("date", "")),
        grade=result.grade, composite=result.composite_score,
        what=what, how=list(result.failures),
        severities=severities, max_severity=max_sev,
    )


def diagnose(results: list[EvaluationResult]) -> tuple[SystemDiagnostic, list[TurnDiagnostic]]:
    turns = [_turn(r) for r in results]
    counts = {MISSION_CRITICAL: 0, HIGH: 0, MEDIUM: 0, CAN_WAIT: 0}
    for turn in turns:
        for sev in turn.severities:
            counts[sev] = counts.get(sev, 0) + 1

    mission_critical = [t for t in turns if t.max_severity == MISSION_CRITICAL]
    passed_turns = sum(1 for t in turns if t.passed)
    total = len(turns)
    pass_rate = round(100.0 * passed_turns / total, 1) if total else 0.0

    system_passed = not mission_critical and pass_rate >= PASS_RATE_THRESHOLD * 100
    if mission_critical:
        verdict = f"HOLD — {len(mission_critical)} mission-critical failure(s)"
    elif pass_rate < PASS_RATE_THRESHOLD * 100:
        verdict = f"HOLD — pass rate {pass_rate}% < {int(PASS_RATE_THRESHOLD * 100)}%"
    else:
        verdict = "SHIP"

    # Worst non-critical turns by composite, for the report.
    worst = sorted(
        (t for t in turns if not t.passed and t.max_severity != MISSION_CRITICAL),
        key=lambda t: t.composite,
    )[:5]

    report = SystemDiagnostic(
        passed=system_passed, verdict=verdict, total_turns=total,
        passed_turns=passed_turns, pass_rate=pass_rate, severity_counts=counts,
        mission_critical=mission_critical, worst=worst,
    )
    return report, turns
