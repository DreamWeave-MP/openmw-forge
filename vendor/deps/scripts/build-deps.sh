#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/fail.sh
source "$SCRIPT_DIR/lib/fail.sh"
openmw_init_error_trap
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

VCPKG_DIR="${VCPKG_DIR:-/opt/vcpkg}"
TRIPLET="${TRIPLET:-$DEFAULT_TRIPLET}"
REPO_ROOT="${OPENMW_DEPS_REPO_ROOT}"

export PATH="$VCPKG_DIR:$PATH"

source "$BUILD_TOOLSET_ENABLE"

echo "Building dependencies"
echo "  profile: $PROFILE"
echo "  triplet: $TRIPLET"
echo "  vcpkg revision: $VCPKG_REVISION"
echo "  vcpkg dir: $VCPKG_DIR"

cd "$REPO_ROOT"
vcpkg install \
    --overlay-ports="$REPO_ROOT/ports" \
    --overlay-triplets="$REPO_ROOT/triplets" \
    --triplet "$TRIPLET" \
    --host-triplet "$TRIPLET"

echo ""
echo "Done. To export:"
echo "  vcpkg export --x-all-installed --7zip --output-dir ./ --output vcpkg-$TRIPLET"
