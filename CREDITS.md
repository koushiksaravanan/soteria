# CREDITS

`soteria` is a composition of ideas from open projects, incident reports, and research. No upstream code is vendored yet. If/when we reuse code, we will preserve licenses and add SPDX headers. Check upstream repos for current license before reuse. Project details below (star counts, team claims, spec numbers) are as publicly presented, not independently verified.

## Incident reports (threat model source)

* Hugging Face — `Security incident disclosure — July 2026` (2026-07-16) + `Anatomy of a Frontier Lab Agent Intrusion: Technical Timeline` (2026-07-27) by Adrien Carreira, Christophe Rannou and HF security team. https://huggingface.co/blog/security-incident-july-2026
* OpenAI — `The Hugging Face incident and the road ahead` (2026-08-26) + Black Hat USA 2026 briefing. Covers ExploitGym escape via Artifactory zero-day, message-board swarm (~700 active / ~1200 total agents), reward-hacking analysis.
* CrowdStrike, METR, Redwood Research — independent validation referenced in OpenAI report.

## Relationship to nono (read this first)

`soteria` is not a competitor to nono and does not claim parity with it.
nono is the enforcement engine: kernel micro-sandboxes on three platforms,
digest-pinned execution, Sigstore provenance, built by a team in Rust.
soteria is the layer above it: profiles, human approvals, phantom
credentials, snapshots + undo, ghost sessions, and a tamper-evident audit
trail — one readable stdlib-only file you can audit in an afternoon.

Where soteria cannot enforce, it delegates: `--backend nono` hands the
boundary to nono (this is the Linux kernel story — soteria alone on Linux
is a soft box), and soteria keeps gates, snapshots, and audit on top.
Profile and policy shapes are deliberately mirrored so moving between the
two is cheap. If you need the strongest per-tool containment, use nono
directly; if you want a supervised, reversible daily driver on your
laptop, use soteria, optionally with nono underneath.

## Direct building blocks

* **nolabs-ai / nono** — OS micro-sandboxes, Landlock/Seatbelt isolation, per-tool sandbox (`command_policies`, `can_use` chaining), network filtering (CONNECT + reverse proxy), proxy credential injection, undo/rollback, audit trail, Sigstore provenance. Team behind Sigstore. https://github.com/nolabs-ai/nono — https://nono.sh — soteria delegates enforcement to it via `--backend nono` (see above) and mirrors its profile/policy shapes lite. No nono code is vendored.
* **trailofbits / coop** — disposable Firecracker/Lima VMs for Claude Code/Codex (`up`/`exec`/`push`/`pull`, credential proxy, Sigstore-attested self-update). https://github.com/trailofbits/coop — evaluated as a soteria backend and cut (VM friction outweighed the isolation gain for a laptop runner); ideas credited, no code reused.
* **Perplexity AI / Numbat** — endpoint visibility, pre-action hooks, OTLP collection, CEL + sequence rules, NDJSON forensics, 52-rule catalog. CISO Kyle Polley and Perplexity security team. https://github.com/perplexityai/numbat
* **Microsoft / Agent Hooks `AGENT-HOOKS-0.1`** — framework-neutral governance contract, 8 interception points, 3 verdicts, fail-closed host obligations, 47-scenario conformance kit. Spec post by Lisa Brown Jaloza, implementation in Microsoft Agent Framework. https://commandline.microsoft.com/agent-hooks-framework-neutral-ai-governance-contract/
* **Auth0 / OpenFGA** — relationship-based access control (Zanzibar model), async human-in-the-loop via CIBA. Used as reference for identity + approval design. https://auth0.com/blog/do-not-let-your-agent-go-rogue/

## Research (policy + runtime guards)

* Aegis — `Runtime Governance for Agentic AI: Action-Boundary Control with Trusted Provenance and Fail-Closed Execution` arXiv:2608.16891 — action-proposal vs trusted decision, Senate quorum.
* SafeAgent — `SafeAgent: A Runtime Protection Architecture for Agentic Systems` arXiv:2604.17562 — runtime controller + context-aware decision core.
* DreamGuard — `DreamGuard: Efficient Runtime Guardrail via Risk-Aware World Model` arXiv:2608.05695 — recurrent risk state, 25ms guard.
* StepGuard — `StepGuard: Learning Step-Level Guardrails` arXiv:2608.24777 — StepGen + Balance-GRPO, -77.3% ASR / -2.8% utility reference target.
* FullStack Labs — `When AI Agents Go Rogue, and How to Stop Them` (2026-07-31) — containment, identity scoping, pipeline hardening checklist.

List authors per arXiv page at implementation time; IDs above are the stable reference.

## Sandboxes & wrappers (compared, not forked)

* `schmitthub/clawker` — local Docker + deny-default egress + worktrees.
* `yaroshevych/AgentSandbox` — per-project Dockerfile + `agents` launcher + iptables firewall.
* `ComposableSecurity/ai-sandbox-devcontainer` — Claude/Codex devcontainer with strong defaults.
* `nano-step/ai-sandbox-wrapper` — non-root, cap-drop, per-project DB isolation.
* `1996fanrui/agents-sandbox (`agbox`)` — local control plane, companion containers.
* `mku-05/sandbox-agent-ai` — hardened `agent-sandbox.sh` launcher, restricted net mode.
* `nikvdp/cco` — Seatbelt/bubblewrap with Docker fallback.
* Anthropic `Claude Code sandbox-environments` docs — Bash tool vs runtime vs devcontainer vs VM model.

## What we owe

If we port profiles, rules, or adapters: keep upstream copyright, link back, send fixes upstream, and note divergences in `docs/ARCHITECTURE.md` coverage matrix. Security ideas are credited here; implementation will cite inline.
