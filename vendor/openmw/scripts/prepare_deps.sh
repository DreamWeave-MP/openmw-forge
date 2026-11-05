#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../config/deps_versions.sh
source "$BUILDER_ROOT/config/deps_versions.sh"

CLI_DEPS_ARCHIVE=""
DEPS_ARCHIVE_ENV="${TARBALL_DEPS_ARCHIVE:-${DEPS_ARCHIVE:-}}"
VCPKG_DEPS_ARCHIVE="${VCPKG_DEPS_ARCHIVE:-}"
DEPS_PREFIX="${TARBALL_DEPS_PREFIX:-$BUILDER_ROOT/work/deps}"
DEPS_ARCHIVE_CACHE_DIR=""
INSTALL_QT=true
INSTALL_SYSTEM_PACKAGES=true
QT_VER="${QT_VER}"

usage() {
    cat <<EOF
Usage: $0 [options]

Prepare dependencies for a portable OpenMW Linux tarball build.

Options:
    --deps-prefix <dir>       Base directory for vcpkg deps and Qt.
                              Env: TARBALL_DEPS_PREFIX
                              Default: $BUILDER_ROOT/work/deps
    --deps-archive <path-or-url>
                              Local .tar.xz/.7z vcpkg deps archive or http(s) URL.
                              Env: TARBALL_DEPS_ARCHIVE
                              Fallbacks: DEPS_ARCHIVE, VCPKG_DEPS_ARCHIVE,
                              $DEPS_ARCHIVE_URL
    --qt-version <ver>        Qt version to install via aqtinstall.
                              Default: ${QT_VER}
    --no-qt                   Skip Qt installation.
    --no-system-packages      Skip dnf package installation.
    --prefix <dir>            Alias for --deps-prefix.
    -h, --help                Show this message.
EOF
    exit "${1:-0}"
}

is_url() {
    [[ "$1" =~ ^https?:// ]]
}

resolve_archive_source() {
    local value="$1"
    local label="$2"
    local warn_missing="$3"

    if [[ -z "$value" ]]; then
        return 1
    fi

    if [[ -f "$value" ]]; then
        echo "$value"
        return 0
    fi

    if is_url "$value"; then
        echo "$value"
        return 0
    fi

    if [[ "$warn_missing" == "1" ]]; then
        echo "warning: ${label} '${value}' is not a readable local file or URL; using fallback" >&2
    fi

    return 1
}

ensure_curl() {
    if command -v curl >/dev/null 2>&1; then
        return 0
    fi

    if [[ "$INSTALL_SYSTEM_PACKAGES" != true ]]; then
        echo "error: curl is required to download URL deps archives" >&2
        return 1
    fi

    local pkg
    local -a curl_packages=(curl curl-minimal)

    for pkg in "${curl_packages[@]}"; do
        echo "--- Ensuring curl command via package: ${pkg} ---"
        if $SUDO dnf install -y "$pkg"; then
            if command -v curl >/dev/null 2>&1; then
                return 0
            fi
        fi
    done

    echo "error: failed to install a curl command. Tried packages: ${curl_packages[*]}" >&2
    return 1
}

select_python_interpreter() {
    local candidate

    for candidate in python3.11 python3; do
        if ! command -v "$candidate" >/dev/null 2>&1; then
            continue
        fi

        local version
        local major
        local minor
        version="$($candidate --version 2>&1 | awk '{print $2}')"

        if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+) ]]; then
            echo "error: could not parse ${candidate} version: $version" >&2
            return 1
        fi

        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        if [[ "$major" -eq 3 && "$minor" -ge 9 ]]; then
            echo "$candidate"
            return 0
        fi
    done

    echo "error: install python3.11 or python3 >= 3.9 before running this script." >&2
    return 1
}

ensure_pip() {
    local python_bin="$1"

    if "$python_bin" -m pip --version >/dev/null 2>&1; then
        return 0
    fi

    echo "--- pip module not found for ${python_bin}; running ensurepip --upgrade ---"
    if ! "$python_bin" -m ensurepip --upgrade; then
        echo "error: failed to bootstrap pip via ${python_bin} -m ensurepip --upgrade" >&2
        return 1
    fi

    "$python_bin" -m pip --version >/dev/null 2>&1
}

archive_filename() {
    local source="$1"
    local filename

    filename="${source##*/}"
    filename="${filename%%\?*}"
    filename="${filename%%#*}"

    if [[ -z "$filename" ]]; then
        filename="vcpkg-deps.tar.xz"
    fi

    echo "$filename"
}

