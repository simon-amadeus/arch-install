#!/usr/bin/env bash
# Logging, error handling, and small utilities shared across bootstrap libs.
#
# Source this from any other lib. It assumes set -Eeuo pipefail in the caller.

# shellcheck disable=SC2034
LOG_FILE="${LOG_FILE:-/tmp/arch-install.log}"

_ts() { date '+%H:%M:%S'; }

log()  { printf '[%s] %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; }
warn() { printf '[%s] WARN: %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; }
die()  { printf '[%s] FATAL: %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

# Print the failing command's location when set -E + trap ERR is active.
on_err() {
    local exit_code=$?
    local line=${1:-?}
    warn "command failed (exit ${exit_code}) at line ${line}${BASH_COMMAND:+: ${BASH_COMMAND}}"
    warn "see ${LOG_FILE} for full output"
    exit "$exit_code"
}

confirm() {
    local prompt="$1" answer
    printf '%s [type YES to proceed]: ' "${prompt}"
    read -r answer
    [[ "$answer" == "YES" ]] || die "aborted by user"
}

require_root() {
    [[ $EUID -eq 0 ]] || die "must run as root"
}

require_cmd() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
    done
}

# Wait for a path to exist. Useful after partitioning/luksFormat.
wait_for_path() {
    local path="$1" timeout="${2:-10}" elapsed=0
    while [[ ! -e "$path" ]]; do
        sleep 1
        elapsed=$((elapsed + 1))
        if (( elapsed >= timeout )); then
            die "timed out waiting for ${path}"
        fi
    done
}
