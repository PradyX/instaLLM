#!/usr/bin/env bash
#
# Runs a device integration test on a connected Android device.
#
# Why this exists
# ---------------
# `flutter test integration_test/<test>.dart -d <serial>` installs a debug
# build of the test entrypoint over the app. When the installed copy is a
# release build, that install uninstalls it first and takes its conversations
# and model files with it, silently. The device is also several phones and a
# tablet at once, so it is named here rather than guessed.
#
# Usage
#   scripts/test_android.sh integration_test/<test>.dart -d <serial> [options]
#   scripts/test_android.sh --check-only -d <serial>
#
# Remaining arguments go to `flutter test`.
#
# Afterwards the device runs the test entrypoint, so reopen the normal app with
# scripts/run_android.sh.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; }

serial=""
check_only=0
flutter_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device-id)
      if [[ $# -lt 2 ]]; then
        fail "$1 needs a serial"
        exit 1
      fi
      serial="$2"
      flutter_args+=("$1" "$2")
      shift 2
      ;;
    --check-only) check_only=1; shift ;;
    -h|--help)
      say "Usage: scripts/test_android.sh integration_test/<test>.dart -d <serial> [options]"
      exit 0
      ;;
    *) flutter_args+=("$1"); shift ;;
  esac
done

if ! command -v adb >/dev/null 2>&1; then
  fail "adb is not on PATH"
  exit 1
fi

if [[ -z "${serial}" ]]; then
  fail "name the device with -d <serial>; 'adb devices' lists the serials."
  exit 1
fi

if ! adb devices | awk 'NR>1 && $2 == "device" { print $1 }' | grep -Fxq -- "${serial}"; then
  fail "'${serial}' is not connected. Use one of the serials 'adb devices' prints."
  exit 1
fi

# A release-signed install cannot be updated in place by a debug test build.
installed_flags=$(adb -s "${serial}" shell dumpsys package com.prady.installm 2>/dev/null \
  | awk '/pkgFlags=/ { print; exit }' | tr -d '\r')
if [[ -n "${installed_flags}" && "${installed_flags}" != *DEBUGGABLE* ]]; then
  fail "this device holds a release-signed InstaLLM, and the debug test build"
  fail "uninstalls it first, deleting its conversations and model files."
  say  "Reinstall a debug build, or run the test on another device."
  exit 1
fi

say "Using device: ${serial}"

if [[ ${check_only} -eq 1 ]]; then
  exit 0
fi

if [[ ${#flutter_args[@]} -eq 0 ]]; then
  fail "name a test: scripts/test_android.sh integration_test/<test>.dart -d ${serial}"
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  fail "flutter is not on PATH"
  exit 1
fi

cd "${PROJECT_DIR}"
exec flutter test "${flutter_args[@]}"
