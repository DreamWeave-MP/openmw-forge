---
layout: default
---

# Verification of the standalone Jess-native OpenMW Forge

## Performed with the supplied Jess 0.3 / Luau 0.745 runtime

- `jess package check .`: strict type checking of package sources.
- `jess check --package . tools/*.jsl src/*.jsl tests/run.jsl`: typed checker including scripts.
- `jess workspace test`: **54 tests in source + 54 tests in packed JPK = 108 passing executions**.
- `jess run --trusted tools/style.jsl`: Jess style checker clean.
- `jess workspace pack --runtime /path/to/jess --output /path/to/openmw-forge`: produced a real Linux x86-64 ELF executable with an embedded Jess runtime.
- `JESS_BIN=/path/to/jess jess run --trusted --package . tools/integration.jsl /path/to/openmw-forge`: compiled ELF tests from a checkout-free working directory. These cover generated assets, mock Podman build/run using an **independently packed Jess mock executable**, error propagation, staging of OpenMW+Qt+vcpkg symlinks and packaging templates, and synthetic `.tar.gz` safety scenarios. The expanded suite also covers real
  offline Git fork/branch switching (using Git URL rewriting to a disposable
  local repository), dirty checkout preservation, source provenance in a staged
  release, refused destructive `--clean` on unowned roots, refused unowned staging
  and smoke scratch paths, missing-main-binary smoke failures, and atomic
  archive replacement under a deliberately failing mocked `tar` executable.
  **101 integration assertions pass** through the compiled ELF. The new
  checks explicitly reject broken packaged launchers, test source/ref selection,
  verify content-derived builder image caching, and simulate publisher first
  creation, rolling asset pruning and checksum/provenance failures.
- `tools/validate.jsl` (Jess shebang) runs these checks together and fails closed on any error.
- The current revision also exercises persistent ccache Docker mounts, disabled-cache plans, rollback/recovery of a managed dependency tree, and rejected user-owned destinations. The latest integrated fixtures additionally verify a real synthetic `.tar.xz` dependency SDK extraction and unchanged-input reuse, a corrupted/invalid SDK metadata cache, prepublished OCI toolchain consumption, and safe CI-only cleanup. A second toolchain GHCR workflow is defined but has not run in GitHub during sandbox development.
- The hosted-workflow YAML is structurally validated and all six jobs use `ubuntu-24.04`. Jess generates nine canonical-documentation pages for Zola. The site templates parse as Jinja-compatible templates, but Zola itself is **not available in this sandbox**, so this is not a successful site-render claim.

The final executable has no dependency on a checked-out Jess workspace. Its runtime and overlay assets are embedded, and the generated Podman/Docker image carries the executable itself.

## What has **not** been proven

No Podman/Docker engine or Zola executable is available in the sandbox. We therefore did not compile the entire pinned vcpkg graph, install Qt from the network, compile a real OpenMW tree, test real debug symbol sidecars, or run the distro image matrix. Our staging fixture uses stub binaries; it is **not** a real OpenMW distribution.

Known release risks: mutable AlmaLinux and distro image tags on first publication (the consumer pins GHCR digests); Qt installer
  downloads that are not content-pinned; the multi-file dependency export
  (metadata plus archive) not being one atomic transaction; compatibility with
  actual vcpkg 7z link metadata; AlmaLinux 9 EPEL/CRB package availability;
  OpenMW CMake evolution; and real runtime plugin/library closure. HTTPS
  dependency archives are now SHA-256-required and the vcpkg source revision
  remains pinned.

Before a production release: `./openmw-forge-linux-x64 doctor`; then run `pipeline --source ... --run-tests` with no compatibility opt-outs on a container-capable host; inspect ELF requirements, debug sidecars and final packages; run `smoke --archive ... --distros almalinux-9,debian-12,ubuntu-24.04`; compare outputs of a second incremental build and retain the build logs.
