#!/usr/bin/env python3
"""Forge API smoke test — verifies backend routes the frontends depend on.

Targets the local dev server (backend/dev/server.py on port 3001) or a deployed
API Gateway URL via FORGE_API_BASE_URL.

For deployed APIs protected by Cognito JWT, set FORGE_SMOKE_AUTH_TOKEN to a valid
access token. Local smoke continues to use FORGE_TEST_USER_ID via backend/dev/server.py.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

API_BASE = os.environ.get("FORGE_API_BASE_URL", "http://localhost:3001").rstrip("/")
TIMEOUT = int(os.environ.get("FORGE_SMOKE_TIMEOUT", "15"))
AUTH_TOKEN = os.environ.get("FORGE_SMOKE_AUTH_TOKEN", "").strip()
LOCAL_DEV = API_BASE.startswith("http://127.0.0.1") or API_BASE.startswith("http://localhost")


def request(method: str, path: str, body: dict | None = None, *, auth: bool = True) -> tuple[int, dict]:
    url = f"{API_BASE}{path}"
    data = None
    headers = {"Content-Type": "application/json"}
    if auth and AUTH_TOKEN:
        headers["Authorization"] = f"Bearer {AUTH_TOKEN}"
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
            return resp.status, payload
    except urllib.error.HTTPError as exc:
        payload = json.loads(exc.read().decode("utf-8") or "{}")
        return exc.code, payload


def check(name: str, ok: bool, detail: str = "") -> bool:
    status = "PASS" if ok else "FAIL"
    suffix = f" — {detail}" if detail else ""
    print(f"[{status}] {name}{suffix}")
    return ok


def main() -> int:
    print(f"Forge smoke test against {API_BASE}\n")
    passed = True

    code, health = request("GET", "/health", auth=False)
    passed &= check("GET /health", code == 200 and health.get("status") in {"ok", "degraded"}, f"status={code}")
    readiness = health.get("readiness") or {}
    passed &= check(
        "GET /health readiness block",
        "productionReady" in readiness and "seedFallbackEnabled" in readiness,
        f"productionReady={readiness.get('productionReady')}",
    )
    self_healing = health.get("selfHealing") or {}
    passed &= check(
        "GET /health selfHealing block",
        self_healing.get("enabled") is not None,
        f"enabled={self_healing.get('enabled')}",
    )

    terra = (health.get("integrations") or {}).get("terra") or {}
    passed &= check(
        "GET /health integrations.terra",
        "configured" in terra and "selfHealing" in terra,
        f"status={terra.get('status', 'n/a')}",
    )

    code, terra_health = request("GET", "/integrations/terra/health", auth=False)
    passed &= check(
        "GET /integrations/terra/health",
        code == 200 and "healthy" in terra_health and "integration" in terra_health,
        f"status={code}",
    )

    if not LOCAL_DEV and not AUTH_TOKEN:
        print("[SKIP] Protected route smoke checks — set FORGE_SMOKE_AUTH_TOKEN for deployed API")
        print()
        if passed:
            print("Public smoke checks passed.")
            return 0
        print("One or more public smoke checks failed.")
        return 1

    code, dashboard = request("GET", "/dashboard/today")
    passed &= check(
        "GET /dashboard/today",
        code == 200 and "profile" in dashboard and "readiness" in dashboard,
        f"status={code}",
    )

    code, sleep = request("GET", "/sleep?days=7")
    passed &= check("GET /sleep", code == 200 and "sleep" in sleep, f"status={code}")

    code, history = request("GET", "/workouts/history?days=14")
    passed &= check(
        "GET /workouts/history",
        code == 200 and "workouts" in history,
        f"status={code}",
    )

    code, progress = request("GET", "/progress/summary?days=30")
    passed &= check(
        "GET /progress/summary",
        code == 200 and "summary" in progress,
        f"status={code}",
    )

    code, lifestyle = request("GET", "/lifestyle/dashboard")
    passed &= check(
        "GET /lifestyle/dashboard",
        code == 200 and "metrics" in lifestyle and "nutrition" in lifestyle,
        f"status={code}",
    )

    code, habits = request(
        "POST",
        "/wellbeing/habits/meditation/complete",
        {"completed": True},
    )
    passed &= check(
        "POST /wellbeing/habits/{id}/complete",
        code == 200 and "habits" in habits,
        f"status={code}",
    )

    code, aria_lifestyle = request("POST", "/aria/lifestyle", {"focus": "nutrition"})
    if code == 200 and aria_lifestyle.get("coaching"):
        check("POST /aria/lifestyle", True, f"status={code}")
    elif code == 503:
        check("POST /aria/lifestyle", True, "status=503 (ARIA unavailable locally — expected)")
    else:
        passed &= check("POST /aria/lifestyle", False, f"status={code}")

    code, chat = request("POST", "/aria/chat", {"content": "How should I train today?"})
    if code == 200 and chat.get("message", {}).get("content"):
        check("POST /aria/chat", True, f"status={code}")
    elif code == 503:
        check("POST /aria/chat", True, "status=503 (Bedrock unavailable locally — expected)")
    else:
        passed &= check("POST /aria/chat", False, f"status={code}")

    print()
    if passed:
        print("All smoke checks passed.")
        return 0
    print("One or more smoke checks failed.")
    return 1


if __name__ == "__main__":
    sys.exit(main())