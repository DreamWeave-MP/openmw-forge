#!/usr/bin/env bash
set -euo pipefail

ROOT=""
# AlmaLinux 9 base/system toolchain symbol-version floor.
# This is the package compatibility contract, not a caller preference.
MAX_GLIBC="2.34"
MAX_GLIBCXX="3.4.29"
MAX_CXXABI="1.3.13"
VIOLATIONS=0
SCANNED=0

usage() {
    cat <<EOF
Usage: $0 --root <dir>

Required:
    --root <dir>           Directory to scan recursively for ELF files

Options:
    -h, --help             Show this message
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)        ROOT="${2:?--root requires a value}"; shift 2 ;;
        -h|--help)     usage 0 ;;
        *)             echo "error: unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -z "$ROOT" ]] && { echo "error: --root is required" >&2; usage 1; }
[[ ! -d "$ROOT" ]] && { echo "error: $ROOT is not a directory" >&2; exit 1; }

version_gt() {
    [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

echo "=== Symbol-version audit ==="
echo "  root:        $ROOT"
echo "  max GLIBC:   $MAX_GLIBC"
echo "  max GLIBCXX: $MAX_GLIBCXX"
echo "  max CXXABI:  $MAX_CXXABI"

while IFS= read -r -d '' file; do
    if ! head -c 4 "$file" 2>/dev/null | grep -q $'\x7fELF'; then
        continue
    fi

    SCANNED=$((SCANNED + 1))
    syms=$(objdump -T "$file" 2>/dev/null || true)

    while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        if version_gt "$ver" "$MAX_GLIBC"; then
            echo "VIOLATION: $file requires GLIBC_$ver (max $MAX_GLIBC)"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    done < <(echo "$syms" | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^GLIBC_//' | sort -u -V)

    while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        if version_gt "$ver" "$MAX_GLIBCXX"; then
            echo "VIOLATION: $file requires GLIBCXX_$ver (max $MAX_GLIBCXX)"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    done < <(echo "$syms" | grep -oE 'GLIBCXX_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^GLIBCXX_//' | sort -u -V)

    while IFS= read -r ver; do
        [[ -z "$ver" ]] && continue
        if version_gt "$ver" "$MAX_CXXABI"; then
            echo "VIOLATION: $file requires CXXABI_$ver (max $MAX_CXXABI)"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    done < <(echo "$syms" | grep -oE 'CXXABI_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^CXXABI_//' | sort -u -V)
done < <(find "$ROOT" -type f -print0)

echo "--- Scanned $SCANNED ELF files ---"

if [[ "$VIOLATIONS" -gt 0 ]]; then
    echo "FAIL: $VIOLATIONS symbol-version violation(s) found" >&2
    exit 1
fi

echo "OK: all binaries compatible!"
