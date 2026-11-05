#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CALLER_DIR="$(pwd)"

OPENMW_SOURCE_ROOT="$HOME/GitHub/openmw"
OPENMW_BUILD_DIR="$BUILDER_ROOT/work/distrobox-build"
DEPS_PREFIX="$BUILDER_ROOT/work/distrobox-deps"
OUTPUT_DIR="$BUILDER_ROOT/artifacts"
BOX_NAME="${BOX_NAME:-openmw-tarball-build}"
JOBS="${JOBS:-3}"
RUN_TESTS=false
GTEST_FILTER="${GTEST_FILTER:-*}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-tests) RUN_TESTS=true; shift ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--run-tests]

Build and stage the local OpenMW package inside the existing distrobox.

Options:
    --run-tests  Configure and run openmw-tests and components-tests after
                 the normal build. GTEST_FILTER controls the executed tests;
                 the default is * (all tests).
    -h, --help   Show this message.
EOF
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

[[ -f "$OPENMW_SOURCE_ROOT/CMakeLists.txt" ]] || {
    echo "error: OpenMW source checkout not found at $OPENMW_SOURCE_ROOT" >&2
    exit 1
}

command -v distrobox >/dev/null 2>&1 || {
    echo "error: distrobox is required; local staging builds always run inside distrobox" >&2
    exit 1
}

find_deps_archive() {
    local source_tar="$OPENMW_SOURCE_ROOT/vcpkg-x64-linux-dynamic.tar.xz"
    local builder_tar="$BUILDER_ROOT/vcpkg-x64-linux-dynamic.tar.xz"
    local source_7z="$OPENMW_SOURCE_ROOT/vcpkg-x64-linux-dynamic.7z"
    local builder_7z="$BUILDER_ROOT/vcpkg-x64-linux-dynamic.7z"

    if [[ -f "$source_tar" ]]; then
        printf '%s\n' "$source_tar"
    elif [[ -f "$builder_tar" ]]; then
        printf '%s\n' "$builder_tar"
    elif [[ -f "$source_7z" ]]; then
        printf '%s\n' "$source_7z"
    elif [[ -f "$builder_7z" ]]; then
        printf '%s\n' "$builder_7z"
    fi
}

box_exists() {
    distrobox list 2>/dev/null | grep -qE "\|\s*${BOX_NAME}\s*\|"
}

run_tests() {
    echo "=== Building and running OpenMW tests ==="
    distrobox enter "$BOX_NAME" -- env \
        "OPENMW_TEST_SCRIPT_DIR=$SCRIPT_DIR" \
        "OPENMW_TEST_SOURCE_ROOT=$OPENMW_SOURCE_ROOT" \
        "OPENMW_TEST_BUILD_DIR=$OPENMW_BUILD_DIR" \
        "OPENMW_TEST_DEPS_PREFIX=$DEPS_PREFIX" \
        "OPENMW_TEST_JOBS=$JOBS" \
        "OPENMW_TEST_FILTER=$GTEST_FILTER" \
        bash -s <<'EOF'
set -euo pipefail

SCRIPT_DIR="$OPENMW_TEST_SCRIPT_DIR"
OPENMW_SOURCE_ROOT="$OPENMW_TEST_SOURCE_ROOT"
OPENMW_BUILD_DIR="$OPENMW_TEST_BUILD_DIR"
DEPS_PREFIX="$OPENMW_TEST_DEPS_PREFIX"
JOBS="$OPENMW_TEST_JOBS"
GTEST_FILTER="$OPENMW_TEST_FILTER"
source "$SCRIPT_DIR/../config/deps_versions.sh"

if command -v scl_source >/dev/null 2>&1; then
    set +u
    source scl_source enable gcc-toolset-13
    set -u
fi

export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"

"$SCRIPT_DIR/configure_openmw.sh" \
    --openmw-source-root "$OPENMW_SOURCE_ROOT" \
    --build-dir "$OPENMW_BUILD_DIR" \
    --deps-prefix "$DEPS_PREFIX" \
    --build-type RelWithDebInfo \
    --cmake-arg "-DBUILD_OPENMW_TESTS=ON" \
    --cmake-arg "-DBUILD_COMPONENTS_TESTS=ON"

cmake --build "$OPENMW_BUILD_DIR" --target openmw-tests components-tests -- -j"$JOBS"
LD_LIBRARY_PATH="$DEPS_PREFIX/openmw-deps/installed/$VCPKG_TARGET_TRIPLET/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$OPENMW_BUILD_DIR/openmw-tests" "--gtest_filter=$GTEST_FILTER"
LD_LIBRARY_PATH="$DEPS_PREFIX/openmw-deps/installed/$VCPKG_TARGET_TRIPLET/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$OPENMW_BUILD_DIR/components-tests" "--gtest_filter=$GTEST_FILTER"
EOF
}

