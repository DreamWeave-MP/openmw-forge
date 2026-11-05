# OpenMW Forge

A consolidated **Jess workspace** for Linux OpenMW dependency builds, binaries, and portable tarball packaging. The canonical compatibility target is **AlmaLinux 9**. It replaces the two repositories' top-level Bash command interface with a typed, tested Jess command planner, while retaining the difficult, compatibility-sensitive CMake/vcpkg/Qt and archive leaf scripts until an actual end-to-end build can validate their replacement.

This is intentionally a **Linux build tool**, not a port of the original dependency repository's Windows/macOS GitHub Actions workflows. Those jobs and symbol-server uploads are outside the Linux migration. See [`docs/AUDIT.md`](docs/AUDIT.md) for the per-file responsibility map and remaining limitations.

## What it does

- One entry point: `forge` (Jess package target) with `doctor`, `deps`, `build`, `pipeline`, `package`, `verify`, and `smoke` commands.
- One compatibility baseline: AlmaLinux 9, `x64-linux-dynamic`, with `GLIBC_2.34`, `GLIBCXX_3.4.29`, and `CXXABI_1.3.13` ceilings. A failed explicit archive download **does not** silently fall back to the old AlmaLinux 8 artifact.
- Direct, argument-vector process spawning; no interpolated shell command lines in the Jess orchestration.
- Container builds isolated under Podman or Docker, or explicit local/distrobox operation.
- A side-effect-free plan via `--dry-run`, fail-fast subprocess handling, and source/write-root overlap checks including symlink aliases.
- Optional both-suite GoogleTest execution, debug-symbol sidecars, compatibility auditing, packaged binary smoke tests, and multi-distribution testing.

## Quick start

Requires Jess 0.3.0 / Luau 0.745 matching this workspace, Bash, Git, and Podman or Docker. The production build also downloads CMake/vcpkg/Qt dependencies and needs a substantial amount of disk space and compute. Commands run from the **repository root**.

```bash
# Confirm the tool interface and prerequisites; no downloads.
jess workspace run --trusted forge -- help
jess workspace run --trusted forge -- doctor

# Inspect exactly what would execute without creating files.
jess workspace run --trusted forge -- pipeline \
  --source /absolute/path/to/openmw --dry-run

# Build pinned vcpkg dependencies in AlmaLinux 9, then compile/package OpenMW.
jess workspace run --trusted forge -- pipeline \
  --source /absolute/path/to/openmw --jobs 6 --run-tests

# Or build in two phases, reusing the generated dependency archive.
jess workspace run --trusted forge -- deps
jess workspace run --trusted forge -- build \
  --source /absolute/path/to/openmw --stage-only --no-qt
```

The `--no-qt` example is only usable if the selected `--deps-prefix` already contains the required Qt installation; for a fresh workspace omit `--no-qt`.

For an existing AlmaLinux 9-compatible `.7z` dependency export:

```bash
jess workspace run --trusted forge -- build \
  --source /absolute/path/to/openmw \
  --deps-archive /absolute/path/to/vcpkg-x64-linux-dynamic.7z \
  --build-type RelWithDebInfo --portable
```

A local mode (`--mode local`) runs the legacy leaf scripts directly and **must be run on a correctly provisioned AlmaLinux 9 machine**; running local mode on Bazzite/Fedora does not guarantee the required GLIBC floor. Distrobox mode (`--mode distrobox`) is available for full dependency and OpenMW builds; use container or local for package-only assembly. Container mode builds two images tagged `openmw-forge-deps:alma9` and `openmw-forge-openmw:alma9`, which it retains for caching. No container runtime is removed unless an explicitly selected legacy distrobox script does so.

## Common operations

| Goal | Command and main options |
|---|---|
| Build only dependencies | `deps [--deps-output PATH] [--triplet NAME]` |
| Build + package | `build --source PATH [--deps-archive FILE|HTTPS_URL]` |
| Build full pipeline | `pipeline --source PATH` |
| Build and leave staging tree | `build --source PATH --stage-only` |
| Repackage compiled tree | `package --source PATH [--portable] [--no-smoke]` |
| Reuse existing extraction | `build --source PATH --no-prepare` |
| Run CMake/GoogleTest suites | `build --source PATH --run-tests [--gtest-filter FILTER]` |
| Verify dependency export | `verify [--deps-output PATH]` (host requires 7zip + readelf) |
| Test packaged tarball | `smoke --archive PATH [--with-qt]` |
| Test across distroboxes | `smoke --archive PATH --distros almalinux-9,debian-12` |
| Inspect plan only | Any command + `--dry-run` |

Other flags include `--mode container|local|distrobox`, `--engine podman|docker`, `--build-dir`, `--deps-prefix`, `--output-dir`, `--jobs`, `--qt-version`, `--triplet`, `--build-type`, `--clean`, `--no-ccache`, `--no-system-packages`, `--cmake-arg` (repeatable), `--no-compat`, and `--no-smoke` (opt-outs for package validation). Options are parsed as values, not shell code. `--run-tests` builds both `openmw-tests` and `components-tests` and runs them before packaging.

**Output roots:** `artifacts/deps/` for dependency exports, `artifacts/openmw/` for tarballs, `work/build/` for CMake and staging, and `work/deps/` for extracted dependencies and Qt. These are ignored by Git. Override them with separate absolute paths; writable roots must not overlap the source checkout or each other.

## Validation

```bash
# Requires JESS_BIN only if Jess is not on PATH.
JESS_BIN=/path/to/jess ./tools/validate.sh
```

This runs the Luau strict checker, the source-and-packed Jess suite, Jess's **own style checker**, Bash syntax checks for retained workers, mocked end-to-end CLI execution, and archive traversal/symlink guard tests. A full production dependency/OpenMW build is **not** claimed validated; see [`docs/VALIDATION.md`](docs/VALIDATION.md) for details and steps to finish qualification on an AlmaLinux 9 runner.

## Layout

- `src/` — Jess parsing, configuration, deterministic execution plans, checked subprocess execution.
- `tools/forge.jsl` — command entry point, with capabilities declared in `jess.toml`.
- `vendor/deps/` — original pinned vcpkg manifest, overlays, custom Linux triplet, AlmaLinux system bootstrap, exporter, ABI verification.
- `vendor/openmw/` — original OpenMW CMake, Qt, packaging, debug-symbol, distrobox, and smoke-test workers, with focused migration fixes.
- `tests/` — Jess pure planner tests, mocked integration checks, tarball safety checks.
- `docs/` — upstream audit, constraints, and verification evidence.

Jess does not magically make AlmaLinux and Qt builds hermetic. Network dependencies, base-image tag mutability, external vcpkg/Qt source distribution, host SELinux/Docker differences, and the underlying CMake project remain real operational dependencies. We preserve the existing checks rather than claiming that passing unit tests proves binary portability.

## License

The dependency build repository shipped its source under Apache-2.0; its license remains at `vendor/deps/LICENSE`. Original source and upstream notices remain within the imported directories. The combined workspace is offered under Apache-2.0; retain the notices of included third-party port patches and distributions.
