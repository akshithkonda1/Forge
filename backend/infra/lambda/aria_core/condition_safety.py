"""Declared-condition safety rules. User-declared only. Never guess.

Coach copy never names seizures or medication. When a rule changes a plan,
ARIA says so. Stdlib only.
"""

from __future__ import annotations

from typing import Any, Iterable

BANNED = (
    "seizure",
    "seizures",
    "medication",
    "medications",
    "prescription",
    "prescribe",
    "recovery",
)

SWIM = ("swim", "swimming", "open water")
CLIMB = ("climb", "climbing", "boulder", "bouldering", "rope climb")


def contains_banned(text: str) -> bool:
    lower = (text or "").lower()
    return any(token in lower for token in BANNED)


def is_solo_swim_or_climb(name: str) -> bool:
    lower = (name or "").lower()
    return any(token in lower for token in SWIM + CLIMB)


def decide(
    declared: Iterable[str] | None,
    *,
    sleep_hours: float | None = None,
    heat_risk: bool = False,
    move_names: Iterable[str] | None = None,
) -> dict[str, Any]:
    conditions = [str(item).strip().lower() for item in (declared or []) if str(item).strip()]
    if not conditions:
        return {
            "blockedMoves": [],
            "keptMoves": [],
            "replacements": [],
            "flags": [],
            "changeNote": "",
            "applied": False,
        }
    epilepsy = "epilepsy" in conditions or "seizures" in conditions
    blocked: list[str] = []
    kept: list[str] = []
    replacements: list[str] = []
    flags: list[str] = []
    for name in move_names or []:
        if epilepsy and is_solo_swim_or_climb(name):
            blocked.append(name)
            swap = _replacement(name)
            if swap:
                replacements.append(swap)
        else:
            kept.append(name)
    if epilepsy and sleep_hours is not None and sleep_hours < 6.5:
        flags.append("sleepLoss")
    if epilepsy and heat_risk:
        flags.append("heat")
    note = _note(blocked, replacements, flags)
    return {
        "blockedMoves": blocked,
        "keptMoves": kept,
        "replacements": replacements,
        "flags": flags,
        "changeNote": note,
        "applied": bool(blocked or flags),
    }


def _replacement(name: str) -> str | None:
    lower = name.lower()
    if any(token in lower for token in SWIM):
        return "Easy pool-side mobility"
    if any(token in lower for token in CLIMB):
        return "Floor strength circuit"
    return None


def _note(blocked: list[str], replacements: list[str], flags: list[str]) -> str:
    bits: list[str] = []
    if blocked:
        listed = " and ".join(item.lower() for item in blocked)
        if replacements:
            swapped = " and ".join(item.lower() for item in replacements)
            bits.append(f"A safety rule swapped {listed} for {swapped}.")
        else:
            bits.append(f"A safety rule removed {listed} from today's plan.")
    if "sleepLoss" in flags:
        bits.append("Last night ran short — keep intensity grounded.")
    if "heat" in flags:
        bits.append("Heat is high — keep the session cooler and shorter.")
    return " ".join(bits)


def training_line(declared: Iterable[str] | None) -> str:
    conditions = [str(item).strip().lower() for item in (declared or []) if str(item).strip()]
    if "epilepsy" in conditions or "seizures" in conditions:
        return (
            "Here's what works with your body: no solo swimming or climbing, "
            "grounded intensity, predictable rest windows, and extra care after "
            "short sleep or heat. Lifestyle coaching only."
        )
    return ""
