---
layout: default
---

# Performance: fastest path to a qualified OpenMW tarball

Forge is deliberately **not** a general build framework. Its expensive units
are a pinned AlmaLinux 9 C++ toolchain, one pinned vcpkg SDK, one Qt installation,
OpenMW compilation, and release verification. The fundamental optimization is
**not doing work whose inputs have not changed**.

## What is reused, and where

| Stage | Local host / repeat container | Four-hour GitHub-hosted build |
|---|---|---|
| AlmaLinux 9 toolchain | Content-derived local Docker image | Prepublished GHCR image **resolved to its OCI digest**; falls back to building from source on first use |
| vcpkg dependency SDK | SHA-256 input/metadata/archive check avoids reinstall/export | Complete qualified `.7z` export restored with Actions cache; worker rechecks its fingerprint and bytes |
| vcpkg binary packages | Persistent mounted volume | Restored only if SDK cache misses; saved as soon as dependencies qualify |
| Qt 6.6.3 | Installation is reused if present | Version-keyed Actions cache, restored into the mounted Qt prefix |
| C/C++ object compilation | Ninja and mounted ccache | 1 GiB compressed ccache restored across hosted runs, per-day snapshots |
| CMake buildtree | Reused for an unchanged local build root | Fresh per hosted run (too large to cache blindly without benchmarking) |
| Dependency extraction | Content hash avoids re-extraction | Archive is extracted once into the fresh runner, then its root is **renamed**, not copied, into position |
| Packaging + distro smoke | Always verified for releases | Always rerun, even if the source SHA is unchanged |

## Two distinct CI artifacts

`vendor/builder/Dockerfile` is the canonical, pinned-profile AlmaLinux 9
builder definition. `.github/workflows/forge-toolchain.yml` publishes
`ghcr.io/<owner>/<repo>-builder:alma9-<recipe-sha>` **only when its recipe
changes**, or on manual dispatch. This publication is isolated from the
four-hour OpenMW release workflow. The scheduled workflow resolves the image
into a digest-pinned `FROM` line so its content cannot change partway through
one build. The builder image carries system tools and Autoconf 2.72, **not**
OpenMW source, release credentials, or a fixed Jess executable.

The runtime automatically falls back to the embedded source build if the GHCR
package has not been published, so fresh forks can still work. The initial
fallback will be much slower, may challenge standard runner disk limits, and
**must not** be mistaken for a fully qualified production run. Publishing the
toolchain from the default branch first is highly recommended.

The **qualified SDK export** is a separate, immutable cache input. For a hit,
Forge requires a matching profile, triplet, pinned vcpkg revision, exact overlay
file hashes, compiler/CMake/Autoconf version strings, toolchain OCI identity,
archive SHA-256, and safe archive member listing. A mismatch causes a rebuild,
not silent reuse. New exports receive their metadata only after vcpkg export
and ABI verification. Host-native filesystem locks serialize concurrent writers
without leaving stale lock directories after crashes.

Actions' key includes the relevant Jess SDK implementation and overlay assets.
The cache itself is **not a release artifact**. A full build still checks the
packaged launchers and ABI, runs GoogleTests, and performs distro smoke tests.
Caches can expire or be evicted; cache misses must never turn into release-gate
skips.

## Hosted runner disk, memory, and cold-start cost

Standard GitHub-hosted `ubuntu-24.04` runners have limited cores, RAM, and
**14 GB of nominal SSD**, with different CPU/RAM allocations for public and
private repositories. `ci/uberbranch-config.jsl` starts with two compiler
jobs. More jobs are not necessarily faster when C++ compilation starts
swapping, or when a CMake job fails for lack of memory.

After SDK verification, CI saves the export and binary packages **before**
OpenMW compilation. `tools/ci_resources.jsl` then refuses to run outside the
expected GitHub workspace and removes only the Forge-owned temporary vcpkg
checkout and its CI binary-package cache. This reclaims room for CMake, debug
symbols and packaging. Extraction uses same-filesystem rename to eliminate a
second full SDK copy. `df -h` is printed before and after this reclamation.

The toolchain image must still be pulled into the ephemeral runner, and Docker
image layers share its disk budget. On a genuinely cold run, dependency builds
may still exceed standard hosted resources. **No complete OpenMW production
compile was performed in the development sandbox**, so we do not claim a
measured cold/warm speedup or guaranteed completion time.

## Measuring the right things

Use the GitHub job's individual step durations to separate SDK preparation,
OpenMW compilation and distro smoke. Retain `ccache --show-stats`, the SDK
reuse/rebuild log line, and the before/after disk reports. Benchmark four
scenarios on identical runners: first cold build, unchanged `master`, new
OpenMW commit with identical dependencies, and changed vcpkg overlay or
builder image. Report elapsed time, peak disk usage, ccache hit rate, SDK
cache status, and release hashes. A fast but false-green build has no value.

GitHub's cache storage is finite. We intentionally **do not** upload complete
CMake buildtrees or every installed dependency directory to Actions cache:
they would consume substantial bandwidth and compete with the compiler cache.
Do not increase ccache capacity without measuring cache-hit improvement versus
upload/download time and quota churn. Use a separate GHCR/OCI-based artifact
store if the qualified SDK outgrows repository cache limits.

## Known limits / further work

- Base AlmaLinux tags and the Qt installer feed are not yet hermetically pinned
  end-to-end. OCI toolchain digests help at consumption time, but do not turn a
  mutable upstream download into a reproducible dependency closure.
- GitHub cache entries are immutable. A corrupted matching SDK cache triggers
  a rebuild, but GitHub may continue serving that old key until it expires or
  the cache generation/key is changed; monitor that case explicitly.
- The vcpkg installed tree and CMake buildtree are not carried between hosted
  runs. Do not cache them without cold/warm transfer benchmarks and strong
  invalidation rules.
- Ninja, `ccache`, Qt, compression and distro smoke behavior must be measured
  against a **real** OpenMW package before further micro-optimization.

See [CI](CI.md), [release configuration](RELEASE.md), and
[release readiness](RELEASE-READINESS.md).
