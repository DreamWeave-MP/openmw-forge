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
  jobs = 2,
}
```

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
6. Inspect ABI ceilings and execute **packaged launchers and raw ELF binaries**
   in AlmaLinux 9 and Ubuntu 24.04 smoke containers.
7. Transfer files through a short-lived Actions artifact; a separate job
   validates SHA-256 and the configured repository/ref/full SHA before using
   `contents: write` to update the `das-uberbranch` prerelease.

The rolling prerelease includes the main package, matching debug package,
`SOURCE.txt`, and `SHA256SUMS`. Its previous Forge tarballs are pruned after
success while unrelated assets remain. GitHub Release assets are independent
objects, not an atomic multi-asset transaction. Consumers should verify the
checksums and matching source revision before using a rolling release.

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
