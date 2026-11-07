#!/usr/bin/env bash
set -euo pipefail

# Cheap scheduled-release gate. A release is reusable only when its complete
# uploaded payload proves the exact versioned source/build identity.
: "${GITHUB_OUTPUT:?}" "${GITHUB_STEP_SUMMARY:?}" "${GITHUB_TOKEN:?}"
: "${OPENMW_REPOSITORY:?}" "${OPENMW_REF:?}" "${OPENMW_RELEASE_TAG:?}"
: "${FORGE_TOOLCHAIN_ID:?}" "${RUNNER_ARCH:?}"
: "${FORGE_PROFILE_SETTINGS_JSON:?}" "${FORGE_JESS_IDENTITY:?}"
OPENMW_PROFILE="${OPENMW_PROFILE:-upstream}"
if [[ ! "$OPENMW_PROFILE" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "Invalid release profile id: $OPENMW_PROFILE" >&2
  exit 1
fi

if [[ ! "$FORGE_JESS_IDENTITY" =~ ^[^[:space:]@]+@sha256:[0-9a-f]{64}$ ]]; then
  echo "Cannot establish immutable Jess runtime identity: $FORGE_JESS_IDENTITY" >&2
  exit 1
fi

profile_settings=$(jq -cS --arg profile "$OPENMW_PROFILE" --arg repo "$OPENMW_REPOSITORY" \
  --arg ref "$OPENMW_REF" --arg tag "$OPENMW_RELEASE_TAG" '
  if type == "object" and .schema == "forge-profile-settings/v1" and .profile == $profile
    and .repository == $repo and .ref == $ref and .release_tag == $tag
    and (.cmake_args | type) == "array" and (.features | type) == "object"
    and (.test_policy | type) == "object"
  then . else error("release profile settings do not match selected source") end' \
  <<<"$FORGE_PROFILE_SETTINGS_JSON")

if [[ ! "$FORGE_TOOLCHAIN_ID" =~ ^(ghcr\.io/.+@sha256:[0-9a-f]{64}|fallback:[0-9a-f]{64}:[0-9a-f]{64})$ ]]; then
  echo "Cannot establish immutable toolchain identity: $FORGE_TOOLCHAIN_ID" >&2
  exit 1
fi

resolve_source() {
  local remote="$1" ref="$2" listing count sha branch='' tag='' peeled=''
  local -a queries
  # Support an unqualified branch/tag only when it resolves unambiguously.
  # Annotated tags are peeled and their commit object is selected.
  case "$ref" in
    refs/heads/*)
      branch="$ref"
      queries=("$branch")
      ;;
    refs/tags/*)
      tag="$ref"
      peeled="$ref^{}"
      queries=("$tag" "$peeled")
      ;;
    *)
      branch="refs/heads/$ref"
      tag="refs/tags/$ref"
      peeled="$tag^{}"
      queries=("$branch" "$tag" "$peeled")
      ;;
  esac
  listing=$(git ls-remote "$remote" "${queries[@]}") || {
    echo "Failed to query source ref $remote @ $ref" >&2
    return 1
  }
  mapfile -t matches < <(awk -v branch="$branch" -v tag="$tag" -v peeled="$peeled" \
    '($2 == branch && branch != "") || ($2 == tag && tag != "") || ($2 == peeled && peeled != "") { print $1 " " $2 }' <<<"$listing")
  count=${#matches[@]}
  if (( count == 0 )); then echo "Source ref not found: $remote @ $ref" >&2; return 1; fi
  if (( count > 2 )); then echo "Ambiguous source ref: $remote @ $ref" >&2; return 1; fi
  local branch_sha='' tag_sha='' peeled_sha=''
  for entry in "${matches[@]}"; do
    read -r sha refname <<<"$entry"
    case "$refname" in
      "$branch") branch_sha="$sha" ;;
      "$tag") tag_sha="$sha" ;;
      "$peeled") peeled_sha="$sha" ;;
    esac
  done
  if [[ -n "$branch_sha" && -n "$tag_sha" ]]; then
    echo "Ref resolves as both branch and tag; configure a qualified ref: $ref" >&2; return 1
  fi
  sha="${peeled_sha:-${branch_sha:-$tag_sha}}"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Remote returned a non-commit SHA for $ref" >&2; return 1; }
  printf '%s' "$sha"
}

verify_asset_digests() {
  local release_json="$1" directory="$2" marker_digest marker_actual
  local source_sha provenance_sha sha filename digest count main_name debug_name
  local expected_count=4
  if [[ "$OPENMW_PROFILE" == clockwork ]]; then expected_count=5; fi
  local entry_count=0
  local -A checksums=()
  local manifest="$directory/SHA256SUMS"
  [[ -s "$manifest" && -s "$directory/SOURCE.txt" && -s "$directory/PROVENANCE.json" ]] || return 1

  marker_digest=$(jq -r '.assets[] | select(.name == "SHA256SUMS") | .digest // empty' <<<"$release_json")
  [[ "$marker_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
  marker_actual=$(sha256sum "$manifest" | cut -d' ' -f1)
  [[ "$marker_digest" == "sha256:$marker_actual" ]] || return 1

  main_name=$(jq -r '.assets[].name' <<<"$release_json" | grep -E '^openmw-.*-Linux-64Bit\.tar\.gz$')
  debug_name=$(jq -r '.assets[].name' <<<"$release_json" | grep -E '^openmw-.*-Linux-64Bit-debug\.tar\.gz$')
  [[ -n "$main_name" && -n "$debug_name" ]] || return 1

  while read -r sha filename; do
    [[ -n "$sha" && -n "$filename" && "$sha" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$filename" =~ ^[A-Za-z0-9._+-]+$ && -z "${checksums[$filename]+present}" ]] || return 1
    count=$(jq --arg name "$filename" '[.assets[] | select(.name == $name)] | length' <<<"$release_json")
    [[ "$count" == 1 ]] || return 1
    digest=$(jq -r --arg name "$filename" '.assets[] | select(.name == $name) | .digest // empty' <<<"$release_json")
    [[ "$digest" == "sha256:$sha" ]] || return 1
    checksums[$filename]="$sha"
    ((entry_count += 1))
  done < "$manifest"

  [[ "$entry_count" -eq "$expected_count" ]] || return 1
  [[ -n "${checksums[$main_name]:-}" && -n "${checksums[$debug_name]:-}" ]] || return 1
  source_sha=${checksums[SOURCE.txt]:-}
  provenance_sha=${checksums[PROVENANCE.json]:-}
  [[ -n "$source_sha" && -n "$provenance_sha" ]] || return 1
  [[ "$(sha256sum "$directory/SOURCE.txt" | cut -d' ' -f1)" == "$source_sha" ]] || return 1
  [[ "$(sha256sum "$directory/PROVENANCE.json" | cut -d' ' -f1)" == "$provenance_sha" ]] || return 1
  if [[ "$OPENMW_PROFILE" == clockwork ]]; then
    [[ -s "$directory/VULKAN-QUALIFICATION.txt" ]] || return 1
    [[ -n "${checksums[VULKAN-QUALIFICATION.txt]:-}" ]] || return 1
    [[ "$(sha256sum "$directory/VULKAN-QUALIFICATION.txt" | cut -d' ' -f1)" == "${checksums[VULKAN-QUALIFICATION.txt]}" ]] || return 1
  fi
  return 0
}

source_sha=$(resolve_source "$OPENMW_REPOSITORY" "$OPENMW_REF")
recipe_files=(.github/workflows/das-uberbranch.yml .github/actions/setup-jess/action.yml src tools vendor/builder vendor/deps jess.toml)
if [[ "$OPENMW_PROFILE" == clockwork ]]; then recipe_files+=(.github/workflows/das-uberbranch-clockwork.yml); fi
recipe_hash=$(git ls-files -z "${recipe_files[@]}" \
  | sort -z | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1)
inputs=$(jq -cnS \
  --arg schema 'forge-release-inputs/v1' \
  --arg profile "$OPENMW_PROFILE" \
  --arg jess_runtime "$FORGE_JESS_IDENTITY" \
  --arg repository "$OPENMW_REPOSITORY" \
  --arg requested_ref "$OPENMW_REF" \
  --arg release_tag "$OPENMW_RELEASE_TAG" \
  --arg source_sha "$source_sha" \
  --arg target "linux-$RUNNER_ARCH" \
  --arg toolchain "$FORGE_TOOLCHAIN_ID" \
  --arg dependencies "$(git ls-files -z vendor/deps src/native_deps.jsl src/native_sdk_cache.jsl | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1)" \
  --arg qt '6.6.3' \
  --arg compiler 'GCC Toolset 13; CMake from immutable AlmaLinux 9 builder' \
  --argjson profile_settings "$profile_settings" \
  --arg recipe_hash "$recipe_hash" \
  '{schema:$schema,profile:$profile,repository:$repository,requested_ref:$requested_ref,release_tag:$release_tag,source_sha:$source_sha,target:$target,toolchain:$toolchain,dependency_sdk_fingerprint:$dependencies,qt:$qt,compiler_configuration:$compiler,cmake_flags:$profile_settings.cmake_args,profile_settings:$profile_settings,jess_runtime:$jess_runtime,forge_recipe_sha256:$recipe_hash}')
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
  qualification_count=$(grep -xc 'VULKAN-QUALIFICATION.txt' <<<"$names" || true)
  qualification_valid=true
  if [[ "$OPENMW_PROFILE" == clockwork ]]; then
    [[ "$qualification_count" -eq 1 ]] || qualification_valid=false
  elif [[ "$qualification_count" -ne 0 ]]; then qualification_valid=false; fi
  if [[ "$(jq -r '.isPrerelease' <<<"$release_json")" == true ]] \
    && grep -qx 'SHA256SUMS' <<<"$names" && grep -qx 'SOURCE.txt' <<<"$names" \
    && grep -qx 'PROVENANCE.json' <<<"$names" \
    && [[ "$main_count" -eq 1 && "$debug_count" -eq 1 ]] && [[ "$qualification_valid" == true ]] \
    && grep -Fq -- "-g${source_sha:0:12}-Linux-64Bit.tar.gz" <<<"$names" \
    && grep -Fq -- "-g${source_sha:0:12}-Linux-64Bit-debug.tar.gz" <<<"$names"; then
    download_patterns=(--pattern SHA256SUMS --pattern SOURCE.txt --pattern PROVENANCE.json)
    expected_downloads=3
    if [[ "$OPENMW_PROFILE" == clockwork ]]; then
      download_patterns+=(--pattern VULKAN-QUALIFICATION.txt)
      expected_downloads=4
    fi
    if GH_TOKEN="$GITHUB_TOKEN" gh release download "$OPENMW_RELEASE_TAG" "${download_patterns[@]}" \
      --dir "$temp" >/dev/null 2>&1 \
      && [[ "$(find "$temp" -maxdepth 1 -type f | wc -l)" -eq "$expected_downloads" ]] \
      && verify_asset_digests "$release_json" "$temp"; then
      provenance="$temp/PROVENANCE.json"
      source="$temp/SOURCE.txt"
      if jq -e --arg fp "$fingerprint" --arg sha "$source_sha" --arg repo "$OPENMW_REPOSITORY" \
        --arg ref "$OPENMW_REF" --argjson inputs "$inputs" \
        --arg profile "$OPENMW_PROFILE" --arg tag "$OPENMW_RELEASE_TAG" \
        '.schema == "forge-qualified-release/v1" and .qualified == true and .input_fingerprint == $fp and .source_sha == $sha and .repository == $repo and .requested_ref == $ref and .profile == $profile and .release_tag == $tag and .inputs == $inputs' \
        "$provenance" >/dev/null \
        && grep -Fqx "Profile: $OPENMW_PROFILE" "$source" \
        && grep -Fqx "GitHub release: $OPENMW_RELEASE_TAG" "$source" \
        && grep -Fqx "OpenMW repository: $OPENMW_REPOSITORY" "$source" \
        && grep -Fqx "OpenMW requested ref: $OPENMW_REF" "$source" \
        && grep -Fqx "OpenMW resolved SHA: $source_sha" "$source" \
        && grep -Fqx "Build input fingerprint: $fingerprint" "$source" \
        && { [[ "$OPENMW_PROFILE" != clockwork ]] \
          || { grep -Fqx 'Profile: clockwork' "$temp/VULKAN-QUALIFICATION.txt" \
            && grep -Fqx 'Renderer: vulkan 1.3' "$temp/VULKAN-QUALIFICATION.txt" \
            && grep -Fqx "Clockwork source SHA: $source_sha" "$temp/VULKAN-QUALIFICATION.txt" \
            && grep -Fqx "Builder image: $FORGE_TOOLCHAIN_ID" "$temp/VULKAN-QUALIFICATION.txt"; }; }; then
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
  printf '### Release preflight\n\n- Profile: `%s`\n- Decision: `%s`\n- Source: `%s` @ `%s`\n- Release: `%s`\n- Resolved SHA: `%s`\n- Input fingerprint: `%s`\n' \
    "$OPENMW_PROFILE" "$reason" "$OPENMW_REPOSITORY" "$OPENMW_REF" \
    "$OPENMW_RELEASE_TAG" "$source_sha" "$fingerprint"
} >> "$GITHUB_STEP_SUMMARY"
echo "Preflight: $reason ($fingerprint)"
if [[ "$preflight_failure" == true ]]; then
  echo 'Release metadata lookup failed; refusing to run an expensive build without a reliable preflight result.' >&2
  exit 1
fi
