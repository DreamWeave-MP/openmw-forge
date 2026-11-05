+++
title = "OpenMW Forge"
description = "Fast, repeatable Linux builds and qualified releases for any OpenMW branch or fork."
date = 2026-11-05

[taxonomies]
tags = ["OpenMW", "Jess", "Build Systems"]

[extra]
sections = ["overview", "credits"]
+++

OpenMW Forge is a self-contained Jess executable that builds and packages OpenMW with a pinned AlmaLinux 9 dependency toolchain, vcpkg, Qt, ccache, and CI-based release verification.

<!-- more -->

[Get started with Forge](docs/) or browse the [CLI reference](docs/cli/).

The independent `das-uberbranch` workflow builds the configured OpenMW fork and branch every four hours and publishes only qualified Linux releases.
