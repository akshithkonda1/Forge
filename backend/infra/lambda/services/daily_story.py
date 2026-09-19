"""ARIA's daily story — a short narrative plus a handful of actionable
insights, generated from whatever domains ``fusion.fuse_turn`` already fused
(readiness/aging/activity/sleep) for this turn.

This does not re-fuse anything. ``context.aging.sources`` already carries
whichever signals contributed to the fused biological age — today that is
Apple Health-derived estimates only (see ``estimators.fuse_biological_age``),
but that dict-keyed fusion already accepts vendor ages by source name, so a
future Whoop/Terra sample slots in there with zero changes here: the
narrative and insight text just start citing another source alongside HRV
and VO2.

Deterministic Phase-1 rules, same posture as ``estimators.py``: state what
the data actually shows, never invent a signal that is not present. A quiet
day with too little to say returns ``None`` rather than padding the story.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from services import aria_engine

# Thresholds below mirror the ones ``fusion.py`` already uses for
# "meaningfully off personal baseline" (see ``_personal_deficit_protect``),
# so a reader doesn't get a different definition of "notable" per surface.
_HRV_TREND_NOTABLE = 8.0
_AGING_DELTA_NOTABLE = 1.0


@dataclass
class StoryInsight:
    text: str
    domain: str
    evidence: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {"text": self.text, "domain": self.domain, "evidence": self.evidence}


@dataclass
class DailyStory:
    generated_at: datetime
    narrative: str
    insights: list[StoryInsight] = field(default_factory=list)
    sources: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "generated_at": self.generated_at.isoformat(),
            "narrative": self.narrative,
            "insights": [i.to_dict() for i in self.insights],
            "sources": self.sources,
        }


def build_daily_story(
    context: aria_engine.ARIAContext,
    baselines: Any,
    *,
    now: datetime | None = None,
) -> DailyStory | None:
    """Turn an already permission-redacted ``ARIAContext`` into a story.

    ``context`` must already have denied domains blanked by
    ``aria_engine.apply_permissions`` (``fusion.fuse_turn`` does this before
    returning) — this function does not re-check permissions, so a blanked
    domain is indistinguishable from, and handled the same as, one with no
    data yet.
    """
    now = now or datetime.now(timezone.utc)
    insights: list[StoryInsight] = []
    sources: set[str] = set()

    aging = context.aging
    if aging.delta_years is not None and aging.state in ("younger", "older") and abs(aging.delta_years) >= _AGING_DELTA_NOTABLE:
        direction = "dropped" if aging.state == "younger" else "climbed"
        cited = _cite(aging.sources)
        insights.append(StoryInsight(
            text=(
                f"Your training age has {direction} about {abs(aging.delta_years):g} year"
                f"{'s' if abs(aging.delta_years) != 1 else ''} {aging.state} than your calendar age"
                + (f", driven by {cited}" if cited else "") + "."
            ),
            domain="aging",
            evidence=f"biological age {aging.biological_age_years:g}y vs calendar {aging.chronological_age_years:g}y"
                if aging.biological_age_years is not None and aging.chronological_age_years is not None else "",
        ))
        sources.update(_source_tags(aging.sources))

    readiness = context.readiness
    if readiness.hrv_7day_trend is not None and abs(readiness.hrv_7day_trend) >= _HRV_TREND_NOTABLE:
        if readiness.hrv_7day_trend <= -_HRV_TREND_NOTABLE:
            insights.append(StoryInsight(
                text="Your HRV has been trending down this week — recovery is asking for easier days, not harder ones.",
                domain="readiness",
                evidence=f"HRV 7-day trend {readiness.hrv_7day_trend:+.1f}ms",
            ))
        else:
            insights.append(StoryInsight(
                text="Your HRV has been trending up this week — recovery has room for you to push if you want it.",
                domain="readiness",
                evidence=f"HRV 7-day trend {readiness.hrv_7day_trend:+.1f}ms",
            ))
        sources.add("apple-health")

    activity = context.activity
    steps_baseline = getattr(baselines, "steps", None)
    if activity.steps_3day_avg is not None and steps_baseline and steps_baseline > 0:
        ratio = activity.steps_3day_avg / steps_baseline
        if ratio >= 1.25:
            insights.append(StoryInsight(
                text="You've been moving more than usual the last few days — that activity is showing up in the numbers above.",
                domain="activity",
                evidence=f"3-day avg steps {activity.steps_3day_avg:g} vs personal baseline {steps_baseline:g}",
            ))
            sources.add("apple-health")
        elif ratio <= 0.6:
            insights.append(StoryInsight(
                text="Activity has been quieter than your usual the last few days.",
                domain="activity",
                evidence=f"3-day avg steps {activity.steps_3day_avg:g} vs personal baseline {steps_baseline:g}",
            ))
            sources.add("apple-health")

    sleep = context.sleep
    sleep_baseline = getattr(baselines, "sleep_duration_min", None)
    if sleep.duration_minutes is not None and sleep_baseline and sleep_baseline > 0:
        if sleep.duration_minutes < 0.85 * sleep_baseline:
            insights.append(StoryInsight(
                text="Last night ran short of what you usually get — worth protecting tonight.",
                domain="sleep",
                evidence=f"{sleep.duration_minutes:g}min vs personal baseline {sleep_baseline:g}min",
            ))
            sources.add("apple-health")

    if not insights:
        return None

    narrative = _narrative(insights)
    return DailyStory(generated_at=now, narrative=narrative, insights=insights, sources=sorted(sources))


def _cite(source_labels: list[str]) -> str:
    """As ``body_model._aging_estimates`` actually emits them: plain tokens
    ``"vo2"`` / ``"rhr"`` / ``"hrv"`` for signal-derived estimates, or
    ``"<vendor>:<kind>"`` once a vendor age (Whoop, Terra, ...) contributes —
    at which point this starts naming the vendor directly, no code change
    needed here."""
    if not source_labels:
        return ""
    readable = {"hrv": "your recovery (HRV)", "vo2": "your fitness (VO2)", "rhr": "resting heart rate"}
    for label in source_labels:
        if label in readable:
            return readable[label]
    for label in source_labels:
        if ":" in label:
            return label.split(":", 1)[0]
    return ""


def _source_tags(source_labels: list[str]) -> list[str]:
    tags: list[str] = []
    for label in source_labels:
        tags.append(label.split(":", 1)[0] if ":" in label else "apple-health")
    return tags


# Priority order for which insights lead the narrative paragraph — a
# causal/structural read (aging) outranks a single-week trend, which
# outranks a single-night deviation.
_DOMAIN_PRIORITY = {"aging": 0, "readiness": 1, "activity": 2, "sleep": 3}


def _narrative(insights: list[StoryInsight]) -> str:
    ranked = sorted(insights, key=lambda i: _DOMAIN_PRIORITY.get(i.domain, 9))
    lead = ranked[: min(2, len(ranked))]
    return " ".join(i.text for i in lead)
