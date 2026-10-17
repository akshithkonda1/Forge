#!/usr/bin/env python3
"""Fail if deleted HUD / pre-rewrite UI components come back.

Akshith's rewrite made every screen one interface: `forgeContentCard` +
`ForgeCardHeader` + `ForgePageHeader` / `ForgeScreenStack`. Old HUD pieces,
duplicate card chrome, and pre-rewrite widgets must not resurface. The
compiler will not catch a resurrected `HudChrome.swift` until macOS CI, and
it will not catch a web `AriaOrb` wrapper at all. This decides it from the
text, on Linux, in about a second.

Comments and this file's own ban list are ignored. Product Swift / TS / TSX
that names a deleted symbol fails the job.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
)

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT = re.compile(r"//[^\n]*")
HTML_COMMENT = re.compile(r"<!--.*?-->", re.S)

# Deleted identifiers. Adding a name here is the lock: if the type returns
# in product code, Repo Hygiene goes red.
BANNED = [
    "HudChrome",
    "HudVibeChip",
    "HudVitals",
    "HudMark",
    "HudRing",
    "HudOverlay",
    "HudSweep",
    "HudBracket",
    "AriaOrb",
    "drawAriaRingField",
    "HomeAuroraBackground",
    "HomeReadinessFieldView",
    "HomeRingFieldCanvas",
    "HomeRingField",
    "ForgePlate",
    "forgePlate",
    "ForgeCardModifier",
    "forgeInnerWell",
    "forgeSurfaceCard",
    "forgeCardShadow",
    "SegmentedPillControl",
    "ScanlineOverlay",
    "TickDialView",
    "ReticleOverlay",
    "CockpitChrome",
]

# `forgeGlassCard` is the drawing primitive inside `forgeContentCard`. It is
# not a public screen API. Call sites outside these two files are a regression.
GLASS_ALLOW = {
    ROOT / "ForgeSwift" / "ForgeSwift" / "ForgeChrome.swift",
    ROOT / "ForgeSwift" / "ForgeSwift" / "View+ForgeCardShadow.swift",
}

SCAN_GLOBS = [
    "ForgeSwift/**/*.swift",
    "src/**/*.ts",
    "src/**/*.tsx",
]

SELF = ROOT / "scripts" / "check-legacy-ui.py"


def strip_comments(text: str, suffix: str) -> str:
    if suffix in {".ts", ".tsx"}:
        text = HTML_COMMENT.sub("", text)
    return LINE_COMMENT.sub("", BLOCK_COMMENT.sub("", text))


def tracked_files() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "--", "ForgeSwift", "src"],
        capture_output=True,
        text=True,
        check=True,
        cwd=ROOT,
    )
    files: list[Path] = []
    for line in out.stdout.splitlines():
        path = ROOT / line
        if path.suffix in {".swift", ".ts", ".tsx"}:
            files.append(path)
    return files


def main() -> int:
    status = 0
    banned_re = re.compile(r"\b(" + "|".join(re.escape(name) for name in BANNED) + r")\b")
    glass_re = re.compile(r"\bforgeGlassCard\b")
    forge_card_re = re.compile(r"\bforgeCard\s*\(")
    # Leftover from replacing `.forgePlate(energy: x ? a : b)` with
    # `.forgeContentCard() : b)` — that does not compile.
    leftover_ternary_re = re.compile(r"forgeContentCard\([^)]*\)\s*:")

    hits: list[str] = []
    glass_hits: list[str] = []
    leftover_hits: list[str] = []

    for path in tracked_files():
        if path.resolve() == SELF.resolve():
            continue
        if not path.is_file():
            continue
        raw = path.read_text(encoding="utf-8")
        body = strip_comments(raw, path.suffix)
        rel = path.relative_to(ROOT)

        for match in banned_re.finditer(body):
            line = body[: match.start()].count("\n") + 1
            hits.append(f"{rel}:{line}: {match.group(1)}")

        if glass_re.search(body) and path.resolve() not in {p.resolve() for p in GLASS_ALLOW}:
            for match in glass_re.finditer(body):
                line = body[: match.start()].count("\n") + 1
                glass_hits.append(f"{rel}:{line}: forgeGlassCard")

        # Dead duplicate of forgeContentCard. Do not match ForgeCardHeader.
        if forge_card_re.search(body):
            for match in forge_card_re.finditer(body):
                line = body[: match.start()].count("\n") + 1
                hits.append(f"{rel}:{line}: forgeCard(")

        for match in leftover_ternary_re.finditer(body):
            line = body[: match.start()].count("\n") + 1
            leftover_hits.append(f"{rel}:{line}: {match.group(0).strip()}")

    if hits:
        status = 1
        print("✗ Deleted legacy UI identifiers came back:")
        for hit in hits:
            print(f"    {hit}")
        print(
            "  Use forgeContentCard + ForgeCardHeader + ForgePageHeader / "
            "ForgeScreenStack. Do not resurrect HUD chrome, AriaOrb, "
            "HomeAuroraBackground, or a second card API."
        )
    else:
        print("✓ No deleted HUD / pre-rewrite UI identifiers in product code")

    if glass_hits:
        status = 1
        print("✗ forgeGlassCard used outside the one card primitive:")
        for hit in glass_hits:
            print(f"    {hit}")
        print("  Screens take forgeContentCard. Only ForgeChrome and View+ForgeCardShadow may name forgeGlassCard.")
    else:
        print("✓ forgeGlassCard stays inside the one card primitive")

    if leftover_hits:
        status = 1
        print("✗ Leftover forgePlate ternary on forgeContentCard (does not compile):")
        for hit in leftover_hits:
            print(f"    {hit}")
        print("  Use `.forgeContentCard()` only. Do not keep ` : color)` from the old plate API.")
    else:
        print("✓ No leftover forgePlate ternary on forgeContentCard")

    for allowed in GLASS_ALLOW:
        if not allowed.is_file():
            status = 1
            print(f"✗ Expected card primitive file missing: {allowed.relative_to(ROOT)}")

    return status


if __name__ == "__main__":
    sys.exit(main())
