"""Evidence-graph fusion for ARIA's deterministic coaching core.

Signals are scored data. Patterns are small rules over the scored set.
Python owns the truth: ACWR, sleep debt, and overtraining flags are
derived here (preferring payload values when the client already computed
them) so recommendation / plan builders compose combinations instead of
nested if/elif trees.

Stdlib-only. No Bedrock. No numpy.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Sequence

# Domain priority weights — readiness/sleep/training drive load calls.
_DOMAIN_WEIGHT = {
    "sleep": 1.0,
    "readiness": 1.0,
    "training": 0.9,
    "nutrition": 0.7,
    "lifestyle": 0.65,
    "activity": 0.55,
    "body": 0.5,
    "chronotype": 0.45,
    "progress": 0.4,
}
_PRIORITY_WEIGHT = {"high": 1.0, "medium": 0.7, "low": 0.4}
_DIRECTION_MAG = {"negative": 1.0, "positive": 0.85, "neutral": 0.35}

# Banister-style ACWR bands (Foster acute:chronic workload ratio).
ACWR_SWEET_LOW = 0.8
ACWR_SWEET_HIGH = 1.3
ACWR_OVERREACH = 1.5

# Sleep-debt gates aligned with SimRunner directional rules.
SLEEP_DEBT_TONIGHT_H = 2.0
SLEEP_DEBT_7D_H = 5.0
TARGET_SLEEP_H = 8.0

# Readiness hard floor — never advocate high intensity below this.
READINESS_PROTECT = 50.0
READINESS_GREEN = 70.0


@dataclass(frozen=True)
class DerivedLoad:
    """Workload + recovery picture used by pattern detection."""

    acwr: float | None = None
    sleep_debt_tonight_h: float = 0.0
    sleep_debt_7d_h: float | None = None
    is_overtrained: bool = False
    readiness: float | None = None
    hrv_trend: float | None = None
    source: str = "estimated"  # payload | estimated | mixed

    def to_dict(self) -> dict[str, Any]:
        return {
            "acwr": round(self.acwr, 2) if self.acwr is not None else None,
            "sleep_debt_tonight_h": round(self.sleep_debt_tonight_h, 2),
            "sleep_debt_7d_h": (
                round(self.sleep_debt_7d_h, 2) if self.sleep_debt_7d_h is not None else None
            ),
            "is_overtrained": self.is_overtrained,
            "readiness": self.readiness,
            "hrv_trend": self.hrv_trend,
            "source": self.source,
        }


@dataclass(frozen=True)
class ScoredSignal:
    signal: Any
    score: float
    magnitude: float


@dataclass(frozen=True)
class EvidencePattern:
    """One cross-signal story ARIA can speak."""

    key: str
    score: float
    stance: str  # protect | proceed | fuel | clarify
    notice: str
    next_step: str
    why: str
    actions: tuple[str, ...] = field(default_factory=tuple)
    confidence_cap: float | None = None
    reason_suffix: str = ""
    blocks_intensity: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "score": round(self.score, 3),
            "stance": self.stance,
            "notice": self.notice,
            "next_step": self.next_step,
            "why": self.why,
            "actions": list(self.actions),
            "confidence_cap": self.confidence_cap,
            "reason_suffix": self.reason_suffix,
            "blocks_intensity": self.blocks_intensity,
        }


def derive_load(ctx: Any) -> DerivedLoad:
    """Prefer client-computed ACWR / 7d debt; otherwise estimate from weekly load."""
    training = getattr(ctx, "training", None)
    sleep = getattr(ctx, "sleep", None)
    readiness = getattr(ctx, "readiness", None)

    payload_acwr = _num(getattr(training, "acwr", None))
    acute = _num(getattr(training, "acute_load", None))
    chronic = _num(getattr(training, "chronic_load", None))
    weekly = _num(getattr(training, "weekly_load_score", None))
    debt_7d = _num(getattr(sleep, "sleep_debt_7d_hours", None))
    target_h = _num(getattr(sleep, "target_hours", None)) or TARGET_SLEEP_H
    duration_min = _num(getattr(sleep, "duration_minutes", None))
    recovery = _num(getattr(readiness, "recovery_score", None))
    hrv_trend = _num(getattr(readiness, "hrv_7day_trend", None))

    source_bits: list[str] = []
    acwr = payload_acwr
    if acwr is None and acute is not None and chronic is not None and chronic > 1e-6:
        acwr = acute / chronic
        source_bits.append("ratio")
    elif acwr is not None:
        source_bits.append("payload")
    elif weekly is not None:
        # weekly_load_score is ~0–100; map 55 → ~1.0 ACWR sweet-spot center.
        acwr = max(0.4, min(2.2, weekly / 55.0))
        source_bits.append("estimated")

    tonight = 0.0
    if duration_min is not None:
        tonight = max(0.0, target_h - (duration_min / 60.0))

    if debt_7d is not None:
        source_bits.append("debt7d")
    elif tonight > 0:
        # Single-night shortfall is a lower-bound proxy until multi-night history arrives.
        debt_7d = tonight
        source_bits.append("debt_proxy")

    overtrained = False
    flag = getattr(training, "is_overtrained", None)
    if isinstance(flag, bool):
        overtrained = flag
        source_bits.append("flag")
    elif acwr is not None:
        if acwr >= ACWR_OVERREACH:
            overtrained = True
        elif acwr >= ACWR_SWEET_HIGH and recovery is not None and recovery < READINESS_PROTECT:
            overtrained = True
        elif weekly is not None and weekly >= 90 and (
            hrv_trend is not None and hrv_trend <= -8
        ):
            overtrained = True

    source = "mixed" if len(source_bits) > 1 else (source_bits[0] if source_bits else "estimated")
    if source in ("ratio", "debt_proxy", "flag"):
        source = "payload" if "payload" in source_bits or "flag" in source_bits else "estimated"
    if "payload" in source_bits and ("estimated" in source_bits or "debt_proxy" in source_bits):
        source = "mixed"
    elif "payload" in source_bits or "flag" in source_bits or "debt7d" in source_bits or "ratio" in source_bits:
        source = "payload" if any(s in source_bits for s in ("payload", "debt7d", "ratio", "flag")) else source

    return DerivedLoad(
        acwr=acwr,
        sleep_debt_tonight_h=tonight,
        sleep_debt_7d_h=debt_7d,
        is_overtrained=overtrained,
        readiness=recovery,
        hrv_trend=hrv_trend,
        source=source,
    )


def score_signals(signals: Sequence[Any]) -> list[ScoredSignal]:
    """Rank signals by magnitude × domain weight × priority (± personal bonus)."""
    scored: list[ScoredSignal] = []
    for signal in signals:
        priority = str(getattr(signal, "priority", "low") or "low")
        direction = str(getattr(signal, "direction", "neutral") or "neutral")
        domain = str(getattr(signal, "domain", "") or "")
        kind = str(getattr(signal, "baseline_kind", "population") or "population")
        mag = _DIRECTION_MAG.get(direction, 0.35) * _PRIORITY_WEIGHT.get(priority, 0.4)
        mag *= _DOMAIN_WEIGHT.get(domain, 0.4)
        if kind == "personal":
            mag *= 1.08
        scored.append(ScoredSignal(signal=signal, score=mag, magnitude=mag))
    scored.sort(key=lambda s: (-s.score, str(getattr(s.signal, "domain", ""))))
    return scored


def detect_pattern(
    ctx: Any,
    signals: Sequence[Any],
    restricted: Sequence[str] | None = None,
    *,
    stance: str = "",
    brief: Any = None,
    load: DerivedLoad | None = None,
) -> EvidencePattern:
    """Pick the highest-scoring cross-signal story for today's call."""
    blocked = set(restricted or ())
    derived = load or derive_load(ctx)
    ranked = score_signals(signals)
    lead = ranked[0].signal if ranked else None
    negative = [s.signal for s in ranked if getattr(s.signal, "direction", "") == "negative"]
    learned = ""
    if brief is not None and str(getattr(brief, "stance", "") or "") == stance:
        learned = str(getattr(brief, "one_next_move", "") or "").strip()

    candidates: list[EvidencePattern] = []

    # --- Overreaching / overtraining (ACWR) ---------------------------------
    if derived.is_overtrained or (
        derived.acwr is not None and derived.acwr >= ACWR_SWEET_HIGH and "training" not in blocked
    ):
        acwr_txt = f"{derived.acwr:.2f}" if derived.acwr is not None else "elevated"
        candidates.append(
            EvidencePattern(
                key="overreaching",
                score=1.35 + (0.15 if derived.is_overtrained else 0.0),
                stance="protect",
                notice=(
                    f"Workload is running hot (ACWR {acwr_txt}"
                    f"{', overtraining risk' if derived.is_overtrained else ''}) — "
                    f"{_lead_interp(lead, 'fatigue is stacking')}."
                ),
                next_step=learned
                or "Back off intensity — deload or Zone 2 only until load cools",
                why=(
                    f"ACWR {acwr_txt} sits above the 0.8–1.3 sweet spot"
                    + (
                        "; treat this as overreaching until readiness recovers"
                        if derived.is_overtrained
                        else ""
                    )
                ),
                actions=("Show deload week", "Swap to Zone 2", "Protect tonight's sleep"),
                confidence_cap=0.62 if derived.is_overtrained else 0.72,
                reason_suffix=f"ACWR {acwr_txt} — back off load",
                blocks_intensity=True,
            )
        )

    # --- Under-recovery: HRV↓ + sleep debt ----------------------------------
    hrv_falling = derived.hrv_trend is not None and derived.hrv_trend <= -8
    debt_7 = derived.sleep_debt_7d_h or 0.0
    sleep_ok = "sleep" not in blocked
    if hrv_falling and sleep_ok and (
        derived.sleep_debt_tonight_h > SLEEP_DEBT_TONIGHT_H or debt_7 > SLEEP_DEBT_7D_H
    ):
        debt = debt_7 if debt_7 > derived.sleep_debt_tonight_h else derived.sleep_debt_tonight_h
        candidates.append(
            EvidencePattern(
                key="under_recovery",
                score=1.4,
                stance="protect",
                notice=(
                    f"HRV {abs(derived.hrv_trend):.0f}% below baseline with {debt:.1f}h sleep debt — "
                    f"sleep first tonight, then training"
                ),
                next_step=learned
                or "Sleep first — protect tonight's wind-down before training volume",
                why="HRV falling plus sleep debt means the autonomic system is still carrying load",
                actions=("Protect tonight's sleep", "Show recovery plan", "Swap to Zone 2"),
                confidence_cap=0.60,
                reason_suffix=(
                    f"HRV falling {derived.hrv_trend:.0f}% + {debt:.1f}h sleep debt — sleep first, "
                    f"confidence capped"
                ),
                blocks_intensity=True,
            )
        )

    # --- Heavy 7-day sleep debt alone ---------------------------------------
    if sleep_ok and debt_7 > SLEEP_DEBT_7D_H:
        candidates.append(
            EvidencePattern(
                key="sleep_debt",
                score=1.2,
                stance="protect",
                notice=(
                    f"{debt_7:.1f}h of sleep debt over the week — "
                    f"{_lead_interp(lead, 'the night bank is overdrawn')}."
                ),
                next_step=learned or "Prioritize sleep tonight and keep today's session easy",
                why="Seven-day sleep debt above 5h is a directional safety gate",
                actions=("Protect tonight's sleep", "Shorten today's session", "Set a wind-down alarm"),
                confidence_cap=0.65,
                reason_suffix=f"{debt_7:.1f}h sleep debt — prioritize sleep",
                blocks_intensity=True,
            )
        )

    # --- Low readiness hard floor -------------------------------------------
    if derived.readiness is not None and derived.readiness < READINESS_PROTECT:
        candidates.append(
            EvidencePattern(
                key="low_readiness",
                score=1.25,
                stance="protect",
                notice=(
                    f"Readiness {derived.readiness:.0f}/100 — "
                    f"{_lead_interp(lead, 'today is a protect day')}."
                ),
                next_step=learned
                or "Keep today low-intensity — Zone 2 cardio or mobility, not a hard session",
                why="Readiness below 50 never gets a high-intensity call",
                actions=("Show recovery plan", "Swap to Zone 2", "Protect tonight's sleep"),
                confidence_cap=0.68,
                reason_suffix=f"readiness {derived.readiness:.0f} — intensity blocked",
                blocks_intensity=True,
            )
        )

    # --- Life rhythm (Lifestyle QoL) protect — client-authored score only ---
    if "lifestyle" not in blocked:
        qol = getattr(getattr(ctx, "lifestyle", None), "quality_of_life_score", None)
        if isinstance(qol, (int, float)):
            try:
                from services.aria_engine import life_rhythm_training_plan
            except Exception:  # pragma: no cover - defensive import
                life_rhythm_training_plan = None  # type: ignore
            band = getattr(getattr(ctx, "lifestyle", None), "quality_of_life_band", None)
            pillars = getattr(getattr(ctx, "lifestyle", None), "quality_of_life_pillars", None) or {}
            plan = (
                life_rhythm_training_plan(int(qol), band=band if isinstance(band, str) else None, pillars=pillars)
                if life_rhythm_training_plan
                else None
            )
            if plan and (plan.get("keep_light") or int(qol) < 50):
                drivers = getattr(getattr(ctx, "lifestyle", None), "quality_of_life_drivers", None) or []
                driver_bit = f" ({', '.join(list(drivers)[:2])})" if drivers else ""
                candidates.append(
                    EvidencePattern(
                        key="life_rhythm_protect",
                        score=1.18 if int(qol) < 50 else 1.05,
                        stance="protect",
                        notice=(
                            f"Life rhythm {int(qol)}/100{driver_bit} — "
                            f"{_lead_interp(lead, 'ease the session so the grade can climb')}"
                        ),
                        next_step=learned or plan["reason"],
                        why="Lifestyle QoL is strained or depleted — training follows the life grade",
                        actions=("Keep it light", "Show recovery plan", "Open Lifestyle"),
                        confidence_cap=0.70,
                        reason_suffix=plan["reason"],
                        blocks_intensity=True,
                    )
                )

    # --- Persona / fusion stance hooks --------------------------------------
    if stance == "fuel":
        candidates.append(
            EvidencePattern(
                key="fuel_gap",
                score=0.95,
                stance="fuel",
                notice=_lead_interp(lead, "fuel first — protein and water before load"),
                next_step=learned
                or "Protein and water with the next meal, then train inside the day you have",
                why="Nutrition is the limiting signal right now",
                actions=("Log the next meal", "Today's workout", "Check hydration"),
            )
        )
    if stance == "clarify":
        candidates.append(
            EvidencePattern(
                key="clarify",
                score=0.7,
                stance="clarify",
                notice=_lead_interp(lead, "I can give a best-effort read"),
                next_step=learned
                or "Best-effort read from what I have, then the one missing signal",
                why="Usable picture is still thin",
                actions=("Sync HealthKit", "Tell ARIA about last night", "Today's workout"),
                confidence_cap=0.55,
                reason_suffix="sparse signals — clarify before locking the call",
            )
        )

    # --- Negative cluster without a named clinical pattern ------------------
    if negative and stance in ("", "protect", "proceed"):
        driver = negative[0]
        candidates.append(
            EvidencePattern(
                key="protect_cluster",
                score=0.9 + (0.1 if stance == "protect" else 0.0),
                stance="protect",
                notice=_cap(getattr(driver, "interpretation", "") or "signals say protect load"),
                next_step=learned
                or "Keep today low-intensity — Zone 2 cardio or mobility, not a hard session",
                why=f"{getattr(driver, 'metric', 'signal')}: {getattr(driver, 'interpretation', '')}",
                actions=("Show recovery plan", "Swap to Zone 2", "Protect tonight's sleep"),
                blocks_intensity=True,
            )
        )

    # --- Green light --------------------------------------------------------
    if (
        lead is not None
        and getattr(lead, "direction", "") == "positive"
        and not derived.is_overtrained
        and (derived.readiness is None or derived.readiness >= READINESS_GREEN)
        and (derived.acwr is None or derived.acwr < ACWR_SWEET_HIGH)
    ):
        candidates.append(
            EvidencePattern(
                key="green_light",
                score=0.85,
                stance="proceed",
                notice=f"You're primed — {getattr(lead, 'interpretation', 'signals look strong')}.",
                next_step=learned or "Green light for intensity — this is a day to push",
                why=f"{getattr(lead, 'metric', 'signal')}: {getattr(lead, 'interpretation', '')}",
                actions=("Build a hard session", "Set a PR target", "Review readiness"),
            )
        )

    # --- Default moderate ---------------------------------------------------
    detail = getattr(lead, "interpretation", None) if lead else None
    candidates.append(
        EvidencePattern(
            key="moderate",
            score=0.4,
            stance="proceed" if stance in ("", "proceed") else (stance or "proceed"),
            notice=_cap(detail or "your signals are mid-band"),
            next_step=learned
            or "Train at moderate intensity with controlled progressive overload",
            why=detail or "steady stimulus without overreaching",
            actions=("Today's workout", "Tune intensity", "Check sleep trend"),
        )
    )

    candidates.sort(key=lambda p: (-p.score, p.key))
    return candidates[0]


