#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'if [[ -f "$scratch/uberbranch.jsl" ]]; then cp "$scratch/uberbranch.jsl" "$root/src/uberbranch.jsl"; fi; rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/assets"
real_git=$(command -v git)
cat > "$scratch/bin/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == ls-remote ]]; then
  if [[ "${MOCK_GIT_FAIL:-false}" == true ]]; then exit 2; fi
  sha=${MOCK_SOURCE_SHA:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}
  printf '%s\trefs/heads/master\n' "$sha"
else
  exec "$REAL_GIT" "$@"
fi
MOCK
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MOCK_GH_MODE:-missing}" == api-fail ]]; then exit 1; fi
if [[ "$1" == release && "$2" == view ]]; then
  if [[ "${MOCK_GH_MODE:-missing}" == missing ]]; then echo 'HTTP 404: Not Found' >&2; exit 1; fi
  printf '%s\n' "$MOCK_RELEASE_JSON"
elif [[ "$1" == release && "$2" == download ]]; then
  while (($#)); do
    if [[ "$1" == --dir ]]; then target="$2"; shift 2; else shift; fi
  done
  cp "$MOCK_ASSET_DIR"/* "$target/"
else exit 3; fi
MOCK
chmod +x "$scratch/bin/git" "$scratch/bin/gh"

export PATH="$scratch/bin:$PATH" REAL_GIT="$real_git"
export GITHUB_OUTPUT="$scratch/output" GITHUB_STEP_SUMMARY="$scratch/summary" GITHUB_TOKEN=fixture
export OPENMW_REPOSITORY=https://example.invalid/openmw.git OPENMW_REF=master OPENMW_RELEASE_TAG=das-uberbranch
export OPENMW_PROFILE=upstream
export FORGE_TOOLCHAIN_ID=ghcr.io/example/forge-builder@sha256:$(printf 'b%.0s' {1..64}) RUNNER_ARCH=X64
export MOCK_RELEASE_JSON='{}'

run_preflight() { : > "$GITHUB_OUTPUT"; : > "$GITHUB_STEP_SUMMARY"; bash "$root/tools/release_preflight.sh"; }
output() { sed -n "s/^$1=//p" "$GITHUB_OUTPUT" | tail -n1; }

run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == release-missing ]] || exit 1
fp=$(output input_fingerprint); sha=$(output source_sha); inputs=$(output inputs_json)
mkdir -p "$scratch/assets"
printf 'archive payload\n' > "$scratch/assets/openmw-0.53.0-g${sha:0:12}-Linux-64Bit.tar.gz"
printf 'debug payload\n' > "$scratch/assets/openmw-0.53.0-g${sha:0:12}-Linux-64Bit-debug.tar.gz"
printf 'Profile: %s\nGitHub release: %s\nOpenMW repository: %s\nOpenMW requested ref: %s\nOpenMW resolved SHA: %s\nBuild input fingerprint: %s\n' \
  "$OPENMW_PROFILE" "$OPENMW_RELEASE_TAG" "$OPENMW_REPOSITORY" "$OPENMW_REF" "$sha" "$fp" > "$scratch/assets/SOURCE.txt"
jq -cnS --arg fp "$fp" --arg sha "$sha" --arg repo "$OPENMW_REPOSITORY" --arg ref "$OPENMW_REF" \
  --argjson inputs "$inputs" \
  '{schema:"forge-qualified-release/v1",qualified:true,input_fingerprint:$fp,source_sha:$sha,repository:$repo,requested_ref:$ref,profile:"upstream",release_tag:"das-uberbranch",inputs:$inputs}' \
  > "$scratch/assets/PROVENANCE.json"
(cd "$scratch/assets" && sha256sum openmw-* SOURCE.txt PROVENANCE.json > SHA256SUMS)
export MOCK_ASSET_DIR="$scratch/assets" MOCK_GH_MODE=present
export MOCK_RELEASE_JSON=$(jq -cn --argjson names "$(find "$scratch/assets" -maxdepth 1 -type f -printf '%f\n' | jq -R . | jq -s .)" \
  '{isPrerelease:true,assets:[$names[]|{name:.}]}')
run_preflight
[[ "$(output should_build)" == false && "$(output reason)" == skipped-qualified ]] || exit 1
OPENMW_PROFILE=clockwork run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == invalid-or-mismatched-provenance ]] || exit 1
grep -Fq -- '- Profile: `clockwork`' "$GITHUB_STEP_SUMMARY" || exit 1

cp "$scratch/assets/PROVENANCE.json" "$scratch/provenance.json"
jq '.qualified = false' "$scratch/assets/PROVENANCE.json" > "$scratch/provenance.invalid"
mv "$scratch/provenance.invalid" "$scratch/assets/PROVENANCE.json"
(cd "$scratch/assets" && sha256sum openmw-* SOURCE.txt PROVENANCE.json > SHA256SUMS)
run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == invalid-or-mismatched-provenance ]] || exit 1
mv "$scratch/provenance.json" "$scratch/assets/PROVENANCE.json"
(cd "$scratch/assets" && sha256sum openmw-* SOURCE.txt PROVENANCE.json > SHA256SUMS)

cp "$scratch/assets/SHA256SUMS" "$scratch/SHA256SUMS"
rm "$scratch/assets/SHA256SUMS"
export MOCK_RELEASE_JSON=$(jq -cn --argjson names "$(find "$scratch/assets" -maxdepth 1 -type f -printf '%f\n' | jq -R . | jq -s .)" \
  '{isPrerelease:true,assets:[$names[]|{name:.}]}')
run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == incomplete-release-assets ]] || exit 1
mv "$scratch/SHA256SUMS" "$scratch/assets/SHA256SUMS"
export MOCK_RELEASE_JSON=$(jq -cn --argjson names "$(find "$scratch/assets" -maxdepth 1 -type f -printf '%f\n' | jq -R . | jq -s .)" \
  '{isPrerelease:true,assets:[$names[]|{name:.}]}')

cp "$root/src/uberbranch.jsl" "$scratch/uberbranch.jsl"
printf '\n-- fixture recipe change\n' >> "$root/src/uberbranch.jsl"
run_preflight
mv "$scratch/uberbranch.jsl" "$root/src/uberbranch.jsl"
[[ "$(output should_build)" == true && "$(output reason)" == invalid-or-mismatched-provenance ]] || exit 1

FORCE_REBUILD=true run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == manual-force-rebuild ]] || exit 1
unset FORCE_REBUILD

MOCK_SOURCE_SHA=cccccccccccccccccccccccccccccccccccccccc run_preflight
[[ "$(output should_build)" == true ]] || exit 1
unset MOCK_SOURCE_SHA

FORGE_TOOLCHAIN_ID=ghcr.io/example/forge-builder@sha256:$(printf 'd%.0s' {1..64}) run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == invalid-or-mismatched-provenance ]] || exit 1

printf 'corrupt\n' >> "$scratch/assets/SOURCE.txt"
MOCK_GH_MODE=present run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == missing-or-invalid-checksum-payload ]] || exit 1

if MOCK_GH_MODE=api-fail run_preflight >/dev/null 2>&1; then
  echo 'release API failure unexpectedly passed preflight' >&2; exit 1
fi
[[ "$(output should_build)" == true && "$(output reason)" == release-api-unavailable ]] || exit 1

if MOCK_GIT_FAIL=true MOCK_GH_MODE=present run_preflight >/dev/null 2>&1; then
  echo 'source API failure unexpectedly passed preflight' >&2; exit 1
fi

cat > "$scratch/bin/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
[[ "$1 $2 $3" == 'manifest inspect --verbose' ]] || { echo 'preflight attempted a Docker pull/build' >&2; exit 9; }
printf '{"Descriptor":{"digest":"sha256:%064d"}}\n' 1
MOCK
chmod +x "$scratch/bin/docker"
export GITHUB_REPOSITORY=DreamWeave-MP/openmw-forge
export GITHUB_OUTPUT="$scratch/toolchain-output" GITHUB_ENV="$scratch/toolchain-env"
export MOCK_DOCKER_LOG="$scratch/docker.log"
(cd "$root" && jess run --trusted --package . tools/toolchain_image.jsl --preflight >/dev/null)
grep -q '^toolchain_id=ghcr.io/dreamweave-mp/openmw-forge-builder@sha256:' "$GITHUB_OUTPUT" || exit 1
if grep -Eq '(^| )(pull|build)( |$)' "$MOCK_DOCKER_LOG"; then
  echo 'toolchain identity preflight downloaded or built an image' >&2; exit 1
fi
echo 'PASS release preflight fixtures: absent, qualified skip, incomplete assets, corrupt provenance, changed recipe/source/toolchain, force, corrupt checksum payload, API failures, manifest-only toolchain identity'
