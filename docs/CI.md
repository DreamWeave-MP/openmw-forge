---
layout: default
---

# CI and documentation infrastructure

Forge uses **ordinary GitHub-hosted Ubuntu 24.04 x86-64 runners**. There are no
self-hosted runners, larger-runner subscriptions, or bespoke server requirements.
Docker builds the AlmaLinux 9 payload inside the hosted Ubuntu environment.
The workflows borrow StroggForge's staged quality/release model, while keeping
Forge's Jess-native build pipeline separate from StroggForge's Cargo workflows.

## Workflows and permissions

| Workflow | Trigger | What it does |
|---|---|---|
| `forge-ci.yml` | Every push/PR/manual | Jess strict/style and source/JPK tests, standalone ELF compilation and integration fixtures |
| `forge-ci.yml` docs | After validation | Jess generates documentation pages, Zola builds the site; deploy on default branch |
| `forge-toolchain.yml` | Builder recipe change / manual | Publish content-tagged AlmaLinux 9 toolchain image to GHCR on the normal hosted runner |
| `das-uberbranch.yml` | `23 */4 * * *` UTC/manual | AlmaLinux 9 dependency/OpenMW build, GoogleTests, packaging, ABI and distro-launcher smoke tests |
| `das-uberbranch.yml` publish | Successful scheduled build only | Recheck transferred SHA-256 and source provenance; publish rolling prerelease |

Every checkout uses `actions/checkout@v7` with `persist-credentials: false`.
The normal build has `contents: read` permissions. Only the isolated release
publisher receives `contents: write`; the separate toolchain publisher receives
`packages: write` for its own GHCR image. The scheduled builder needs only
`packages: read` for its prequalified toolchain. Only the Pages deployment job receives
`pages: write` and `id-token: write`. This matters when the configured source
becomes someone else's fork: its CMake scripts can execute arbitrary processes.
Never expose a release-capable token inside that build container.

## Docs: same generator as StroggForge

StroggForge's War Room is built with **Zola**. Forge uses the same generator,
currently pinned at `0.23.6`, rather than GitHub's Jekyll builder. It does not
vendor StroggForge's GPL-licensed theme or pretend the Rust/Cargo workflow
supports Jess. Forge carries its own small, responsive Zola templates and
uses the Jess generator `tools/docs.jsl` to turn the canonical Markdown in
`docs/` into pages under `site/content/manual/`.

To preview locally from a source checkout with Jess and Zola installed:

```sh
jess run --trusted --package . tools/docs.jsl
zola --root site serve
```

For a production build:

```sh
jess run --trusted --package . tools/docs.jsl
zola --root site build --output-dir ../public
```

GitHub Pages: Settings → Pages → Build and deployment → **GitHub Actions**.
Documentation builds on pull requests too, but only the default branch deploys.
The generated pages and `public/` are ignored; edit Markdown sources in `docs/`,
not generated files. No npm, Node, Rust or remote hosted service is needed to
render this documentation site locally.

## Jess installation

`.github/actions/setup-jess` downloads the public Jess Linux x64 release.
Set the repository variable `JESS_RELEASE_TAG` to the tested release tag to
avoid automatically picking up a newer Jess version. The executable built by
CI embeds Jess and can be downloaded from the workflow artifacts.

## Hosted image and SDK cache lifecycle

The toolchain is built from **`vendor/builder/Dockerfile`**. A separate
workflow publishes its image to `ghcr.io/<owner>/<repo>-builder` when that
recipe changes on the default branch, or when manually requested. This uses
ordinary `ubuntu-24.04`; no private machine, privileged runner registration,
or dedicated hardware is needed. In Settings → Actions enable normal workflow
permissions; GHCR publication requires package-write permission only in the
publisher job. If the GHCR package is private, GitHub's provided token must
have read access in the scheduled job.

On every four-hour release run, `tools/toolchain_image.jsl` computes the recipe
identity, tries to pull the corresponding image, and exports its immutable OCI
digest into the build environment. If the image has not been published yet,
Forge explicitly falls back to the full local container-image build. **The
first production run may therefore be much slower**. To avoid this, run the
`Forge AlmaLinux 9 toolchain image` workflow first, then manually dispatch
`OpenMW das-uberbranch`.

The scheduled workflow restores three bounded caches using **`actions/cache@v6`**:
qualified SDK export, `ccache`, and vcpkg binary packages (only if the SDK
misses). It separately restores Qt 6.6.3. The Jess worker verifies a restored
SDK's input fingerprint, archive SHA-256 and archive members before skipping
vcpkg. The original source/ref, OpenMW GoogleTests, final tarball, ABI, and
launcher/distro smoke gates **always** execute.

To preserve disk on the standard hosted runner, the dependency stage saves
its qualified SDK (and any rebuilt binary packages) **before** the OpenMW
stage. Then a CI-only Jess cleanup removes temporary vcpkg buildtrees and
binary packages, after verifying ownership of the vcpkg checkout. It never
removes outputs or OpenMW source. GitHub's runner disk budget is tight: keep
an eye on `df -h`, ccache statistics, and the release job duration.

The initial two-job parallelism is conservative. The four-hour builder has a
330-minute timeout, under the hosted six-hour job limit. **A complete cold
vcpkg/Qt/OpenMW production build has not yet been qualified on this budget.**
Caches are best-effort and may expire or be evicted; the build must still
succeed correctly on a miss. See [performance](PERFORMANCE.md),
[release readiness](RELEASE-READINESS.md), and
[troubleshooting](TROUBLESHOOTING.md).

GitHub schedules run from the default branch, may be delayed or dropped, and
cannot guarantee an exact four-hour publication interval. The concurrency
group prevents overlapping release publishers.
