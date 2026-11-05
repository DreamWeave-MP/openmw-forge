# OpenMW Forge

**A standalone Linux x86-64 executable built with Jess 0.3 / Luau 0.745.** Forge merges the dependency and OpenMW Linux build repositories into one command-line tool. **AlmaLinux 9** is the sole supported build ABI baseline. The executable embeds its Jess runtime, pinned vcpkg manifest, triplets, port overlays, OpenMW packaging templates, and the actual Jess workers. You do **not** need a Jess installation, workspace checkout, or Bash script to use the compiled executable.

The OpenMW source checkout, external build tools, a container engine (Podman or Docker by default), and network/compute for the real builds are still needed. Forge is an orchestrator, not a replacement for CMake, vcpkg, Qt, compiler toolchains, or a container runtime.

## Quick start: compiled binary

```sh
chmod +x ./openmw-forge-linux-x64
./openmw-forge-linux-x64 help

# Dry-run without writing files or requiring the OpenMW checkout.
./openmw-forge-linux-x64 pipeline --source /absolute/path/to/openmw --dry-run

# Production dependency + OpenMW pipeline, inside AlmaLinux 9:
./openmw-forge-linux-x64 pipeline --source /absolute/path/to/openmw --jobs 6 --run-tests

# Independent phases:
./openmw-forge-linux-x64 deps
./openmw-forge-linux-x64 build --source /absolute/path/to/openmw

# Reassemble an already compiled checkout, without rebuilding:
./openmw-forge-linux-x64 package --source /absolute/path/to/openmw \
    --build-dir /absolute/path/to/build --deps-prefix /absolute/path/to/deps

# Smoke-test an existing OpenMW tarball, optionally across Linux distros:
./openmw-forge-linux-x64 smoke --archive /absolute/path/to/openmw.tar.gz \
    --distros almalinux-9,debian-12,ubuntu-24.04
```

Default mode is `--mode container` with `--engine podman`; `--engine docker` is supported. Native `--mode local` runs tools directly on an AlmaLinux 9 host. `distrobox` is **not** supported: the prior Distrobox Bash workflow has been removed rather than emulated. `--no-system-packages` can avoid the automatic DNF bootstrap when running in a preprovisioned environment.

You may execute Forge from **any** directory. Relative options resolve against the current directory; defaults create `work/` and `artifacts/` beneath it, not inside the OpenMW source checkout. `--dry-run` plans without creating directories or starting tools. Writable paths must not overlap the source tree or each other, including through existing symlinks.

## Commands and switches

| Command | Responsibility |
|---|---|
| `doctor` | Check container engine, or native local tools, without changing the system |
| `deps` | Build pinned vcpkg overlay ports, export `.7z` and metadata, verify ELF ABI |
| `build` | Prepare Qt/vcpkg, configure and compile OpenMW, optionally run GoogleTests, package |
| `pipeline` | Run `deps` then `build` in one invocation, passing the resulting archive |
| `package` | Stage binaries, Qt/plugins, vcpkg libraries, resources and debug sidecars |
| `verify` | Check an existing dependency export, metadata and symbol-version limits |
| `smoke` | Validate an OpenMW `.tar.gz`, then run ELF smoke checks (optionally on a distro matrix) |
| `help` | Print complete usage and switches |

Important options: `--source`, `--deps-archive` (local absolute `.7z`/`.tar.xz` or HTTPS), `--deps-output`, `--build-dir`, `--deps-prefix`, `--output-dir`, `--jobs`, `--qt-version`, `--build-type`, `--triplet`, `--clean`, `--portable`, `--stage-only`, `--no-prepare`, `--no-qt`, `--no-ccache`, `--run-tests`, `--gtest-filter`, `--no-compat`, `--no-smoke`, repeatable `--cmake-arg`, `--distros`, `--with-qt`, and `--dry-run`. `--no-qt` skips installing Qt but does **not** waive the requirement for an existing Qt installation at configuration time.

The ABI ceilings match AlmaLinux 9: `GLIBC_2.34`, `GLIBCXX_3.4.29`, `CXXABI_1.3.13`. Dependencies and OpenMW are built with the pinned `x64-linux-dynamic` triplet. An explicit dependency download does not silently fall back to an old artifact.

## Jess source and development

The shipped executable requires no Jess runtime. **Developers** who want to edit or rebuild the source can use the executable Jess scripts, which carry their own shebangs:

```sh
# In this repository, with jess on PATH:
./tools/forge.jsl help
./tools/release.jsl /absolute/path/to/openmw-forge-linux-x64
./tools/validate.jsl /absolute/path/to/openmw-forge-linux-x64
```

Alternatively, `jess workspace pack --output /path/to/openmw-forge-linux-x64 --runtime /path/to/jess` produces a standalone ELF binary directly. Build orchestration, dependency verification, OpenMW staging, debug splitting and smoke-test coordination live in `src/native*.jsl` and `src/plan.jsl`; process invocation passes argv vectors, never a Bash `-c` command. `src/assets.jsl` is generated from the retained original vcpkg overlays/templates for embedding in the executable. Jess source tests run in source and packed JPK form.

The upstream vcpkg project itself supplies `bootstrap-vcpkg.sh`, and distributed OpenMW tarballs include the upstream POSIX `/bin/sh` launcher to set their runtime library paths. Those are **third-party packaging/runtime interfaces**, not Forge build orchestration. CMake, DNF, Git, tar, Python and compiler binaries remain native external processes.

## Scope and qualification

- The Linux build workflows are migrated; Windows/macOS original CI jobs and symbol-server publishing are intentionally out of scope.
- `jess package check`, Jess style, source+packed unit tests, and a compiled ELF integration suite are automated. The latter uses an independently compiled Jess fake container engine, builds a synthetic package staging tree, and tests archive rejection.
- **A full production vcpkg+Qt+OpenMW build and cross-distro smoke sweep have not run in the supplied sandbox.** Podman and Docker are absent here. Do not interpret the green tests as proof of binary portability; qualify this against an AlmaLinux 9 build host before publishing releases.
- Upstream container image tags, Qt downloads and dependency archives are not yet content-addressed; real builds are not hermetic. See `docs/VALIDATION.md` and `docs/AUDIT.md` for detail.

## Licensing

The original dependency builder is Apache-2.0 and its notice remains at `vendor/deps/LICENSE`. Existing upstream port patches, vcpkg manifest and OpenMW template notices are retained. The consolidated Forge source is offered under Apache-2.0, subject to retained third-party notices.
