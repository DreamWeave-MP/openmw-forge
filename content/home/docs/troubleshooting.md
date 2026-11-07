+++
title = "Troubleshooting"
weight = 80
description = "OpenMW Forge: Troubleshooting"
+++


## The four-hour job did not run

Scheduled workflows execute only from the repository default branch. Check
that the file has been merged, Actions is enabled, and the schedule is not
disabled after inactivity. GitHub can delay or omit an individual tick. Trigger
`workflow_dispatch` manually to isolate CI configuration from scheduling.

## Builder image fails with `curl-minimal` / `curl` DNF conflict

AlmaLinux 9 includes `curl-minimal`, which supplies the `curl` executable
used by Forge. Installing the separate full `curl` RPM alongside it fails DNF
transaction resolution. The builder Dockerfile and local system-package
provisioning intentionally request **`curl-minimal`**, not `curl`. Do not
work around this with `--skip-broken` or `--allowerasing`.

After updating the builder recipe, rerun the **Forge AlmaLinux 9 toolchain
image** workflow (`gh workflow run forge-toolchain.yml --ref main`). Its image
tag is derived from the Dockerfile checksum, so changing the recipe produces
a different image identity. A successful image publication alone does not
qualify a complete OpenMW release; run the separate release workflow next.

## Standalone compilation reports `failed to read 'jess'`

`jess` on `PATH` is sufficient to **run** the CLI, but `jess workspace pack
--runtime` requires an actual executable file path. Forge's setup action
exports `JESS_BIN` as an absolute path for later CI steps, and its release
script resolves the executable from `PATH` if that variable is absent.
If invoking the script by hand, use `JESS_BIN=/absolute/path/to/jess`.
Do not pass the bare string `jess` to the packer's `--runtime` option.

## Jess CI reports `jess.lock is out of date` or missing DreamWeave site packages

Forge itself does not depend on the six packages required by the documentation
site. The root `jess-workspace.toml` and `jess.lock` belong to the **Jess-native
StroggForge site job**, not the Forge executable. Run `jess package test .`
for application tests; use `tools/release.jsl` to compile the ELF. It creates an
isolated package workspace and checks the source digest before packing. Do not
add site dependencies to Forge's `jess.toml` or disable lock validation to
silence this error. Use `jess workspace sync --locked` only when preparing to
run the site generator with its compatible Jess runtime.

## Docker or AlmaLinux cannot start

The workflow requires only a standard GitHub-hosted `ubuntu-24.04` runner,
which includes Docker. Locally use `forge doctor --engine docker`; use
`--engine podman` if that is your installed container runtime. AlmaLinux 9
remains the **build ABI** even when the outer host is Ubuntu.

## vcpkg or CMake ran out of disk/memory

Read `df -h` printed by CI, the `OpenMW CMake parallelism` line, and
OOM-killer messages. With `jobs = 'auto'`, Forge uses all CPUs visible to the
AlmaLinux container. If peak compiler memory exhausts the runner, set
`jobs = 2` or `jobs = 1` in `ci/uberbranch-config.jsl` to reduce parallelism. Cache the **verified exported SDK** and compiler/vcpkg binary caches,
not every `buildtrees` directory or the mutable installed tree. The scheduled
job saves the SDK before OpenMW compilation, then safely reclaims vcpkg
checkout/buildtrees. Clean unqualified stale artifacts before reuse.
The default hosted runner has finite resources and the full build has not yet
been qualified there; do not silently change to self-hosted machines.

## GHCR toolchain image is unavailable

The scheduled job attempts the digest-pinned image computed from
`vendor/builder/Dockerfile` and falls back to building the same recipe on
GitHub-hosted Ubuntu. Publish the separate `Forge AlmaLinux 9 toolchain image`
workflow from the default branch to avoid repeated DNF/Autoconf work. A fresh
fork may initially lack GHCR package read permission; check the toolchain
resolver output and GHCR package visibility. Release verification never skips
just because the fast image is missing.

## The qualified SDK cache is rejected

Forge checks the builder identity, triplet, vcpkg revision, overlay file
hashes, archive SHA-256, and safe archive members before reuse. A bad cache
is a rebuild, not a green cache hit. GitHub cache entries cannot be rewritten
under the same key, so invalidate the key or allow the stale entry to expire
if the same corrupted entry keeps returning.

## SDK export fails with `uninspectable dependency symlink`

Native `.7z` archives normally store a POSIX symbolic link's target as the
entry's compressed data, **not** as a `Symbolic Link` field in `7z l -slt`.
Older Forge releases rejected these ordinary entries while validating a
successfully exported SDK (for example, `debug/lib/libexpat.so`). That did
not establish that the archive or the compiled libraries were malformed.

