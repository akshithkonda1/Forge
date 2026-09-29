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
    summary_path = results / "summary.json"
    report = _load_json(summary_path)
    report["scenario"] = report.get("scenario") or args.scenario
    report["generated_at"] = report.get("generated_at") or datetime.now(timezone.utc).isoformat()
    report["guards"] = _fetch_guards(args.base_url)
    report["vm"] = _vm_facts()
    k6_json = Path(args.k6_json) if args.k6_json else results / f"{args.scenario}.k6.json"
    report["peak_rps"] = _peak_rps_from_k6_json(k6_json)
    if report.get("breaking_point") and report["peak_rps"]:
        report["breaking_point"] = dict(report["breaking_point"])
        report["breaking_point"]["peak_1s_http_reqs_measured"] = report["peak_rps"].get(
            "peak_1s_http_reqs"
        )
    text = json.dumps(report, indent=2) + "\n"
    summary_path.write_text(text, encoding="utf-8")
    (results / f"{args.scenario}.json").write_text(text, encoding="utf-8")
    markdown = _md(report)
    (results / "summary.md").write_text(markdown, encoding="utf-8")
    (results / f"{args.scenario}.md").write_text(markdown, encoding="utf-8")
    print(markdown)


if __name__ == "__main__":
    main()
