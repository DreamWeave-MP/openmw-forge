# Linux Portable Tarball Status

The standalone builder preserves the branch behavior: vcpkg dependency archive extraction, Qt 6.6.3 installation via `aqtinstall`, RPATH configuration, runtime wrappers, Qt/vcpkg library bundling, debug sidecar creation, symbol-version compatibility auditing, and tarball smoke tests.

The important architectural change is that the builder no longer assumes the OpenMW source tree is the parent repository. `scripts/configure_openmw.sh` contains the extracted tarball/vcpkg CMake configuration logic that used to live behind `CI_OPENMW_USE_VCPKG=true` in `CI/before_script.linux.sh`.

Known constraints:

- Dependency archives may be `.tar.xz` or `.7z`.
- System package installation is RPM/dnf-oriented for Alma/RHEL-family build containers.
- Container and distrobox wrappers use AlmaLinux 9 by default, matching the compatibility audit's AlmaLinux 9 base/system toolchain symbol-version floor.
