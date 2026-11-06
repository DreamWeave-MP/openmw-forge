# OpenMW Forge

**A standalone Linux x86-64 executable built with Jess 0.3 / Luau 0.745.** Forge merges the dependency and OpenMW Linux build repositories into one command-line tool. **AlmaLinux 9** is the sole supported build ABI baseline. The executable embeds its Jess runtime, pinned vcpkg manifest, triplets, port overlays, OpenMW packaging templates, and the actual Jess workers. You do **not** need a Jess installation, workspace checkout, or Bash script to use the compiled executable.

The OpenMW source checkout, external build tools, a container engine (Podman or Docker by default), and network/compute for the real builds are still needed. Forge is an orchestrator, not a replacement for CMake, vcpkg, Qt, compiler toolchains, or a container runtime.

## CI, documentation and the four-hour OpenMW release

Forge runs on standard GitHub-hosted Ubuntu runners. The regular
`.github/workflows/forge-ci.yml` validates Jess strict/style, source/JPK tests,
and the standalone Linux ELF, then invokes StroggForge's **Jess-native**
`modGlobalBuild.yml@v69` to build and check the documentation directly from
[`content/home/docs/`](content/home/docs/_index.md). No Zola or Jekyll.
The site toolchain is pinned independently of Forge's newer Jess runtime.
The separate `.github/workflows/das-uberbranch.yml` schedules an OpenMW
**Linux package + detached debug symbols** every four hours (`23 */4 * * *` UTC), running real
AlmaLinux 9/Docker builds, GoogleTests, archive and launcher verification, and
a cross-distro smoke gate before updating the `das-uberbranch` prerelease.

**To switch the scheduled fork or branch, edit only**
[`ci/uberbranch-config.jsl`](ci/uberbranch-config.jsl): its `repository` and
`ref` initially select official `https://gitlab.com/OpenMW/openmw.git` at
`master`. The workflow uses ordinary GitHub-hosted `ubuntu-24.04` runners: no custom
runner registration or hardware. It runs AlmaLinux 9 inside Docker and publishes
releases through a separate, narrowly write-permitted job. The checked-in
configuration defaults to **`--jobs auto`**, resolving the CPUs available inside the
AlmaLinux build container at execution time. Use `--jobs N` or set `jobs = N`
in `ci/uberbranch-config.jsl` to limit concurrency if peak GCC memory demands it. For setup, see [CI](content/home/docs/ci.md), [scheduled releases](content/home/docs/release.md),
[CLI examples](content/home/docs/cli.md), [performance](content/home/docs/performance.md),
[troubleshooting](content/home/docs/troubleshooting.md) and [release qualification](content/home/docs/release-readiness.md).
The heavy production build **has not been executed in this test sandbox**.

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

## Building an arbitrary OpenMW fork or branch

Forge can build an **existing checkout** (`--source`) or resolve a **remote Git
fork** (`--repo` with optional `--ref`). You do not need to change your local
checkout, and Forge never resets a user-supplied source tree:

```sh
./openmw-forge-linux-x64 pipeline \
    --repo https://github.com/your-name/openmw.git \
    --ref feature/cool-shaders --jobs 12 --run-tests

# Build a local checkout in whatever branch it currently contains:
./openmw-forge-linux-x64 pipeline --source /path/to/your/openmw --jobs 12
```

SSH Git remotes and explicit commit SHAs, tags, `refs/heads/...`, and feature
branches are supported. Remote source preparation is shallow and uses a private,
per-repository checkout under `work/sources/`. Changes to that managed checkout
are **not silently destroyed**: a dirty checkout makes a later revision switch
fail closed. Repositories with different remotes never share the same checkout;
per-remote-and-ref CMake build directories avoid stale cross-fork caches.

Remote packages include a `-g<12-digit commit>` component in their archive name
and a `FORGE_BUILD_SOURCE.txt` file recording the remote, requested ref and
resolved full Git SHA. Dry runs display the requested ref without connecting to
Git or writing anything. Git must be installed on the machine running Forge
when `--repo` is used; the container image includes Git as well.

### Cached SDK extraction and link validation

