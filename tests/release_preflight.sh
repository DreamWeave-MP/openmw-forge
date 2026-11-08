#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'if [[ -f "$scratch/uberbranch.jsl" ]]; then cp "$scratch/uberbranch.jsl" "$root/src/uberbranch.jsl"; fi; if [[ -f "$scratch/release-profiles.jsl" ]]; then cp "$scratch/release-profiles.jsl" "$root/ci/release-profiles.jsl"; fi; if [[ -f "$scratch/forge-ci.yml" ]]; then cp "$scratch/forge-ci.yml" "$root/.github/workflows/forge-ci.yml"; fi; if [[ -f "$scratch/clockwork-workflow.yml" ]]; then cp "$scratch/clockwork-workflow.yml" "$root/.github/workflows/das-uberbranch-clockwork.yml"; fi; rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/assets"
real_git=$(command -v git)
cat > "$scratch/bin/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == ls-remote ]]; then
  if [[ "${MOCK_GIT_FAIL:-false}" == true ]]; then exit 2; fi
  sha=${MOCK_SOURCE_SHA:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}
  peeled=${MOCK_PEELED_SHA:-cccccccccccccccccccccccccccccccccccccccc}
  mode=${MOCK_GIT_MODE:-branch}
  shift 2
  for query in "$@"; do
    case "$query" in
      refs/heads/*)
        if [[ "$mode" == branch || "$mode" == collision ]]; then printf '%s\t%s\n' "$sha" "$query"; fi
        ;;
      refs/tags/*\^\{\})
        if [[ "$mode" == tag || "$mode" == collision ]]; then printf '%s\t%s\n' "$peeled" "$query"; fi
        ;;
      refs/tags/*)
        if [[ "$mode" == tag || "$mode" == collision ]]; then
          printf '%s\t%s\n' bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$query"
        fi
        ;;
    esac
  done
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
  patterns=()
  while (($#)); do
    if [[ "$1" == --dir ]]; then target="$2"; shift 2
    elif [[ "$1" == --pattern ]]; then patterns+=("$2"); shift 2
    else shift; fi
  done
  printf '%s\n' "${patterns[*]}" >> "$MOCK_DOWNLOAD_LOG"
  for pattern in "${patterns[@]}"; do cp "$MOCK_ASSET_DIR/$pattern" "$target/"; done
else exit 3; fi
MOCK
chmod +x "$scratch/bin/git" "$scratch/bin/gh"

export PATH="$scratch/bin:$PATH" REAL_GIT="$real_git"
export GITHUB_OUTPUT="$scratch/output" GITHUB_STEP_SUMMARY="$scratch/summary" GITHUB_TOKEN=fixture
export OPENMW_REPOSITORY=https://example.invalid/openmw.git OPENMW_REF=master OPENMW_RELEASE_TAG=das-uberbranch
export OPENMW_PROFILE=upstream
export FORGE_TOOLCHAIN_ID=ghcr.io/example/forge-builder@sha256:$(printf 'b%.0s' {1..64}) RUNNER_ARCH=X64
export FORGE_JESS_IDENTITY=dev@sha256:$(printf 'd%.0s' {1..64})
export FORGE_PROFILE_SETTINGS_JSON='{"schema":"forge-profile-settings/v1","profile":"upstream","repository":"https://example.invalid/openmw.git","ref":"master","release_tag":"das-uberbranch","jobs":"auto","distros":"almalinux-9,ubuntu-24.04","cmake_args":[],"features":{"vulkan":false,"luau":false,"lua_ui":false},"test_policy":{"google_tests":true,"package_smoke":true,"qt_smoke":true}}'
export MOCK_RELEASE_JSON='{}' MOCK_DOWNLOAD_LOG="$scratch/downloads.log"

run_preflight() { : > "$GITHUB_OUTPUT"; : > "$GITHUB_STEP_SUMMARY"; (cd "$root" && jess run --trusted --package . tools/release_preflight.jsl); }
output() { sed -n "s/^$1=//p" "$GITHUB_OUTPUT" | tail -n1; }

refresh_release_json() {
  local asset_list='[]' path name digest directory="${1:-$scratch/assets}"
  for path in "$directory"/*; do
    [[ -f "$path" ]] || continue
    name=${path##*/}
    digest=$(sha256sum "$path" | cut -d' ' -f1)
    entry="{\"name\":\"$name\",\"digest\":\"sha256:$digest\"}"
    if [[ "$asset_list" == '[]' ]]; then asset_list="[$entry]"; else asset_list="${asset_list%]},$entry]"; fi
  done
  MOCK_RELEASE_JSON="{\"isPrerelease\":true,\"assets\":$asset_list}"
  export MOCK_RELEASE_JSON
}

