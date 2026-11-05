# Migration audit: dependency builder + standalone OpenMW tarball builder

Scope: the supplied `dream-deps-build.bundle` HEAD `5981e98` and `openmw-linux-build.bundle` HEAD `88d88df`. The new workspace is an AlmaLinux 9 **Linux** build orchestrator; it is not a Windows/macOS CI rewrite.

## Dependency repository — source-file responsibility map

| File or directory | Original responsibility | Merged disposition |
|---|---|---|
| `build.conf` | Profile selectors, toolset/ABI ceilings, vcpkg git SHA pin | Retained; default set to `alma9`, GLIBC ceiling 2.34, CXXABI ceiling 1.3.13 |
| `Dockerfile` | Build context inside baseline Alma image, execute `build-all.sh` | Retained as dedicated deps image; default base moved to Alma 9 |
| `vcpkg.json` | Required packages and Linux/Windows/macOS feature selections | Retained byte-for-byte |
| `ports/openmw-osg/` | OSG overlay plus custom patches | Retained |
| `ports/openmw-mygui-osx/` | macOS MyGUI patch/port | Retained for data integrity; not executed by Linux target |
| `ports/unshield/` | Custom unshield vcpkg port | Retained |
| `triplets/` | Linux dynamic + macOS dynamic triplets | Retained |
| `scripts/lib/config.sh` | Dynamic environment/profile loading | Retained as worker-internal compatibility layer |
| `scripts/lib/fail.sh` | Bash trap and diagnostic utility | Retained |
| `scripts/doctor.sh` | Preflight host engine/network/permissions tests | Retained; optional 7zip installation is no longer mistakenly a fatal prerequisite |
| `scripts/install-system-deps.sh` | EPEL/CRB packages, GCC toolset, verified autoconf installation | Retained inside container |
| `scripts/setup-vcpkg.sh` | Clone/checkout pinned revision and bootstrap vcpkg | Retained inside container |
| `scripts/build-deps.sh` | vcpkg install overlay ports/triplets | Retained inside container |
| `scripts/build-all.sh` | System install, vcpkg install/export, metadata write, ABI verification | Retained as the container worker; invoked by Jess, not handwritten per-user CLI |
| `scripts/verify-build.sh` | Validate artifact/metadata, archive contents, call ABI checker | Retained |
| `scripts/verify-abi.sh` | Read ELF symbol-version floors with readelf | Retained |
| `scripts/cleanbuild.sh` | Distrobox or reusable container orchestration, deletes old export | **Compatibility only** for `--mode distrobox`; not the default Jessie container workflow |
| `.github/workflows/build.yaml`, `.github/actions/` | CI for Linux/macOS/Windows, artifact uploads, GPG/SSH manifest promotion | Not executed or migrated into the Linux CLI; original bundle is the archival source |
| `Store-Symbols.ps1` | Windows PDB/symbol-server repackage | Retained as historical Windows-related data, not a Linux command |

**Strengths:** pinned vcpkg revision, custom triplet/port overlays, checking ELF symbols after builds, metadata tying archives to a selected profile, verification after package export, separation of host/container responsibilities.

**Weaknesses:** two unrelated command parsing/configuration schemes; Alma 8 default inconsistent with Alma 9 tarball builder; stale and incompatible GLIBC/CXXABI ceilings; 7zip checked before installation; `cleanbuild.sh` removes existing exports up front; `vcpkg export` and metadata are not transactional across failures; old build tag references can silently be substituted when a download fails; substantial privileged bootstrap, and no content hash for downloaded prebuilt archive.

## OpenMW Linux repository — source-file responsibility map

| File or directory | Original responsibility | Merged disposition |
|---|---|---|
| `config/deps_versions.sh` | Qt version and legacy published dependency archive pointer | Retained for Qt defaults; strict Jess builds forbid legacy download fallback |
| `docker/Dockerfile.tarball` | Alma 9 build image and scripts | Retained and provisioned with packaging/ABI/debug tools for package-only runs |
| `scripts/prepare_deps.sh` | Install system packages/Qt, download and extract vcpkg archive | Retained; added `--require-archive` fail-closed switch for Jess invocations |
| `scripts/configure_openmw.sh` | Generate OpenMW CMake configuration against external vcpkg/Qt tree | Retained |
| `scripts/build_binaries.sh` | Prepare/configure/build, optional assembly | Retained; added both GoogleTest suites and forwarding of assembly validation and dependency strictness |
| `scripts/assemble_tarball.sh` | Stage binaries, copy vcpkg/Qt libs/assets, split symbols, audit, smoke test, make tarball | Retained; Qt-version override exposed |
| `scripts/split_debug.sh` | GNU objcopy/strip debug sidecar handling | Retained |
| `scripts/check_compat.sh` | GLIBC/GLIBCXX/CXXABI ceiling audit | Retained unchanged: canonical Alma 9 packaging contract |
| `scripts/run_container.sh` | Container image/mount orchestration and argument parsing | **Superseded by Jess**; retained only as a historical compatibility script |
| `scripts/run_distrobox.sh` | Distrobox creation/reuse and host mounts | Retained as optional Distrobox backend; now forwards test/strict flags |
| `scripts/build_local_staging.sh` | Developer convenience path `$HOME/GitHub/openmw`, destructive stage move | Not the default pipeline; preserved but **not** routed by the Jess CLI |
| `templates/runtime_wrapper.sh.in` | LD_LIBRARY_PATH and launcher wrapper behavior | Retained unchanged |
| `templates/README.packagecontents.txt` | In-package documentation | Retained unchanged |
| `tests/test_tarball.sh` | Validates package/executable layout, traversal/link safety, smoke binaries | Retained and exercised with synthetic fixtures |
| `tests/multi_distro_test.sh` | Distrobox smoke matrix | Retained; exposed via `smoke --distros` |
| `docs/` | Original status, coverage and supported distro notes | Retained under vendor for comparison |

