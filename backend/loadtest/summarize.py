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
                {"requests": 0, "errors": 0, "durations_ms": [], "status_codes": defaultdict(int)},
            )
            metric = point.get("metric")
            if metric == "http_reqs":
                stats["requests"] += int(data.get("value") or 0)
                status = str(tags.get("status") or "0")
                stats["status_codes"][status] += int(data.get("value") or 0)
                if status == "0" or (status.isdigit() and int(status) >= 400):
                    stats["errors"] += int(data.get("value") or 0)
            elif metric == "http_req_duration":
                stats["durations_ms"].append(float(data.get("value") or 0))
    out = {}
    for name, stats in by_route.items():
        durs = stats["durations_ms"]
        reqs = stats["requests"]
        out[name] = {
            "requests": reqs,
            "errors": stats["errors"],
            "error_rate": (stats["errors"] / reqs) if reqs else 0,
            "requests_per_second": (reqs / duration_seconds) if duration_seconds else 0,
            "latency_ms": {
                "p50": _percentile(durs, 0.50),
                "p95": _percentile(durs, 0.95),
                "p99": _percentile(durs, 0.99),
            },
            "status_codes": dict(sorted(stats["status_codes"].items())),
        }
    return out


def _overall_from_k6_json(path: Path) -> dict:
    """Overall request/latency/error stats from k6 --out json. Excludes /__loadtest."""
    times: list[datetime] = []
    durations: list[float] = []
    requests = 0
    errors = 0
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
            data = point.get("data") or {}
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
            metric = point.get("metric")
            if metric == "http_reqs":
                n = int(data.get("value") or 0)
                requests += n
                status = str(tags.get("status") or "0")
                if status == "0" or (status.isdigit() and int(status) >= 400):
                    errors += n
            elif metric == "http_req_duration":
                durations.append(float(data.get("value") or 0))
    if times:
        duration = (max(times) - min(times)).total_seconds()
        # k6 test duration includes the last request; add nothing if identical
        duration = max(duration, 1e-6)
    else:
        duration = 0.0
    return {
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
    }


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
    return {
        "peak_1s_http_reqs": buckets[peak_ts],
        "samples": len(buckets),
        "min_1s_http_reqs": min(buckets.values()),
        "median_1s_http_reqs": sorted(buckets.values())[len(buckets) // 2],
    }


STRESS_STAGES = (
    # (duration_s, start_rate, target_rate)
    (15.0, 1.0, 5.0),
    (15.0, 5.0, 15.0),
    (15.0, 15.0, 30.0),
    (15.0, 30.0, 50.0),
    (15.0, 50.0, 80.0),
)


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


def _derive_stress_breaking_point(report: dict) -> dict:
    duration = float(report.get("duration_seconds") or 0)
    error_rate = float(report.get("error_rate_overall") or 0)
    p95 = (report.get("latency_ms") or {}).get("p95")
    planned = sum(stage[0] for stage in STRESS_STAGES)
    aborted = duration < planned - 0.5
    interp = _interpolated_arrival_rate(duration)
    reasons = []
    if error_rate >= 0.01:
        reasons.append(f"error_rate {error_rate:.4f} >= 0.01")
    if p95 is not None and p95 >= 2000:
        reasons.append(f"p95_ms {p95} >= 2000")
    codes = []
    for name, stats in (report.get("per_route") or {}).items():
        for status, count in (stats.get("status_codes") or {}).items():
            if status == "0" or (str(status).isdigit() and int(status) >= 400):
                codes.append(f"{name} {status}×{count}")
    peak = (report.get("peak_rps") or {}).get("peak_1s_http_reqs")
    if aborted and reasons:
        note = (
            f"aborted at {duration:.2f}s of {planned:.0f}s planned: "
            + "; ".join(reasons)
            + (f" ({'; '.join(codes)})" if codes else "")
        )
    elif not aborted:
        note = f"cap reached at {interp['stage_target_rps']} rps without abort"
    else:
        note = f"stopped at {duration:.2f}s without a recorded threshold reason"
    return {
        "aborted": aborted,
        "reason": reasons,
        "error_status_codes": codes,
        "p95_ms_at_stop": p95,
        "interpolated_arrival_rps_at_stop": interp["interpolated_arrival_rps"],
        "failed_at_target_rps": interp["stage_target_rps"] if aborted else None,
        "held_through_target_rps": interp["last_completed_target_rps"],
        "peak_1s_http_reqs_before_stop": peak,
        "duration_seconds": duration,
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
        f"- duration_seconds: {report.get('duration_seconds')}",
        f"- vm_cpu_count: {vm.get('cpu_count')}",
        f"- vm_ram_gib: {vm.get('ram_gib')}",
        f"- backend_workers: {backend.get('workers')} ({backend.get('worker_model')})",
        "",
        "## Per route",
        "",
    ]
    per_route = report.get("per_route") or {}
    if not per_route:
        lines.append("_no per-route samples_")
    else:
        lines.append("| route | requests | rps | error_rate | status_codes | p50_ms | p95_ms | p99_ms |")
        lines.append("| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: |")
        for name, stats in sorted(per_route.items()):
            lat = stats.get("latency_ms") or {}
            codes = stats.get("status_codes") or {}
            code_s = ", ".join(f"{k}:{v}" for k, v in sorted(codes.items(), key=lambda kv: kv[0]))
            lines.append(
                f"| {name} | {stats.get('requests', 0)} | {stats.get('requests_per_second')} | "
                f"{stats.get('error_rate', 0)} | {code_s or 'n/a'} | "
                f"{lat.get('p50')} | {lat.get('p95')} | {lat.get('p99')} |"
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
    duration = float(report.get("duration_seconds") or 0)
    report["per_route"] = _routes_from_k6_json(k6_json, duration)
    if args.scenario == "stress":
        report["breaking_point"] = _derive_stress_breaking_point(report)
        report["aborted"] = report["breaking_point"]["aborted"]
    else:
        report["breaking_point"] = None
        report["aborted"] = False
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
