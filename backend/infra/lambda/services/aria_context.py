from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any

from storage import dynamodb, keys


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _parse_dt(value: Any) -> datetime | None:
    """Parse an ISO-8601 string (or pass through a datetime) into aware UTC.

    Returns None for anything unparseable so callers can decide the fallback —
    fabricating a timestamp for a bad input is how a "wedding in three weeks"
    silently becomes "wedding right now" and never expires.
    """
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _dedupe_keep_order(values: list[str], *, cap: int | None = None) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        norm = value.strip()
        if not norm or norm.lower() in seen:
            continue
        seen.add(norm.lower())
        out.append(norm)
    return out[:cap] if cap is not None else out


def _slug(text: str) -> str:
    """Deterministic id fragment from free text (stable across processes)."""
    return hashlib.sha1(text.strip().lower().encode("utf-8")).hexdigest()[:16]


def _humanize_when(when: datetime | None, now: datetime) -> str:
    """Human-friendly relative time: 'today', 'tomorrow', 'in 3 days', 'in 2 weeks'."""
    if when is None:
        return "sometime"
    days = (when.date() - now.date()).days
    if days < 0:
        return "recently"
    if days == 0:
        return "today"
    if days == 1:
        return "tomorrow"
    if days < 14:
        return f"in {days} days"
    if days < 60:
        return f"in {days // 7} weeks"
    return f"in {days // 30} months"


@dataclass
class UserContext:
    """ARIA's *long-term* memory — the durable "what ARIA knows about you".

    This is companion memory (goals, relationships, preferences, running
    themes), not a clinical chart. Transient, event-anchored items ("wedding in
    three weeks") live in the separate short-term store (``MemoryItem``) and
    expire on their own.
    """

    user_id: str
    lifestyle_tags: list[str] = field(default_factory=list)
    current_goals: list[str] = field(default_factory=list)
    constraints: list[str] = field(default_factory=list)
    recent_patterns: list[str] = field(default_factory=list)
    last_insights: list[str] = field(default_factory=list)
    # Durable facts ARIA has learned about the user's life — the substance of the
    # bond ("training for a first 10k", "sister's wedding matters to them").
    life_facts: list[str] = field(default_factory=list)
    relationship_level: int = 1
    last_updated: datetime = field(default_factory=_utcnow)
    last_promoted_at: datetime | None = None
    # Day-to-day companion cadence: last memory self-evaluation and last check-in.
    last_evaluated_at: datetime | None = None
    last_checkin_at: datetime | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "user_id": self.user_id,
            "lifestyle_tags": self.lifestyle_tags,
            "current_goals": self.current_goals,
            "constraints": self.constraints,
            "recent_patterns": self.recent_patterns,
            "last_insights": self.last_insights,
            "life_facts": self.life_facts,
            "relationship_level": self.relationship_level,
            "last_updated": self.last_updated.isoformat(),
            "last_promoted_at": self.last_promoted_at.isoformat() if self.last_promoted_at else None,
            "last_evaluated_at": self.last_evaluated_at.isoformat() if self.last_evaluated_at else None,
            "last_checkin_at": self.last_checkin_at.isoformat() if self.last_checkin_at else None,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> UserContext:
        parsed = _parse_dt(data.get("last_updated")) or _utcnow()
        return cls(
            user_id=str(data.get("user_id", "")),
            lifestyle_tags=list(data.get("lifestyle_tags") or []),
            current_goals=list(data.get("current_goals") or []),
            constraints=list(data.get("constraints") or []),
            recent_patterns=list(data.get("recent_patterns") or []),
            last_insights=list(data.get("last_insights") or []),
            life_facts=list(data.get("life_facts") or []),
            relationship_level=int(data.get("relationship_level") or 1),
            last_updated=parsed,
            last_promoted_at=_parse_dt(data.get("last_promoted_at")),
            last_evaluated_at=_parse_dt(data.get("last_evaluated_at")),
            last_checkin_at=_parse_dt(data.get("last_checkin_at")),
        )


