# profiles — policy presets

`minimal` (LLM APIs only) · `developer` (general dev) · `claude-code` / `codex` (runtimes, no harness OAuth state — agents re-login via API key through `--credential`).

```bash
./soteria profile list                  # presets + yours
./soteria profile init --name my-agent --extends developer --out ~/.config/soteria/profiles/my-agent.json
./soteria profile validate --file ~/.config/soteria/profiles/my-agent.json
./soteria profile diff --a minimal --b developer
```

Custom profiles support `extends`, `groups`, `filesystem` (allow/read/write/deny), `network` (domains/credentials), and `command_policies.commands` (`from`/`can_use`/`invocation_policy`, `sandbox` fs scope, `network` egress scope with `allow_domains`/`deny_domains`/`allow_endpoints`/`services` — always a subset of the session). CLI flags override profile values.

## Packs — sharing profiles

A pack is a zip of profiles plus a `pack.json` manifest (name, version, sha256 per file):

```bash
./soteria pack init --dir ./team-profiles --name team --out team-1.0.0.zip
./soteria pack verify --file team-1.0.0.zip        # digests re-checked, fail closed
./soteria pack sign --file team-1.0.0.zip          # cosign passthrough (Fulcio OIDC)
./soteria pack pull --source ./team-1.0.0.zip      # or https://… URL
./soteria pack pull --source URL --strict           # refuse unsigned packs
./soteria pack list                                # installed pack receipts
```

Pull verifies digests before installing, validates every profile, refuses shipped preset names without `--force`, and records a receipt. Unsigned packs install with a loud warning (authorship unverified); `--strict` refuses them. Signature presence is reported, not cryptographically verified — digests are the enforced guarantee.
