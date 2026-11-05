#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../config/deps_versions.sh
source "$BUILDER_ROOT/config/deps_versions.sh"

OPENMW_SOURCE_ROOT="${OPENMW_SOURCE_ROOT:-}"
BUILD_DIR="${OPENMW_BUILD_DIR:-$BUILDER_ROOT/work/build}"
DEPS_PREFIX="${TARBALL_DEPS_PREFIX:-$BUILDER_ROOT/work/deps}"
DEPS_DIR=""
QT_DIR=""
OUTPUT_DIR="${TARBALL_OUTPUT_DIR:-$BUILDER_ROOT/artifacts}"
PORTABLE=false
BUILD_TYPE=""
RUN_COMPAT=true
RUN_SMOKE=true
STAGE_ONLY=false

usage() {
    cat <<EOF
Usage: $0 --openmw-source-root <dir> [options]

Assemble portable OpenMW Linux tarballs from an arbitrary source/build/deps set.

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
    --output-dir <dir>         Directory for final tarballs. Env: TARBALL_OUTPUT_DIR
                               Default: $BUILDER_ROOT/artifacts
    --build-type <value>       Debug, Release, RelWithDebInfo, MinSizeRel, None.
                               If omitted, read from CMakeCache.txt, then RelWithDebInfo.
    --triplet <value>          vcpkg triplet. Default: $VCPKG_TARGET_TRIPLET
    --qt-version <ver>        Qt installed version. Default: $QT_VER
    --portable                 Store config/user-data/data-local inside tarball dir.
    --stage-only               Populate package staging only; skip debug split,
                               compatibility audit, smoke tests, and tarballs.
    --no-compat-check          Skip symbol-version audit.
    --no-smoke                 Skip packaged binary --help smoke tests.
    --repo-root <dir>          Alias for --openmw-source-root.
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
        --openmw-source-root|--repo-root) OPENMW_SOURCE_ROOT="${2:?$1 requires a value}"; shift 2 ;;
        --build-dir)      BUILD_DIR="${2:?--build-dir requires a value}"; shift 2 ;;
        --deps-prefix)    DEPS_PREFIX="${2:?--deps-prefix requires a value}"; shift 2 ;;
        --deps-dir)       DEPS_DIR="${2:?--deps-dir requires a value}"; shift 2 ;;
        --qt-dir)         QT_DIR="${2:?--qt-dir requires a value}"; shift 2 ;;
        --output-dir)     OUTPUT_DIR="${2:?--output-dir requires a value}"; shift 2 ;;
        --build-type)     BUILD_TYPE="${2:?--build-type requires a value}"; shift 2 ;;
        --triplet)        VCPKG_TARGET_TRIPLET="${2:?--triplet requires a value}"; shift 2 ;;
        --qt-version)     QT_VER="${2:?--qt-version requires a value}"; shift 2 ;;
        --portable)       PORTABLE=true; shift ;;
        --stage-only)     STAGE_ONLY=true; shift ;;
        --no-compat-check) RUN_COMPAT=false; shift ;;
        --no-smoke)       RUN_SMOKE=false; shift ;;
        -h|--help)        usage 0 ;;
        *)                echo "error: unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -z "$OPENMW_SOURCE_ROOT" ]] && { echo "error: --openmw-source-root or OPENMW_SOURCE_ROOT is required" >&2; usage 1; }

OPENMW_SOURCE_ROOT="$(abs_path "$OPENMW_SOURCE_ROOT")"
BUILD_DIR="$(abs_path "$BUILD_DIR")"
DEPS_PREFIX="$(abs_path "$DEPS_PREFIX")"
OUTPUT_DIR="$(abs_path "$OUTPUT_DIR")"

[[ -f "$OPENMW_SOURCE_ROOT/CMakeLists.txt" ]] || { echo "error: $OPENMW_SOURCE_ROOT does not look like an OpenMW source root" >&2; exit 1; }
[[ -d "$BUILD_DIR" ]] || { echo "error: build dir does not exist: $BUILD_DIR" >&2; exit 1; }

