"""ARIA's long-term learning engine — dummy is a test consumer, not the owner.

This module is how ARIA learns and teaches, on the live backend and in tests.
It lives under ``backend/infra/lambda/services`` because that is the
production hot path. The SimRunner dummy orchestrator may *call* it so a
laptop test can exercise the same policy; it must never *own* it. Deleting
the dummy orchestra must leave this file, ``adapt()``, ``apply_chat_turn()``,
and Dynamo ``ARIA#PERSONA`` in place.

It coaches two ways from the same policy:

  * **contextual** — calendar busy windows and classified kinds (never titles,
    places, attendees), recovery, sleep, workouts.
  * **generalized** — conversation + Dirichlet priors + the Q-table, when
    no life/body context was sent. Same API either way, like a real model
    that still answers with an empty context window.

The online model:

  * Dirichlet–multinomial posteriors over *how you train* (slot, follow-
    through, what you talk about). Cold start uses sports-science priors so
    turn one is already adapted; every observation updates immediately.
  * TD(0) Q-table over (life-bucket × stance). Completes, skips, and
    reactions are rewards. Softmax of feature logits plus Q; temperature
    cools with n. No randomness — deterministic.
  * A **priority ranker** over domains: events (wedding/game/travel, busy
    windows), what ARIA has already ingested (insights, patterns, goals,
    constraints), conversation, and relationship depth. Rank-sensitive
    TD updates teach *what to lead with*, not only which stance to take.
  * A **self-training critic** (``self_trainer.py``): ARIA predicts at
    commit, self-labels conversation, judges right/wrong, and tunes her
    own step size. Dummy never owns this.
  * Hedge over specialists present when the outcome landed.
  * Teach both directions: the brief tells ARIA how to coach, and one
    learned sentence ARIA can tell the person.

Stdlib only. ``adapt()`` is pure. Persistence (load/save) is the live
route's job, not the dummy's.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any, Iterable

# --- Vocabulary ---------------------------------------------------------------

SLOTS = ("morning", "midday", "evening")
STANCES = ("protect", "proceed", "fuel", "clarify")
DOMAINS = (
    "sleep",
    "readiness",
    "training",
    "nutrition",
    "lifestyle",
    "progress",
    "body",
    "cycle",
)
FOLLOW = ("complete", "skip")

# Classified calendar kinds ARIA may learn. Titles never match this set.
CALENDAR_KINDS = frozenset(
    {"wedding", "game", "flight", "travel", "work", "dinner", "family", "appointment", "social"}
)
HEADLINE_KINDS = frozenset({"wedding", "game", "flight", "travel"})

_DOMAIN_CUES: dict[str, tuple[str, ...]] = {
    "sleep": ("sleep", "slept", "insomnia", "bedtime", "last night", "nap"),
    "readiness": ("readiness", "recover", "hrv", "tired", "exhausted", "drained", "sore"),
    "training": ("train", "workout", "session", "lift", "gym", "squat", "run today"),
    "nutrition": ("eat", "food", "protein", "meal", "calorie", "hydrat", "water"),
    "lifestyle": ("work", "travel", "busy", "schedule", "calendar", "tonight"),
    "progress": ("progress", "gains", "stronger", "streak", "plateau"),
    "body": ("pain", "hurt", "knee", "shoulder", "injury", "ache"),
    "cycle": ("period", "cycle", "luteal", "follicular", "pms", "cramp"),
}
_ADVICE_CUES = ("should i", "what should", "recommend", "train today", "what's the move")

# Half-life of the prior: eight real observations and learned mass equals prior.
PRIOR_STRENGTH = 8.0

# Small RL: TD(0) on a 9×4 Q-table (calendar bucket × body bucket × stance).
# Short horizon — one coaching turn, not a 10k-step MDP.
TD_ALPHA = 0.28
TD_GAMMA = 0.55
Q_BLEND = 0.85          # how hard Q pulls the softmax vs the feature prior
HEDGE_ETA = 0.18        # multiplicative-weights step on specialists
TEMP_FLOOR = 0.35       # softmax temperature never goes colder than this
SOURCE_KEYS = ("event", "ingest", "conversation", "body")
ALPHA_MIN = 0.08
ALPHA_MAX = 0.55


def _default_source_w() -> dict[str, float]:
    return {key: 1.0 for key in SOURCE_KEYS}

# Priors: not uniform. Slight evening-training bias (most desk lives), complete
# more often than skip, protect slightly on the table because Forge is recovery-
# aware. These are the "even at the beginning" recommendations.
_SLOT_PRIOR = {"morning": 1.0, "midday": 1.0, "evening": 1.4}
_FOLLOW_PRIOR = {"complete": 2.0, "skip": 1.0}
_DOMAIN_PRIOR = {d: 1.0 for d in DOMAINS}


# --- Calendar ingest (kinds + busy windows only) ---------------------------


@dataclass(frozen=True)
class CalendarRead:
    busy_today: int = 0
    morning_busy: bool = False
    evening_busy: bool = False
    all_day_busy: bool = False
    kinds: tuple[str, ...] = ()

    @property
    def headlines(self) -> tuple[str, ...]:
        return tuple(k for k in self.kinds if k in HEADLINE_KINDS)

    def as_dict(self) -> dict[str, Any]:
        return {
            "busy_today": self.busy_today,
            "morning_busy": self.morning_busy,
            "evening_busy": self.evening_busy,
            "all_day_busy": self.all_day_busy,
            "kinds": list(self.kinds),
            "headlines": list(self.headlines),
        }


def is_allowed_calendar_tag(tag: str) -> bool:
    """Same contract as iOS ``FakeCalendarPack.isAllowedIngestTag``."""
    text = (tag or "").strip()
    if text.startswith("calendar:busy:"):
        tail = text[len("calendar:busy:") :]
        return tail.isdigit()
    if text in ("calendar:morning:busy", "calendar:evening:busy", "calendar:allday:busy"):
        return True
    if text.startswith("calendar:kind:"):
        return text[len("calendar:kind:") :] in CALENDAR_KINDS
    return False


def parse_calendar(tags: Iterable[str] | None) -> CalendarRead:
    """Drop anything that looks like a title, place, or attendee."""
    busy = 0
    morning = evening = all_day = False
    kinds: list[str] = []
    for raw in tags or ():
        tag = str(raw)
        if not is_allowed_calendar_tag(tag):
            continue
        if tag.startswith("calendar:busy:"):
            busy = int(tag[len("calendar:busy:") :])
        elif tag == "calendar:morning:busy":
            morning = True
        elif tag == "calendar:evening:busy":
            evening = True
        elif tag == "calendar:allday:busy":
            all_day = True
        elif tag.startswith("calendar:kind:"):
            kind = tag[len("calendar:kind:") :]
            if kind not in kinds:
                kinds.append(kind)
    kinds.sort()
    return CalendarRead(busy, morning, evening, all_day, tuple(kinds))


# --- Persona (the thing that learns) ----------------------------------------


def _copy_priors(src: dict[str, float]) -> dict[str, float]:
    return {k: float(v) for k, v in src.items()}


@dataclass
class PersonaState:
    """Learned how-you-work. Counts include the prior (Dirichlet α)."""

    slot: dict[str, float] = field(default_factory=lambda: _copy_priors(_SLOT_PRIOR))
    domain: dict[str, float] = field(default_factory=lambda: _copy_priors(_DOMAIN_PRIOR))
    follow: dict[str, float] = field(default_factory=lambda: _copy_priors(_FOLLOW_PRIOR))
    skip_when_evening_busy: float = 0.4
    complete_when_evening_busy: float = 0.6
    reactions_up: float = 1.0
    reactions_down: float = 0.4
    n_calendar: int = 0
    n_chat: int = 0
    n_workout: int = 0
    relationship_level: int = 1
    # RL: Q[bucket][stance], last action for TD credit, Hedge weights.
    q: dict[str, dict[str, float]] = field(default_factory=dict)
    specialist_w: dict[str, float] = field(default_factory=dict)
    last_bucket: str | None = None
    last_stance: str | None = None
    last_specialists: tuple[str, ...] = ()
    n_updates: int = 0
    ingest: dict[str, float] = field(default_factory=lambda: _copy_priors(_DOMAIN_PRIOR))
    n_ingest: int = 0
    priority_q: dict[str, dict[str, float]] = field(default_factory=dict)
    last_event_bucket: str | None = None
    last_priority: tuple[str, ...] = ()
    # Self-training critic: ARIA judges her last call and tunes alpha.
    td_alpha: float = TD_ALPHA
    last_td_sign: int = 0
    last_predicted_reward: float = 0.0
    last_stance_p: float = 0.0
    last_sources: tuple[str, ...] = ()
    n_right: int = 0
    n_wrong: int = 0
    n_self_train: int = 0
    calibration: float = 0.5
    source_w: dict[str, float] = field(default_factory=_default_source_w)
    last_verdict: str | None = None

    @property
    def n(self) -> int:
        return int(self.n_calendar + self.n_chat + self.n_workout)

    def confidence(self) -> float:
        """0 at cold start, ~0.5 after eight observations, approaching 1."""
        return round(self.n / (self.n + PRIOR_STRENGTH), 4)

    def posterior(self, axis: str) -> dict[str, float]:
        table = {"slot": self.slot, "domain": self.domain, "follow": self.follow}[axis]
        total = sum(table.values()) or 1.0
        return {k: round(v / total, 4) for k, v in table.items()}

    def preferred_slot(self) -> str:
        post = self.posterior("slot")
        return max(post, key=post.get)

    def p_skip_evening(self) -> float:
        total = self.skip_when_evening_busy + self.complete_when_evening_busy
        return self.skip_when_evening_busy / total if total else 0.4

    def as_dict(self) -> dict[str, Any]:
        return {
            "slot": dict(self.slot),
            "domain": dict(self.domain),
            "follow": dict(self.follow),
            "skip_when_evening_busy": self.skip_when_evening_busy,
            "complete_when_evening_busy": self.complete_when_evening_busy,
            "reactions_up": self.reactions_up,
            "reactions_down": self.reactions_down,
            "n_calendar": self.n_calendar,
            "n_chat": self.n_chat,
            "n_workout": self.n_workout,
            "relationship_level": self.relationship_level,
            "q": {k: dict(v) for k, v in self.q.items()},
            "specialist_w": dict(self.specialist_w),
            "last_bucket": self.last_bucket,
            "last_stance": self.last_stance,
            "last_specialists": list(self.last_specialists),
            "n_updates": self.n_updates,
            "ingest": dict(self.ingest),
            "n_ingest": self.n_ingest,
            "priority_q": {k: dict(v) for k, v in self.priority_q.items()},
            "last_event_bucket": self.last_event_bucket,
            "last_priority": list(self.last_priority),
            "td_alpha": self.td_alpha,
            "last_td_sign": self.last_td_sign,
            "last_predicted_reward": self.last_predicted_reward,
            "last_stance_p": self.last_stance_p,
            "last_sources": list(self.last_sources),
            "n_right": self.n_right,
            "n_wrong": self.n_wrong,
            "n_self_train": self.n_self_train,
            "calibration": self.calibration,
            "source_w": dict(self.source_w),
            "last_verdict": self.last_verdict,
            "n": self.n,
            "confidence": self.confidence(),
            "preferred_slot": self.preferred_slot(),
        }

    def ingest_posterior(self) -> dict[str, float]:
        total = sum(self.ingest.values()) or 1.0
        return {k: round(v / total, 4) for k, v in self.ingest.items()}

    @classmethod
    def from_dict(cls, raw: dict[str, Any] | None) -> "PersonaState":
        data = raw or {}
        state = cls()
        for axis, prior in (("slot", _SLOT_PRIOR), ("domain", _DOMAIN_PRIOR), ("follow", _FOLLOW_PRIOR)):
            incoming = data.get(axis)
            if isinstance(incoming, dict):
                merged = _copy_priors(prior)
                for key, value in incoming.items():
                    if key in merged:
                        try:
                            merged[key] = float(value)
                        except (TypeError, ValueError):
                            continue
                setattr(state, axis, merged)
        for name in (
            "skip_when_evening_busy",
            "complete_when_evening_busy",
            "reactions_up",
            "reactions_down",
        ):
            try:
                setattr(state, name, float(data.get(name, getattr(state, name))))
            except (TypeError, ValueError):
                pass
        for name in ("n_calendar", "n_chat", "n_workout", "relationship_level", "n_ingest"):
            try:
                setattr(state, name, int(data.get(name, getattr(state, name))))
            except (TypeError, ValueError):
                pass
        state.relationship_level = max(1, min(10, state.relationship_level))
        raw_q = data.get("q")
        if isinstance(raw_q, dict):
            cleaned: dict[str, dict[str, float]] = {}
            for bucket, row in raw_q.items():
                if not isinstance(row, dict):
                    continue
                cleaned[str(bucket)] = {
                    s: float(row[s]) for s in STANCES if s in row
                }
            state.q = cleaned
        raw_w = data.get("specialist_w")
        if isinstance(raw_w, dict):
            state.specialist_w = {
                str(k): float(v) for k, v in raw_w.items()
                if isinstance(v, (int, float))
            }
        last_b = data.get("last_bucket")
        state.last_bucket = str(last_b) if last_b else None
        last_s = data.get("last_stance")
        state.last_stance = str(last_s) if last_s in STANCES else None
        specs = data.get("last_specialists")
        if isinstance(specs, list):
            state.last_specialists = tuple(str(s) for s in specs if s)
        try:
            state.n_updates = int(data.get("n_updates") or 0)
        except (TypeError, ValueError):
            state.n_updates = 0
        incoming_ingest = data.get("ingest")
        if isinstance(incoming_ingest, dict):
            merged_ingest = _copy_priors(_DOMAIN_PRIOR)
            for key, value in incoming_ingest.items():
                if key in merged_ingest:
                    try:
                        merged_ingest[key] = float(value)
                    except (TypeError, ValueError):
                        continue
            state.ingest = merged_ingest
        raw_pq = data.get("priority_q")
        if isinstance(raw_pq, dict):
            cleaned_p: dict[str, dict[str, float]] = {}
            for event_key, row in raw_pq.items():
                if not isinstance(row, dict):
                    continue
                cleaned_p[str(event_key)] = {
                    d: float(row[d]) for d in DOMAINS if d in row
                }
            state.priority_q = cleaned_p
        last_eb = data.get("last_event_bucket")
        state.last_event_bucket = str(last_eb) if last_eb else None
        last_p = data.get("last_priority")
        if isinstance(last_p, list):
            state.last_priority = tuple(str(d) for d in last_p if d in DOMAINS)
        try:
            state.td_alpha = _clip(float(data.get("td_alpha", TD_ALPHA)), ALPHA_MIN, ALPHA_MAX)
        except (TypeError, ValueError):
            state.td_alpha = TD_ALPHA
        try:
            sign = int(data.get("last_td_sign", 0) or 0)
        except (TypeError, ValueError):
            sign = 0
        state.last_td_sign = sign if sign in (-1, 0, 1) else 0
        for name in ("last_predicted_reward", "last_stance_p", "calibration"):
            try:
                setattr(state, name, float(data.get(name, getattr(state, name))))
            except (TypeError, ValueError):
                pass
        state.calibration = _clip(state.calibration, 0.0, 1.0)
        for name in ("n_right", "n_wrong", "n_self_train"):
            try:
                setattr(state, name, max(0, int(data.get(name, getattr(state, name)))))
            except (TypeError, ValueError):
                pass
        raw_sw = data.get("source_w")
        merged_w = _default_source_w()
        if isinstance(raw_sw, dict):
            for key in SOURCE_KEYS:
                if key not in raw_sw:
                    continue
                try:
                    merged_w[key] = _clip(float(raw_sw[key]), 0.4, 2.0)
                except (TypeError, ValueError):
                    continue
        state.source_w = merged_w
        srcs = data.get("last_sources")
        if isinstance(srcs, list):
            state.last_sources = tuple(str(s) for s in srcs if s in SOURCE_KEYS)
        verdict = data.get("last_verdict")
        state.last_verdict = (
            str(verdict) if verdict in ("right", "wrong", "mixed") else None
        )
        return state


# --- Online updates ----------------------------------------------------------


def _bump(table: dict[str, float], key: str, amount: float = 1.0) -> None:
    if key in table:
        table[key] = table[key] + amount


def observe_calendar(state: PersonaState, tags: Iterable[str] | None) -> PersonaState:
    cal = parse_calendar(tags)
    state.n_calendar += 1
    # Headlines are rare and high-signal: bump lifestyle so ARIA brings it.
    if cal.headlines:
        _bump(state.domain, "lifestyle", 1.2)
        _bump(state.ingest, "lifestyle", 1.0)
    if cal.evening_busy:
        _bump(state.domain, "lifestyle", 0.4)
        _bump(state.ingest, "lifestyle", 0.3)
    return state


def observe_conversation(state: PersonaState, message: str) -> PersonaState:
    text = (message or "").lower()
    state.n_chat += 1
    hit = False
    for domain, cues in _DOMAIN_CUES.items():
        if any(c in text for c in cues):
            _bump(state.domain, domain, 1.0)
            hit = True
    if not hit:
        _bump(state.domain, "lifestyle", 0.3)
    return state


_PATTERN_TO_DOMAIN: tuple[tuple[str, str], ...] = (
    ("low_readiness", "readiness"),
    ("strong_sleep", "sleep"),
    ("sleep", "sleep"),
    ("recover", "readiness"),
    ("training", "training"),
    ("workout", "training"),
    ("calendar", "lifestyle"),
    ("busy", "lifestyle"),
    ("protein", "nutrition"),
    ("knee", "body"),
    ("shoulder", "body"),
    ("cycle", "cycle"),
)


def _ingest_texts(source: Any) -> list[str]:
    """What ARIA already holds: insights, patterns, goals, constraints — never titles."""
    if source is None:
        return []
    texts: list[str] = []
    if isinstance(source, dict):
        blobs = (
            source.get("insights"),
            source.get("last_insights"),
            source.get("patterns"),
            source.get("recent_patterns"),
            source.get("goals"),
            source.get("constraints"),
        )
        for blob in blobs:
            if isinstance(blob, list):
                texts.extend(str(item) for item in blob if item)
            elif blob:
                texts.append(str(blob))
        return texts
    lifestyle = getattr(source, "lifestyle", None)
    for blob in (
        getattr(source, "last_insights", None),
        getattr(source, "recent_patterns", None),
        getattr(source, "constraints", None),
        getattr(lifestyle, "recent_patterns", None) if lifestyle is not None else None,
        getattr(lifestyle, "goals", None) if lifestyle is not None else None,
        getattr(source, "current_goals", None),
    ):
        if isinstance(blob, list):
            texts.extend(str(item) for item in blob if item)
    return texts


def observe_ingest(state: PersonaState, source: Any) -> PersonaState:
    """Fold already-ingested ARIA context into the priority Dirichlet.

    Relationship does not gate *whether* we ingest — we always learn — but
    ranking later uses bond depth to decide how hard memory pulls the order.
    """
    texts = _ingest_texts(source)
    if not texts:
        return state
    state.n_ingest += 1
    for raw in texts:
        text = raw.lower()
        hit = False
        for needle, domain in _PATTERN_TO_DOMAIN:
            if needle in text:
                _bump(state.ingest, domain, 0.8)
                hit = True
        for domain, cues in _DOMAIN_CUES.items():
            if any(c in text for c in cues):
                _bump(state.ingest, domain, 0.5)
                hit = True
        if not hit:
            _bump(state.ingest, "lifestyle", 0.2)
    return state


def observe_workout(
    state: PersonaState,
    *,
    completed: bool,
    hour: int | None = None,
    evening_busy: bool = False,
    intensity: str | None = None,
) -> PersonaState:
    del intensity  # reserved: intensity-given-readiness head
    state.n_workout += 1
    _bump(state.follow, "complete" if completed else "skip", 1.0)
    if hour is not None:
        if hour < 12:
            slot = "morning"
        elif hour < 17:
            slot = "midday"
        else:
            slot = "evening"
        if completed:
            _bump(state.slot, slot, 1.0)
    if evening_busy:
        if completed:
            state.complete_when_evening_busy += 1.0
        else:
            state.skip_when_evening_busy += 1.0
    return state


def observe_sleep_nudge(state: PersonaState, *, followed: bool) -> PersonaState:
    """A wind-down / bedtime nudge landed or didn't — same follow axis as workouts."""
    _bump(state.follow, "complete" if followed else "skip", 0.6)
    _bump(state.ingest, "sleep", 0.8)
    _bump(state.domain, "sleep", 0.4)
    state.n_ingest += 1
    return state