The cached `vcpkg-*.7z` SDK is SHA-256 checked, then metadata-preflighted
before a single extraction into an isolated Forge-owned staging directory.
Versioned `.so` symlinks often form chains; the extractor uses 7-Zip's
`-snld10` policy so those legitimate internal links and parent-relative
systemd links are not rejected. Forge still validates extracted link targets,
containment, and archive metadata before it publishes the SDK. Never use
`-snld20` or restore the old one-process-per-symlink decompression loop.

## Bounded GUI smoke tests

Release smoke tests still exercise **both** native executables and packaged
launchers, including the Qt graphical tools (`openmw-launcher`, `openmw-cs`,
`openmw-wizard`). Forge launches GUI programs **without command-line arguments**:
OpenMW-CS treats `--help` as a filename and terminates when that file does
not exist. Unlike command-line tools, graphical applications start their event
loops rather than consistently supporting a help flag. Forge checks GUI startup
for **five seconds** with `QT_QPA_PLATFORM=offscreen`. A clean exit passes; a process
that stays alive through startup with no fatal linker/Qt diagnostics counts as a
*startup-liveness pass*, then Forge terminates it. Early crashes, loader errors,
Qt platform failures, reported fatal startup errors, and OOM kills fail.
A process that displays a non-fatal warning and remains running still counts as
alive, not fully functional. This check does not guarantee complete GUI
functionality or a usable display.

The minimal distro smoke images explicitly provision GL, EGL and GLib runtime
libraries. GL/EGL installation alone does not guarantee `libglib-2.0.so.0`
on Ubuntu 24.04. For GLib, Ubuntu 24.04 and Debian 13 use
`libglib2.0-0t64`, whereas Ubuntu 22.04 and Debian 12 use `libglib2.0-0`;
other package managers have their own names. These are dependencies of the
**test containers**, not changes to the AlmaLinux toolchain or OpenMW SDK.

Command-line tools retain `--help` arguments, strict help/exit validation, and a **30-second**
execution deadline. In cross-distribution smoke checks, Forge launches
containers detached, polls their state, collects their logs, and forcibly removes
each container on completion. These limits do not change the AlmaLinux builder,
vcpkg SDK, or published package format.

## Persistent caches and safe cleanup

The AlmaLinux 9 container image contains the system packages used by both build
phases; this prevents repeated DNF installs on short-lived worker runs. Host
volumes persist the vcpkg checkout/downloads, compiled binary cache, and
OpenMW `ccache` between container invocations. The four-hour GitHub-hosted workflow resolves a separately published
AlmaLinux 9 GHCR toolchain image to its immutable digest when available,
restores a complete SHA-256-verified vcpkg SDK export and Qt cache, and reuses
`ccache` and vcpkg binary packages as appropriate. It saves the verified SDK
before OpenMW compilation and reclaims temporary vcpkg buildtrees to stay
inside normal hosted-runner disk limits. Cache misses are safe, not proof of
release compatibility. Qt and dependency extraction are skipped when the
expected outputs and content fingerprints are already present; a verified
SDK export also skips vcpkg install and export on matching inputs. These optimizations reduce redundant work, and new CMake build trees prefer
Ninja; already configured trees retain their existing generator. **No
cold-versus-warm production benchmark has yet been performed.**

The builder is currently pinned to AlmaLinux `9.5-20250519` and 9.5 vault
repositories to avoid the 9.7 GLIBC_2.35 function backports; GCC Toolset 13 is retained. The
image checks the specific dangerous versioned exports before heavy provisioning
and after DNF. The complete SDK and release are separately audited for every
imported ABI requirement above the GLIBC_2.34 ceiling.
SDK fingerprints and vcpkg binary caches are segregated by this baseline;
older 9.6 binaries are not reused.

`--clean` refuses to remove build content unless the target directory carries
a valid Forge ownership marker (new empty build directories are automatically
marked). Package staging, temporary extraction, smoke-test directories and
embedded asset contexts likewise require ownership markers before replacement.
If you have generated `work/` directories from the older Forge executable,
manually inspect and move/remove the old unmarked generated directories once;
Forge will not assume that a matching filename grants it permission to delete
your files.

A dependency archive fetched from HTTPS **must** provide a SHA-256 digest:

```sh
./openmw-forge-linux-x64 build --source /path/to/openmw \
  --deps-archive https://example.org/my-vcpkg-deps.7z \
  --deps-sha256 YOUR_VERIFIED_64_DIGIT_SHA256
```

