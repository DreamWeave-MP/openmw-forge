#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../config/deps_versions.sh
source "$BUILDER_ROOT/config/deps_versions.sh"

OPENMW_SOURCE_ROOT="${OPENMW_SOURCE_ROOT:-}"
OPENMW_BUILD_DIR="${OPENMW_BUILD_DIR:-$BUILDER_ROOT/work/build}"
DEPS_PREFIX="${TARBALL_DEPS_PREFIX:-$BUILDER_ROOT/work/deps}"
DEPS_DIR=""
QT_DIR=""
BUILD_TYPE="${CMAKE_BUILD_TYPE:-RelWithDebInfo}"
USE_CCACHE=true
BUILD_TESTS_ONLY="${BUILD_TESTS_ONLY:-}"
BUILD_OPENMW_ONLY="${BUILD_OPENMW_ONLY:-}"
EXTRA_CMAKE_ARGS=()

usage() {
    cat <<EOF
Usage: $0 --openmw-source-root <dir> [options]

Configure an arbitrary OpenMW source tree for the standalone Linux tarball build.

Required unless set by environment:
    --openmw-source-root <dir>  OpenMW source checkout. Env: OPENMW_SOURCE_ROOT

Options:
    --build-dir <dir>          CMake build directory. Env: OPENMW_BUILD_DIR
                               Default: $BUILDER_ROOT/work/build
    --deps-prefix <dir>        Prefix containing openmw-deps/ and QT/.
                               Env: TARBALL_DEPS_PREFIX
                               Default: $BUILDER_ROOT/work/deps
    --deps-dir <dir>           vcpkg installed triplet dir. Overrides --deps-prefix.
    --qt-dir <dir>             Qt install dir. Overrides --deps-prefix derived path.
    --build-type <value>       Debug, Release, RelWithDebInfo, MinSizeRel, None.
                               Default: RelWithDebInfo
    --triplet <value>          vcpkg triplet. Default: $VCPKG_TARGET_TRIPLET
    --no-ccache                Do not configure compiler launchers.
    --build-tests-only         Configure OpenMW test/benchmark targets only.
    --build-openmw-only        Configure only the openmw binary target.
    --cmake-arg <arg>          Append one raw CMake configure argument. Repeatable.
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
        --deps-dir)           DEPS_DIR="${2:?--deps-dir requires a value}"; shift 2 ;;
        --qt-dir)             QT_DIR="${2:?--qt-dir requires a value}"; shift 2 ;;
        --build-type)         BUILD_TYPE="${2:?--build-type requires a value}"; shift 2 ;;
        --triplet)            VCPKG_TARGET_TRIPLET="${2:?--triplet requires a value}"; shift 2 ;;
        --no-ccache)          USE_CCACHE=false; shift ;;
        --build-tests-only)   BUILD_TESTS_ONLY=1; shift ;;
        --build-openmw-only)  BUILD_OPENMW_ONLY=1; shift ;;
        --cmake-arg)          EXTRA_CMAKE_ARGS+=("${2:?--cmake-arg requires a value}"); shift 2 ;;
        -h|--help)            usage 0 ;;
        *)                    echo "error: unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -z "$OPENMW_SOURCE_ROOT" ]] && { echo "error: --openmw-source-root or OPENMW_SOURCE_ROOT is required" >&2; usage 1; }

case "$BUILD_TYPE" in
    Debug|Release|RelWithDebInfo|MinSizeRel|None) ;;
    *) echo "error: unsupported build type '$BUILD_TYPE'." >&2; exit 1 ;;
esac

OPENMW_SOURCE_ROOT="$(abs_path "$OPENMW_SOURCE_ROOT")"
OPENMW_BUILD_DIR="$(abs_path "$OPENMW_BUILD_DIR")"
DEPS_PREFIX="$(abs_path "$DEPS_PREFIX")"

[[ -f "$OPENMW_SOURCE_ROOT/CMakeLists.txt" ]] || { echo "error: $OPENMW_SOURCE_ROOT does not look like an OpenMW source root" >&2; exit 1; }

DEPENDENCIES_ROOT_PATH="$DEPS_PREFIX/openmw-deps"
if [[ -z "$DEPS_DIR" ]]; then
    DEPS_DIR="$DEPENDENCIES_ROOT_PATH/installed/$VCPKG_TARGET_TRIPLET"
else
    DEPS_DIR="$(abs_path "$DEPS_DIR")"
    DEPENDENCIES_ROOT_PATH="$(cd "$DEPS_DIR/../.." && pwd)"
fi

if [[ -z "$QT_DIR" ]]; then
    QT_DIR="$DEPS_PREFIX/QT/$QT_VER/gcc_64"
else
    QT_DIR="$(abs_path "$QT_DIR")"
fi

[[ -d "$DEPS_DIR/lib" ]] || { echo "error: deps dir missing lib/: $DEPS_DIR" >&2; exit 1; }
[[ -f "$DEPENDENCIES_ROOT_PATH/scripts/buildsystems/vcpkg.cmake" ]] || { echo "error: vcpkg toolchain not found under $DEPENDENCIES_ROOT_PATH" >&2; exit 1; }
[[ -d "$QT_DIR/lib" ]] || { echo "error: Qt dir missing lib/: $QT_DIR" >&2; exit 1; }

