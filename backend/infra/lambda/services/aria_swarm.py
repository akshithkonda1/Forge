"""ARIA Swarm — background read / evaluate / write over the wearable dataset.

Long-term this is the Grok-agentic path: when a chat turn starts, Swarm fans
out into whatever the user already has (WHOOP, Apple Watch, Oura / RRA,
Garmin) and builds one actionable picture. Claude still owns the spoken
reply. Swarm owns the dataset pass.

This module is deterministic Python. It never calls Bedrock, Grok, or any
other model — that is the whole point of the dummy/test path. Live Grok
fills the same ``read → evaluate → write`` contract later; until then every
chat turn can still exercise the agentic shape without plugging a model in.

Law:
  * Python owns truth. Headlines never dump vitals.
  * Unknown / untagged samples are attributed to a wearable, not left as
    ``simrunner``.
  * Persist is opt-in. Dummy never writes Dynamo.
"""

from __future__ import annotations

from typing import Any

SCHEMA = "aria-swarm-1"
NAME = "swarm"
SLOT = "tertiary"
SLOT_NAME = "Grok"
STAGES = ("read", "evaluate", "write")

# Canonical wearable sources Swarm knows how to inspect. ``rra`` is the
# recovery-ring alias (Oura in this product). ``apple-health`` is the Watch
# ledger Apple Health already holds.
_CANON = {
    "apple-watch": "apple-watch",
    "applewatch": "apple-watch",
    "watch": "apple-watch",
    "apple-health": "apple-watch",
    "applehealth": "apple-watch",
    "healthkit": "apple-watch",
    "whoop": "whoop",
    "oura": "oura",
    "rra": "oura",
    "garmin": "garmin",
}

_SOURCE_LABEL = {
    "apple-watch": "Apple Watch",
    "whoop": "WHOOP",
    "oura": "Oura",
    "garmin": "Garmin",
}

# What each source is trusted to speak for when samples carry a source tag.
_SOURCE_DOMAINS = {
    "oura": ("sleep",),
    "whoop": ("recovery",),
    "apple-watch": ("activity",),
    "garmin": ("activity", "recovery"),
}

# When a sample has no wearable tag (the dummy used to stamp everything
# ``simrunner``), attribute the metric the way a real stack usually lands:
# recovery ring owns the night, WHOOP owns HRV, Watch owns movement.
_METRIC_SOURCE = {
    "sleep": "oura",
    "sleep-stage": "oura",
    "sleep_duration": "oura",
    "sleep_deep": "oura",
    "sleep_rem": "oura",
    "sleep_light": "oura",
    "sleep_efficiency": "oura",
    "hrv": "whoop",
    "hrv_sdnn": "whoop",
    "recovery": "whoop",
    "readiness": "whoop",
    "resting-heart-rate": "apple-watch",
    "resting_heart_rate": "apple-watch",
    "heart-rate": "apple-watch",
    "heart_rate": "apple-watch",
    "steps": "apple-watch",
    "active-calories": "apple-watch",
    "active_energy": "apple-watch",
    "distance": "apple-watch",
    "exercise_minutes": "apple-watch",
}

_SLEEP_TYPES = frozenset(
    {
        "sleep",
        "sleep-stage",
        "sleep_duration",
        "sleep_deep",
        "sleep_rem",
        "sleep_light",
        "sleep_efficiency",
    }
)
_RECOVERY_TYPES = frozenset(
    {"hrv", "hrv_sdnn", "recovery", "readiness", "resting-heart-rate", "resting_heart_rate"}
)
_ACTIVITY_TYPES = frozenset(
    {
        "steps",
        "active-calories",
        "active_energy",
        "distance",
        "exercise_minutes",
        "heart-rate",
        "heart_rate",
    }
)


def canonical_source(raw: Any) -> str | None:
    """Map a vendor / HealthKit / alias string onto a Swarm source id."""
    key = str(raw or "").strip().lower().replace("_", "-").replace(" ", "-")
    if not key:
        return None
    if key in _CANON:
        return _CANON[key]
    if "whoop" in key:
        return "whoop"
    if "oura" in key or key == "rra":
        return "oura"
    if "garmin" in key:
        return "garmin"
    if "watch" in key or "apple" in key or "healthkit" in key:
        return "apple-watch"
    return None


def source_label(source_id: str) -> str:
    return _SOURCE_LABEL.get(source_id, source_id)


