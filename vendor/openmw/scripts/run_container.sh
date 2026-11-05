#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

IMAGE_NAME="${IMAGE_NAME:-openmw-standalone-tarball}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
OPENMW_SOURCE_ROOT="${OPENMW_SOURCE_ROOT:-}"
OPENMW_BUILD_DIR="${OPENMW_BUILD_DIR:-$BUILDER_ROOT/work/container-build}"
DEPS_PREFIX="${TARBALL_DEPS_PREFIX:-$BUILDER_ROOT/work/container-deps}"
OUTPUT_DIR="${TARBALL_OUTPUT_DIR:-$BUILDER_ROOT/artifacts}"
CLI_DEPS_ARCHIVE="${TARBALL_DEPS_ARCHIVE:-}"
BUILD_TYPE="RelWithDebInfo"
KEEP_IMAGE=false
FORWARD_ARGS=()

usage() {
    cat <<EOF
Usage: $0 --openmw-source-root <dir> [options]

Build and package OpenMW in a podman/docker container using this standalone builder.

Required unless set by environment:
    --openmw-source-root <dir>  OpenMW source checkout. Env: OPENMW_SOURCE_ROOT

Options:
    --build-dir <dir>          Host build dir. Env: OPENMW_BUILD_DIR
                               Default: $BUILDER_ROOT/work/container-build
    --deps-prefix <dir>        Host deps prefix. Env: TARBALL_DEPS_PREFIX
                               Default: $BUILDER_ROOT/work/container-deps
    --output-dir <dir>         Host output dir. Env: TARBALL_OUTPUT_DIR
                               Default: $BUILDER_ROOT/artifacts
    --deps-archive <path-url>  Local .tar.xz/.7z archive or URL. Env: TARBALL_DEPS_ARCHIVE
    --build-type <value>       Debug, Release, RelWithDebInfo, MinSizeRel, None.
    --clean                    Forward to build_binaries.sh.
    --portable                 Forward to assemble_tarball.sh through build_binaries.sh.
    --keep-image               Do not remove the built container image.
    -h, --help                 Show this message.

Environment:
    CONTAINER_ENGINE           podman or docker (default: podman)
    IMAGE_NAME                 Build image name (default: openmw-standalone-tarball)
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
        --clean|--portable|--no-system-packages|--no-qt|--no-ccache)
                              FORWARD_ARGS+=("$1"); shift ;;
        --qt-version|--triplet|--jobs|--cmake-arg)
                              FORWARD_ARGS+=("$1" "${2:?$1 requires a value}"); shift 2 ;;
        --keep-image)         KEEP_IMAGE=true; shift ;;
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

echo "=== Building image ($CONTAINER_ENGINE) ==="
"$CONTAINER_ENGINE" build \
    -t "$IMAGE_NAME" \
    -f "$BUILDER_ROOT/docker/Dockerfile.tarball" \
    "$BUILDER_ROOT"

run_args=(
    --rm
    -v "$OPENMW_SOURCE_ROOT:/src:ro,z"
    -v "$OPENMW_BUILD_DIR:/build:Z"
    -v "$DEPS_PREFIX:/deps:Z"
    -v "$OUTPUT_DIR:/out:Z"
)

container_archive=""
if [[ -n "$CLI_DEPS_ARCHIVE" ]]; then
    if [[ -f "$CLI_DEPS_ARCHIVE" ]]; then
        CLI_DEPS_ARCHIVE="$(abs_path "$CLI_DEPS_ARCHIVE")"
        archive_name="$(basename "$CLI_DEPS_ARCHIVE")"
        run_args+=(-v "$CLI_DEPS_ARCHIVE:/input/$archive_name:ro,z")
        container_archive="/input/$archive_name"
    else
        container_archive="$CLI_DEPS_ARCHIVE"
    fi
fi

cmd=(
    /builder/scripts/build_binaries.sh
    --openmw-source-root /src
    --build-dir /build
    --deps-prefix /deps
    --output-dir /out
    --build-type "$BUILD_TYPE"
    --assemble
)
[[ -n "$container_archive" ]] && cmd+=(--deps-archive "$container_archive")
cmd+=("${FORWARD_ARGS[@]}")

echo "=== Building + packaging inside container ==="
"$CONTAINER_ENGINE" run "${run_args[@]}" "$IMAGE_NAME" "${cmd[@]}"

if [[ "$KEEP_IMAGE" == true ]]; then
    echo "=== Keeping image $IMAGE_NAME for layer cache reuse ==="
else
    echo "=== Removing image $IMAGE_NAME ==="
    "$CONTAINER_ENGINE" rmi "$IMAGE_NAME"
fi

echo "Output: $OUTPUT_DIR/"
ls "$OUTPUT_DIR"/openmw-*-Linux-64Bit*.tar.gz 2>/dev/null || true
