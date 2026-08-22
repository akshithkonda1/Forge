#!/usr/bin/env python3
"""Structural checks for hand-edited Xcode project files.

`project.pbxproj` is an old-style plist that nothing on a Linux runner can parse,
so a broken edit normally surfaces as a macOS build failure ten minutes later —
or, worse, as a file that silently never gets compiled. Every failure mode below
has actually happened in this repo:

  * a `PBXFileReference` added but never put in a `PBXSourcesBuildPhase`, so the
    file exists, imports cleanly in the editor, and is simply not built;
  * a `PBXBuildFile` pointing at a `fileRef` that no longer exists;
  * a target listed in `PBXProject.targets` whose product reference was never
    added to the Products group.

These are all decidable from the text alone. This script decides them, on Linux,
in under a second, so a bad edit fails at commit time instead of in CI.

It works mostly on the ID graph, which is usually the part that breaks, plus one
lexical rule — because the ID graph is not the only part that breaks. A file
called `AppStore+Profile.swift` was registered as `path = AppStore+Profile.swift;`
and `+` is not a legal character in an unquoted old-style plist string, so Xcode
reported "missing semicolon in dictionary on line 420" and refused to open the
project at all. Every ID was correct. Exit 1 on any finding.
"""

from __future__ import annotations

import os
import re
import sys
from collections import defaultdict

ID = r"[0-9A-Za-z_]{6,32}"

# Objects that mean "this file gets compiled/copied into some target".
MEMBERSHIP_ISA = {"PBXBuildFile"}

# File types we expect to be a member of at least one target. Headers, plists,
# entitlements and markdown are referenced by build settings or by nothing at
# all, so absence of membership is normal for them.
SOURCE_SUFFIXES = (".swift", ".m", ".mm", ".c", ".cpp", ".metal")


OBJECT_START = re.compile(rf"^\t\t({ID})\s*(?:/\*.*?\*/)?\s*=\s*\{{\s*$")
OBJECT_INLINE = re.compile(rf"^\t\t({ID})\s*(?:/\*.*?\*/)?\s*=\s*\{{(.*)\}};\s*$")


def parse_objects(text: str) -> dict[str, str]:
    """Map object ID -> raw body. Later definitions win, matching Xcode.

    Scanned line by line with brace counting rather than one big regex. A regex
    with an optional `/* ... */` group backtracks across newlines and will
    happily match one object's ID against a later object's brace, swallowing
    everything between — which looks exactly like a hundred missing objects.
    """
    objects: dict[str, str] = {}
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        inline = OBJECT_INLINE.match(line)
        if inline:
            objects[inline.group(1)] = inline.group(2)
            i += 1
            continue
        start = OBJECT_START.match(line)
        if start:
            depth = 1
            body: list[str] = []
            i += 1
            while i < len(lines) and depth > 0:
                depth += lines[i].count("{") - lines[i].count("}")
                if depth > 0:
                    body.append(lines[i])
                i += 1
            objects[start.group(1)] = "\n".join(body)
            continue
        i += 1
    return objects


def isa_of(body: str) -> str:
    m = re.search(r"\bisa\s*=\s*(\w+)\s*;", body)
    return m.group(1) if m else ""


def referenced_ids(body: str) -> set[str]:
    """IDs this object points at, ignoring the ones inside /* comments */."""
    stripped = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    out = set()
    for m in re.finditer(rf"\b({ID})\b", stripped):
        tok = m.group(1)
        # Object IDs are hex-ish and long; build settings values are words.
        if len(tok) >= 6 and re.fullmatch(r"[0-9A-F]{6,32}|[0-9A-Za-z]*\d[0-9A-Za-z]{5,}", tok):
            out.add(tok)
    return out