if [[ -z "$DEPS_DIR" ]]; then
    DEPS_DIR="$DEPS_PREFIX/openmw-deps/installed/$VCPKG_TARGET_TRIPLET"
else
    DEPS_DIR="$(abs_path "$DEPS_DIR")"
fi

if [[ -z "$QT_DIR" ]]; then
    QT_DIR="$DEPS_PREFIX/QT/$QT_VER/gcc_64"
else
    QT_DIR="$(abs_path "$QT_DIR")"
fi

[[ -d "$DEPS_DIR/lib" ]] || { echo "error: $DEPS_DIR does not contain a lib/ directory" >&2; exit 1; }
[[ -d "$QT_DIR/lib" ]] || { echo "error: $QT_DIR does not contain a lib/ directory" >&2; exit 1; }

if [[ -z "$BUILD_TYPE" ]]; then
    if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
        BUILD_TYPE="$(sed -n 's/^CMAKE_BUILD_TYPE:STRING=//p' "$BUILD_DIR/CMakeCache.txt" | head -n 1)"
    fi
    [[ -z "$BUILD_TYPE" ]] && BUILD_TYPE="RelWithDebInfo"
fi

case "$BUILD_TYPE" in
    Debug|Release|RelWithDebInfo|MinSizeRel|None) ;;
    *) echo "error: unsupported build type '$BUILD_TYPE'." >&2; exit 1 ;;
esac

BUILD_DEBUG_LIBS=false
[[ "$BUILD_TYPE" == "Debug" ]] && BUILD_DEBUG_LIBS=true

MAJOR="$(grep 'set(OPENMW_VERSION_MAJOR' "$OPENMW_SOURCE_ROOT/CMakeLists.txt" | grep -o '[0-9]\+')"
MINOR="$(grep 'set(OPENMW_VERSION_MINOR' "$OPENMW_SOURCE_ROOT/CMakeLists.txt" | grep -o '[0-9]\+')"
RELEASE="$(grep 'set(OPENMW_VERSION_RELEASE' "$OPENMW_SOURCE_ROOT/CMakeLists.txt" | grep -o '[0-9]\+')"
VERSION="${MAJOR}.${MINOR}.${RELEASE}"

PACKAGE_NAME="openmw-${VERSION}-Linux-64Bit"
[[ "$PORTABLE" == true ]] && PACKAGE_NAME="${PACKAGE_NAME}-portable"
DEBUG_PACKAGE_NAME="${PACKAGE_NAME}-debug"
STAGING="$BUILD_DIR/package-staging/$PACKAGE_NAME"
DEBUG_STAGING="$BUILD_DIR/package-staging-debug/$DEBUG_PACKAGE_NAME"

echo "=== Packaging OpenMW ${VERSION} ==="
echo "  source:     $OPENMW_SOURCE_ROOT"
echo "  build:      $BUILD_DIR"
echo "  deps:       $DEPS_DIR"
echo "  qt:         $QT_DIR"
echo "  output:     $OUTPUT_DIR"
echo "  build type: $BUILD_TYPE"

rm -rf "$BUILD_DIR/package-staging" "$BUILD_DIR/package-staging-debug"
mkdir -p "$STAGING/lib"

echo "--- Installing binaries ---"
BINARIES=(
    openmw
    openmw-launcher
    openmw-cs
    openmw-wizard
    openmw-iniimporter
    openmw-essimporter
    openmw-navmeshtool
    openmw-bulletobjecttool
    bsatool
    esmtool
    niftest
)

for bin in "${BINARIES[@]}"; do
    if [[ -f "$BUILD_DIR/$bin" ]]; then
        cp "$BUILD_DIR/$bin" "$STAGING/${bin}.x86_64"
        cp "$BUILDER_ROOT/templates/runtime_wrapper.sh.in" "$STAGING/$bin"
        chmod +x "$STAGING/$bin"
    else
        echo "  warning: $bin not found, skipping"
    fi
