# Original dependency-build repository: retained inputs

This directory preserves the dependency builder's original vcpkg manifest, triplets, overlay ports and patches, and the Apache-2.0 license. The orchestration scripts were replaced by `src/native_deps.jsl` and are no longer installed in this merged Linux repository.

Run `./tools/embed_assets.jsl` from the source root after editing these inputs to regenerate `src/assets.jsl`. They are shipped inside the standalone Jess executable. The Linux build target is exclusively AlmaLinux 9.

Refer to the root `README.md` and `docs/AUDIT.md` for the modern CLI, original-file responsibility map, and qualification limits.
