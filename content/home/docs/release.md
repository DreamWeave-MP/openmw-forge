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

## Select the OpenMW source

The scheduled **Das UberBranch** workflow builds **Clockwork Vulkan** from
`https://gitlab.com/OursCodeur/openmw.git` at `clockwork-alpha`. A manual
`workflow_dispatch` can choose `clockwork` (default) or `upstream` (official
`https://gitlab.com/OpenMW/openmw.git` at `master`). Both profiles execute
**the same** Forge build, GoogleTests, package, distro smoke, and publication
logic. The only source-specific parameters are encoded in
`ci/release-profiles.jsl`: source repository/ref, required CMake features,
release identity, and package namespace. Dependencies and builder-image
selection remain independent of renderer validation. Both source profiles
consume the same Linux vcpkg SDK: SDL2 is built with its `vulkan` feature
and X11/Wayland window backends enabled. This makes Vulkan window creation
available to Clockwork without enabling Vulkan rendering in upstream/master.
The manifest change invalidates the dependency SDK identity and requires a new
SDK build; CI does not perform frame capture or renderer verification.

Release tags follow the source identity: **Clockwork** publishes to
[`das-uberbranch`](https://github.com/DreamWeave-MP/openmw-forge/releases/tag/das-uberbranch)
and **upstream/master** publishes to
[`upstream`](https://github.com/DreamWeave-MP/openmw-forge/releases/tag/upstream).
The two profiles retain independent artifact namespaces and provenance, but share
the exact same dependency SDK, build and publication machinery. When switching from historical release tags, delete the old GitHub Releases
before rerunning the publisher. Deleting a release may leave its Git tag behind;
the standalone integrator safely retargets the historical `das-uberbranch` tag
to the new Forge `main` when necessary. No old releases or assets are migrated.
The publisher refuses to overwrite an existing release belonging to a different
OpenMW source.

Each run resolves its selected source to a full commit SHA and records that
revision in its archives, `SOURCE.txt`, and `PROVENANCE.json`. `jobs = 'auto'`
uses the available build-container CPUs; the release profile can instead cap
parallelism with an integer.

## What qualifies a build

1. Verify the source, immutable builder, Jess runtime, and versioned build-input
   fingerprint; use a complete existing release when its identity matches.
2. Compile the engine with the selected profile's flags; run GoogleTests.
3. Produce matching runtime and debug archives and audit packaged ELF/ABI and
   dependency closure.
4. Execute package/launcher smoke tests on AlmaLinux 9 and Ubuntu 24.04.
   These test binary and package viability; **there is no renderer startup,
   frame-rate, Lavapipe, example-suite, or Vulkan capture test**.
5. Upload the candidate with `SOURCE.txt`, `PROVENANCE.json`, and `SHA256SUMS`;
   the publish job revalidates the full identity and all SHA-256 entries before
   updating the selected prerelease. `SHA256SUMS` is uploaded last as a
   completion marker.

No `VULKAN-QUALIFICATION.txt` asset is generated or required for either source.
Vulkan support is still checked at configuration/compiled-feature/package
level for Clockwork, as appropriate for a build pipeline.

## Running qualification on the PR branch

Push a commit whose message contains `[qualify-clockwork]` to
`pr-04-clockwork-full-build`. The one shared workflow runs a full Clockwork
build with `force_rebuild=true`, but **skips the write-permissioned publication
job** for push events. Ordinary pushes do not launch a build.

For a deliberate publishing run, dispatch `das-uberbranch.yml` with
`release_profile=clockwork` (or `upstream`) from a GitHub-registered workflow.
GitHub scheduled workflows always run from the default branch, so the changed
four-hour schedule will not take effect until this branch is merged. Do not
activate release publishing on a PR by giving the push trigger write access.

A failed publishing job can be retried via `candidate_run_id` and, when needed,
`force_republish`. Candidate recovery requires the **same profile, source SHA,
recipe fingerprint, and checksum-verified release payload** as the current
preflight. A failed build never generates a publishable candidate.

## Local dry run

```sh
jess run --trusted --package . tools/uberbranch.jsl --release-profile clockwork --dry-run
jess run --trusted --package . tools/uberbranch.jsl --release-profile upstream --dry-run
```

The standalone toolchain/SDK preparation and build-only paths remain available:

```sh
jess run --trusted --package . tools/uberbranch.jsl --release-profile clockwork --prepare-deps --dry-run
jess run --trusted --package . tools/uberbranch.jsl --release-profile clockwork --build-only --dry-run
```

The split lets a verified SDK remain cached even if a later engine build fails.
No profile-specific renderer qualification stage or duplicate CI build path is
maintained.
