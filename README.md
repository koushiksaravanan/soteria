# soteria — a supervisor for coding agents

Run `claude` / `codex` / `opencode` with full autonomy without handing them your machine: one project to work in, approvals before irreversible moves, secrets the agent never sees, background sessions, and one-command undo when it goes wrong — all in one readable stdlib-only Python file, with a tamper-evident log of everything.

Proven on macOS with `claude` and `opencode`; `codex`/`pi` and Linux (use the `docker`/`nono` backend) are unexercised. Not independently audited — `docs/THREAT_MODEL.md` lists what's not covered. Stdlib-only means one auditable file, at the price of a hand-rolled proxy and in-memory secrets (`docs/ARCHITECTURE.md` §4.4).

Boxed to one project, real secrets never visible, asks before irreversible moves on mediated paths, one-command undo. (Shims mediate `PATH` lookups only — shell builtins, absolute paths, and in-interpreter calls bypass them; the kernel box is the real wall.)

Needs Python 3.10+ (macOS for kernel enforcement). No other dependencies.

## Install

```bash
git clone https://github.com/koushiksaravanan/soteria.git && cd soteria
./install.sh                    # prereq check + setup (idempotent, safe to re-run)
./install.sh --with-app         # also build SoteriaBar.app (macOS)
./install.sh --with-docker      # also build the soteria-toolbox image
```

What that wires in: `~/.config/soteria/profiles/` (presets, auto-refreshed on later runs), `~/.soteria/` (audit log, snapshots, sessions), plus the optional app bundle and container image. No daemons, no services, no root.

After the v0 tag, no clone needed:

```bash
brew install https://raw.githubusercontent.com/koushiksaravanan/soteria/v0/Formula/soteria.rb
```

## Everyday use — the menu-bar app (macOS)

```bash
app/SoteriaBar/build.sh   # swiftc only, no Xcode; bundles the CLI
open SoteriaBar.app       # shield icon in the menu bar
```

Shield menu: **New secure session…** (agent × strictness × backend → secured Terminal), **Ghost sessions…** (list, attach, stop background runs), **Undo latest snapshot…**, **Connect API keys…** (keys into Keychain — agents only ever see phantoms). The dialog previews and customizes everything (ask/network overrides, caps, detached); all enforcement stays in the CLI.

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
git pull && ./install.sh        # refresh presets + re-verify (add --with-app/--with-docker as needed)
pkill -f SoteriaBar; rm -rf SoteriaBar.app    # remove the menu-bar app
rm -rf ~/.soteria ~/.config/soteria           # remove all state (snapshots, log, sessions, presets)
```

License: MIT — see `LICENSE`.