def observe_reaction(state: PersonaState, reaction: str) -> PersonaState:
    token = (reaction or "").strip().lower()
    if token in ("🔥", "💪", "thumbs_up", "love", "up", "like"):
        state.reactions_up += 1.0
    elif token in ("thumbs_down", "down", "dislike", "skip"):
        state.reactions_down += 1.0
    return state


def observe_relationship(state: PersonaState, level: int) -> PersonaState:
    try:
        state.relationship_level = max(1, min(10, int(level)))
    except (TypeError, ValueError):
        pass
    return state


# --- Reinforcement: TD(0) + Hedge -------------------------------------------

_BODY_BUCKETS = ("depleted", "mixed", "recovered")
_CAL_BUCKETS = ("clear", "evening_busy", "headline")


def event_bucket(cal: CalendarRead) -> str:
    """Priority is event-conditioned: a wedding is not a packed Tuesday."""
    if cal.headlines:
        return cal.headlines[0]
    if cal.evening_busy:
        return "evening_busy"
    if cal.morning_busy:
        return "morning_busy"
    return "clear"


def _pq(state: PersonaState, event_key: str, domain: str) -> float:
    row = state.priority_q.get(event_key) or {}
    return float(row.get(domain, 0.0))


def _set_pq(state: PersonaState, event_key: str, domain: str, value: float) -> None:
    row = state.priority_q.setdefault(event_key, {})
    row[domain] = round(value, 6)


