#!/usr/bin/env bash
# Common helpers for integration test scripts.
# Sourced by other scripts; not executed directly.

set -euo pipefail

# Print a section header for log grouping (GitHub Actions and local).
log_section() {
    printf '\n=== %s ===\n' "$1"
}

# Fail with a message.
die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# Ensure a command exists.
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}