def run_swarm(
    *,
    context: Any | None = None,
    samples: list[Any] | None = None,
    connected: list[str] | None = None,
    persist_to: Any | None = None,
    user_id: str | None = None,
) -> dict[str, Any]:
    """One background swarm pass. Always local. Never a model call.

    ``persist_to`` is a ``CoachContextEngine`` (or anything with
    ``add_insight``). Dummy leaves it None.
    """
    grouped = _group_samples(samples or [])
    reads = _read(context, grouped)
    agents = _evaluate(reads)
    picture = _write(agents, reads)
    envelope = {
        "schema": SCHEMA,
        "name": NAME,
        "slot": SLOT,
        "slot_name": SLOT_NAME,
        "agentic": True,
        "model": None,
        "stages": list(STAGES),
        "sources": [
            {
                "id": source_id,
                "label": source_label(source_id),
                "present": reads[source_id]["present"],
                "domains": list(reads[source_id]["domains"]),
            }
            for source_id in _ordered_sources(reads, connected)
        ],
        "agents": [a.as_dict() for a in agents],
        "picture": picture,
    }
    if persist_to is not None and user_id and picture.get("headline"):
        try:
            persist_to.add_insight(user_id, picture["headline"])
            envelope["wrote"] = True
        except Exception:
            envelope["wrote"] = False
    else:
        envelope["wrote"] = False
    return envelope


def _ordered_sources(reads: dict[str, dict[str, Any]], connected: list[str] | None) -> list[str]:
    order = ("whoop", "apple-watch", "oura", "garmin")
    wanted: list[str] = []
    for raw in connected or []:
        key = canonical_source(raw)
        if key and key not in wanted:
            wanted.append(key)
    if not wanted:
        wanted = [sid for sid in order if reads.get(sid, {}).get("present")]
    if not wanted:
        wanted = [sid for sid in order if sid in reads]
    for sid in order:
        if sid in wanted:
            continue
        if reads.get(sid, {}).get("present"):
            wanted.append(sid)
    return wanted


def _group_samples(samples: list[Any]) -> dict[str, dict[str, list[Any]]]:
    grouped: dict[str, dict[str, list[Any]]] = {}
    for raw in samples:
        metric, source = _sample_metric_and_source(raw)
        if metric is None or source is None:
            continue
        domain = _domain_for_metric(metric)
        if domain is None:
            continue
        bucket = grouped.setdefault(source, {"sleep": [], "recovery": [], "activity": []})
        bucket[domain].append(raw)
    return grouped


def _sample_metric_and_source(raw: Any) -> tuple[str | None, str | None]:
    if raw is None:
        return None, None
    if isinstance(raw, dict):
        metric = str(raw.get("type") or raw.get("metric") or "").strip().lower()
        tagged = canonical_source(
            raw.get("source") or raw.get("provider") or raw.get("device")
        )
    else:
        metric_raw = getattr(raw, "metric", None) or getattr(raw, "type", None)
        if hasattr(metric_raw, "value"):
            metric_raw = metric_raw.value
        metric = str(metric_raw or "").strip().lower()
        tagged = canonical_source(getattr(raw, "source", None))
    metric = metric.replace("_", "-")
    if not metric:
        return None, None
    source = tagged or _METRIC_SOURCE.get(metric.replace("-", "_")) or _METRIC_SOURCE.get(metric)
    return metric, source


def _domain_for_metric(metric: str) -> str | None:
    key = metric.replace("_", "-")
    alt = metric.replace("-", "_")
    if key in _SLEEP_TYPES or alt in _SLEEP_TYPES:
        return "sleep"
    if key in _RECOVERY_TYPES or alt in _RECOVERY_TYPES:
        return "recovery"
    if key in _ACTIVITY_TYPES or alt in _ACTIVITY_TYPES:
        return "activity"
    return None


def _read(context: Any | None, grouped: dict[str, dict[str, list[Any]]]) -> dict[str, dict[str, Any]]:
    """Inspect each wearable slice. Words, never the raw fields."""
    sleep = _sleep_band(context)
    recovery = _recovery_band(context)
    activity = _activity_band(context)
    has_samples = bool(grouped)

    reads: dict[str, dict[str, Any]] = {}
    for source_id, domains in _SOURCE_DOMAINS.items():
        present_domains: list[str] = []
        notes: dict[str, str] = {}
        for domain in domains:
            from_samples = bool(grouped.get(source_id, {}).get(domain))
            from_context = _context_has(domain, sleep, recovery, activity)
            # Context-only turns get a virtual split (Oura night, WHOOP
            # recovery, Watch movement). Once real samples exist, a source
            # is present only when it actually contributed.
            inferred = from_context and (from_samples or not has_samples)
            if from_samples or inferred:
                present_domains.append(domain)
                notes[domain] = {
                    "sleep": sleep or "unknown",
                    "recovery": recovery or "unknown",
                    "activity": activity or "quiet",
                }[domain]
            else:
                notes[domain] = "missing"
        reads[source_id] = {
            "present": bool(present_domains),
            "domains": present_domains,
            "notes": notes,
        }
    # A connected source with samples in an unexpected domain still counts.
    for source_id, buckets in grouped.items():
        if source_id not in reads:
            present = [d for d, rows in buckets.items() if rows]
            reads[source_id] = {
                "present": bool(present),
                "domains": present,
                "notes": {d: "info" for d in present},
            }
            continue
        extra = [d for d, rows in buckets.items() if rows and d not in reads[source_id]["domains"]]
        if extra:
            reads[source_id]["domains"] = list(reads[source_id]["domains"]) + extra
            reads[source_id]["present"] = True
            for domain in extra:
                reads[source_id]["notes"][domain] = {
                    "sleep": sleep or "unknown",
                    "recovery": recovery or "unknown",
                    "activity": activity or "quiet",
                }.get(domain, "info")
    return reads


