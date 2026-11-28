#!/usr/bin/env bash
#
# Runs InstaLLM on a connected Android device over adb.
#
# Why this exists
# ---------------
# This machine keeps two phones and a tablet attached at once, and several of
# them are wireless (`adb-<serial>-<suffix>._adb-tls-connect._tcp`), so a bare
# `flutter run` either asks which device or picks one the caller did not mean.
# The device is therefore named explicitly here, and the serial is the one adb
# reports, which is also the id `flutter -d` accepts.
#
# Usage
#   scripts/run_android.sh                     run on the only connected device
#   scripts/run_android.sh -d <serial>         run on that device
#   scripts/run_android.sh --check-only        list devices and stop
#   scripts/run_android.sh --help
#   scripts/run_android.sh [args...]           remaining args go to `flutter run`
#
# Exits non-zero when adb is missing, no device is connected, or the device is
# ambiguous and none was named. Run it from a terminal, not a pipe, if you want
# flutter's hot-reload keys.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage
  scripts/run_android.sh                 run on the only connected device
  scripts/run_android.sh -d <serial>     run on that device
  scripts/run_android.sh --check-only    list devices and stop
  scripts/run_android.sh --allow-data-loss
                                         install the debug APK even though it
                                         will uninstall a release build
  scripts/run_android.sh --help
  scripts/run_android.sh [args...]       remaining args are passed to `flutter run`

The serial is the one `adb devices` prints, for example
  adb-0123456789ABCDEF-_adb-tls-connect._tcp
USAGE
}

# Prints one serial per connected device, in adb's order.
device_serials() {
  adb devices | awk 'NR>1 && $2 == "device" { print $1 }'
}

check_only=0
serial=""
allow_data_loss=0
flutter_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)
      if [[ $# -lt 2 ]]; then
        fail "$1 needs a serial"
        exit 1
      fi
      serial="$2"
      shift 2
      ;;
    --allow-data-loss) allow_data_loss=1; shift ;;
    --check-only) check_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) flutter_args+=("$1"); shift ;;
  esac
done

if ! command -v adb >/dev/null 2>&1; then
  fail "adb is not on PATH"
  exit 1
fi

serials=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && serials+=("${line}")
done < <(device_serials)

if [[ ${#serials[@]} -eq 0 ]]; then
  fail "no Android device is connected; check 'adb devices' and pair it again."
  exit 1
fi

say "Connected devices:"
for candidate in "${serials[@]}"; do
  say "  ${candidate}"
done

if [[ -n "${serial}" ]]; then
  if ! printf '%s\n' "${serials[@]}" | grep -Fxq -- "${serial}"; then
    fail "'${serial}' is not connected. Use one of the serials above."
    exit 1
  fi
elif [[ ${#serials[@]} -eq 1 ]]; then
  serial="${serials[0]}"
else
  fail "several devices are connected, so name one with -d <serial>."
  exit 1
fi

# The installed copy and the APK this script builds are signed differently
# whenever one of them is a release build. adb then rejects the install with
# INSTALL_FAILED_UPDATE_INCOMPATIBLE and Flutter uninstalls the app first, on
# its own, taking the conversations and models with it. A release build is
# therefore reported here instead, because the loss is silent otherwise.
installed_flags=$(adb -s "${serial}" shell dumpsys package com.prady.installm 2>/dev/null \
  | awk '/pkgFlags=/ { print; exit }' | tr -d '\r')
if [[ -n "${installed_flags}" ]]; then
  if [[ "${installed_flags}" != *DEBUGGABLE* ]]; then
    if [[ "${allow_data_loss}" -ne 1 ]]; then
      fail "this device holds a release-signed InstaLLM, and installing the debug APK"
      fail "uninstalls it first, deleting its conversations and model files."
      say  "Reinstall a release build instead, or pass --allow-data-loss to accept that."
      exit 1
    fi
    say "warning: the installed release build will be uninstalled, and its data with it."
  else
    say "Installed copy is a debug build, so this replaces it in place."
  fi
fi

# One instance only: the app writes the same conversations, settings and model
# directory, so a second copy would race the first.
if adb -s "${serial}" shell pidof com.prady.installm >/dev/null 2>&1; then
  say "InstaLLM is running on ${serial}; the launch replaces it."
fi

say "Using device: ${serial}"

if [[ "${check_only}" -eq 1 ]]; then
  exit 0
fi

if ! command -v flutter >/dev/null 2>&1; then
  fail "flutter is not on PATH"
  exit 1
fi

cd "${PROJECT_DIR}"
exec flutter run -d "${serial}" ${flutter_args[@]+"${flutter_args[@]}"}
