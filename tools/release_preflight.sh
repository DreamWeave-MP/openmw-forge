#!/usr/bin/env bash
set -euo pipefail

# Cheap scheduled-release gate. A release is reusable only when its complete
# uploaded payload proves the exact versioned source/build identity.
: "${GITHUB_OUTPUT:?}" "${GITHUB_STEP_SUMMARY:?}" "${GITHUB_TOKEN:?}"
: "${OPENMW_REPOSITORY:?}" "${OPENMW_REF:?}" "${OPENMW_RELEASE_TAG:?}"
: "${FORGE_TOOLCHAIN_ID:?}" "${RUNNER_ARCH:?}"

if [[ ! "$FORGE_TOOLCHAIN_ID" =~ ^(ghcr\.io/.+@sha256:[0-9a-f]{64}|fallback:[0-9a-f]{64}:[0-9a-f]{64})$ ]]; then
  echo "Cannot establish immutable toolchain identity: $FORGE_TOOLCHAIN_ID" >&2
  exit 1
fi

resolve_source() {
  local remote="$1" ref="$2" listing count sha
  # Support an unqualified branch/tag only when it resolves unambiguously.
  # Annotated tags are peeled and their commit object is selected.
  listing=$(git ls-remote "$remote" \
    "refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}") || {
    echo "Failed to query source ref $remote @ $ref" >&2
    return 1
  }
  mapfile -t matches < <(awk -v branch="refs/heads/$ref" -v tag="refs/tags/$ref" -v peeled="refs/tags/$ref^{}" \
    '$2 == branch || $2 == tag || $2 == peeled { print $1 " " $2 }' <<<"$listing")
  count=${#matches[@]}
  if (( count == 0 )); then echo "Source ref not found: $remote @ $ref" >&2; return 1; fi
  if (( count > 2 )); then echo "Ambiguous source ref: $remote @ $ref" >&2; return 1; fi
  local branch_sha='' tag_sha='' peeled_sha=''
  for entry in "${matches[@]}"; do
    read -r sha refname <<<"$entry"
    case "$refname" in
      "refs/heads/$ref") branch_sha="$sha" ;;
      "refs/tags/$ref") tag_sha="$sha" ;;
      "refs/tags/$ref^{}") peeled_sha="$sha" ;;
    esac
  done
  if [[ -n "$branch_sha" && -n "$tag_sha" ]]; then
    echo "Ref resolves as both branch and tag; configure a qualified ref: $ref" >&2; return 1
  fi
  sha="${peeled_sha:-${branch_sha:-$tag_sha}}"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Remote returned a non-commit SHA for $ref" >&2; return 1; }
  printf '%s' "$sha"
}

source_sha=$(resolve_source "$OPENMW_REPOSITORY" "$OPENMW_REF")
recipe_hash=$(git ls-files -z .github/workflows ci src tools vendor/builder vendor/deps jess.toml \
  | sort -z | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1)
inputs=$(jq -cnS \
  --arg schema 'forge-release-inputs/v1' \
  --arg profile 'upstream' \
  --arg repository "$OPENMW_REPOSITORY" \
  --arg requested_ref "$OPENMW_REF" \
  --arg source_sha "$source_sha" \
  --arg target "linux-$RUNNER_ARCH" \
  --arg toolchain "$FORGE_TOOLCHAIN_ID" \
  --arg dependencies "$(git ls-files -z vendor/deps src/native_deps.jsl src/native_sdk_cache.jsl | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1)" \
  --arg qt '6.6.3' \
  --arg compiler 'GCC Toolset 13; CMake from immutable AlmaLinux 9 builder' \
  --arg cmake_flags 'Forge scheduled defaults; --run-tests; jobs=auto' \
  --arg recipe_hash "$recipe_hash" \
  '{schema:$schema,profile:$profile,repository:$repository,requested_ref:$requested_ref,source_sha:$source_sha,target:$target,toolchain:$toolchain,dependency_sdk_fingerprint:$dependencies,qt:$qt,compiler_configuration:$compiler,cmake_flags:$cmake_flags,forge_recipe_sha256:$recipe_hash}')
fingerprint=$(printf '%s' "$inputs" | sha256sum | cut -d' ' -f1)
printf 'source_sha=%s\ninput_fingerprint=%s\ninputs_json=%s\n' \
  "$source_sha" "$fingerprint" "$inputs" >> "$GITHUB_OUTPUT"