def _context_has(domain: str, sleep: str, recovery: str, activity: str) -> bool:
    if domain == "sleep":
        return sleep not in ("", "unknown")
    if domain == "recovery":
        return recovery not in ("", "unknown")
    if domain == "activity":
        return activity not in ("", "quiet")
    return False


class _Agent:
    def __init__(self, source: str, kind: str, stance: str, read: str, evaluate: str, write: str):
        self.source = source
        self.kind = kind
        self.stance = stance
        self.read = read
        self.evaluate = evaluate
        self.write = write

    @property
    def id(self) -> str:
        return f"{self.source}-{self.kind}"

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "source": self.source,
            "source_label": source_label(self.source),
            "ops": list(STAGES),
            "stance": self.stance,
            "read": self.read,
            "evaluate": self.evaluate,
            "write": self.write,
        }


def _evaluate(reads: dict[str, dict[str, Any]]) -> list[_Agent]:
    agents: list[_Agent] = []
    for source_id in ("whoop", "apple-watch", "oura", "garmin"):
        info = reads.get(source_id) or {"present": False, "domains": [], "notes": {}}
        if source_id == "garmin" and not info.get("present"):
            continue
        domains = list(info.get("domains") or _SOURCE_DOMAINS.get(source_id, ()))
        if not domains:
            domains = list(_SOURCE_DOMAINS.get(source_id, ()))
        for domain in domains:
            note = (info.get("notes") or {}).get(domain) or "missing"
            present = bool(info.get("present")) and domain in (info.get("domains") or [])
            stance, read, evaluate, write = _agent_copy(
                source_id, domain, note, present=present
            )
            agents.append(_Agent(source_id, domain, stance, read, evaluate, write))
    return agents


def _agent_copy(source: str, domain: str, note: str, *, present: bool) -> tuple[str, str, str, str]:
    label = source_label(source)
    if not present or note in ("missing", "unknown"):
        return (
            "missing",
            f"{label} has no {domain} read in yet.",
            f"Won't invent a {domain} picture from {label}.",
            f"Leave {domain} open until {label} lands.",
        )
    if domain == "sleep":
        if note == "thin":
            return (
                "caution",
                f"{label} has the night.",
                "The night ran thin, so today should protect tomorrow.",
                "Protect sleep before adding load.",
            )
        if note == "rebuilt":
            return (
                "go",
                f"{label} has the night.",
                "Sleep has been catching up — there is something to spend.",
                "One honest session is on the table if recovery agrees.",
            )
        return (
            "info",
            f"{label} has the night.",
            "Sleep is decent, not a story.",
            "Keep the night in the picture; don't overclaim it.",
        )
    if domain == "recovery":
        if note == "asking":
            return (
                "caution",
                f"{label} has recovery.",
                "The body is asking for care, not a lecture.",
                "Keep today kind.",
            )
        if note == "ready":
            return (
                "go",
                f"{label} has recovery.",
                "Recovery is steady enough for real work.",
                "Train inside what the day already holds.",
            )
        return (
            "info",
            f"{label} has recovery.",
            "Recovery is workable, not sharp.",
            "Don't pick a fight with the day.",
        )
    # activity
    if note in ("in_the_legs", "on_a_streak"):
        return (
            "info",
            f"{label} logged movement.",
            "Last session is still in the legs.",
            "Train if you want — don't pretend it didn't happen.",
        )
    if note == "fresh":
        return (
            "go",
            f"{label} has activity.",
            "It's been a minute — the body can take real work if the night agrees.",
            "A full session is allowed, not required.",
        )
    return (
        "info",
        f"{label} has activity.",
        "Movement is quiet today.",
        "Fit training into the day you already have.",
    )


