"""Proactive ARIA brief — deterministic coaching copy for push and Home."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from data.seed_data import today_iso
from services import conclusions_store
from services.daily_scores import get_or_compute_daily_scores


_VALID_FOCUS = {"morning", "evening", "post-workout", "auto", "midday"}


def _infer_focus(focus: str) -> str:
    if focus in _VALID_FOCUS and focus != "auto":
        return focus
    hour = datetime.now(timezone.utc).hour
    if hour < 12:
        return "morning"
    if hour >= 20:
        return "evening"
    return "midday"


def _decision_label(decision: str) -> str:
    return {
        "train": "Train",
        "active_rest": "Active rest",
        "recover": "Recover",
    }.get(decision, "Check in")


def _title_for_focus(*, focus: str, decision: str) -> str:
    if focus == "morning":
        return {
            "train": "Morning brief — ready to train",
            "active_rest": "Morning brief — move with intent",
            "recover": "Morning brief — recovery day",
        }.get(decision, "Morning brief")
    if focus == "evening":
        return "Evening wind-down"
    if focus == "post-workout":
        return "Post-workout debrief"
    return "ARIA check-in"


def _headline(
    *,
    focus: str,
    decision: str,
    strain: int,
    recovery: int,
    sleep_score: int,
    sleep_need: int,
    compound_flags: list[str],
) -> str:
    if focus == "evening":
        if sleep_need > 0:
            hours = sleep_need // 60
            mins = sleep_need % 60
            need = f"{hours}h {mins}m" if hours and mins else (f"{hours}h" if hours else f"{mins}m")
            return f"Sleep need {need} tonight — start winding down early."
        return f"Recovery {recovery}/100 · Sleep {sleep_score}/100 — protect tonight's rest."

    if focus == "post-workout":
        return f"Session logged — strain {strain}/100. Prioritize cooldown and hydration."

    if "recovery-debt-under-load" in compound_flags:
        return f"Recovery debt under load — {_decision_label(decision).lower()} recommended."

    if decision == "train":
        return f"Trilogy green light — strain {strain}, recovery {recovery}, sleep {sleep_score}."
    if decision == "recover":
        return f"Recovery {recovery}/100 — ease intensity and bank sleep."
    return f"Active rest window — recovery {recovery}/100, sleep {sleep_score}/100."


def _body(
    *,
    focus: str,
    decision: str,
    coaching_brief: str,
    dashboard_template: str,
    strain: int,
    recovery: int,
    sleep_score: int,
    sleep_need: int,
    cycle_note: str | None,
) -> str:
    parts: list[str] = []

    if focus == "morning":
        parts.append(dashboard_template or coaching_brief)
        parts.append(
            f"Today's trilogy — Strain {strain}, Recovery {recovery}, Sleep {sleep_score}. "
            f"Action: {_decision_label(decision)}."
        )
    elif focus == "evening":
        parts.append(coaching_brief)
        if sleep_need > 0:
            parts.append(f"You're short about {sleep_need} minutes of sleep vs target — dim screens and hydrate.")
        else:
            parts.append("Sleep bank looks adequate — keep your bedtime consistent.")
    elif focus == "post-workout":
        parts.append(
            f"Nice work. Strain is {strain}/100 with recovery at {recovery}/100. "
            "Cool down, refuel within 60 minutes, and log how you feel."
        )
    else:
        parts.append(coaching_brief)
        parts.append(f"Current decision: {_decision_label(decision)}.")

    if cycle_note:
        parts.append(cycle_note)

    return " ".join(p.strip() for p in parts if p and p.strip())


def notification_copy(headline: str, body: str) -> str:
    text = headline.strip()
    if len(text) < 80 and body:
        extra = body.split(".")[0].strip()
        if extra and extra not in text:
            text = f"{text} {extra}."
    return text[:178]


def build_proactive_brief(
    user_id: str,
    *,
    focus: str = "auto",
    date: str | None = None,
) -> dict[str, Any]:
    """Build proactive brief from conclusions + authoritative daily scores."""
    target_focus = _infer_focus(focus.lower() if focus else "auto")
    target_date = date or today_iso()

    conclusions = conclusions_store.get_or_refresh_conclusions(user_id)
    compound_flags = conclusions.get("compoundFlags") or []
    coaching_brief = conclusions.get("coachingBrief") or ""
    templates = conclusions.get("offlineTemplates") or {}
    dashboard_template = templates.get("dashboard") or ""

    daily = get_or_compute_daily_scores(
        user_id,
        date=target_date,
        compound_flags=compound_flags,
    )
    decision = str(daily.get("trainingDecision") or "active_rest")
    strain = int((daily.get("strain") or {}).get("score") or 0)
    recovery = int((daily.get("recovery") or {}).get("score") or 0)
    sleep_block = daily.get("sleep") or {}
    sleep_score = int(sleep_block.get("score") or 0)
    sleep_need = int(sleep_block.get("sleepNeedMinutes") or 0)
    cycle = daily.get("cycleContext") or {}
    cycle_note = cycle.get("coachingNote") if cycle.get("hasData") else None

    headline = _headline(
        focus=target_focus,
        decision=decision,
        strain=strain,
        recovery=recovery,
        sleep_score=sleep_score,
        sleep_need=sleep_need,
        compound_flags=compound_flags,
    )
    body = _body(
        focus=target_focus,
        decision=decision,
        coaching_brief=coaching_brief,
        dashboard_template=dashboard_template,
        strain=strain,
        recovery=recovery,
        sleep_score=sleep_score,
        sleep_need=sleep_need,
        cycle_note=cycle_note,
    )

    return {
        "focus": target_focus,
        "title": _title_for_focus(focus=target_focus, decision=decision),
        "headline": headline,
        "body": body,
        "notificationCopy": notification_copy(headline, body),
        "trainingDecision": decision,
        "dailyScores": {
            "date": daily.get("date", target_date),
            "strain": daily.get("strain"),
            "recovery": daily.get("recovery"),
            "sleep": daily.get("sleep"),
            "trainingDecision": decision,
            "cycleContext": cycle,
        },
        "compoundFlags": compound_flags,
        "coachingBrief": coaching_brief,
        "coveragePct": conclusions.get("coveragePct"),
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }