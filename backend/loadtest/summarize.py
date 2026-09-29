#!/usr/bin/env python3
"""Merge k6 JSON with live guard counters, VM facts, and write the markdown report."""

from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


# Must match backend/loadtest/k6/stress.js STAGES (duration_s, start_rate, target).
STRESS_STAGES = (
    (20.0, 1.0, 20.0),
    (20.0, 20.0, 50.0),
    (20.0, 50.0, 100.0),
    (20.0, 100.0, 200.0),
    (20.0, 200.0, 400.0),
    (20.0, 400.0, 600.0),
    (20.0, 600.0, 800.0),
    (20.0, 800.0, 1000.0),
    (20.0, 1000.0, 1000.0),
)
STRESS_CEILING_RPS = STRESS_STAGES[-1][2]


def _load_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _fetch_guards(base_url: str) -> dict:
    url = base_url.rstrip("/") + "/__loadtest/guards"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))
            return {"status": int(response.status), "payload": payload}
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError) as exc:
        return {"status": 0, "payload": {"error": str(exc)}}


def _vm_facts() -> dict:
    cpus = os.cpu_count()
    mem_kb = None
    meminfo = Path("/proc/meminfo")
    if meminfo.is_file():
        for line in meminfo.read_text(encoding="utf-8").splitlines():
            if line.startswith("MemTotal:"):
                mem_kb = int(line.split()[1])
                break
    return {
        "cpu_count": cpus,
        "ram_kib": mem_kb,
        "ram_gib": round(mem_kb / (1024 * 1024), 2) if mem_kb else None,
        "backend": {
            "server": "backend/loadtest/run_server.py → ThreadingHTTPServer",
            "workers": 1,
            "worker_model": "single process, thread-per-request (no gunicorn/uvicorn workers)",
            "not": "Lambda or API Gateway",
            "numbers_mean": "local Dummy backend ceiling on this VM, not production capacity",
        },
    }


def _percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    idx = (len(ordered) - 1) * q
    lo = int(idx)
    hi = min(lo + 1, len(ordered) - 1)
    frac = idx - lo
    return ordered[lo] * (1 - frac) + ordered[hi] * frac


def classify_status(status: str) -> str:
    """Return 'ok', '429', '5xx', or 'other' (network/timeout/other 4xx)."""
    if status == "429":
        return "429"
    if status.isdigit():
        code = int(status)
        if 200 <= code < 400:
            return "ok"
        if 500 <= code <= 599:
            return "5xx"
    return "other"


def _empty_error_split() -> dict[str, int]:
    return {"5xx": 0, "429": 0, "other": 0}


def _attach_error_rates(stats: dict, reqs: int) -> dict:
    split = stats.setdefault("errors_split", _empty_error_split())
    stats["errors_5xx"] = split["5xx"]
    stats["errors_429"] = split["429"]
    stats["errors_other"] = split["other"]
    stats["errors_non_429"] = split["5xx"] + split["other"]
    stats["error_rate"] = (stats.get("errors") or 0) / reqs if reqs else 0
    stats["error_rate_5xx"] = split["5xx"] / reqs if reqs else 0
    stats["error_rate_429"] = split["429"] / reqs if reqs else 0
    stats["error_rate_other"] = split["other"] / reqs if reqs else 0
    stats["error_rate_non_429"] = stats["errors_non_429"] / reqs if reqs else 0
    return stats


def _routes_from_k6_json(path: Path, duration_seconds: float) -> dict:
    """Per-route counts, status codes, and latency from k6 --out json points."""
    by_route: dict[str, dict] = {}
    if not path.is_file():
        return by_route
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                point = json.loads(line)
            except json.JSONDecodeError:
                continue
            if point.get("type") != "Point":
                continue
            data = point.get("data") or {}
            tags = data.get("tags") or {}
            route = tags.get("route")
            if not route or route.startswith("GET /__loadtest"):
                continue
            stats = by_route.setdefault(
                route,
                {
                    "requests": 0,
                    "errors": 0,
                    "durations_ms": [],
                    "status_codes": defaultdict(int),
                    "errors_split": _empty_error_split(),
                },
            )
            metric = point.get("metric")
            if metric == "http_reqs":
                n = int(data.get("value") or 0)
                stats["requests"] += n
                status = str(tags.get("status") or "0")
                stats["status_codes"][status] += n
                kind = classify_status(status)
                if kind != "ok":
                    stats["errors"] += n
                    stats["errors_split"][kind] += n
            elif metric == "http_req_duration":
                stats["durations_ms"].append(float(data.get("value") or 0))
    out = {}
    for name, stats in by_route.items():
        durs = stats["durations_ms"]
        reqs = stats["requests"]
        row = {
            "requests": reqs,
            "errors": stats["errors"],
            "requests_per_second": (reqs / duration_seconds) if duration_seconds else 0,
            "latency_ms": {
                "p50": _percentile(durs, 0.50),
                "p95": _percentile(durs, 0.95),
                "p99": _percentile(durs, 0.99),
            },
            "status_codes": dict(sorted(stats["status_codes"].items())),
            "errors_split": dict(stats["errors_split"]),
        }
        _attach_error_rates(row, reqs)
        out[name] = row
    return out


