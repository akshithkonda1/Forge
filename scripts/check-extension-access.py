#!/usr/bin/env python3
"""File-scoped access across a type split into extension files.

When a class is split into `Type.swift` plus `Type+Concern.swift`, Swift's
`private` stops meaning "this type" and starts meaning "this file". Two failures
follow, and neither is visible in a diff:

  * a `private` member read from a sibling file — does not resolve at all;
  * a `private(set)` property *written* from a sibling file — reads fine, and
    fails only on assignment, so it survives a casual look at the code.

Both cost a six-minute macOS CI round trip to discover. This decides them here,
per property, and deliberately does not complain about a `private(set)` that
siblings only read: keeping the setter private is the point of writing it.

Exit 1 on any finding.
"""
from __future__ import annotations

import collections
import glob
import os
import re
import sys

MUTATORS = ('append', 'insert', 'remove', 'removeAll', 'removeFirst', 'removeLast',
            'sort', 'popLast', 'updateValue', 'formUnion', 'merge', 'reserveCapacity')

DECL = re.compile(r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*'
                  r'((?:(?:public|internal|fileprivate|private|open)(?:\(set\))?\s+|'
                  r'static\s+|class\s+|final\s+|lazy\s+|weak\s+|unowned\s+|'
                  r'nonisolated\s+|mutating\s+|override\s+)*)'
                  r'(func|var|let|subscript)\s+(\w+)')

SKIP_DIRS = {'.git', 'node_modules', '.build', 'DerivedData', 'Pods'}


def declares_local(code: str, name: str) -> bool:
    """`var settings = …` inside a method is not the property of the same name."""
    return re.search(rf'\b(?:var|let)\s+{re.escape(name)}\b', code) is not None


def uses(name: str, text: str, mutating_only: bool) -> tuple[int, str] | None:
    write = [rf'(?<![.\w]){re.escape(name)}\s*(?:\??\.\w+)*\s*=(?!=)',
             rf'(?<![.\w]){re.escape(name)}\s*[-+*/]?=(?!=)',
             rf'(?<![.\w]){re.escape(name)}\s*\.\s*(?:{"|".join(MUTATORS)})\b',
             rf'(?<![.\w]){re.escape(name)}\s*\[[^\]]*\]\s*=(?!=)',
             rf'&{re.escape(name)}\b']
    patterns = write if mutating_only else [rf'(?<![.\w]){re.escape(name)}\b']
    for n, line in enumerate(text.split('\n'), 1):
        code = re.sub(r'//.*|"(?:[^"\\]|\\.)*"', '', line)
        if declares_local(code, name):
            continue
        if any(re.search(p, code) for p in patterns):
            return n, line.strip()[:88]
    return None


def members_at_type_scope(text: str):
    """Declarations directly inside the type, found by brace depth."""
    depth = 0
    for n, line in enumerate(text.split('\n'), 1):
        code = re.sub(r'//.*|"(?:[^"\\]|\\.)*"', '', line)
        if depth == 1:
            m = DECL.match(line)
            if m:
                yield n, m.group(1), m.group(3)
        depth += (code.count('{') - code.count('}')
                  + code.count('(') - code.count(')')
                  + code.count('[') - code.count(']'))


def check(root: str) -> list[str]:
    groups: dict[str, list[str]] = collections.defaultdict(list)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith('.swift') or '+' not in fn:
                continue
            groups[fn.split('+')[0]].append(os.path.join(dirpath, fn))
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            stem = fn[:-6]
            if fn.endswith('.swift') and stem in groups:
                groups[stem].insert(0, os.path.join(dirpath, fn))

    findings = []
    for stem, files in sorted(groups.items()):
        owners = [f for f in files if '+' not in os.path.basename(f)]
        if not owners:
            continue          # extensions of a type declared elsewhere
        owner = owners[0]
        siblings = [f for f in files if f != owner]
        texts = {f: open(f, encoding='utf-8').read() for f in siblings}
        for line_no, mods, name in members_at_type_scope(
                open(owner, encoding='utf-8').read()):
            priv = re.search(r'\b(private|fileprivate)(\(set\))?\s', mods)
            if not priv or 'static' in mods:
                continue
            setter_only = bool(priv.group(2))
            for f, text in texts.items():
                hit = uses(name, text, mutating_only=setter_only)
                if hit:
                    what = ("has a private setter but is assigned"
                            if setter_only else "is private but is used")
                    findings.append(
                        f"{owner}:{line_no}: {name} {what} in "
                        f"{os.path.basename(f)}:{hit[0]}  ({hit[1]})")
                    break
    return findings


def main() -> int:
    findings = check(sys.argv[1] if len(sys.argv) > 1 else '.')
    if findings:
        print("File-scoped access across an extension split:\n")
        for f in findings:
            print(f"  {f}")
        print(f"\n{len(findings)} problem(s). `private` means 'this file', so a type "
              "split across\nfiles cannot keep its parts private from each other.")
        return 1
    print("check-extension-access: no file-scoped access crosses an extension split")
    return 0


if __name__ == '__main__':
    sys.exit(main())
