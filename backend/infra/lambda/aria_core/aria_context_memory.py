"""Adaptive ARIA context — Python twin of ForgeCore AriaContextMemory.

Dreams and health stay off the server unless the matching opt-in is on.
Deletes propagate as tombstones. Bedrock stays off. Retrieval is ranked
by learned relevance + recency + confidence — a linear, inspectable
formula, never a dump and never a black-box model.
"""

from __future__ import annotations

from typing import Any

DOMAINS = (
    "sleep_dreams",
    "lifestyle_hobbies",
    "people",
    "goals",
    "health_constraints",
    "mood_mentality",
)
SENSITIVE = {"sleep_dreams", "health_constraints"}
BEDROCK_OFF = True
BACKUP_EXCLUDED = True
RANK_FORMULA = "learnedRelevance + recency + 1.2*confidence + userOverride"

CAPS = {"stm": 64, "vault": 320, "userContext": 48, "pageSize": 20}


def classify(text: str, source: str = "") -> str:
    blob = f"{text} {source}".lower()
    if any(w in blob for w in ("dream", "nightmare", "lucid")):
        return "sleep_dreams"
    if any(w in blob for w in ("seizure", "epilep", "injur", "condition", "medication")):
        return "health_constraints"
    if "goal" in blob or "this season" in blob:
        return "goals"
    if any(w in blob for w in ("hobby", "free day", "pottery", "cooking", "walk")):
        return "lifestyle_hobbies"
    if any(w in blob for w in ("partner", "friend", "people")):
        return "people"
    if any(w in blob for w in ("mood", "stress", "drained", "quiet stretch")):
        return "mood_mentality"
    if any(w in blob for w in ("sleep", "night")):
        return "sleep_dreams"
    return "lifestyle_hobbies"


def fingerprint(domain: str, text: str) -> str:
    return f"{domain}|{text.lower()}"


def useful(stats: dict[str, Any] | None) -> float:
    stats = stats or {}
    good = float(stats.get("replied", 0) + stats.get("acted", 0))
    bad = float(stats.get("ignored", 0) + stats.get("corrected", 0))
    return good - 0.6 * bad


def learned_relevance(signals: dict[str, Any] | None) -> float:
    signals = signals or {}
    return (
        float(signals.get("replied", 0)) * 1.0
        + float(signals.get("acted", 0)) * 1.25
        + float(signals.get("surfaced", 0)) * 0.05
        - float(signals.get("ignored", 0)) * 0.7
        - float(signals.get("corrected", 0)) * 0.9
    )


def recency(updated_at: float, now: float) -> float:
    age = max(0.0, (now - updated_at) / (60 * 24 * 3600))
    return max(0.0, 1.0 - age)


def explain(item: dict[str, Any], stats: dict[str, Any], now: float) -> dict[str, Any]:
    domain = str(item.get("domain") or "")
    learned = learned_relevance(item.get("signals")) + 0.25 * useful(stats.get(domain))
    rec = recency(float(item.get("updatedAt") or now), now)
    conf = float(item.get("confidence") or 0.55)
    override = 10.0 if item.get("userLocked") else 0.0
    total = learned + rec + 1.2 * conf + override
    return {
        "learnedRelevance": learned,
        "recency": rec,
        "confidence": conf,
        "userOverride": override,
        "total": total,
        "formula": RANK_FORMULA,
    }


def rank(items: list[dict[str, Any]], stats: dict[str, Any], now: float) -> list[dict[str, Any]]:
    active = [row for row in items if not row.get("supersededBy")]
    return sorted(active, key=lambda row: explain(row, stats, now)["total"], reverse=True)


def granularity(domain: str, stats: dict[str, Any]) -> str:
    return "fine" if useful(stats.get(domain)) >= 2 else "coarse"


def decay_half_life_days(domain: str, stats: dict[str, Any]) -> float:
    u = useful(stats.get(domain))
    if u >= 4:
        return 28.0
    if u >= 1:
        return 16.0
    return 8.0


