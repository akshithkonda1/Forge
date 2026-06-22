"""ARIA SimRunner — single entry point.

Runs the full offline pipeline against one archetype, a tier, or all 20:

    python -m backend.simrunner                       # tier 1 (fast sanity)
    python -m backend.simrunner --model <model_id>
    python -m backend.simrunner --tier 3
    python -m backend.simrunner --all
"""

from __future__ import annotations

import argparse
import os
import re

from .aria_simrunner import _stats, baseline, diagnostics, report_builder
from .aria_simrunner.aria_engine import ARIAEngine
from .aria_simrunner.aria_evaluator import DimensionScores, evaluate
from .aria_simrunner.aria_generator import get_queries_for_tier
from .aria_simrunner.determinism_checker import check_determinism
from .aria_simrunner.stability_analyzer import analyze
from .backend_simulator import bedrock_catalog, model_registry
from .backend_simulator.behavior_engine import generate_stream
from .backend_simulator.data_generator import build_context

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPORTS_DIR = os.path.join(_HERE, "reports")
_BASELINES_DIR = os.path.join(_HERE, "baselines")
_CONFIG_PATH = os.path.join(_HERE, "sim_config.yaml")
_DIM_NAMES = list(DimensionScores.WEIGHTS)

_DEFAULTS = {
    "seed": 42,
    "seed_count": 1,
    "snapshot_days": [7, 14, 21, 29],
    "determinism_sample_size": 5,
    "use_real_api": False,
    "report_format": "both",
    "engine_model": None,
    "engine_models": None,
    "gate_max_drop": 3.0,
}


# --- minimal YAML subset loader (stdlib only) -------------------------------

def _parse_scalar(s: str):
    s = s.strip()
    if s.lower() in ("true", "false"):
        return s.lower() == "true"
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    if re.fullmatch(r"-?\d+\.\d+", s):
        return float(s)
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        return [_parse_scalar(x) for x in inner.split(",")] if inner else []
    return s.strip("\"'")


def _parse_yaml(text: str) -> dict:
    root: dict = {}
    nested: dict | None = None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        key, _, val = line.strip().partition(":")
        key = key.strip()
        if indent == 0:
            if val.strip() == "":
                nested = {}
                root[key] = nested
            else:
                root[key] = _parse_scalar(val)
                nested = None
        elif nested is not None:
            nested[key] = _parse_scalar(val)
    return root


def _validate_config(config: dict) -> dict:
    """Coerce types and clamp ranges so a malformed sim_config.yaml never crashes
    a run or produces nonsense — fall back to the default for any bad value."""
    out = dict(_DEFAULTS)
    out.update(config)

    try:
        out["seed"] = int(out.get("seed", 42))
    except (TypeError, ValueError):
        out["seed"] = 42

    days = out.get("snapshot_days", _DEFAULTS["snapshot_days"])
    if not isinstance(days, (list, tuple)):
        days = _DEFAULTS["snapshot_days"]
    clean = sorted({int(d) for d in days if isinstance(d, (int, float)) and 0 <= int(d) <= 29})
    out["snapshot_days"] = clean or list(_DEFAULTS["snapshot_days"])

    try:
        out["determinism_sample_size"] = max(1, int(out.get("determinism_sample_size", 5)))
    except (TypeError, ValueError):
        out["determinism_sample_size"] = 5

    if out.get("report_format") not in ("text", "json", "both"):
        out["report_format"] = "both"
    out["use_real_api"] = bool(out.get("use_real_api", False))

    em = out.get("engine_model")
    out["engine_model"] = str(em) if em and str(em).strip().lower() not in ("none", "null", "") else None
    ems = out.get("engine_models")
    out["engine_models"] = {str(k): str(v) for k, v in ems.items()} if isinstance(ems, dict) else None

    try:
        out["seed_count"] = max(1, int(out.get("seed_count", 1)))
    except (TypeError, ValueError):
        out["seed_count"] = 1
    try:
        out["gate_max_drop"] = max(0.0, float(out.get("gate_max_drop", 3.0)))
    except (TypeError, ValueError):
        out["gate_max_drop"] = 3.0
    return out