def check(path: str) -> list[str]:
    text = open(path, encoding="utf-8").read()
    objects = parse_objects(text)
    findings: list[str] = []

    by_isa: dict[str, list[str]] = defaultdict(list)
    for oid, body in objects.items():
        by_isa[isa_of(body)].append(oid)

    if not by_isa.get("PBXProject"):
        return [f"{path}: no PBXProject object found — file is not a project.pbxproj?"]

    # 1. Dangling references. Every ID an object names must be an object we have.
    #    Restricted to the structural keys, because buildSettings values can look
    #    like IDs (DEVELOPMENT_TEAM, for one) without being any.
    structural = re.compile(
        rf"\b(?:fileRef|target|targetProxy|containerPortal|productReference|"
        rf"buildConfigurationList|mainGroup|productRefGroup|remoteGlobalIDString|"
        rf"rootObject)\s*=\s*({ID})"
    )
    for oid, body in objects.items():
        for m in structural.finditer(body):
            if m.group(1) not in objects:
                findings.append(
                    f"{path}: {oid} ({isa_of(body)}) references missing object {m.group(1)}"
                )

    # List-valued members: children, files, buildPhases, dependencies, targets.
    list_block = re.compile(
        r"\b(children|files|buildPhases|dependencies|targets|"
        r"buildConfigurations|packageProductDependencies)\s*=\s*\((.*?)\);",
        re.S,
    )
    for oid, body in objects.items():
        for m in list_block.finditer(body):
            for item in re.finditer(rf"^\s*({ID})\s*(?:/\*.*?\*/)?\s*,", m.group(2), re.M):
                if item.group(1) not in objects:
                    findings.append(
                        f"{path}: {oid} ({isa_of(body)}) lists missing object "
                        f"{item.group(1)} under `{m.group(1)}`"
                    )

    # 2. Source files that are in the project but in no target.
    #    This is the silent one: the file compiles in the editor and never ships.
    built_refs = set()
    for oid in by_isa.get("PBXBuildFile", []):
        m = re.search(rf"fileRef\s*=\s*({ID})", objects[oid])
        if m:
            built_refs.add(m.group(1))

    for oid in by_isa.get("PBXFileReference", []):
        body = objects[oid]
        pm = re.search(r"\bpath\s*=\s*\"?([^\";]+)\"?\s*;", body)
        if not pm:
            continue
        rel = pm.group(1)
        if not rel.endswith(SOURCE_SUFFIXES):
            continue
        if oid not in built_refs:
            findings.append(
                f"{path}: {rel} has a file reference but is in no target "
                f"(orphaned PBXFileReference {oid}) — it will never be compiled"
            )

    # 3. Every native target's product must be in some group, or it does not
    #    show up under Products and the scheme cannot resolve it.
    grouped = set()
    for oid in by_isa.get("PBXGroup", []):
        grouped |= {
            m.group(1)
            for m in re.finditer(rf"^\s*({ID})\s*(?:/\*.*?\*/)?\s*,", objects[oid], re.M)
        }
    for oid in by_isa.get("PBXNativeTarget", []):
        m = re.search(rf"productReference\s*=\s*({ID})", objects[oid])
        name = re.search(r"\bname\s*=\s*\"?([^\";]+)\"?\s*;", objects[oid])
        label = name.group(1) if name else oid
        if m and m.group(1) not in grouped:
            findings.append(
                f"{path}: target {label} product {m.group(1)} is in no group — "
                f"add it to the Products group"
            )

    # 4. Targets must be reachable from the project, or xcodebuild -list omits
    #    them and they are never built by anything.
    proj_body = objects[by_isa["PBXProject"][0]]
    tm = re.search(r"\btargets\s*=\s*\((.*?)\);", proj_body, re.S)
    listed = (
        {m.group(1) for m in re.finditer(rf"^\s*({ID})\s*(?:/\*.*?\*/)?\s*,", tm.group(1), re.M)}
        if tm
        else set()
    )
    for oid in by_isa.get("PBXNativeTarget", []):
        if oid not in listed:
            name = re.search(r"\bname\s*=\s*\"?([^\";]+)\"?\s*;", objects[oid])
            findings.append(
                f"{path}: target {name.group(1) if name else oid} is defined but not "
                f"listed in PBXProject.targets"
            )

    # 5. Files referenced on disk. A path that does not exist builds until the
    #    moment it does not.
    #    `path` is relative to the enclosing group, which this does not resolve,
    #    so the test is a basename search across the repo: enough to catch a file
    #    that is simply not there, without re-implementing group nesting.
    for oid in by_isa.get("PBXFileReference", []):
        body = objects[oid]
        if "BUILT_PRODUCTS_DIR" in body or "SDKROOT" in body or "DEVELOPER_DIR" in body:
            continue
        pm = re.search(r"\bpath\s*=\s*\"?([^\";]+)\"?\s*;", body)
        if not pm or oid not in built_refs:
            continue
        rel = pm.group(1)
        if os.path.isabs(rel):
            continue
        if os.path.basename(rel) not in _repo_entries():
            findings.append(f"{path}: {rel} is compiled by a target but does not exist on disk")

    findings += unquoted_value_findings(path, text)
    findings += duplicate_object_findings(path, text)
    return findings


