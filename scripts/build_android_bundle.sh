#!/usr/bin/env bash
# Build the signed Android App Bundle (.aab) for a Google Play upload.
#
# Play needs the bundle, not an APK, and it needs a release signature: the
# keystore lives outside the repository and android/key.properties points at
# it, so this script refuses to run on a checkout without that file instead of
# producing an unsigned bundle that Play would reject.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -f android/key.properties ]; then
  echo "Missing android/key.properties; add storeFile, storePassword, keyAlias and keyPassword." >&2
  exit 1
fi

BUNDLE="build/app/outputs/bundle/release/app-release.aab"
# A failed build must not leave an older bundle looking like a fresh one.
rm -f "$BUNDLE"

flutter build appbundle --release "$@"

if [ ! -f "$BUNDLE" ]; then
  echo "Build finished without $BUNDLE" >&2
  exit 1
fi

VERSION="$(sed -n 's/^version: *//p' pubspec.yaml | head -n 1)"
echo
echo "Bundle:  $BUNDLE ($(du -h "$BUNDLE" | cut -f1))"
echo "Version: $VERSION"
echo "SHA-256: $(shasum -a 256 "$BUNDLE" | cut -d' ' -f1)"
