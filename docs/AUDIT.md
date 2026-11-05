---
layout: default
---

# Migration audit: two Bash-driven Linux build repositories to one native Jess tool

The supplied inputs were `dream-deps-build.bundle` HEAD `5981e98` and `openmw-linux-build.bundle` HEAD `88d88df`. We preserve the **AlmaLinux 9** ABI floor, original dependency manifests/ports and packaging templates. The migration targets Linux; legacy macOS/Windows CI is not being replaced.

## Dependency repository inventory

| Original file group | Responsibility | Jess-native replacement / status |
|---|---|---|
| `build.conf` | ABI/profile defaults, vcpkg and autoconf pin | `src/config.jsl` and `src/native_deps.jsl` (Alma 9 only) |
| `Dockerfile`, `.dockerignore` | System build image | `src/native.jsl` emits a single Alma 9 Dockerfile embedding the compiled Forge binary |
| `vcpkg.json` | Exact dependency manifest | Retained under `vendor/deps/`; embedded in `src/assets.jsl` |
| `ports/openmw-osg/`, `ports/openmw-mygui-osx/`, `ports/unshield/` | Overlay ports and patches | Preserved and embedded; macOS-only MyGUI data retained as provenance |
| `triplets/` | Custom dynamic Linux and macOS triplets | Preserved; Linux `x64-linux-dynamic` is canonical |
| `scripts/lib/config.sh`, `fail.sh` | Bash environment/trap helpers | Eliminated; typed options and exceptions in Jess |
| `scripts/doctor.sh` | Prerequisite checks | `src/execute.jsl` `doctor` |
| `scripts/install-system-deps.sh` | DNF/EPEL/CRB/toolset/autoconf | `src/native_deps.jsl`; signed autoconf source SHA-512 retained |
| `scripts/setup-vcpkg.sh`, `build-deps.sh` | Checkout pin, bootstrap, vcpkg install | `src/native_deps.jsl` invokes upstream Git/vcpkg by argv |
| `scripts/build-all.sh`, `verify-build.sh`, `verify-abi.sh` | Orchestration, export metadata, ELF ABI audit | `src/native_deps.jsl` native workers |
| `scripts/cleanbuild.sh` | Destructive container/distrobox management | Removed; Jess plans explicit image/build roots, no implicit distrobox destruction |
| `.github/` and `Store-Symbols.ps1` | Cross-platform CI and Windows symbols | Not migrated; beyond scope of Linux standalone tool |

The dependency system's strengths were pinned source inputs, custom vcpkg ports, triplet discipline and post-export ELF audits. Weaknesses included scattered configuration, Bash stateful workers, Alma 8 defaults, multiple incompatible ABI ceilings, unsafe early deletion of artifacts and a broken 7zip preflight. Jess consolidates the Linux path in one process and preserves the ABI checks. The external vcpkg *project* still requires its own bootstrap script.

## OpenMW Linux repository inventory

| Original file group | Responsibility | Jess-native replacement / status |
|---|---|---|
| `config/deps_versions.sh` | Qt version and dependency artifact fallback | Typed default options in `src/config.jsl`; no historical-archive fallback |
| `docker/Dockerfile.tarball` | Compiler/packaging container | Shared Alma 9 image in `src/native.jsl` |
| `scripts/prepare_deps.sh` | System packages, Qt download, archive extraction | `src/native_openmw.jsl` `prepare` and `extractDeps` |
| `scripts/configure_openmw.sh`, `build_binaries.sh` | CMake configure and build | `src/native_openmw.jsl` `configure` and `build`, both GoogleTest targets |
| `scripts/assemble_tarball.sh`, `split_debug.sh` | ELF files, plugins, Qt libs, resources, debug symbols, final tarball | `src/native_package.jsl` `package`/`splitDebug` |
| `scripts/check_compat.sh`, `tests/test_tarball.sh` | ELF ceilings and archive safety | `src/native_abi.jsl` and `src/native_archive.jsl` |
| `tests/multi_distro_test.sh` | Distrobox package testing | `src/native_smoke.jsl` native container image matrix |
| `scripts/run_container.sh`, `run_distrobox.sh` | Interactive command-line wrappers | Removed, superseded by compiled Jess entry point and deterministic `src/plan.jsl` |
| `scripts/build_local_staging.sh` | Local convenience helper with hardcoded home path | Removed; direct CLI `package`/`--stage-only` replaces it |
| `templates/runtime_wrapper.sh.in`, `README.packagecontents.txt` | OpenMW distribution launcher and readme | Retained unchanged and embedded as data; POSIX runtime launcher is not an orchestration worker |
| `docs/` | Old workflow documentation | Superseded by root README and this audit |

The OpenMW builder already had good source/build separation, portable packaging, debug symbols, and smoke/compatibility checks. Its weakest parts were overlapping Bash CLIs, hardcoded developer paths, implicit environment coupling and the possibility of silently using an old dependency release.

## Resulting architecture

`tools/forge.jsl` is a shebang-enabled Jess command target; `jess workspace pack --runtime` produces one portable Linux executable. `src/args.jsl` parses typed options. `src/plan.jsl` produces deterministic command+mount vectors, and `src/execute.jsl` enforces path safety, resolves symlink aliases and stops on the first failure. `src/native_openmw.jsl` builds, `src/native_package.jsl` stages, `src/native_smoke.jsl` executes package tests, `src/native_abi.jsl` audits ABI ceilings, `src/native_archive.jsl` validates archive members, and `src/source.jsl` selects remote Git revisions. `src/assets.jsl` embeds the original vcpkg overlays and templates, so an extracted source/workspace is unnecessary. `tools/{release,validate,integration}.jsl` are additional executable Jess scripts.

CMake, vcpkg, Git, tar, DNF, Qt installers, compiler utilities and Podman/Docker remain separate processes—not Bash `-c` orchestration. The emitted Dockerfile necessarily uses container RUN directives. The upstream OpenMW POSIX wrapper remains in *published OpenMW tarballs*, where it establishes library paths, but Forge itself neither launches nor requires a Bash worker.

## Limitations

Production network builds were not executed. External package availability on Alma 9, Qt's installer behavior and the compiled OpenMW ABI must be qualified on actual hosts. We deliberately dropped Distrobox mode rather than keep its Bash worker. Base and smoke images and Qt downloads are not digest-pinned. HTTPS dependency archives are SHA-256-verified, while the vcpkg source is revision-pinned. Main/debug archives are prepared as a recoverable pair, but no pair of separate filesystem renames is simultaneously atomic to outside readers. Dependency export metadata and payload also do not form one atomic multi-file transaction. Windows/macOS CI and symbol publishing remain out of scope.
