# SoteriaBar — menu-bar front-end (macOS)

Shield icon: new session dialog (agent × strictness × backend, ask/network overrides, detached + caps), per-service API-key login (Keychain — agents only see phantoms), undo, ghost sessions. All enforcement stays in the CLI. Self-test and audit log remain CLI-only (`./soteria test`, `./soteria logs`).

```bash
app/SoteriaBar/build.sh   # swiftc only, bundles ./soteria, ad-hoc signs
open SoteriaBar.app       # menu-bar only, no Dock icon
```

Rebuild after pulling — the bundle embeds the current `./soteria`.
