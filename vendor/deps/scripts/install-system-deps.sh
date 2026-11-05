#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/fail.sh
source "$SCRIPT_DIR/lib/fail.sh"
openmw_init_error_trap
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

enable_crb() {
    if command -v crb >/dev/null 2>&1; then
        crb enable
        return
    fi

    if command -v dnf >/dev/null 2>&1; then
        dnf install -y dnf-plugins-core
        if dnf repolist all | grep -q '^crb'; then
            dnf config-manager --set-enabled crb
        elif dnf repolist all | grep -q '^powertools'; then
            dnf config-manager --set-enabled powertools
        fi
    fi
}

common_packages=(
    git
    tar
    p7zip
    zip
    unzip
    curl
    "$BUILD_TOOLSET_PACKAGE"
    cmake
    ninja-build
    perl
    autoconf
    autoconf-archive
    automake
    libtool
    nasm
    pkgconfig
    mesa-libGL-devel
    mesa-libEGL-devel
    libXcursor-devel
    libX11-devel
    libXft-devel
    libXext-devel
    libxkbcommon-devel
    wayland-devel
    texinfo
    gettext-devel
    kernel-headers
)

case "$PROFILE" in
    alma8)
        python_packages=(python39)
        ;;
    alma9)
        python_packages=(python3)
        ;;
    *)
        echo "ERROR: Unsupported profile for system dependency installation: $PROFILE" >&2
        exit 1
        ;;
esac

echo "Installing system dependencies for profile=$PROFILE"
dnf install -y epel-release
enable_crb
dnf install -y "${common_packages[@]}" "${python_packages[@]}"

if [ "$PROFILE" = "alma8" ] && [ -x /usr/bin/python3.9 ]; then
    alternatives --set python3 /usr/bin/python3.9
fi

if ! /usr/local/bin/autoconf --version 2>/dev/null | head -1 | grep -q "$BUILD_AUTOCONF_VERSION"; then
    tmpdir="$(mktemp -d)"
    tarball="$tmpdir/autoconf.tar.gz"
    curl -L "$BUILD_AUTOCONF_URL" -o "$tarball"
    printf '%s  %s\n' "$BUILD_AUTOCONF_SHA512" "$tarball" | sha512sum -c -
    tar xf "$tarball" -C "$tmpdir"
    cd "$tmpdir/autoconf-$BUILD_AUTOCONF_VERSION"
    ./configure --prefix=/usr/local
    make && make install
    rm -rf "$tmpdir"
fi