def bucket(feat: dict[str, float]) -> str:
    """Nine discrete states the Q-table can actually fill."""
    if feat.get("headline", 0) >= 0.5:
        cal = "headline"
    elif feat.get("evening_busy", 0) >= 0.5:
        cal = "evening_busy"
    else:
        cal = "clear"
    if feat.get("low_recovery", 0) >= 0.5 or feat.get("short_sleep", 0) >= 0.5:
        body = "depleted"
    elif feat.get("high_recovery", 0) >= 0.5:
        body = "recovered"
    else:
        body = "mixed"
    return f"{cal}|{body}"


def _q(state: PersonaState, key: str, stance: str) -> float:
    row = state.q.get(key) or {}
    return float(row.get(stance, 0.0))


def _set_q(state: PersonaState, key: str, stance: str, value: float) -> None:
    row = state.q.setdefault(key, {})
    row[stance] = round(value, 6)


def reward_for_workout(
    *,
    completed: bool,
    evening_busy: bool = False,
    headline: bool = False,
    last_stance: str | None = None,
) -> float:
    """Shaped reward: did the last coaching action fit what they actually did?"""
    stance = last_stance or ""
    if stance == "protect":
        if evening_busy or headline:
            return 0.85 if not completed else 0.15  # protecting a packed day is the win
        return -0.25 if completed else 0.35
    if stance == "proceed":
        if completed:
            return 1.0 if not evening_busy else 0.35
        return -0.85 if evening_busy else -0.45
    if stance == "fuel":
        return 0.35 if completed else -0.15
    if stance == "clarify":
        return 0.05
    return 0.4 if completed else -0.3