echo "=== Local OpenMW staging build ==="
echo "  source:  $OPENMW_SOURCE_ROOT"
echo "  build:   $OPENMW_BUILD_DIR"
echo "  deps:    $DEPS_PREFIX"
echo "  output:  $OUTPUT_DIR"
echo "  result:  $CALLER_DIR"
echo "  box:     $BOX_NAME"
echo "  jobs:    $JOBS"
echo "  mode:    distrobox-only"

if [[ -f "$OPENMW_BUILD_DIR/CMakeCache.txt" && -d "$DEPS_PREFIX/openmw-deps" ]] && box_exists; then
    echo "=== Reusing configured build tree inside $BOX_NAME ==="
    distrobox enter "$BOX_NAME" -- bash -lc "
        set -euo pipefail
        if command -v scl_source >/dev/null 2>&1; then
            set +u
            source scl_source enable gcc-toolset-13
            set -u
        fi
        cmake --build '$OPENMW_BUILD_DIR' -- -j'$JOBS'
        '$SCRIPT_DIR/assemble_tarball.sh' \
            --openmw-source-root '$OPENMW_SOURCE_ROOT' \
            --build-dir '$OPENMW_BUILD_DIR' \
            --deps-prefix '$DEPS_PREFIX' \
            --output-dir '$OUTPUT_DIR' \
            --stage-only
    "
else
    echo "=== Bootstrapping build tree inside distrobox ==="
    DEPS_ARCHIVE="$(find_deps_archive || true)"
    [[ -n "$DEPS_ARCHIVE" ]] && echo "  archive: $DEPS_ARCHIVE"
    cmd=(
        "$SCRIPT_DIR/run_distrobox.sh"
        --openmw-source-root "$OPENMW_SOURCE_ROOT"
        --build-dir "$OPENMW_BUILD_DIR"
        --deps-prefix "$DEPS_PREFIX"
        --output-dir "$OUTPUT_DIR"
        --keep-box
        --jobs "$JOBS"
        --stage-only
    )
    [[ -n "$DEPS_ARCHIVE" ]] && cmd+=(--deps-archive "$DEPS_ARCHIVE")
    "${cmd[@]}"
fi

if [[ "$RUN_TESTS" == true ]]; then
    run_tests
fi

STAGING_ROOT="$OPENMW_BUILD_DIR/package-staging"
mapfile -t STAGED_DIRS < <(find "$STAGING_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'openmw-*-Linux-64Bit*' | sort)

if [[ "${#STAGED_DIRS[@]}" -ne 1 ]]; then
    echo "error: expected exactly one staged package under $STAGING_ROOT, found ${#STAGED_DIRS[@]}" >&2
    exit 1
fi

STAGED_DIR="${STAGED_DIRS[0]}"
PACKAGE_NAME="$(basename "$STAGED_DIR")"
DEST_DIR="$CALLER_DIR/$PACKAGE_NAME"

if [[ "$DEST_DIR" == "$STAGED_DIR" ]]; then
    echo "=== Staging build complete ==="
    echo "Staged package already in current directory: $DEST_DIR"
    exit 0
fi

echo "=== Moving staged package to current directory ==="
if [[ -e "$DEST_DIR" || -L "$DEST_DIR" ]]; then
    echo "Removing existing staged package: $DEST_DIR"
    rm -rf -- "$DEST_DIR"
fi
if [[ -e "$DEST_DIR" || -L "$DEST_DIR" ]]; then
    echo "error: failed to remove existing staged package: $DEST_DIR" >&2
    exit 1
fi
mv -- "$STAGED_DIR" "$DEST_DIR"

echo "=== Staging build complete ==="
echo "Staged package: $DEST_DIR"
