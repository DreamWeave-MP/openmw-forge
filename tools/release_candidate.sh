#!/usr/bin/env bash
set -euo pipefail

candidate_run_id=${1:-}
workflow_path=${2:-}
build_job_name=${3:-}
artifact_prefix=${4:-}
if [[ -z "${GITHUB_OUTPUT:-}" || -z "${CURRENT_REPOSITORY:-}" || ! "${CURRENT_REPOSITORY_ID:-}" =~ ^[0-9]+$ ]]; then
  echo 'candidate inspection requires GitHub Actions outputs and repository identity' >&2
  exit 1
fi
if [[ -z "$workflow_path" || -z "$build_job_name" || -z "$artifact_prefix" ]]; then
  echo 'usage: tools/release_candidate.sh RUN_ID WORKFLOW_PATH BUILD_JOB_NAME ARTIFACT_PREFIX' >&2
  exit 2
fi

unusable() {
  echo "Candidate unavailable: $1; falling back to a cold build."
  printf 'usable=false\n' >> "$GITHUB_OUTPUT"
}

if [[ ! "$candidate_run_id" =~ ^[0-9]+$ ]]; then
  unusable 'run ID must contain decimal digits only'
  exit 0
fi

api() {
  GH_TOKEN="${GH_TOKEN:-}" gh api "repos/$CURRENT_REPOSITORY/actions/runs/$candidate_run_id$1" 2>/dev/null
}

run_json=$(api '' || true)
if [[ -z "$run_json" ]] || ! jq -e \
  --arg path "$workflow_path" \
  --arg repo "$CURRENT_REPOSITORY" --argjson repo_id "$CURRENT_REPOSITORY_ID" \
  '.path == $path and (.event == "workflow_dispatch" or .event == "schedule") and .repository.full_name == $repo
    and .repository.id == $repo_id and .head_repository.id == $repo_id' <<<"$run_json" >/dev/null; then
  unusable 'run is unavailable or does not belong to this Clockwork workflow and repository'
  exit 0
fi

jobs_json=$(api '/jobs?filter=all&per_page=100' || true)
if [[ -z "$jobs_json" ]] || ! jq -e \
  --arg job "$build_job_name" \
  '[.jobs[] | select(.name == $job)
    | select(.conclusion == "success")] | length > 0' <<<"$jobs_json" >/dev/null; then
  unusable 'no successful Clockwork build job exists in that run'
  exit 0
fi

artifacts_json=$(api '/artifacts?per_page=100' || true)
if [[ -z "$artifacts_json" ]] || ! jq -e '.artifacts | type == "array"' <<<"$artifacts_json" >/dev/null; then
  unusable 'artifact metadata could not be read'
  exit 0
fi

artifact_name=$(jq -r --argjson run_id "$candidate_run_id" --argjson repo_id "$CURRENT_REPOSITORY_ID" \
  --arg prefix "$artifact_prefix" \
  '[.artifacts[] | select(.expired == false)
    | select(.name | startswith($prefix))
    | select(.name | test("^[A-Za-z0-9_-]+-[0-9]+-[0-9]+$"))
    | select(.workflow_run.id == $run_id and .workflow_run.repository_id == $repo_id
      and .workflow_run.head_repository_id == $repo_id)]
    | sort_by(.created_at) | last | .name // empty' <<<"$artifacts_json")
if [[ -z "$artifact_name" ]]; then
  unusable 'no unexpired candidate artifact is attached to that run'
  exit 0
fi

printf 'usable=true\nartifact_name=%s\n' "$artifact_name" >> "$GITHUB_OUTPUT"
echo "Candidate artifact is eligible for download: $artifact_name"