CMAKE_CONF_OPTS=(
    -DCMAKE_C_COMPILER="${CC:-/usr/bin/cc}"
    -DCMAKE_CXX_COMPILER="${CXX:-/usr/bin/c++}"
    -DOPENMW_CXX_FLAGS="${OPENMW_CXX_FLAGS:-}"
    -DCMAKE_INSTALL_RPATH="\$ORIGIN/../lib"
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
    -DCMAKE_PREFIX_PATH="$DEPS_DIR;$QT_DIR"
    -Dcollada_dom_DIR="$DEPS_DIR/share/collada-dom"
    -DOPENMW_USE_SYSTEM_RECASTNAVIGATION=OFF
    -DOPENMW_USE_SYSTEM_SQLITE3=OFF
    -DVCPKG_HOST_TRIPLET="$VCPKG_TARGET_TRIPLET"
    -DVCPKG_TARGET_TRIPLET="$VCPKG_TARGET_TRIPLET"
    -DCMAKE_TOOLCHAIN_FILE="$DEPENDENCIES_ROOT_PATH/scripts/buildsystems/vcpkg.cmake"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
)

if [[ -n "${CMAKE_EXE_LINKER_FLAGS:-}" ]]; then
    CMAKE_CONF_OPTS+=(-DCMAKE_EXE_LINKER_FLAGS="${CMAKE_EXE_LINKER_FLAGS}")
fi

if [[ "$USE_CCACHE" == true ]]; then
    CMAKE_CONF_OPTS+=(
        -DCMAKE_C_COMPILER_LAUNCHER="ccache"
        -DCMAKE_CXX_COMPILER_LAUNCHER="ccache"
    )
fi

if [[ -n "${CMAKE_CXX_FLAGS_DEBUG:-}" ]]; then
    CMAKE_CONF_OPTS+=(-DCMAKE_CXX_FLAGS_DEBUG="${CMAKE_CXX_FLAGS_DEBUG}")
fi

if [[ -n "${BUILD_WITH_CODE_COVERAGE:-}" ]]; then
    CMAKE_CONF_OPTS+=(-DBUILD_WITH_CODE_COVERAGE="${BUILD_WITH_CODE_COVERAGE}")
fi

if [[ -n "${CI_CLANG_TIDY:-}" ]]; then
    CMAKE_CONF_OPTS+=(
        -DCMAKE_CXX_CLANG_TIDY=clang-tidy-19
        -DBUILD_COMPONENTS_TESTS=ON
        -DBUILD_OPENMW_TESTS=ON
        -DBUILD_OPENCS_TESTS=ON
        -DBUILD_BENCHMARKS=ON
    )
fi

if [[ -n "$BUILD_TESTS_ONLY" ]]; then
    CXX_FLAGS="-Wno-error=deprecated-declarations -Wno-error=nonnull -Wno-error=deprecated-copy"
    if [[ "${CXX:-}" == 'clang++' ]]; then
        CXX_FLAGS="${CXX_FLAGS} -Wno-error=unused-lambda-capture -Wno-error=gnu-zero-variadic-macro-arguments"
    fi
    CMAKE_CONF_OPTS+=(
        -DCMAKE_CXX_FLAGS="$CXX_FLAGS"
        -DBUILD_OPENMW=OFF
        -DBUILD_BSATOOL=OFF
        -DBUILD_ESMTOOL=OFF
        -DBUILD_LAUNCHER=OFF
        -DBUILD_MWINIIMPORTER=OFF
        -DBUILD_ESSIMPORTER=OFF
        -DBUILD_OPENCS=OFF
        -DBUILD_WIZARD=OFF
        -DBUILD_NAVMESHTOOL=OFF
        -DBUILD_BULLETOBJECTTOOL=OFF
        -DBUILD_NIFTEST=OFF
        -DBUILD_COMPONENTS_TESTS=ON
        -DBUILD_OPENMW_TESTS=ON
        -DBUILD_OPENCS_TESTS=ON
        -DBUILD_BENCHMARKS=ON
    )
elif [[ -n "$BUILD_OPENMW_ONLY" ]]; then
    CMAKE_CONF_OPTS+=(
        -DBUILD_OPENMW=ON
        -DBUILD_BSATOOL=OFF
        -DBUILD_ESMTOOL=OFF
        -DBUILD_LAUNCHER=OFF
        -DBUILD_MWINIIMPORTER=OFF
        -DBUILD_ESSIMPORTER=OFF
        -DBUILD_OPENCS=OFF
        -DBUILD_WIZARD=OFF
        -DBUILD_NAVMESHTOOL=OFF
        -DBUILD_BULLETOBJECTTOOL=OFF
        -DBUILD_NIFTEST=OFF
    )
fi

CMAKE_CONF_OPTS+=("${EXTRA_CMAKE_ARGS[@]}")

mkdir -p "$OPENMW_BUILD_DIR"

echo "=== Configuring OpenMW tarball build ==="
echo "  source:     $OPENMW_SOURCE_ROOT"
echo "  build:      $OPENMW_BUILD_DIR"
echo "  deps:       $DEPS_DIR"
echo "  qt:         $QT_DIR"
echo "  build type: $BUILD_TYPE"

if command -v scl_source >/dev/null 2>&1; then
    set +u
    source scl_source enable gcc-toolset-13
    set -u
fi

${ANALYZE:-} cmake \
    -S "$OPENMW_SOURCE_ROOT" \
    -B "$OPENMW_BUILD_DIR" \
    "${CMAKE_CONF_OPTS[@]}"
