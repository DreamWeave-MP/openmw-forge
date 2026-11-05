#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/fail.sh
source "$SCRIPT_DIR/lib/fail.sh"
openmw_init_error_trap
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

TRIPLET="${TRIPLET:-$DEFAULT_TRIPLET}"
OUTPUT_DIR="${OUTPUT_DIR:-$OPENMW_DEPS_REPO_ROOT}"
ARCHIVE_PATH="$OUTPUT_DIR/vcpkg-$TRIPLET.7z"
METADATA_PATH="$OUTPUT_DIR/vcpkg-$TRIPLET.build-meta"

echo "Verifying exported build artifacts"
echo "  profile: $PROFILE"
echo "  triplet: $TRIPLET"
echo "  output dir: $OUTPUT_DIR"

if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "ERROR: Missing archive: $ARCHIVE_PATH" >&2
    exit 1
fi

if [ ! -s "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive is empty: $ARCHIVE_PATH" >&2
    exit 1
fi

if [ ! -f "$METADATA_PATH" ]; then
    echo "ERROR: Missing metadata file: $METADATA_PATH" >&2
    exit 1
fi

metadata_profile="$(grep '^profile=' "$METADATA_PATH" | cut -d'=' -f2-)"
metadata_triplet="$(grep '^triplet=' "$METADATA_PATH" | cut -d'=' -f2-)"
metadata_revision="$(grep '^vcpkg_revision=' "$METADATA_PATH" | cut -d'=' -f2-)"

if [ "$metadata_profile" != "$PROFILE" ]; then
    echo "ERROR: Metadata profile mismatch. expected=$PROFILE actual=$metadata_profile" >&2
    exit 1
fi

if [ "$metadata_triplet" != "$TRIPLET" ]; then
    echo "ERROR: Metadata triplet mismatch. expected=$TRIPLET actual=$metadata_triplet" >&2
    exit 1
fi

if [ "$metadata_revision" != "$VCPKG_REVISION" ]; then
    echo "ERROR: Metadata vcpkg revision mismatch. expected=$VCPKG_REVISION actual=$metadata_revision" >&2
    exit 1
fi

if [ -n "$OPENMW_DEPS_7ZIP_CMD" ]; then
    temp_list="$(mktemp)"
    "$OPENMW_DEPS_7ZIP_CMD" l "$ARCHIVE_PATH" > "$temp_list"
    if ! grep -q "installed/$TRIPLET" "$temp_list"; then
        rm -f "$temp_list"
        echo "ERROR: Archive does not include installed/$TRIPLET" >&2
        exit 1
    fi
    rm -f "$temp_list"
else
    echo "WARNING: 7zip command is not available (tried: 7z, 7zz, 7za), skipping archive content check"
fi

echo "Running ABI verification"
TRIPLET="$TRIPLET" OUTPUT_DIR="$OUTPUT_DIR" bash -e "$SCRIPT_DIR/verify-abi.sh"

echo "Verification complete"