def _overall_from_k6_json(path: Path) -> dict:
    """Overall request/latency/error stats from k6 --out json. Excludes /__loadtest."""
    times: list[datetime] = []
    durations: list[float] = []
    requests = 0
    errors = 0
    split = _empty_error_split()
    dropped = 0
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                point = json.loads(line)
            except json.JSONDecodeError:
                continue
            if point.get("type") != "Point":
                continue
            metric = point.get("metric")
            data = point.get("data") or {}
            if metric == "dropped_iterations":
                dropped += int(data.get("value") or 0)
                continue
            tags = data.get("tags") or {}
            route = tags.get("route") or ""
            if route.startswith("GET /__loadtest"):
                continue
            raw = data.get("time")
            if raw:
                try:
                    times.append(datetime.fromisoformat(str(raw).replace("Z", "+00:00")))
                except ValueError:
                    pass
            if metric == "http_reqs":
                n = int(data.get("value") or 0)
                requests += n
                status = str(tags.get("status") or "0")
                kind = classify_status(status)
                if kind != "ok":
                    errors += n
                    split[kind] += n
            elif metric == "http_req_duration":
                durations.append(float(data.get("value") or 0))
    if times:
        duration = (max(times) - min(times)).total_seconds()
        duration = max(duration, 1e-6)
    else:
        duration = 0.0
    out = {
        "duration_seconds": duration,
        "requests": requests,
        "requests_per_second": requests / duration if duration else 0,
        "latency_ms": {
            "p50": _percentile(durations, 0.50),
            "p95": _percentile(durations, 0.95),
            "p99": _percentile(durations, 0.99),
        },
        "error_rate": errors / requests if requests else 0,
        "error_rate_overall": errors / requests if requests else 0,
        "errors": errors,
        "errors_split": dict(split),
        "dropped_iterations": dropped,
    }
    _attach_error_rates(out, requests)
    return out


