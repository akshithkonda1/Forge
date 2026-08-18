"""Report builder — narrative text + JSON, written to reports/."""

from __future__ import annotations

import datetime
import json
import os
from dataclasses import asdict

from .aria_evaluator import EvaluationResult
from .determinism_checker import DeterminismReport
from .stability_analyzer import StabilityReport


def _timestamp() -> str:
    """Pinned run timestamp when SIMRUNNER_TODAY is set (reproducible reports),
    otherwise the real wall-clock time."""
    pinned = os.getenv("SIMRUNNER_TODAY")
    if pinned:
        try:
            datetime.date.fromisoformat(pinned)
            return f"{pinned}T00:00:00"
        except ValueError:
            pass
    return datetime.datetime.now().isoformat(timespec="seconds")


def _label(score: float) -> str:
    if score >= 80:
        return "pass"
    if score >= 65:
        return "needs work"
    return "failing"


def _dim_line(name: str, score: float) -> str:
    return f"{name:<25}{score:>5.1f} — {_label(score)}"


def build_narrative(
    model: dict,
    stability: StabilityReport,
    determinism: DeterminismReport | None,
    timestamp: str,
    engine_model: str = "stub",
    diagnostic=None,
    multiseed: dict | None = None,
) -> str:
    d = stability.dimension_averages
    lines: list[str] = []
    add = lines.append

    add("ARIA SimRunner — Evaluation Report")
    add("=" * 35)
    add(f"Model Under Test: {model['display_name']} (Tier {model['difficulty_tier']})")
    add(f"Coaching Challenge: {model['coaching_challenge']}")
    add(f"Run Date: {timestamp}")
    add(f"Total Evaluations: {stability.total_runs}")
    add("")
    add(f"OVERALL GRADE: {stability.overall_grade}")
    add(f"Composite Score: {stability.overall_composite}/100")
    add("")

    if diagnostic is not None:
        sc = diagnostic.severity_counts
        add("━━━ DIAGNOSTICS — VERDICT ━━━━━━━━━━━━━━━")
        add(f"  {'✅' if diagnostic.passed else '⛔'} {diagnostic.verdict}")
        add(f"  Turns passed: {diagnostic.passed_turns}/{diagnostic.total_turns} ({diagnostic.pass_rate}%)")
        add(f"  Severity: mission_critical {sc['mission_critical']} · high {sc['high']} · "
            f"medium {sc['medium']} · can_wait {sc['can_wait']}")
        if diagnostic.mission_critical:
            add("  Mission-critical (fix before ship) — what / how / when:")
            for t in diagnostic.mission_critical[:10]:
                add(f"    ✗ {t.when}")
                for how in t.how:
                    add(f"        - {how}")
        if diagnostic.worst:
            add("  Worst non-critical turns:")
            for t in diagnostic.worst:
                add(f"    · {t.composite}/100 [{', '.join(t.what) or 'low composite'}] — {t.when}")
        add("")

    add("━━━ CRITICAL FAILURES ━━━━━━━━━━━━━━━━━━━")
    if stability.critical_failures:
        for failure in stability.critical_failures:
            add(f"  ✗ {failure}")
    else:
        add("  No critical failures detected.")
    add("")

    add("━━━ DIMENSION BREAKDOWN ━━━━━━━━━━━━━━━━━")
    add(_dim_line("Context Utilization:", d.context_utilization))
    add(_dim_line("Directional Correctness:", d.directional_correctness))
    add(_dim_line("Chronotype Alignment:", d.chronotype_alignment))
    add(_dim_line("Actionability:", d.actionability))
    add(_dim_line("Epistemic Honesty:", d.epistemic_honesty))
    add(_dim_line("Tone Compliance:", d.tone_compliance))
    add("")

    if multiseed:
        c = multiseed["composite"]
        add("━━━ STATISTICAL CONFIDENCE (multi-seed) ━")
        add(f"  Seeds: {multiseed['seed_count']}")
        add(f"  Composite: {c.mean} ± {c.stdev}  [{c.min}–{c.max}]  p10–p90 {c.p10}–{c.p90}  "
            f"{'stable' if c.stable else 'UNSTABLE (high variance)'}")
        for dim, dist in multiseed["dimensions"].items():
            flag = "" if dist.stable else "  ⚠ unstable"
            add(f"    {dim:<24} {dist.mean} ± {dist.stdev}{flag}")
        add("")

    add("━━━ BY DIFFICULTY TIER ━━━━━━━━━━━━━━━━━")
    for tier in sorted(stability.by_tier):
        s = stability.by_tier[tier]
        add(f"Tier {tier}: {s.grade}  ({s.pass_rate}% pass rate, {s.run_count} runs, {s.failure_count} below B)")
    add("")

    add("━━━ TOP FAILURE PATTERNS ━━━━━━━━━━━━━━━")
    if stability.top_failure_patterns:
        for i, pattern in enumerate(stability.top_failure_patterns, 1):
            add(f"  {i}. {pattern}")
    else:
        add("  None.")
    add("")

    add("━━━ WHAT NEEDS TO CHANGE ━━━━━━━━━━━━━━━")
    if stability.top_recommendations:
        for i, rec in enumerate(stability.top_recommendations, 1):
            add(f"  {i}. {rec}")
    else:
        add("  Nothing pressing — maintain current behavior.")
    add("")

    add("━━━ DETERMINISM ━━━━━━━━━━━━━━━━━━━━━━━")
    if determinism is None:
        add("  Skipped — real-API mode is non-deterministic (see multi-seed variance above).")
    else:
        add(f"Semantic Determinism Rate: {determinism.semantic_determinism_rate}%  "
            f"({determinism.sample_count} prompts × {determinism.runs_per_sample} runs)")
        if determinism.inconsistent:
            add("  Inconsistent prompts:")
            for item in determinism.inconsistent:
                add(f"    - {item}")
        else:
            add("  All sampled prompts were semantically stable.")
    add("")

    add("━━━ MODELS USED (harness engine) ━━━━━━━━")
    add(f"Engine: {engine_model}")
    if stability.models_used:
        for model_id, count in sorted(stability.models_used.items(), key=lambda kv: (-kv[1], kv[0])):
            add(f"  {model_id:<42} ×{count}")
    else:
        add("  (none)")
    add("")

    add(f"Consumer Stability Grade:  {stability.consumer_stability_grade}")
    add(f"Epistemic Rigor Grade:     {stability.epistemic_rigor_grade}")
    add("")
    return "\n".join(lines)