def reward_for_sleep_nudge(
    *,
    followed: bool,
    last_stance: str | None = None,
) -> float:
    """Did the last coaching action fit whether they actually protected the night?"""
    stance = last_stance or ""
    if stance == "protect":
        return 0.9 if followed else -0.2
    if stance == "proceed":
        return 0.2 if followed else -0.45
    if stance == "fuel":
        return 0.3 if followed else -0.1
    if stance == "clarify":
        return 0.05
    return 0.45 if followed else -0.25


def reward_for_reaction(reaction: str) -> float:
    token = (reaction or "").strip().lower()
    if token in ("🔥", "💪", "thumbs_up", "love", "up", "like"):
        return 0.7
    if token in ("thumbs_down", "down", "dislike", "skip"):
        return -0.7
    return 0.0


def reinforce(
    state: PersonaState,
    reward: float,
    next_bucket: str | None = None,
) -> float:
    """TD(0) on the last (bucket, stance). Hedge-update specialists that were in the room.

    Returns the TD error so tests can see the table actually moved.
    """
    if not state.last_bucket or not state.last_stance:
        return 0.0
    q_sa = _q(state, state.last_bucket, state.last_stance)
    boot = 0.0
    if next_bucket:
        boot = max(_q(state, next_bucket, a) for a in STANCES)
    delta = float(reward) + TD_GAMMA * boot - q_sa
    alpha = _clip(float(state.td_alpha or TD_ALPHA), ALPHA_MIN, ALPHA_MAX)
    _set_q(state, state.last_bucket, state.last_stance, q_sa + alpha * delta)
    state.n_updates += 1
    # Hedge: specialists present on a good outcome grow; present on a miss shrink.
    scale = math.exp(HEDGE_ETA * _clip(float(reward), -1.5, 1.5))
    for spec in state.last_specialists:
        current = state.specialist_w.get(spec, 1.0)
        state.specialist_w[spec] = round(_clip(current * scale, 0.25, 4.0), 4)
    # Rank-sensitive TD: the domain we led with takes the outcome hardest.
    if state.last_event_bucket and state.last_priority:
        credits = (1.0, 0.55, 0.3)
        boot_p = 0.0
        nxt_event = next_bucket.split("|", 1)[0] if next_bucket else None
        if nxt_event:
            boot_p = max(_pq(state, nxt_event, d) for d in DOMAINS)
        for index, domain in enumerate(state.last_priority[:3]):
            credit = credits[index] if index < len(credits) else 0.2
            q_pd = _pq(state, state.last_event_bucket, domain)
            p_delta = float(reward) * credit + TD_GAMMA * boot_p * credit - q_pd
            _set_pq(
                state,
                state.last_event_bucket,
                domain,
                q_pd + alpha * p_delta,
            )
    try:
        from . import self_trainer

        self_trainer.apply_judgment(state, float(reward), delta, TD_ALPHA)
    except Exception:
        pass
    return round(delta, 6)


def commit_action(
    state: PersonaState,
    bucket_key: str,
    stance: str,
    specialists: Iterable[str],
    event_bucket_key: str | None = None,
    priority: Iterable[str] | None = None,
    stance_p: float | None = None,
    sources: Iterable[str] | None = None,
) -> None:
    """Remember what ARIA just did so the next outcome can credit it."""
    state.last_bucket = bucket_key
    state.last_stance = stance if stance in STANCES else None
    state.last_specialists = tuple(str(s) for s in specialists if s)
    if event_bucket_key:
        state.last_event_bucket = str(event_bucket_key)
    if priority is not None:
        state.last_priority = tuple(str(d) for d in priority if d in DOMAINS)
    predicted = 0.0
    if state.last_bucket and state.last_stance:
        predicted = _q(state, state.last_bucket, state.last_stance)
    try:
        from . import self_trainer

        self_trainer.record_prediction(
            state,
            predicted,
            float(stance_p or 0.0),
            sources,
        )
    except Exception:
        state.last_predicted_reward = predicted
        try:
            state.last_stance_p = float(stance_p or 0.0)
        except (TypeError, ValueError):
            state.last_stance_p = 0.0
        if sources is not None:
            state.last_sources = tuple(
                str(s) for s in sources if s in SOURCE_KEYS
            )


def pretrain_from_history(
    state: PersonaState,
    days: Iterable[Any],
) -> PersonaState:
    """Replay a workout history through the RL loop so SimRunner starts learned.

    Each day: pick a stance from the current policy, then reward it from
    whether they actually trained and how recovered they were. Constant
    learn-and-teach even before the live turn.
    """
    for day in days or ():
        logged = bool(getattr(day, "workout_logged", False))
        readiness = getattr(day, "readiness_score", None)
        rec = float(readiness) / 100.0 if isinstance(readiness, (int, float)) else None
        feat = {
            "evening_busy": 0.0,
            "headline": 0.0,
            "low_recovery": 1.0 if rec is not None and rec < 0.50 else 0.0,
            "high_recovery": 1.0 if rec is not None and rec >= 0.75 else 0.0,
            "short_sleep": 0.0,
            "missing": 0.05,
            "lang_train": 1.0,
            "lang_sleep": 0.0,
            "lang_food": 0.0,
            "lang_advice": 1.0,
            "p_evening": state.posterior("slot").get("evening", 0.4),
            "p_skip": state.posterior("follow").get("skip", 0.3),
            "p_skip_evening": state.p_skip_evening(),
            "p_sleep_talk": state.posterior("domain").get("sleep", 0.12),
            "relationship": 0.2,
            "learned": state.confidence(),
            "busy_load": 0.0,
            "morning_busy": 0.0,
        }
        nxt = bucket(feat)
        if state.last_stance:
            r = reward_for_workout(
                completed=logged,
                evening_busy=False,
                last_stance=state.last_stance,
            )
            reinforce(state, r, next_bucket=nxt)
        observe_workout(state, completed=logged, hour=18 if logged else None)
        stance, _ = _pick_stance(feat, state)
        commit_action(state, nxt, stance, ("workout", "recovery"))
    return state


# --- Features + softmax policy ----------------------------------------------


def _clip(value: float, lo: float, hi: float) -> float:
    return lo if value < lo else hi if value > hi else value


def _softmax(logits: list[float]) -> list[float]:
    peak = max(logits)
    exps = [math.exp(x - peak) for x in logits]
    total = sum(exps) or 1.0
    return [e / total for e in exps]


def _sleep_hours(ctx: Any) -> float | None:
    minutes = getattr(getattr(ctx, "sleep", None), "duration_minutes", None)
    if isinstance(minutes, (int, float)):
        return float(minutes) / 60.0
    today = getattr(ctx, "today", None)
    hours = getattr(today, "total_sleep_hours", None) if today is not None else None
    return float(hours) if isinstance(hours, (int, float)) else None


def _recovery(ctx: Any) -> float | None:
    score = getattr(getattr(ctx, "readiness", None), "recovery_score", None)
    if isinstance(score, (int, float)):
        return float(score) / 100.0
    today = getattr(ctx, "today", None)
    raw = getattr(today, "readiness_score", None) if today is not None else None
    return float(raw) / 100.0 if isinstance(raw, (int, float)) else None


