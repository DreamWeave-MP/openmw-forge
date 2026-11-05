---
layout: default
---

# das-uberbranch: scheduled OpenMW Linux release

A separate GitHub Actions workflow runs at minute 23 every four hours UTC:

```yaml
schedule:
  - cron: '23 */4 * * *'
```

Edit **`ci/uberbranch-config.jsl`** to change only the tracked source:

```luau
repository = 'https://gitlab.com/OpenMW/openmw.git',
ref = 'master',
releaseTag = 'das-uberbranch',
jobs = 8,
```

Use the SSH/HTTPS clone URL of any OpenMW fork and a branch, tag or SHA. Forge
will fetch it into an isolated managed checkout, record the resolved full Git
SHA, and include its prefix in the package filename. Config validation rejects
invalid remote/ref values. Do not edit the GitHub workflow just to swap forks.

The job compiles Forge from the current repository, runs the full dependency
and OpenMW pipeline (including GoogleTests), assembles the Linux + debug
archives, audits the ABI, executes actual packaged launchers (including the required Qt launcher)
in AlmaLinux 9 and Ubuntu 24.04, and checks the provenance SHA and artifact hashes before
uploading to the **`das-uberbranch`** GitHub prerelease. The build job
never receives a release-capable GitHub token: it uploads a short-lived
workflow artifact, and a separate write-permitted job verifies the downloaded
files before release publication.

Release assets include the main tarball, matching `-debug.tar.gz`, `SOURCE.txt`
with the exact upstream revision and CI run, and `SHA256SUMS`. Builds with
failed smoke tests or missing artifacts never reach the upload step. Individual GitHub asset replacement is **not atomic as a group**. A
successful update removes older Forge tarball assets once the current tarballs
and metadata have been uploaded. Unrelated release assets are preserved. If
an upload fails, the previous revision can remain partially visible; inspect
`SOURCE.txt` and `SHA256SUMS` for a coherent release set.

You can inspect config without compiling or publishing:

```sh
jess run --trusted --package . tools/uberbranch.jsl --dry-run
```

Trigger a real run from Actions → **OpenMW das-uberbranch (four-hour build)** →
Run workflow. It needs the labeled self-hosted runner described in [CI](CI.md).
Nothing starts automatically until the workflow is merged into the repository's
default branch, Actions is enabled, and the runner is online.