def _write(agents: list[_Agent], reads: dict[str, dict[str, Any]]) -> dict[str, Any]:
    stances = [a.stance for a in agents]
    if "caution" in stances:
        stance = "protect"
    elif stances and all(s == "missing" for s in stances):
        stance = "clarify"
    elif "go" in stances and "caution" not in stances:
        stance = "proceed"
    else:
        stance = "proceed"

    present = [
        source_label(sid)
        for sid, info in reads.items()
        if info.get("present")
    ]
    caution = [a for a in agents if a.stance == "caution"]
    missing = [a for a in agents if a.stance == "missing"]
    go = [a for a in agents if a.stance == "go"]

    if caution:
        headline = caution[0].evaluate
    elif go and stance == "proceed":
        headline = go[0].evaluate
    elif missing and not present:
        headline = "No wearable picture is in yet, so I won't pretend I have a clean read."
    else:
        headline = "I looked across the wearables you already have. One next move from there."

    if stance == "protect":
        actions = ["Keep it light today", "How did I sleep?"]
    elif stance == "clarify":
        actions = ["How did I sleep?", "What should I train?"]
    else:
        actions = ["What should I train?", "How did I sleep?"]

    writes = [
        {
            "kind": "swarm_picture",
            "summary": headline,
            "source": NAME,
            "stance": stance,
        }
    ]
    for agent in agents:
        if agent.stance == "missing":
            continue
        writes.append(
            {
                "kind": f"swarm_{agent.kind}",
                "summary": agent.write,
                "source": agent.source,
                "stance": agent.stance,
            }
        )
    return {
        "headline": headline,
        "stance": stance,
        "actions": actions,
        "writes": writes,
        "wearables": present,
    }


def _sleep_band(context: Any | None) -> str:
    hours = _sleep_hours(context)
    if hours is None:
        return "unknown"
    if hours < 6.4:
        return "thin"
    if hours >= 7.4:
        return "rebuilt"
    return "decent"


def _recovery_band(context: Any | None) -> str:
    if context is None:
        return "unknown"
    today = getattr(context, "today", None)
    readiness = None
    if today is not None:
        readiness = getattr(today, "readiness_score", None)
    readiness_ctx = getattr(context, "readiness", None)
    if readiness is None and readiness_ctx is not None:
        readiness = getattr(readiness_ctx, "recovery_score", None)
    overtrained = bool(getattr(context, "is_overtrained", False))
    debt = getattr(context, "sleep_debt_7d_hours", None)
    trend = getattr(context, "readiness_trend", None)
    if readiness_ctx is not None and getattr(readiness_ctx, "hrv_7day_trend", None) is not None:
        try:
            if float(readiness_ctx.hrv_7day_trend) <= -8:
                return "asking"
        except (TypeError, ValueError):
            pass
    if readiness is None and not overtrained:
        hrv = _hrv(context)
        if hrv is None:
            return "unknown"
    if overtrained:
        return "asking"
    try:
        score = float(readiness) if readiness is not None else None
    except (TypeError, ValueError):
        score = None
    if score is not None and score < 50:
        return "asking"
    try:
        if debt is not None and float(debt) > 5.0:
            return "asking"
    except (TypeError, ValueError):
        pass
    if score is not None and score >= 75 and trend != "falling":
        return "ready"
    if score is None:
        return "unknown"
    return "steady"


def _activity_band(context: Any | None) -> str:
    if context is None:
        return "quiet"
    today = getattr(context, "today", None)
    logged = bool(getattr(today, "workout_logged", False)) if today is not None else False
    streak = int(getattr(context, "training_streak", 0) or 0)
    days = getattr(context, "days_since_last_workout", None)
    training = getattr(context, "training", None)
    if training is not None and getattr(training, "hours_since_last_workout", None) is not None:
        try:
            hours = float(training.hours_since_last_workout)
            logged = logged or hours <= 12
            if days is None:
                days = int(hours / 24.0)
        except (TypeError, ValueError):
            pass
    if streak >= 3:
        return "on_a_streak"
    if logged or days == 0:
        return "in_the_legs"
    try:
        if days is not None and int(days) >= 3:
            return "fresh"
    except (TypeError, ValueError):
        pass
    return "quiet"


def _sleep_hours(context: Any | None) -> float | None:
    if context is None:
        return None
    sleep = getattr(context, "sleep", None)
    if sleep is not None:
        mins = getattr(sleep, "duration_minutes", None)
        if mins is not None:
            try:
                return float(mins) / 60.0
            except (TypeError, ValueError):
                pass
    today = getattr(context, "today", None)
    if today is not None:
        hours = getattr(today, "total_sleep_hours", None)
        if hours is not None:
            try:
                return float(hours)
            except (TypeError, ValueError):
                pass
    return None


def _hrv(context: Any | None) -> float | None:
    if context is None:
        return None
    sleep = getattr(context, "sleep", None)
    if sleep is not None and getattr(sleep, "hrv", None) is not None:
        try:
            return float(sleep.hrv)
        except (TypeError, ValueError):
            pass
    today = getattr(context, "today", None)
    if today is not None and getattr(today, "hrv", None) is not None:
        try:
            return float(today.hrv)
        except (TypeError, ValueError):
            pass
    return None