def agreement_factor(signals: Sequence[Any]) -> tuple[float, str | None]:
    """Direction agreement for principled confidence: coherent → slight bonus."""
    directions = {
        getattr(s, "direction", "")
        for s in signals
        if getattr(s, "direction", "") in ("negative", "positive")
    }
    if "negative" in directions and "positive" in directions:
        return -0.12, "signals diverge (e.g. sleep and HRV disagree)"
    if len(signals) >= 2 and directions == {"negative"}:
        return 0.02, None
    if len(signals) >= 2 and directions == {"positive"}:
        return 0.02, None
    return 0.0, None


def plan_outline(pattern: EvidencePattern, ctx: Any, days: int = 3) -> list[dict[str, str]]:
    """Multi-day skeleton for the ``plan`` response type."""
    days = max(2, min(7, int(days)))
    goal = getattr(getattr(ctx, "profile", None), "primary_goal", None) or "general-fitness"
    blocks_intensity = pattern.blocks_intensity or pattern.stance == "protect"

    outline: list[dict[str, str]] = []
    for i in range(days):
        if blocks_intensity and i == 0:
            focus = "Recovery / Zone 2 only"
            note = pattern.next_step
        elif blocks_intensity and i == 1:
            focus = "Mobility + easy aerobic"
            note = "Reassess HRV and sleep before adding intensity"
        elif not blocks_intensity and i == 0:
            focus = "Primary quality session"
            note = pattern.next_step
        elif not blocks_intensity and i == 1:
            focus = "Supporting volume"
            note = f"Bias toward {goal} without stacking fatigue"
        else:
            focus = "Optional easy or rest"
            note = "Leave headroom if sleep or readiness slips"
        outline.append({"day": f"Day {i + 1}", "focus": focus, "note": note})
    return outline


def _lead_interp(lead: Any, fallback: str) -> str:
    if lead is None:
        return fallback
    text = str(getattr(lead, "interpretation", "") or "").strip()
    return text or fallback


def _cap(text: str) -> str:
    text = (text or "").strip()
    if not text:
        return text
    return text[0].upper() + text[1:]


def _num(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
