#!/usr/bin/env bash
# Run native Flutter tests without starting a second Pocket LLM instance.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXECUTABLE="$REPO_ROOT/build/macos/Build/Products/Debug/Pocket LLM.app/Contents/MacOS/Pocket LLM"

if [ "$#" -eq 0 ]; then
  printf 'Usage: scripts/test_macos.sh integration_test/<test>.dart [test options]\n' >&2
  exit 2
fi

if pgrep -f "$APP_EXECUTABLE" >/dev/null; then
  printf 'Quit Pocket LLM before native tests; two instances share app storage.\n' >&2
  exit 1
fi

cd "$REPO_ROOT"
scripts/run_macos.sh --ensure-only
flutter test "$@" -d macos
# Device tests leave the bundle using their test entrypoint. Rebuild/open the
# normal app afterwards with scripts/open_macos_app.sh.
