#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == api ]] || exit 2
case "$2" in
  */actions/runs/12345) cat "$CANDIDATE_RUN_JSON" ;;
  */actions/runs/12345/jobs\?*) cat "$CANDIDATE_JOBS_JSON" ;;
  */actions/runs/12345/artifacts\?*) cat "$CANDIDATE_ARTIFACTS_JSON" ;;
  *) exit 3 ;;
esac
MOCK
chmod +x "$scratch/bin/gh"

export PATH="$scratch/bin:$PATH"
export CURRENT_REPOSITORY='DreamWeave-MP/openmw-forge'
export CURRENT_REPOSITORY_ID=123
export GH_TOKEN=fixture-token
export CANDIDATE_RUN_JSON="$scratch/run.json"
export CANDIDATE_JOBS_JSON="$scratch/jobs.json"
export CANDIDATE_ARTIFACTS_JSON="$scratch/artifacts.json"
export GITHUB_OUTPUT="$scratch/output"

jq -cn '{path:".github/workflows/das-uberbranch-clockwork.yml",event:"workflow_dispatch",
  conclusion:"failure",repository:{id:123,full_name:"DreamWeave-MP/openmw-forge"},head_repository:{id:123}}' > "$CANDIDATE_RUN_JSON"
jq -cn '{jobs:[{name:"Build and qualify Clockwork on GitHub-hosted Ubuntu (AlmaLinux 9 containers)",conclusion:"success"}]}' > "$CANDIDATE_JOBS_JSON"
jq -cn '{artifacts:[{name:"openmw-das-uberbranch-clockwork-candidate-12345-2",expired:false,
  created_at:"2026-11-07T00:00:00Z",workflow_run:{id:12345,repository_id:123,head_repository_id:123}}]}' \
  > "$CANDIDATE_ARTIFACTS_JSON"

run_check() {
  : > "$GITHUB_OUTPUT"
  bash "$root/tools/release_candidate.sh" "${1:-12345}" \
    "${2:-.github/workflows/das-uberbranch-clockwork.yml}" \
    "${3:-Build and qualify Clockwork on GitHub-hosted Ubuntu (AlmaLinux 9 containers)}" \
    "${4:-openmw-das-uberbranch-clockwork-candidate-}" >/dev/null
}

run_check
grep -qx 'usable=true' "$GITHUB_OUTPUT"
grep -qx 'artifact_name=openmw-das-uberbranch-clockwork-candidate-12345-2' "$GITHUB_OUTPUT"

# A failed workflow run is still recoverable when its full build job succeeded
# and its retained candidate is intact (for example, publication failed).
jq -e '.conclusion == "failure"' "$CANDIDATE_RUN_JSON" >/dev/null

jq '.path = ".github/workflows/other.yml"' "$CANDIDATE_RUN_JSON" > "$scratch/wrong.json"
mv "$scratch/wrong.json" "$CANDIDATE_RUN_JSON"
run_check
grep -qx 'usable=false' "$GITHUB_OUTPUT"

jq -cn '{jobs:[{name:"Build and qualify Clockwork on GitHub-hosted Ubuntu (AlmaLinux 9 containers)",conclusion:"failure"}]}' \
  > "$CANDIDATE_JOBS_JSON"
jq '.path = ".github/workflows/das-uberbranch-clockwork.yml"' "$CANDIDATE_RUN_JSON" > "$scratch/run.json.tmp"
mv "$scratch/run.json.tmp" "$CANDIDATE_RUN_JSON"
run_check
grep -qx 'usable=false' "$GITHUB_OUTPUT"

jq '.jobs[0].conclusion = "success"' "$CANDIDATE_JOBS_JSON" > "$scratch/jobs.json.tmp"
mv "$scratch/jobs.json.tmp" "$CANDIDATE_JOBS_JSON"
jq '.artifacts[0].expired = true' "$CANDIDATE_ARTIFACTS_JSON" > "$scratch/artifacts.json.tmp"
mv "$scratch/artifacts.json.tmp" "$CANDIDATE_ARTIFACTS_JSON"
run_check
grep -qx 'usable=false' "$GITHUB_OUTPUT"

run_check invalid-id
grep -qx 'usable=false' "$GITHUB_OUTPUT"

# Upstream scheduled candidates use the same validator and can be recovered
# from an overall failed schedule run if the successful build job is retained.
jq '.path = ".github/workflows/das-uberbranch.yml" | .event = "schedule"' "$CANDIDATE_RUN_JSON" > "$scratch/run.json.tmp"
mv "$scratch/run.json.tmp" "$CANDIDATE_RUN_JSON"
jq '.jobs[0].name = "Build OpenMW on GitHub-hosted Ubuntu (AlmaLinux 9 containers)"' "$CANDIDATE_JOBS_JSON" > "$scratch/jobs.json.tmp"
mv "$scratch/jobs.json.tmp" "$CANDIDATE_JOBS_JSON"
jq '.artifacts[0].name = "openmw-das-uberbranch-candidate-12345-1" | .artifacts[0].expired = false' "$CANDIDATE_ARTIFACTS_JSON" > "$scratch/artifacts.json.tmp"
mv "$scratch/artifacts.json.tmp" "$CANDIDATE_ARTIFACTS_JSON"
run_check 12345 .github/workflows/das-uberbranch.yml \
  'Build OpenMW on GitHub-hosted Ubuntu (AlmaLinux 9 containers)' openmw-das-uberbranch-candidate-
grep -qx 'usable=true' "$GITHUB_OUTPUT"
echo 'PASS candidate recovery fixtures: prior publish failure with successful build, wrong workflow, failed build, expired artifact, malformed run ID'
