from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

from responses import RouteError, ok
from storage import dynamodb, keys

_CATALOG_PATH = Path(__file__).resolve().parent.parent / "data" / "health_device_catalog.json"
_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,63}$")
_REQUIRED_FIELDS = (
    "id",
    "name",
    "maker",
    "category",
    "summary",
    "metrics",
    "writesToAppleHealth",
    "hasIOSApp",
    "worksWithAppleWatch",
    "setupHint",
    "symbolName",
    "line",
    "generation",
    "releasedYear",
)


def load_static_catalog() -> dict:
    if _CATALOG_PATH.exists():
        payload = json.loads(_CATALOG_PATH.read_text())
    else:
        payload = {}
    payload.setdefault("version", 1)
    payload.setdefault("devices", [])
    payload.setdefault("retire", [])
    if not payload.get("updatedAt"):
        payload["updatedAt"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    return payload


def _stored_devices() -> list[dict]:
    items = dynamodb.query_prefix(keys.CATALOG_PK, keys.catalog_device_sk_prefix())
    devices = []
    for item in items:
        device = item.get("device")
        if isinstance(device, dict) and device.get("id"):
            devices.append(device)
    return devices


def handle_get_devices_catalog() -> dict:
    static = load_static_catalog()
    by_id: dict[str, dict] = {}
    for device in static.get("devices") or []:
        if isinstance(device, dict) and device.get("id"):
            by_id[str(device["id"])] = device
    for device in _stored_devices():
        by_id[str(device["id"])] = device
    for retired in static.get("retire") or []:
        by_id.pop(str(retired), None)
    return ok(
        {
            "version": int(static.get("version") or 1),
            "updatedAt": static.get("updatedAt"),
            "devices": list(by_id.values()),
            "retire": list(static.get("retire") or []),
        }
    )


def handle_post_devices_seen(body: dict) -> dict:
    incoming = body.get("devices")
    if not isinstance(incoming, list):
        raise RouteError(400, "Request body must include a 'devices' array.")
    if len(incoming) > 20:
        raise RouteError(400, "At most 20 devices can be reported at once.")

    accepted = 0
    for raw in incoming:
        device = _validated_device(raw)
        if device is None:
            continue
        dynamodb.put_item(
            {
                **keys.catalog_device_key(device["id"]),
                "device": device,
                "updatedAt": datetime.now(timezone.utc).isoformat(),
            }
        )
        accepted += 1
    return ok({"accepted": accepted})


def _validated_device(raw: object) -> dict | None:
    if not isinstance(raw, dict):
        return None
    for field in _REQUIRED_FIELDS:
        if field not in raw:
            return None
    ident = str(raw.get("id") or "")
    if not _ID_RE.match(ident):
        return None
    name = str(raw.get("name") or "").strip()
    if len(name) < 2 or len(name) > 80:
        return None
    try:
        generation = int(raw["generation"])
        released_year = int(raw["releasedYear"])
    except (TypeError, ValueError):
        return None
    metrics = raw.get("metrics")
    if not isinstance(metrics, list) or not metrics:
        return None
    return {
        "id": ident,
        "name": name,
        "maker": str(raw.get("maker") or name)[:40],
        "category": str(raw.get("category") or "wearable")[:24],
        "summary": str(raw.get("summary") or "")[:240],
        "metrics": [str(item)[:40] for item in metrics[:8]],
        "writesToAppleHealth": bool(raw.get("writesToAppleHealth")),
        "hasIOSApp": bool(raw.get("hasIOSApp")),
        "worksWithAppleWatch": bool(raw.get("worksWithAppleWatch")),
        "appStoreURL": raw.get("appStoreURL"),
        "setupHint": str(raw.get("setupHint") or "")[:240],
        "symbolName": str(raw.get("symbolName") or "sensor.tag.radiowaves.forward")[:64],
        "line": str(raw.get("line") or ident)[:64],
        "generation": generation,
        "releasedYear": released_year,
        "stillCompatible": bool(raw.get("stillCompatible", True)),
        "photoURL": raw.get("photoURL"),
    }