reason='release-missing'
should_build=true
preflight_failure=false
error_file=$(mktemp)
temp=''
cleanup() {
  [[ -z "$temp" ]] || rm -rf "$temp"
  rm -f "$error_file"
}
trap cleanup EXIT
if [[ "${FORCE_REBUILD:-false}" == true ]]; then
  reason='manual-force-rebuild'
elif release_json=$(GH_TOKEN="$GITHUB_TOKEN" gh release view "$OPENMW_RELEASE_TAG" --json assets,isPrerelease 2>"$error_file"); then
  temp=$(mktemp -d)
  names=$(jq -r '.assets[].name' <<<"$release_json")
  main_count=$(grep -Ec '^openmw-.*-Linux-64Bit\.tar\.gz$' <<<"$names" || true)
  debug_count=$(grep -Ec '^openmw-.*-Linux-64Bit-debug\.tar\.gz$' <<<"$names" || true)
  if [[ "$(jq -r '.isPrerelease' <<<"$release_json")" == true ]] \
    && grep -qx 'SHA256SUMS' <<<"$names" && grep -qx 'SOURCE.txt' <<<"$names" \
    && grep -qx 'PROVENANCE.json' <<<"$names" \
    && [[ "$main_count" -eq 1 && "$debug_count" -eq 1 ]] \
    && grep -Fq -- "-g${source_sha:0:12}-Linux-64Bit.tar.gz" <<<"$names" \
    && grep -Fq -- "-g${source_sha:0:12}-Linux-64Bit-debug.tar.gz" <<<"$names"; then
    if GH_TOKEN="$GITHUB_TOKEN" gh release download "$OPENMW_RELEASE_TAG" \
      --pattern SHA256SUMS --pattern SOURCE.txt --pattern PROVENANCE.json \
      --pattern 'openmw-*-Linux-64Bit.tar.gz' --pattern 'openmw-*-Linux-64Bit-debug.tar.gz' \
      --dir "$temp" >/dev/null 2>&1 \
      && (cd "$temp" && sha256sum --strict --check SHA256SUMS >/dev/null 2>&1) \
      && [[ "$(find "$temp" -maxdepth 1 -type f ! -name SHA256SUMS | wc -l)" -eq "$(wc -l < "$temp/SHA256SUMS")" ]] \
      && diff -u <(sed -E 's/^[0-9a-f]{64}  //' "$temp/SHA256SUMS" | sort) \
        <(find "$temp" -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort) >/dev/null; then
      provenance="$temp/PROVENANCE.json"
      source="$temp/SOURCE.txt"
      if jq -e --arg fp "$fingerprint" --arg sha "$source_sha" --arg repo "$OPENMW_REPOSITORY" \
        --arg ref "$OPENMW_REF" --argjson inputs "$inputs" \
        '.schema == "forge-qualified-release/v1" and .qualified == true and .input_fingerprint == $fp and .source_sha == $sha and .repository == $repo and .requested_ref == $ref and .inputs == $inputs' \
        "$provenance" >/dev/null \
        && grep -Fqx "OpenMW repository: $OPENMW_REPOSITORY" "$source" \
        && grep -Fqx "OpenMW requested ref: $OPENMW_REF" "$source" \
        && grep -Fqx "OpenMW resolved SHA: $source_sha" "$source" \
        && grep -Fqx "Build input fingerprint: $fingerprint" "$source"; then
        should_build=false
        reason='skipped-qualified'
      else reason='invalid-or-mismatched-provenance'; fi
    else reason='missing-or-invalid-checksum-payload'; fi
  else reason='incomplete-release-assets'; fi
else
  # Release lookup failure is not evidence of qualification. Rebuild and let
  # the narrowly scoped publish job report any persistent API failure.
  if grep -Eqi 'HTTP 404|Not Found' "$error_file"; then
    reason='release-missing'
  else
    reason='release-api-unavailable'
    preflight_failure=true
  fi
fi

printf 'should_build=%s\nreason=%s\n' "$should_build" "$reason" >> "$GITHUB_OUTPUT"
{
  printf '### Upstream release preflight\n\n- Decision: `%s`\n- Source: `%s` @ `%s`\n- Resolved SHA: `%s`\n- Input fingerprint: `%s`\n' \
    "$reason" "$OPENMW_REPOSITORY" "$OPENMW_REF" "$source_sha" "$fingerprint"
} >> "$GITHUB_STEP_SUMMARY"
echo "Preflight: $reason ($fingerprint)"
if [[ "$preflight_failure" == true ]]; then
  echo 'Release metadata lookup failed; refusing to run an expensive build without a reliable preflight result.' >&2
  exit 1
fi
