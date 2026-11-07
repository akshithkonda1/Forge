"""Runtime detector for health data on Forge servers.

Default is dry-run. Quarantine, destroy, and the write-block only apply
when their flags are on — and destroy still refuses live AWS unless
``FORGE_HEALTH_LEAK_APPLY=1`` (off, and Akshith has not said go).
"""

from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

from responses import RouteError
from storage import dynamodb, keys

HEALTH_KEYS = frozenset(
    {
        "samples",
        "metrics",
        "vitals",
        "hrv",
        "heartrate",
        "heart_rate",
        "spo2",
        "sleep",
        "sleephours",
        "sleepminutes",
        "bodyweight",
        "weightkg",
        "cycleday",
        "image_base64",
        "imagebase64",
    }
)

CANARIES = frozenset({"188", "177", "11.7", "702", "99.3", "27", "ZeldaCanaryQuill"})

HEALTH_SK_PREFIXES = ("METRIC#", "EMERGENCY#", "ARIA#BODY_SNAPSHOT")

AUDIT_PK = "LEAK#AUDIT"
BLOCK_KEY = {"pk": "LEAK#QUARANTINE", "sk": "BLOCK"}
QUARANTINE_PK = "LEAK#QUARANTINE"


def _flag(name: str) -> bool:
    return os.getenv(name, "").lower() in {"1", "true", "yes"}


def destroy_enabled() -> bool:
    return _flag("FORGE_HEALTH_LEAK_DESTROY")


def quarantine_enabled() -> bool:
    return _flag("FORGE_HEALTH_LEAK_QUARANTINE")


def apply_live_aws() -> bool:
    # Live AWS destroy/quarantine stays off until Akshith says go.
    return _flag("FORGE_HEALTH_LEAK_APPLY")


def auto_block_enabled() -> bool:
    return _flag("FORGE_HEALTH_LEAK_AUTO_BLOCK")


def writes_blocked() -> bool:
    if _flag("FORGE_HEALTH_QUARANTINE_BLOCK"):
        return True
    item = dynamodb.get_item(BLOCK_KEY["pk"], BLOCK_KEY["sk"])
    return bool(item and item.get("blocked"))


def set_block(blocked: bool) -> None:
    dynamodb.put_item(
        {
            "pk": BLOCK_KEY["pk"],
            "sk": BLOCK_KEY["sk"],
            "blocked": blocked,
            "at": datetime.now(timezone.utc).isoformat(),
            "values": None,
        }
    )


def normalize_key(raw: str) -> str:
    return raw.lower().replace("_", "").replace("-", "")


def looks_like_health_key(raw: str) -> bool:
    return normalize_key(raw) in HEALTH_KEYS


def contains_canary(value: Any) -> bool:
    text = str(value)
    return any(token in text for token in CANARIES)


def findings_in(value: Any, *, path: str = "", honor_canary: bool = False) -> list[str]:
    hits: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            here = f"{path}.{key}" if path else str(key)
            health = looks_like_health_key(str(key))
            if health:
                hits.append(here)
            hits.extend(findings_in(child, path=here, honor_canary=health or honor_canary))
    elif isinstance(value, list):
        for idx, child in enumerate(value[:50]):
            hits.extend(findings_in(child, path=f"{path}[{idx}]", honor_canary=honor_canary))
    elif honor_canary and contains_canary(value):
        hits.append(path or "value")
    return hits


def write_audit(reason: str, paths: list[str], *, destroyed: bool, quarantined: bool) -> None:
    stamp = datetime.now(timezone.utc).isoformat()
    dynamodb.put_item(
        {
            "pk": AUDIT_PK,
            "sk": f"EVENT#{stamp}",
            "reason": reason,
            "field_paths": paths[:20],
            "destroyed": destroyed,
            "quarantined": quarantined,
            "dry_run": not (destroy_enabled() and apply_live_aws()),
            "values": None,
        }
    )


def handle_finding(item: dict[str, Any] | None, paths: list[str], *, reason: str) -> dict[str, Any]:
    """Quarantine / destroy / block. Destroy is dry-run unless APPLY is on."""
    dry_destroy = not (destroy_enabled() and apply_live_aws())
    did_quarantine = False
    did_destroy = False

    if item and quarantine_enabled() and apply_live_aws():
        dynamodb.put_item(
            {
                "pk": QUARANTINE_PK,
                "sk": f"ITEM#{item.get('sk') or 'unknown'}",
                "locked": True,
                "values": None,
            }
        )
        did_quarantine = True
    elif item and quarantine_enabled():
        did_quarantine = False  # recorded as intended, not applied

    if item and destroy_enabled() and apply_live_aws() and item.get("pk") and item.get("sk"):
        dynamodb.delete_item(item["pk"], item["sk"])
        did_destroy = True

    if auto_block_enabled():
        set_block(True)

    write_audit(reason, paths, destroyed=did_destroy, quarantined=did_quarantine)
    return {
        "paths": paths,
        "destroyed": did_destroy,
        "quarantined": did_quarantine,
        "dry_run": dry_destroy,
        "blocked": writes_blocked(),
    }


def inspect_request(method: str, path: str, body: dict[str, Any]) -> dict[str, Any] | None:
    if writes_blocked() and method in {"POST", "PUT", "PATCH", "DELETE"}:
        raise RouteError(
            423,
            "Health leak quarantine is set. Writes are refused until it is clear.",
            code="health_quarantine_block",
        )
    hits = findings_in(body)
    # Health presented on observe / health/batch is stripped by those routes.
    # A leak is storage, not a rejected body. Still audit the attempt.
    if not hits:
        return None
    if path in {"/ai/observe", "/health/batch"}:
        write_audit("ingress_stripped", hits, destroyed=False, quarantined=False)
        return {"paths": hits, "stripped": True, "dry_run": True}
    return handle_finding(None, hits, reason=f"ingress:{method}:{path}")


def scan_local_store() -> list[dict[str, Any]]:
    """Scan the in-memory test store only. Never live AWS."""
    reports: list[dict[str, Any]] = []
    if getattr(dynamodb, "_TABLE_NAME", None):
        return reports
    items = []
    with dynamodb._local_lock:
        items = list(dynamodb._local_store.values())
    for item in items:
        sk = str(item.get("sk") or "")
        pk = str(item.get("pk") or "")
        if pk in {AUDIT_PK, QUARANTINE_PK, BLOCK_KEY["pk"]}:
            continue
        health_sk = any(sk.startswith(prefix) for prefix in HEALTH_SK_PREFIXES)
        hits = findings_in(item)
        if health_sk or hits:
            reports.append(handle_finding(item, hits or [sk], reason="store"))
    return reports


def deploy_gate() -> None:
    if writes_blocked():
        raise SystemExit("health quarantine block is set; deploy refused")
