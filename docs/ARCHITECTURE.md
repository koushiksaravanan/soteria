# ARCHITECTURE — soteria

A supervisor layer for running coding agents with autonomy — not a sandbox itself. Model proposes, trusted runtime decides; enforcement is delegated per platform (Seatbelt, Docker, nono).

## 1. Goals / non-goals

Goals:
* Let `claude`/`opencode` run with `--dangerously-*` inside a box on a Mac laptop (`codex`/`pi` launch the same way, unexercised).
* Default-deny writes (boxed to project) + secrets + egress, per-tool gate, post-hoc sequence findings, human ask only on irreversible, one-command undo, verifiable audit.
* Single static binary, local-first, one readable file, versioned policy.

Non-goals:
* Full VM memory isolation (no VM backend; Docker is the strongest boundary soteria ships).
* Server-side / hosted-tool interception.
* Malicious host or malicious operator (host is trusted).
* Perfect prompt-injection or zero-day prevention.

## 2. Principles

1. Fail-closed: crash, timeout, malformed verdict, missing context = deny with machine-readable reason.
2. Gate every layer we own: launch verdict, shim re-gating, egress proxy, fs box. (No pre/post-tool hook framework — gates, not hooks.)
3. Least privilege: writes boxed to project, per-tool fs scope, short-lived phantom tokens. Reads are allow-by-default outside secret/harness-state denies — a known tradeoff, see §8.
4. No secrets in sandbox: proxy injection preferred over env injection.
5. Everything reversible + provable: snapshots + hash-chained log.
6. Zero dependencies means hand-rolled security code: the proxy parser and the Seatbelt generator are the two functions that most need someone else's eyes. The single-file auditability is the point; external red-teaming of `write_sb_profile` and `_ProxyHandler` is the outstanding debt.

Inspired by Microsoft Agent Hooks `AGENT-HOOKS-0.1` (deny-means-deny, 8 points, 3 verdicts, 47-case conformance) and Aegis action-boundary model.

## 3. Overview

```
User CLI
  |
Launcher (snapshot, resolve profile, spawn)
  |
Supervisor (parent, holds real creds, proxy, policy engine, audit sealer)
  |--- IPC / approval queue
  |
Child: agent + all subprocesses (Seatbelt-boxed on macOS, proxy-only net, phantom creds)
  |
  |-- fs writes -> Seatbelt allow-list (reads: allow except secret/harness-state denies)
  |-- net CONNECT -> localhost proxy -> domain + endpoint check -> TLS out
  |-- tool call -> argv check -> per-tool Seatbelt profile -> L7 check
  |
Records -> local hash-chained NDJSON + snapshots (no Merkle tree, no signatures)
```

Parent never enters box. Child never sees real creds.

## 4. Components

### 4.1 Launcher `soteria run`
* Resolves `--profile` (+ `extends`), `--network-profile` (CLI wins, else profile, else `developer`), `--credential`, `--allow/--read/--write` + file variants, `--allow-domain/--deny-domain`, `--allow-endpoint`, `--block-net`, `--rollback`.
* Takes pre-snapshot (full copy under `~/.soteria/snapshots/<id>/tree` + SHA-256 `manifest.json`; no dedup yet).
* Applies kernel box then `exec` agent. No shell injection: argv array only.

### 4.2 Isolator
* macOS: Seatbelt profile generated from JSON, applied via `sandbox-exec`, irrevocable — **shipped** (`write_sb_profile`, denies resolved from profile groups).
* Linux: soft box only today (argv + env + audit). **No native Landlock yet** — use `--backend nono` (kernel) or `--backend docker` (container) on Linux.
* WSL2: detected and reported by `setup` (`/proc/version`); same delegation advice as Linux (Landlock TCP unavailable there).
* Fallback: Docker runner reuses same profiles + proxy. No `docker.sock` mount by default; `docker/kubectl` in the default command deny-list.