def _lifestyle_tags(ctx: Any) -> list[str]:
    lifestyle = getattr(ctx, "lifestyle", None)
    tags = getattr(lifestyle, "tags", None) if lifestyle is not None else None
    if isinstance(tags, list):
        return [str(t) for t in tags]
    extra = getattr(ctx, "lifestyle_tags", None)
    if isinstance(extra, list):
        return [str(t) for t in extra]
    return []


def _missing_ratio(ctx: Any) -> float:
    fields = getattr(ctx, "missing_fields", None)
    if isinstance(fields, list) and fields:
        return _clip(len(fields) / 24.0, 0.0, 1.0)
    has_sleep = getattr(ctx, "has_sleep", None)
    if has_sleep is False:
        return 0.7
    return 0.15 if _sleep_hours(ctx) is None else 0.05


def features(message: str, ctx: Any, persona: PersonaState) -> dict[str, float]:
    cal = parse_calendar(_lifestyle_tags(ctx))
    sleep_h = _sleep_hours(ctx)
    recovery = _recovery(ctx)
    text = (message or "").lower()
    lang_train = 1.0 if any(c in text for c in _DOMAIN_CUES["training"]) else 0.0
    lang_sleep = 1.0 if any(c in text for c in _DOMAIN_CUES["sleep"]) else 0.0
    lang_food = 1.0 if any(c in text for c in _DOMAIN_CUES["nutrition"]) else 0.0
    lang_advice = 1.0 if any(c in text for c in _ADVICE_CUES) else 0.0
    return {
        "evening_busy": 1.0 if cal.evening_busy else 0.0,
        "morning_busy": 1.0 if cal.morning_busy else 0.0,
        "headline": 1.0 if cal.headlines else 0.0,
        "busy_load": _clip(cal.busy_today / 6.0, 0.0, 1.5),
        "low_recovery": 1.0 if recovery is not None and recovery < 0.50 else 0.0,
        "high_recovery": 1.0 if recovery is not None and recovery >= 0.75 else 0.0,
        "short_sleep": 1.0 if sleep_h is not None and sleep_h < 6.5 else 0.0,
        "missing": _missing_ratio(ctx),
        "lang_train": lang_train,
        "lang_sleep": lang_sleep,
        "lang_food": lang_food,
        "lang_advice": lang_advice,
        "p_evening": persona.posterior("slot").get("evening", 0.4),
        "p_skip": persona.posterior("follow").get("skip", 0.3),
        "p_skip_evening": persona.p_skip_evening(),
        "p_sleep_talk": persona.posterior("domain").get("sleep", 0.12),
        "relationship": _clip((persona.relationship_level - 1) / 9.0, 0.0, 1.0),
        "learned": persona.confidence(),
    }


# Softmax policy weights: stance × feature. Hand-fit to sports-science priors,
# then the learned columns (p_skip_evening, p_skip, learned) let the person
# move the policy the way a watch history moves a homepage.
_STANCE_WEIGHTS: dict[str, dict[str, float]] = {
    "protect": {
        "evening_busy": 1.6,
        "headline": 1.8,
        "busy_load": 0.8,
        "low_recovery": 1.7,
        "short_sleep": 1.4,
        "p_skip_evening": 1.5,
        "p_skip": 0.6,
        "p_sleep_talk": 0.5,
        "relationship": -0.15,
        "bias": 0.2,
    },
    "proceed": {
        "high_recovery": 1.5,
        "lang_train": 1.4,
        "lang_advice": 0.6,
        "p_evening": 0.3,
        "relationship": 0.2,
        "bias": 0.5,
        "evening_busy": -1.1,
        "headline": -1.2,
        "low_recovery": -1.3,
        "short_sleep": -0.9,
        "p_skip_evening": -1.0,
    },
    "fuel": {
        "lang_food": 1.8,
        "lang_train": 0.4,
        "bias": 0.15,
    },
    "clarify": {
        "missing": 2.2,
        "bias": 0.1,
        "lang_advice": -0.4,
        "relationship": -0.7,
    },
}


def _source_w(state: PersonaState, key: str) -> float:
    try:
        return _clip(float(state.source_w.get(key, 1.0)), 0.4, 2.0)
    except (TypeError, ValueError):
        return 1.0


def _hot_sources(feat: dict[str, float]) -> tuple[str, ...]:
    found: list[str] = []
    if (
        feat.get("evening_busy", 0.0) >= 0.5
        or feat.get("headline", 0.0) >= 0.5
        or feat.get("morning_busy", 0.0) >= 0.5
    ):
        found.append("event")
    if (
        feat.get("low_recovery", 0.0) >= 0.5
        or feat.get("high_recovery", 0.0) >= 0.5
        or feat.get("short_sleep", 0.0) >= 0.5
    ):
        found.append("body")
        found.append("ingest")
    if (
        feat.get("lang_train", 0.0) >= 0.5
        or feat.get("lang_sleep", 0.0) >= 0.5
        or feat.get("lang_food", 0.0) >= 0.5
        or feat.get("lang_advice", 0.0) >= 0.5
    ):
        found.append("conversation")
    return tuple(found)


def _stance_logits(feat: dict[str, float], state: PersonaState | None = None) -> dict[str, float]:
    out: dict[str, float] = {}
    key = bucket(feat)
    n = state.n_updates if state is not None else 0
    blend = Q_BLEND * (n / (n + 4.0))  # Q is quiet until it has been taught
    temp = max(TEMP_FLOOR, 0.95 / (1.0 + n / 12.0))
    if state is not None and state.n_self_train > 0:
        try:
            from . import self_trainer

            temp *= self_trainer.heat_from_calibration(state.calibration)
        except Exception:
            pass
    for stance in STANCES:
        weights = _STANCE_WEIGHTS[stance]
        score = weights.get("bias", 0.0)
        for name, weight in weights.items():
            if name == "bias":
                continue
            score += weight * feat.get(name, 0.0)
        if state is not None:
            score += blend * _q(state, key, stance)
        out[stance] = score / temp
    return out


def _pick_stance(
    feat: dict[str, float],
    state: PersonaState | None = None,
) -> tuple[str, dict[str, float]]:
    logits = _stance_logits(feat, state)
    ordered = [logits[s] for s in STANCES]
    probs = _softmax(ordered)
    post = {s: round(p, 4) for s, p in zip(STANCES, probs)}
    lead = max(post, key=post.get)
    return lead, post


