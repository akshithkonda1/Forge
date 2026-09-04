#!/usr/bin/env python3
"""Check a split against the pre-split file in git: same code, redistributed.

The splitter checks that it dropped nothing on the way out. This checks the
result independently, from the committed original, so a bug in the splitter
cannot vouch for itself. Comparing multisets of stripped lines catches a lost
brace, a duplicated declaration, and a chunk moved twice; the only differences
it should ever print are edits made deliberately.

Usage: verify_split.py <rev:path/to/Original.swift> <new1.swift> [new2.swift ...]
"""
import collections
import re
import subprocess
import sys

IMPORT = re.compile(r'^(?:@[\w.]+\s+)*import\s+\w+')


def substantive(lines):
    return collections.Counter(
        stripped for stripped in (l.strip() for l in lines)
        if stripped and not stripped.startswith('//') and not IMPORT.match(stripped))


def main():
    original = subprocess.run(['git', 'show', sys.argv[1]],
                              capture_output=True, text=True, check=True).stdout.split('\n')
    produced = []
    for path in sys.argv[2:]:
        produced += open(path, encoding='utf-8').read().split('\n')

    before, after = substantive(original), substantive(produced)
    print(f"  {sys.argv[1]}: {sum(before.values())} code lines -> "
          f"{sum(after.values())} across {len(sys.argv) - 2} files")
    ok = True
    for label, diff in (('lost', before - after), ('gained', after - before)):
        if diff:
            ok = False
            print(f"  {label} ({sum(diff.values())}):")
            for line, n in list(diff.items())[:25]:
                print(f"      x{n}  {line[:110]}")
    if ok:
        print("  identical: every line of code accounted for exactly once")
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