Downloads are cached by verified content hash and extension, and partial
transfers are not promoted. Local `.7z` and `.tar.xz` dependency exports remain
supported. Exported dependency archives and OpenMW tarballs are built in staging
paths and verified before their final filenames are published. Main and debug
archives are staged together with a recoverable local publication journal;
they remain separate files, and GitHub Releases cannot atomically replace a
multi-file release. A failed release must not be interpreted as qualified.

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

Important options: `--source`, `--repo`, `--ref`, `--deps-sha256`, `--deps-archive` (local absolute `.7z`/`.tar.xz` or HTTPS), `--deps-output`, `--build-dir`, `--deps-prefix`, `--output-dir`, `--jobs auto|N`, `--qt-version`, `--build-type`, `--triplet`, `--clean`, `--portable`, `--stage-only`, `--no-prepare`, `--no-ccache`, `--run-tests`, `--gtest-filter`, `--no-compat`, `--no-smoke`, repeatable `--cmake-arg`, `--distros`, `--with-qt`, and `--dry-run`. **Qt is required** for the current OpenMW distribution profile; unsupported `--no-qt` is rejected instead of silently producing an incomplete build.

The ABI ceilings match AlmaLinux 9: `GLIBC_2.34`, `GLIBCXX_3.4.29`, `CXXABI_1.3.13`. Dependencies and OpenMW are built with the pinned `x64-linux-dynamic` triplet. An explicit dependency download does not silently fall back to an old artifact.

## Jess source and development

The shipped executable requires no Jess runtime. **Developers** who want to edit or rebuild the source can use the executable Jess scripts, which carry their own shebangs:

```sh
# In this repository, with jess on PATH:
./tools/forge.jsl help
./tools/release.jsl /absolute/path/to/openmw-forge-linux-x64
./tools/validate.jsl /absolute/path/to/openmw-forge-linux-x64
```

Use `jess package test .` for Forge's source and packed-JPK tests and `./tools/release.jsl /absolute/path/to/openmw-forge-linux-x64` to compile the standalone ELF. The release script stages only Forge's package payload, checks its digest, and packs it without the repository's **separate documentation dev-dependencies**. Running `jess workspace pack` directly from the repository root may resolve those site dependencies and is not the supported Forge release command. Build orchestration, dependency verification, OpenMW staging, debug splitting and smoke-test coordination live in `src/native*.jsl`, `src/source.jsl`, and `src/plan.jsl`; process invocation passes argv vectors, never a Bash `-c` command. `src/assets.jsl` is regenerated with the shebang-enabled `./tools/embed_assets.jsl` from the retained original vcpkg overlays/templates before rebuilding.

The upstream vcpkg project itself supplies `bootstrap-vcpkg.sh`, and distributed OpenMW tarballs include the upstream POSIX `/bin/sh` launcher to set their runtime library paths. Those are **third-party packaging/runtime interfaces**, not Forge build orchestration. CMake, DNF, Git, tar, Python and compiler binaries remain native external processes.

## Scope and qualification

- The Linux build workflows are migrated; Windows/macOS original CI jobs and symbol-server publishing are intentionally out of scope.
- `jess package check`, Jess style, source+packed unit tests, and a compiled ELF integration suite are automated. The latter uses an independently compiled Jess fake container engine, builds a synthetic package staging tree, and tests archive rejection.
- **A full production vcpkg+Qt+OpenMW build and cross-distro smoke sweep have not run in the supplied sandbox.** Podman and Docker are absent here. Do not interpret the green tests as proof of binary portability; qualify this against an AlmaLinux 9 build host before publishing releases.
- Base container image tags and the Qt installer source are not yet pinned by digest; HTTPS dependency archives require SHA-256, and vcpkg is revision-pinned. Real builds are not yet hermetic. See `content/home/docs/validation.md`, `content/home/docs/audit.md`, and `content/home/docs/release-readiness.md`.

## Licensing

The original dependency builder is Apache-2.0 and its notice remains at `vendor/deps/LICENSE`. Existing upstream port patches, vcpkg manifest and OpenMW template notices are retained. The consolidated Forge source is offered under Apache-2.0, subject to retained third-party notices.