**Strengths:** source/build/deps roots were already explicit; debug symbol sidecar support, compatibility symbol checks, tarball layout checks, comprehensive portability test script, optional staged-only build, and distrobox/container isolation.

**Weaknesses:** overlapping CLI parsing in `build_binaries.sh`, `run_container.sh`, and `run_distrobox.sh`; hardcoded local-source path in staging convenience script; shell commands mix environment setup and state-changing build stages; package-only containers formerly assumed previous setup had installed needed tools; unattended fallback to a historical dependency release; no single source of truth shared with dependency build metadata.

## New control plane

`src/args.jsl` parses strict CLI switches; `src/config.jsl` pins canonical Alma 9 defaults; `src/plan.jsl` generates the entire command vector and mounts without spawning anything; `src/execute.jsl` preflights files, resolves projected writable paths through symlinks, safely creates build roots, and executes commands sequentially with fail-fast results. `tools/forge.jsl` adapts Jess OS path APIs and routes the user's intent. `jess.toml` names the package, command target, API exports, tests, and required host capabilities.

The **unified contract** uses separate dependency-output, CMake-build, extracted-deps, and final-package roots. The Jess default container workflow invokes the Dockerfiles and build leaf scripts directly rather than nesting shell wrappers. `pipeline` guarantees that the package build consumes the archive the dependency stage created; a failed stage prevents all subsequent stages. `--dry-run` does not spawn processes or mutate paths.

No general-purpose shell evaluator was added. Paths and CMake arguments go to `@dream/process.run` as literal argv entries; the shell workers still use Bash internally for the jobs they already owned.

## Remaining concerns, not disguised as completed work

1. **Full build unverified.** A real AlmaLinux 9 vcpkg export, Qt install, OpenMW configure/compile, debug split, ABI audit and multi-distro smoke sweep is required for release confidence.
2. **Dependency supply chain.** The vcpkg git SHA is pinned, but the base image uses a mutable `almalinux:9` tag, Qt downloads are not content-addressed, and explicit prebuilt archive URLs lack hash verification. Pin images by digest and validate external archives before claiming strong reproducibility.
3. **No transactional artifact promotion.** A failed build can leave a partial export at the target filename. Use temporary outputs, verification, and atomic promotion in a future revision.
4. **Distrobox still delegates to original wrapper.** The primary container backend is directly planned by Jess; the Distrobox compatibility backend is not fully refactored yet.
5. **Binary packaging is still Bash.** The complex ELF/Qt/asset staging behavior was deliberately preserved because rewriting it without a true production fixture would trade functioning logic for untested code. A native-Jess staged-file packager is a future migration candidate once golden fixture tests exist.
6. **Windows/macOS CI out of scope.** The original dependency repository included cross-platform GitHub Actions and Windows symbol uploads. This workspace retains relevant port data but does not claim to replace those services.
7. **Host-side verify command.** `verify` invokes original scripts locally, so it needs `readelf` and a 7-Zip extractor on the host; `deps` verifies during its container build automatically.
8. **Workspace root required.** The Jess target uses the checked-out `vendor/` tree at the working directory. It is not yet a standalone packed `.jsw` that can spawn external files without the repository contents.

## Recommended real-host qualification

1. On an Alma 9 capable Podman/Docker host, run `doctor`, then `deps` and inspect the `.build-meta` file for `profile=alma9`, correct pin, nonempty `.7z`, and ABI ceilings.
2. Run `build --source /path/to/openmw --run-tests` with no validation opt-outs. Capture console logs and resulting `openmw-*-Linux-64Bit*.tar.gz` and debug sidecars.
3. Run `smoke --archive ... --distros almalinux-9,debian-12,ubuntu-22.04` (and optional GUI checks in a display-enabled environment).
4. Run a second incremental build and compare cache behavior, provenance and packaging repeatability.
