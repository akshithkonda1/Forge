#!/usr/bin/env python3
"""Fail when a SwiftPM target's explicit `sources:` list drifts from the disk.

ForgeCore's Package.swift lists every file by name instead of letting SwiftPM
walk the directory. That is deliberate — the comment on both lists says so:

    // Explicit sources only — never pick up Finder " 2.swift" duplicates.

The cost of that choice is that the list is now a second place to remember, and
forgetting it fails silently in the direction that matters. A source file added
and not listed is never compiled into the module; a *test* file added and not
listed is never run, and `swift test` reports success for the tests that remain.
Nothing goes red. The only way to notice is to read the directory and the
manifest side by side, which nobody does.

That nearly happened on the commit that added SessionClockTests,
CompanionConfigTests and WorkoutCoachingTests — a change whose entire purpose
was to end "these managers have no tests".

The reverse direction is checked too. A listed file that does not exist fails
the SwiftPM build already, but failing here is faster and says which manifest
entry is wrong instead of surfacing as a build error.

Objection worth answering: doesn't flagging unlisted files defeat the point of
the explicit list, which exists to ignore Finder duplicates? No — those are
rejected repo-wide by scripts/check-conflict-copies.sh, which fails on
` 2.swift`, ` (1).swift`, ` copy.swift` and the rest wherever they appear. A
conflict copy cannot reach a state where this gate is the thing complaining
about it.

Targets with no explicit `sources:` are skipped: SwiftPM walks the directory for
those, so there is no list to drift.

Exit 1 on any drift.
"""

from __future__ import annotations

import os
import re
import sys

MANIFESTS = ["ForgeSwift/ForgeCore/Package.swift"]

# Kept in step with check-conflict-copies.sh. A conflict copy is that gate's to
# report; naming it twice would send someone to fix the wrong thing.
CONFLICT_COPY = re.compile(
    r"(^|/)[^/]+( [0-9]+| \([0-9]+\)| \(.*[Cc]onflict[^)]*\)|[ -]+[Cc]opy( [0-9]+)?)(/|\.[^./]+|$)"
)


class Target:
    def __init__(self, kind: str, name: str, path: str | None,
                 sources: list[str] | None, exclude: list[str]):
        self.kind = kind
        self.name = name
        self.path = path
        self.sources = sources
        self.exclude = exclude

    def __repr__(self) -> str:
        return f"{self.kind} {self.name}"


def _blocks(manifest: str) -> list[tuple[str, str]]:
    """(kind, body) for each .target(...) / .testTarget(...), paren-balanced.

    A regex cannot find the end of these: the bodies contain nested arrays,
    parentheses and commas. Scanning with a depth counter can, as long as it
    skips string literals — a path could contain a bracket.
    """
    found: list[tuple[str, str]] = []
    for match in re.finditer(r"\.(testTarget|target)\s*\(", manifest):
        kind = match.group(1)
        i = match.end()
        depth = 1
        in_string = False
        while i < len(manifest) and depth > 0:
            char = manifest[i]
            if in_string:
                if char == "\\":
                    i += 2
                    continue
                if char == '"':
                    in_string = False
            elif char == '"':
                in_string = True
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    found.append((kind, manifest[match.end():i]))
                    break
            i += 1
    return found


def _scalar(body: str, key: str) -> str | None:
    match = re.search(rf'\b{key}\s*:\s*"([^"]*)"', body)
    return match.group(1) if match else None


def _array(body: str, key: str) -> list[str] | None:
    match = re.search(rf"\b{key}\s*:\s*\[", body)
    if match is None:
        return None
    i = match.end()
    depth = 1
    while i < len(body) and depth > 0:
        if body[i] == "[":
            depth += 1
        elif body[i] == "]":
            depth -= 1
        i += 1
    return re.findall(r'"([^"]*)"', body[match.end():i - 1])


def parse_targets(manifest: str) -> list[Target]:
    targets = []
    for kind, body in _blocks(manifest):
        name = _scalar(body, "name")
        if not name:
            continue
        targets.append(Target(
            kind=kind,
            name=name,
            path=_scalar(body, "path"),
            sources=_array(body, "sources"),
            exclude=_array(body, "exclude") or [],
        ))
    return targets


def swift_files(root: str) -> set[str]:
    found = set()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in {".build", "build", ".git"}]
        for name in filenames:
            if not name.endswith(".swift"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), root)
            if CONFLICT_COPY.search(rel):
                continue  # check-conflict-copies.sh owns these
            found.add(rel.replace(os.sep, "/"))
    return found


def covered_by(entry: str, root: str, on_disk: set[str]) -> set[str]:
    """The files one `sources:` entry accounts for.

    An entry may name a file or a directory; SwiftPM takes every source beneath
    a directory, so `sources: ["Intelligence"]` covers the whole folder.
    """
    if entry in on_disk:
        return {entry}
    if os.path.isdir(os.path.join(root, entry)):
        prefix = entry.rstrip("/") + "/"
        return {f for f in on_disk if f.startswith(prefix)}
    return set()


def main() -> int:
    findings: list[str] = []
    checked = 0
    skipped: list[str] = []

    for manifest_path in MANIFESTS:
        if not os.path.exists(manifest_path):
            print(f"check-package-sources: {manifest_path} not found", file=sys.stderr)
            return 1
        package_dir = os.path.dirname(manifest_path)
        manifest = open(manifest_path, encoding="utf-8").read()

        for target in parse_targets(manifest):
            if target.sources is None:
                skipped.append(f"{target.name} (no explicit sources)")
                continue
            if target.path is None:
                findings.append(
                    f"[{target.name}] lists sources but no path; this gate cannot "
                    "resolve it against the disk."
                )
                continue

            root = os.path.join(package_dir, target.path)
            if not os.path.isdir(root):
                findings.append(f"[{target.name}] path {target.path!r} does not exist.")
                continue

            on_disk = swift_files(root)
            excluded: set[str] = set()
            for entry in target.exclude:
                excluded |= covered_by(entry, root, on_disk) or {entry}
            on_disk -= excluded

            accounted: set[str] = set()
            for entry in target.sources:
                covers = covered_by(entry, root, on_disk)
                if not covers and entry not in excluded:
                    findings.append(
                        f"[{target.name}] {entry!r} is listed in sources but is not "
                        f"on disk under {target.path}/."
                    )
                accounted |= covers

            for missing in sorted(on_disk - accounted):
                noun = "test" if target.kind == "testTarget" else "source"
                consequence = (
                    "it is never run, and swift test still reports success"
                    if target.kind == "testTarget"
                    else "it is never compiled into the module"
                )
                findings.append(
                    f"[{target.name}] {target.path}/{missing} exists but is not listed "
                    f"in sources — as an unlisted {noun}, {consequence}."
                )

            checked += 1

    if findings:
        print("SwiftPM manifests have drifted from the files on disk:\n")
        for finding in findings:
            print(f"  {finding}")
        print(f"\n{len(findings)} problem(s). These lists are explicit on purpose, so")
        print("adding a file means adding it in two places. Nothing else reports this:")
        print("an unlisted test is simply never run.")
        return 1

    detail = f"{checked} target(s) with explicit sources"
    if skipped:
        detail += f"; skipped {', '.join(skipped)}"
    print(f"check-package-sources: every SwiftPM sources list matches the disk ({detail})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
