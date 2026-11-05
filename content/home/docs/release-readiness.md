+++
title = "Release readiness"
weight = 40
description = "OpenMW Forge: Release readiness"
+++


The CLI is built and exercised in a Jess 0.3/Luau 0.745 sandbox, **not yet
qualified as a production OpenMW release builder**. No Docker/Podman engine is
available in the test environment, and vcpkg/Qt/OpenMW were not actually
compiled here. Treat all external dependency packaging and ABI compatibility
claims as unverified until the following checks run on an AlmaLinux 9 builder.

## Required physical build gates

1. Build a real pinned vcpkg dependency export and verify its 7z metadata,
   ELF symbol ceilings, and extracted symlinks on AlmaLinux 9.
2. Build an upstream OpenMW branch and a fork feature branch using `--repo`.
   Compare their reported SHA and generated `FORGE_BUILD_SOURCE.txt` metadata.
3. Run both GoogleTest targets, package debug symbols, and verify the actual
   OpenMW ELF and Qt plugin closure. Never use `--no-compat`/`--no-smoke` for
   release artifacts.
4. Test a final package in a clean execution environment and in the selected
   distro matrix (`almalinux-9,debian-12,ubuntu-24.04` initially).
5. Repeat the *same* build: measure cold/warm elapsed time, CPU time, peak RSS,
   data downloaded, and vcpkg cache hits. Repeat after changing only the OpenMW
   source revision, then after changing the dependency manifest.
6. Simulate interrupts during dependency export, Qt installation and
   main/debug archive publication. Ensure prior releases remain consumable,
   verify recovery journals and managed-directory rollback, and exercise
   contested build/source/SDK/smoke locks across separate processes.
7. Exercise valid real-world vcpkg exports containing symlinks and hardlinks;
   the 7z metadata checks are tested against synthetic listings but not a real
   vcpkg export in this environment.

## Operating constraints

- Remote forks: `--repo https://host/owner/openmw.git --ref branch-or-sha`.
  Local working trees: `--source /path/to/openmw`, never automatically reset.
- `--clean` requires a Forge-owned build root. Generated staging paths also
  require valid ownership markers; inspect old unmarked workspaces manually.
- HTTPS dependency archives require `--deps-sha256` and reject corrupted caches.
- Persistent vcpkg downloads and binaries are stored under `work/cache/`.
  The AlmaLinux 9 toolchain dependencies are layered into the image.
- Native workers invoke CMake, Git, vcpkg, tar and other external executables
  with argument arrays. Forge contains no Bash orchestration script.
- The original vcpkg bootstrap and the packaged OpenMW POSIX runtime launcher
  are upstream interfaces, not Forge workers.

## Limits of this increment

There is no measured speedup against the original two repositories yet.
The first run can still be slow because of image construction, the source
checkout and native dependency compilation. Qt downloads and distro images
lack immutable content pins, and a release is not fully hermetic. Source
checkout collisions are checked against the stored remote identity. Do not
claim production ABI or distro compatibility based solely on the supplied
synthetic fixtures.

## Adversarial review follow-up

See [2026-11-05 hardening](@/home/docs/hardening-2026-11-05.md) for the internal worker
checks, cross-root locks, extracted SDK fingerprint, Qt validation and Docker
UID/GID behavior. This does not replace a real hosted cold/warm build, an
independent transitive runtime/Qt plugin closure scan, or a native SHA-256
manifest-driven Qt acquisition implementation. Rolling releases remain
non-atomic at the GitHub API level: consume only checksum-verified artifact
sets.
