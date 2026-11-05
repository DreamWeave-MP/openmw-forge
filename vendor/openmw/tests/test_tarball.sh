#!/usr/bin/env bash
set -euo pipefail

WITH_QT=false
TARBALL=""
OUTPUT_DIR=""

usage() {
    cat <<EOF
Usage: $0 [options] <tarball.tar.gz>

Smoke test an OpenMW Linux tarball on the current distro.

Options:
    --with-qt             Also launch openmw-wizard, openmw-launcher, and
                          openmw-cs under a short timeout. Requires a working
                          display backend such as X11, Wayland, or Xvfb.
    --output-dir <path>   Where to write RESULTS_<distro>.tar.gz.
                          Default: directory of the tarball.
    -h, --help            Show this message.

The tarball is validated, then extracted into a fresh temporary directory.
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-qt)    WITH_QT=true; shift ;;
        --output-dir) OUTPUT_DIR="${2:?--output-dir requires a value}"; shift 2 ;;
        -h|--help)    usage 0 ;;
        -*)           echo "error: unknown option: $1" >&2; usage 1 ;;
        *)            TARBALL="$1"; shift ;;
    esac
done

[[ -z "$TARBALL" ]] && { echo "error: tarball path is required" >&2; usage 1; }
[[ ! -f "$TARBALL" ]] && { echo "error: $TARBALL is not a file" >&2; exit 1; }

TARBALL="$(readlink -f "$TARBALL")"
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="$(dirname "$TARBALL")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(readlink -f "$OUTPUT_DIR")"

mapfile -t TARBALL_ENTRIES < <(tar tzf "$TARBALL")
if [[ "${#TARBALL_ENTRIES[@]}" -eq 0 ]]; then
    echo "error: $TARBALL is empty" >&2
    exit 1
fi

