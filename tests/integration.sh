#!/usr/bin/env bash
set -euo pipefail

# Host-side integration tests: actual Jess CLI + real filesystem + mocked engine.
# No Docker, Podman, network, or OpenMW compilation is required.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JESS_BIN="${JESS_BIN:-$(command -v jess || true)}"
if [[ -z "$JESS_BIN" ]]; then
    echo 'error: set JESS_BIN to the Jess executable before running integration tests' >&2
    exit 1
fi
JESS_BIN="$(readlink -f "$JESS_BIN")"
cd "$ROOT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/mockbin" "$TMP/source" "$TMP/existing-build"
printf 'cmake_minimum_required(VERSION 3.20)\n' > "$TMP/source/CMakeLists.txt"
printf 'fake archive\n' > "$TMP/dependencies.7z"
export MOCK_LOG="$TMP/engine.log"
: > "$MOCK_LOG"
cat > "$TMP/mockbin/podman" <<'MOCK'
#!/usr/bin/env bash
printf 'BEGIN\n' >> "$MOCK_LOG"
printf 'arg=[%s]\n' "$@" >> "$MOCK_LOG"
printf 'END\n' >> "$MOCK_LOG"
if [[ "${1:-}" == '--version' ]]; then
    echo 'podman mock 1.0'
    exit 0
fi
if [[ "${MOCK_FAIL_ON:-}" == "${1:-}" ]]; then
    exit 42
fi
MOCK
chmod +x "$TMP/mockbin/podman"
export PATH="$TMP/mockbin:$PATH"

run() {
    "$JESS_BIN" workspace run --trusted forge -- "$@"
}
assert_present() {
    grep -F -- "$1" "$2" >/dev/null || { echo "missing expected text: $1" >&2; exit 1; }
}
assert_absent() {
    if grep -F -- "$1" "$2" >/dev/null; then
        echo "unexpected text: $1" >&2
        exit 1
    fi
}
expect_failure() {
    local expect="$1"
    shift
    if run "$@" > "$TMP/failure.log" 2>&1; then
        echo "unexpected success: $*" >&2
        exit 1
    fi
    assert_present "$expect" "$TMP/failure.log"
}

# 1. Truly side-effect-free planning: even a destination directory is not created.
run deps --dry-run --deps-output "$TMP/no-side-effects" > "$TMP/dry-run.log"
assert_present 'BASE_IMAGE=almalinux:9' "$TMP/dry-run.log"
[[ ! -e "$TMP/no-side-effects" ]]
[[ ! -s "$MOCK_LOG" ]]

# 2. Real CLI executes two separated spawn calls; no shell interpretation.
run deps --deps-output "$TMP/dependency-output" > "$TMP/deps.log"
assert_present 'arg=[BASE_IMAGE=almalinux:9]' "$MOCK_LOG"
assert_present 'arg=[PROFILE=alma9]' "$MOCK_LOG"
[[ "$(grep -c '^BEGIN$' "$MOCK_LOG")" -eq 2 ]]

# 3. Real build command forwards a CMake string as one literal argument.
: > "$MOCK_LOG"
run build --source "$TMP/source" --deps-archive "$TMP/dependencies.7z" \
    --build-dir "$TMP/build" --deps-prefix "$TMP/install" --output-dir "$TMP/out" \
    --run-tests --gtest-filter 'Loader.*' --cmake-arg '-DVALUE=hello; $(touch /tmp/never-run-this)' \
    > "$TMP/build.log"
assert_present 'arg=[-DVALUE=hello; $(touch /tmp/never-run-this)]' "$MOCK_LOG"
assert_present 'arg=[--run-tests]' "$MOCK_LOG"
assert_present 'arg=[Loader.*]' "$MOCK_LOG"
assert_present 'arg=[/input/deps.7z]' "$MOCK_LOG"
[[ "$(grep -c '^BEGIN$' "$MOCK_LOG")" -eq 2 ]]

# 4. A missing archive stops before the engine receives any command.
: > "$MOCK_LOG"
expect_failure 'required file not found' build --source "$TMP/source" --deps-archive "$TMP/no.7z"
[[ ! -s "$MOCK_LOG" ]]

# 5. Symlinks to writable paths inside the source are rejected before spawning.
mkdir -p "$TMP/source/writable"
ln -s "$TMP/source/writable" "$TMP/indirect-build"
expect_failure 'writable path overlaps OpenMW source' build \
    --source "$TMP/source" --build-dir "$TMP/indirect-build" \
    --deps-archive "$TMP/dependencies.7z"
[[ ! -s "$MOCK_LOG" ]]

# 6. Failures abort the pipeline instead of proceeding to a subsequent stage.
export MOCK_FAIL_ON=run
expect_failure 'exited with 42' pipeline --source "$TMP/source"
unset MOCK_FAIL_ON
[[ "$(grep -c '^BEGIN$' "$MOCK_LOG")" -eq 2 ]]

# 7. Doctor makes explicit, non-destructive prerequisite checks.
: > "$MOCK_LOG"
run doctor > "$TMP/doctor.log"
assert_present 'PASS podman' "$TMP/doctor.log"
assert_present 'PASS AlmaLinux 9' "$TMP/doctor.log"

# 8. Invalid flags produce errors without starting external tools.
: > "$MOCK_LOG"
expect_failure 'unknown option' deps --invented
[[ ! -s "$MOCK_LOG" ]]

# 9. Preflight refuses missing source trees before mutating build outputs.
expect_failure 'required file not found' build --source "$TMP/no-source" \
    --deps-archive "$TMP/dependencies.7z" --build-dir "$TMP/not-created"
[[ ! -e "$TMP/not-created" ]]

printf 'PASS: 9 CLI integration scenarios (mocked container engine)\n'
