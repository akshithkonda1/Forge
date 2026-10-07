#!/usr/bin/env python3
"""Classify an xcodebuild test log. Fail-closed. Substring-safe banners.

Xcode 16 / ``test`` prints ``** TEST SUCCEEDED **``.
Xcode 27 ``test-without-building`` prints ``** TEST EXECUTE SUCCEEDED **``.
A naive ``TEST SUCCEEDED`` grep misses the latter — that phrase is not a
substring of ``TEST EXECUTE SUCCEEDED`` — and can also match prose. This
helper matches the full ``** … **`` banner only.

Failure banners, ``failed (``, ``XCTAssert``, and ``test runner crashed``
win over a success banner so a real red cannot go green.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SUCCESS_BANNER = re.compile(r"^\s*\*\* TEST (?:EXECUTE )?SUCCEEDED \*\*\s*$")
FAILURE_BANNER = re.compile(r"^\s*\*\* TEST (?:EXECUTE |BUILD )?FAILED \*\*\s*$")
ASSERTION = re.compile(r"failed \(|XCTAssert|test runner crashed")


def classify(text: str) -> str:
    failed = False
    succeeded = False
    for line in text.splitlines():
        if FAILURE_BANNER.search(line) or ASSERTION.search(line):
            failed = True
        elif SUCCESS_BANNER.search(line):
            succeeded = True
    if failed:
        return "failed"
    if succeeded:
        return "success"
    return "incomplete"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", help="xcodebuild test log path")
    args = parser.parse_args(argv)
    path = Path(args.log)
    if not path.is_file():
        print("incomplete")
        return 0
    print(classify(path.read_text(encoding="utf-8", errors="replace")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
