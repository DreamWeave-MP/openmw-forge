#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="$SCRIPT_DIR/test_tarball.sh"

TARBALL=""
WITH_QT=false
KEEP_BOXES=false
KEEP_IMAGES=false
DISTRO_FILTER=""
OUTPUT_DIR=""
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
MOUNT_ROOT=""

usage() {
    cat <<EOF
Usage: $0 [options] <tarball.tar.gz>

Run tests/test_tarball.sh inside fresh distroboxes for several target distros.

Options:
    --with-qt              Forward --with-qt to test_tarball.sh. Requires a
                           working display backend such as X11, Wayland, or Xvfb.
    --distros <list>       Comma-separated subset of distro tags to run.
    --output-dir <path>    Where to collect RESULTS_*.tar.gz archives.
                           Default: directory of input tarball.
    --keep-boxes           Do not remove distrobox instances after each run.
    --keep-images          Do not remove pulled container images after each run.
    --container-engine <c> Container CLI used only for image cleanup.
                           Default: podman.
    -h, --help             Show this message.
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-qt)          WITH_QT=true; shift ;;
        --distros)          DISTRO_FILTER="${2:?--distros requires a value}"; shift 2 ;;
        --output-dir)       OUTPUT_DIR="${2:?--output-dir requires a value}"; shift 2 ;;
        --keep-boxes)       KEEP_BOXES=true; shift ;;
        --keep-images)      KEEP_IMAGES=true; shift ;;
        --container-engine) CONTAINER_ENGINE="${2:?--container-engine requires a value}"; shift 2 ;;
        -h|--help)          usage 0 ;;
        -*)                 echo "error: unknown option: $1" >&2; usage 1 ;;
        *)                  TARBALL="$1"; shift ;;
    esac
done

[[ -z "$TARBALL" ]] && { echo "error: tarball path is required" >&2; usage 1; }
[[ ! -f "$TARBALL" ]] && { echo "error: $TARBALL is not a file" >&2; exit 1; }
[[ ! -x "$TEST_SCRIPT" ]] && { echo "error: $TEST_SCRIPT is not executable" >&2; exit 1; }

TARBALL="$(readlink -f "$TARBALL")"
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="$(dirname "$TARBALL")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

cleanup_mount_root() {
    if [[ -n "$MOUNT_ROOT" ]]; then
        rm -rf "$MOUNT_ROOT"
    fi
}
trap cleanup_mount_root EXIT

MOUNT_ROOT="$(mktemp -d "$OUTPUT_DIR/.multi-distro-mounts.XXXXXXXX")"
if ! ln -f "$TARBALL" "$MOUNT_ROOT/input.tar.gz" 2>/dev/null; then
    cp "$TARBALL" "$MOUNT_ROOT/input.tar.gz"
fi
cp "$TEST_SCRIPT" "$MOUNT_ROOT/test_tarball.sh"
chmod +x "$MOUNT_ROOT/test_tarball.sh"

APT_BOOTSTRAP='apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libgl1'
DNF_BOOTSTRAP='dnf install -y -q mesa-libGL'
DISTROS=(
    "almalinux-9|almalinux:9|$DNF_BOOTSTRAP|native floor proxy"
    "debian-12|debian:12|$APT_BOOTSTRAP|Debian 12"
    "debian-13|debian:trixie|$APT_BOOTSTRAP|Debian 13"
    "ubuntu-22.04|ubuntu:22.04|$APT_BOOTSTRAP|Linux Mint 21.x proxy"
    "ubuntu-24.04|ubuntu:24.04|$APT_BOOTSTRAP|Ubuntu 24.04"
    "fedora-41|fedora:41|$DNF_BOOTSTRAP|Fedora 41"
    "fedora-latest|fedora:latest|$DNF_BOOTSTRAP|Fedora latest"
    "archlinux|archlinux:latest|pacman -Sy --noconfirm --needed libglvnd|Arch/Endeavour/Cachy proxy"
    "opensuse-tumbleweed|opensuse/tumbleweed|zypper --non-interactive --quiet install Mesa-libGL1|openSUSE Tumbleweed"
    "voidlinux|ghcr.io/void-linux/void-glibc-full:latest|xbps-install -Sy libglvnd|Void Linux glibc"
)

