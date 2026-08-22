#!/usr/bin/env python3
"""Move methods of a large class into `extension` files, safely.

Splitting a 1,700-line class is not the same problem as splitting a file full of
unrelated types, and it has two rules that a text move will happily break:

  * **Instance stored properties cannot live in an extension.** Swift rejects it
    outright. Static stored properties and computed properties are fine.
  * **`private` is file-scoped.** A private helper called from the code left
    behind, or from a different extension file, stops resolving the moment it
    moves — so either it travels with everything that calls it, or it has to
    become internal, which for a store class means exposing the mutable state
    you most wanted to keep private.

So this refuses to run rather than produce either failure, and reports exactly
which members are the problem. Grouping members by concern usually means each
concern's private helpers travel with it and nothing needs relaxing at all;
where that is not true, the report says so and the decision stays a human one.

Usage: swift_extract_extension.py <file.swift> <TypeName> <plan.json>
  plan.json: {"Type+Concern.swift": ["method", "otherMethod"], ...}
             Members not listed stay in the type body.
"""
import json
import os
import re
import sys

MEMBER = re.compile(
    r'^\s{1,8}(?:@[\w.]+(?:\([^)]*\))?\s*)*'
    r'((?:public |internal |fileprivate |private |static |class |final |lazy |'
    r'weak |unowned |mutating |nonisolated |override |convenience |required )*)'
    r'(func|var|let|init|subscript|deinit)\b\s*\(?\s*([A-Za-z_][A-Za-z0-9_]*)?')


def members_of(path, typename):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from swift_decls import declarations, scan
    info = declarations(path)
    lines = open(path, encoding='utf-8').read().split('\n')
    decl = next((d for d in info['decls'] if d['name'] == typename), None)
    if decl is None:
        raise SystemExit(f"{typename}: not a top-level declaration in {path}")

    # Two passes. The first finds where each member's own declaration begins;
    # the second walks each start back over the doc comment and attributes that
    # belong to it, and only then sets the previous member's end. Doing both in
    # one pass made a member end on the next member's `@discardableResult`,
    # which then also began the next member — so the attribute landed in two
    # files at once, and left a dangling attribute behind in the first.
    starts, depth = [], 0
    for i in range(decl['start'], decl['end'] + 1):
        code = re.sub(r'//.*|"(?:[^"\\]|\\.)*"', '', lines[i])
        if depth == 1:
            m = MEMBER.match(lines[i])
            if m and (m.group(3) or m.group(2) in ('init', 'deinit', 'subscript')):
                starts.append((i, m.group(1).strip(), m.group(2), m.group(3) or m.group(2)))
        depth += (code.count('{') - code.count('}')
                  + code.count('(') - code.count(')')
                  + code.count('[') - code.count(']'))

    adjusted = []
    for n, (i, mods, kind, name) in enumerate(starts):
        start = i
        floor = starts[n - 1][0] + 1 if n else decl['start'] + 1
        while start > floor and lines[start - 1].strip().startswith(('///', '//', '@')):
            start -= 1
        adjusted.append((start, mods, kind, name))

    found = []
    for n, (start, mods, kind, name) in enumerate(adjusted):
        end = (adjusted[n + 1][0] - 1) if n + 1 < len(adjusted) else decl['end'] - 1
        while end > start and not lines[end].strip():
            end -= 1
        found.append(finish(lines, start, end, mods, kind, name))

    return info, lines, decl, found

def finish(lines, start, end, mods, kind, name):
    return {
        'name': name, 'kind': kind, 'mods': mods,
        'start': start, 'end': end,
        'private': 'private' in mods or 'fileprivate' in mods,
        'static': 'static' in mods or 'class' in mods,
        'body': '\n'.join(lines[start:end + 1]),
    }


def is_instance_stored(m, lines):
    """Stored instance properties may not be moved into an extension."""
    if m['kind'] not in ('var', 'let') or m['static']:
        return False
    head = lines[m['start']:m['end'] + 1]
    text = '\n'.join(head)
    if re.search(r'@(Published|State|AppStorage|StateObject|ObservedObject|Environment)', text):
        return True
    # `var x: T { ... }` with no `=` before the brace is computed; anything else
    # that declares storage is not movable.
    first = next((l for l in head if re.match(r'^\s*(?:@[\w.]+\s*)*(?:\w+ )*(?:var|let)\b', l)), head[0])
    before_brace = first.split('{')[0]
    return '=' in before_brace or '{' not in first


def main():
    path, typename, planfile = sys.argv[1], sys.argv[2], sys.argv[3]
    plan = json.load(open(planfile, encoding='utf-8'))
    info, lines, decl, members = members_of(path, typename)
    by_name = {}
    for m in members:
        by_name.setdefault(m['name'], []).append(m)

    home = {}
    for filename, names in plan.items():
        for n in names:
            if n not in by_name:
                raise SystemExit(f"{n}: not a member of {typename}")
            for m in by_name[n]:
                home[id(m)] = filename

    problems = []
    for m in members:
        if id(m) not in home:
            continue
        if is_instance_stored(m, lines):
            problems.append(f"{m['name']} is a stored instance property — "
                            f"Swift does not allow those in an extension")
        if m['kind'] == 'deinit' or (m['kind'] == 'init' and 'convenience' not in m['mods']):
            problems.append(f"{m['name']} is a designated initializer or deinit — "
                            f"a class keeps those in its own declaration")
    for m in members:
        if not m['private']:
            continue
        # `init`, `deinit` and `subscript` are not referenced by those names, so
        # matching on them just flags every member that happens to write
        # `SomeOtherType.init(...)`.
        if m['kind'] in ('init', 'deinit', 'subscript'):
            continue
        owner = home.get(id(m))          # None means "stays in the type body"
        for other in members:
            if other is m or home.get(id(other)) == owner:
                continue
            if re.search(r'\b' + re.escape(m['name']) + r'\b', other['body']):
                where = home.get(id(other)) or f"{os.path.basename(path)} (the type body)"
                problems.append(
                    f"{m['name']} is private in "
                    f"{owner or os.path.basename(path) + ' (the type body)'} "
                    f"but used by {other['name']} in {where}")
    if problems:
        raise SystemExit("cannot move these as asked:\n  " + "\n  ".join(sorted(set(problems))))

    moved = {id(m) for m in members if id(m) in home}
    out = []
    for i, line in enumerate(lines):
        if any(m['start'] <= i <= m['end'] for m in members if id(m) in moved):
            continue
        out.append(line)
    open(path, 'w', encoding='utf-8').write(
        re.sub(r'\n{3,}', '\n\n', '\n'.join(out)))

    header = '\n'.join(info['header'])
    for filename, names in plan.items():
        chunks = [m for m in members if home.get(id(m)) == filename]
        chunks.sort(key=lambda m: m['start'])
        body = '\n\n'.join(m['body'] for m in chunks)
        target = os.path.join(os.path.dirname(path), filename)
        with open(target, 'w', encoding='utf-8') as fh:
            fh.write(f"{header}\n\nextension {typename} {{\n\n{body}\n}}\n")
        print(f"  wrote {target} ({body.count(chr(10)) + 4} lines, {len(chunks)} members)")
    print(f"  {path} keeps {len(members) - len(moved)} members")


if __name__ == '__main__':
    main()