@dataclass
class MemoryItem:
    """ARIA's *short-term* memory — transient, often event-anchored.

    "I've got a wedding in three weeks." ARIA holds it while it's relevant and
    forgets it once ``expires_at`` passes. A ``ttl`` (epoch seconds) is stored so
    DynamoDB auto-reaps it server-side, but reads also filter on ``expires_at``
    because DynamoDB TTL deletion is only eventually consistent (and the local
    dev store never expires on its own).
    """

    id: str
    text: str
    source: str = "conversation"   # conversation | calendar | ...
    category: str = "note"         # note | event | trait | ...
    created_at: datetime = field(default_factory=_utcnow)
    expires_at: datetime | None = None
    event_at: datetime | None = None

    def is_active(self, now: datetime) -> bool:
        return self.expires_at is None or self.expires_at > now

    def to_item(self, user_id: str) -> dict[str, Any]:
        key = keys.aria_short_term_key(user_id, self.id)
        item: dict[str, Any] = {
            "pk": key["pk"],
            "sk": key["sk"],
            "mem_id": self.id,
            "text": self.text,
            "source": self.source,
            "category": self.category,
            "created_at": self.created_at.isoformat(),
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "event_at": self.event_at.isoformat() if self.event_at else None,
        }
        if self.expires_at is not None:
            # DynamoDB TTL attribute (epoch seconds). Harmless in the local store.
            item["ttl"] = int(self.expires_at.timestamp())
        return item

    @classmethod
    def from_item(cls, item: dict[str, Any]) -> MemoryItem:
        return cls(
            id=str(item.get("mem_id") or str(item.get("sk", "")).split("#")[-1]),
            text=str(item.get("text") or ""),
            source=str(item.get("source") or "conversation"),
            category=str(item.get("category") or "note"),
            created_at=_parse_dt(item.get("created_at")) or _utcnow(),
            expires_at=_parse_dt(item.get("expires_at")),
            event_at=_parse_dt(item.get("event_at")),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "text": self.text,
            "source": self.source,
            "category": self.category,
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "event_at": self.event_at.isoformat() if self.event_at else None,
        }


@dataclass
class MemoryReview:
    """Result of ARIA's daily memory self-evaluation."""

    evaluated_at: datetime
    forgotten: list[str] = field(default_factory=list)
    graduated: list[str] = field(default_factory=list)
    kept: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "evaluated_at": self.evaluated_at.isoformat(),
            "forgotten": self.forgotten,
            "graduated": self.graduated,
            "kept": self.kept,
        }


@dataclass
class CheckinPrompt:
    """A daily "anything new?" check-in ARIA offers the user."""

    text: str
    date: str
    upcoming: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {"text": self.text, "date": self.date, "upcoming": self.upcoming}