Forge now validates the cached archive's metadata and link sizes **before**
any extraction. It rejects duplicate paths, path traversal, hard links, and
any archived path that would write beneath an archived symlink. A single full
7z extraction into a fresh Forge-owned staging tree is followed by checks of
every actual symlink target against the archive metadata, including target
length and tree containment, before the SDK is published or used. This avoids
one separate solid-archive decompression per link.

7-Zip 26.04's default security policy rejects normal versioned ELF link chains
(`libfoo.so` -> `libfoo.so.1` -> real library) and parent-relative systemd
socket links with `Dangerous link via another link was ignored`. Forge uses
**`-snld10`**, which permits these in-tree links while preserving 7-Zip's path
checks. Do **not** replace it with `-snld20`: that bypasses all 7-Zip symlink
safety, and Forge's post-extraction checks are no substitute for safe writes
during extraction. Keep the metadata preflight and isolated staging mandatory.

If the export step has already run, preserve the vcpkg binary cache; the
150-package dependency compilation did not fail. On a runner with restored
binary-cache entries, rerunning the updated build should be able to reuse
matching ABI packages rather than rebuilding every dependency. A qualified
SDK cache hit is not guaranteed until the export passes verification.

## `ccache` shows zero hits

A cold build has no hits; inspect the cache statistics after a *second* build.
Older workflows used an automatic post-job cache save, which skipped saving
on packaging or GUI smoke failures even after a complete OpenMW compile.
Current CI uses explicit restore/save actions and preserves the 2 GiB ccache
snapshot after the attempted build, including failed smoke tests. Confirm `work/cache/ccache` is present in the container mount plan (try
`forge pipeline ... --dry-run`) and that CI restored the compiler cache after
checkout. `--no-ccache` intentionally disables it. A changed compiler or
build flags can invalidate cached objects.

## A cached Qt installation is rejected

Forge checks OpenMW-required Qt 6 ELF libraries, CMake targets (including
LinguistTools), and the XCB platform plugin,
not just an existing `QT/<version>/gcc_64` directory. A Forge-managed Qt cache
also carries a versioned installer identity, so changing the Qt or pinned AQT
version invalidates it. An incomplete **unowned** Qt directory is never
overwritten: inspect it and move it aside yourself. A managed Qt installation
is prepared in a separate staging tree and can be recovered from the previous
qualified version after an interrupted replacement.

The current package profile always requires Qt. The old `--no-qt` option was
removed because it could not produce the distribution promised by that flag.

## Another build or SDK verification is already in use

Forge takes kernel-owned advisory locks from canonical resource paths under
`$HOME/.cache/openmw-forge/locks` around managed source checkouts, build
and dependency directories, final output directories, SDK export/verification,
and shared smoke-test scratch paths. It fails rather than running two writers
through the same mutable checkout or packaging workspace. Wait until the other
invocation exits or use independent work roots; **do not delete lock files to
force concurrent execution**. A crashed process releases its kernel locks.

## Packaging or publication was interrupted

If every CMake build step and both OpenMW GoogleTest suites pass but the
package smoke step reports `smoke bsatool.x86_64 exited with 1:`, the binary
may be healthy. `bsatool`, `esmtool`, and `niftest` deliberately return status
**1** for `--help` while printing their usage to stdout. Forge checks the
specific tool's help banner and only accepts that documented nonzero status;
an arbitrary exit 1, missing library, or broken launcher remains a failure.
The same contract applies to distro-container smoke tests. Keep this test in
Jess, rather than patching upstream OpenMW's command-line behavior.

Main and debug archives are **compressed before either previous archive is
replaced**. A main-only (Debug) build is rejected if it would leave an old
matching `-debug.tar.gz` beside the new archive. A local managed recovery journal records the files that must be
restored if the process dies during publication. A subsequent Forge package
invocation recovers the previous complete archive set before publishing a new
one. Do not manually remove `artifacts/openmw/.forge-archive-publication` while
recovering a failed release; preserve the journal and any backup files.

GitHub Releases are different: the remote API uploads independent assets and
cannot promise an atomic view of the main/debug pair. The release publisher
validates hashes and provenance. Downstream consumers should verify both
artifacts and the manifest before adopting a rolling `das-uberbranch` release.

## Forge refuses `--clean`

Forge will not erase an unowned build or scratch directory. Keep your source
checkout outside generated work roots. Move or rename old unmarked outputs
manually after inspection, then let Forge create a new managed directory.

## The release job fails publication

Look for the SHA-256/provenance validation errors before investigating token
permissions. The build job needs only `contents: read`; the separate publish
job needs `contents: write` and a `GITHUB_TOKEN` able to create and update
GitHub releases. A failed qualification must leave the release unmodified.

