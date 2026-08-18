"""Regression baselines + gate.

A baseline is a committed golden snapshot (per model) of the metrics that matter:
composite, grade, dimension averages, determinism, and the set of queries that
produced mission-critical failures. `compare` diffs a fresh run against it and
`gate` fails when the composite regresses past a threshold or a new
mission-critical failure appears.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass


def _safe(model_id: str) -> str:
    return re.sub(r"[./:-]", "_", model_id)


def record(model: dict, stability, diagnostic, determinism_rate) -> dict:
    """The golden snapshot for one model."""
    return {
        "model_id": model["model_id"],
        "tier": model["difficulty_tier"],
        "composite": stability.overall_composite,
        "grade": stability.overall_grade,
        "dimensions": stability.dimension_averages.as_dict(),
        "verdict": diagnostic.verdict,
        "system_passed": diagnostic.passed,
        "mission_critical_count": len(diagnostic.mission_critical),
        "mission_critical_queries": sorted({t.query for t in diagnostic.mission_critical}),
        "determinism_rate": determinism_rate,
    }


def save(records: list[dict], out_dir: str) -> list[str]:
    os.makedirs(out_dir, exist_ok=True)
    written: list[str] = []
    for rec in records:
        path = os.path.join(out_dir, _safe(rec["model_id"]) + ".json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(rec, fh, indent=2, sort_keys=True)
        written.append(path)
    return written


def load(in_dir: str) -> dict[str, dict]:
    out: dict[str, dict] = {}
    if not os.path.isdir(in_dir):
        return out
    for name in os.listdir(in_dir):
        if name.endswith(".json"):
            with open(os.path.join(in_dir, name), encoding="utf-8") as fh:
                rec = json.load(fh)
            if isinstance(rec, dict) and rec.get("model_id"):
                out[rec["model_id"]] = rec
    return out


@dataclass
class ModelDiff:
    model_id: str
    composite_delta: float
    grade_from: str
    grade_to: str
    new_mission_critical: list[str]
    resolved_mission_critical: list[str]
    determinism_delta: float
    missing_baseline: bool


def compare(current: list[dict], baseline: dict[str, dict]) -> list[ModelDiff]:
    diffs: list[ModelDiff] = []
    for rec in current:
        base = baseline.get(rec["model_id"])
        if base is None:
            diffs.append(ModelDiff(rec["model_id"], 0.0, "—", rec["grade"], [], [], 0.0, True))
            continue
        cur_mc = set(rec.get("mission_critical_queries", []))
        base_mc = set(base.get("mission_critical_queries", []))
        diffs.append(ModelDiff(
            model_id=rec["model_id"],
            composite_delta=round(rec["composite"] - base["composite"], 1),
            grade_from=base["grade"], grade_to=rec["grade"],
            new_mission_critical=sorted(cur_mc - base_mc),
            resolved_mission_critical=sorted(base_mc - cur_mc),
            determinism_delta=round((rec.get("determinism_rate") or 0) - (base.get("determinism_rate") or 0), 1),
            missing_baseline=False,
        ))
    return diffs


def gate(diffs: list[ModelDiff], max_drop: float) -> tuple[bool, list[str]]:
    """Pass unless a composite regresses past max_drop or a new mission-critical appears."""
    reasons: list[str] = []
    for d in diffs:
        if d.missing_baseline:
            continue
        if d.composite_delta < -max_drop:
            reasons.append(f"{d.model_id}: composite {d.composite_delta} (exceeds -{max_drop} drop)")
        if d.new_mission_critical:
            reasons.append(f"{d.model_id}: {len(d.new_mission_critical)} new mission-critical failure(s)")
    return (not reasons, reasons)


def write_comparison(diffs: list[ModelDiff], out_dir: str) -> str:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "comparison.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump([vars(d) for d in diffs], fh, indent=2)
    return path
