#!/usr/bin/env bash
#
# Runs InstaLLM on Linux, after checking the two things a bare
# `flutter run -d linux` silently trips over.
#
# Why this exists
# ---------------
# 1. Startup reads `.env` through flutter_dotenv and the app exits when it is
#    missing; `.env` is gitignored, so a fresh checkout has `.env.example` only.
# 2. Chat needs the llama.cpp runtime this repository builds into `linux/lib/`
#    (also gitignored). Without it the app still launches and renders, but the
#    runtime reports no loaded library and no model can be opened, which looks
#    like a chat bug rather than a missing build step. `linux/lib` is copied
#    into the bundle by linux/CMakeLists.txt on the next build.
#
# Usage
#   scripts/run_linux.sh                 check prerequisites, then run the app
#   scripts/run_linux.sh --check-only    check prerequisites and stop
#   scripts/run_linux.sh --help
#   scripts/run_linux.sh <args...>       remaining args are passed to `flutter run`
#
# Exits non-zero when a prerequisite is missing or when `flutter run` fails.
# Run it from a terminal, not a pipe, if you want flutter's hot-reload keys.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-${HOME}/flutter-projects/llama.cpp}"

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
fail() { printf 'error: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage
  scripts/run_linux.sh                 check prerequisites, then run the app
  scripts/run_linux.sh --check-only    check prerequisites and stop
  scripts/run_linux.sh --help
  scripts/run_linux.sh <args...>       remaining args are passed to `flutter run`

Environment
  LLAMA_CPP_DIR   llama.cpp checkout used to build linux/lib
                  (default: ~/flutter-projects/llama.cpp)
USAGE
}

# Copies .env.example to .env when startup's required file is absent. Existing
# contents are never overwritten.
ensure_env_file() {
  if [[ -f "${PROJECT_DIR}/.env" ]]; then
    say "Found .env"
    return 0
  fi

  if [[ ! -f "${PROJECT_DIR}/.env.example" ]]; then
    fail "neither .env nor .env.example exists in ${PROJECT_DIR}"
    return 1
  fi

  cp "${PROJECT_DIR}/.env.example" "${PROJECT_DIR}/.env"
  say "Created .env from .env.example"
}

# Reports whether the bundled llama.cpp runtime is present and says exactly how
# to build it when it is not. A missing runtime is a warning rather than an
# error: the UI, settings and model management still work without it.
check_native_runtime() {
  local lib_dir="${PROJECT_DIR}/linux/lib"

  if [[ -f "${lib_dir}/libllama.so" ]]; then
    say "Found llama.cpp runtime in linux/lib"
    if [[ ! -f "${lib_dir}/libmtmd.so" ]]; then
      warn "linux/lib/libmtmd.so is missing: image and audio input will report unavailable."
    fi
    return 0
  fi

  warn "linux/lib/libllama.so is missing, so no model can be opened."
  say  "Build the Linux runtime libraries first:"
  say  "  LLAMA_CPP_DIR=${LLAMA_CPP_DIR} scripts/build_llama_native_libs.sh linux"
  say  "See scripts/BUILD_LINUX.md for the llama.cpp checkout and toolchain it needs."
  if [[ ! -d "${LLAMA_CPP_DIR}" ]]; then
    say  "There is no llama.cpp checkout at ${LLAMA_CPP_DIR} yet."
  fi
  return 0
}

check_only=0
flutter_args=()

for arg in "$@"; do
  case "$arg" in
    --check-only) check_only=1 ;;
    -h|--help) usage; exit 0 ;;
    *) flutter_args+=("$arg") ;;
  esac
done

if [[ "$(uname -s)" != "Linux" ]]; then
  fail "this script runs the Linux target and must be run on a Linux host."
  exit 1
fi

ensure_env_file
check_native_runtime

if [[ "${check_only}" -eq 1 ]]; then
  exit 0
fi

if ! command -v flutter >/dev/null 2>&1; then
  fail "flutter is not on PATH"
  exit 1
fi

cd "${PROJECT_DIR}"
exec flutter run -d linux ${flutter_args[@]+"${flutter_args[@]}"}