run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == release-missing ]] || exit 1
upstream_fp=$(output input_fingerprint)
cp "$root/ci/release-profiles.jsl" "$scratch/release-profiles.jsl"
sed -i 's/OpenMW Clockwork experimental/Clockwork title-only fixture edit/' "$root/ci/release-profiles.jsl"
cp "$root/.github/workflows/forge-ci.yml" "$scratch/forge-ci.yml"
sed -i 's/Forge validation and documentation/Unrelated validation workflow fixture/' "$root/.github/workflows/forge-ci.yml"
run_preflight
[[ "$(output input_fingerprint)" == "$upstream_fp" ]] || {
  echo 'Clockwork metadata or unrelated workflow changed the upstream fingerprint' >&2; exit 1;
}
cp "$root/.github/workflows/das-uberbranch-clockwork.yml" "$scratch/clockwork-workflow.yml"
sed -i 's/name: OpenMW Clockwork experimental prerelease/name: Clockwork fingerprint fixture edit/' \
  "$root/.github/workflows/das-uberbranch-clockwork.yml"
run_preflight
[[ "$(output input_fingerprint)" == "$upstream_fp" ]] || {
  echo 'Clockwork workflow edit changed the upstream fingerprint' >&2; exit 1;
}
cp "$scratch/clockwork-workflow.yml" "$root/.github/workflows/das-uberbranch-clockwork.yml"
cp "$scratch/release-profiles.jsl" "$root/ci/release-profiles.jsl"
cp "$scratch/forge-ci.yml" "$root/.github/workflows/forge-ci.yml"
FORGE_PROFILE_SETTINGS_JSON=${FORGE_PROFILE_SETTINGS_JSON/'"cmake_args":[]'/'"cmake_args":["-DUPSTREAM_TEST_FEATURE=ON"]'} run_preflight
[[ "$(output input_fingerprint)" != "$upstream_fp" ]] || {
  echo 'selected profile build settings did not change the fingerprint' >&2; exit 1;
}
FORGE_PROFILE_SETTINGS_JSON=$FORGE_PROFILE_SETTINGS_JSON FORGE_JESS_IDENTITY=dev@sha256:$(printf 'e%.0s' {1..64}) run_preflight
[[ "$(output input_fingerprint)" != "$upstream_fp" ]] || {
  echo 'selected immutable Jess runtime identity did not change the fingerprint' >&2; exit 1;
}
MOCK_GIT_MODE=branch OPENMW_REF=refs/heads/master \
  FORGE_PROFILE_SETTINGS_JSON=${FORGE_PROFILE_SETTINGS_JSON/'"ref":"master"'/'"ref":"refs/heads/master"'} run_preflight
[[ "$(output source_sha)" == aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ]] || exit 1
MOCK_GIT_MODE=tag OPENMW_REF=refs/tags/v1.0 \
  FORGE_PROFILE_SETTINGS_JSON=${FORGE_PROFILE_SETTINGS_JSON/'"ref":"master"'/'"ref":"refs/tags/v1.0"'} run_preflight
[[ "$(output source_sha)" == cccccccccccccccccccccccccccccccccccccccc ]] || exit 1
if MOCK_GIT_MODE=collision OPENMW_REF=master run_preflight >/dev/null 2>&1; then
  echo 'unqualified branch/tag collision unexpectedly passed' >&2; exit 1
fi
if MOCK_GIT_MODE=tag OPENMW_REF=refs/tags/v1.0 \
  FORGE_PROFILE_SETTINGS_JSON=${FORGE_PROFILE_SETTINGS_JSON/'"ref":"master"'/'"ref":"refs/tags/v1.0"'} run_preflight >/dev/null 2>&1; then :; else
  echo 'qualified annotated tag unexpectedly failed' >&2; exit 1
fi
run_preflight
fp=$(output input_fingerprint); sha=$(output source_sha); inputs=$(output inputs_json)
mkdir -p "$scratch/assets"
printf 'archive payload\n' > "$scratch/assets/openmw-0.53.0-g${sha:0:12}-Linux-64Bit.tar.gz"
printf 'debug payload\n' > "$scratch/assets/openmw-0.53.0-g${sha:0:12}-Linux-64Bit-debug.tar.gz"
printf 'Profile: %s\nGitHub release: %s\nOpenMW repository: %s\nOpenMW requested ref: %s\nOpenMW resolved SHA: %s\nBuild input fingerprint: %s\n' \
  "$OPENMW_PROFILE" "$OPENMW_RELEASE_TAG" "$OPENMW_REPOSITORY" "$OPENMW_REF" "$sha" "$fp" > "$scratch/assets/SOURCE.txt"
