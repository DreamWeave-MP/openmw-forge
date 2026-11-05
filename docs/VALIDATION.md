# Validation report

## Executed in the supplied sandbox

- `jess package check .`: strict Luau type check clean (with the supplied Jess 0.3.0 / Luau 0.745 runtime).
- `jess workspace test`: **41 assertions/tests registered, 82 executions passed**, with source and packed-JPK providers.
- `jess run --trusted tools/style.jsl`: Jess's built-in style checker passed, including strict `src/` rules and no `any` casts.
- `bash -n`: all imported shell workers parsed successfully.
- `tests/integration.sh`: 9 mocked end-to-end CLI scenarios passed. These launch the *real Jess command* and use a fake `podman` binary to validate the actual process invocation sequence, options, fail-fast behavior and filesystem checks.
- `tests/archive_safety.sh`: 4 synthetic tarball scenarios passed: valid non-GUI package, `../` traversal, absolute member, and escaping symlink. The real `smoke` CLI and original tarball verifier are exercised.

The Jess tests cover valid/invalid options, canonical Alma 9 defaults, triplet/Qt override forwarding, source/write-root overlap rejection, symbolic command arguments, package-only assembly, direct/distrobox/local runner choices, build-test filter controls, no-prepare caching, HTTPS archive URL requirements, staged packaging, single/multi-distro smoke selection, no side effects in plans and validation command safety.

## Not executed here

- Full Podman/Docker build images with DNF and EPEL packages.
- vcpkg network clone and full compiled dependency graph.
- Real Qt installation and CMake OpenMW binaries.
- Real split-debug and ABI scans of newly produced OpenMW ELF binaries.
- GUI smoke tests, distrobox matrix, or actual Linux distro portability.

**There are no fabricated benchmarks or claims of a successful production build.** The tests validate the control plane and retained archive safety behavior. An AlmaLinux 9 build host is required to determine whether the concrete OpenMW revision, vcpkg pin, Qt version, and GCC toolset work together end to end.