done

echo "--- Bundling vcpkg libraries ---"
EXCLUDE_LIBS="libasound|libatopology"

copy_vcpkg_libs() {
    local source_dir="$1"
    local suffix="${2:-standard}"

    if [[ ! -d "$source_dir" ]]; then
        return 0
    fi

    echo "    from ${source_dir} (${suffix})"

    while IFS= read -r lib; do
        cp -a "$lib" "$STAGING/lib/"
    done < <(find "$source_dir" -maxdepth 1 -name "*.so*" | grep -Ev "$EXCLUDE_LIBS" || true)

    while IFS= read -r dir; do
        cp -a "$dir" "$STAGING/lib/"
    done < <(find "$source_dir" -maxdepth 1 -type d -name "osgPlugins-*" || true)
}

if [[ "$BUILD_DEBUG_LIBS" == true ]]; then
    if [[ -d "$DEPS_DIR/debug/lib" ]]; then
        echo "--- Bundling vcpkg debug libraries ---"
        copy_vcpkg_libs "$DEPS_DIR/debug/lib" "debug"
    else
        echo "warning: debug build detected but $DEPS_DIR/debug/lib not found"
        echo "         Falling back to standard vcpkg libs"
        copy_vcpkg_libs "$DEPS_DIR/lib" "release"
    fi
else
    copy_vcpkg_libs "$DEPS_DIR/lib" "release"
fi

echo "--- Bundling Qt libraries ---"
while IFS= read -r lib; do
    cp -a "$lib" "$STAGING/lib/"
done < <(find "$QT_DIR/lib" -maxdepth 1 \( -name "libQt6*.so.*" -o -name "libicu*.so.*" \) || true)

echo "--- Bundling Qt plugins ---"
cp -a "$QT_DIR/plugins" "$STAGING/plugins"
rm -rf "$STAGING/plugins/designer"

if [[ -d /usr/lib64 ]]; then
    XCB_LIB_SRC=/usr/lib64
elif [[ -d /usr/lib/x86_64-linux-gnu ]]; then
    XCB_LIB_SRC=/usr/lib/x86_64-linux-gnu
else
    XCB_LIB_SRC=/usr/lib
fi
shopt -s nullglob
for lib in "$XCB_LIB_SRC"/libxcb-*.so.* \
           "$XCB_LIB_SRC"/libxkbcommon.so.* \
           "$XCB_LIB_SRC"/libxkbcommon-x11.so.*; do
    cp -a "$lib" "$STAGING/lib/"
done
shopt -u nullglob

echo "--- Copying config files ---"
if [[ -f "$BUILD_DIR/openmw.cfg" ]]; then
    if [[ "$PORTABLE" == true ]]; then
        echo "  (portable mode: rewriting config/user-data/data-local to tarball-relative paths)"
        sed \
            -e 's|^config="?userconfig?"|config=config|' \
            -e 's|^user-data="?userdata?"|user-data=userdata|' \
            -e 's|^data-local="?userdata?data"|data-local=userdata/data|' \
            "$BUILD_DIR/openmw.cfg" > "$STAGING/openmw.cfg"
    else
        cp "$BUILD_DIR/openmw.cfg" "$STAGING/openmw.cfg"
    fi
else
    echo "  warning: $BUILD_DIR/openmw.cfg not found"
fi

[[ -f "$BUILD_DIR/defaults.bin" ]] && cp "$BUILD_DIR/defaults.bin" "$STAGING/"
[[ -f "$BUILD_DIR/defaults-cs.bin" ]] && cp "$BUILD_DIR/defaults-cs.bin" "$STAGING/"
[[ -f "$BUILD_DIR/gamecontrollerdb.txt" ]] && cp "$BUILD_DIR/gamecontrollerdb.txt" "$STAGING/"

