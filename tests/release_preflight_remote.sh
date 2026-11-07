#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/checkout"

# Keep the GitHub release absent while allowing the source resolver and pinned
# fetch to talk to the real OpenMW GitLab repository.
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == release && "$2" == view ]]; then
  echo 'HTTP 404: Not Found' >&2
  exit 1
fi
exit 2
MOCK
chmod +x "$scratch/bin/gh"

export PATH="$scratch/bin:$PATH"
export GITHUB_OUTPUT="$scratch/output" GITHUB_STEP_SUMMARY="$scratch/summary" GITHUB_TOKEN=remote-test
export OPENMW_REPOSITORY=https://gitlab.com/OpenMW/openmw.git OPENMW_REF=master
export OPENMW_RELEASE_TAG=das-uberbranch OPENMW_PROFILE=upstream RUNNER_ARCH=X64
export FORGE_TOOLCHAIN_ID="fallback:$(printf 'a%.0s' {1..64}):$(printf 'b%.0s' {1..64})"

bash "$root/tools/release_preflight.sh"
resolved=$(sed -n 's/^source_sha=//p' "$GITHUB_OUTPUT")
[[ "$resolved" =~ ^[0-9a-f]{40}$ ]] || { echo 'preflight did not return a full source SHA' >&2; exit 1; }
[[ "$(sed -n 's/^reason=//p' "$GITHUB_OUTPUT")" == release-missing ]] || exit 1

git init -q "$scratch/checkout"
git -C "$scratch/checkout" fetch --quiet --depth=1 --no-tags "$OPENMW_REPOSITORY" "$resolved"
fetched=$(git -C "$scratch/checkout" rev-parse FETCH_HEAD)
[[ "$fetched" == "$resolved" ]] || { echo 'GitLab fetch did not return the exact preflight SHA' >&2; exit 1; }
echo "PASS live GitLab source preflight and pinned fetch: $fetched"
