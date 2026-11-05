#!/usr/bin/env bash
set -euo pipefail

STAGING=""
DEBUG_STAGING=""
PROCESSED=0
SKIPPED=0
PRESTRIPPED=0
UNSAFE=0

UNSAFE_TO_STRIP=(
    'libicudata.so.*'
)

usage() {
    cat <<EOF
Usage: $0 --staging <dir> --debug-staging <dir>

Required:
    --staging <dir>        Staged tarball tree containing binaries and .so files
    --debug-staging <dir>  Output directory for the parallel debug sidecar tree
    -h, --help             Show this message
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --staging)       STAGING="${2:?--staging requires a value}"; shift 2 ;;
        --debug-staging) DEBUG_STAGING="${2:?--debug-staging requires a value}"; shift 2 ;;
        -h|--help)       usage 0 ;;
        *)               echo "error: unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -z "$STAGING" ]] && { echo "error: --staging is required" >&2; usage 1; }
[[ -z "$DEBUG_STAGING" ]] && { echo "error: --debug-staging is required" >&2; usage 1; }
[[ ! -d "$STAGING" ]] && { echo "error: $STAGING is not a directory" >&2; exit 1; }

mkdir -p "$DEBUG_STAGING"

echo "=== Splitting debug info ==="
echo "  staging:       $STAGING"
echo "  debug staging: $DEBUG_STAGING"

while IFS= read -r -d '' file; do
    if ! head -c 4 "$file" 2>/dev/null | grep -q $'\x7fELF'; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if objdump -h "$file" 2>/dev/null | grep -q '\.gnu_debuglink'; then
        PRESTRIPPED=$((PRESTRIPPED + 1))
        continue
    fi

    base="$(basename "$file")"
    unsafe=false
    for pat in "${UNSAFE_TO_STRIP[@]}"; do
        if [[ "$base" == $pat ]]; then
            unsafe=true
            break
        fi
    done
    if [[ "$unsafe" == true ]]; then
        UNSAFE=$((UNSAFE + 1))
        continue
    fi

    rel="${file#$STAGING/}"
    dbg_dir="$DEBUG_STAGING/$(dirname "$rel")"
    dbg_name="$(basename "$file").debug"
    dbg_file="$dbg_dir/$dbg_name"

    mkdir -p "$dbg_dir"
    chmod u+w "$file"
    objcopy --only-keep-debug "$file" "$dbg_file"
    chmod 644 "$dbg_file"
    strip --strip-debug --strip-unneeded "$file"
    objcopy --add-gnu-debuglink="$dbg_file" "$file"

    PROCESSED=$((PROCESSED + 1))
done < <(find "$STAGING" -type f -print0)

echo "--- Processed $PROCESSED ELF files (skipped $SKIPPED non-ELF, $PRESTRIPPED pre-stripped, $UNSAFE unsafe-to-strip) ---"
