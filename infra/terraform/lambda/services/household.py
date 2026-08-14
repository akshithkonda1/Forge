"""Household members ARIA supports — names and roles, never cycle data.

Cycle Partner lives on-device (CloudKit). This store only remembers who you
show up for so ARIA can speak to a partner and a daughter as different people,
not as a single optional pulse.
"""

from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any

from storage import dynamodb, keys

ROLES = {"partner", "child", "family", "friend"}
_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,40}$")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load(user_id: str) -> dict[str, Any]:
    item = dynamodb.get_item(**keys.household_key(user_id)) or {}
    members = item.get("members") if isinstance(item.get("members"), list) else []
    return {"members": members, "updatedAt": item.get("updatedAt")}


def replace(user_id: str, incoming: list[Any]) -> dict[str, Any]:
    members = []
    seen = set()
    for raw in incoming[:8]:
        if not isinstance(raw, dict):
            continue
        ident = str(raw.get("id") or "").strip().lower()
        name = str(raw.get("name") or "").strip()[:40]
        role = str(raw.get("role") or "partner").strip().lower()
        if role not in ROLES:
            role = "partner"
        if not _ID_RE.match(ident) or len(name) < 1:
            continue
        if ident in seen:
            continue
        seen.add(ident)
        members.append(
            {
                "id": ident,
                "name": name,
                "role": role,
                "earlyCycles": bool(raw.get("earlyCycles")),
                "relationship": str(raw.get("relationship") or role)[:32],
            }
        )
    payload = {"members": members, "updatedAt": _now()}
    dynamodb.put_item({**keys.household_key(user_id), **payload})
    return payload


def briefing_for_chat(user_id: str) -> str | None:
    members = load(user_id).get("members") or []
    if not members:
        return None
    bits = []
    for member in members:
        role = member.get("role")
        name = member.get("name")
        if role == "child":
            if member.get("earlyCycles"):
                bits.append(
                    f"You support {name} as a parent — early cycles. "
                    "Practical, private, never cute, never a lecture."
                )
            else:
                bits.append(
                    f"You support {name} as a parent. Dignity and logistics, not commentary."
                )
        elif role == "partner":
            bits.append(
                f"You support {name} as a partner. Mindset and load, not mood-as-excuse."
            )
        else:
            bits.append(f"You support {name} ({role}). Show up; don't narrate their body.")
    return "Household ARIA is holding: " + " | ".join(bits)