def load_config(path: str = _CONFIG_PATH) -> dict:
    config = dict(_DEFAULTS)
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as fh:
                config.update({k: v for k, v in _parse_yaml(fh.read()).items() if v is not None})
        except OSError:
            pass
    if os.getenv("USE_REAL_API", "").lower() == "true":
        config["use_real_api"] = True
    env_model = os.getenv("SIMRUNNER_ENGINE_MODEL")
    if env_model:
        config["engine_model"] = env_model
    return _validate_config(config)


# --- pipeline ---------------------------------------------------------------

def _eval_seed(model: dict, config: dict, engine: ARIAEngine, seed: int):
    """Run the full snapshot × query eval loop for one seed.

    Returns (results, contexts, snapshot_days, queries, stream). Each seed is
    deterministic; variance across seeds is what multi-seed confidence measures.
    """
    profile = model["behavioral_profile"]
    tier = model["difficulty_tier"]

    stream = generate_stream(profile, seed=seed)
    snapshot_days = [d for d in config["snapshot_days"] if 0 <= d < len(stream)]
    queries = get_queries_for_tier(tier)
    contexts = {day: build_context(stream, profile, day) for day in snapshot_days}

    results = []
    run_id = 0
    for day in snapshot_days:
        context = contexts[day]
        for query in queries:
            response = engine.respond(query, context, seed=seed)
            results.append(evaluate(run_id, query, tier, context, response))
            run_id += 1
    return results, contexts, snapshot_days, queries, stream


def run_model(model: dict, config: dict, engine: ARIAEngine) -> dict:
    profile = model["behavioral_profile"]
    tier = model["difficulty_tier"]
    seed = int(config["seed"])
    seed_count = int(config["seed_count"])

    # Each seed is deterministic; multi-seed spreads variance for confidence bands.
    runs = []           # one StabilityReport per seed
    primary = None      # (results, contexts, snapshot_days, queries, stream) for seed[0]
    for i in range(seed_count):
        artifacts = _eval_seed(model, config, engine, seed + i)
        runs.append(analyze(artifacts[0]))
        if i == 0:
            primary = artifacts

    primary_results, contexts, snapshot_days, queries, stream = primary
    stability = runs[0]
    diagnostic, _turns = diagnostics.diagnose(primary_results)

    multiseed = None
    if seed_count > 1:
        multiseed = {
            "seed_count": seed_count,
            "composite": _stats.summarize([r.overall_composite for r in runs]),
            "dimensions": {
                dim: _stats.summarize([getattr(r.dimension_averages, dim) for r in runs])
                for dim in _DIM_NAMES
            },
        }

    # Determinism is a stub-engine property; under real-API it's non-deterministic,
    # so we skip the check and let multi-seed variance (above) carry confidence.
    determinism = None
    if not config["use_real_api"]:
        sample_n = int(config["determinism_sample_size"])
        sample_ctx = contexts[max(snapshot_days)] if snapshot_days else build_context(stream, profile)
        samples = [(tier, q, sample_ctx) for q in queries[:sample_n]]
        determinism = check_determinism(engine, samples, seed=seed)

    engine_model = engine.detect_model()
    paths = report_builder.save_reports(
        model, stability, determinism, primary_results, _REPORTS_DIR, config["report_format"],
        engine_model=engine_model, diagnostic=diagnostic, multiseed=multiseed,
    )

    det_rate = determinism.semantic_determinism_rate if determinism else None
    det_str = f"{det_rate}%" if det_rate is not None else "skipped (real-API)"

    label = model["display_name"] + ("  [derived]" if model.get("derived") else "")
    mark = "✅" if diagnostic.passed else "⛔"
    print(f"  {label}")
    print(f"    Grade {stability.overall_grade}  ({stability.overall_composite}/100)  "
          f"· {stability.total_runs} evals · determinism {det_str}")
    print(f"    verdict: {mark} {diagnostic.verdict}  ·  pass rate {diagnostic.pass_rate}%")
    if multiseed:
        c = multiseed["composite"]
        print(f"    multi-seed: {c.mean} ± {c.stdev} over {seed_count} seeds "
              f"({'stable' if c.stable else 'UNSTABLE — high variance'})")
    print(f"    engine: {engine_model}")
    if diagnostic.mission_critical:
        print(f"    ⛔ {len(diagnostic.mission_critical)} mission-critical failure(s) — must fix before ship")
    elif stability.critical_failures:
        print(f"    ⚠ {len(stability.critical_failures)} critical failure(s)")
    for path in paths:
        print(f"    → {os.path.relpath(path, _HERE)}")

    # The enriched baseline record doubles as the combined-summary row.
    rec = baseline.record(model, stability, diagnostic, det_rate)
    rec.update({
        "display_name": model["display_name"],
        "engine_model": engine_model,
        "derived": bool(model.get("derived")),
        "consumer_stability_grade": stability.consumer_stability_grade,
        "epistemic_rigor_grade": stability.epistemic_rigor_grade,
        "critical_failures": len(stability.critical_failures),
    })
    return rec


