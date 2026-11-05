#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JESS_BIN="${JESS_BIN:-$(command -v jess || true)}"
[[ -n "$JESS_BIN" ]] || { echo 'error: set JESS_BIN to the Jess executable' >&2; exit 1; }
JESS_BIN="$(readlink -f "$JESS_BIN")"
export JESS_BIN
cd "$ROOT"

printf '\n== Jess strict package check ==\n'
"$JESS_BIN" package check .
printf '\n== Jess package tests: source and packed ==\n'
"$JESS_BIN" workspace test > /dev/null
printf 'PASS: Jess source and packed test suites\n'
printf '\n== Jess style check ==\n'
"$JESS_BIN" run --trusted tools/style.jsl
printf '\n== Bash syntax of retained leaf workers ==\n'
while IFS= read -r -d '' file; do
    bash -n "$file"
done < <(find vendor -type f -name '*.sh' -print0)
printf 'PASS: bash -n for retained leaf workers\n'
printf '\n== Mock container engine integration ==\n'
bash tests/integration.sh
printf '\n== Package archive safety ==\n'
bash tests/archive_safety.sh
printf '\nPASS: all available validation gates\n'