def rank_priorities(
    message: str,
    ctx: Any,
    persona: PersonaState,
    feat: dict[str, float],
    cal: CalendarRead,
) -> tuple[list[str], dict[str, float], str]:
    """Learn what to lead with given the event, ingest, conversation, and bond.

    Score for each domain is the sum of:
      conversation mass (what they talk about)
      ingest mass (insights, patterns, goals, constraints ARIA already holds),
        scaled by relationship (a new user is known, not familiar)
      event-conditioned Q (what paid off on nights like this)
      last-ranking stickiness (so the coach does not flip every turn)
      this-turn event / body / language biases
    """
    event_key = event_bucket(cal)
    rel = max(0.0, min(1.0, feat.get("relationship", 0.15)))
    conv_w = _source_w(persona, "conversation")
    ingest_w = _source_w(persona, "ingest")
    event_w = _source_w(persona, "event")
    body_w = _source_w(persona, "body")
    ingest_gain = (0.35 + 0.65 * rel) * ingest_w
    scores: dict[str, float] = {}
    for domain in DOMAINS:
        conversation = float(persona.domain.get(domain, 1.0)) * conv_w
        ingested = float(persona.ingest.get(domain, 1.0)) * ingest_gain
        event_q = 1.8 * event_w * _pq(persona, event_key, domain)
        stick = 0.55 if (persona.last_priority and persona.last_priority[0] == domain) else 0.0
        scores[domain] = conversation + ingested + event_q + stick

    # Current-turn ingest still counts even if Dirichlet has not been bumped yet.
    for raw in _ingest_texts(ctx):
        text = raw.lower()
        for needle, domain in _PATTERN_TO_DOMAIN:
            if needle in text:
                scores[domain] = scores.get(domain, 0.0) + 0.45 * ingest_gain
        for domain, cues in _DOMAIN_CUES.items():
            if any(c in text for c in cues):
                scores[domain] = scores.get(domain, 0.0) + 0.25 * ingest_gain

    text = (message or "").lower()
    for domain, cues in _DOMAIN_CUES.items():
        if any(c in text for c in cues):
            scores[domain] = scores.get(domain, 0.0) + 1.4 * conv_w

    # This-turn calendar is the day they have, not learned credit — keep it
    # unweighted so a wedding still leads "train today" at cold start.
    if feat.get("headline", 0.0) >= 0.5 or bool(cal.headlines):
        scores["lifestyle"] = scores.get("lifestyle", 0.0) + 2.6
        scores["training"] = scores.get("training", 0.0) - 0.9
    elif feat.get("evening_busy", 0.0) >= 0.5:
        scores["lifestyle"] = scores.get("lifestyle", 0.0) + 1.5
        scores["training"] = scores.get("training", 0.0) - 0.55
    if feat.get("morning_busy", 0.0) >= 0.5:
        scores["lifestyle"] = scores.get("lifestyle", 0.0) + 0.8
    if feat.get("short_sleep", 0.0) >= 0.5:
        scores["sleep"] = scores.get("sleep", 0.0) + 1.6 * body_w
        scores["training"] = scores.get("training", 0.0) - 0.5 * body_w
    if feat.get("low_recovery", 0.0) >= 0.5:
        scores["readiness"] = scores.get("readiness", 0.0) + 1.4 * body_w
        scores["training"] = scores.get("training", 0.0) - 0.7 * body_w

    ranking = sorted(DOMAINS, key=lambda d: (-scores.get(d, 0.0), d))
    if event_key in HEADLINE_KINDS:
        reason = (
            f"event={event_key} leads; conversation, ingest, and "
            f"relationship={rel:.2f} rank the rest"
        )
    elif event_key in ("evening_busy", "morning_busy"):
        reason = (
            f"busy window={event_key}; ingest and conversation "
            f"(bond={rel:.2f}) set order after lifestyle"
        )
    else:
        reason = (
            f"no headline event; conversation + ingest "
            f"(bond={rel:.2f}) plus learned event-Q"
        )
    return ranking, scores, reason


def _lead_domain(message: str, ctx: Any, persona: PersonaState, feat: dict[str, float]) -> str:
    cal = parse_calendar(_lifestyle_tags(ctx))
    ranking, _, _ = rank_priorities(message, ctx, persona, feat, cal)
    return ranking[0]


_DOMAIN_TO_SPECIALIST = {
    "sleep": "sleep",
    "readiness": "recovery",
    "training": "workout",
    "nutrition": "lifestyle",
    "lifestyle": "lifestyle",
    "progress": "progress",
    "body": "recovery",
    "cycle": "cycle",
}


_SPECIALIST_TO_DOMAIN = {
    "sleep": "sleep",
    "recovery": "readiness",
    "workout": "training",
    "lifestyle": "lifestyle",
    "progress": "progress",
    "cycle": "cycle",
}


def _specialists(
    lead: str,
    feat: dict[str, float],
    stance: str,
    state: PersonaState | None = None,
    ranking: list[str] | None = None,
) -> list[str]:
    roster: list[str] = []

    def add(name: str) -> None:
        spec = _DOMAIN_TO_SPECIALIST.get(name, name)
        if spec not in roster:
            roster.append(spec)

    add(lead)
    if feat["headline"] or feat["evening_busy"]:
        add("lifestyle")
    if stance == "protect":
        add("recovery")
        if feat["short_sleep"] or feat["p_sleep_talk"] > 0.2:
            add("sleep")
    if feat["lang_train"] or lead == "training":
        add("training")
    if feat["lang_food"]:
        add("nutrition")
    # Hedge: a specialist that has been paying off for this person joins,
    # then ranking decides order so events still lead.
    if state is not None and state.specialist_w:
        ranked = sorted(state.specialist_w.items(), key=lambda kv: kv[1], reverse=True)
        for spec, weight in ranked:
            if weight >= 1.25:
                add(spec)
            if len(roster) >= 3:
                break
    if ranking:
        rank_index = {domain: i for i, domain in enumerate(ranking)}
        hedge = (state.specialist_w if state is not None else {}) or {}

        def _spec_key(name: str) -> tuple[int, float, str]:
            domain = _SPECIALIST_TO_DOMAIN.get(name, lead)
            return (rank_index.get(domain, 99), -float(hedge.get(name, 1.0)), name)

        roster = sorted(roster, key=_spec_key)
    return roster[:3]


_SPEAK = {
    "protect": (
        "Lead with the life they actually have today. Fit training around busy "
        "windows and headlines (wedding, game, travel) without naming titles or "
        "places. One next move that protects load."
    ),
    "proceed": (
        "They have the capacity and this is how they work. Answer the ask. "
        "Cite one signal as support, not a HUD."
    ),
    "fuel": (
        "Training has to fit the next meal. Protein and water before another "
        "session lecture."
    ),
    "clarify": (
        "Say what is missing. Do not invent a baseline. Best-effort read, then "
        "one focused follow-up."
    ),
}

_MOVE = {
    "protect": "Protect load and fit a shorter session around the day they already have.",
    "proceed": "Spend the readiness on one quality session, in the slot they actually use.",
    "fuel": "Protein and water with the next meal, then train inside the day they have.",
    "clarify": "Give a best-effort read, then ask for the one missing signal.",
}


def _how_you_work(persona: PersonaState, cal: CalendarRead) -> str:
    conf = persona.confidence()
    slot = persona.preferred_slot()
    follow = persona.posterior("follow")
    domain_post = persona.posterior("domain")
    talk = max(domain_post, key=domain_post.get)
    bits: list[str] = []
    if conf < 0.18:
        bits.append("Still learning how you work — using today's calendar and a cautious prior.")
    else:
        bits.append(f"You tend to train in the {slot}.")
        if persona.p_skip_evening() >= 0.55:
            bits.append("You usually skip when the evening is packed.")
        elif follow.get("complete", 0) >= 0.6:
            bits.append("When you plan a session, you usually finish it.")
        if domain_post.get(talk, 0) >= 0.22 and talk not in ("lifestyle",):
            bits.append(f"You keep coming back to {talk} with ARIA.")
    if cal.headlines:
        kind = cal.headlines[0]
        bits.append(f"This week has {kind} on it — that changes the session, not the relationship.")
    elif cal.evening_busy:
        bits.append("Evening is spoken for today.")
    elif cal.morning_busy:
        bits.append("Morning is already spoken for.")
    rel = persona.relationship_level
    if rel <= 2:
        bits.append("Relationship is new — known, not familiar.")
    elif rel <= 5:
        bits.append(f"You've been talking ({rel}/10) — recall is allowed, familiarity isn't assumed.")
    else:
        bits.append("There's a real bond. Callbacks are earned; don't perform them.")
    if persona.n_ingest > 0:
        ingested = persona.ingest_posterior()
        held = max(ingested, key=ingested.get)
        if ingested.get(held, 0) >= 0.18:
            bits.append(f"I've already been holding {held} from what we've seen together.")
    if persona.last_priority:
        bits.append(f"On days like this I lead with {persona.last_priority[0]}.")
    if persona.last_verdict == "wrong":
        bits.append("Last call missed — I am correcting, not repeating it.")
    elif persona.last_verdict == "right":
        bits.append("Last call landed — keep the principle.")
    return " ".join(bits)