TOP_DIR=""
HAS_TOP_DIR=false
for entry in "${TARBALL_ENTRIES[@]}"; do
    if [[ -z "$entry" || "$entry" == /* || "$entry" == ../* || "$entry" == */../* || "$entry" == */.. ]]; then
        echo "error: unsafe or empty archive entry: $entry" >&2
        exit 1
    fi
    if [[ "$entry" != */* ]]; then
        echo "error: archive entry is not under a top-level directory: $entry" >&2
        exit 1
    fi

    top="${entry%%/*}"
    if [[ -z "$top" || "$top" == "." || "$top" == ".." ]]; then
        echo "error: invalid top-level directory in archive entry: $entry" >&2
        exit 1
    fi
    if [[ -z "$TOP_DIR" ]]; then
        TOP_DIR="$top"
    elif [[ "$TOP_DIR" != "$top" ]]; then
        echo "error: archive must contain exactly one top-level directory" >&2
        echo "       found both: $TOP_DIR and $top" >&2
        exit 1
    fi
    [[ "$entry" == "$top/" ]] && HAS_TOP_DIR=true
done

if [[ "$HAS_TOP_DIR" != true ]]; then
    echo "error: archive does not contain a real top-level directory entry: $TOP_DIR/" >&2
    exit 1
fi

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/openmw-tarball-test.XXXXXXXX")"
cleanup_work_root() {
    rm -rf "$WORK_ROOT"
}
trap cleanup_work_root EXIT

echo "=== Extracting $TARBALL ==="
echo "  top-level dir: $TOP_DIR"
echo "  work dir: $WORK_ROOT"
tar xzf "$TARBALL" -C "$WORK_ROOT"

path_is_inside() {
    local path="$1"
    local root="$2"
    [[ "$path" == "$root" || "$path" == "$root"/* ]]
}

PACKAGE_PATH="$WORK_ROOT/$TOP_DIR"
if [[ ! -d "$PACKAGE_PATH" || -L "$PACKAGE_PATH" ]]; then
    echo "error: extracted top-level path is not a real directory: $TOP_DIR/" >&2
    exit 1
fi

WORK_ROOT_PHYS="$(cd "$WORK_ROOT" && pwd -P)"
TARBALL_DIR="$(cd "$PACKAGE_PATH" && pwd -P)"
if ! path_is_inside "$TARBALL_DIR" "$WORK_ROOT_PHYS"; then
    echo "error: extracted package root escapes work directory: $TARBALL_DIR" >&2
    exit 1
fi

while IFS= read -r -d '' link_path; do
    link_target="$(readlink "$link_path")"
    if [[ "$link_target" == /* ]]; then
        target_path="$link_target"
    else
        target_path="$(dirname "$link_path")/$link_target"
    fi
    if ! resolved_target="$(readlink -m "$target_path")"; then
        echo "error: could not resolve symlink target: $link_path -> $link_target" >&2
        exit 1
    fi
    if ! path_is_inside "$resolved_target" "$TARBALL_DIR"; then
        rel_link="${link_path#$TARBALL_DIR/}"
        echo "error: archive symlink escapes package tree: $rel_link -> $link_target" >&2
        exit 1
    fi
done < <(find "$TARBALL_DIR" -type l -print0)

while IFS= read -r -d '' file_path; do
    link_count="$(stat -c '%h' -- "$file_path")"
    [[ "$link_count" -le 1 ]] && continue

    internal_count=0
    while IFS= read -r -d '' _same_file; do
        internal_count=$((internal_count + 1))
    done < <(find "$TARBALL_DIR" -xdev -samefile "$file_path" -print0)

    if [[ "$internal_count" -lt "$link_count" ]]; then
        rel_file="${file_path#$TARBALL_DIR/}"
        echo "error: archive hardlink escapes package tree: $rel_file" >&2
        exit 1
    fi
done < <(find "$TARBALL_DIR" -xdev -type f -links +1 -print0)

LOG_DIR="$TARBALL_DIR/.test-logs"
mkdir -p "$LOG_DIR"

FAIL_PATTERN='error while loading shared libraries|cannot open shared object|symbol lookup error|undefined symbol|Could not load the Qt platform plugin|\*\*\* Fatal Error \*\*\*|Abnormal termination condition'
FAILS=0
NON_QT_RUNS=0

require_executable() {
    local bin="$1"
    if [[ ! -x "$TARBALL_DIR/$bin" ]]; then
        echo "  FAIL: required executable missing: $bin"
        FAILS=$((FAILS + 1))
        return 1
    fi
    echo "  ok: found required executable $bin"
    return 0
}

check_output() {
    local name="$1"
    local logfile="$2"
    if grep -qE "$FAIL_PATTERN" "$logfile"; then
        echo "  FAIL: $name"
        grep -E "$FAIL_PATTERN" "$logfile" | sed 's/^/        /'
        FAILS=$((FAILS + 1))
        return 1
    fi
    return 0
}

run_and_check() {
    local bin="$1"
    local -a args=("${@:2}")
    if [[ ! -x "$TARBALL_DIR/$bin" ]]; then
        echo "  skip: $bin (not present)"
        return 2
    fi
    local log="$LOG_DIR/$bin.log"
    local rc=0
    if (cd "$TARBALL_DIR" && "./$bin" "${args[@]}") > "$log" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    if ! check_output "$bin" "$log"; then
        return 1
    fi
    if [[ "$rc" -ne 0 ]]; then
        echo "  FAIL: $bin exited with status $rc"
        FAILS=$((FAILS + 1))
        return 1
    fi
    echo "  ok: $bin"
    return 0
}

echo "=== Testing non-Qt binaries ==="
echo "Target: $TARBALL_DIR"
echo "Logs:   $LOG_DIR"

require_executable openmw || true
require_executable openmw.x86_64 || true

NON_QT_BINARIES=(
    openmw
    openmw-iniimporter
    openmw-essimporter
    openmw-navmeshtool
    openmw-bulletobjecttool
    bsatool
    esmtool
    niftest
)

for bin in "${NON_QT_BINARIES[@]}"; do
    if run_and_check "$bin" --help; then
        NON_QT_RUNS=$((NON_QT_RUNS + 1))
    else
        rc=$?
        [[ "$rc" -eq 2 ]] || true
    fi
done

if [[ "$NON_QT_RUNS" -eq 0 ]]; then
    echo "  FAIL: no non-Qt binary executed successfully"
    FAILS=$((FAILS + 1))
fi

if [[ "$WITH_QT" == true ]]; then
    echo "=== Running Qt apps under timeout ==="
    QT_BINARIES=(openmw-wizard openmw-launcher openmw-cs)
    QT_TIMEOUT=5

    for bin in "${QT_BINARIES[@]}"; do
        if [[ ! -x "$TARBALL_DIR/$bin" ]]; then
            echo "  skip: $bin (not present)"
            continue
        fi
        log="$LOG_DIR/$bin.log"
        rc=0
        if (cd "$TARBALL_DIR" && timeout --signal=TERM "$QT_TIMEOUT" "./$bin") > "$log" 2>&1; then
            rc=0
        else
            rc=$?
        fi

        if grep -qE "$FAIL_PATTERN" "$log"; then
            echo "  FAIL: $bin"
            grep -E "$FAIL_PATTERN" "$log" | sed 's/^/        /'
            FAILS=$((FAILS + 1))
            continue
        fi

        if [[ "$rc" -ne 0 && "$rc" -ne 124 && "$rc" -ne 143 ]]; then
            echo "  FAIL: $bin exited with status $rc"
            FAILS=$((FAILS + 1))
            continue
        fi

        if ! grep -q 'Crash handler installed' "$log"; then
            echo "  FAIL: $bin - never reached main (no crash-handler banner in log)"
            FAILS=$((FAILS + 1))
            continue
        fi

        echo "  ok: $bin (survived ${QT_TIMEOUT}s)"
    done
fi

DISTRO_ID="unknown"
DISTRO_VER=""
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_VER="${VERSION_ID:-}"
fi
DISTRO_TAG="$DISTRO_ID"
[[ -n "$DISTRO_VER" ]] && DISTRO_TAG="${DISTRO_ID}-${DISTRO_VER}"
DISTRO_TAG="$(echo "$DISTRO_TAG" | tr ' /' '__')"

RESULTS_PATH="$OUTPUT_DIR/RESULTS_${DISTRO_TAG}.tar.gz"
echo "=== Archiving logs ==="
echo "  distro:  $DISTRO_TAG"
echo "  results: $RESULTS_PATH"
tar czf "$RESULTS_PATH" -C "$TARBALL_DIR" "$(basename "$LOG_DIR")"

if [[ "$FAILS" -eq 0 ]]; then
    echo "=== All checks passed ==="
    exit 0
fi

echo "=== $FAILS check(s) failed ==="
exit 1
