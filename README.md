# soteria — a supervisor for coding agents

Run `claude` / `codex` / `opencode` with full autonomy without handing them your machine: one project to work in, approvals before irreversible moves, secrets the agent never sees, background sessions, and one-command undo when it goes wrong — with a tamper-evident log of everything.

Proven on macOS with `claude` and `opencode`; `codex`/`pi` and Linux (use the `docker`/`nono` backend) are unexercised. Not independently audited — `docs/THREAT_MODEL.md` lists what's not covered. Shims mediate `PATH` lookups only (builtins, absolute paths, and in-interpreter calls bypass them); the kernel box is the real wall.

## Install

Recommended — Homebrew, no clone needed:

```bash
brew tap koushiksaravanan/soteria
brew trust koushiksaravanan/soteria   # one-time gate for third-party taps
brew install soteria
```

From source — needs Python 3.10+ (macOS for kernel enforcement), nothing else:

```bash
git clone https://github.com/koushiksaravanan/soteria.git && cd soteria
./install.sh                    # prereq check + setup (idempotent, safe to re-run)
./install.sh --with-app         # also build SoteriaBar.app (macOS)
./install.sh --with-docker      # also build the soteria-toolbox image
```

What setup wires in: `~/.config/soteria/profiles/` (presets, auto-refreshed on later runs) and `~/.soteria/` (audit log, snapshots, sessions). No daemons, no services, no root.

## Everyday use — the menu-bar app (macOS)

```bash
app/SoteriaBar/build.sh   # swiftc only, no Xcode; bundles the CLI
open SoteriaBar.app       # goddess icon in the menu bar
```

- **New secure session…** — pick agent, strictness, and backend; opens a secured Terminal.
- **Ghost sessions…** — list background runs; attach to watch output, stop to kill.
- **Undo latest snapshot…** — revert what a session changed.
- **Connect API keys…** — keys into Keychain; agents only ever see phantoms.

The session dialog customizes everything (ask/network overrides, extra denials, caps, detached mode). All enforcement stays in the CLI.

## Advanced — command line

```bash
./soteria test                    # self-test, must stay green
./soteria setup                   # check host + install presets
./soteria run --allow ./proj --rollback -- claude --dangerously-skip-permissions
./soteria run --allow ./proj --detached -- codex   # background session
./soteria sessions               # list background sessions
./soteria attach <id>            # read its output (--follow to tail)
./soteria stop <id>              # stop it
./soteria undo <id> --yes        # revert what a session changed
./soteria list                   # snapshots, newest first
./soteria logs -f                # follow the audit log (tamper-evident)
./soteria scan                   # post-hoc attack findings over the log
./soteria launch --ui            # visual wizard + live log in browser
```

Caps per tool: `--memory 512M --max-processes 256 --tool-timeout 300`.
Approvals: terminal prompt, or `--ask-socket` for GUI flows.
Fails closed: crash, timeout, or dead approver = deny.

Backends (`run --backend`, also in the app dialog): `local` (default, kernel box on macOS) · `docker` (container sees only `/workspace`) · `nono` (kernel boxes, including Linux).

## Docs

`docs/ARCHITECTURE.md` (how it works) · `docs/THREAT_MODEL.md` (residual risks) · `docs/ROADMAP.md` (what's next) · `CREDITS.md` · `profiles/`, `ui/`, `app/` READMEs.

## Update / uninstall

```bash
brew upgrade soteria              # brew installs
git pull && ./install.sh          # source installs (add --with-app/--with-docker as needed)
brew uninstall soteria            # or: pkill -f SoteriaBar; rm -rf SoteriaBar.app
rm -rf ~/.soteria ~/.config/soteria   # remove all state (snapshots, log, sessions, presets)
```

License: MIT — see `LICENSE`.