def _multiseed_json(multiseed: dict | None) -> dict | None:
    if not multiseed:
        return None
    return {
        "seed_count": multiseed["seed_count"],
        "composite": vars(multiseed["composite"]),
        "dimensions": {k: vars(v) for k, v in multiseed["dimensions"].items()},
    }


def build_json(
    model: dict,
    stability: StabilityReport,
    determinism: DeterminismReport | None,
    results: list[EvaluationResult],
    timestamp: str,
    engine_model: str = "stub",
    diagnostic=None,
    multiseed: dict | None = None,
) -> dict:
    return {
        "model": {
            "model_id": model["model_id"],
            "display_name": model["display_name"],
            "difficulty_tier": model["difficulty_tier"],
            "coaching_challenge": model["coaching_challenge"],
            "derived": bool(model.get("derived")),
        },
        "engine_model": engine_model,
        "models_used": stability.models_used,
        "run_date": timestamp,
        "overall": {
            "composite": stability.overall_composite,
            "grade": stability.overall_grade,
            "consumer_stability_grade": stability.consumer_stability_grade,
            "epistemic_rigor_grade": stability.epistemic_rigor_grade,
        },
        "dimension_averages": stability.dimension_averages.as_dict(),
        "by_tier": {str(t): asdict(s) for t, s in stability.by_tier.items()},
        "critical_failures": stability.critical_failures,
        "top_failure_patterns": stability.top_failure_patterns,
        "top_recommendations": stability.top_recommendations,
        "determinism": asdict(determinism) if determinism is not None else None,
        "diagnostics": diagnostic.to_dict() if diagnostic is not None else None,
        "multiseed": _multiseed_json(multiseed),
        "evaluations": [asdict(r) for r in results],
    }


def _safe(model_id: str) -> str:
    # Mirror model_registry._sanitize_id. Bedrock ids contain ':' (e.g. v1:0).
    for ch in (".", "/", "-", ":"):
        model_id = model_id.replace(ch, "_")
    return model_id


def save_reports(
    model: dict,
    stability: StabilityReport,
    determinism: DeterminismReport | None,
    results: list[EvaluationResult],
    out_dir: str,
    report_format: str = "both",
    engine_model: str = "stub",
    diagnostic=None,
    multiseed: dict | None = None,
) -> list[str]:
    os.makedirs(out_dir, exist_ok=True)
    timestamp = _timestamp()
    stem = os.path.join(out_dir, _safe(model["model_id"]))
    written: list[str] = []

    if report_format in ("text", "both"):
        path = stem + ".txt"
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(build_narrative(model, stability, determinism, timestamp, engine_model, diagnostic, multiseed))
        written.append(path)
    if report_format in ("json", "both"):
        path = stem + ".json"
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(build_json(model, stability, determinism, results, timestamp, engine_model, diagnostic, multiseed),
                      fh, indent=2, default=str)
        written.append(path)
    return written