### 4.3 Net proxy
* Random localhost port, 256-bit session token. Reverse routes check `X-Soteria-Token`; `CONNECT` accepts `Bearer`/Basic (password = token) or the same header — other localhost processes can't ride the proxy.
* Two modes in one server: **reverse proxy** (credential injection, `BASE_URL` rewiring) and **CONNECT tunnel** (domain-filtered TCP relay, TLS stays end-to-end). Child gets `HTTP_PROXY`/`HTTPS_PROXY` (+ `NO_PROXY` for loopback) whenever filtering is on.
* Embedded groups: `llm_apis`, `package_registries`, `github`, `sigstore`, `documentation`, `google_cloud/azure/aws_bedrock`. Profiles: `minimal`, `developer`, `claude-code`, `codex`, `opencode`, `enterprise`. Explicit `--allow-domain` adds to the profile's groups; `--deny-domain` wins over both.
* Always-denied, non-overridable: `169.254.169.254`, `metadata.*.internal`, `169.254.0.0/16`, `fe80::/10` — checked on entry and against DNS answers (rebind protection, pinned sockaddr).
* Endpoint rules: `Service:METHOD:/glob`, e.g. `openai:POST:/v1/chat/completions`, `github:GET:/repos/*/issues/**`.
* `--upstream-proxy` is passed through to `--backend nono`; the local proxy does not chain upstream itself. Proxy decisions land in the audit log (`proxy.allow/deny/connect_allow`).

### 4.4 Cred broker
* Preferred: proxy injection. Sets `OPENAI_BASE_URL=http://127.0.0.1:PORT/openai` etc. in child. Strips incoming `Authorization`/`x-api-key`/`x-goog-api-key`, injects real at boundary, streams back.
* Stdlib price, stated plainly: this is a hand-parsed proxy on `BaseHTTPRequestHandler`, and CPython holds secrets in memory with no explicit zeroising. Zero dependencies buys one-file auditability; it does not buy memory safety. `write_sb_profile` (Seatbelt text generation) and `_ProxyHandler` (request parsing) are flagged for external red-team review — self-tests prove intended paths, not absent bugs.
* Env injection is NOT offered for API keys — phantom placeholders only. `--set-env`/`--env` cover non-secret config.
* Sources: parent env, macOS Keychain (`security`, service `soteria`), `env://VAR`, `file://PATH`, `op://vault/item/field` (1Password CLI), `keyring://service/account`. Custom profile credentials: `upstream` + `credential_key` + header `inject_header`/`credential_format` (header mode only for now; no `query_param`/`url_path`/`basic_auth`, SigV4, or OAuth yet).
* Built-ins: `openai: Authorization: Bearer {}`, `anthropic: x-api-key: {}`, `github: Authorization: Bearer {}`.

### 4.5 Tool broker (per-invocation micro-sandbox)
Status: **supervised broker shipped** (local backends). Each run installs
read-only shims for every mediated tool; the shim re-enters via
`soteria _broker`, which forwards over a per-run Unix socket to a host-side
supervisor daemon. The daemon re-checks tool + argv policy (incl. `can_use` /
`from.<caller>` edges), confines cwd to the project, caps depth (8) and
per-tool runtime (`--tool-timeout`, default 300s) plus 1MB output caps, then
spawns the real binary (resolved off-shim-PATH) under a per-tool Seatbelt
profile generated from `command_policies.commands.<tool>.sandbox`
(`fs_read`/`fs_write`, `.` = project; defaults: gh read-only, git read-write).
Legacy in-box `_broker` gate+exec remains as fail-closed fallback when the
socket is unreachable. Seatbelt re-allows shim-dir reads so shims run under
kernel mode. The launch gate resolves the approved top-level tool to its real
binary so it isn't re-gated; `--allow-command` exempts a tool everywhere.
Still pending: digest-verified exec, per-tool network narrowing, native
Landlock — full child micro-sandbox stays delegated to `--backend nono`.
Shell builtins and in-interpreter calls (`os.remove`) bypass shims by
construction; kernel deny groups remain the backstop.

Resource caps ride the same spawn path: `--memory` (parsed by `parse_size`,
`K/M/G` + bare bytes, `0` = no cap), `--max-processes` (`RLIMIT_NPROC`),
and `--tool-timeout` (wall-clock watchdog + `RLIMIT_CPU` backstop) apply in
the daemon's `preexec_fn`, with a best-effort cgroup-v2 join on Linux
(`memory.max`/`pids.max`, silent fallback when unwritable). macOS skips
`RLIMIT_AS`/`RSS` (any finite value breaks dyld at exec — verified) and
`RLIMIT_DATA` (unsettable): memory caps are Linux-enforced, macOS gets
CPU+NPROC+watchdog. Kills are labeled `limit=timeout|memory|cpu|rlimit`
on the `broker.exec` audit event.

