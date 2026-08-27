#!/usr/bin/env python3
"""LocalTestingOrchestrator must stay network-free, and AriaWebResearch must
stay confined to it.

LocalTestingOrchestrator's own doc comment promises it never calls Forge's
backend — "no URLSession, no baseURL... checkable by grep" — because a
tester needs to trust that a local-testing session cannot quietly touch
production. AriaWebResearch is the one intentional exception: a curated,
keyless fetch to a handful of general reference URLs, gated to local
testing and isolated in its own file specifically so that promise stays
literally true rather than becoming a comment the code no longer matches.

Both halves of that design are silently violable by a future edit that
looks harmless in review: URLSession creeping into LocalTestingOrchestrator
directly, or AriaWebResearch getting called from somewhere outside the one
place that's actually gated behind AriaOperatingMode.isLocalTesting (e.g. a
live-backend code path, or a UI file reaching for it directly). Neither
would fail to compile and neither would fail an existing test. This is the
same failure shape #155/#156's widget bundle collision was — a real
regression with every other gate green — so it gets the same kind of gate.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
)

SERVICES_DIR = ROOT / "ForgeSwift" / "ForgeSwift" / "Services"
ORCHESTRATOR = SERVICES_DIR / "LocalTestingOrchestrator.swift"
WEB_RESEARCH = SERVICES_DIR / "AriaWebResearch.swift"

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT = re.compile(r"//[^\n]*")

NETWORK_TERMS = re.compile(r"\bURLSession\b|\bURLRequest\b|\bAriaService\.shared\b")
WEB_RESEARCH_REF = re.compile(r"\bAriaWebResearch\b")


def strip_comments(text: str) -> str:
    """Prose must not count as a reference — a doc comment that mentions
    AriaWebResearch by name (as this file's own does) would otherwise make
    the second check vacuous."""
    return LINE_COMMENT.sub("", BLOCK_COMMENT.sub("", text))


def main() -> int:
    if not ORCHESTRATOR.is_file():
        print(f"✗ {ORCHESTRATOR.relative_to(ROOT)} not found — this check has nothing to check.")
        return 1
    if not WEB_RESEARCH.is_file():
        print(f"✗ {WEB_RESEARCH.relative_to(ROOT)} not found — this check has nothing to check.")
        return 1

    status = 0

    orchestrator_body = strip_comments(ORCHESTRATOR.read_text(encoding="utf-8"))
    hits = NETWORK_TERMS.findall(orchestrator_body)
    if hits:
        status = 1
        print(f"✗ {ORCHESTRATOR.relative_to(ROOT)} references {sorted(set(hits))} — "
              f"LocalTestingOrchestrator is supposed to hold no network transport at all. "
              f"If this turn genuinely needs the network, route it through AriaWebResearch "
              f"(local-testing-gated, its own file) rather than adding it here directly.")
    else:
        print(f"✓ {ORCHESTRATOR.relative_to(ROOT)}: no network transport")

    swift_files = sorted(ROOT.joinpath("ForgeSwift").rglob("*.swift"))
    offenders: dict[Path, int] = {}
    for path in swift_files:
        if path in (ORCHESTRATOR, WEB_RESEARCH):
            continue
        body = strip_comments(path.read_text(encoding="utf-8"))
        count = len(WEB_RESEARCH_REF.findall(body))
        if count:
            offenders[path] = count

    if offenders:
        status = 1
        for path, count in sorted(offenders.items()):
            print(f"✗ {path.relative_to(ROOT)}: references AriaWebResearch ({count}x) — "
                  f"it should only ever be called from LocalTestingOrchestrator.swift, "
                  f"the one call site that's actually behind "
                  f"AriaOperatingMode.current.isLocalTesting. A call from anywhere else "
                  f"risks turning a local-testing-only web fetch into a live-backend one.")
    else:
        print(f"✓ AriaWebResearch is referenced only from {ORCHESTRATOR.relative_to(ROOT)} "
              f"and its own file")

    return status


if __name__ == "__main__":
    sys.exit(main())