def _select_models(args) -> list[dict]:
    if args.model:
        return [model_registry.resolve_archetype(args.model)]
    if args.all:
        return list(model_registry.BEDROCK_MODEL_REGISTRY)
    if args.tier:
        return model_registry.get_models_by_tier(args.tier)
    return model_registry.get_models_by_tier(1)  # default: fast tier-1 sanity


def _print_catalog() -> None:
    print("ARIA SimRunner — 20 curated archetypes (use a model_id with --model);")
    print("any Bedrock model id also works via --model (see --list-bedrock).")
    for tier in range(1, 6):
        print(f"\nTier {tier}:")
        for model in model_registry.get_models_by_tier(tier):
            print(f"  {model['model_id']:<42} {model['display_name']}")


def _print_bedrock_catalog() -> None:
    catalog = bedrock_catalog.load_catalog()
    print(f"AWS Bedrock catalog — {len(catalog)} models (any id works with --model):")
    for provider in bedrock_catalog.providers():
        print(f"\n{provider}:")
        for m in [x for x in catalog if x.provider == provider]:
            print(f"  {m.model_id:<46} {m.model_class:<10} {m.modality}")


def _print_diffs(diffs) -> None:
    for d in diffs:
        if d.missing_baseline:
            print(f"  + {d.model_id}: new (no baseline) → grade {d.grade_to}")
            continue
        arrow = "→" if d.grade_from != d.grade_to else "="
        sign = "+" if d.composite_delta >= 0 else ""
        line = (f"  · {d.model_id}: composite {sign}{d.composite_delta}, "
                f"grade {d.grade_from}{arrow}{d.grade_to}")
        if d.new_mission_critical:
            line += f", +{len(d.new_mission_critical)} mission-critical"
        if d.resolved_mission_critical:
            line += f", -{len(d.resolved_mission_critical)} resolved"
        print(line)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="backend.simrunner", description="ARIA SimRunner — offline evaluation harness")
    parser.add_argument("--list", action="store_true", help="list the 20 curated archetypes and exit")
    parser.add_argument("--list-bedrock", action="store_true", help="list the full Bedrock model catalog and exit")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--model", help="archetype model_id OR any Bedrock catalog id")
    group.add_argument("--tier", type=int, choices=[1, 2, 3, 4, 5], help="test all archetypes in a tier")
    group.add_argument("--all", action="store_true", help="test all 20 archetypes")
    parser.add_argument("--seeds", type=int, default=None,
                        help="number of seeds for multi-seed confidence (overrides config seed_count)")
    parser.add_argument("--baseline", nargs="?", const=_BASELINES_DIR, default=None, metavar="DIR",
                        help="write golden baseline snapshots (default dir: baselines/)")
    parser.add_argument("--compare", nargs="?", const=_BASELINES_DIR, default=None, metavar="DIR",
                        help="diff this run against a committed baseline (default dir: baselines/)")
    parser.add_argument("--gate", action="store_true",
                        help="fail (exit 2) on a composite regression or a new mission-critical failure")
    args = parser.parse_args(argv)

    if args.list:
        _print_catalog()
        return 0
    if args.list_bedrock:
        _print_bedrock_catalog()
        return 0

    config = load_config()
    if args.seeds is not None:
        config["seed_count"] = max(1, args.seeds)
    engine = ARIAEngine(
        use_real_api=bool(config["use_real_api"]),
        engine_models=config.get("engine_models"),
        engine_model=config.get("engine_model"),
    )
    try:
        models = _select_models(args)
    except KeyError:
        print(f"error: unknown model {args.model!r}.")
        print("Run `python -m backend.simrunner --list` (archetypes) or `--list-bedrock` (full catalog).")
        return 2

    scope = args.model or (f"tier {args.tier}" if args.tier else ("all 20" if args.all else "tier 1 (default)"))
    print(f"ARIA SimRunner — scope: {scope}  ·  real_api={config['use_real_api']}  ·  "
          f"seed={config['seed']}  ·  seeds={config['seed_count']}")
    print("-" * 70)

    records = [run_model(model, config, engine) for model in models]

    print("-" * 70)
    if len(records) > 1:
        avg = round(sum(s["composite"] for s in records) / len(records), 1)
        det_vals = [s["determinism_rate"] for s in records if s.get("determinism_rate") is not None]
        det = f"{round(sum(det_vals) / len(det_vals), 1)}%" if det_vals else "n/a (real-API)"
        crit = sum(s["critical_failures"] for s in records)
        mc = sum(s["mission_critical_count"] for s in records)
        held = sum(1 for s in records if not s["system_passed"])
        path = report_builder.save_combined_summary(records, _REPORTS_DIR)
        print(f"Suite: {len(records)} models · avg composite {avg}/100 · avg determinism {det} · "
              f"{crit} critical · {mc} mission-critical · {held} held")
        print(f"Combined summary → {os.path.relpath(path, _HERE)}")
    else:
        print(f"Done. Reports in {os.path.relpath(_REPORTS_DIR, _HERE)}/")

    # --- regression baselines + gate ----------------------------------------
    if args.baseline is not None:
        written = baseline.save(records, args.baseline)
        print(f"Baseline written: {len(written)} snapshot(s) → {os.path.relpath(args.baseline, _HERE)}/")

    compare_dir = None
    if args.gate:
        compare_dir = args.compare if args.compare is not None else _BASELINES_DIR
    elif args.compare is not None:
        compare_dir = args.compare

    if compare_dir is not None:
        base = baseline.load(compare_dir)
        if not base:
            print(f"warning: no baseline found in {os.path.relpath(compare_dir, _HERE)}/ — run --baseline first.")
            return 0  # nothing to regress against
        diffs = baseline.compare(records, base)
        cpath = baseline.write_comparison(diffs, _REPORTS_DIR)
        print("-" * 70)
        print(f"Comparison vs baseline → {os.path.relpath(cpath, _HERE)}")
        _print_diffs(diffs)
        if args.gate:
            passed, reasons = baseline.gate(diffs, config["gate_max_drop"])
            if passed:
                print(f"✅ Regression gate PASSED (max allowed drop {config['gate_max_drop']}).")
                return 0
            print(f"⛔ Regression gate FAILED — {len(reasons)} issue(s):")
            for reason in reasons:
                print(f"    - {reason}")
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