echo "--- Copying resources ---"
if [[ -d "$BUILD_DIR/resources" ]]; then
    cp -a "$BUILD_DIR/resources" "$STAGING/resources"
else
    echo "error: $BUILD_DIR/resources not found" >&2
    exit 1
fi

[[ -f "$OPENMW_SOURCE_ROOT/files/launcher/images/openmw.png" ]] && cp "$OPENMW_SOURCE_ROOT/files/launcher/images/openmw.png" "$STAGING/"
[[ -f "$OPENMW_SOURCE_ROOT/files/opencs/openmw-cs.png" ]] && cp "$OPENMW_SOURCE_ROOT/files/opencs/openmw-cs.png" "$STAGING/"

echo "--- Copying documentation ---"
[[ -f "$OPENMW_SOURCE_ROOT/CHANGELOG.md" ]] && cp "$OPENMW_SOURCE_ROOT/CHANGELOG.md" "$STAGING/CHANGELOG.txt"
[[ -f "$OPENMW_SOURCE_ROOT/LICENSE" ]] && cp "$OPENMW_SOURCE_ROOT/LICENSE" "$STAGING/LICENSE.txt"
[[ -f "$OPENMW_SOURCE_ROOT/README.md" ]] && cp "$OPENMW_SOURCE_ROOT/README.md" "$STAGING/"
cp "$BUILDER_ROOT/templates/README.packagecontents.txt" "$STAGING/"

if [[ "$STAGE_ONLY" == true ]]; then
    echo "--- Stage-only mode: skipping debug split, compatibility audit, smoke tests, and tarball creation ---"
    echo "=== Done ==="
    echo "Package staging: $STAGING"
    exit 0
fi

if [[ "$BUILD_DEBUG_LIBS" == true ]]; then
    echo "--- DEBUG build: skipping split_debug and sidecar archive ---"
else
    "$SCRIPT_DIR/split_debug.sh" \
        --staging "$STAGING" \
        --debug-staging "$DEBUG_STAGING"
fi

if [[ "$RUN_COMPAT" == true ]]; then
    "$SCRIPT_DIR/check_compat.sh" --root "$STAGING"
fi

if [[ "$RUN_SMOKE" == true ]]; then
    echo "--- Smoke testing binaries ---"
    SMOKE_BINARIES=(
        openmw
        openmw-iniimporter
        openmw-essimporter
        openmw-navmeshtool
        openmw-bulletobjecttool
        bsatool
        esmtool
        niftest
    )
    for bin in "${SMOKE_BINARIES[@]}"; do
        [[ -x "$STAGING/$bin" ]] || continue
        output=$("$STAGING/$bin" --help 2>&1 || true)
        if echo "$output" | grep -qE 'error while loading shared libraries|cannot open shared object|symbol lookup error|undefined symbol'; then
            echo "FAIL: $bin could not load its dynamic dependencies:" >&2
            echo "$output" >&2
            exit 1
        fi
        echo "  ok: $bin"
    done
fi

echo "--- Creating tarballs ---"
mkdir -p "$OUTPUT_DIR"
tar czf "$OUTPUT_DIR/${PACKAGE_NAME}.tar.gz" -C "$BUILD_DIR/package-staging" "$PACKAGE_NAME"
if [[ "$BUILD_DEBUG_LIBS" == false ]]; then
    tar czf "$OUTPUT_DIR/${DEBUG_PACKAGE_NAME}.tar.gz" -C "$BUILD_DIR/package-staging-debug" "$DEBUG_PACKAGE_NAME"
fi

echo "=== Done ==="
if [[ "$BUILD_DEBUG_LIBS" == true ]]; then
    ls -lh "$OUTPUT_DIR/${PACKAGE_NAME}.tar.gz"
else
    ls -lh "$OUTPUT_DIR/${PACKAGE_NAME}.tar.gz" "$OUTPUT_DIR/${DEBUG_PACKAGE_NAME}.tar.gz"
fi
