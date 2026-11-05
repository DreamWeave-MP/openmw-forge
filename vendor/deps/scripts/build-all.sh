#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/fail.sh
source "$SCRIPT_DIR/lib/fail.sh"
openmw_init_error_trap
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
REPO_ROOT="${OPENMW_DEPS_REPO_ROOT}"

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo env \
            PROFILE="$PROFILE" \
            OPENMW_DEPS_BUILD_CONF="$OPENMW_DEPS_BUILD_CONF" \
            OPENMW_DEPS_REPO_ROOT="$OPENMW_DEPS_REPO_ROOT" \
            "$@"
    else
        echo "ERROR: Need root privileges to run '$*' and sudo is not available" >&2
        exit 1
    fi
}

TRIPLET="${TRIPLET:-$DEFAULT_TRIPLET}"
VCPKG_DIR="${VCPKG_DIR:-/opt/vcpkg}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT}"

export VCPKG_DIR
export PROFILE

echo "Running full dependency build"
echo "  profile: $PROFILE"
echo "  triplet: $TRIPLET"
echo "  image: $BUILD_IMAGE"
echo "  vcpkg revision: $VCPKG_REVISION"
echo "  output dir: $OUTPUT_DIR"

if [ "${OPENMW_DEPS_SKIP_DOCTOR:-0}" != "1" ]; then
    echo "=== Running preflight doctor (core mode) ==="
    MODE=core TRIPLET="$TRIPLET" OUTPUT_DIR="$OUTPUT_DIR" PROFILE="$PROFILE" bash -e "$SCRIPT_DIR/doctor.sh"
fi

echo "=== Installing system dependencies ==="
run_as_root bash -e "$SCRIPT_DIR/install-system-deps.sh"

OPENMW_DEPS_7ZIP_CMD="$(resolve_7zip_cmd)"
if [ -z "$OPENMW_DEPS_7ZIP_CMD" ]; then
    echo "ERROR: No 7zip command found after dependency installation (tried: 7z, 7zz, 7za)" >&2
    exit 1
fi
export OPENMW_DEPS_7ZIP_CMD
echo "  7zip command: $OPENMW_DEPS_7ZIP_CMD"

echo -e "\n=== Setting up vcpkg ==="
run_as_root bash -e "$SCRIPT_DIR/setup-vcpkg.sh"
run_as_root chown -R "$(id -u):$(id -g)" "$VCPKG_DIR"

echo -e "\n=== Building deps (triplet=$TRIPLET) ==="
TRIPLET="$TRIPLET" bash -e "$SCRIPT_DIR/build-deps.sh"

echo -e "\n=== Exporting ==="
source "$BUILD_TOOLSET_ENABLE"
export PATH="$VCPKG_DIR:$PATH"
cd "$REPO_ROOT"
vcpkg export \
    --x-all-installed \
    --7zip \
    --output-dir "$OUTPUT_DIR" \
    --output "vcpkg-$TRIPLET"

metadata_file="$OUTPUT_DIR/vcpkg-$TRIPLET.build-meta"
cat > "$metadata_file" <<EOF
profile=$PROFILE
triplet=$TRIPLET
image=$BUILD_IMAGE
vcpkg_revision=$VCPKG_REVISION
vcpkg_dir=$VCPKG_DIR
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo ""
echo "=== Verifying exported build artifacts ==="
TRIPLET="$TRIPLET" OUTPUT_DIR="$OUTPUT_DIR" PROFILE="$PROFILE" bash -e "$SCRIPT_DIR/verify-build.sh"

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_DIR/vcpkg-$TRIPLET.7z"
echo "Metadata: $metadata_file"
