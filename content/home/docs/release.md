+++
title = "Scheduled releases"
weight = 30
description = "OpenMW Forge: Scheduled releases"
+++


This is a **separate** GitHub Actions workflow, not part of the Forge source
validation lane. It runs on standard `ubuntu-24.04` GitHub-hosted runners and
builds the payload inside AlmaLinux 9 Docker containers.

```yaml
on:
  schedule:
    - cron: '23 */4 * * *'
  workflow_dispatch:
```

## Change the OpenMW fork or branch

Edit one source-controlled file: **`ci/uberbranch-config.jsl`**.

```luau
return table.freeze {
  repository = 'https://gitlab.com/OpenMW/openmw.git',
  ref = 'master',
  releaseTag = 'das-uberbranch',
  jobs = 'auto', -- all CPUs available inside the build container
}
```

`jobs = 'auto'` is the default. Forge runs `nproc` inside its AlmaLinux
container to pick the current runner's available CPUs, and passes that count
explicitly to both CMake build invocations and vcpkg. To cap memory pressure,
set `jobs` to an integer from 1 to 1024 instead; explicit counts always win.

The initial source is official OpenMW `master`. To build a fork, change only
`repository` and `ref` to the desired HTTPS/SSH clone URL and branch, tag, or
commit. No workflow YAML edit and no separate OpenMW checkout are required.
The managed checkout records the resolved **full Git SHA** and Forge records
that revision in the tarball name and `SOURCE.txt` provenance.

## Successful release criteria

1. Check out Forge without leaving GitHub credentials in Git config.
2. Resolve the digest-pinned GHCR builder image (or a safe first-run local fallback); restore the verified SDK export, Qt and compiler caches.
3. Run Jess strict/style and source/JPK tests, compile the standalone ELF.
4. Verify/reuse the pinned SDK or build/ABI-qualify it on a cache miss. Save it immediately; reclaim temporary vcpkg buildtrees. Compile OpenMW in AlmaLinux 9 with GoogleTests.
5. Produce the main `.tar.gz` and matching `-debug.tar.gz`.
6. Audit the closure of every packaged ELF and supported Qt runtime plugin
   inside each target smoke distribution. The package omits unused Qt SDK
   database, GTK theme, and print plugins, but retains XCB, Wayland and
   offscreen GUI support. Then inspect ABI ceilings and execute **packaged launchers and raw ELF binaries**
   in AlmaLinux 9 and Ubuntu 24.04 smoke containers.
7. Transfer files through a short-lived Actions artifact; a separate job
   validates SHA-256 and the configured repository/ref/full SHA before using
   `contents: write` to update the `das-uberbranch` prerelease.

The rolling prerelease includes the main package, matching debug package,
`SOURCE.txt`, and `SHA256SUMS`. Its previous Forge tarballs are pruned after
success while unrelated assets remain. GitHub Release assets are independent
objects, not an atomic multi-asset transaction. Consumers should verify the
checksums and matching source revision before using a rolling release.

## Clockwork experimental release and publish recovery

Clockwork is published only through the separate
`das-uberbranch-clockwork` experimental prerelease. Its workflow remains
`workflow_dispatch` only until the real Vulkan frame, Luau/UI behavior, package,
GoogleTest, ABI, and distribution gates have passed. The upstream four-hour
schedule and release tag are independent.

Preflight records the full Clockwork source SHA and versioned build-input
fingerprint. If that identity already has a complete checksummed release, the
workflow exits without restoring SDK or compiler caches. Use `force_rebuild`
only when a new compilation is intended. Cache hits are reported separately;
they never qualify a release.

If a build and its qualification tests succeeded but the publication job
failed, dispatch the Clockwork workflow again with the prior run's numeric
`candidate_run_id`. Set `force_republish` when the existing release is already
qualified but the operator explicitly wants to publish that candidate again.
Recovery checks that the run belongs to this workflow and repository, its
Clockwork build job succeeded, and its candidate artifact is still retained.
Forge then compares its full source SHA, fingerprint, structured provenance,
Clockwork Vulkan report, and every SHA-256 entry against the new preflight
identity before transferring it to the write-scoped publisher. A missing,
expired, malformed, or mismatched candidate falls back to a cold build when
preflight says one is needed. A failed build, GoogleTest, ABI, or smoke gate
does not upload a candidate. Candidate artifacts are retained for three days;
they are not a compilation cache and do not bypass qualification.

The run summary records the profile, full source SHA, fingerprint, preflight and
recovery decision, cache restore results, builder digest, build/smoke duration,
ccache statistics, and release URL when one is available. Verify the published
release by checking `SOURCE.txt`, `PROVENANCE.json`,
`VULKAN-QUALIFICATION.txt`, and `SHA256SUMS` together.

The upstream `das-uberbranch` manual workflow accepts the same run-ID recovery
inputs for a qualified upstream candidate. Its scheduled runs remain unchanged;
recovery is an operator-triggered dispatch.

## Offline dry runs for the two scheduled stages

```sh
jess run --trusted --package . tools/uberbranch.jsl --prepare-deps --dry-run
jess run --trusted --package . tools/uberbranch.jsl --build-only --dry-run
```

The split matters: the SDK export can be cached immediately when qualified,
even if a later upstream OpenMW commit fails to compile. The default local
`tools/uberbranch.jsl` invocation still executes the combined pipeline. Never
publish a release on the strength of the dependency stage alone.

## First-time activation

1. Merge the new workflows onto the Forge repository's **default branch**.
2. Enable GitHub Actions and allow workflows to create releases using the
   repository's `GITHUB_TOKEN` (`contents: write` is granted only to the
   publication job). No personal access token is required for public OpenMW.
3. Optionally pin `JESS_RELEASE_TAG` under repository variables.
4. Run **Forge AlmaLinux 9 toolchain image** on the default branch and check that the GHCR package is readable to the scheduled build. This preprovisions DNF/Autoconf once instead of wasting every four-hour run.

5. Select Settings → Pages → Source **GitHub Actions** for the documentation.
6. Trigger **OpenMW das-uberbranch (four-hour build)** manually; check output,
   cache hit rates, peak disk usage, test results and the final release assets.
7. Only after that successful qualification rely on the periodic schedule.

Dry-run the selection without touching Git or compiling:

```sh
jess run --trusted --package . tools/uberbranch.jsl --dry-run
```

GitHub schedules can be delayed or dropped under load. Two runs do not overlap;
when a previous build occupies the runner beyond four hours, scheduled runs
may coalesce. The hard limit is 330 minutes per build job. See
[CI](@/home/docs/ci.md), [performance](@/home/docs/performance.md) and [release readiness](@/home/docs/release-readiness.md).
