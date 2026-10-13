#!/usr/bin/env bash
# Build the InstaLLM Android APK; defaults to a locally testable debug build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
if [ "$#" -eq 0 ]; then
  set -- --debug
fi
flutter build apk "$@"
