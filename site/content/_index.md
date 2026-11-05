+++
title = "OpenMW Forge"
template = "index.html"
+++

A standalone Jess-compiled build system for producing portable OpenMW Linux archives with AlmaLinux 9, vcpkg, Qt, ABI verification, and distributable debug symbols.

Build a checked-out source tree or target a remote fork and branch directly. The two CI workflows are deliberately independent: one qualifies Forge itself; the other rebuilds the configured OpenMW revision every four hours and updates `das-uberbranch` only after release checks succeed.