def item_decay_half_life_days(item: dict[str, Any], stats: dict[str, Any]) -> float:
    half = decay_half_life_days(str(item.get("domain") or ""), stats)
    rel = learned_relevance(item.get("signals"))
    if rel >= 2:
        half *= 1.5
    elif rel <= -1:
        half *= 0.55
    return max(4.0, min(45.0, half))


def retention_priority(domain: str, stats: dict[str, Any]) -> float:
    row = stats.get(domain) or {}
    mentions = float(row.get("mentions", 0))
    return 1.0 + useful(row) + 0.15 * mentions


def retain(items: list[dict[str, Any]], stats: dict[str, Any], now: float, cap: int) -> list[dict[str, Any]]:
    locked = [row for row in items if row.get("userLocked") and not row.get("supersededBy")]
    unlocked = [row for row in items if not row.get("userLocked") and not row.get("supersededBy")]
    ranked = rank(unlocked, stats, now)
    kept = ranked[:cap]
    return locked + kept


def bump(stats: dict[str, Any], domain: str, kind: str, mentions: int = 0) -> dict[str, Any]:
    next_stats = dict(stats)
    row = dict(next_stats.get(domain) or {})
    row[kind] = int(row.get(kind, 0)) + 1
    if mentions:
        row["mentions"] = int(row.get("mentions", 0)) + mentions
    next_stats[domain] = row
    return next_stats


def bump_item(item: dict[str, Any], kind: str) -> dict[str, Any]:
    next_item = dict(item)
    signals = dict(next_item.get("signals") or {})
    signals[kind] = int(signals.get(kind, 0)) + 1
    next_item["signals"] = signals
    return next_item


def record(item: dict[str, Any], stats: dict[str, Any], kind: str) -> tuple[dict[str, Any], dict[str, Any]]:
    domain = str(item.get("domain") or "")
    return bump_item(item, kind), bump(stats, domain, kind)


def server_context(items: list[dict[str, Any]], share: dict[str, bool] | None = None) -> dict[str, str]:
    share = share or {"shareDreams": False, "shareHealth": False}
    allowed: list[dict[str, Any]] = []
    for item in items:
        domain = str(item.get("domain") or "")
        opt = bool(item.get("shareOptIn"))
        if domain == "sleep_dreams" and not (share.get("shareDreams") and opt):
            continue
        if domain == "health_constraints" and not (share.get("shareHealth") and opt):
            continue
        allowed.append(item)
    ranked = allowed[:12]
    out: dict[str, str] = {}
    if ranked:
        out["context_summaries"] = " | ".join(
            str(row.get("summary") or row.get("text") or "")[:96] for row in ranked
        )
        out["context_domains"] = ",".join(str(row.get("domain") or "") for row in ranked)
    return out


def apply_tombstones(payload: dict[str, Any], tombstones: list[dict[str, Any]]) -> dict[str, Any]:
    dead = {str(t.get("id")) for t in tombstones if t.get("id")}
    fingerprints = {str(t.get("fingerprint")) for t in tombstones if t.get("fingerprint")}
    if not dead and not fingerprints:
        return payload
    items = []
    for row in payload.get("items") or []:
        if not isinstance(row, dict):
            continue
        if str(row.get("id")) in dead:
            continue
        fp = fingerprint(str(row.get("domain") or ""), str(row.get("text") or ""))
        if fp in fingerprints:
            continue
        items.append(row)
    next_payload = dict(payload)
    next_payload["items"] = items
    return next_payload


def contains_sensitive_leak(payload: dict[str, str], share: dict[str, bool] | None = None) -> bool:
    share = share or {"shareDreams": False, "shareHealth": False}
    blob = " ".join(str(v) for v in payload.values()).lower()
    if not share.get("shareDreams") and "dream" in blob:
        return True
    if not share.get("shareHealth") and ("seizure" in blob or "epilep" in blob):
        return True
    return False
