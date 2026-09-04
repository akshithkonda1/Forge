#!/usr/bin/env python3
"""Every widget on disk must actually be in its bundle.

A `struct X: Widget` that no `WidgetBundle` names is not a build error and
not a test failure. It compiles, it is registered in the Xcode target, it
looks entirely healthy in the file tree — and it can never appear on a home
screen or a watch face, because WidgetKit only ever sees what the bundle
lists. The feature is simply absent, and nothing says so.

This is not hypothetical. #155 added `HydrationComplication` and registered
it; #156 added `SupportComplication` and registered it; the two edits landed
on the same line of `ForgeWatchWidgetBundle.body`, and the merge kept one.
The file stayed on disk, stayed in the Xcode target, and stayed compiling,
so every gate we had was green while the watch face lost a complication.

Scope is the directory containing the bundle, which is how these extensions
are laid out. Live Activities live outside both bundle directories and are
deliberately not required here.
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

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT = re.compile(r"//[^\n]*")

# `struct Foo: Widget` — but not `: WidgetBundle`, and not `WidgetConfiguration`.
WIDGET_DECL = re.compile(r"\bstruct\s+([A-Za-z_]\w*)\s*:\s*Widget\s*(?:\{|$)", re.M)
BUNDLE_DECL = re.compile(r"\bstruct\s+([A-Za-z_]\w*)\s*:\s*WidgetBundle\b")


def strip_comments(text: str) -> str:
    """Prose must not count as registration, and a doc comment that names
    every widget in the bundle would otherwise make this check vacuous."""
    return LINE_COMMENT.sub("", BLOCK_COMMENT.sub("", text))


def main() -> int:
    bundles = sorted(
        p for p in ROOT.joinpath("ForgeSwift").rglob("*.swift")
        if BUNDLE_DECL.search(strip_comments(p.read_text(encoding="utf-8")))
    )
    if not bundles:
        print("✗ no WidgetBundle found — this check has silently stopped checking anything.")
        return 1

    status = 0
    for bundle_path in bundles:
        scope = bundle_path.parent
        body = strip_comments(bundle_path.read_text(encoding="utf-8"))
        registered = set(re.findall(r"\b([A-Za-z_]\w*)\s*\(\s*\)", body))

        declared: dict[str, Path] = {}
        for swift in sorted(scope.rglob("*.swift")):
            for name in WIDGET_DECL.findall(strip_comments(swift.read_text(encoding="utf-8"))):
                declared[name] = swift

        orphans = sorted(set(declared) - registered)
        rel = bundle_path.relative_to(ROOT)
        if orphans:
            status = 1
            for name in orphans:
                print(f"✗ {declared[name].relative_to(ROOT)}: {name} is a Widget that "
                      f"{rel.name} never lists.")
                print(f"    It compiles and ships, but WidgetKit will never show it. "
                      f"Add {name}() to the bundle, or delete the file.")
        else:
            print(f"✓ {rel}: all {len(declared)} widgets registered")

    return status


if __name__ == "__main__":
    sys.exit(main())
