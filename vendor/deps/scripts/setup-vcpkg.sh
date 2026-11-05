#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/fail.sh
source "$SCRIPT_DIR/lib/fail.sh"
openmw_init_error_trap
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

VCPKG_DIR="${VCPKG_DIR:-/opt/vcpkg}"

echo "Setting up vcpkg"
echo "  profile: $PROFILE"
echo "  revision: $VCPKG_REVISION"
echo "  install dir: $VCPKG_DIR"

if [ -d "$VCPKG_DIR/.git" ]; then
    cd "$VCPKG_DIR"
    git fetch
    git checkout "$VCPKG_REVISION"
else
    git clone https://github.com/microsoft/vcpkg.git "$VCPKG_DIR"
    cd "$VCPKG_DIR"
    git checkout "$VCPKG_REVISION"
fi

source "$BUILD_TOOLSET_ENABLE"
./bootstrap-vcpkg.sh -disableMetrics

echo ""
echo "vcpkg is ready at $VCPKG_DIR"
echo "Add it to your PATH:  export PATH=\"$VCPKG_DIR:\$PATH\""