class CoachContextEngine:
    """Layer 2 — persistent contextual model for ARIA."""

    def get_or_create_context(self, user_id: str) -> UserContext:
        key = keys.aria_context_key(user_id)
        item = dynamodb.get_item(key["pk"], key["sk"])
        if item and item.get("payload"):
            return UserContext.from_dict(item["payload"])
        return UserContext(user_id=user_id)

    def update_context(self, user_id: str, updates: dict[str, Any]) -> UserContext:
        context = self.get_or_create_context(user_id)
        for field_name, value in updates.items():
            if hasattr(context, field_name):
                setattr(context, field_name, value)
        context.last_updated = _utcnow()
        self._save(user_id, context)
        return context

    def build_rich_context(self, user_id: str, recent_metrics: dict[str, float]) -> dict[str, Any]:
        context = self.get_or_create_context(user_id)
        patterns = list(context.recent_patterns)
        readiness = recent_metrics.get("readiness", 0)
        if readiness and readiness < 55 and "low_readiness_streak" not in patterns:
            patterns.append("low_readiness_streak")
        sleep_score = recent_metrics.get("sleep_score", 0)
        if sleep_score >= 85 and "strong_sleep_recovery" not in patterns:
            patterns.append("strong_sleep_recovery")

        if patterns != context.recent_patterns:
            context.recent_patterns = patterns
            self._save(user_id, context)

        return {
            "user_id": user_id,
            "lifestyle_tags": context.lifestyle_tags,
            "goals": context.current_goals,
            "constraints": context.constraints,
            "recent_patterns": patterns,
            "recent_metrics": recent_metrics,
            "relationship_level": context.relationship_level,
            "timestamp": _utcnow().isoformat(),
        }

    def add_insight(self, user_id: str, insight: str) -> UserContext:
        context = self.get_or_create_context(user_id)
        context.last_insights.insert(0, insight)
        if len(context.last_insights) > 15:
            context.last_insights.pop()
        context.last_updated = _utcnow()
        self._save(user_id, context)
        return context

    def memory_reference(self, user_id: str, message: str) -> str | None:
        context = self.get_or_create_context(user_id)
        if context.relationship_level < 2 or not context.last_insights:
            return None
        lower = message.lower()
        if any(token in lower for token in ("tired", "recovery", "sleep", "exhausted")):
            return f"Last time you felt like this, we focused on recovery — {context.last_insights[0]}"
        return None

    # ------------------------------------------------------------------
    # Long-term memory: durable facts ARIA knows about the user.
    # ------------------------------------------------------------------
    def record_life_fact(self, user_id: str, fact: str, *, cap: int = 50) -> UserContext:
        fact = fact.strip()
        if not fact:
            return self.get_or_create_context(user_id)
        context = self.get_or_create_context(user_id)
        context.life_facts = _dedupe_keep_order([fact, *context.life_facts], cap=cap)
        context.last_updated = _utcnow()
        self._save(user_id, context)
        return context

    # ------------------------------------------------------------------
    # Short-term memory: transient, event-anchored items with TTL.
    # ------------------------------------------------------------------
    def remember_short_term(
        self,
        user_id: str,
        text: str,
        *,
        source: str = "conversation",
        category: str = "note",
        expires_at: datetime | None = None,
        event_at: datetime | None = None,
        mem_id: str | None = None,
        now: datetime | None = None,
    ) -> MemoryItem | None:
        text = text.strip()
        if not text:
            return None
        now = now or _utcnow()
        # A default horizon so a note without an explicit expiry still ages out
        # instead of living forever in the "short-term" store. Traits are the
        # exception: they are durable observations staged for graduation into
        # long-term memory, so they must not silently expire (and get forgotten)
        # before the next daily evaluation promotes them.
        if expires_at is None and category != "trait":
            expires_at = (event_at + timedelta(days=1)) if event_at else (now + timedelta(days=14))
        item = MemoryItem(
            id=mem_id or _slug(f"{category}:{text}:{event_at.isoformat() if event_at else ''}"),
            text=text,
            source=source,
            category=category,
            created_at=now,
            expires_at=expires_at,
            event_at=event_at,
        )
        dynamodb.put_item(item.to_item(user_id))
        return item

    def short_term_memories(
        self,
        user_id: str,
        *,
        now: datetime | None = None,
        include_expired: bool = False,
    ) -> list[MemoryItem]:
        now = now or _utcnow()
        pk = keys.user_pk(user_id)
        rows = dynamodb.query_prefix(pk, keys.aria_short_term_prefix())
        items = [MemoryItem.from_item(row) for row in rows]
        if not include_expired:
            items = [m for m in items if m.is_active(now)]
        # Soonest event first, then soonest expiry, then newest — so "what's
        # coming up" reads naturally and deterministically.
        far = datetime.max.replace(tzinfo=timezone.utc)
        items.sort(key=lambda m: (m.event_at or m.expires_at or far, m.created_at))
        return items

    def forget_short_term(self, user_id: str, mem_id: str) -> None:
        key = keys.aria_short_term_key(user_id, mem_id)
        dynamodb.delete_item(key["pk"], key["sk"])

    def ingest_calendar_events(
        self,
        user_id: str,
        events: list[dict[str, Any]] | None,
        *,
        now: datetime | None = None,
        horizon_days: int = 120,
    ) -> list[MemoryItem]:
        """Ingest normalized calendar events (Apple/Google) into short-term memory.

        Provider-agnostic: each event is a dict with a title (``title`` /
        ``summary`` / ``name``) and ``start`` (+ optional ``end``) as ISO strings.
        Past events are skipped; events beyond the horizon are ignored until they
        get closer; re-ingesting the same event overwrites rather than duplicates
        (deterministic id from title + start).
        """
        if not events:
            return []
        now = now or _utcnow()
        horizon = now + timedelta(days=horizon_days)
        ingested: list[MemoryItem] = []
        for event in events:
            if not isinstance(event, dict):
                continue
            title = str(
                event.get("title") or event.get("summary") or event.get("name") or ""
            ).strip()
            start = _parse_dt(event.get("start") or event.get("start_at") or event.get("date"))
            if not title or start is None:
                continue
            end = _parse_dt(event.get("end") or event.get("end_at")) or (start + timedelta(hours=1))
            # Keep it while it's relevant: until the day after it ends.
            expires_at = end + timedelta(days=1)
            if expires_at <= now or start > horizon:
                continue
            item = self.remember_short_term(
                user_id,
                f"{title} on {start.date().isoformat()}",
                source="calendar",
                category="event",
                expires_at=expires_at,
                event_at=start,
                mem_id=_slug(f"calendar:{title}:{start.isoformat()}"),
                now=now,
            )
            if item is not None:
                ingested.append(item)
        ingested.sort(key=lambda m: (m.event_at or m.expires_at or now, m.created_at))
        return ingested

    # ------------------------------------------------------------------
    # Daily companion cadence: self-evaluation + check-in.
    # ------------------------------------------------------------------
    def needs_daily_evaluation(self, user_id: str, *, now: datetime | None = None) -> bool:
        now = now or _utcnow()
        context = self.get_or_create_context(user_id)
        last = context.last_evaluated_at
        return last is None or last.date() != now.date()

    def evaluate_memory(self, user_id: str, *, now: datetime | None = None) -> MemoryReview:
        """ARIA evaluates its own memory: forget what's done, keep what matters,
        graduate durable takeaways into long-term memory."""
        now = now or _utcnow()
        all_items = self.short_term_memories(user_id, now=now, include_expired=True)
        forgotten: list[str] = []
        graduated: list[str] = []
        kept: list[str] = []
        for item in all_items:
            if item.category == "trait":
                # A durable observation about the user — promote to long-term and
                # drop the transient copy. Checked before expiry so a trait is
                # never lost to TTL before it graduates.
                self.record_life_fact(user_id, item.text)
                self.forget_short_term(user_id, item.id)
                graduated.append(item.text)
            elif not item.is_active(now):
                self.forget_short_term(user_id, item.id)
                forgotten.append(item.text)
            else:
                kept.append(item.text)
        context = self.get_or_create_context(user_id)
        context.last_evaluated_at = now
        self._save(user_id, context)
        return MemoryReview(evaluated_at=now, forgotten=forgotten, graduated=graduated, kept=kept)

    def daily_checkin(
        self,
        user_id: str,
        *,
        now: datetime | None = None,
        mark: bool = True,
    ) -> CheckinPrompt | None:
        """Offer a once-a-day "anything new?" check-in. Returns None if ARIA has
        already checked in today."""
        now = now or _utcnow()
        context = self.get_or_create_context(user_id)
        if context.last_checkin_at is not None and context.last_checkin_at.date() == now.date():
            return None

        upcoming = [
            m for m in self.short_term_memories(user_id, now=now)
            if m.category == "event" and m.event_at is not None
        ]
        if upcoming:
            nxt = upcoming[0]
            when = _humanize_when(nxt.event_at, now)
            lead = f"You've got {nxt.text} — {when}. "
        else:
            lead = ""
        text = (
            f"{lead}Anything new I should know about today — plans, how you're "
            f"feeling, anything on your mind?"
        )
        if mark:
            context.last_checkin_at = now
            self._save(user_id, context)
        return CheckinPrompt(
            text=text,
            date=now.date().isoformat(),
            upcoming=[m.to_dict() for m in upcoming[:5]],
        )

    def memory_prompt_block(self, user_id: str, *, now: datetime | None = None) -> str:
        """Render long-term + active short-term memory as a prompt-injectable block.

        Empty string when there's nothing to say, so callers can gate on it.
        """
        now = now or _utcnow()
        context = self.get_or_create_context(user_id)
        lines: list[str] = []

        long_term: list[str] = []
        if context.life_facts:
            long_term.append("knows: " + "; ".join(context.life_facts[:8]))
        if context.current_goals:
            long_term.append("goals: " + "; ".join(context.current_goals[:5]))
        if context.constraints:
            long_term.append("constraints: " + "; ".join(context.constraints[:5]))
        if context.recent_patterns:
            long_term.append("patterns: " + "; ".join(context.recent_patterns[:5]))
        if context.last_insights:
            long_term.append("recently told them: " + "; ".join(context.last_insights[:3]))

        short_term = self.short_term_memories(user_id, now=now)
        upcoming = [
            f"{m.text} ({_humanize_when(m.event_at, now)})" if m.event_at else m.text
            for m in short_term[:6]
        ]

        if long_term:
            lines.append("[MEMORY — long term]")
            lines.extend(f"- {entry}" for entry in long_term)
        if upcoming:
            lines.append("[MEMORY — short term / coming up]")
            lines.extend(f"- {entry}" for entry in upcoming)
        return "\n".join(lines)

    def _save(self, user_id: str, context: UserContext) -> None:
        key = keys.aria_context_key(user_id)
        dynamodb.put_item(
            {
                "pk": key["pk"],
                "sk": key["sk"],
                "payload": context.to_dict(),
            }
        )