if [[ -n "$DISTRO_FILTER" ]]; then
    IFS=',' read -r -a REQUESTED_DISTROS <<< "$DISTRO_FILTER"
    UNKNOWN_DISTROS=()
    for requested_tag in "${REQUESTED_DISTROS[@]}"; do
        found=false
        for entry in "${DISTROS[@]}"; do
            IFS='|' read -r tag _image _bootstrap _note <<< "$entry"
            if [[ "$requested_tag" == "$tag" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" != true ]]; then
            UNKNOWN_DISTROS+=("${requested_tag:-<empty>}")
        fi
    done

    if [[ "${#UNKNOWN_DISTROS[@]}" -gt 0 ]]; then
        echo "error: unknown distro tag(s): ${UNKNOWN_DISTROS[*]}" >&2
        exit 1
    fi
fi

filter_matches() {
    local tag="$1"
    [[ -z "$DISTRO_FILTER" ]] && return 0
    case ",$DISTRO_FILTER," in
        *",$tag,"*) return 0 ;;
        *) return 1 ;;
    esac
}

TOTAL=0
PASSED=()
FAILED=()
SKIPPED=()
SELECTED_DISTROS=()

for entry in "${DISTROS[@]}"; do
    IFS='|' read -r tag _image _bootstrap _note <<< "$entry"
    filter_matches "$tag" || continue
    SELECTED_DISTROS+=("$entry")
done

if [[ "${#SELECTED_DISTROS[@]}" -eq 0 ]]; then
    if [[ -n "$DISTRO_FILTER" ]]; then
        echo "error: --distros selected no known distro tags: $DISTRO_FILTER" >&2
    else
        echo "error: no distro targets are configured" >&2
    fi
    exit 1
fi

if ! command -v distrobox >/dev/null 2>&1; then
    echo "error: distrobox is required but was not found in PATH" >&2
    exit 1
fi

for entry in "${SELECTED_DISTROS[@]}"; do
    IFS='|' read -r tag image bootstrap note <<< "$entry"
    TOTAL=$((TOTAL + 1))
    box_name="openmw-smoketest-$tag"

    echo "========================================================"
    echo " [$tag] $image"
    echo " $note"
    echo "========================================================"

    distrobox rm --force "$box_name" >/dev/null 2>&1 || true
    create_args=(
        --yes
        --name "$box_name"
        --image "$image"
        --volume "$MOUNT_ROOT:/openmw-smoke/input:ro"
        --volume "$OUTPUT_DIR:/openmw-smoke/output:rw"
    )
    if ! distrobox create "${create_args[@]}" >/dev/null 2>&1; then
        echo "  SKIP: could not create $box_name"
        SKIPPED+=("$tag")
        continue
    fi

    work_dir="/var/tmp/openmw-smoke-work-$tag"
    qt_flag=""
    [[ "$WITH_QT" == true ]] && qt_flag="--with-qt"

    echo "--- Bootstrapping $box_name ---"
    if ! distrobox enter "$box_name" -- bash -c "sudo sh -c \"$bootstrap\"" >/dev/null 2>&1; then
        echo "  SKIP: bootstrap failed"
        SKIPPED+=("$tag")
        [[ "$KEEP_BOXES" != true ]] && distrobox rm --force "$box_name" >/dev/null 2>&1 || true
        continue
    fi

    echo "--- Running smoke test inside $box_name ---"
    rc=0
    if distrobox enter "$box_name" -- bash -c "
        set -e
        rm -rf '$work_dir'
        mkdir -p '$work_dir'
        cd '$work_dir'
        '/openmw-smoke/input/test_tarball.sh' $qt_flag --output-dir '/openmw-smoke/output' '/openmw-smoke/input/input.tar.gz'
    "; then
        rc=0
    else
        rc=$?
    fi

    if [[ $rc -eq 0 ]]; then
        echo "  PASS: $tag"
        PASSED+=("$tag")
    else
        echo "  FAIL: $tag (exit $rc)"
        FAILED+=("$tag")
    fi

    distrobox enter "$box_name" -- rm -rf "$work_dir" >/dev/null 2>&1 || true

    if [[ "$KEEP_BOXES" != true ]]; then
        distrobox rm --force "$box_name" >/dev/null 2>&1 || true
    fi

    if [[ "$KEEP_IMAGES" != true ]]; then
        "$CONTAINER_ENGINE" rmi "$image" >/dev/null 2>&1 || echo "  (image still in use, left alone)"
    fi
done

echo "========================================================"
echo " Summary"
echo "========================================================"
echo "  Total attempted: $TOTAL"
echo "  Passed:          ${#PASSED[@]} ${PASSED[*]:-}"
echo "  Failed:          ${#FAILED[@]} ${FAILED[*]:-}"
echo "  Skipped:         ${#SKIPPED[@]} ${SKIPPED[*]:-}"
echo "  Results in:      $OUTPUT_DIR"

if [[ ${#FAILED[@]} -gt 0 || ${#SKIPPED[@]} -gt 0 ]]; then
    exit 1
fi
exit 0
