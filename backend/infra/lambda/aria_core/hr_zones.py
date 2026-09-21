"""Heart-rate zones — shared iOS + watchOS + Android effort bands.

Python port of ForgeCore's ``HRZones.swift`` (numbers only; SwiftUI Color
stays on the client). Thresholds are the v1 fixed bands.
"""

from __future__ import annotations

from dataclasses import dataclass

# Upper bounds for zones 1-4 (zone 5 is everything above).
THRESHOLDS: tuple[int, int, int, int] = (110, 130, 150, 165)

_COACHING = {
    1: "Easy does it — this pace is pure recovery.",
    2: "Perfect Zone 2 — this is what building your base feels like.",
    3: "Strong steady work. Breathing hard but in control is the spot.",
    4: "High effort — great in doses. Listen for when it's enough.",
    5: "Max effort. Short and sharp, then let it go.",
}


@dataclass(frozen=True)
class HRZone:
    zone: int
    label: str

    @property
    def coaching_line(self) -> str:
        return _COACHING.get(self.zone, _COACHING[5])


def zone_for_bpm(bpm: int) -> HRZone:
    if bpm < THRESHOLDS[0]:
        return HRZone(1, "Zone 1")
    if bpm < THRESHOLDS[1]:
        return HRZone(2, "Zone 2")
    if bpm < THRESHOLDS[2]:
        return HRZone(3, "Zone 3")
    if bpm < THRESHOLDS[3]:
        return HRZone(4, "Zone 4")
    return HRZone(5, "Zone 5")


def zone_for_number(number: int) -> HRZone:
    if number <= 1:
        return zone_for_bpm(THRESHOLDS[0] - 1)
    if number == 2:
        return zone_for_bpm(THRESHOLDS[0])
    if number == 3:
        return zone_for_bpm(THRESHOLDS[1])
    if number == 4:
        return zone_for_bpm(THRESHOLDS[2])
    return zone_for_bpm(THRESHOLDS[3])
