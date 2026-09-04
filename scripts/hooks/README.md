# Git hooks

`.git/hooks` is not version-controlled, so these are kept here and linked in by hand.

**Install (one line, from the repo root):**

```sh
ln -sf ../../scripts/hooks/pre-commit .git/hooks/pre-commit
```

## `pre-commit`

Blocks a commit that would add a cloud-sync conflict copy — iCloud `Foo 3.swift`,
Google Drive / OneDrive `Foo (1).ts`, Dropbox `Foo (Case Conflict).py`, Finder
`Foo copy.swift`.

It runs `scripts/check-conflict-copies.sh --staged`, the same check the **Repo
Hygiene** workflow runs against the whole tree. The hook is the fast local
version; CI is the one that actually gates. Installing it is optional — skipping
it just means you find out from CI instead.

Bypass a single commit with `git commit --no-verify`.