# The characters Xcode leaves unquoted in a value. It quotes anything else —
# `"Info-Add.plist"` in this very project — and a value that needs quoting and
# does not have it stops the parse dead at that line.
BARE_STRING = re.compile(r"[A-Za-z0-9_./]+")
ASSIGNMENT = re.compile(r"^\s*[\w.\[\]]+ = (.+);\s*$")
TRAILING_COMMENT = re.compile(r"/\*.*?\*/")


def unquoted_value_findings(path: str, text: str) -> list[str]:
    """Values that would fail the old-style plist lexer."""
    findings = []
    for n, line in enumerate(text.split("\n"), 1):
        # Skip the inline dictionary lines; their inner values are checked by
        # the same rule when split on ';'.
        for chunk in line.split(";"):
            m = ASSIGNMENT.match(chunk + ";")
            if not m:
                continue
            value = TRAILING_COMMENT.sub("", m.group(1)).strip()
            if not value or value.startswith(("\"", "{", "(")):
                continue
            if not BARE_STRING.fullmatch(value):
                findings.append(
                    f"{path}:{n}: value {value!r} needs quoting — "
                    f"Xcode cannot parse it and will call the project damaged")
    return findings


OBJECT_DEF = re.compile(rf"^\t\t({ID}) /\* (.*?) \*/ = \{{isa = (\w+);")


def duplicate_object_findings(path: str, text: str) -> list[str]:
    """One id, two definitions.

    An old-style plist dictionary with a repeated key keeps one of them and
    silently discards the other, so two definitions of the same object are
    harmless right up until they stop being identical — at which point which one
    survives is not something the file tells you. This project carried 24 such
    pairs, all byte-identical, from some earlier edit that re-inserted a block
    that already existed.
    """
    seen: dict[str, tuple[int, str]] = {}
    findings = []
    for n, line in enumerate(text.split("\n"), 1):
        m = OBJECT_DEF.match(line)
        if not m:
            continue
        oid = m.group(1)
        if oid in seen:
            first_line, first_text = seen[oid]
            same = "identical" if first_text == line else "DIFFERENT content"
            findings.append(
                f"{path}:{n}: {oid} ({m.group(2)}) is already defined at line "
                f"{first_line} with {same} — one definition is silently discarded")
        else:
            seen[oid] = (n, line)
    return findings


_ENTRIES: set[str] | None = None

# Walks that include worktrees, node_modules, or a leftover nested checkout
# hang the job for minutes and look like a CI timeout. Skip them everywhere.
SKIP_DIRS = {
    ".git",
    "build",
    "DerivedData",
    "node_modules",
    ".next",
    ".claude",
    "__pycache__",
    ".venv",
    "venv",
    ".swiftpm",
    "xcuserdata",
    "dist",
    "coverage",
    ".turbo",
    ".pnpm-store",
}


def _prune(dirpath: str, dirnames: list[str]) -> None:
    keep: list[str] = []
    for name in dirnames:
        if name in SKIP_DIRS or name.endswith(".noindex"):
            continue
        child = os.path.join(dirpath, name)
        # Nested leftover clones (this repo has historically grown a Forge/Forge).
        if os.path.isdir(os.path.join(child, ".git")):
            continue
        keep.append(name)
    dirnames[:] = keep


def _repo_entries() -> set[str]:
    """Every file and directory name in the repo, by basename.

    Directories count: `Assets.xcassets` is a bundle, so a files-only walk
    reports the whole asset catalog as missing.
    """
    global _ENTRIES
    if _ENTRIES is None:
        _ENTRIES = set()
        for dirpath, dirnames, filenames in os.walk("."):
            _prune(dirpath, dirnames)
            _ENTRIES.update(filenames)
            _ENTRIES.update(dirnames)
    return _ENTRIES


def _discover_projects() -> list[str]:
    found: list[str] = []
    for dirpath, dirnames, filenames in os.walk("."):
        _prune(dirpath, dirnames)
        if "project.pbxproj" in filenames:
            found.append(os.path.join(dirpath, "project.pbxproj"))
    return found


def main(argv: list[str]) -> int:
    paths = argv[1:] or _discover_projects()
    if not paths:
        print("check-pbxproj: no project.pbxproj found")
        return 0

    findings: list[str] = []
    for p in paths:
        findings += check(p)

    if findings:
        print("Xcode project structure problems:\n")
        for f in findings:
            print(f"  {f}")
        print(f"\n{len(findings)} problem(s). These break the build on macOS or, worse, ship a")
        print("file that is silently never compiled.")
        return 1

    print(f"check-pbxproj: {len(paths)} project file(s) OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
