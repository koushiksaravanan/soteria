# profiles — policy presets

`minimal` (LLM APIs only) · `developer` (general dev) · `claude-code` / `codex` (runtimes, no harness OAuth state — agents re-login via API key through `--credential`).

```bash
./soteria profile list                  # presets + yours
./soteria profile init --name my-agent --extends developer --out ~/.config/soteria/profiles/my-agent.json
./soteria profile validate --file ~/.config/soteria/profiles/my-agent.json
./soteria profile diff --a minimal --b developer
```

Custom profiles support `extends`, `groups`, `filesystem` (allow/read/write/deny), `network` (domains/credentials), and `command_policies.commands` (`from`/`can_use`/`invocation_policy`/`sandbox` fs scope). CLI flags override profile values.