archive_cache_file() {
    local source="$1"
    local filename
    local digest

    filename="$(archive_filename "$source")"
    if command -v cksum >/dev/null 2>&1; then
        digest="$(printf '%s' "$source" | cksum | awk '{print $1}')"
    else
        digest="$(printf '%s' "$source" | wc -c | tr -d '[:space:]')"
    fi

    echo "$DEPS_ARCHIVE_CACHE_DIR/${digest}-${filename}"
}

download_url_archive() {
    local source="$1"
    local cache_file="$2"
    local tmp_archive

    ensure_curl
    tmp_archive="$(mktemp "${DEPS_ARCHIVE_CACHE_DIR}/.deps-archive.XXXXXX")"

    if curl -fSL "$source" -o "$tmp_archive"; then
        mv "$tmp_archive" "$cache_file"
        echo "$cache_file"
        return 0
    fi

    rm -f "$tmp_archive"
    return 1
}

acquire_archive_file() {
    local source="$1"
    local label="$2"
    local warn_invalid="$3"
    local resolved

    if ! resolved="$(resolve_archive_source "$source" "$label" "$warn_invalid")"; then
        return 1
    fi

    if is_url "$resolved"; then
        local cache_file
        cache_file="$(archive_cache_file "$resolved")"
        mkdir -p "$DEPS_ARCHIVE_CACHE_DIR"
        if [[ -f "$cache_file" ]]; then
            echo "info: using cached archive from ${label}: $resolved"
            ARCHIVE_FILE="$cache_file"
            return 0
        fi

        echo "info: downloading archive from ${label}: $resolved"
        local downloaded
        if downloaded="$(download_url_archive "$resolved" "$cache_file")"; then
            ARCHIVE_FILE="$downloaded"
            return 0
        fi

        echo "warning: failed to download ${label}: $resolved; trying next fallback" >&2
        return 1
    fi

    ARCHIVE_FILE="$resolved"
    return 0
}

extract_archive() {
    local archive="$1"

    mkdir -p "$DEPS_PREFIX/openmw-deps-pre"
    echo "--- Extracting vcpkg deps ---"

    case "$archive" in
        *.tar.xz)
            if ! tar --version >/dev/null 2>&1; then
                echo "error: tar not available or not functioning" >&2
                exit 1
            fi

            echo "  using extraction mode: tar -xJf"
            if ! tar -xJf "$archive" -C "$DEPS_PREFIX/openmw-deps-pre" >/dev/null 2>&1; then
                echo "error: failed to extract deps archive with tar -xJf: $archive" >&2
                exit 1
            fi
            ;;
        *.7z)
            extract_7z_archive "$archive" "$DEPS_PREFIX/openmw-deps-pre"
            ;;
        *)
            echo "error: unsupported deps archive format: $archive (expected .tar.xz or .7z)" >&2
            exit 1
            ;;
    esac
}

find_7z_extractor() {
    local candidate
    for candidate in 7zz 7z 7za; do
        if command -v "$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_7z_extractor() {
    local extractor

    if extractor="$(find_7z_extractor)"; then
        echo "$extractor"
        return 0
    fi

    if [[ "$INSTALL_SYSTEM_PACKAGES" != true ]]; then
        echo "error: 7z/7zz/7za is required to extract .7z dependency archives" >&2
        return 1
    fi

    local pkg
    for pkg in 7zip p7zip p7zip-plugins; do
        echo "--- Ensuring 7z extractor via package: ${pkg} ---" >&2
        if $SUDO dnf install -y "$pkg" >/dev/null 2>&1; then
            if extractor="$(find_7z_extractor)"; then
                echo "$extractor"
                return 0
            fi
        fi
    done

    echo "error: failed to install a 7z extractor" >&2
    return 1
}

extract_7z_archive() {
    local archive="$1"
    local output_dir="$2"
    local extractor
    local status=0

    extractor="$(ensure_7z_extractor)"
    echo "  using extraction mode: ${extractor} x"
    "$extractor" x -y "-o${output_dir}" "$archive" >/dev/null || status=$?

    # Some 7z builds return 1 for non-fatal warnings such as symlink handling.
    # Validate the extracted tree below instead of repacking the archive into a
    # different format just to placate one tool. That would be ridiculous.
    if [[ "$status" -gt 1 ]]; then
        echo "error: failed to extract deps archive with ${extractor}: $archive" >&2
        exit 1
    fi
}