printf '{"input_fingerprint":"%s","inputs":%s,"profile":"upstream","qualified":true,"release_tag":"das-uberbranch","repository":"%s","requested_ref":"%s","schema":"forge-qualified-release/v1","source_sha":"%s"}\n' \
  "$fp" "$inputs" "$OPENMW_REPOSITORY" "$OPENMW_REF" "$sha" > "$scratch/assets/PROVENANCE.json"
(cd "$scratch/assets" && sha256sum openmw-* SOURCE.txt PROVENANCE.json > SHA256SUMS)
export MOCK_ASSET_DIR="$scratch/assets" MOCK_GH_MODE=present
refresh_release_json
run_preflight
[[ "$(output should_build)" == false && "$(output reason)" == skipped-qualified ]] || exit 1
OPENMW_PROFILE=clockwork OPENMW_REPOSITORY=https://example.invalid/clockwork.git \
  OPENMW_REF=clockwork-alpha OPENMW_RELEASE_TAG=das-uberbranch-clockwork \
  FORGE_PROFILE_SETTINGS_JSON="$(printf '%s' "$FORGE_PROFILE_SETTINGS_JSON" | sed -e 's|"profile":"upstream"|"profile":"clockwork"|' -e 's|"repository":"https://example.invalid/openmw.git"|"repository":"https://example.invalid/clockwork.git"|' -e 's|"ref":"master"|"ref":"clockwork-alpha"|' -e 's|"release_tag":"das-uberbranch"|"release_tag":"das-uberbranch-clockwork"|' -e 's|"cmake_args":\[\]|"cmake_args":["-DOPENMW_USE_VULKAN=ON"]|' -e 's|"features":{[^}]*}|"features":{"vulkan":true,"luau":true,"lua_ui":true}|')" \
  run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == incomplete-release-assets ]] || exit 1
grep -Fq -- '- Profile: `clockwork`' "$GITHUB_STEP_SUMMARY" || exit 1
grep -qx 'SHA256SUMS SOURCE.txt PROVENANCE.json' "$MOCK_DOWNLOAD_LOG" || exit 1
if grep -q 'openmw-.*tar.gz' "$MOCK_DOWNLOAD_LOG"; then
  echo 'preflight downloaded a large OpenMW archive' >&2; exit 1
fi

cp "$scratch/assets/PROVENANCE.json" "$scratch/provenance.json"
sed 's/"qualified":true/"qualified":false/' "$scratch/assets/PROVENANCE.json" > "$scratch/provenance.invalid"
mv "$scratch/provenance.invalid" "$scratch/assets/PROVENANCE.json"
(cd "$scratch/assets" && sha256sum openmw-* SOURCE.txt PROVENANCE.json > SHA256SUMS)
refresh_release_json
run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == invalid-or-mismatched-provenance ]] || exit 1
mv "$scratch/provenance.json" "$scratch/assets/PROVENANCE.json"
(cd "$scratch/assets" && sha256sum openmw-* SOURCE.txt PROVENANCE.json > SHA256SUMS)
refresh_release_json