def _cite(feat: dict[str, float], lead: str) -> list[str]:
    cites: list[str] = []
    if feat["short_sleep"] or lead == "sleep":
        cites.append("sleep.duration")
    if feat["low_recovery"] or feat["high_recovery"] or lead in ("readiness", "training"):
        cites.append("readiness.recovery")
    if feat["headline"] or feat["evening_busy"]:
        cites.append("lifestyle.calendar")
    return cites[:3]


def _do_not_invent(cal: CalendarRead) -> list[str]:
    banned = ["diagnosis", "supplements", "calendar titles", "places", "attendees"]
    if "cycle" not in cal.kinds:
        banned.append("cycle")
    return banned


# --- Public inference ----------------------------------------------------------


@dataclass
class Adaptation:
    """What ARIA is told: how this person works, and how to coach today."""

    stance: str
    lead_domain: str
    specialists: list[str]
    quality: str
    pattern: str
    salience: float
    how_you_work: str
    how_to_speak: str
    one_next_move: str
    cite: list[str]
    do_not_invent: list[str]
    calendar: dict[str, Any]
    stance_probs: dict[str, float]
    confidence: float
    preferred_slot: str
    n_observations: int
    teach_user: str
    bucket_key: str
    n_updates: int
    grounding: str
    prioritize: list[str]
    priority_scores: dict[str, float]
    priority_reason: str
    event_bucket: str
    last_verdict: str | None = None
    td_alpha: float = TD_ALPHA
    calibration: float = 0.5
    n_right: int = 0
    n_wrong: int = 0
    sources: tuple[str, ...] = ()

    def as_dict(self) -> dict[str, Any]:
        return {
            "stance": self.stance,
            "lead_domain": self.lead_domain,
            "specialists": list(self.specialists),
            "quality": self.quality,
            "pattern": self.pattern,
            "salience": self.salience,
            "how_you_work": self.how_you_work,
            "how_to_speak": self.how_to_speak,
            "one_next_move": self.one_next_move,
            "cite": list(self.cite),
            "do_not_invent": list(self.do_not_invent),
            "calendar": dict(self.calendar),
            "stance_probs": dict(self.stance_probs),
            "confidence": self.confidence,
            "preferred_slot": self.preferred_slot,
            "n_observations": self.n_observations,
            "teach_user": self.teach_user,
            "bucket": self.bucket_key,
            "n_updates": self.n_updates,
            "grounding": self.grounding,
            "prioritize": list(self.prioritize),
            "priority_scores": {
                k: round(v, 4) for k, v in self.priority_scores.items()
            },
            "priority_reason": self.priority_reason,
            "event_bucket": self.event_bucket,
            "last_verdict": self.last_verdict,
            "td_alpha": round(self.td_alpha, 4),
            "calibration": round(self.calibration, 4),
            "n_right": self.n_right,
            "n_wrong": self.n_wrong,
            "sources": list(self.sources),
            "aria_instructions": self.aria_instructions(),
        }

    def aria_instructions(self) -> str:
        specs = ", ".join(self.specialists) or "aria"
        cites = ", ".join(self.cite) or "none"
        banned = ", ".join(self.do_not_invent)
        order = " > ".join(self.prioritize) or self.lead_domain
        verdict = self.last_verdict or "none"
        extra = ""
        if self.last_verdict == "wrong":
            extra = (
                "You judged your last coaching call as wrong. Do not double down "
                "on that stance; change the call."
            )
        elif self.last_verdict == "right":
            extra = (
                "Your last coaching call was right. Keep the same principle, "
                "not the same script."
            )
        return (
            "[CONTEXTUALIZATION — how this person works]\n"
            f"- how_you_work: {self.how_you_work}\n"
            f"- lead_domain: {self.lead_domain}\n"
            f"- prioritize: {order}\n"
            f"- event: {self.event_bucket}\n"
            f"- priority_reason: {self.priority_reason}\n"
            f"- stance: {self.stance}\n"
            f"- pattern: {self.pattern}\n"
            f"- quality: {self.quality}\n"
            f"- preferred_slot: {self.preferred_slot}\n"
            f"- specialists: {specs}\n"
            f"- speak: {self.how_to_speak}\n"
            f"- cite: {cites}\n"
            f"- do_not_invent: {banned}\n"
            f"- one_next_move: {self.one_next_move}\n"
            f"- teach_the_person: {self.teach_user}\n"
            f"- grounding: {self.grounding}\n"
            f"- last_verdict: {verdict}\n"
            f"- calibration: {self.calibration:.2f} "
            f"({self.n_right} right / {self.n_wrong} wrong)\n"
            f"- learned_confidence: {self.confidence:.2f} from {self.n_observations} observations "
            f"({self.n_updates} RL updates, alpha={self.td_alpha:.2f})\n"
            "Follow this block. Teach from it — one learned fact, never a HUD. "
            "Follow prioritize in order; lead with the first domain. "
            "If grounding is generalized, coach from conversation, relationship, and "
            "what you have already ingested; do not invent a calendar or a body you "
            "were not given. If grounding is contextual, fit the session around the "
            "event and busy windows. Never read calendar titles. "
            + extra
        )


def _teach_user(state: PersonaState, cal: CalendarRead, stance: str) -> str:
    """What ARIA teaches the person — a learned fact, not a metric dump."""
    if state.n_updates < 2 and state.n < 3:
        if cal.headlines:
            kind = cal.headlines[0]
            return f"I'll build around the {kind} this week, then learn from whether that actually helped."
        return "I'll learn what actually works for you from what you do next, not just what you say."
    slot = state.preferred_slot()
    if state.p_skip_evening() >= 0.55 and (cal.evening_busy or stance == "protect"):
        return "You've been skipping stacked evenings — I'm treating that as how you work, not a miss."
    if state.posterior("follow").get("complete", 0) >= 0.65 and stance == "proceed":
        return f"When you say yes, you finish. I'll keep putting sessions in the {slot}."
    best_q = -999.0
    best_action = stance
    for key, row in state.q.items():
        for action, value in row.items():
            if value > best_q:
                best_q = value
                best_action = action
    if state.n_updates >= 4 and best_action == "protect":
        return "Protecting load on thin days has been the move that sticks for you."
    if cal.headlines:
        return f"There's {cal.headlines[0]} this week. I'll teach the plan around that, then update from what you actually do."
    return f"I'm coaching toward the {slot} slot because that's where your sessions actually land."


def _grounding(feat: dict[str, float], cal: CalendarRead) -> str:
    """contextual = life or body was sent; generalized = conversation + priors."""
    has_life = bool(cal.headlines or cal.evening_busy or cal.morning_busy or cal.busy_today)
    has_body = (
        feat.get("low_recovery", 0) >= 0.5
        or feat.get("high_recovery", 0) >= 0.5
        or feat.get("short_sleep", 0) >= 0.5
    )
    return "contextual" if (has_life or has_body) else "generalized"


def _pattern(feat: dict[str, float], stance: str) -> str:
    if feat["missing"] >= 0.55:
        return "sparse_picture"
    if feat["headline"]:
        return "life_event"
    if feat["evening_busy"] and feat["p_skip_evening"] >= 0.5:
        return "protects_evenings"
    if feat["low_recovery"] or feat["short_sleep"]:
        return "under_recovery"
    if feat["high_recovery"] and stance == "proceed":
        return "well_recovered"
    if feat["lang_food"]:
        return "fuel_gap"
    return "normal"