install_system_packages() {
    if [[ "$INSTALL_SYSTEM_PACKAGES" != true ]]; then
        return 0
    fi

    if ! command -v dnf >/dev/null 2>&1; then
        echo "error: dnf was not found. Run inside Alma/RHEL/Fedora or pass --no-system-packages after installing host deps manually." >&2
        exit 1
    fi

    echo "--- Installing system dependencies ---"
    $SUDO dnf install -y epel-release
    $SUDO dnf install -y \
        gcc-toolset-13 \
        cmake \
        ccache \
        git \
        python3-pip \
        mesa-libGL-devel \
        mesa-libEGL-devel \
        libxkbcommon-devel \
        libxkbcommon-x11 \
        libxcb \
        xcb-util \
        xcb-util-image \
        xcb-util-keysyms \
        xcb-util-wm \
        xcb-util-renderutil \
        xcb-util-cursor
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --deps-archive)       CLI_DEPS_ARCHIVE="${2:?--deps-archive requires a value}"; shift 2 ;;
        --deps-prefix|--prefix) DEPS_PREFIX="${2:?$1 requires a value}"; shift 2 ;;
        --qt-version)         QT_VER="${2:?--qt-version requires a value}"; shift 2 ;;
        --no-qt)              INSTALL_QT=false; shift ;;
        --no-system-packages) INSTALL_SYSTEM_PACKAGES=false; shift ;;
        -h|--help)            usage 0 ;;
        *)                    echo "error: unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ "$DEPS_PREFIX" != /* ]] && DEPS_PREFIX="$PWD/$DEPS_PREFIX"
DEPS_ARCHIVE_CACHE_DIR="${DEPS_PREFIX}/.deps-archive-cache"
mkdir -p "$DEPS_PREFIX"

ARCHIVE_FILE=""
if ! acquire_archive_file "$CLI_DEPS_ARCHIVE" "explicit --deps-archive" 1; then
    if ! acquire_archive_file "$DEPS_ARCHIVE_ENV" "TARBALL_DEPS_ARCHIVE/DEPS_ARCHIVE" 0; then
        if ! acquire_archive_file "$VCPKG_DEPS_ARCHIVE" "VCPKG_DEPS_ARCHIVE" 0; then
            if ! acquire_archive_file "$DEPS_ARCHIVE_URL" "DEPS_ARCHIVE_URL fallback" 0; then
                echo "error: no valid deps archive source found" >&2
                exit 1
            fi
        fi
    fi
fi

SUDO=""
if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi

install_system_packages

if command -v scl_source >/dev/null 2>&1; then
    set +u
    source scl_source enable gcc-toolset-13
    set -u
fi

if [[ "$INSTALL_QT" == true ]]; then
    echo "--- Installing Qt ${QT_VER} via aqtinstall ---"
    PYTHON_BIN="$(select_python_interpreter)"
    ensure_pip "$PYTHON_BIN"
    "$PYTHON_BIN" -m pip install aqtinstall
    "$PYTHON_BIN" -m aqt install-qt linux desktop "$QT_VER" gcc_64 \
        --archives qtbase qtdeclarative qtsvg qttools qtwayland icu \
        -O "$DEPS_PREFIX/QT"
fi

rm -rf "$DEPS_PREFIX/openmw-deps" "$DEPS_PREFIX/openmw-deps-pre"
extract_archive "$ARCHIVE_FILE"
if ! find "$DEPS_PREFIX/openmw-deps-pre" -mindepth 2 -maxdepth 4 -path "*/installed/$VCPKG_TARGET_TRIPLET/lib" -type d | grep -q .; then
    echo "error: extracted deps archive does not contain installed/$VCPKG_TARGET_TRIPLET/lib" >&2
    exit 1
fi
if ! find "$DEPS_PREFIX/openmw-deps-pre" -mindepth 2 -maxdepth 4 -path "*/scripts/buildsystems/vcpkg.cmake" -type f | grep -q .; then
    echo "error: extracted deps archive does not contain scripts/buildsystems/vcpkg.cmake" >&2
    exit 1
fi
mv "$DEPS_PREFIX/openmw-deps-pre"/*/ "$DEPS_PREFIX/openmw-deps/"
rmdir "$DEPS_PREFIX/openmw-deps-pre"

echo "--- Done ---"
echo "  deps prefix: $DEPS_PREFIX"
echo "  vcpkg deps:  $DEPS_PREFIX/openmw-deps"
[[ "$INSTALL_QT" == true ]] && echo "  Qt ${QT_VER}:  $DEPS_PREFIX/QT/${QT_VER}/gcc_64"