cp "$scratch/assets/SHA256SUMS" "$scratch/SHA256SUMS"
rm "$scratch/assets/SHA256SUMS"
refresh_release_json
run_preflight
[[ "$(output should_build)" == true && "$(output reason)" == incomplete-release-assets ]] || exit 1
mv "$scratch/SHA256SUMS" "$scratch/assets/SHA256SUMS"
refresh_release_json

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
refresh_release_json
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
if [[ "$1 $2 $3" == 'manifest inspect --verbose' ]]; then
  if [[ "${MOCK_IMAGE_MISSING:-false}" == true && "$4" == ghcr.io/* ]]; then exit 1; fi
elif [[ "$1" == pull && ( "$2" == ghcr.io/*@sha256:* || "$2" == almalinux/9-base@sha256:* ) ]]; then exit 0
else echo 'unexpected Docker command during toolchain resolution' >&2; exit 9; fi
if [[ "$1" == pull ]]; then exit 0; fi
case "${MOCK_MANIFEST_SHAPE:-descriptor}" in
  index)
    printf '[{"Descriptor":{"digest":"sha256:%s","platform":{"os":"linux","architecture":"amd64"}}},{"Descriptor":{"digest":"sha256:%s","platform":{"os":"linux","architecture":"arm64"}}}]\n' \
      "$(printf 'a%.0s' {1..64})" "$(printf 'b%.0s' {1..64})"
    ;;
  digest)
    printf '{"Digest":"sha256:%s"}\n' "$(printf 'c%.0s' {1..64})"
    ;;
  descriptor)
    printf '{"Descriptor":{"digest":"sha256:%s"}}\n' "$(printf 'd%.0s' {1..64})"
    ;;
  *) exit 8 ;;
esac
MOCK
chmod +x "$scratch/bin/docker"
export GITHUB_REPOSITORY=DreamWeave-MP/openmw-forge
export GITHUB_OUTPUT="$scratch/toolchain-output" GITHUB_ENV="$scratch/toolchain-env"
export MOCK_DOCKER_LOG="$scratch/docker.log"
run_toolchain_preflight() {
  : > "$GITHUB_OUTPUT"; : > "$GITHUB_ENV"
  (cd "$root" && jess run --trusted --package . tools/toolchain_image.jsl --preflight >/dev/null)
}
MOCK_MANIFEST_SHAPE=index run_toolchain_preflight
grep -q "^toolchain_id=ghcr.io/dreamweave-mp/openmw-forge-builder@sha256:$(printf 'a%.0s' {1..64})$" "$GITHUB_OUTPUT" || exit 1
MOCK_MANIFEST_SHAPE=digest run_toolchain_preflight
grep -q "^toolchain_id=ghcr.io/dreamweave-mp/openmw-forge-builder@sha256:$(printf 'c%.0s' {1..64})$" "$GITHUB_OUTPUT" || exit 1
MOCK_MANIFEST_SHAPE=descriptor run_toolchain_preflight
grep -q '^toolchain_id=ghcr.io/dreamweave-mp/openmw-forge-builder@sha256:' "$GITHUB_OUTPUT" || exit 1
if grep -Eq '(^| )(pull|build)( |$)' "$MOCK_DOCKER_LOG"; then
  echo 'toolchain identity preflight downloaded or built an image' >&2; exit 1
fi
: > "$MOCK_DOCKER_LOG"
: > "$GITHUB_OUTPUT"; : > "$GITHUB_ENV"
export MOCK_MANIFEST_SHAPE=index
(cd "$root" && jess run --trusted --package . tools/toolchain_image.jsl >/dev/null)
expected_pinned="ghcr.io/dreamweave-mp/openmw-forge-builder@sha256:$(printf 'a%.0s' {1..64})"
grep -qx "toolchain_id=$expected_pinned" "$GITHUB_OUTPUT" || exit 1
grep -qx "FORGE_TOOLCHAIN_IMAGE=$expected_pinned" "$GITHUB_ENV" || exit 1
grep -qx "pull $expected_pinned" "$MOCK_DOCKER_LOG" || exit 1
export MOCK_IMAGE_MISSING=true MOCK_MANIFEST_SHAPE=descriptor
run_toolchain_preflight
fallback_preflight_id=$(sed -n 's/^toolchain_id=//p' "$GITHUB_OUTPUT")
[[ "$fallback_preflight_id" == fallback:* ]] || exit 1
: > "$MOCK_DOCKER_LOG"; : > "$GITHUB_OUTPUT"; : > "$GITHUB_ENV"
(cd "$root" && jess run --trusted --package . tools/toolchain_image.jsl >/dev/null)
fallback_actual_id=$(sed -n 's/^toolchain_id=//p' "$GITHUB_OUTPUT")
[[ "$fallback_actual_id" == "$fallback_preflight_id" ]] || exit 1
grep -q '^FORGE_TOOLCHAIN_BASE_IMAGE=almalinux/9-base@sha256:' "$GITHUB_ENV" || exit 1
unset MOCK_IMAGE_MISSING MOCK_MANIFEST_SHAPE

# Clockwork's own workflow is a build input for Clockwork, while remaining
# irrelevant to upstream release identity. A qualified Clockwork marker also
# requires its Vulkan evidence asset and checksum.
OPENMW_PROFILE=clockwork
OPENMW_REPOSITORY=https://example.invalid/clockwork.git
OPENMW_REF=clockwork-alpha
OPENMW_RELEASE_TAG=das-uberbranch-clockwork
FORGE_PROFILE_SETTINGS_JSON="$(printf '%s' "$FORGE_PROFILE_SETTINGS_JSON" | sed -e 's|"profile":"upstream"|"profile":"clockwork"|' -e 's|"repository":"https://example.invalid/openmw.git"|"repository":"https://example.invalid/clockwork.git"|' -e 's|"ref":"master"|"ref":"clockwork-alpha"|' -e 's|"release_tag":"das-uberbranch"|"release_tag":"das-uberbranch-clockwork"|' -e 's|"cmake_args":\[\]|"cmake_args":["-DOPENMW_USE_VULKAN=ON","-DOPENMW_USE_SYSTEM_GLSLANG=OFF","-DOPENMW_USE_SYSTEM_VULKAN_HEADERS=OFF","-DOPENMW_USE_SYSTEM_VMA=OFF"]|' -e 's|"features":{[^}]*}|"features":{"vulkan":true,"luau":true,"lua_ui":true}|')"
export OPENMW_PROFILE OPENMW_REPOSITORY OPENMW_REF OPENMW_RELEASE_TAG FORGE_PROFILE_SETTINGS_JSON
MOCK_GH_MODE=missing run_preflight
clockwork_fp=$(output input_fingerprint)
sed -i 's/name: OpenMW Clockwork experimental prerelease/name: Clockwork fingerprint fixture edit/' \
  "$root/.github/workflows/das-uberbranch-clockwork.yml"
MOCK_GH_MODE=missing run_preflight
[[ "$(output input_fingerprint)" != "$clockwork_fp" ]] || {
  echo 'Clockwork workflow edit did not change the Clockwork fingerprint' >&2; exit 1;
}
cp "$scratch/clockwork-workflow.yml" "$root/.github/workflows/das-uberbranch-clockwork.yml"
MOCK_GH_MODE=missing run_preflight
clockwork_fp=$(output input_fingerprint); clockwork_sha=$(output source_sha); clockwork_inputs=$(output inputs_json)
mkdir -p "$scratch/clockwork-assets"
printf 'clockwork archive\n' > "$scratch/clockwork-assets/openmw-0.52.0-g${clockwork_sha:0:12}-Linux-64Bit.tar.gz"
printf 'clockwork debug archive\n' > "$scratch/clockwork-assets/openmw-0.52.0-g${clockwork_sha:0:12}-Linux-64Bit-debug.tar.gz"
printf 'Profile: clockwork\nGitHub release: das-uberbranch-clockwork\nOpenMW repository: %s\nOpenMW requested ref: clockwork-alpha\nOpenMW resolved SHA: %s\nBuild input fingerprint: %s\n' \
  "$OPENMW_REPOSITORY" "$clockwork_sha" "$clockwork_fp" > "$scratch/clockwork-assets/SOURCE.txt"
printf '{"input_fingerprint":"%s","inputs":%s,"profile":"clockwork","qualified":true,"release_tag":"%s","repository":"%s","requested_ref":"%s","schema":"forge-qualified-release/v1","source_sha":"%s"}\n' \
  "$clockwork_fp" "$clockwork_inputs" "$OPENMW_RELEASE_TAG" "$OPENMW_REPOSITORY" "$OPENMW_REF" "$clockwork_sha" > "$scratch/clockwork-assets/PROVENANCE.json"
printf 'Profile: clockwork\nRenderer: vulkan 1.3\nClockwork source SHA: %s\nExample-suite SHA: a1ba6fc9d7315c2158ef4c60349fc4e71b7ca343\nBuilder image: %s\n' \
  "$clockwork_sha" "$FORGE_TOOLCHAIN_ID" > "$scratch/clockwork-assets/VULKAN-QUALIFICATION.txt"
(cd "$scratch/clockwork-assets" && sha256sum openmw-* SOURCE.txt PROVENANCE.json VULKAN-QUALIFICATION.txt > SHA256SUMS)
export MOCK_ASSET_DIR="$scratch/clockwork-assets"
refresh_release_json "$scratch/clockwork-assets"
MOCK_GH_MODE=present run_preflight
[[ "$(output should_build)" == false && "$(output reason)" == skipped-qualified ]] || {
  echo 'complete Clockwork release with Vulkan evidence did not qualify for skip' >&2; exit 1;
}
grep -qx 'SHA256SUMS SOURCE.txt PROVENANCE.json VULKAN-QUALIFICATION.txt' "$MOCK_DOWNLOAD_LOG" || exit 1

echo 'PASS release preflight fixtures: qualified refs, profile-isolated settings and workflow identity, Jess runtime identity, digest-only asset verification, Clockwork Vulkan evidence, source/recipe/toolchain changes, force, API failures, OCI index and single-manifest toolchain identities'
