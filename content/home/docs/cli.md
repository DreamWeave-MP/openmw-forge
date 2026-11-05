+++
title = "CLI reference"
weight = 10
description = "OpenMW Forge: CLI reference"
+++


The compiled ELF is self-contained. Rename it to `forge`, make it executable,
and run it from any writable directory. No workspace checkout is needed.

```sh
./forge --version
./forge --help
./forge pipeline --help
./forge doctor --mode container --engine docker
```

## Everyday build

```sh
./forge pipeline --repo https://gitlab.com/OpenMW/openmw.git --ref master \
  --engine docker --jobs 8 --run-tests --dry-run
./forge pipeline --repo https://gitlab.com/OpenMW/openmw.git --ref master \
  --engine docker --jobs 8 --run-tests
```

The remote checkout lives under `work/sources/`; switching forks and refs
uses managed, separate checkouts and versioned output names. You can also use
`--source /path/to/local/openmw` to build an existing tree without any Git
mutation. Never combine `--source` and `--repo`.

## Advanced commands

- `deps`: pinned vcpkg/Qt dependencies and AlmaLinux 9 ABI verification.
- `build`: compile and package from existing dependency archives or prepared roots.
- `package`: repackage an already compiled build tree.
- `verify`: verify a dependency export and its ABI.
- `smoke`: check archive safety, ABI, **actual packaged POSIX launchers** and
  ELF binaries; use `--distros almalinux-9,ubuntu-24.04` to test both.
- `doctor`: check a working container engine or a native AlmaLinux 9 host.

Run `./forge COMMAND --help` for command-specific examples. The default
container engine is Podman; set `--engine docker` on Docker hosts.

`--clean` only removes Forge-marked build roots. `--dry-run` is read-only.
HTTPS dependency archives require `--deps-sha256`. Forge compresses the main
`.tar.gz` and `-debug.tar.gz` into a managed staging directory before changing
either published file; an interrupted local publication restores the previous
set on the next run. These remain two filesystem entries rather than one
atomically visible object. Release automation verifies both digests.

Full cold builds require substantial disk, network and CPU resources. For
repeated builds, the image holds the SHA-512-verified Autoconf 2.72 toolchain
and Forge reuses matching content-derived image tags, while vcpkg downloads and
binary caches persist on the build host.
