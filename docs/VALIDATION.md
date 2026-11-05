# Verification of the standalone Jess-native OpenMW Forge

## Performed with the supplied Jess 0.3 / Luau 0.745 runtime

- `jess package check .`: strict type checking of package sources.
- `jess check --package . tools/*.jsl src/*.jsl tests/run.jsl`: typed checker including scripts.
- `jess workspace test`: **36 tests in source + 36 tests in packed JPK = 72 passing executions**.
- `jess run --trusted tools/style.jsl`: Jess style checker clean.
- `jess workspace pack --runtime /path/to/jess --output /path/to/openmw-forge`: produced a real Linux x86-64 ELF executable with an embedded Jess runtime.
- `JESS_BIN=/path/to/jess jess run --trusted --package . tools/integration.jsl /path/to/openmw-forge`: compiled ELF tests from a checkout-free working directory. These cover generated assets, mock Podman build/run using an **independently packed Jess mock executable**, error propagation, staging of OpenMW+Qt+vcpkg symlinks and packaging templates, and synthetic `.tar.gz` safety scenarios.
- `tools/validate.jsl` (Jess shebang) runs these checks together and fails closed on any error.

The final executable has no dependency on a checked-out Jess workspace. Its runtime and overlay assets are embedded, and the generated Podman/Docker image carries the executable itself.

## What has **not** been proven

No Podman/Docker engine is available in the sandbox. We therefore did not compile the entire pinned vcpkg graph, install Qt from the network, compile a real OpenMW tree, test real debug symbol sidecars, or run the distro image matrix. Our staging fixture uses stub binaries; it is **not** a real OpenMW distribution.

Known release risks: mutable container tags, externally downloaded Qt and package archives without pinned hashes, vcpkg export publication not fully transactional, dependency availability in AlmaLinux 9 EPEL/CRB, OpenMW CMake project evolution and real plugin/runtime-library coverage.

Before a production release: `./openmw-forge-linux-x64 doctor`; then run `pipeline --source ... --run-tests` with no compatibility opt-outs on a container-capable host; inspect ELF requirements, debug sidecars and final packages; run `smoke --archive ... --distros almalinux-9,debian-12,ubuntu-24.04`; compare outputs of a second incremental build and retain the build logs.
