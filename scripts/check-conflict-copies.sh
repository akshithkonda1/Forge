#!/usr/bin/env bash
#
# Fails if any file-sync conflict copy is present in the repository.
#
# Cloud sync clients resolve a simultaneous save of the same filename by keeping
# both versions and renaming one. Each client has its own convention:
#
#   iCloud Drive     Foo 2.swift, Foo 3.swift        (space + integer)
#   Google Drive     Foo (1).swift
#   OneDrive         Foo (2).swift
#   Dropbox          Foo (Case Conflict).swift, Foo (user's conflicted copy).swift
#   Finder/Explorer  Foo copy.swift, Foo - Copy.swift, Foo copy 2.swift
#
# These copies are stale snapshots. They are never referenced by the build, so
# nothing fails when they land — they simply accumulate, and a reader cannot tell
# which of `Foo.swift` and `Foo 3.swift` is the real one. 111 of them reached
# main in a single commit before this check existed.
#
# Usage:
#   scripts/check-conflict-copies.sh            # scan tracked files (CI, hook)
#   scripts/check-conflict-copies.sh --staged   # scan only staged additions
#
# Exits 0 when clean, 1 when conflict copies are found.

set -euo pipefail

mode="${1:-tracked}"

case "$mode" in
    --staged) listing=$(git diff --cached --name-only --diff-filter=AM) ;;
    tracked)  listing=$(git ls-files) ;;
    *) echo "usage: $0 [--staged]" >&2; exit 2 ;;
esac

# Matched against path segments, not only the basename. iCloud also duplicates
# whole folders (`Views/Profile 2/Foo.swift`) and extensionless files
# (`.gitkeep 3`). Those used to slip through and land on main.
#   ' [0-9]+'          iCloud
#   ' \([0-9]+\)'      Google Drive / OneDrive
#   ' \(.*[Cc]onflict' Dropbox, both spellings
#   '[ -]+[Cc]opy'     Finder / Explorer, optional trailing index
# Trailing `/` catches a numbered folder anywhere in the path
# (`Views/Profile 2/Foo.swift`). Trailing extension or EOS catches the file
# itself (`Foo 2.swift`, `.gitkeep 3`).
pattern='(^|/)[^/]+( [0-9]+| \([0-9]+\)| \(.*[Cc]onflict[^)]*\)|[ -]+[Cc]opy( [0-9]+)?)(/|\.[^./]+|$)'

found=$(printf '%s\n' "$listing" | grep -E "$pattern" || true)

if [ -n "$found" ]; then
    count=$(printf '%s\n' "$found" | grep -c .)
    echo "✗ $count file-sync conflict copy/copies found:"
    printf '%s\n' "$found" | sed 's/^/    /'
    cat <<'EOF'

These are cloud-sync conflict copies, not real source files. Delete them:

    git ls-files | grep -E ' [0-9]+\.[^./]+$' | tr '\n' '\0' | xargs -0 git rm --

If the repository lives inside a synced folder (iCloud Drive, Dropbox, Google
Drive, OneDrive), it will keep producing these. Move the checkout outside the
synced folder, or exclude it from sync.
EOF
    exit 1
fi

echo "✓ no file-sync conflict copies"
