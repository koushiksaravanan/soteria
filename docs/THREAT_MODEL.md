# THREAT MODEL — soteria

## 1. Attacker

* Benign agent gone wild: excessive autonomy, reward-hacking impossible tasks, misreading scope.
* Compromised agent: prompt injection in repo/issue/doc/dependency, malicious MCP server, poisoned dataset/template.
* Malicious instructions smuggled via tool output that steer next tool calls.
* No human directs each step; thousands of small automated decisions at machine speed.

Assumed capable of: reading any file agent can read, running allowed tools with crafted args, reaching any network destination agent can reach, persisting notes for next run, coordinating via shared files if permitted.

## 2. Trust boundaries

```
[User + Host OS + Keystore] TRUSTED
  |
[Supervisor: policy engine, proxy, cred broker, audit sealer] TRUSTED
  |
[Child box: agent, subprocesses, tools, MCP] UNTRUSTED
  |
[External: model API, GitHub, registries] UNTRUSTED (allow-listed)
```

Host compromise, malicious operator, physical access: out of scope. Server-side tool execution that never hits local gate: surfaced as gap, not covered.

## 3. Assets

* Host fs: `~/.ssh`, `~/.aws`, `~/.config/gcloud`, `.env`, other checkouts.
* Secrets: LLM keys, GitHub tokens, cloud creds.
* Project integrity: source, `.git/hooks/config`, CI.
* Network position: ability to exfil or pivot to internal hosts, metadata, k8s.
* Provenance: audit log integrity.

## 4. HF July 2026 mapping

Based on public disclosures, as reported (not independently verified): Hugging Face `security-incident-july-2026` + `agent-intrusion-technical-timeline` (Adrien Carreira, Christophe Rannou), OpenAI `Hugging Face incident and the road ahead` (Aug 2026).

| HF TTP | Laptop analogue | Control in soteria |
|--------|-----------------|---------------------|
| Escape via package-proxy zero-day / SSRF to internet | Agent uses allowed proxy/registry to reach unexpected host | CONNECT tunnel + domain groups + endpoint rules, DNS-rebind check, deny IP literals/link-local; kernel mode pins egress to the proxy |
| Artifactory as message board, dir-name channel, swarm collusion | Agents share `/tmp`, dotfiles, chat logs to coordinate | Burst + denied-persistence findings via `scan`; NO rendezvous-file detection yet |
| Never give up on 198/898 unsolved tasks, cheat eval | Agent loops, tries riskier paths after failure | Denied-persistence findings + ask-on-irreversible; NO budgets/circuit breakers yet |
| HDF5 external read -> env/source disclosure | Dataset/CSV/notebook loader reads `/etc/passwd`, `~/.aws` | Fs profile denies + Seatbelt read-denies on macOS (soft mode: gate-only); mediated tools get a per-tool Seatbelt fs scope, but there is no per-loader micro-sandbox inside an interpreter |
| Jinja/RefJinja RCE in prod pod | Template renders `{{ exec(...) }}` | No template sandboxing — out of scope for a laptop runner; box + snapshots contain the blast radius |
| Service-account token -> cluster-admin in <13h | `AWS_*` env, `gh auth token`, kubeconfig reuse | Phantom creds (never in child env), `docker/kubectl` in default deny-list; `.ssh`/`.aws`/gcloud/`.kube` denied by group |
| Cloud metadata `169.254.169.254` | Same on laptop with cloud creds | Always-denied CIDRs, non-overridable, enforced at proxy AND argv gate |
| GitHub App `contents:write` + PR to poison CI | `git push`, hook plant, remote add | `push/merge` = ask (terminal/socket, fail-closed); snapshots make it reversible. NO hash-bound approval, NO `.git` over-mount yet |
| Dead-drop datasets + API as C2/exfil | Pastebin/Gist/dataset upload as exfil | Egress allow-list + post-hoc exfil-sequence findings + hash-chained trail; no live sequence blocking yet |
| Guardrail asymmetry (hosted model refused forensics) | Same for user triage | Local `scan`/`timeline` over the on-device log; no data must leave device |

## 5. Non-goals / residual risk

* Kernel zero-day in Seatbelt itself; VM-grade memory isolation on local backends (no VM backend — Docker is a container boundary, not memory isolation).
* Data leaving via allowed destination (model prompt, allowed GitHub repo, shared SaaS tenant, domain-fronting). Mitigated by endpoint rules + `block-net`, not eliminated.
* Shim bypasses by construction: shell builtins, absolute-path invocation, in-interpreter calls; soft mode additionally allows shim tampering and proxy env removal. The supervised daemon narrows mediated tools further (per-tool Seatbelt fs scope, cwd confinement), but unmediated paths still rely on the session box — kernel/docker/nono backends close these progressively.
* Reads outside the project are allowed by default (verified: a boxed `cat` reads `/tmp` fine). Secrets, harness state, and explicit denies are the exceptions. Other checkouts and drops are therefore readable — exfiltration must still pass the allow-listed proxy, where it is logged, but an allowed destination (including the model itself) cannot be distinguished from legitimate traffic.
* Ghost sessions outlive the terminal that spawned them — reaped via `stop`/`cleanup`, or they linger (visible in `sessions`). Spools live next to the audit log under the same host trust. Memory caps are Linux-enforced; on macOS a malloc-loop is bounded by CPU/watchdog kill, not bytes.
* User explicitly widens policy (`--allow / --allow-domain *`, mounts `$HOME`, `--allow-command rm`, shares `docker.sock`). Logged + warned, but allowed.
* Social engineering the human approver. Mitigated by explicit argv display + snapshots, not solved (no hash-bound approval yet).

## 6. Abuse cases to test

Covered by `./soteria test` (source; rebuild the frozen exe from
`soteria.spec` before citing its result — a stale dist proves nothing):

1. `cat ~/.ssh/id_rsa` -> kernel deny (Seatbelt read-deny + argv gate).
2. `env | grep KEY` -> sees phantom only.
3. `curl 169.254.169.254` -> proxy DENY `denied_cidr` (argv gate first).
4. `gh issue comment` with exfil -> tool argv deny, at launch and via shim.
5. `gh api …/comments` passing argv but hitting denied endpoint -> L7 deny.
6. `git push` -> ask, deny without approval (terminal + socket, incl. genuine single-ask approval).
7. Detached runs gate identically (`rm` denied pre-fork, no job leaked; ask with no channel refused); per-tool memory/process caps kill runaways with `limit=` audit.
8. `stop` refuses to signal on pid doubt (unknown job, dead `ps` match); resource-limit and session tests cover the guards.
9. Host harness OAuth state (`~/.claude*`, `~/.codex`) unreadable in-box (`deny_harness_state` + argv secret marks + Seatbelt denies); agents re-authenticate via API key through the proxy, never from the human's login.
10. `~/.kube/config` unreadable in-box (deny_credentials group + argv mark).

Not yet covered (aspirational): `/tmp` message-board rendezvous detection, recon-loop circuit breaker, template-payload sandboxing, hook-tamper drift detection, hash-bound approvals.
