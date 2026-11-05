---
layout: default
---

# Performance, caches, and CI resource budget

Forge's optimization target is **elapsed time to a verified OpenMW tarball**,
not Jess script execution time. The heaviest work happens in vcpkg, Qt,
CMake/Ninja, C++ compilation, packaging, and distro startup.

## Existing accelerations

- **Ninja** is selected for a new build directory if available; an existing
  CMake cache retains its generator to avoid breaking incremental builds.
- OpenMW C/C++ compiler invocations use **ccache** by default. Container builds
  mount `work/cache/ccache` into the AlmaLinux worker at
  `/forge/work/ccache` and set `CCACHE_DIR`. The cache is compressed and limited
  to **1 GiB** by default; `ccache --show-stats` prints observed hits/misses.
  Use `--no-ccache` to explicitly disable it.
- The vcpkg source/downloads tree and vcpkg compiled binary cache are mounted
  from durable host directories across *container* invocations.
- GitHub Actions restores the vcpkg binary and OpenMW compiler caches across
  ephemeral hosted machines, subject to repository cache limits and eviction.
- The builder image installs Autoconf 2.72 and system dependencies in a
  Docker layer once per matching image identity on a given runner.
- Qt and dependency extraction have reuse checks, but those extracted working
  directories are **not** persisted between separate hosted jobs today.

## Cache lifecycle caveats

A GitHub-hosted job starts on a fresh VM. Docker images and unexported build
workspaces vanish afterward. An `actions/cache` hit is best-effort and the
cache can be evicted. It is **never proof that an upstream source revision was
correct**; provenance and hashes remain release gates.

The scheduled pipeline uses one snapshot key per day and input fingerprint.
New results after the first cache save of the day are stored when the next
daily key becomes available. This avoids saving six nearly identical caches
per day, but sacrifices same-day freshness. The Actions cache quota is finite;
if dependency archives regularly exceed it, we should switch to immutable,
content-addressed GHCR/Release artifacts rather than caching entire mutable
buildtrees.

## Standard hosted runner constraints

The canonical schedule uses `ubuntu-24.04` and `jobs = 2`. GitHub allocates
modest cores, memory, and disk to standard hosted runners; values vary by
repository visibility. **There is no demonstrated end-to-end cold build on
those limits yet.** Measure `df -h`, OOM events, elapsed stage times and the
cache hit rate on a manual workflow dispatch. The 330-minute job timeout is
intentional, below the maximum hosted job duration.

## Benchmark plan

Record cold build, same-commit rebuild, upstream-only change, vcpkg manifest
change, and a new fork. For each, save elapsed time for dependency install,
Qt, CMake configure, compile, test, archive and distro smoke; `ccache -s`,
vcpkg binary-cache hit statistics, peak RSS, free disk and downloaded bytes.
Until those measurements exist, **no numeric CI speedup should be claimed**.

The next major speed improvements are complete content-addressed dependency
exports, safe stage-resume journals, and caching build inputs across hosted
jobs without sending gigabytes of temporary buildtrees through Actions/cache.
