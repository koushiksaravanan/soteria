# ROADMAP — soteria

> Status 2026-09-07: self-test green on macOS source (frozen exe
> needs a rebuild from `soteria.spec` — dist/ is stale). Proven: macOS,
> `claude` + `opencode`. `codex`/`pi` launch untested; Linux is soft-box
> without nono/Docker. One maintainer, no audit, no funding — plan
> accordingly.

## Shipped (v0)

* `run` with profiles, Seatbelt session box, proxy cred injection + endpoint rules, CONNECT tunnel, snapshots + `verify`/`cleanup`/`undo`.
* Supervised tool broker (shims + daemon + per-tool Seatbelt scope), `can_use` caller edges, per-tool resource caps.
* Ghost sessions (`--detached`, `sessions`/`stop`/`attach`), harness OAuth state denied in-box.
* Hash-chained audit + `verify`, `scan` (4 post-hoc rules + `--fail-on`), `timeline`, `why`, `setup` (installs + refreshes presets).
* Backends: `local`, `docker`, `nono`. Menu-bar app + web wizard. Coop backend evaluated and cut.

## Next (small, concrete)

* External red-team of `write_sb_profile` + `_ProxyHandler` (the two functions self-tests can't validate).
* Rebuild + Developer-ID-sign the frozen exe; re-verify it runs the suite.
* Fill the tap formula sha256 per release (`homebrew-soteria` repo) so `brew upgrade` tracks new tags.
* `codex` end-to-end pass on macOS; Linux soft-box pass with `--backend docker`.
* Per-tool network narrowing (scoped proxy tokens per tool).

## Later (directional, not committed)

* Live sequence blocking, content-hash-bound approvals, usage budgets.
* Pack registry + cosign verification passthrough; native Landlock via ctypes.
* Agent Hooks conformance port; managed/fleet mode; central audit sink.
* Explicitly out of v1: cloud execution, TLS intercept, full DLP, server gateway.

## Notes

* Stays a Python 3.10+ **stdlib-only single file** (+ PyInstaller onefile). No Rust core, no SDK matrix — one-file auditability is the point.
* Shims cover local children; no harness hook framework is planned.
* `--upstream-proxy` passes through to nono only; the local proxy doesn't chain upstream.
