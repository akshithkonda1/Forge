#!/usr/bin/env python3
"""Fail if ForgeSwift sources enumerate the address book.

The people screen is picker-only: `CNContactPickerViewController` returns the
contacts the user taps, and the system picker needs no Contacts permission.
`CNContactFetchRequest` / `enumerateContacts` would read the whole book and
require `NSContactsUsageDescription`, which this app no longer declares.

Exit 1 on any finding.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = "ForgeSwift"
FORBIDDEN = re.compile(r"\bCNContactFetchRequest\b|\benumerateContacts\b")
SKIP_DIRS = {".git", "build", "DerivedData", ".build", "node_modules"}


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def skip_dir(name: str) -> bool:
    return name in SKIP_DIRS or name == "Tests" or name.endswith("Tests")


def swift_sources(root: str) -> list[str]:
    found: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not skip_dir(d)]
        found += [
            os.path.join(dirpath, f)
            for f in filenames
            if f.endswith(".swift") and not f.endswith("Tests.swift")
        ]
    return sorted(found)


def main() -> int:
    if not os.path.isdir(ROOT):
        print(f"check-contacts-picker-only: {ROOT} not found", file=sys.stderr)
        return 1

    findings: list[str] = []
    scanned = 0
    for path in swift_sources(ROOT):
        try:
            body = strip_comments(open(path, encoding="utf-8").read())
        except (UnicodeDecodeError, OSError):
            continue
        scanned += 1
        if FORBIDDEN.search(body):
            findings.append(path)

    if findings:
        print("Address-book enumeration is forbidden (picker-only Contacts):\n")
        for path in findings:
            print(f"  {path}")
        print(f"\n{len(findings)} file(s) name CNContactFetchRequest or enumerateContacts.")
        return 1

    print(
        "check-contacts-picker-only: no address-book enumeration "
        f"({scanned} Swift source(s) scanned)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
