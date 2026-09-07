# Contributing to soteria

Solo-maintainer rules. Short on purpose.

## Workflow (enforced on `main`)

1. **Branch for everything.** `feat/<slice>`, `fix/<thing>`, `docs/<area>`, `chore/<task>`. No direct pushes to `main` (force-push and deletion are blocked; history must stay linear). PRs are required with zero approvals — the point is the review trail plus green CI, not permission.
2. **Suite green before you open the PR.** `./soteria test` — all of it, source tree. Frozen-exe verification (`./dist/soteria test`) only when `soteria.spec` or the CLI changed meaningfully; rebuild from the spec first, never trust a stale `dist/`.
3. **PR, then squash-merge.** One logical change per PR. The squash message follows existing style (`feat|fix|docs|chore(scope): ...`). CI (`self-test` on macOS + Ubuntu) must pass; it runs the full suite hermetically.
4. **Docs move with code.** Behavior change without `docs/` + README updates gets sent back. No hardcoded test counts in prose — the suite prints its own number.

## Release

- Tag `v<minor>` per release; Homebrew tap (`homebrew-soteria`) formula `url`+`sha256` bumped from the tag tarball in the same cycle.
- Security tightenings also refresh shipped presets: `setup` auto-refreshes user copies with backup — no manual migration step.

## What gets extra scrutiny

- `write_sb_profile` (Seatbelt text generation) and `_ProxyHandler` (request parsing): flagged for external red-team review. Self-tests prove intended paths, not absent bugs — changes here need a second pair of eyes, not just green tests.
- Anything touching credential resolution, shim generation, or the broker socket protocol: same bar.
