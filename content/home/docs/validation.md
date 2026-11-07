+++
title = "Validation and testing"
weight = 50
description = "OpenMW Forge: Validation and testing"
+++


## Performed with the supplied Jess 0.3 / Luau 0.745 runtime

- `jess package check .`: strict type checking of package sources.
- `jess check --package . tools/*.jsl src/*.jsl tests/run.jsl`: typed checker including scripts.
- `jess package test .`: **56 tests in source + 56 tests in packed JPK = 112 passing executions** without site packages.
- `jess run --trusted tools/style.jsl`: Jess style checker clean.
- `jess run --trusted tools/release.jsl /absolute/path/to/openmw-forge`: stages the Forge package into a separate temporary workspace, verifies the package digest, and packs a Linux x86-64 ELF with an embedded Jess runtime, without restoring documentation packages.
- `JESS_BIN=/path/to/jess jess run --trusted --package . tools/integration.jsl /path/to/openmw-forge`: compiled ELF tests from a checkout-free working directory. These cover generated assets, mock Podman build/run using an **independently packed Jess mock executable**, error propagation, staging of OpenMW+Qt+vcpkg symlinks and packaging templates, and synthetic `.tar.gz` safety scenarios. The expanded suite also covers real
  offline Git fork/branch switching (using Git URL rewriting to a disposable
  local repository), dirty checkout preservation, source provenance in a staged
  release, refused destructive `--clean` on unowned roots, refused unowned staging
  and smoke scratch paths, missing-main-binary smoke failures, and atomic
  archive replacement under a deliberately failing mocked `tar` executable.
  **136 integration assertions pass** through the compiled ELF. The new
  checks explicitly reject broken packaged launchers, test source/ref selection,
  verify content-derived builder image caching, and simulate publisher first
  creation, rolling asset pruning and checksum/provenance failures.
- `tools/validate.jsl` (Jess shebang) runs these checks together and fails closed on any error.
- The current revision also exercises persistent ccache Docker mounts, disabled-cache plans, rollback/recovery of a managed dependency tree, and rejected user-owned destinations. The latest integrated fixtures additionally verify a real synthetic `.tar.xz` dependency SDK extraction and unchanged-input reuse, a corrupted/invalid SDK metadata cache, prepublished OCI toolchain consumption, and safe CI-only cleanup. A second toolchain GHCR workflow is defined but has not run in GitHub during sandbox development.
- DreamWeave Mod Template (Jess packages pinned in `jess.lock`) validates
  `content/home/mod.toml` and the content tree; the native site renderer builds
  **12 pages**, and `dreamweave-links` checks **405 local links, assets and anchors**
  on the local test fixture. GitHub Pages deployment itself remains unverified
  until the new workflow runs on GitHub.

The real OpenMW build remains unqualified: there is no Podman/Docker engine
in this sandbox, so the pinned vcpkg graph, Qt, OpenMW compilation and actual
user-visible Linux tarballs were not executed here.


The final executable has no dependency on a checked-out Jess workspace. Its runtime and overlay assets are embedded, and the generated Podman/Docker image carries the executable itself.

## What has **not** been proven

No Podman/Docker engine is available in the sandbox. We therefore did not compile the entire pinned vcpkg graph, install Qt from the network, compile a real OpenMW tree, test real debug symbol sidecars, or run the distro image matrix. Our staging fixture uses stub binaries; it is **not** a real OpenMW distribution.

Known release risks: mutable AlmaLinux and distro image tags on first publication (the consumer pins GHCR digests); Qt installer
  downloads that are not content-pinned; the multi-file dependency export
  (metadata plus archive) not being one atomic transaction; compatibility with
  actual vcpkg 7z link metadata; AlmaLinux 9 EPEL/CRB package availability;
  OpenMW CMake evolution; and real runtime plugin/library closure. HTTPS
  dependency archives are now SHA-256-required and the vcpkg source revision
  remains pinned.

Before a production release: `./openmw-forge-linux-x64 doctor`; then run `pipeline --source ... --run-tests` with no compatibility opt-outs on a container-capable host; inspect ELF requirements, debug sidecars and final packages; run `smoke --archive ... --distros almalinux-9,debian-12,ubuntu-24.04`; compare outputs of a second incremental build and retain the build logs.

The distro smoke images install both OpenGL and EGL runtime dispatch libraries
before testing the graphical Qt binaries. On AlmaLinux 9, `mesa-libGL` alone
does **not** provide `libEGL.so.1`; the smoke image also installs
`libglvnd-egl`. On Debian/Ubuntu, the corresponding package is `libegl1`.
The test images supply system graphics dependencies; they do not imply those
libraries are included in the downloadable OpenMW distribution. QtNetwork may bring in MIT Kerberos GSSAPI (`libgssapi_krb5.so.2`) even
when OpenMW-CS itself does not use network authentication. The smoke images
therefore install the distro-specific GSSAPI runtime (`libgssapi-krb5-2` on
Debian/Ubuntu, `krb5-libs` on Fedora/AlmaLinux, `krb5` on Arch/openSUSE, `mit-krb5-libs` on Void).

Before starting any packaged executable, Forge enumerates every regular ELF in
the extracted package, including `.so` libraries and Qt plugins. It invokes
`ldd` **inside each target distro image** with the same packaged library path,
collects missing dependencies and incompatible symbol versions in bounded
batches, then reports every failed distribution together. The check is strict
even if `ldd` exits zero while printing `not found`. It does not replace
bounded GUI startup or CLI smoke tests: plugin discovery and initialization
can still fail even after the ELF closure resolves. Recheck an existing archive
with `forge smoke --archive <archive.tar.gz> --distros <csv> --with-qt` without
rerunning OpenMW compilation. No Docker/Podman validation was available locally.

The Forge
package itself still undergoes the independent ELF ABI and executable checks.

## Generated asset parity

Run `jess run --trusted tools/embed_assets.jsl --check` to verify the compiled
asset map exactly matches `vendor/deps`, `vendor/openmw`, and `vendor/builder`.
The check is read-only and is mandatory in normal and scheduled CI. After
changing a vendor file, regenerate with `jess run --trusted tools/embed_assets.jsl`
and commit the resulting `src/assets.jsl` diff.

## Additional hardening regressions

The compiled integration suite also covers rejected `--no-qt` builds,
invalid-but-hash-matching SDK archive candidates falling back to a rebuild,
shared build/managed-source/SDK verification/smoke locks, a Qt cache missing
required libraries or carrying the wrong installer identity, and main/debug
archive publication plus interrupted-journal recovery. Safety fixtures also
verify that source-path overlaps are rejected **before creating lock files**
and that a main-only build cannot leave a stale matching debug sidecar.

CI executes `tools/embed_assets.jsl --check`: the embedded Jess asset map must
match the original vendor files byte-for-byte. A developer must regenerate the
asset map when editing an overlay or source template. Strict/style and fixture
tests still **do not** qualify a production OpenMW release; the real AlmaLinux
9 Docker/vcpkg/Qt/CMake/distro run is the final gate.

### GUI startup is bounded, not skipped

The release smoke gate launches the packaged `openmw-launcher`, `openmw-cs`,
and `openmw-wizard` executables and shell wrappers under the offscreen Qt
backend, on each selected distribution. These programs may ignore `--help` and
remain in their GUI event loop. Forge observes their startup for five seconds,
fails a crash, OOM, missing shared library or Qt platform error, and terminates
still-running GUI containers after the deadline. A still-running app is a
startup-liveness check, not proof of interactive rendering. The command-line
smoke deadline is 30 seconds and timeouts fail.
