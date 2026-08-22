#!/usr/bin/env python3
"""Top-level declaration boundaries in a Swift file.

Splitting a 5,000-line view by eyeballing line numbers loses a closing brace
sooner or later, and the only compiler available here is a six-minute CI round
trip. So the split is done by a parser instead: brace depth tracked outside of
strings and comments, declarations taken whole, and the leading comments and
attributes that belong to a declaration carried along with it.

Emits JSON so the callers that actually move code can stay small.
"""
import json
import re
import sys

DECL = re.compile(
    r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*'
    r'(?:public|internal|fileprivate|private|open|final|indirect|@objc\s+)*\s*'
    r'(?:\b(struct|class|enum|extension|protocol|func|actor|typealias|var|let)\b'
    r'|(#Preview)\b)'
)
NAME = re.compile(
    r'\b(?:struct|class|enum|extension|protocol|func|actor|typealias|var|let)\s+'
    r'([A-Za-z_][A-Za-z0-9_]*)'
)


def scan(lines):
    """Yield (index, depth_before, depth_after) with strings/comments removed."""
    depth = 0
    in_block_comment = 0
    in_multiline_string = False
    out = []
    for i, raw in enumerate(lines):
        before = depth
        stripped_for_depth = []
        j = 0
        line = raw
        n = len(line)
        in_string = False
        while j < n:
            ch = line[j]
            two = line[j:j + 2]
            if in_multiline_string:
                if line[j:j + 3] == '"""':
                    in_multiline_string = False
                    j += 3
                    continue
                j += 1
                continue
            if in_block_comment:
                if two == '*/':
                    in_block_comment -= 1
                    j += 2
                    continue
                if two == '/*':
                    in_block_comment += 1
                    j += 2
                    continue
                j += 1
                continue
            if in_string:
                if ch == '\\':
                    j += 2
                    continue
                if ch == '"':
                    in_string = False
                j += 1
                continue
            if line[j:j + 3] == '"""':
                in_multiline_string = True
                j += 3
                continue
            if two == '//':
                break
            if two == '/*':
                in_block_comment += 1
                j += 2
                continue
            if ch == '"':
                in_string = True
                j += 1
                continue
            stripped_for_depth.append(ch)
            j += 1
        code = ''.join(stripped_for_depth)
        # Brackets of every kind, not just braces: a top-level
        # `let x: [T] = [ ... ]` spanning 190 lines closes on `]`, and counting
        # only `{}` reported it as a single line — which would have silently
        # dropped 190 lines of restaurant data on the first split.
        depth += (code.count('{') - code.count('}')
                  + code.count('[') - code.count(']')
                  + code.count('(') - code.count(')'))
        out.append((i, before, depth, code))
    return out


def declarations(path):
    lines = open(path, encoding='utf-8').read().split('\n')
    scanned = scan(lines)
    decls = []
    header_end = 0
    seen_code = False

    for i, before, after, code in scanned:
        if before != 0:
            continue
        text = lines[i]
        # `@preconcurrency import AVFoundation` and `@_exported import X` are
        # imports; matching only a leading `import` left them to be mistaken for
        # the first declaration's attributes.
        if not seen_code and re.match(r'^\s*(?:@[\w.]+\s+)*import\s+\w+', text):
            header_end = i + 1
            continue
        if DECL.match(text) and not text.lstrip().startswith('//'):
            seen_code = True
            # Walk back over the comments and attributes attached to this decl.
            start = i
            k = i - 1
            while k >= header_end:
                prev = lines[k].strip()
                if prev.startswith('//') or prev.startswith('*') or prev.startswith('/*') \
                        or prev.endswith('*/') or (prev.startswith('@') and not prev.startswith('@_')):
                    start = k
                    k -= 1
                    continue
                break
            # Find where this declaration closes.
            end = i
            for j2, b2, a2, _ in scanned[i:]:
                end = j2
                if a2 == 0 and j2 >= i:
                    break
            m = NAME.search(text)
            match = DECL.match(text)
            kind = match.group(1) or match.group(2)
            decls.append({
                'name': m.group(1) if m else kind,
                'kind': kind,
                'start': start,
                'decl_line': i,
                'end': end,
                'lines': end - start + 1,
            })
    return {
        'path': path,
        'total': len(lines),
        'header_end': header_end,
        'header': lines[:header_end],
        'decls': decls,
    }


if __name__ == '__main__':
    result = declarations(sys.argv[1])
    if len(sys.argv) > 2 and sys.argv[2] == '--json':
        print(json.dumps(result, indent=2))
    else:
        print(f"{result['path']}: {result['total']} lines, "
              f"{len(result['decls'])} top-level decls")
        covered = 0
        for d in result['decls']:
            covered += d['lines']
            print(f"  {d['lines']:5d}  {d['kind']:9s} {d['name']}"
                  f"   [{d['start'] + 1}-{d['end'] + 1}]")
        print(f"  covered {covered} of {result['total']}")
