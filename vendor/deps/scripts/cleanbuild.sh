#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/fail.sh
source "$SCRIPT_DIR/lib/fail.sh"
openmw_init_error_trap
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

MODE="${MODE:-distrobox}"
TRIPLET="${TRIPLET:-$DEFAULT_TRIPLET}"
OUTPUT_DIR="${OUTPUT_DIR:-$OPENMW_DEPS_REPO_ROOT}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
OPENMW_DEPS_IMAGE="${OPENMW_DEPS_IMAGE:-openmw-deps-${PROFILE}}"
BOX_NAME="${BOX_NAME:-openmw-deps-${PROFILE}}"
OPENMW_DEPS_CONTAINER="${OPENMW_DEPS_CONTAINER:-openmw-deps-${PROFILE}}"
REMOVE_OPENMW_DEPS_IMAGE="${REMOVE_OPENMW_DEPS_IMAGE:-0}"

should_remove_runtime() {
    [ "$REMOVE_OPENMW_DEPS_IMAGE" = "1" ]
}

image_exists() {
    $CONTAINER_ENGINE image inspect "$OPENMW_DEPS_IMAGE" >/dev/null 2>&1
}

build_runtime_image() {
    echo "=== Building runtime image ($CONTAINER_ENGINE) ==="
    $CONTAINER_ENGINE build --build-arg BASE_IMAGE="$BUILD_IMAGE" -t "$OPENMW_DEPS_IMAGE" .
}

container_exists() {
    $CONTAINER_ENGINE container inspect "$OPENMW_DEPS_CONTAINER" >/dev/null 2>&1
}

container_is_running() {
    [ "$($CONTAINER_ENGINE container inspect --format '{{.State.Running}}' "$OPENMW_DEPS_CONTAINER" 2>/dev/null || true)" = "true" ]
}

cleanup() {
    if should_remove_runtime && [ "$MODE" = "distrobox" ]; then
        distrobox rm --force "$BOX_NAME" 2>/dev/null || true
    fi

    if should_remove_runtime && [ "$MODE" = "container" ]; then
        $CONTAINER_ENGINE rm --force "$OPENMW_DEPS_CONTAINER" 2>/dev/null || true
    fi

    if should_remove_runtime; then
        $CONTAINER_ENGINE rmi "$OPENMW_DEPS_IMAGE" 2>/dev/null || true
    fi
}
trap cleanup EXIT

cd "$REPO_ROOT"

echo "=== Running preflight doctor ($MODE mode) ==="
MODE="$MODE" TRIPLET="$TRIPLET" OUTPUT_DIR="$OUTPUT_DIR" PROFILE="$PROFILE" CONTAINER_ENGINE="$CONTAINER_ENGINE" bash -e "$SCRIPT_DIR/doctor.sh"

rm -f "$OUTPUT_DIR/vcpkg-$TRIPLET.7z" "$OUTPUT_DIR/vcpkg-$TRIPLET.build-meta"

case "$MODE" in
    distrobox)
        export DBX_CONTAINER_MANAGER="$CONTAINER_ENGINE"

        if should_remove_runtime; then
            echo "=== Removing any existing $BOX_NAME ==="
            distrobox rm --force "$BOX_NAME" 2>/dev/null || true
        fi

        if should_remove_runtime || ! $CONTAINER_ENGINE container inspect "$BOX_NAME" >/dev/null 2>&1; then
            build_runtime_image
        fi

        if ! $CONTAINER_ENGINE container inspect "$BOX_NAME" >/dev/null 2>&1; then
            echo "=== Creating $BOX_NAME ==="
            distrobox create --yes --name "$BOX_NAME" --image "$OPENMW_DEPS_IMAGE"
        else
            echo "=== Reusing existing $BOX_NAME ==="
        fi

        echo "=== Running build-all.sh inside $BOX_NAME ==="
        distrobox enter "$BOX_NAME" -- env \
            PROFILE="$PROFILE" \
            TRIPLET="$TRIPLET" \
            OUTPUT_DIR="$OUTPUT_DIR" \
            OPENMW_DEPS_7ZIP_CMD= \
            OPENMW_DEPS_SKIP_DOCTOR=1 \
            bash -e "$SCRIPT_DIR/build-all.sh"
        ;;
    container)
        volume_mount="$OUTPUT_DIR:/out"
        if [ "$CONTAINER_ENGINE" = "podman" ]; then
            volume_mount="$volume_mount:Z"
        fi

        if should_remove_runtime; then
            echo "=== Removing any existing $OPENMW_DEPS_CONTAINER ==="
            $CONTAINER_ENGINE rm --force "$OPENMW_DEPS_CONTAINER" 2>/dev/null || true
            build_runtime_image
        elif ! container_exists; then
            if ! image_exists; then
                build_runtime_image
            fi
        fi

        if ! container_exists; then
            echo "=== Creating $OPENMW_DEPS_CONTAINER ==="
            $CONTAINER_ENGINE create \
                --name "$OPENMW_DEPS_CONTAINER" \
                -v "$volume_mount" \
                "$OPENMW_DEPS_IMAGE" \
                tail -f /dev/null >/dev/null
        else
            echo "=== Reusing existing $OPENMW_DEPS_CONTAINER ==="
        fi

        if ! container_is_running; then
            $CONTAINER_ENGINE start "$OPENMW_DEPS_CONTAINER" >/dev/null
        fi

        echo "=== Running clean build inside container ==="
        $CONTAINER_ENGINE exec \
            -e PROFILE="$PROFILE" \
            -e TRIPLET="$TRIPLET" \
            -e OUTPUT_DIR=/out \
            -e OPENMW_DEPS_7ZIP_CMD= \
            -e OPENMW_DEPS_SKIP_DOCTOR=1 \
            "$OPENMW_DEPS_CONTAINER" \
            bash -e scripts/build-all.sh

        if container_is_running; then
            $CONTAINER_ENGINE stop "$OPENMW_DEPS_CONTAINER" >/dev/null
        fi
        ;;
    *)
        echo "ERROR: Unsupported MODE '$MODE'. Use MODE=distrobox or MODE=container." >&2
        exit 1
        ;;
esac
