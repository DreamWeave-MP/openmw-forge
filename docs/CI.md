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
| `das-uberbranch.yml` | `23 */4 * * *` UTC/manual | AlmaLinux 9 dependency/OpenMW build, GoogleTests, packaging, ABI and distro-launcher smoke tests |
| `das-uberbranch.yml` publish | Successful scheduled build only | Recheck transferred SHA-256 and source provenance; publish rolling prerelease |

Every checkout uses `actions/checkout@v7` with `persist-credentials: false`.
The normal build has `contents: read` permissions. Only the isolated release
publisher receives `contents: write`; only the Pages deployment job receives
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

## Ephemeral caches and runner resources

GitHub-hosted runners are discarded after each job. The scheduled workflow
restores the vcpkg **binary** cache and the OpenMW **ccache** directory using
`actions/cache@v4` after checkout. Forge mounts the same directories into
short-lived AlmaLinux containers. A dated cache key limits new snapshots to
roughly one per day per input set instead of six per day; cache eviction and
quotas still apply. The vcpkg working tree, installed artifacts and Docker
images are *not* automatically persistent between different GitHub-hosted
jobs, and a warm cache is never treated as verified source provenance.

The scheduled config uses `jobs = 2`, a conservative baseline for the smaller
standard GitHub-hosted runner. **A complete vcpkg/Qt/OpenMW build has not yet
been qualified on GitHub-hosted resource limits.** Monitor disk space, memory,
cache sizes and run duration on the first manual dispatch. The workflow has a
330-minute timeout, under GitHub's six-hour hosted-job limit. If a cold build
cannot fit, reduce working-set size or reuse verified dependency exports
before considering a larger runner. See [performance](PERFORMANCE.md) and
[troubleshooting](TROUBLESHOOTING.md).

Scheduled GitHub Actions run from the default branch, may be delayed, and may
not execute exactly on the four-hour boundary. A shared concurrency group
prevents overlapping releases.
