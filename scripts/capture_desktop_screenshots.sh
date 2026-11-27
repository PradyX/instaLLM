#!/usr/bin/env bash
# Re-capture the desktop store screens and re-render the store artwork.
#
# The screens used to come from the macOS window with `screencapture`, which
# needs a person to navigate the app: the Flutter content exposes no
# accessibility tree, so driving it meant synthetic clicks. This runs
# integration_test/store_screenshots_test.dart instead, which drives the real
# app through its own widget tree and rasterises the root repaint boundary at
# 2x into screens/desktop/1.png to 4.png at 2560x1440.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

scripts/test_macos.sh integration_test/store_screenshots_test.dart

# Reframe every set from the captures in screens/, since the script renders
# them all in one pass. Needs Pillow and the fonts already on macOS.
python3 scripts/generate_store_art.py

printf '\nCaptures are in screens/desktop/, artwork in screens/framed/.\n'
printf 'Rebuild the normal app afterwards with scripts/open_macos_app.sh.\n'
