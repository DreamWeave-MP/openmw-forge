# OpenMW Standalone Linux Builder

This repository contains the portable Linux tarball build system extracted from the OpenMW branch. It is intentionally standalone: scripts accept explicit OpenMW source, build, dependency, archive, and output roots where relevant and do not call `CI/before_script.linux.sh` or depend on living under `OpenMW/CI/linux`.

## Paths

Common flags and environment variables, supported by the scripts that need them:

| Flag | Environment | Purpose |
|---|---|---|
| `--openmw-source-root` | `OPENMW_SOURCE_ROOT` | Target OpenMW source checkout. Required for configure/build/assemble. |
| `--build-dir` | `OPENMW_BUILD_DIR` | Target CMake build tree. Defaults under `LINUX_BUILD/work/`. |
| `--deps-prefix` | `TARBALL_DEPS_PREFIX` | Prefix containing `openmw-deps/` and `QT/`. Defaults under `LINUX_BUILD/work/`. |
| `--output-dir` | `TARBALL_OUTPUT_DIR` | Final tarball output. Defaults to `LINUX_BUILD/artifacts/`. |
| `--deps-archive` | `TARBALL_DEPS_ARCHIVE` | vcpkg dependency archive path or URL. |

Dependency input archives may be `.tar.xz` or `.7z` archives containing the vcpkg dependency tree. Final OpenMW packages produced by the builder remain `.tar.gz` archives.

## Direct Build

```bash
LINUX_BUILD/scripts/prepare_deps.sh \
    --deps-prefix LINUX_BUILD/work/deps \
    --deps-archive /path/to/vcpkg-x64-linux-dynamic.tar.xz

LINUX_BUILD/scripts/configure_openmw.sh \
    --openmw-source-root /path/to/openmw \
    --build-dir /path/to/build \
    --deps-prefix LINUX_BUILD/work/deps

cmake --build /path/to/build -- -j"$(nproc)"

LINUX_BUILD/scripts/assemble_tarball.sh \
    --openmw-source-root /path/to/openmw \
    --build-dir /path/to/build \
    --deps-prefix LINUX_BUILD/work/deps \
    --output-dir LINUX_BUILD/artifacts
```

Shortcut for prepare + configure + build:

```bash
LINUX_BUILD/scripts/build_binaries.sh \
    --openmw-source-root /path/to/openmw \
    --build-dir LINUX_BUILD/work/build \
    --deps-prefix LINUX_BUILD/work/deps \
    --deps-archive /path/to/deps.tar.xz
```

Shortcut for full build + package:

```bash
LINUX_BUILD/scripts/build_binaries.sh \
    --openmw-source-root /path/to/openmw \
    --build-dir LINUX_BUILD/work/build \
    --deps-prefix LINUX_BUILD/work/deps \
    --output-dir LINUX_BUILD/artifacts \
    --deps-archive /path/to/deps.tar.xz \
    --assemble
```

Shortcut for a local development build that only refreshes the package staging
directory for `$HOME/GitHub/openmw`:

```bash
LINUX_BUILD/scripts/build_local_staging.sh
```

Append `--run-tests` to configure and build `openmw-tests` and
`components-tests` in the same distrobox build tree, then run the complete
GoogleTest suites. Set `GTEST_FILTER` when a narrower run is useful.

```bash
LINUX_BUILD/scripts/build_local_staging.sh --run-tests
GTEST_FILTER='MWInputBindingsManagerTest.*' \
    LINUX_BUILD/scripts/build_local_staging.sh --run-tests
```

This always builds inside the `openmw-tarball-build` distrobox, using
`LINUX_BUILD/work/distrobox-build`, `LINUX_BUILD/work/distrobox-deps`, and three
compile jobs. It stops after staging; no debug symbols are split, no compatibility
audit runs, no smoke tests run, and no tarballs are created. The resulting staging
directory is moved into the directory where you ran the script. If an older staged
directory with the same name already exists there, it is removed before the new
one is moved into place.

`--stage-only` is also available on `build_binaries.sh`, `run_distrobox.sh`, and
`assemble_tarball.sh` when you need the same behavior with explicit paths.

## Distrobox

Requires `distrobox` and a container engine. The wrapper creates an AlmaLinux box, mounts the source tree read-only, and mounts the requested build/deps/output roots read-write.

```bash
LINUX_BUILD/scripts/run_distrobox.sh \
    --openmw-source-root /path/to/openmw \
    --build-dir LINUX_BUILD/work/distrobox-build \
    --deps-prefix LINUX_BUILD/work/distrobox-deps \
    --output-dir LINUX_BUILD/artifacts \
    --deps-archive /path/to/deps.tar.xz
```

Use `--keep-box` for repeated runs. If you reuse an existing box, make sure the same host paths are visible inside it.

## Container

Uses `podman` by default. Set `CONTAINER_ENGINE=docker` for Docker.

```bash
LINUX_BUILD/scripts/run_container.sh \
    --openmw-source-root /path/to/openmw \
    --build-dir LINUX_BUILD/work/container-build \
    --deps-prefix LINUX_BUILD/work/container-deps \
    --output-dir LINUX_BUILD/artifacts \
    --deps-archive /path/to/deps.tar.xz
```

The container image contains only this builder. The OpenMW source tree, build tree, deps prefix, and output directory are mounted at runtime. Podman/Docker volume labels are set so read-only source/archive mounts and writable build outputs work on SELinux hosts.

## Assemble Only

Use this after an existing configure/build when only package assembly changed:

```bash
LINUX_BUILD/scripts/assemble_tarball.sh \
    --openmw-source-root /path/to/openmw \
    --build-dir /path/to/build \
    --deps-prefix /path/to/deps-prefix \
    --output-dir /path/to/artifacts
```

`--portable` rewrites `openmw.cfg` so config, user data, and `data-local` live inside the extracted tarball directory.

## Compatibility Check

```bash
LINUX_BUILD/scripts/check_compat.sh --root /path/to/staged-or-extracted-tree
```

The audit enforces the AlmaLinux 9 base/system toolchain floor: `GLIBC_2.34`, `GLIBCXX_3.4.29`, and `CXXABI_1.3.13`.

## Smoke Tests

Single distro/current host:

```bash
LINUX_BUILD/tests/test_tarball.sh LINUX_BUILD/artifacts/openmw-*-Linux-64Bit.tar.gz
LINUX_BUILD/tests/test_tarball.sh --with-qt LINUX_BUILD/artifacts/openmw-*-Linux-64Bit.tar.gz
```

Multi-distro distrobox sweep:

```bash
LINUX_BUILD/tests/multi_distro_test.sh \
    --distros almalinux-9,ubuntu-22.04,debian-12 \
    LINUX_BUILD/artifacts/openmw-0.51.0-Linux-64Bit.tar.gz
```

## Layout

| Path | Purpose |
|---|---|
| `config/deps_versions.sh` | Qt/deps release pins and vcpkg triplet. |
| `scripts/prepare_deps.sh` | Installs host packages, installs Qt via aqt, extracts vcpkg deps. |
| `scripts/configure_openmw.sh` | Standalone replacement for the tarball/vcpkg branch of OpenMW CI configure. |
| `scripts/build_binaries.sh` | Prepare/configure/build orchestration. |
| `scripts/assemble_tarball.sh` | Package staging, Qt/vcpkg bundling, debug split, compat audit, smoke test, tar creation. |
| `scripts/run_distrobox.sh` | Distrobox full build/package wrapper. |
| `scripts/run_container.sh` | Podman/Docker full build/package wrapper. |
| `tests/` | Tarball smoke and multi-distro tests. |