Example `gh issue view 1052`:
* argv `issue view` matches the allow-list → ALLOW (launch gate; no digest pinning yet).
* proxy allows `POST /graphql`, injects real credential at the boundary, returns output, seals record.

Verdicts: `allow`, `deny (argv|tool|l7|chain)`, `ask (terminal/socket approve/deny/timeout, fail-closed)`.

### 4.6 Policy engine
* JSON profiles + `extends` + `groups` (`node_runtime`, `python_runtime`, `rust_runtime`) — **shipped** (`profiles/`, `profile init/validate/show/diff`).
* Fields: `filesystem.allow/read/write/deny/bypass_protection` (+ `allow_files`), `network.network_profile/allow_domain/deny_domain/custom_credentials`, `command_policies.commands` with `from`/`can_use`/`invocation_policy`/`sandbox.fs_read/fs_write` — **shipped** (launch gate + supervised shims).
* Runtime rules: CEL-compatible planned, not built. At-rest `scan` shipped (see 4.7); live hooks still pending (Phase 2).
* `env allow/deny/set` filtering with wildcards — **shipped**.

### 4.7 Sequence / behavior detector
Status: **post-hoc rules shipped** (`soteria scan` over the audit log:
exfil-sequence, burst, metadata-probing, denied-persistence, with
`--fail-on` for CI; `soteria timeline` for review). Live blocking on
sequences is still pending (Phase 2) — gates act per-event today.
Rules actually implemented:
* `exfil-sequence`: denied secret-path read followed by egress in one session (high)
* `burst`: 50+ gated tool events inside 60s (medium)
* `metadata-probing`: 3+ metadata/link-local attempts (medium)
* `denied-persistence`: same tool denied 3+ times in a session (low)
Still pending: privilege-escalation/lateral chains, rendezvous-file and
cross-session persistence detection.

### 4.8 Human control
* Two channels, both fail-closed (timeout/EOF/malformed = deny): terminal prompt, or unix-socket JSON broker (`soteria ask-listen` reference approver). The menu-bar app ships session management; approvals still happen in the terminal — no GUI approval socket yet.
* Irreversible patterns (`git push`, `rm -rf /`, `kubectl delete`, `terraform apply`, `gh pr merge`) ask under `escalations`/`strict` modes; `never` disables. Approvals are one-shot but NOT content-hash-bound yet. No budgets/time-horizons yet.

### 4.9 Snapshots + audit
* Pre-run full-copy snapshots (`tree/` + SHA-256 `manifest.json`), `list` (newest first) / `show --diff` / `verify` (re-hash manifest) / `undo --yes` / `cleanup --keep/--older-than` (also prunes orphaned shim dirs). Exclude patterns `node_modules/.next/target` (+ `.git`, `__pycache__`). No dedup/Merkle yet.
* Audit: hash-chained NDJSON (`seq/prev/hash`, `logs --verify`, legacy pre-chain lines tolerated), secret redaction, `scan`/`timeline` consumers. No signing, no schema registry, no ship/forwarder yet — the log never leaves the device.

### 4.10 Harness adapters
Proven with `claude` (API key via `--credential anthropic`, proxy-injected) and `opencode` end-to-end in the box. `codex`/`pi` launch the same way but are not regularly exercised — no per-harness fixtures or coverage matrix yet (no invented paths: anything unlisted here is untested). Host harness OAuth state (`~/.claude*`, `~/.codex`) is denied inside the box by the `deny_harness_state` group: agents cannot self-authenticate from the human's login and must re-login via API key. Console OAuth remains a host-side-only convenience for direct (unboxed) use.

