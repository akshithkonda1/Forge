#!/usr/bin/env python3
"""Add and remove Swift sources in an Xcode project, by anchored line edits.

Nothing here parses the project file as a whole. A `project.pbxproj` is an
old-format plist with four separate places that must agree about every source
file — `PBXBuildFile`, `PBXFileReference`, the group's `children`, and the
target's `PBXSourcesBuildPhase` — and a whole-file parser that rewrites all of
it risks reformatting sections nobody asked it to touch.

Instead each new file is threaded in beside an existing one: find the four lines
that mention the anchor, put four analogous lines after them. The anchor decides
the group and the target, which is exactly the intent ("next to LifestyleView"),
and a file that is not in exactly one target is rejected rather than guessed at.

Usage:
  pbxproj_files.py add <project.pbxproj> <Anchor.swift> <New.swift> [New2.swift ...]
  pbxproj_files.py remove <project.pbxproj> <Gone.swift>

The anchor may be written `HomeView.swift:AA0002000000000000000007` to name one
particular file reference. Two targets here each have a file called
HomeView.swift — the phone app's and the watch app's — and the basename alone
cannot say which one a new file should sit beside.
"""
import hashlib
import re
import sys


def lines_of(path):
    return open(path, encoding='utf-8').read().split('\n')


def find_anchor(lines, anchor):
    """The four lines that describe `anchor`, or a loud failure."""
    name, _, wanted_ref = anchor.partition(':')
    build_def = build_use = file_def = group_use = None
    build_ref = None
    if wanted_ref:
        for line in lines:
            if wanted_ref in line and 'isa = PBXBuildFile' in line:
                build_ref = line.split()[0].strip()
    for i, line in enumerate(lines):
        if name not in line:
            continue
        if wanted_ref and wanted_ref not in line and (
                build_ref is None or build_ref not in line):
            continue
        if 'isa = PBXBuildFile' in line:
            if build_def is not None:
                raise SystemExit(
                    f"{name} has more than one PBXBuildFile — it exists in several "
                    f"targets, so 'next to it' is ambiguous. Re-run with "
                    f"{name}:<fileRefID> to say which one.")
            build_def = i
        elif 'isa = PBXFileReference' in line:
            if file_def is not None:
                raise SystemExit(f"{anchor} has more than one PBXFileReference")
            file_def = i
        elif re.match(r'^\t+[0-9A-Za-z_]+ /\* .* in Sources \*/,$', line):
            if build_use is not None:
                raise SystemExit(f"{anchor} appears in more than one Sources phase")
            build_use = i
        elif re.match(r'^\t+[0-9A-Za-z_]+ /\* .* \*/,$', line):
            if group_use is not None:
                raise SystemExit(f"{anchor} appears in more than one group")
            group_use = i
    missing = [n for n, v in [('PBXBuildFile', build_def), ('PBXFileReference', file_def),
                              ('Sources phase', build_use), ('group', group_use)] if v is None]
    if missing:
        raise SystemExit(f"{anchor}: not found in {', '.join(missing)}")
    return build_def, file_def, build_use, group_use


def make_id(seed, taken):
    """A stable 24-character identifier that is not already in the project."""
    for salt in range(1000):
        digest = hashlib.sha1(f"{seed}:{salt}".encode()).hexdigest().upper()[:24]
        if digest not in taken:
            taken.add(digest)
            return digest
    raise SystemExit("could not mint a unique id")


def add(project, anchor, new_files):
    lines = lines_of(project)
    text = '\n'.join(lines)
    taken = set(re.findall(r'\b[0-9A-F]{24}\b', text))
    build_def, file_def, build_use, group_use = find_anchor(lines, anchor)

    anchor_indent = re.match(r'^(\t*)', lines[group_use]).group(1)
    phase_indent = re.match(r'^(\t*)', lines[build_use]).group(1)

    inserts = {build_def: [], file_def: [], build_use: [], group_use: []}
    for name in new_files:
        base = name.split('/')[-1]
        fid = make_id(f"file:{name}", taken)
        bid = make_id(f"build:{name}", taken)
        inserts[build_def].append(
            f'\t\t{bid} /* {base} in Sources */ = {{isa = PBXBuildFile; '
            f'fileRef = {fid} /* {base} */; }};')
        inserts[file_def].append(
            f'\t\t{fid} /* {base} */ = {{isa = PBXFileReference; '
            f'lastKnownFileType = sourcecode.swift; path = {base}; sourceTree = "<group>"; }};')
        inserts[group_use].append(f'{anchor_indent}{fid} /* {base} */,')
        inserts[build_use].append(f'{phase_indent}{bid} /* {base} in Sources */,')

    out = []
    for i, line in enumerate(lines):
        out.append(line)
        if i in inserts:
            out.extend(inserts[i])
    open(project, 'w', encoding='utf-8').write('\n'.join(out))
    print(f"  registered {len(new_files)} file(s) beside {anchor}")


def remove(project, gone):
    lines = lines_of(project)
    base = gone.split('/')[-1]
    keep, dropped = [], 0
    for line in lines:
        if re.search(r'/\* ' + re.escape(base) + r'( in Sources)? \*/', line) and (
                'isa = PBXBuildFile' in line or 'isa = PBXFileReference' in line
                or re.match(r'^\t+[0-9A-Za-z_]+ /\* .* \*/,$', line)):
            dropped += 1
            continue
        keep.append(line)
    if dropped != 4:
        raise SystemExit(f"{base}: expected to drop 4 lines, dropped {dropped}")
    open(project, 'w', encoding='utf-8').write('\n'.join(keep))
    print(f"  unregistered {base}")


if __name__ == '__main__':
    verb, project = sys.argv[1], sys.argv[2]
    if verb == 'add':
        add(project, sys.argv[3], sys.argv[4:])
    elif verb == 'remove':
        remove(project, sys.argv[3])
    else:
        raise SystemExit(f"unknown verb {verb}")