## Documentation site build fails

Forge uses the DreamWeave Mod Template's **Jess site renderer**, via StroggForge
`modGlobalBuild.yml@v69`. No Zola installation is needed. Reproduce the site
check, render, and link audit with the commands in [CI](@/home/docs/ci.md).
Canonical Markdown is in `content/home/docs/`, and compiled output is in
`public/`. Keep those outputs untracked.

## Docker created root-owned build/cache paths

New Docker worker invocations supply `--user <host UID>:<host GID>` and
`HOME=/tmp`; Podman uses `--userns=keep-id`. These are recorded in the dry-run
plan (the host identity placeholder is resolved at execution). If an existing
workspace has **legacy** root-owned files, move/repair it explicitly rather
than using an uncontained recursive `sudo rm -rf`. A proper hosted runner
should test the actual permissions before its vcpkg cleanup stage.

## vcpkg cannot detect the compiler during SDK preparation

Check the **first** `vcpkg install` failure, not the later OpenMW build step.
Forge's dependency manifest and overlays are copied into the AlmaLinux 9
image under `/forge/work/forge-assets/deps/`. Container workers run as the
unprivileged GitHub runner user, so that image-owned directory is **read-only**.
Without an explicit installation root, vcpkg manifest mode attempts to write
`vcpkg_installed` next to the embedded manifest and may fail during the CMake
compiler-identification probe.

Forge sets `--x-install-root=/forge/work/vcpkg/installed` for **both** vcpkg
install and export, keeping package metadata under the writable, host-mounted
checkout. A failure also prints the compiler probe's CMake error/output logs
before Docker removes the worker. Check those logs for a true compiler, linker,
permission, or toolchain mismatch; an outer `unable to detect compiler` error
alone is insufficient to identify the cause. This change does not qualify the
full vcpkg/OpenMW production pipeline without a real hosted build.


## `libsystemd` fails installing Jinja2 inside vcpkg

The AlmaLinux 9 dependency build uses a third-party vcpkg port that creates its
own isolated Python virtual environment. Installing Jinja2 globally on the
runner does **not** make it available inside that environment. This is upstream
Meson/vcpkg build tooling; Forge's orchestration remains Jess-native.

Forge prepares a local wheelhouse with **Jinja2 3.1.6** and **MarkupSafe 2.1.5**,
verifies each downloaded wheel against its pinned PyPI SHA-256, and tests
installation inside an isolated virtual environment **before** starting the
expensive vcpkg build. The wheels are cached within Forge's vcpkg checkout.
Its `PIP_FIND_LINKS` and `PIP_CONSTRAINT` environment settings expose that
verified wheelhouse to vcpkg's subsequent virtualenvs without forcing other
ports to build offline.

The Docker/Podman worker must **not** set `PIP_USER=1` globally. That setting
forces a user-site installation even inside vcpkg's isolated virtualenvs and
causes `Can not perform a '--user' install` errors. Forge supplies `PIP_USER=0`
for vcpkg's Python environment, including the early preflight, so an inherited
user-install default cannot override the virtualenv's site-packages. The Qt
installer explicitly passes `--user` for its separate installer step.

If this preflight fails, inspect the pip stdout/stderr printed directly by
Forge; do not bypass TLS checks or install Python packages globally. If a
later vcpkg port fails, download the `forge-vcpkg-failure-*` workflow artifact
and inspect the port's `*-err.log`. The workflow also attempts to save partial
vcpkg binary-cache results on failure, so a retry can reuse completed ports.
A successful isolated-venv preflight is **not** proof that every third-party
Python port will succeed; it validates the specific Jinja2 failure encountered
in the initial OpenMW dependency build.

The package version and checksum contract intentionally targets the pinned
AlmaLinux 9 x86-64 builder with Python 3.9. Update the wheel set and rerun
regression checks before changing the builder's Python ABI.

## ABI audit fails after a long SDK export (`GLIBC_2.35` on AlmaLinux 9)

AlmaLinux 9.7 backported selected `GLIBC_2.35` symbols while continuing to
identify its glibc as 2.34. Builds using a floating `almalinux:9` image can
therefore produce libraries that cannot load on older EL9 systems. In the
November 5 incident a restored 150-package SDK took almost 32 minutes to fail
because the ABI audit ran *after* compressed-archive symlink validation; the
first mismatch was `debug/lib/libsystemd.so.0.40.0`.