def _peak_rps_from_k6_json(path: Path) -> dict | None:
    """1-second buckets of http_reqs from k6 --out json. None if the file is missing."""
    if not path.is_file():
        return None
    buckets: dict[int, int] = defaultdict(int)
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                point = json.loads(line)
            except json.JSONDecodeError:
                continue
            if point.get("type") != "Point" or point.get("metric") != "http_reqs":
                continue
            data = point.get("data") or {}
            tags = data.get("tags") or {}
            if str(tags.get("route") or "").startswith("GET /__loadtest"):
                continue
            raw = data.get("time")
            if not raw:
                continue
            try:
                when = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
            except ValueError:
                continue
            buckets[int(when.timestamp())] += int(data.get("value") or 0)
    if not buckets:
        return {"note": "k6 json had no http_reqs points"}
    peak_ts = max(buckets, key=buckets.get)
    values = sorted(buckets.values())
    return {
        "peak_1s_http_reqs": buckets[peak_ts],
        "samples": len(buckets),
        "min_1s_http_reqs": min(buckets.values()),
        "median_1s_http_reqs": values[len(values) // 2],
    }


def _timeseries_from_k6_json(path: Path) -> list[dict]:
    """Per-second request, latency, and error-split buckets."""
    if not path.is_file():
        return []
    buckets: dict[int, dict] = {}
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                point = json.loads(line)
            except json.JSONDecodeError:
                continue
            if point.get("type") != "Point":
                continue
            data = point.get("data") or {}
            tags = data.get("tags") or {}
            if str(tags.get("route") or "").startswith("GET /__loadtest"):
                continue
            raw = data.get("time")
            if not raw:
                continue
            try:
                when = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
            except ValueError:
                continue
            ts = int(when.timestamp())
            slot = buckets.setdefault(
                ts,
                {"t": ts, "requests": 0, "durs": [], "split": _empty_error_split()},
            )
            metric = point.get("metric")
            if metric == "http_reqs":
                n = int(data.get("value") or 0)
                slot["requests"] += n
                kind = classify_status(str(tags.get("status") or "0"))
                if kind != "ok":
                    slot["split"][kind] += n
            elif metric == "http_req_duration":
                slot["durs"].append(float(data.get("value") or 0))
    series = []
    for ts in sorted(buckets):
        slot = buckets[ts]
        reqs = slot["requests"]
        split = slot["split"]
        series.append(
            {
                "t": ts,
                "requests": reqs,
                "p95_ms": _percentile(slot["durs"], 0.95),
                "errors_5xx": split["5xx"],
                "errors_429": split["429"],
                "errors_other": split["other"],
                "errors_non_429": split["5xx"] + split["other"],
            }
        )
    return series


def _interpolated_arrival_rate(duration_seconds: float) -> dict:
    elapsed = 0.0
    last_target = 1.0
    for length, start, target in STRESS_STAGES:
        if duration_seconds <= elapsed + length:
            frac = max(0.0, (duration_seconds - elapsed) / length)
            rate = start + (target - start) * frac
            return {
                "stage_target_rps": target,
                "stage_start_rps": start,
                "interpolated_arrival_rps": rate,
                "last_completed_target_rps": last_target if frac < 1 else target,
            }
        elapsed += length
        last_target = target
    cap = STRESS_STAGES[-1][2]
    return {
        "stage_target_rps": cap,
        "stage_start_rps": cap,
        "interpolated_arrival_rps": cap,
        "last_completed_target_rps": cap,
    }


def _rolling_mean(values: list[float], window: int) -> list[float | None]:
    out: list[float | None] = []
    acc = 0.0
    for i, value in enumerate(values):
        acc += value
        if i >= window:
            acc -= values[i - window]
            out.append(acc / window)
        elif i + 1 >= window:
            out.append(acc / window)
        else:
            out.append(None)
    return out


def _derive_stress_breaking_point(report: dict, series: list[dict] | None = None) -> dict:
    duration = float(report.get("duration_seconds") or 0)
    non_429_rate = float(report.get("error_rate_non_429") or 0)
    p95 = (report.get("latency_ms") or {}).get("p95")
    planned = sum(stage[0] for stage in STRESS_STAGES)
    aborted = duration < planned - 0.5
    interp = _interpolated_arrival_rate(duration)
    series = series or []

    first_break = None
    cum_reqs = 0
    cum_non_429 = 0
    t0 = series[0]["t"] if series else None
    for slot in series:
        cum_reqs += slot["requests"]
        cum_non_429 += slot["errors_non_429"]
        slot_p95 = slot.get("p95_ms")
        cum_rate = cum_non_429 / cum_reqs if cum_reqs else 0.0
        reasons = []
        if slot_p95 is not None and slot_p95 >= 2000:
            reasons.append(f"p95_ms {slot_p95:.3f} >= 2000")
        if cum_reqs >= 20 and cum_rate >= 0.01:
            reasons.append(f"non_429_error_rate {cum_rate:.4f} >= 0.01")
        if reasons:
            elapsed = (slot["t"] - t0) if t0 is not None else duration
            first_break = {
                "elapsed_seconds": elapsed,
                "reason": reasons,
                "p95_ms": slot_p95,
                "non_429_error_rate_cumulative": cum_rate,
                "requests_that_second": slot["requests"],
                **_interpolated_arrival_rate(elapsed),
            }
            break

    before = []
    if first_break and t0 is not None:
        cutoff = t0 + first_break["elapsed_seconds"]
        before = [s["requests"] for s in series if s["t"] < cutoff]
    elif series:
        before = [s["requests"] for s in series]
    peak_1s = max(before) if before else (report.get("peak_rps") or {}).get("peak_1s_http_reqs")
    rolling = [v for v in _rolling_mean([float(x) for x in before], 5) if v is not None]
    peak_sustained = max(rolling) if rolling else peak_1s

    reasons = []
    if non_429_rate >= 0.01:
        reasons.append(f"non_429_error_rate {non_429_rate:.4f} >= 0.01")
    if p95 is not None and p95 >= 2000:
        reasons.append(f"p95_ms {p95} >= 2000")
    codes = []
    for name, stats in (report.get("per_route") or {}).items():
        for status, count in (stats.get("status_codes") or {}).items():
            if status == "0" or (str(status).isdigit() and int(status) >= 400):
                codes.append(f"{name} {status}×{count}")

    never_broke = first_break is None and not aborted and not reasons
    if first_break:
        note = (
            f"first break at {first_break['elapsed_seconds']:.2f}s: "
            + "; ".join(first_break["reason"])
            + f" (arrival ~{first_break['interpolated_arrival_rps']:.2f} rps, "
            + f"that-second {first_break['requests_that_second']} req/s)"
        )
    elif never_broke:
        note = f"never broke by the ceiling of {STRESS_CEILING_RPS:.0f} rps"
    elif aborted and reasons:
        note = (
            f"aborted at {duration:.2f}s of {planned:.0f}s planned: "
            + "; ".join(reasons)
            + (f" ({'; '.join(codes)})" if codes else "")
        )
    elif not aborted:
        note = f"cap reached at {interp['stage_target_rps']} rps without abort"
    else:
        note = f"stopped at {duration:.2f}s without a recorded threshold reason"

    break_interp = first_break or interp
    return {
        "aborted": aborted,
        "never_broke_by_ceiling": never_broke,
        "ceiling_rps": STRESS_CEILING_RPS,
        "reason": (first_break or {}).get("reason") or reasons,
        "error_status_codes": codes,
        "p95_ms_at_stop": p95,
        "non_429_error_rate_at_stop": non_429_rate,
        "interpolated_arrival_rps_at_stop": interp["interpolated_arrival_rps"],
        "arrival_rps_at_first_break": break_interp.get("interpolated_arrival_rps"),
        "rps_at_first_break": (first_break or {}).get("requests_that_second"),
        "failed_at_target_rps": (
            None if never_broke else (first_break or interp).get("stage_target_rps") if (first_break or aborted) else None
        ),
        "held_through_target_rps": interp["last_completed_target_rps"],
        "peak_1s_http_reqs_before_stop": peak_1s,
        "peak_sustained_5s_rps_before_break": peak_sustained,
        "duration_seconds": duration,
        "first_break": first_break,
        "note": note,
    }


def _md(report: dict) -> str:
    latency = report.get("latency_ms") or {}
    guards = ((report.get("guards") or {}).get("payload") or {})
    counts = guards.get("counts") or {}
    breaking = report.get("breaking_point")
    vm = report.get("vm") or {}
    backend = vm.get("backend") or {}
    peak = report.get("peak_rps") or {}
    cpu = report.get("cpu") or {}
    split = report.get("errors_split") or {}
    identity = report.get("identity") or {}
    rate_limit = report.get("rate_limit") or {}
    lines = [
        f"# Dummy loadtest — {report.get('scenario', 'unknown')}",
        "",
        f"- generated_at: {report.get('generated_at')}",
        f"- requests: {report.get('requests')}",
        f"- requests_per_second: {report.get('requests_per_second')}",
        f"- p50_ms: {latency.get('p50')}",
        f"- p95_ms: {latency.get('p95')}",
        f"- p99_ms: {latency.get('p99')}",
        f"- error_rate_overall: {report.get('error_rate_overall')}",
        f"- error_rate_5xx: {report.get('error_rate_5xx')}",
        f"- error_rate_429: {report.get('error_rate_429')}",
        f"- error_rate_other: {report.get('error_rate_other')}",
        f"- error_rate_non_429: {report.get('error_rate_non_429')}",
        f"- errors_5xx: {split.get('5xx', report.get('errors_5xx'))}",
        f"- errors_429: {split.get('429', report.get('errors_429'))}",
        f"- errors_other: {split.get('other', report.get('errors_other'))}",
        f"- dropped_iterations: {report.get('dropped_iterations')}",
        f"- duration_seconds: {report.get('duration_seconds')}",
        f"- vm_cpu_count: {vm.get('cpu_count')}",
        f"- vm_ram_gib: {vm.get('ram_gib')}",
        f"- backend_workers: {backend.get('workers')} ({backend.get('worker_model')})",
        f"- backend_is_not: {backend.get('not')}",
        f"- numbers_mean: {backend.get('numbers_mean')}",
        "",
        "## Identity and rate limiter",
        "",
        f"- identity: {identity.get('scheme', 'n/a')}",
        f"- rate_limit_store: {rate_limit.get('store', 'n/a')}",
        f"- rate_limit_patched: {rate_limit.get('patched', False)}",
        f"- backend_restarted_before_run: {rate_limit.get('restarted_before_run', False)}",
        "",
        "## Per route",
        "",
    ]
    per_route = report.get("per_route") or {}
    if not per_route:
        lines.append("_no per-route samples_")
    else:
        lines.append(
            "| route | requests | rps | p50_ms | p95_ms | p99_ms | 5xx | 429 | other | "
            "err_5xx | err_429 | err_other |"
        )
        lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
        for name, stats in sorted(per_route.items()):
            lat = stats.get("latency_ms") or {}
            lines.append(
                f"| {name} | {stats.get('requests', 0)} | {stats.get('requests_per_second')} | "
                f"{lat.get('p50')} | {lat.get('p95')} | {lat.get('p99')} | "
                f"{stats.get('errors_5xx', 0)} | {stats.get('errors_429', 0)} | "
                f"{stats.get('errors_other', 0)} | "
                f"{stats.get('error_rate_5xx', 0)} | {stats.get('error_rate_429', 0)} | "
                f"{stats.get('error_rate_other', 0)} |"
            )
    lines.extend(
        [
            "",
            "## Breaking point",
            "",
            json.dumps(breaking, indent=2) if breaking else "_baseline has no breaking point_",
            "",
            "## Peak 1s request rate (from k6 json)",
            "",
            json.dumps(peak, indent=2) if peak else "_not measured_",
            "",
            "## CPU samples",
            "",
            json.dumps(cpu, indent=2) if cpu else "_not sampled_",
            "",
            "## Zero-Bedrock / Zero-ElevenLabs guard",
            "",
            f"- bedrock_client: {counts.get('bedrock_client', 'missing')}",
            f"- bedrock_invoke: {counts.get('bedrock_invoke', 'missing')}",
            f"- elevenlabs_http: {counts.get('elevenlabs_http', 'missing')}",
            f"- elevenlabs_api: {counts.get('elevenlabs_api', 'missing')}",
            f"- total: {guards.get('total', 'missing')}",
            f"- ok: {guards.get('ok')}",
            "",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--results-dir", default="backend/loadtest/results")
    parser.add_argument("--k6-json", default="")
    args = parser.parse_args()

    results = Path(args.results_dir)
    results.mkdir(parents=True, exist_ok=True)
    k6_json = Path(args.k6_json) if args.k6_json else results / f"{args.scenario}.k6.json"
    report: dict = {"scenario": args.scenario}
    report.update(_overall_from_k6_json(k6_json))
    report["generated_at"] = datetime.now(timezone.utc).isoformat()
    report["guards"] = _fetch_guards(args.base_url)
    report["vm"] = _vm_facts()
    report["peak_rps"] = _peak_rps_from_k6_json(k6_json)
    report["cpu"] = _load_json(results / "cpu.json") or None
    duration = float(report.get("duration_seconds") or 0)
    report["per_route"] = _routes_from_k6_json(k6_json, duration)
    if args.scenario == "stress":
        series = _timeseries_from_k6_json(k6_json)
        report["breaking_point"] = _derive_stress_breaking_point(report, series)
        report["aborted"] = report["breaking_point"]["aborted"]
        report["identity"] = {
            "scheme": "unsigned Dummy Bearer JWT, sub=loadtest-<vu>-<iter>",
            "forge_test_user_id": None,
        }
        report["rate_limit"] = {
            "patched": False,
            "store": "in-memory storage.dynamodb._local_store (APP_DATA_TABLE_NAME unset)",
            "restarted_before_run": True,
        }
    else:
        report["breaking_point"] = None
        report["aborted"] = False
        report["identity"] = {
            "scheme": "FORGE_TEST_USER_ID=loadtest-user",
            "forge_test_user_id": "loadtest-user",
        }
        report["rate_limit"] = {
            "patched": False,
            "store": "in-memory storage.dynamodb._local_store (APP_DATA_TABLE_NAME unset)",
            "restarted_before_run": False,
        }
    summary_path = results / "summary.json"
    text = json.dumps(report, indent=2) + "\n"
    summary_path.write_text(text, encoding="utf-8")
    (results / f"{args.scenario}.json").write_text(text, encoding="utf-8")
    markdown = _md(report)
    (results / "summary.md").write_text(markdown, encoding="utf-8")
    (results / f"{args.scenario}.md").write_text(markdown, encoding="utf-8")
    print(markdown)


if __name__ == "__main__":
    main()
