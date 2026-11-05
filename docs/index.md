---
layout: default
---

# OpenMW Forge

One standalone, Jess-compiled Linux command for reproducible OpenMW dependency
builds, compilation, packaging and verification. Targets **AlmaLinux 9**.

## Start here

1. Download the standalone Linux x86-64 ELF from the latest successful
   **Forge validation and documentation** workflow artifact, then `chmod +x forge`.
2. `./forge doctor --engine docker` checks container readiness.
3. `./forge pipeline --repo https://gitlab.com/OpenMW/openmw.git --ref master --engine docker --run-tests`
   builds the official `master` branch. Use `--dry-run` to inspect the plan first.
4. Find the main and debug `.tar.gz` archives under `artifacts/openmw/`.

**No Jess installation is required for running the compiled ELF.** Jess is
required only to build the Forge executable from source.

## Documentation

- [CLI usage and examples](CLI.md)
- [CI and StroggForge integration](CI.md)
- [Four-hour das-uberbranch release](RELEASE.md)
- [Release-readiness limits](RELEASE-READINESS.md)
- [Validation gates](VALIDATION.md)
- [Migration audit](AUDIT.md)

The built release is a portable OpenMW tarball, *not* a container image. A
passing synthetic integration fixture does not prove that a production OpenMW
source branch compiles: that must be qualified by the scheduled real build.
