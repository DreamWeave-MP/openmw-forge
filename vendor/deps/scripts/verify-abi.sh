#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/fail.sh
source "$SCRIPT_DIR/lib/fail.sh"
openmw_init_error_trap
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

TRIPLET="${TRIPLET:-$DEFAULT_TRIPLET}"
VCPKG_DIR="${VCPKG_DIR:-/opt/vcpkg}"
OUTPUT_DIR="${OUTPUT_DIR:-$OPENMW_DEPS_REPO_ROOT}"
ARCHIVE_PATH="$OUTPUT_DIR/vcpkg-$TRIPLET.7z"
METADATA_PATH="$OUTPUT_DIR/vcpkg-$TRIPLET.build-meta"
SCAN_ROOT="${ABI_SCAN_ROOT:-$VCPKG_DIR/installed/$TRIPLET}"

tmpdir=""
cleanup() {
    if [ -n "$tmpdir" ] && [ -d "$tmpdir" ]; then
        rm -rf "$tmpdir"
    fi
}
trap cleanup EXIT

version_gt() {
    local left="$1"
    local right="$2"

    if [ -z "$left" ]; then
        return 1
    fi

    if [ -z "$right" ]; then
        return 0
    fi

    [ "$(printf '%s\n%s\n' "$left" "$right" | sort -V | awk 'END{print}')" = "$left" ] && [ "$left" != "$right" ]
}

resolve_scan_root() {
    local manifest_scan_root="${ABI_SCAN_ROOT:-$OPENMW_DEPS_REPO_ROOT/vcpkg_installed/$TRIPLET}"

    if [ -d "$manifest_scan_root" ]; then
        printf '%s\n' "$manifest_scan_root"
        return 0
    fi

    if [ -d "$SCAN_ROOT" ]; then
        printf '%s\n' "$SCAN_ROOT"
        return 0
    fi

    if [ -f "$METADATA_PATH" ]; then
        local metadata_vcpkg_dir
        metadata_vcpkg_dir="$(awk -F= '$1 == "vcpkg_dir" { print $2 }' "$METADATA_PATH")"
        if [ -n "$metadata_vcpkg_dir" ] && [ -d "$metadata_vcpkg_dir/installed/$TRIPLET" ]; then
            printf '%s\n' "$metadata_vcpkg_dir/installed/$TRIPLET"
            return 0
        fi
    fi

    if [ -f "$ARCHIVE_PATH" ] && [ -n "$OPENMW_DEPS_7ZIP_CMD" ]; then
        tmpdir="$(mktemp -d)"
        "$OPENMW_DEPS_7ZIP_CMD" x -y "-o$tmpdir" "$ARCHIVE_PATH" >/dev/null 2>&1
        extracted_scan_root="$(find "$tmpdir" -type d -path "*/installed/$TRIPLET" | awk 'NR == 1 { print; exit }')"
        if [ -n "$extracted_scan_root" ] && [ -d "$extracted_scan_root" ]; then
            printf '%s\n' "$extracted_scan_root"
            return 0
        fi
    fi

    echo "ERROR: Could not resolve ABI scan root." >&2
    echo "  looked for: $SCAN_ROOT" >&2
    echo "  archive fallback: $ARCHIVE_PATH" >&2
    echo "  hint: set ABI_SCAN_ROOT or provide a 7zip command (7z, 7zz, or 7za) for archive fallback" >&2
    return 1
}

SCAN_ROOT="$(resolve_scan_root)"

echo "Verifying ABI ceiling"
echo "  profile: $PROFILE"
echo "  triplet: $TRIPLET"
echo "  glibc max: $BUILD_GLIBC_MAX"
echo "  glibcxx max: $BUILD_GLIBCXX_MAX"
echo "  cxxabi max: $BUILD_CXXABI_MAX"
echo "  scan root: $SCAN_ROOT"

max_seen_glibc=""
max_seen_glibcxx=""
max_seen_cxxabi=""
scanned_elf_files=0
declare -a violations=()

while IFS= read -r -d '' file; do
    if ! readelf -h "$file" >/dev/null 2>&1; then
        continue
    fi

    version_info="$(readelf --version-info "$file" 2>/dev/null || true)"
    file_max_glibc="$(printf '%s\n' "$version_info" | awk 'match($0, /GLIBC_[0-9]+(\.[0-9]+)+/) { print substr($0, RSTART + 6, RLENGTH - 6) }' | sort -Vu | awk 'END { print }')"
    file_max_glibcxx="$(printf '%s\n' "$version_info" | awk 'match($0, /GLIBCXX_[0-9]+(\.[0-9]+)+/) { print substr($0, RSTART + 8, RLENGTH - 8) }' | sort -Vu | awk 'END { print }')"
    file_max_cxxabi="$(printf '%s\n' "$version_info" | awk 'match($0, /CXXABI_[0-9]+(\.[0-9]+)+/) { print substr($0, RSTART + 7, RLENGTH - 7) }' | sort -Vu | awk 'END { print }')"

    if [ -z "$file_max_glibc" ] && [ -z "$file_max_glibcxx" ] && [ -z "$file_max_cxxabi" ]; then
        continue
    fi

    scanned_elf_files=$((scanned_elf_files + 1))

    if version_gt "$file_max_glibc" "$max_seen_glibc"; then
        max_seen_glibc="$file_max_glibc"
    fi

    if version_gt "$file_max_glibc" "$BUILD_GLIBC_MAX"; then
        violations+=("$file => GLIBC_$file_max_glibc")
    fi

    if version_gt "$file_max_glibcxx" "$max_seen_glibcxx"; then
        max_seen_glibcxx="$file_max_glibcxx"
    fi

    if version_gt "$file_max_glibcxx" "$BUILD_GLIBCXX_MAX"; then
        violations+=("$file => GLIBCXX_$file_max_glibcxx")
    fi

    if version_gt "$file_max_cxxabi" "$max_seen_cxxabi"; then
        max_seen_cxxabi="$file_max_cxxabi"
    fi

    if version_gt "$file_max_cxxabi" "$BUILD_CXXABI_MAX"; then
        violations+=("$file => CXXABI_$file_max_cxxabi")
    fi
done < <(find "$SCAN_ROOT" -type f -print0)

if [ "$scanned_elf_files" -eq 0 ]; then
    echo "ERROR: No ELF files with ABI symbol versions were found in $SCAN_ROOT" >&2
    exit 1
fi

echo "  scanned files: $scanned_elf_files"
echo "  highest seen: GLIBC_${max_seen_glibc:-none}"
echo "  highest seen: GLIBCXX_${max_seen_glibcxx:-none}"
echo "  highest seen: CXXABI_${max_seen_cxxabi:-none}"

if [ "${#violations[@]}" -gt 0 ]; then
    echo "ERROR: ABI check failed; found symbol versions above configured ceilings" >&2
    shown=0
    for violation in "${violations[@]}"; do
        echo "  $violation" >&2
        shown=$((shown + 1))
        if [ "$shown" -ge 20 ]; then
            remaining=$((${#violations[@]} - shown))
            if [ "$remaining" -gt 0 ]; then
                echo "  ... and $remaining more" >&2
            fi
            break
        fi
    done
    exit 1
fi

echo "ABI verification complete"
