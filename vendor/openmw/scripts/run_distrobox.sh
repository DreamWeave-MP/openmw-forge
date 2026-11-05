#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BOX_NAME="${BOX_NAME:-openmw-tarball-build}"
OPENMW_SOURCE_ROOT="${OPENMW_SOURCE_ROOT:-}"
OPENMW_BUILD_DIR="${OPENMW_BUILD_DIR:-$BUILDER_ROOT/work/distrobox-build}"
DEPS_PREFIX="${TARBALL_DEPS_PREFIX:-$BUILDER_ROOT/work/distrobox-deps}"
OUTPUT_DIR="${TARBALL_OUTPUT_DIR:-$BUILDER_ROOT/artifacts}"
CLI_DEPS_ARCHIVE="${TARBALL_DEPS_ARCHIVE:-}"
KEEP_BOX=false
BUILD_TYPE="RelWithDebInfo"
FORWARD_ARGS=()

usage() {
    cat <<EOF
Usage: $0 --openmw-source-root <dir> [options]

Build and package OpenMW inside an AlmaLinux distrobox using this standalone builder.

Required unless set by environment:
    --openmw-source-root <dir>  OpenMW source checkout. Env: OPENMW_SOURCE_ROOT

Options:
    --build-dir <dir>          Host build dir. Env: OPENMW_BUILD_DIR
                               Default: $BUILDER_ROOT/work/distrobox-build
    --deps-prefix <dir>        Host deps prefix. Env: TARBALL_DEPS_PREFIX
                               Default: $BUILDER_ROOT/work/distrobox-deps
    --output-dir <dir>         Host output dir. Env: TARBALL_OUTPUT_DIR
                               Default: $BUILDER_ROOT/artifacts
    --deps-archive <path-url>  Local .tar.xz/.7z archive or URL. Env: TARBALL_DEPS_ARCHIVE
    --build-type <value>       Debug, Release, RelWithDebInfo, MinSizeRel, None.
    --clean                    Forward to build_binaries.sh.
    --stage-only               Build and populate package staging only.
    --run-tests                Build and run both GoogleTest suites.
    --gtest-filter VALUE       Select GoogleTest cases.
    --no-prepare               Reuse installed Qt and vcpkg packages.
    --portable                 Forward to assemble_tarball.sh through build_binaries.sh.
    --keep-box                 Reuse existing distrobox instead of recreating.
    --keep-image               Alias for --keep-box.
    -h, --help                 Show this message.
EOF
    exit "${1:-0}"
}

abs_path() {
    local path="$1"
    local dir
    local base
    if [[ "$path" == /* ]]; then
        printf '%s\n' "$path"
        return 0
    fi
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    if [[ -d "$dir" ]]; then
        printf '%s/%s\n' "$(cd "$dir" && pwd)" "$base"
    else
        printf '%s/%s\n' "$PWD" "$path"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --openmw-source-root) OPENMW_SOURCE_ROOT="${2:?--openmw-source-root requires a value}"; shift 2 ;;
        --build-dir)          OPENMW_BUILD_DIR="${2:?--build-dir requires a value}"; shift 2 ;;
        --deps-prefix)        DEPS_PREFIX="${2:?--deps-prefix requires a value}"; shift 2 ;;
        --output-dir)         OUTPUT_DIR="${2:?--output-dir requires a value}"; shift 2 ;;
        --deps-archive)       CLI_DEPS_ARCHIVE="${2:?--deps-archive requires a value}"; shift 2 ;;
        --build-type)         BUILD_TYPE="${2:?--build-type requires a value}"; shift 2 ;;
        --clean|--stage-only|--portable|--no-system-packages|--no-qt|--no-ccache|--run-tests|--no-prepare|--no-compat-check|--no-smoke|--strict-deps)
                              FORWARD_ARGS+=("$1"); shift ;;
        --qt-version|--triplet|--jobs|--cmake-arg|--gtest-filter)
                              FORWARD_ARGS+=("$1" "${2:?$1 requires a value}"); shift 2 ;;
        --keep-box|--keep-image) KEEP_BOX=true; shift ;;
        -h|--help)            usage 0 ;;
        *)                    echo "error: unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -z "$OPENMW_SOURCE_ROOT" ]] && { echo "error: --openmw-source-root or OPENMW_SOURCE_ROOT is required" >&2; usage 1; }

OPENMW_SOURCE_ROOT="$(abs_path "$OPENMW_SOURCE_ROOT")"
OPENMW_BUILD_DIR="$(abs_path "$OPENMW_BUILD_DIR")"
DEPS_PREFIX="$(abs_path "$DEPS_PREFIX")"
OUTPUT_DIR="$(abs_path "$OUTPUT_DIR")"

[[ -f "$OPENMW_SOURCE_ROOT/CMakeLists.txt" ]] || { echo "error: source root missing CMakeLists.txt: $OPENMW_SOURCE_ROOT" >&2; exit 1; }
mkdir -p "$OPENMW_BUILD_DIR" "$DEPS_PREFIX" "$OUTPUT_DIR"

box_exists() {
    distrobox list 2>/dev/null | grep -qE "\|\s*${BOX_NAME}\s*\|"
}

if [[ "$KEEP_BOX" == true ]] && box_exists; then
    echo "=== Reusing existing $BOX_NAME ==="
else
    if box_exists; then
        echo "=== Removing old $BOX_NAME ==="
        distrobox rm --force "$BOX_NAME" 2>/dev/null || true
    fi
    echo "=== Creating fresh $BOX_NAME ==="
    create_args=(
        --yes
        --name "$BOX_NAME"
        --image almalinux:9
        --volume "$BUILDER_ROOT:$BUILDER_ROOT:ro"
        --volume "$OPENMW_SOURCE_ROOT:$OPENMW_SOURCE_ROOT:ro"
        --volume "$OPENMW_BUILD_DIR:$OPENMW_BUILD_DIR:rw"
        --volume "$DEPS_PREFIX:$DEPS_PREFIX:rw"
        --volume "$OUTPUT_DIR:$OUTPUT_DIR:rw"
    )
    if [[ -n "$CLI_DEPS_ARCHIVE" && -f "$CLI_DEPS_ARCHIVE" ]]; then
        CLI_DEPS_ARCHIVE="$(abs_path "$CLI_DEPS_ARCHIVE")"
        create_args+=(--volume "$CLI_DEPS_ARCHIVE:$CLI_DEPS_ARCHIVE:ro")
    fi
    distrobox create "${create_args[@]}"
fi

echo "=== Building + packaging inside $BOX_NAME ==="
cmd=(
    "$SCRIPT_DIR/build_binaries.sh"
    --openmw-source-root "$OPENMW_SOURCE_ROOT"
    --build-dir "$OPENMW_BUILD_DIR"
    --deps-prefix "$DEPS_PREFIX"
    --output-dir "$OUTPUT_DIR"
    --build-type "$BUILD_TYPE"
    --assemble
)
[[ -n "$CLI_DEPS_ARCHIVE" ]] && cmd+=(--deps-archive "$CLI_DEPS_ARCHIVE")
cmd+=("${FORWARD_ARGS[@]}")

distrobox enter "$BOX_NAME" -- bash -e "${cmd[@]}"