def adapt(
    message: str,
    ctx: Any,
    persona: PersonaState | dict[str, Any] | None = None,
) -> Adaptation:
    """Pure: today's life + the learned persona → how ARIA should adapt."""
    state = persona if isinstance(persona, PersonaState) else PersonaState.from_dict(persona)
    feat = features(message, ctx, state)
    stance, probs = _pick_stance(feat, state)
    cal = parse_calendar(_lifestyle_tags(ctx))
    ranking, scores, reason = rank_priorities(message, ctx, state, feat, cal)
    lead = ranking[0]
    conf = state.confidence()
    specs = _specialists(lead, feat, stance, state, ranking)
    key = bucket(feat)
    quality = "sparse" if feat["missing"] >= 0.55 else ("trusted" if conf >= 0.35 or cal.headlines else "forming")
    return Adaptation(
        stance=stance,
        lead_domain=lead,
        specialists=specs,
        quality=quality,
        pattern=_pattern(feat, stance),
        salience=round(max(probs.values()) * (0.55 + 0.45 * (1.0 - feat["missing"])), 4),
        how_you_work=_how_you_work(state, cal),
        how_to_speak=_SPEAK[stance],
        one_next_move=_MOVE[stance],
        cite=_cite(feat, lead),
        do_not_invent=_do_not_invent(cal),
        calendar=cal.as_dict(),
        stance_probs=probs,
        confidence=conf,
        preferred_slot=state.preferred_slot(),
        n_observations=state.n,
        teach_user=_teach_user(state, cal, stance),
        bucket_key=key,
        n_updates=state.n_updates,
        grounding=_grounding(feat, cal),
        prioritize=list(ranking),
        priority_scores=scores,
        priority_reason=reason,
        event_bucket=event_bucket(cal),
        last_verdict=state.last_verdict,
        td_alpha=state.td_alpha,
        calibration=state.calibration,
        n_right=state.n_right,
        n_wrong=state.n_wrong,
        sources=_hot_sources(feat),
    )


def stamp_living_context(ctx: Any, living: Any) -> Any:
    """Copy CoachContextEngine ingest onto an ARIAContext in place.

    Insights, patterns, goals, and constraints are what ARIA has already
    ingested. The dummy never owns this; live chat stamps it so ``adapt()``
    and ``observe_ingest()`` see the same memory.
    """
    if ctx is None or living is None:
        return ctx
    insights = list(getattr(living, "last_insights", None) or [])
    patterns = list(getattr(living, "recent_patterns", None) or [])
    goals = list(getattr(living, "current_goals", None) or [])
    constraints = list(getattr(living, "constraints", None) or [])
    try:
        setattr(ctx, "last_insights", insights)
        setattr(ctx, "constraints", constraints)
        setattr(ctx, "current_goals", goals)
    except Exception:
        pass
    lifestyle = getattr(ctx, "lifestyle", None)
    if lifestyle is not None:
        existing_p = list(getattr(lifestyle, "recent_patterns", None) or [])
        existing_g = list(getattr(lifestyle, "goals", None) or [])
        for item in patterns:
            if item not in existing_p:
                existing_p.append(item)
        for item in goals:
            if item not in existing_g:
                existing_g.append(item)
        try:
            lifestyle.recent_patterns = existing_p
            lifestyle.goals = existing_g
        except Exception:
            pass
    return ctx


# --- Persistence (optional; never imported by adapt) -------------------------


def persona_key(user_id: str) -> dict[str, str]:
    return {"pk": f"USER#{user_id}", "sk": "ARIA#PERSONA"}


def load(user_id: str) -> PersonaState:
    uid = (user_id or "").strip()
    if not uid:
        return PersonaState()
    try:
        from storage import dynamodb
        from storage import keys as storage_keys
    except Exception:
        return PersonaState()
    key_fn = getattr(storage_keys, "aria_persona_key", None)
    key = key_fn(uid) if callable(key_fn) else persona_key(uid)
    item = dynamodb.get_item(key["pk"], key["sk"])
    if not item:
        return PersonaState()
    payload = item.get("payload") if isinstance(item, dict) else None
    return PersonaState.from_dict(payload if isinstance(payload, dict) else item)


def save(user_id: str, state: PersonaState) -> None:
    uid = (user_id or "").strip()
    if not uid:
        return
    try:
        from storage import dynamodb
        from storage import keys as storage_keys
    except Exception:
        return
    key_fn = getattr(storage_keys, "aria_persona_key", None)
    key = key_fn(uid) if callable(key_fn) else persona_key(uid)
    dynamodb.put_item({**key, "payload": state.as_dict(), "user_id": uid})


def observe_turn(
    state: PersonaState,
    *,
    message: str,
    tags: Iterable[str] | None,
    relationship_level: int | None = None,
    ctx: Any = None,
) -> PersonaState:
    """One chat turn: self-train from the utterance, then events, conversation, ingest."""
    self_train_from_conversation(state, message)
    if tags:
        observe_calendar(state, tags)
    observe_conversation(state, message)
    if relationship_level is not None:
        observe_relationship(state, relationship_level)
    if ctx is not None:
        observe_ingest(state, ctx)
    return state


def self_train_from_conversation(state: PersonaState, message: str) -> float | None:
    """ARIA trains herself from what they just said, without waiting for a workout."""
    if not state.last_stance:
        return None
    try:
        from . import self_trainer

        reward = self_trainer.conversation_reward(message)
    except Exception:
        return None
    if reward is None:
        return None
    reinforce(state, reward)
    return reward


def apply_chat_turn(
    state: PersonaState,
    *,
    message: str,
    ctx: Any,
    tags: Iterable[str] | None = None,
    relationship_level: int | None = None,
) -> Adaptation:
    """Orchestrator-agnostic chat step: observe → adapt → commit.

    Live Lambda and the dummy test engine both call this. Persistence
    (``load`` / ``save``) stays with the live route. Dummy keeps state in
    memory and must not call Dynamo.
    """
    if tags is None:
        tags = _lifestyle_tags(ctx)
    observe_turn(
        state,
        message=message,
        tags=tags,
        relationship_level=relationship_level,
        ctx=ctx,
    )
    brief = adapt(message, ctx, state)
    commit_action(
        state,
        brief.bucket_key,
        brief.stance,
        brief.specialists,
        event_bucket_key=brief.event_bucket,
        priority=brief.prioritize,
        stance_p=brief.stance_probs.get(brief.stance, 0.0),
        sources=brief.sources,
    )
    return brief


def apply_workout_outcome(
    state: PersonaState,
    *,
    completed: bool,
    hour: int | None = None,
    evening_busy: bool = False,
    headline: bool = False,
    intensity: str | None = None,
) -> float:
    """Live plan complete/skip (and dummy replay): observe + TD reward."""
    observe_workout(
        state,
        completed=completed,
        hour=hour,
        evening_busy=evening_busy,
        intensity=intensity,
    )
    reward = reward_for_workout(
        completed=completed,
        evening_busy=evening_busy,
        headline=headline,
        last_stance=state.last_stance,
    )
    reinforce(state, reward)
    return reward


def apply_sleep_nudge_outcome(
    state: PersonaState,
    *,
    followed: bool,
) -> float:
    """Wind-down / bedtime breaker: observe + TD reward on the last stance."""
    observe_sleep_nudge(state, followed=followed)
    reward = reward_for_sleep_nudge(
        followed=followed,
        last_stance=state.last_stance,
    )
    reinforce(state, reward)
    return reward


def apply_reaction_outcome(state: PersonaState, reaction: str) -> float:
    """Live thumbs-up/down: observe + TD reward on the last committed stance."""
    observe_reaction(state, reaction)
    reward = reward_for_reaction(reaction)
    if reward == 0.0:
        return 0.0
    reinforce(state, reward)
    return reward
