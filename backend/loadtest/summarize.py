#!/usr/bin/env python3
"""Merge k6 JSON with live guard counters and write the markdown report."""

from __future__ import annotations

import argparse
import json
import urllib.error
import urllib.request
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


def _md(report: dict) -> str:
    latency = report.get("latency_ms") or {}
    guards = ((report.get("guards") or {}).get("payload") or {})
    counts = guards.get("counts") or {}
    breaking = report.get("breaking_point")
    lines = [
        f"# Dummy loadtest — {report.get('scenario', 'unknown')}",
        "",
        f"- requests: {report.get('requests')}",
        f"- requests_per_second: {report.get('requests_per_second')}",
        f"- p50_ms: {latency.get('p50')}",
        f"- p95_ms: {latency.get('p95')}",
        f"- p99_ms: {latency.get('p99')}",
        f"- error_rate_overall: {report.get('error_rate_overall')}",
        f"- duration_seconds: {report.get('duration_seconds')}",
        "",
        "## Per route",
        "",
    ]
    per_route = report.get("per_route") or {}
    if not per_route:
        lines.append("_no per-route samples_")
    else:
        lines.append("| route | requests | error_rate | p50_ms | p95_ms | p99_ms |")
        lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
        for name, stats in sorted(per_route.items()):
            lat = stats.get("latency_ms") or {}
            lines.append(
                f"| {name} | {stats.get('requests', 0)} | {stats.get('error_rate', 0)} | "
                f"{lat.get('p50')} | {lat.get('p95')} | {lat.get('p99')} |"
            )
    lines.extend(
        [
            "",
            "## Breaking point",
            "",
            json.dumps(breaking, indent=2) if breaking else "_baseline has no breaking point_",
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
    args = parser.parse_args()

    results = Path(args.results_dir)
    results.mkdir(parents=True, exist_ok=True)
    summary_path = results / "summary.json"
    report = _load_json(summary_path)
    report["scenario"] = report.get("scenario") or args.scenario
    report["guards"] = _fetch_guards(args.base_url)
    summary_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    markdown = _md(report)
    (results / "summary.md").write_text(markdown, encoding="utf-8")
    print(markdown)


if __name__ == "__main__":
    main()