def matrix_diagnostics(summaries: list[dict]) -> dict:
    """Per-model-archetype SHIP/HOLD rates + failure pattern rollup.

    Matrix runs (user archetypes × model archetypes) produce one record per
    pair. This collapses that grid into a clear production gate view without
    requiring an LLM-as-judge.
    """
    by_arch: dict[str, dict] = {}
    pattern_counts: dict[str, int] = {}

    for rec in summaries:
        arch_id = str(rec.get("model_archetype") or "baseline")
        arch_name = str(rec.get("model_archetype_name") or arch_id)
        bucket = by_arch.setdefault(
            arch_id,
            {
                "model_archetype": arch_id,
                "model_archetype_name": arch_name,
                "bedrock_model_id": rec.get("bedrock_model_id"),
                "runs": 0,
                "ship": 0,
                "hold": 0,
                "mission_critical_total": 0,
                "composites": [],
                "user_models_held": [],
                "failure_patterns": {},
            },
        )
        bucket["runs"] += 1
        if rec.get("system_passed"):
            bucket["ship"] += 1
        else:
            bucket["hold"] += 1
            mid = rec.get("model_id")
            if mid:
                bucket["user_models_held"].append(mid)
        bucket["mission_critical_total"] += int(rec.get("mission_critical_count") or 0)
        if rec.get("composite") is not None:
            bucket["composites"].append(float(rec["composite"]))

        # Optional richer pattern lists from full report payloads.
        for pattern in rec.get("top_failure_patterns") or []:
            bucket["failure_patterns"][pattern] = bucket["failure_patterns"].get(pattern, 0) + 1
            pattern_counts[pattern] = pattern_counts.get(pattern, 0) + 1

        for q in rec.get("mission_critical_queries") or []:
            key = f"mission_critical:{q}"
            bucket["failure_patterns"][key] = bucket["failure_patterns"].get(key, 0) + 1
            pattern_counts[key] = pattern_counts.get(key, 0) + 1

    archetypes = []
    for arch_id, b in sorted(by_arch.items(), key=lambda kv: (-kv[1]["hold"], kv[0])):
        runs = max(1, b["runs"])
        comps = b["composites"]
        top_patterns = sorted(b["failure_patterns"].items(), key=lambda kv: -kv[1])[:8]
        archetypes.append(
            {
                "model_archetype": b["model_archetype"],
                "model_archetype_name": b["model_archetype_name"],
                "bedrock_model_id": b["bedrock_model_id"],
                "runs": b["runs"],
                "ship": b["ship"],
                "hold": b["hold"],
                "ship_rate": round(100.0 * b["ship"] / runs, 1),
                "hold_rate": round(100.0 * b["hold"] / runs, 1),
                "mission_critical_total": b["mission_critical_total"],
                "avg_composite": round(sum(comps) / len(comps), 1) if comps else None,
                "user_models_held": sorted(set(b["user_models_held"])),
                "top_failure_patterns": [
                    {"pattern": p, "count": c} for p, c in top_patterns
                ],
            }
        )

    total = len(summaries)
    ships = sum(1 for r in summaries if r.get("system_passed"))
    holds = total - ships
    global_patterns = sorted(pattern_counts.items(), key=lambda kv: -kv[1])[:12]

    return {
        "total_runs": total,
        "ship": ships,
        "hold": holds,
        "ship_rate": round(100.0 * ships / total, 1) if total else 0.0,
        "hold_rate": round(100.0 * holds / total, 1) if total else 0.0,
        "by_model_archetype": archetypes,
        "top_failure_patterns": [
            {"pattern": p, "count": c} for p, c in global_patterns
        ],
    }


def print_matrix_diagnostics(diag: dict) -> None:
    """Human-readable matrix gate board for CI / local runs."""
    print("Matrix diagnostics — model-archetype SHIP/HOLD board")
    print(
        f"  total {diag.get('total_runs', 0)} runs · "
        f"SHIP {diag.get('ship', 0)} ({diag.get('ship_rate', 0)}%) · "
        f"HOLD {diag.get('hold', 0)} ({diag.get('hold_rate', 0)}%)"
    )
    for row in diag.get("by_model_archetype") or []:
        mark = "✅" if row["hold"] == 0 else "⛔"
        avg = row.get("avg_composite")
        avg_s = f"{avg}/100" if avg is not None else "n/a"
        print(
            f"  {mark} {row['model_archetype_name']:<28} "
            f"ship {row['ship_rate']:>5}%  hold {row['hold_rate']:>5}%  "
            f"avg {avg_s}  mc={row['mission_critical_total']}  runs={row['runs']}"
        )
        if row.get("top_failure_patterns"):
            top = ", ".join(
                f"{p['pattern']}×{p['count']}" for p in row["top_failure_patterns"][:3]
            )
            print(f"      patterns: {top}")
    if diag.get("top_failure_patterns"):
        print("  global failure patterns:")
        for p in diag["top_failure_patterns"][:8]:
            print(f"    · {p['pattern']}  (×{p['count']})")


def save_combined_summary(summaries: list[dict], out_dir: str) -> str:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "_combined_summary.json")
    payload = {
        "run_date": _timestamp(),
        "models_tested": len(summaries),
        "summaries": summaries,
    }
    # Always attach matrix diagnostics when there is more than one record so
    # --matrix / --matrix-bedrock produce a clear per-archetype gate board.
    if len(summaries) > 1:
        payload["matrix_diagnostics"] = matrix_diagnostics(summaries)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, default=str)
    return path
