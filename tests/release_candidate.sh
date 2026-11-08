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

CLOCKWORK_PATH=.github/workflows/das-uberbranch-clockwork.yml
CLOCKWORK_JOB='Build and qualify Clockwork on GitHub-hosted Ubuntu (AlmaLinux 9 containers)'

# Fixtures are literal GitHub API shapes, one function per document.
write_run() {
  printf '{"path":"%s","event":"%s","conclusion":"failure","repository":{"id":123,"full_name":"DreamWeave-MP/openmw-forge"},"head_repository":{"id":123}}\n' \
    "$1" "$2" > "$CANDIDATE_RUN_JSON"
}
write_jobs() {
  printf '{"jobs":[{"name":"%s","conclusion":"%s"}]}\n' "$1" "$2" > "$CANDIDATE_JOBS_JSON"
}
write_artifacts() {
  printf '{"artifacts":[{"name":"%s","expired":%s,"created_at":"2026-11-07T00:00:00Z","workflow_run":{"id":12345,"repository_id":123,"head_repository_id":123}}]}\n' \
    "$1" "$2" > "$CANDIDATE_ARTIFACTS_JSON"
}

run_check() {
  : > "$GITHUB_OUTPUT"
  (cd "$root" && jess run --trusted --package . tools/release_candidate.jsl "${1:-12345}" \
    "${2:-$CLOCKWORK_PATH}" \
    "${3:-$CLOCKWORK_JOB}" \
    "${4:-openmw-das-uberbranch-clockwork-candidate-}") >/dev/null
}

write_run "$CLOCKWORK_PATH" workflow_dispatch
write_jobs "$CLOCKWORK_JOB" success
write_artifacts openmw-das-uberbranch-clockwork-candidate-12345-2 false

run_check
grep -qx 'usable=true' "$GITHUB_OUTPUT"
grep -qx 'artifact_name=openmw-das-uberbranch-clockwork-candidate-12345-2' "$GITHUB_OUTPUT"

# A failed workflow run is still recoverable when its full build job succeeded
# and its retained candidate is intact (for example, publication failed).
grep -q '"conclusion":"failure"' "$CANDIDATE_RUN_JSON"

write_run .github/workflows/other.yml workflow_dispatch
run_check
grep -qx 'usable=false' "$GITHUB_OUTPUT"

write_run "$CLOCKWORK_PATH" workflow_dispatch
write_jobs "$CLOCKWORK_JOB" failure
run_check
grep -qx 'usable=false' "$GITHUB_OUTPUT"

write_jobs "$CLOCKWORK_JOB" success
write_artifacts openmw-das-uberbranch-clockwork-candidate-12345-2 true
run_check
grep -qx 'usable=false' "$GITHUB_OUTPUT"

run_check invalid-id
grep -qx 'usable=false' "$GITHUB_OUTPUT"

# Upstream scheduled candidates use the same validator and can be recovered
# from an overall failed schedule run if the successful build job is retained.
UPSTREAM_JOB='Build OpenMW on GitHub-hosted Ubuntu (AlmaLinux 9 containers)'
write_run .github/workflows/das-uberbranch.yml schedule
write_jobs "$UPSTREAM_JOB" success
write_artifacts openmw-das-uberbranch-candidate-12345-1 false
run_check 12345 .github/workflows/das-uberbranch.yml "$UPSTREAM_JOB" openmw-das-uberbranch-candidate-
grep -qx 'usable=true' "$GITHUB_OUTPUT"
echo 'PASS candidate recovery fixtures: prior publish failure with successful build, wrong workflow, failed build, expired artifact, malformed run ID'
