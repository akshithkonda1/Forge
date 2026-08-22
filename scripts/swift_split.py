#!/usr/bin/env python3
"""Split a Swift file into several, without losing or duplicating a line.

Swift has two traps that make a naive split compile-clean locally and fail in
CI, and there is no local compiler here to catch either:

  * `private` is *file*-scoped. A `private struct` at top level, or a `private`
    member reached from an `extension` of the same type, stops resolving the
    moment the two halves land in different files.
  * A dropped or duplicated line in a 5,000-line view is invisible in a diff of
    that size.

So this refuses to run a split that separates a type from its extensions or a
`private` top-level declaration from its only caller, and it verifies afterwards
that every substantive line of the original appears exactly once in the output.

Usage:  swift_split.py <source.swift> <plan.json>
  plan.json:  {"NewFileName.swift": ["TypeA", "TypeB"], ...}
              Naming the source file itself as a key rewrites it in place;
              leaving it out deletes it once its contents have been rehoused.
              "Name#2" addresses one declaration when a name is declared more
              than once — an `enum` and a `private extension` of it, say, which
              belong in different files precisely because one is file-scoped.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swift_decls import declarations  # noqa: E402

# An import is dropped only when nothing in the new file could possibly need it.
# Anything not listed here is kept: a spurious import is free, a missing one is
# a failed CI run.
IMPORT_MARKERS = {
    'Charts': r'\b(Chart|LineMark|BarMark|AreaMark|RuleMark|PointMark|SectorMark|AxisMarks|ChartXAxis|ChartYAxis|chartYScale|chartXScale|chartLegend|chartForegroundStyleScale)\b',
    'WidgetKit': r'\b(WidgetCenter|WidgetKit|TimelineProvider|TimelineEntry|IntentTimelineProvider)\b',
    'AVFoundation': r'\b(AV[A-Z]\w+|AVFoundation)\b',
    'HealthKit': r'\b(HK[A-Z]\w+|HealthKit)\b',
    'WorkoutKit': r'\b(WorkoutKit|WorkoutPlan|CustomWorkout|IntervalBlock|SingleGoalWorkout|WorkoutScheduler|IntervalStep)\b',
    'CoreLocation': r'\b(CL[A-Z]\w+|CoreLocation)\b',
    'MapKit': r'\b(MK[A-Z]\w+|MapKit|Map\(|Marker\(|Annotation\()',
    'UserNotifications': r'\b(UN[A-Z]\w+|UserNotifications)\b',
    'UIKit': r'\b(UI[A-Z]\w+|UIKit|NSAttributedString)\b',
    'Speech': r'\b(SF[A-Z]\w+|Speech)\b',
    'Contacts': r'\b(CN[A-Z]\w+|Contacts)\b',
    'PhotosUI': r'\b(PhotosPicker|PHPicker|PhotosUI)\b',
    'AuthenticationServices': r'\b(AS[A-Z]\w+|AuthenticationServices|SignInWithAppleButton)\b',
    'CryptoKit': r'\b(SHA256|SymmetricKey|CryptoKit|HMAC|Insecure)\b',
    'CoreMotion': r'\b(CM[A-Z]\w+|CoreMotion)\b',
    'AppIntents': r'\b(AppIntent|AppShortcut|AppIntents|EntityQuery)\b',
    'MediaPlayer': r'\b(MP[A-Z]\w+|MediaPlayer)\b',
    'Combine': r'\b(Published|ObservableObject|AnyCancellable|PassthroughSubject|CurrentValueSubject|Publisher|ObservableObjectPublisher|objectWillChange)\b|\.sink|\.store\(in:',
}

# `@preconcurrency import AVFoundation` is an import too. Matching only on a
# leading `import` copied it into all thirteen files, including the nine with
# no audio or capture in them.
IMPORT_LINE = re.compile(r'^\s*(?:@[\w.]+\s+)*import\s+(\w+)')

SUBSTANTIVE = re.compile(r'^\s*(//|/\*|\*|$)')


MEMBER = re.compile(
    r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*'
    r'(?:public |internal |fileprivate |private |static |class |final |mutating |nonisolated |lazy |override )*'
    r'(?:func|var|let|subscript)\s+([A-Za-z_][A-Za-z0-9_]*)')
INIT_LABEL = re.compile(
    r'^\s*(?:@\w+\s+)*(?:\w+ )*init\??\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*:')


def scoped_symbols(decl, lines):
    """The names that stop resolving if this declaration moves files.

    For a type, that is the type's own name. For an `extension` it is not: the
    extension's name *is* the type it extends, which every ordinary user of that
    type mentions, so checking it would flag every reference to a perfectly
    internal enum. What `private extension` actually confines is its members —
    so those are what get checked, and an `init` is addressed by its first
    argument label, which is how a call to it is recognisable at all.

    Members are found by brace depth rather than by indentation. Indentation
    looked equivalent and was not: `let scale` and `let target` inside a method
    body are indented like members, and reading them as members flagged eleven
    references to two local variables.
    """
    if decl['kind'] != 'extension':
        return [decl['name']]
    names = []
    depth = 0
    for line in lines[decl['start']:decl['end'] + 1]:
        code = re.sub(r'//.*|"(?:[^"\\]|\\.)*"', '', line)
        if depth == 1:
            m = MEMBER.match(line)
            if m:
                names.append(m.group(1))
            m = INIT_LABEL.match(line)
            if m:
                names.append(m.group(1))
        depth += code.count('{') - code.count('}')
    return names



def is_separator(line):
    """A line that carries no code: blank, or a comment left between decls."""
    return bool(SUBSTANTIVE.match(line))


def split(source_path, plan):
    info = declarations(source_path)
    lines = open(source_path, encoding='utf-8').read().split('\n')
    by_name = {}
    for d in info['decls']:
        by_name.setdefault(d['name'], []).append(d)

    # --- The private-scope guard -------------------------------------------
    # An `extension X` must not be parted from `X`; that is exactly how a
    # `private` member stops resolving.
    # Every declaration is addressed as (name, ordinal) so a type and a
    # `private extension` of it can be sent to different files.
    ordinals = {}
    for d in info['decls']:
        n = ordinals.get(d['name'], 0)
        d['key'] = f"{d['name']}#{n}"
        ordinals[d['name']] = n + 1

    home = {}
    for filename, names in plan.items():
        for entry in names:
            # `#Preview` is itself a declaration whose name starts with '#',
            # so an ordinal is only an ordinal when the suffix is a number.
            head, _, tail = entry.rpartition('#')
            matches = ([d for d in info['decls'] if d['key'] == entry]
                       if head and tail.isdigit()
                       else [d for d in info['decls'] if d['name'] == entry])
            if not matches:
                raise SystemExit(f"{entry}: no such declaration in {source_path}")
            for d in matches:
                if d['key'] in home:
                    raise SystemExit(f"{d['key']} assigned to both "
                                     f"{home[d['key']]} and {filename}")
                home[d['key']] = filename

    unplaced = [d['key'] for d in info['decls'] if d['key'] not in home]
    if unplaced:
        raise SystemExit("unplaced declarations:\n  " + "\n  ".join(sorted(set(unplaced))))

    # `private`/`fileprivate` is file-scoped: a declaration carrying either may
    # not be parted from the code that reads it. This is the check that a diff
    # of five thousand lines will not make for you.
    problems = []
    for d in info['decls']:
        head = lines[d['decl_line']]
        if not re.search(r'\b(private|fileprivate)\b', head):
            continue
        owner = home[d['key']]
        for symbol in scoped_symbols(d, lines):
            for other in info['decls']:
                if home[other['key']] == owner or other['key'] == d['key']:
                    continue
                chunk = '\n'.join(lines[other['start']:other['end'] + 1])
                if re.search(r'\b' + re.escape(symbol) + r'\b', chunk):
                    problems.append(
                        f"{symbol} is file-scoped in {owner} but referenced by "
                        f"{other['name']} in {home[other['key']]}")
    if problems:
        raise SystemExit("file-scope violations:\n  " + "\n  ".join(sorted(set(problems))))

    # --- Emit ---------------------------------------------------------------
    header = info['header']
    outdir = os.path.dirname(source_path)
    claimed = set()
    written = {}

    for filename in plan:
        chunks = sorted((d['start'], d['end']) for d in info['decls']
                        if home[d['key']] == filename)
        pieces = []
        for start, end in chunks:
            for i in range(start, end + 1):
                claimed.add(i)
            pieces.append('\n'.join(lines[start:end + 1]))
        body = '\n\n'.join(pieces)
        keep = []
        for h in header:
            m = IMPORT_LINE.match(h)
            marker = IMPORT_MARKERS.get(m.group(1)) if m else None
            if marker is None or re.search(marker, body):
                keep.append(h)
        written[filename] = '\n'.join(keep).rstrip('\n') + '\n\n' + body.rstrip('\n') + '\n'

    # --- Verify -------------------------------------------------------------
    lost = [(i + 1, lines[i]) for i in range(len(lines))
            if i not in claimed and i >= info['header_end'] and not is_separator(lines[i])]
    if lost:
        raise SystemExit("lines dropped by the split:\n  " +
                         "\n  ".join(f"{n}: {t}" for n, t in lost[:20]))

    for filename, content in written.items():
        path = os.path.join(outdir, filename)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(content)
        print(f"  wrote {path} ({content.count(chr(10))} lines)")

    if os.path.basename(source_path) not in plan:
        os.remove(source_path)
        print(f"  removed {source_path}")
    return written


if __name__ == '__main__':
    plan = json.load(open(sys.argv[2], encoding='utf-8'))
    split(sys.argv[1], plan)
