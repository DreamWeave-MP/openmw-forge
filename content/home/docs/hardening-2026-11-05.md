+++
title = "Adversarial hardening"
weight = 90
description = "OpenMW Forge: Adversarial hardening"
+++


This pass responds to the adversarial audit of the `8dc8cc4` release tree. It
preserves the AlmaLinux 9 build baseline, OpenMW-specific CLI, GitHub-hosted
runner workflows, and four-hour `das-uberbranch` schedule. It does **not**
qualify an actual OpenMW build: real Docker/vcpkg/Qt/OpenMW validation must
occur on an appropriate Linux runner.

## Filesystem and worker safety

- `__build` and `__package` now pass the same canonical source/writable-root
  overlap checks as public commands, **before** worker invocation or staging.
  Unresolvable symlink ancestors are rejected.
- All write-side builds acquire kernel-owned locks derived from **canonical
  resource paths** under `$HOME/.cache/openmw-forge/locks`, not the invoking
  working directory. Different workspaces sharing an explicit build, dependency,
  or output directory now contend on the same key. Locks are acquired in sorted
  order and released on failure. These locks coordinate processes running under
  the same account and home; they are not a substitute for filesystem ownership
  when different Unix users share a path.
- The extracted vcpkg tree carries its own SHA-256 fingerprint of files,
  directories, and symlink targets. The source archive hash alone is no longer
  enough to reuse a modified installed tree. File hashing uses 64-file batches,
  not a new subprocess per library. A damaged or unreadable tree triggers
  re-extraction from the verified archive. A full hash costs I/O; benchmark it
  against extraction on the actual runner.
- The generated POSIX launchers follow *relative* symbolic links from the
  containing directory of each link. The compiled integration test launches
  from an unrelated working directory.

## Container identity and Qt

- Docker workers use the **actual invoking host UID:GID**, resolved by the
  executor, so files produced on writable bind mounts are not root-owned by
  default. The planner remains pure and uses a placeholder until execution.
  Podman workers request `--userns=keep-id`. Workers use a writable `/tmp` HOME.
  These semantics need a real hosted Docker exercise; synthetic command tests
  do not prove host filesystem permissions.
- Qt qualification now requires ELF-format shared libraries for Core, Gui,
  Widgets, Network, OpenGL, OpenGLWidgets, Svg, Qml, and Quick, matching CMake
  package configurations, plus the XCB platform plugin and LinguistTools.
  Cached installs missing a non-Core module fail qualification. This is a
  structural/ELF-header check, not a transitive runtime dependency audit.
- **Remaining Python limitation:** Qt acquisition currently invokes the
  pinned `aqtinstall` Python tool, now installed into the unprivileged user's
  environment rather than globally. Removing Python *from Forge-authored Qt
  acquisition* requires a manifest of official Qt SDK archives with verified
  SHA-256 digests, tested extraction/relocation semantics, and a real Qt build.
  Those verified hashes are not in this review environment; do **not** treat
  an unverified mirror download as a completed replacement. Upstream ports
  can separately require Python at compile time.

## CI and release publication

- CI requires an explicitly chosen `JESS_RELEASE_TAG` repository variable; a
  silent download of whichever Jess build is latest is no longer permitted.
  Pin the tested release before enabling workflows.
- The rolling release uploads package assets and source notes **before** the
  `SHA256SUMS` manifest. A completed checksum upload acts as the publication
  marker. **GitHub Release assets are not a multi-file transaction**: consumers
  must retrieve the manifest and verify every artifact before adoption, and a
  manifest failure leaves the publisher unsuccessful without pruning old files.

## Verification, and what is not proved

The Jess package checker, style checker, source/JPK tests, packed Linux ELF
integration suite, and embedded-asset parity gate should all pass in CI. The
integration suite includes symlink aliases, shared-resource locking, corrupted
SDK libraries, missing Qt components, release-completion marker failure, and
relative wrapper symlinks. It uses synthetic fixtures and a fake container
engine, so it **does not** establish that a real OpenMW binary builds or starts.

Before promoting `das-uberbranch` to a production-qualified release, run one
cold and one warm build in GitHub-hosted AlmaLinux 9 Docker, inspect UID/GID
ownership after dependency generation, validate a real Qt install, verify the
complete ELF/Qt plugin closure and launcher smoke in clean distros, and obtain
build duration and peak disk/memory measurements. Keep the `--run-tests` gate.
