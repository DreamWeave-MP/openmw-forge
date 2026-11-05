# Distro Smoke Targets

Minimum floor checks:

- AlmaLinux 9, glibc 2.34, distrobox image `almalinux:9`.
- Debian 12, glibc 2.36, distrobox image `debian:12`.
- Ubuntu 22.04, glibc 2.35, distrobox image `ubuntu:22.04`.

Modern distro proxies:

- Debian 12/13 for MX Linux and Q4OS-style Debian derivatives.
- Ubuntu 22.04/24.04 for Linux Mint and Ubuntu LTS desktops.
- Fedora latest and Fedora 41 for modern GNOME/Wayland stacks.
- Arch Linux for EndeavourOS/CachyOS-style rolling stacks.
- openSUSE Tumbleweed and Void Linux glibc for rolling/independent coverage.

Distrobox verifies dynamic linking, glibc symbol floors, Qt plugin loading, and basic process startup. It does not replace live ISO testing for compositor, portal, audio, GPU, or desktop-session quirks.