Forge.s toolchain builder now starts from the dated official 9.5 base image
(`9.5-20250519`), uses frozen AlmaLinux 9.5 BaseOS/AppStream/CRB/Extras
repositories, and fails its image build if glibc exports the specific seven
RHEL 9.7 function backports at `GLIBC_2.35`. It installs only binutils first
so this check runs **before** the expensive C++ packages, then repeats after
DNF finishes. The failed November 5 AlmaLinux 9.5 image build exposed a bug
in Forge.s first preflight: it scanned `readelf --version-info` for any
`GLIBC_2.35` *version node*. Earlier EL9 glibc packages already carry such
nodes, without necessarily exporting the later ABI-breaking functions. The
corrected preflight uses `nm -D --defined-only` to check versioned **exports**
by name; failure logs the specific symbols and glibc RPM versions. The final
SDK/release scans remain the authoritative strict gate and reject **every**
imported version above the configured ceilings, including unknown functions.
This is a build
compatibility baseline; the final release smoke still tests current targets.
The frozen historical build image is not a substitute for an up-to-date
runtime image or receiving current security fixes.

**After changing this builder recipe, publish the separate**
`forge-toolchain.yml` **image before retrying** `das-uberbranch.yml`. The
new image identity intentionally invalidates previous SDK/binary cache keys;
Forge also separates local vcpkg packages by the ABI baseline so it cannot
silently reuse old-ABI outputs. A cold dependency rebuild may be necessary.

The ABI audit now runs on the *installed tree before* creating the large 7z
export. Freshly exported archives compare metadata against the locally audited
symlink targets without reopening the solid archive for every link. **Restored
or external archives remain untrusted**: Forge verifies the archive digest
and metadata first, performs a single isolated extraction, then checks the
actual extracted links before using or publishing the SDK. This avoids the
former several-hundred-process decompression loop without weakening the ABI
audit or allowing unvalidated archive members to escape staging.

### Missing `libgssapi_krb5.so.2` or other `.so` in smoke containers

OpenMW-CS may load QtNetwork, which transitively requires Kerberos GSSAPI.
The Ubuntu/Debian image recipes install `libgssapi-krb5-2`; Fedora/AlmaLinux
use `krb5-libs`, while other distro profiles use `krb5` (Arch/openSUSE) or `mit-krb5-libs` (Void). Do not bundle the
builder's system Kerberos libraries to conceal missing target-runtime dependencies.

### Optional Qt SDK plugins versus supported OpenMW runtime plugins

The aqt Qt SDK contains drivers for third-party databases (Mimer SQL,
MySQL, PostgreSQL, ODBC), GTK desktop theme integration, and CUPS printing.
These are **not OpenMW runtime requirements**. Forge now stages only supported
runtime plugin families and the local SQLite driver, not the entire Qt SDK
plugin directory. This avoids advertising broken features or forcing every
portable OpenMW build to install unrelated client libraries.

Native Wayland support **is retained**, including the Wayland Qt platform and
its graphics integration plugins. The smoke containers therefore provide
`libwayland-cursor.so.0` and `libwayland-egl.so.1` as system dependencies:
`libwayland-cursor`/`libwayland-egl` on AlmaLinux and Fedora;
`libwayland-cursor0`/`libwayland-egl1` on Debian/Ubuntu; and the corresponding
Wayland runtime on other selected distributions. The release still checks
*every ELF that ships*, and both raw GUI executables and wrappers still start
under a bounded timeout. This is a deliberate package-content policy, not a
blanket exception to dependency checks.

Closure failures are grouped by distribution and missing SONAME with a sample
consumer path; symbol-version and other loader errors remain visible. To
investigate new failures without recompiling OpenMW, run `forge smoke` against
an already-built tarball in a container-enabled environment.

The distro smoke gate now performs a full ELF dependency-closure check before
launching any executable. It checks the packaged Qt plugin tree as well as
binaries, using each target distro's loader environment, and reports *all*
unresolved SONAMEs or symbol-version problems together. Fix missing system
runtime packages in the corresponding smoke image; keep actual bounded GUI
startup checks in place to catch non-linker failures. An existing packaged
tarball can be rechecked with `forge smoke --archive ... --distros ... --with-qt`.

### Cross-distro smoke appears stuck on the first GUI tool

A legacy Forge smoke implementation ran `openmw-launcher --help` synchronously
without a timeout. The Qt launcher can enter an event loop instead of exiting.
The bounded smoke path now starts distro containers detached, checks their
state, collects logs, and removes them after at most a five-second GUI startup
window (plus container overhead). The CLI help deadline is 30 seconds. Fatal
linker or Qt diagnostics remain failures, and long-running GUI startup is
reported only as a liveness check. If a build predates this change, cancel the
hung GitHub Actions run; the patch applies to subsequent runs only.
