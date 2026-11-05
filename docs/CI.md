---
layout: default
---

# StroggForge conventions and CI

Forge follows DreamWeave/StroggForge's **GitHub Actions workflow**, release
asset and GitHub Pages conventions, but uses a **Jess-native build lane**.
Do **not** point this repository at StroggForge's `rustGlobalBuild.yml`: that
workflow requires Cargo binaries, not Jess `.jsl` command packages.

## Workflows

| Path | Trigger | Responsibility |
|---|---|---|
| `.github/workflows/forge-ci.yml` | Push, PR, manual | Jess strict/style, source+JPK tests, standalone ELF integration; publish Pages docs on the default branch |
| `.github/workflows/das-uberbranch.yml` | `23 */4 * * *` UTC, manual | Build configured OpenMW ref on a dedicated runner, smoke-test main + debug artifacts, publish prerelease assets |

Both install Jess through `.github/actions/setup-jess`, a minimal composite
bootstrap from the public `DreamWeave-MP/jess` release. The `JESS_RELEASE_TAG`
repository variable optionally pins a specific Jess release; without it, the
latest available release is selected. For release reproducibility, pin it.

The documentation site uses GitHub Pages' Jekyll builder and standard Pages
upload/deploy actions, publishing the files under `docs/`. In repository
Settings → Pages, select **GitHub Actions** as the build source. Pages needs
`pages: write` and `id-token: write` permissions, already scoped to its job.

## Dedicated scheduled runner

Register a self-hosted Linux x86-64 runner with the `openmw-build` label,
Docker daemon access, Git, `gh`, `unzip`, compiler toolchain utilities and
sufficient disk/RAM for the real vcpkg/Qt/OpenMW build (plan for tens of GB).
The workflow intentionally does **not** silently fall back to an undersized
GitHub-hosted VM. Configure `GH_TOKEN` via the workflow's built-in
`github.token` with repository `contents: write`; the workflow does not
require a personal access token. The heavy build job uses only `contents: read`;
a separate Ubuntu publisher job obtains `contents: write` **after** the
complete package has passed ABI, GoogleTest, launcher and distro checks. The
publisher verifies transferred SHA-256 hashes and the configured source/ref
before modifying the release. `gh release` targets the Forge repository.

Scheduled GitHub workflows run from the **default branch** and may be delayed
or skipped under load. The concurrency group prevents overlapping release
jobs, but GitHub may coalesce queued schedules if a build takes longer than
four hours. The schedule is a best-effort cadence, not an SLA.

CI has **not** been exercised on your actual GitHub runner from this sandbox;
validate the first manual dispatch and inspect its logs and published assets
before relying on periodic releases.
