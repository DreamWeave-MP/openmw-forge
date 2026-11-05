#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OPENMW_SOURCE_ROOT="${OPENMW_SOURCE_ROOT:-}"
OPENMW_BUILD_DIR="${OPENMW_BUILD_DIR:-$BUILDER_ROOT/work/build}"
DEPS_PREFIX="${TARBALL_DEPS_PREFIX:-$BUILDER_ROOT/work/deps}"
OUTPUT_DIR="${TARBALL_OUTPUT_DIR:-$BUILDER_ROOT/artifacts}"
CLI_DEPS_ARCHIVE="${TARBALL_DEPS_ARCHIVE:-}"
BUILD_TYPE="${CMAKE_BUILD_TYPE:-RelWithDebInfo}"
CLEAN_BUILD=false
RUN_PREPARE=true
RUN_ASSEMBLE=false
STAGE_ONLY=false
PORTABLE=false
JOBS="$(nproc)"
PREPARE_ARGS=()
CONFIGURE_ARGS=()

usage() {
    cat <<EOF
Usage: $0 --openmw-source-root <dir> [options]

Prepare dependencies, configure, and build OpenMW for portable Linux tarballs.

Required unless set by environment:
    --openmw-source-root <dir>  OpenMW source checkout. Env: OPENMW_SOURCE_ROOT

Path options:
    --build-dir <dir>          CMake build directory. Env: OPENMW_BUILD_DIR
                               Default: $BUILDER_ROOT/work/build
    --deps-prefix <dir>        Prefix containing/extracting deps and Qt.
                               Env: TARBALL_DEPS_PREFIX
                               Default: $BUILDER_ROOT/work/deps
    --output-dir <dir>         Output dir when --assemble is used.
                               Env: TARBALL_OUTPUT_DIR
                               Default: $BUILDER_ROOT/artifacts
    --deps-archive <path-url>  Local .tar.xz/.7z deps archive or URL.
                               Env: TARBALL_DEPS_ARCHIVE

Build options:
    --clean                    Wipe --build-dir before configuring.
    --debug                    Alias for --build-type Debug.
    --build-type <value>       Debug, Release, RelWithDebInfo, MinSizeRel, None.
    --jobs <n>                 Parallel build jobs. Default: nproc.
    --no-prepare               Skip scripts/prepare_deps.sh.
    --assemble                 Run scripts/assemble_tarball.sh after build.
    --stage-only               Populate package staging only; implies --assemble.
    --portable                 Forward portable mode to assembly.
    --no-system-packages       Forward to prepare_deps.sh.
    --no-qt                    Forward to prepare_deps.sh.
    --qt-version <ver>         Forward to prepare_deps.sh/configure defaults.
    --triplet <value>          Forward to configure_openmw.sh.
    --no-ccache                Forward to configure_openmw.sh.
    --cmake-arg <arg>          Forward raw arg to configure_openmw.sh. Repeatable.
    -h, --help                 Show this message.
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --openmw-source-root) OPENMW_SOURCE_ROOT="${2:?--openmw-source-root requires a value}"; shift 2 ;;
        --build-dir)          OPENMW_BUILD_DIR="${2:?--build-dir requires a value}"; shift 2 ;;
        --deps-prefix)        DEPS_PREFIX="${2:?--deps-prefix requires a value}"; shift 2 ;;
        --output-dir)         OUTPUT_DIR="${2:?--output-dir requires a value}"; shift 2 ;;
        --deps-archive)       CLI_DEPS_ARCHIVE="${2:?--deps-archive requires a value}"; shift 2 ;;
        --clean)              CLEAN_BUILD=true; shift ;;
        --debug)              BUILD_TYPE=Debug; shift ;;
        --build-type)         BUILD_TYPE="${2:?--build-type requires a value}"; shift 2 ;;
        --jobs)               JOBS="${2:?--jobs requires a value}"; shift 2 ;;
        --no-prepare)         RUN_PREPARE=false; shift ;;
        --assemble)           RUN_ASSEMBLE=true; shift ;;
        --stage-only)         RUN_ASSEMBLE=true; STAGE_ONLY=true; shift ;;
        --portable)           PORTABLE=true; shift ;;
        --no-system-packages|--no-qt)
                              PREPARE_ARGS+=("$1"); shift ;;
        --qt-version)
                              PREPARE_ARGS+=("$1" "${2:?--qt-version requires a value}"); shift 2 ;;
        --triplet|--cmake-arg)
                              CONFIGURE_ARGS+=("$1" "${2:?$1 requires a value}"); shift 2 ;;
        --no-ccache|--build-tests-only|--build-openmw-only)
                              CONFIGURE_ARGS+=("$1"); shift ;;
        -h|--help)            usage 0 ;;
        *)                    echo "error: unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -z "$OPENMW_SOURCE_ROOT" ]] && { echo "error: --openmw-source-root or OPENMW_SOURCE_ROOT is required" >&2; usage 1; }

case "$BUILD_TYPE" in
    Debug|Release|RelWithDebInfo|MinSizeRel|None) ;;
    *) echo "error: unsupported build type '$BUILD_TYPE'." >&2; exit 1 ;;
esac

if [[ "$RUN_PREPARE" == true ]]; then
    echo "=== Stage 1: Prepare deps ==="
    prepare_cmd=("$SCRIPT_DIR/prepare_deps.sh" --deps-prefix "$DEPS_PREFIX")
    [[ -n "$CLI_DEPS_ARCHIVE" ]] && prepare_cmd+=(--deps-archive "$CLI_DEPS_ARCHIVE")
    prepare_cmd+=("${PREPARE_ARGS[@]}")
    "${prepare_cmd[@]}"
fi

if [[ "$CLEAN_BUILD" == true ]]; then
    echo "=== Cleaning build dir: $OPENMW_BUILD_DIR ==="
    rm -rf "$OPENMW_BUILD_DIR"
fi
mkdir -p "$OPENMW_BUILD_DIR/tmp"
export TMPDIR="$OPENMW_BUILD_DIR/tmp"
export CMAKE_BUILD_TYPE="$BUILD_TYPE"

if command -v scl_source >/dev/null 2>&1; then
    set +u
    source scl_source enable gcc-toolset-13
    set -u
fi
export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"

echo "=== Stage 2: Configure ==="
"$SCRIPT_DIR/configure_openmw.sh" \
    --openmw-source-root "$OPENMW_SOURCE_ROOT" \
    --build-dir "$OPENMW_BUILD_DIR" \
    --deps-prefix "$DEPS_PREFIX" \
    --build-type "$BUILD_TYPE" \
    "${CONFIGURE_ARGS[@]}"

echo "=== Stage 3: Build ==="
cmake --build "$OPENMW_BUILD_DIR" -- -j"$JOBS"

if [[ "$RUN_ASSEMBLE" == true ]]; then
    echo "=== Stage 4: Assemble tarball ==="
    assemble_cmd=(
        "$SCRIPT_DIR/assemble_tarball.sh"
        --openmw-source-root "$OPENMW_SOURCE_ROOT"
        --build-dir "$OPENMW_BUILD_DIR"
        --deps-prefix "$DEPS_PREFIX"
        --output-dir "$OUTPUT_DIR"
        --build-type "$BUILD_TYPE"
    )
    [[ "$PORTABLE" == true ]] && assemble_cmd+=(--portable)
    [[ "$STAGE_ONLY" == true ]] && assemble_cmd+=(--stage-only)
    "${assemble_cmd[@]}"
fi

echo "=== Done ==="
echo "Build complete. Binaries are in $OPENMW_BUILD_DIR"
