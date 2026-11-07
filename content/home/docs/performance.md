+++
title = "Performance"
weight = 70
description = "OpenMW Forge: Performance"
+++


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
| C/C++ object compilation | Ninja and mounted ccache | 2 GiB compressed ccache restored across hosted runs, saved even after failed packaging/smoke, per-day snapshots |
| CMake buildtree | Reused for an unchanged local build root | Fresh per hosted run (too large to cache blindly without benchmarking) |
| Dependency extraction | Full extracted-tree file/symlink hash avoids untrusted reuse; verified unchanged inputs skip decompression | Archive is extracted once into the fresh runner, then its root is **renamed**, not copied, into position |
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
private repositories. Forge defaults to `jobs = 'auto'` in
`ci/uberbranch-config.jsl`. Automatic parallelism is resolved with `nproc`
**inside the AlmaLinux container**, where the compile actually runs, not on
the outer Ubuntu host. Forge prints the resolved count and uses it for both
OpenMW and GoogleTest CMake builds (and vcpkg when an SDK rebuild is required).
An explicit `--jobs N` or scheduled `jobs = N` overrides it. More jobs may
increase peak GCC memory, trigger the OOM killer, or reduce throughput if the
runner starts swapping. Prefer measuring CI before imposing a lower fixed cap.

After SDK verification, CI saves the export and binary packages **before**
OpenMW compilation. `tools/ci_resources.jsl` then refuses to run outside the
expected GitHub workspace and removes only the Forge-owned temporary vcpkg
checkout and its CI binary-package cache. This reclaims room for CMake, debug
symbols and packaging. Extraction uses same-filesystem rename to eliminate a
second full SDK copy. `df -h` is printed before and after this reclamation.

Compiler caching uses explicit GitHub Actions restore and save steps.
The save step runs after the build/smoke stage even when that stage fails, so
successfully compiled objects survive unrelated failures in packaging and
runtime smoke tests. The cache key rotates daily and includes the immutable
builder identity; older snapshots can be restored by prefix. A cache hit is
not guaranteed until a previous run has actually saved one. The default
compressed ccache allowance is now **2 GiB**, up from 1 GiB after a logged
cold OpenMW build triggered four ccache cleanup passes.

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
Monitor actual hit rate, cleanups, and upload/download time before increasing
ccache capacity further; GitHub cache quota churn can negate improvements. Use a separate GHCR/OCI-based artifact
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

See [CI](@/home/docs/ci.md), [release configuration](@/home/docs/release.md), and
[release readiness](@/home/docs/release-readiness.md).

## Extracted SDK integrity versus speed

On repeated runs, Forge hashes the extracted SDK in bounded SHA-256 batches
(including symlink targets and directory structure). This is an intentional
correctness cost to prevent a source archive hash from hiding a corrupt
installed file. Measure this cost on hosted runners: if hashing approaches
extraction time, use an immutable verified unpacked artifact rather than
weakening the release gate.

## ELF baseline and fresh-export validation

The build container uses the dated official AlmaLinux 9.5 base image **and**
frozen 9.5 repositories. This matters because 9.7 backported `GLIBC_2.35`
symbols under a glibc 2.34 version number, creating genuine requirements
that are not available on earlier EL9 releases. Image immutability and the
SDK's image-digest cache key prevent silent baseline changes; a change to
this baseline deliberately costs one cold dependency rebuild. The sysroot
preflight installs only binutils before logging the libc RPM and checking the
versioned exports of the seven RHEL 9.7 glibc backport functions; it repeats
after bulk DNF. Legacy EL9 glibc libraries can already have a `GLIBC_2.35`
version **definition**, so checking for the bare string would fail incorrectly.
The packaged-ELF scanner is the authoritative portability gate: it rejects
**all imported** requirements above the GLIBC_2.34, GLIBCXX_3.4.29 and
CXXABI_1.3.13 ceilings, whether or not the name is on the preflight list.

The `readelf --version-info` audit now checks imported GNU version **needs**,
not exported version definitions. It runs on the installed vcpkg tree *before*
7z export, reporting progress every 100 ELF files. This prevents a late ABI
failure from wasting compression and archive inspection work.

For a **newly created** SDK, Forge validates the archive's member table and
compares listed symlinks with the already audited local installation. For
**cached or external archives**, Forge hashes and preflights the archive,
extracts it **once** into an isolated, empty managed directory using the
contained-link-compatible 7-Zip `-snld10` policy, and validates every actual
symlink target and its final containment before use. No per-link solid-archive
extraction is necessary. Unsafe paths, duplicate entries, hard links, and
archive members written through symlink ancestors are rejected **before**
extraction. Keep those checks and the post-extraction verification intact;
`-snld20` is not a safe alternative.