### 4.11 Ghost sessions
Status: **shipped** (`run --detached`, `sessions`, `attach [--follow]`,
`stop [--grace]`). Snapshot + launch gate resolve up front in the parent;
detached + needs-approval with no socket channel and no TTY refuses (rc 3,
fail-closed) rather than forking an unapproved command. The parent forks
before proxy/daemon exist, so the child owns the full sandbox lifecycle
(proxy, shims, daemon, backend assembly) with stdout/stderr spooled to
`~/.soteria/sessions/<id>.spool.log` and stdin on `/dev/null` (descendant
terminal asks fail closed to deny). The child marks the job file
`exited` + `exit_code` atomically and `os._exit`s; the parent prints the id
and returns immediately. `stop` re-reads the job file, probes liveness, and
checks `ps` cmdline for pid-recycling before `SIGTERM` (escalates to
`SIGKILL` after `--grace`, default 2s); any doubt refuses. `session_list`
flips dead-but-marked-running rows to `exited` (exit unknown — "died
unreported"). `cleanup` prunes exited jobs (never running+alive) under the
same keep/age rules, even when no snapshots exist.

## 5. Key flows

File edit: agent writes inside `--allow` dir → post-run `show --diff` → `undo` if unwanted. (No pre-tool mediation: the box, not the call, is the boundary.)
Push: `git push` → no argv allow → ask (terminal/socket) → on allow, real `git` runs (launch-gate bypass avoids re-asking its own shim) → audit.
Model call: child SDK reads `OPENAI_BASE_URL` → proxy checks token + endpoint rules → injects real key → TLS out → audit logs service + HTTP code only, never the key.

## 6. Deployment

* Local: single file `./soteria` (source, needs Python 3.10+) or `dist/soteria` onefile (no runtime; `profiles/`+`ui/` bundled). Records in `~/.soteria/records.ndjson`, config in `~/.config/soteria/` (both overridable via `SOTERIA_HOME`/`SOTERIA_CONFIG`).
* Managed fleet / admin-owned installs: not built (no `--managed`, no read-only rules dir, no MDM script).
* Container: `--backend docker` / `nono` delegate the boundary. Local enforces via Seatbelt on macOS and soft box elsewhere — Linux kernel isolation means nono or Docker.

## 7. Testing

* Self-test suite (`./soteria test`, green): covering argv/tool
  gates, `can_use` chaining, secret scrub, proxy injection + endpoint rules,
  CONNECT allow/deny/auth, kernel pin, ask-broker fail-closed (incl. genuine
  single-ask approval), supervised shims (child block/allow/exempt, absolute
  re-entry, per-tool sandbox validation, daemon deny/allow/cwd-cap/depth-cap,
  forward fallback), resource limits (parse_size, macOS AS-skip, cgroup
  fallback, CPU backstop, fail-closed flags), ghost sessions (roundtrip,
  liveness, pid-validation, stop/double-stop, detached spool/list/attach,
  deny-leaks-no-job, ask-without-channel), harness-state lockdown,
  docker/nono construction + e2e (where binaries exist), profiles/`why`,
  env filtering, credential resolvers, audit chain, snapshot verify/cleanup,
  scan/timeline, Landlock detection, release-bundle payload. The frozen exe
  runs the same suite (`./dist/soteria test`) — rebuild it from
  `soteria.spec` first; a stale dist is not proof of the current source.
* Still pending: Agent Hooks 47-case conformance port, HF replay suite,
  red-team prompt-injection corpus, latency budget measurement.

## 8. Limits (honest)

* Kernel box != VM memory isolation (no VM backend — Docker is a container boundary, not memory isolation).
* macOS Seatbelt has no per-port dest filter (we pin to `localhost:*`); Linux has no native Landlock at all yet (soft box; `--backend nono/docker`).
* Shims mediate `PATH` lookups only: shell builtins, absolute-path invocation, and in-interpreter calls (`python -c os.remove`) bypass them. Soft mode additionally can't stop shim tampering or `HTTP_PROXY` unsetting — accidents-only.
* `stop` never signals on doubt (unknown job, failed liveness, `ps` mismatch → refuse); `RLIMIT_NPROC` counts the uid's procs on macOS, so floors below ~16 can starve forking tools (warned, 32+ recommended).
* CONNECT filtering binds cooperative clients in soft mode; kernel mode enforces via Seatbelt pin.
* TLS not intercepted (by design) — shared SaaS/CDN can still carry data to another tenant. Use `block-net` when no egress acceptable.
* `HTTP_PROXY` carries the per-session token in the child env (localhost-only, rotated per run — same tradeoff as nono).
* Prompts themselves leave machine to model API.
