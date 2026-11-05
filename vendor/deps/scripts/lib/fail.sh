#!/usr/bin/env bash

openmw_fail() {
    local exit_code="${1:-1}"
    local failed_command="${2:-unknown}"
    local script_path="${3:-$0}"
    local profile="${PROFILE:-${DEFAULT_PROFILE:-unknown}}"
    local triplet="${TRIPLET:-${DEFAULT_TRIPLET:-unknown}}"
    local revision="${VCPKG_REVISION:-unknown}"

    trap - ERR

    if [ "${BASH_SUBSHELL:-0}" -gt 0 ]; then
        exit "$exit_code"
    fi

    if [ "${OPENMW_FAIL_REPORTED:-0}" -eq 1 ]; then
        exit "$exit_code"
    fi
    OPENMW_FAIL_REPORTED=1

    echo "ERROR: command failed" >&2
    echo "  script: $script_path" >&2
    echo "  profile: $profile" >&2
    echo "  triplet: $triplet" >&2
    echo "  vcpkg revision: $revision" >&2
    echo "  command: $failed_command" >&2
    echo "  exit code: $exit_code" >&2

    exit "$exit_code"
}

openmw_init_error_trap() {
    if [ "${OPENMW_FAIL_TRAP_ACTIVE:-0}" = "1" ]; then
        return 0
    fi

    OPENMW_FAIL_TRAP_ACTIVE=1
    export OPENMW_FAIL_TRAP_ACTIVE

    set -E
    trap 'openmw_fail "$?" "$BASH_COMMAND" "${BASH_SOURCE[0]:-$0}"' ERR
}
