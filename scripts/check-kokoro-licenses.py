#!/usr/bin/env python3
"""Fail if eSpeak, phonemizer, or other GPL TTS bits land in the iOS mouth.

Kokoro on the phone is Apache/MIT only: mattmireles/kokoro-coreml v2.0 plus
MisakiSwift. FluidAudio's docs still name eSpeak-NG (GPL-3.0). Older
kokoro-ios commits were GPL. This gate reads the project pin and the
resolved package graph (when present) so a later SPM bump cannot quietly
pull eSpeakNGSwift, phonemizer, or FluidAudioTTS into the app.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBXPROJ = ROOT / "ForgeSwift" / "ForgeSwift.xcodeproj" / "project.pbxproj"
CORE = (
    ROOT
    / "ForgeSwift"
    / "ForgeCore"
    / "Sources"
    / "ForgeCore"
    / "Intelligence"
    / "AriaKokoroVoice.swift"
)
ENGINE = ROOT / "ForgeSwift" / "ForgeSwift" / "AriaKokoroEngine.swift"
RESOLVED = [
    ROOT / "ForgeSwift" / "ForgeSwift.xcodeproj" / "project.xcworkspace"
    / "xcshareddata" / "swiftpm" / "Package.resolved",
    ROOT / "ForgeSwift" / "ForgeSwift.xcodeproj" / "project.xcworkspace"
    / "xcshareddata" / "swiftpm" / "configuration" / "Package.resolved",
]

PINNED_REVISION = "e4242c94c0dc5be62258cc3cf15c86c37382c3d5"
PINNED_PACKAGE = "https://github.com/mattmireles/kokoro-coreml"

FORBIDDEN_URLS = (
    "espeak-ng",
    "espeaking",
    "eSpeakNGSwift",
    "mlalma/eSpeakNGSwift",
    "bootphon/phonemizer",
    "phonemizer",
    "FluidInference/FluidAudio",
    "mweinbach/kokoro-swift",
)
FORBIDDEN_IMPORTS = (
    "import eSpeak",
    "import eSpeakNG",
    "import eSpeakNGLib",
    "import eSpeakNGSwift",
    "import FluidAudioTTS",
    "import FluidAudio",
    "NSBundleResourceRequest",
)
# Names that must not appear as a linked product or remote package.
FORBIDDEN_PRODUCTS = (
    "eSpeakNGLib",
    "eSpeakNGSwift",
    "FluidAudioTTS",
    "FluidAudioWithTTS",
    "FluidAudio",
)

GPL_LICENSE_LINE = re.compile(r"\bGNU (AFFERO |LESSER )?GENERAL PUBLIC LICENSE\b|\bGPL-3\.0\b", re.I)
ESPEAK_TOKEN = re.compile(r"espeak-ng|eSpeakNG|phonemizer", re.I)


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _scan_sources() -> list[str]:
    findings: list[str] = []
    for dirpath, dirnames, filenames in os.walk(ROOT / "ForgeSwift"):
        if any(part in {".build", "DerivedData", ".swiftpm", "SourcePackages"} for part in Path(dirpath).parts):
            dirnames[:] = []
            continue
        for name in filenames:
            if not name.endswith(".swift"):
                continue
            path = Path(dirpath) / name
            text = path.read_text(encoding="utf-8", errors="replace")
            rel = path.relative_to(ROOT)
            for needle in FORBIDDEN_IMPORTS:
                if needle in text:
                    findings.append(f"{rel}: forbidden symbol {needle!r}")
    return findings


def _scan_pbxproj(text: str) -> list[str]:
    findings: list[str] = []
    if PINNED_PACKAGE not in text:
        findings.append("project.pbxproj does not reference mattmireles/kokoro-coreml")
    if PINNED_REVISION not in text:
        findings.append(f"project.pbxproj is not pinned to kokoro-coreml {PINNED_REVISION}")
    for needle in FORBIDDEN_URLS + FORBIDDEN_PRODUCTS:
        if needle in text:
            findings.append(f"project.pbxproj references forbidden package {needle!r}")
    if "NSBundleResourceRequest" in text:
        findings.append("project.pbxproj mentions On-Demand Resources")
    # Watch must not link KokoroTTS.
    if re.search(r"ForgeWatch[^\n]*KokoroTTS|KokoroTTS[^\n]*ForgeWatch", text):
        findings.append("KokoroTTS appears to be linked to ForgeWatch")
    return findings


def _scan_resolved(path: Path) -> list[str]:
    if not path.exists():
        return []
    text = _read(path)
    findings: list[str] = []
    for needle in FORBIDDEN_URLS + FORBIDDEN_PRODUCTS:
        if needle.lower() in text.lower() and needle != "phonemizer":
            findings.append(f"{path.relative_to(ROOT)}: forbidden dependency {needle!r}")
    # phonemizer as a package identity, not a comment
    if re.search(r"bootphon|eSpeakNGSwift|espeak-ng\.git|FluidAudio\.git", text, re.I):
        findings.append(f"{path.relative_to(ROOT)}: forbidden TTS/G2P checkout")
    return findings


def _scan_checkouts(root: Path) -> list[str]:
    if not root.exists():
        return []
    findings: list[str] = []
    for checkout in root.rglob("LICENSE*"):
        try:
            text = checkout.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if ESPEAK_TOKEN.search(checkout.as_posix()):
            findings.append(f"{checkout}: path looks like eSpeak/phonemizer")
            continue
        # Only fail GPL licenses in packages we actually resolved for Kokoro,
        # not a random file that mentions GPL in a comment.
        if GPL_LICENSE_LINE.search(text[:1200]) and ESPEAK_TOKEN.search(text):
            findings.append(f"{checkout}: GPL license alongside eSpeak/phonemizer")
    for path in root.rglob("*"):
        name = path.name.lower()
        if "espeak" in name or "phonemizer" in name:
            findings.append(f"{path}: forbidden checkout name")
    return findings


def main() -> int:
    findings: list[str] = []
    core = _read(CORE)
    if "e4242c94c0dc5be62258cc3cf15c86c37382c3d5" not in core:
        findings.append("AriaKokoroVoice.swift is not pinned to kokoro-coreml v2.0")
    if 'g2p = "MisakiSwift"' not in core:
        findings.append("AriaKokoroVoice.swift must name MisakiSwift as G2P")
    if "usesEspeak = false" not in core:
        findings.append("AriaKokoroVoice.swift must keep usesEspeak = false")
    engine = _read(ENGINE)
    for line in engine.splitlines():
        stripped = line.strip()
        if stripped.startswith("import ") and any(
            token in stripped for token in ("eSpeak", "phonemizer", "FluidAudio")
        ):
            findings.append(f"AriaKokoroEngine.swift forbidden import: {stripped}")
        if "github.com/" in stripped.lower() and any(
            token in stripped for token in FORBIDDEN_URLS
        ):
            findings.append(f"AriaKokoroEngine.swift forbidden package: {stripped}")
    if "KokoroTTS" not in engine:
        findings.append("AriaKokoroEngine.swift does not import KokoroTTS")

    findings += _scan_pbxproj(_read(PBXPROJ))
    findings += _scan_sources()
    for resolved in RESOLVED:
        findings += _scan_resolved(resolved)

    extra = os.environ.get("KOKORO_SOURCEPACKAGES")
    if extra:
        findings += _scan_checkouts(Path(extra))
    default_checkouts = ROOT / "ForgeSwift" / "SourcePackages" / "checkouts"
    findings += _scan_checkouts(default_checkouts)

    if findings:
        print("Kokoro license / G2P problems:\n")
        for item in findings:
            print(f"  {item}")
        return 1
    print("check-kokoro-licenses: kokoro-coreml v2.0 pin, MisakiSwift G2P, no eSpeak/GPL")
    return 0


if __name__ == "__main__":
    sys.exit(main())
