---
layout: default
---

# Troubleshooting and diagnostics

## The four-hour job did not run

Scheduled workflows execute only from the repository default branch. Check
that the file has been merged, Actions is enabled, and the schedule is not
disabled after inactivity. GitHub can delay or omit an individual tick. Trigger
`workflow_dispatch` manually to isolate CI configuration from scheduling.

## Docker or AlmaLinux cannot start

The workflow requires only a standard GitHub-hosted `ubuntu-24.04` runner,
which includes Docker. Locally use `forge doctor --engine docker`; use
`--engine podman` if that is your installed container runtime. AlmaLinux 9
remains the **build ABI** even when the outer host is Ubuntu.

## vcpkg or CMake ran out of disk/memory

Read `df -h` printed by CI and check for OOM-killer messages. Set `jobs = 1`
in `ci/uberbranch-config.jsl` to lower peak compilation memory. Cache the **verified exported SDK** and compiler/vcpkg binary caches,
not every `buildtrees` directory or the mutable installed tree. The scheduled
job saves the SDK before OpenMW compilation, then safely reclaims vcpkg
checkout/buildtrees. Clean unqualified stale artifacts before reuse.
The default hosted runner has finite resources and the full build has not yet
been qualified there; do not silently change to self-hosted machines.

## GHCR toolchain image is unavailable

The scheduled job attempts the digest-pinned image computed from
`vendor/builder/Dockerfile` and falls back to building the same recipe on
GitHub-hosted Ubuntu. Publish the separate `Forge AlmaLinux 9 toolchain image`
workflow from the default branch to avoid repeated DNF/Autoconf work. A fresh
fork may initially lack GHCR package read permission; check the toolchain
resolver output and GHCR package visibility. Release verification never skips
just because the fast image is missing.

## The qualified SDK cache is rejected

Forge checks the builder identity, triplet, vcpkg revision, overlay file
hashes, archive SHA-256, and safe archive members before reuse. A bad cache
is a rebuild, not a green cache hit. GitHub cache entries cannot be rewritten
under the same key, so invalidate the key or allow the stale entry to expire
if the same corrupted entry keeps returning.

## `ccache` shows zero hits

A cold build has no hits; inspect the cache statistics after a *second* build.
Confirm `work/cache/ccache` is present in the container mount plan (try
`forge pipeline ... --dry-run`) and that CI restored the compiler cache after
checkout. `--no-ccache` intentionally disables it. A changed compiler or
build flags can invalidate cached objects.

## Forge refuses `--clean`

Forge will not erase an unowned build or scratch directory. Keep your source
checkout outside generated work roots. Move or rename old unmarked outputs
manually after inspection, then let Forge create a new managed directory.

## The release job fails publication

Look for the SHA-256/provenance validation errors before investigating token
permissions. The build job needs only `contents: read`; the separate publish
job needs `contents: write` and a `GITHUB_TOKEN` able to create and update
GitHub releases. A failed qualification must leave the release unmodified.

## Docs site build fails

From the Forge source root run `jess run --trusted --package . tools/docs.jsl`
then `zola --root site build --output-dir ../public`. Edit source Markdown in
`docs/`, not `site/content/manual`. Check Zola version `0.23.6`; the site
uses Zola (as StroggForge does), **not** the old Jekyll Pages builder.
