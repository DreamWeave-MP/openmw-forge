+++
title = "Documentation"
weight = 1
sort_by = "weight"
template = "docs/section.html"
page_template = "docs/page.html"

[extra]
api_docs = true
docs_root = true
docs_project_name = "OpenMW Forge"
docs_short_title = "Forge Docs"
docs_project_path = "@/home/docs/_index.md"
docs_repository_url = "https://github.com/DreamWeave-MP/openmw-forge/tree/main/content/home/docs"
docs_sidebar_label = "Documentation"
+++


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

- [CLI usage and examples](@/home/docs/cli.md)
- [CI and StroggForge integration](@/home/docs/ci.md)
- [Four-hour das-uberbranch release](@/home/docs/release.md)
- [Release-readiness limits](@/home/docs/release-readiness.md)
- [Validation gates](@/home/docs/validation.md)
- [Migration audit](@/home/docs/audit.md)
- [Performance and cache design](@/home/docs/performance.md)
- [Troubleshooting](@/home/docs/troubleshooting.md)

The built release is a portable OpenMW tarball, *not* a container image. A
passing synthetic integration fixture does not prove that a production OpenMW
source branch compiles: that must be qualified by the scheduled real build.
