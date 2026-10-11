#!/usr/bin/env bash
#
# Opens Pocket LLM the way Finder and the Dock do: a real build of the app,
# started by LaunchServices.
#
# Why this exists
# ---------------
# Two things about a built bundle bite the moment one is opened by hand.
#
#  1. `flutter test integration_test/<file> -d macos` builds
#     build/macos/Build/Products/Debug/Pocket LLM.app with the *test* file as
#     its entrypoint and leaves it that way, so a bundle opened by hand after a
#     device test is not the app: the window stays blank because there is no
#     test runner to drive it. This script rebuilds from lib/main.dart first.
#  2. macOS shows a first-time privacy prompt only to an app *it* started.
#     Opened from Finder, the Dock or `open`, the app is its own responsible
#     process; started by `flutter run`, a terminal or an IDE, macOS reads the
#     launcher's Info.plist instead and ends the app when that program has no
#     description for the permission (which is how speech recognition used to
#     take the chat down — see lib/features/voice/data/platform_speech_service.dart).
#     Something that has to be granted, such as Device recognition in
#     Settings › Voice, therefore has to be granted in an app opened this way.
#
# It refuses to open a second copy while one is running: two instances write the
# same conversations, settings and model directory.
#
# Usage
#   scripts/open_macos_app.sh              build from lib/main.dart, then open
#   scripts/open_macos_app.sh --no-build   open the existing bundle unchanged
#   scripts/run_macos.sh                   run attached instead, with hot reload
#   scripts/open_macos_app.sh --help
#
# Exits non-zero when an instance is already running, when the build fails, or
# when there is no built app to open.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/build/macos/Build/Products/Debug/Pocket LLM.app"
APP_EXECUTABLE="$APP/Contents/MacOS/Pocket LLM"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage
  scripts/open_macos_app.sh              build from lib/main.dart, then open
  scripts/open_macos_app.sh --no-build   open the existing bundle unchanged
  scripts/run_macos.sh                   run attached instead, with hot reload
USAGE
}

build=1

for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    -h|--help) usage; exit 0 ;;
    *)
      fail "unknown argument: $arg"
      usage >&2
      exit 2
      ;;
  esac
done

running="$(pgrep -f "$APP_EXECUTABLE" | paste -sd' ' - || true)"
if [ -n "$running" ]; then
  fail "Pocket LLM is already running (pid $running)."
  fail "Quit it first: two copies write the same conversations and settings."
  exit 1
fi

if [ "$build" -eq 1 ]; then
  if ! command -v flutter >/dev/null 2>&1; then
    fail "flutter is not on PATH"
    exit 1
  fi
  # Rebuilt from lib/main.dart, so a bundle left over from a device test is the
  # app again rather than a blank test window.
  ( cd "$REPO_ROOT" && flutter build macos --debug )
fi

if [ ! -x "$APP_EXECUTABLE" ]; then
  fail "no built app at $APP"
  fail "Run scripts/open_macos_app.sh without --no-build to build one."
  exit 1
fi

# `open` hands the app to LaunchServices — the same path Finder and the Dock
# use — so the app owns a permission request instead of attributing it to
# whatever started it. -n because the check above only proves nothing is
# running under this path.
open -n "$APP"
say "Opened $APP"
say "This is a normal app launch, so Settings › Voice › Allow device recognition can be granted here."
