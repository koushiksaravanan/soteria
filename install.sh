#!/bin/sh
# soteria installer: prereq check + first-time setup. Idempotent — safe to re-run.
# Usage: ./install.sh [--with-app] [--with-docker]
#   --with-app     also build SoteriaBar.app (macOS, needs swiftc)
#   --with-docker  also build the soteria-toolbox image (needs docker)
set -eu
cd "$(dirname "$0")"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1 ($2)"; exit 1; }; }

need python3 "install Python 3.10+ (python.org or brew install python)"
ver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
major=${ver%%.*}; minor=${ver#*.}
if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 10 ]; }; then
  echo "need Python 3.10+, found $ver"; exit 1
fi
echo "python: $(python3 --version) — ok"

./soteria setup || { echo "setup failed"; exit 1; }

if [ "${1:-}" = "--with-app" ] || [ "${2:-}" = "--with-app" ]; then
  if [ "$(uname)" = "Darwin" ]; then
    sh app/SoteriaBar/build.sh
  else
    echo "skip: SoteriaBar.app is macOS-only"
  fi
fi
if [ "${1:-}" = "--with-docker" ] || [ "${2:-}" = "--with-docker" ]; then
  if command -v docker >/dev/null 2>&1; then
    docker build -f examples/Dockerfile.toolbox -t soteria-toolbox .
  else
    echo "skip: docker not found (Docker Desktop for --backend docker)"
  fi
fi

echo ""
echo "installed. next:"
echo "  ./soteria test                       # self-test, must stay green"
echo "  ./soteria run --allow ./proj --rollback -- claude --dangerously-skip-permissions"
echo "  open SoteriaBar.app                  # if built with --with-app"
