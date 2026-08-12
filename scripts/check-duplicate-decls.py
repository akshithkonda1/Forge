#!/usr/bin/env python3
"""Catch a Swift function declared twice in the same type.

This repo keeps producing duplicates, in a new shape each time: duplicate
*files* (111 of them, then 44 more), duplicate *pbxproj objects*, and then a
duplicate *declaration* — PR #120 pasted a byte-identical copy of
`enableForBiologicalSexIfNeeded` into `MenstrualHealthStore.swift`, which broke
`main` for every branch until a PR build happened to surface it.

The compiler catches it, but only on macOS, several minutes into a build, and
only for whoever runs CI next. This catches it on Linux in about a second.

Scope is deliberately narrow, because a noisy gate gets ignored and is worse
than no gate:

  * `func` only. Local `let`/`var` inside method bodies are scoped to the
    method and legitimately repeat constantly — including them produced 130
    findings on a healthy tree, none of them real.
  * Type-body depth only, so a nested helper inside a method is not compared
    against a method.
  * Full signatures, accumulated across line breaks. Overloads differ in their
    parameter lists, and comparing only the first line reported four distinct
    `application(_:...)` delegate methods as one repeated declaration.

Exit 1 on any finding.
"""

from __future__ import annotations

import os
import re
import sys
from collections import defaultdict

FUNC = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
                  r"(?:public|internal|private|fileprivate|open)?\s*"
                  r"(?:static\s+|class\s+|final\s+|override\s+|mutating\s+|"
                  r"nonisolated\s+|convenience\s+|required\s+)*"
                  r"func\s+[A-Za-z_]\w*")

SCOPE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
                   r"(?:public|internal|private|fileprivate|open)?\s*"
                   r"(?:final\s+)?(?:class|struct|enum|extension|protocol|actor)\s+"
                   r"([A-Za-z_][\w.]*)")


def strip_comments(lines: list[str]) -> list[str]:
    out: list[str] = []
    in_block = False
    for raw in lines:
        line = raw
        if in_block:
            if "*/" in line:
                line = line.split("*/", 1)[1]
                in_block = False
            else:
                out.append("")
                continue
        if "/*" in line:
            before, _, after = line.partition("/*")
            if "*/" in after:
                line = before + after.split("*/", 1)[1]
            else:
                line, in_block = before, True
        out.append(re.sub(r"//.*$", "", line))
    return out


def scan(path: str) -> list[str]:
    try:
        raw_lines = open(path, encoding="utf-8").read().split("\n")
    except (UnicodeDecodeError, OSError):
        return []

    lines = strip_comments(raw_lines)
    seen: dict[tuple[str, str], list[int]] = defaultdict(list)
    scope_stack: list[tuple[str, int]] = []
    depth = 0
    index = 0

    while index < len(lines):
        line = lines[index]
        if not line.strip():
            index += 1
            continue

        scope_match = SCOPE.match(line)
        enclosing = scope_stack[-1][0] if scope_stack else "<file>"
        body_depth = scope_stack[-1][1] + 1 if scope_stack else 0

        if FUNC.match(line) and not scope_match and depth == body_depth:
            # Accumulate until the parameter list closes and the body opens, so
            # a signature wrapped across lines is compared whole.
            parts = [line.strip()]
            opens = line.count("(") - line.count(")")
            cursor = index
            while (opens > 0 or "{" not in lines[cursor]) and cursor + 1 < len(lines):
                cursor += 1
                parts.append(lines[cursor].strip())
                opens += lines[cursor].count("(") - lines[cursor].count(")")
            signature = re.sub(r"\s+", " ", " ".join(parts)).split("{", 1)[0].strip()
            seen[(enclosing, signature)].append(index + 1)

        opened = line.count("{")
        closed = line.count("}")
        if scope_match and opened:
            scope_stack.append((scope_match.group(1), depth))
        depth += opened - closed
        while scope_stack and depth <= scope_stack[-1][1]:
            scope_stack.pop()
        index += 1

    findings = []
    for (enclosing, signature) in sorted(seen, key=lambda k: seen[k][0]):
        numbers = seen[(enclosing, signature)]
        if len(numbers) > 1:
            where = ", ".join(str(n) for n in numbers)
            short = signature if len(signature) <= 90 else signature[:87] + "..."
            findings.append(f"{path}:{numbers[1]}: '{short}' declared "
                            f"{len(numbers)} times in {enclosing} (lines {where})")
    return findings


def main(argv: list[str]) -> int:
    roots = argv[1:] or ["."]
    findings: list[str] = []
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames
                           if d not in {".git", "build", "DerivedData", ".build", "node_modules"}]
            for name in sorted(filenames):
                if name.endswith(".swift"):
                    findings += scan(os.path.join(dirpath, name))

    if findings:
        print("Duplicate Swift function declarations:\n")
        for f in findings:
            print(f"  {f}")
        print(f"\n{len(findings)} duplicate declaration(s). Each is an 'invalid redeclaration'")
        print("error on macOS, which blocks the build for every branch until it is removed.")
        return 1

    print("check-duplicate-decls: no duplicate function declarations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
