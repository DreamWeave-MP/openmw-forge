#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/fail.sh
source "$SCRIPT_DIR/lib/fail.sh"
openmw_init_error_trap
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

MODE="${MODE:-distrobox}"
OUTPUT_DIR="${OUTPUT_DIR:-$OPENMW_DEPS_REPO_ROOT}"
NETWORK_CHECK=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --network-check)
            NETWORK_CHECK=1
            shift
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            echo "Usage: $0 [--mode distrobox|container|core] [--output-dir DIR] [--network-check]" >&2
            exit 1
            ;;
    esac
done

pass_count=0
fail_count=0

check_ok() {
    local message="$1"
    echo "[PASS] $message"
    pass_count=$((pass_count + 1))
}

check_fail() {
    local message="$1"
    echo "[FAIL] $message"
    fail_count=$((fail_count + 1))
}

check_command() {
    local cmd="$1"
    local label="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        check_ok "$label"
    else
        check_fail "$label (missing command: $cmd)"
    fi
}

echo "Running dependency build doctor"
echo "  profile: $PROFILE"
echo "  mode: $MODE"
echo "  triplet: ${TRIPLET:-$DEFAULT_TRIPLET}"
echo "  output dir: $OUTPUT_DIR"
echo "  image: $BUILD_IMAGE"
echo "  vcpkg revision: $VCPKG_REVISION"

check_command bash "bash is available"
check_command git "git is available"
check_command curl "curl is available"
if [ -n "$OPENMW_DEPS_7ZIP_CMD" ]; then
    check_ok "7zip command is available ($OPENMW_DEPS_7ZIP_CMD)"
else
    check_fail "7zip command is not available (tried: 7z, 7zz, 7za)"
fi

if [ -d "$OUTPUT_DIR" ]; then
    if [ -w "$OUTPUT_DIR" ]; then
        check_ok "output directory is writable"
    else
        check_fail "output directory is not writable: $OUTPUT_DIR"
    fi
else
    output_parent="$(dirname "$OUTPUT_DIR")"
    if [ -d "$output_parent" ] && [ -w "$output_parent" ]; then
        check_ok "output directory parent is writable (directory can be created)"
    else
        check_fail "output directory parent is not writable: $output_parent"
    fi
fi

if [ -x "$SCRIPT_DIR/build-all.sh" ] && [ -x "$SCRIPT_DIR/verify-build.sh" ]; then
    check_ok "core scripts are present and executable"
else
    check_fail "core scripts are missing or not executable"
fi

case "$MODE" in
    distrobox)
        check_command distrobox "distrobox is available"
        engine="${CONTAINER_ENGINE:-podman}"
        if command -v "$engine" >/dev/null 2>&1; then
            check_ok "container engine is available ($engine)"
        else
            check_fail "container engine is not available for Dockerfile builds in distrobox mode: $engine"
        fi
        ;;
    container)
        engine="${CONTAINER_ENGINE:-}"
        if [ -z "$engine" ]; then
            if command -v podman >/dev/null 2>&1; then
                engine="podman"
            elif command -v docker >/dev/null 2>&1; then
                engine="docker"
            fi
        fi

        if [ -n "$engine" ] && command -v "$engine" >/dev/null 2>&1; then
            check_ok "container engine is available ($engine)"
        else
            check_fail "no supported container engine found (set CONTAINER_ENGINE or install podman/docker)"
        fi
        ;;
    core)
        if [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
            check_ok "root privilege path is available (root or sudo)"
        else
            check_fail "neither root nor sudo is available for system dependency installation"
        fi
        ;;
    *)
        check_fail "unsupported mode '$MODE' (use distrobox, container, or core)"
        ;;
esac

if [ "$NETWORK_CHECK" -eq 1 ]; then
    network_urls=(
        "$BUILD_AUTOCONF_URL"
        "https://github.com/microsoft/vcpkg.git"
    )

    for url in "${network_urls[@]}"; do
        if curl -fsI --max-time 15 "$url" >/dev/null; then
            check_ok "network reachability: $url"
        else
            check_fail "network reachability failed: $url"
        fi
    done
fi

echo "Doctor summary: $pass_count passed, $fail_count failed"

if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
