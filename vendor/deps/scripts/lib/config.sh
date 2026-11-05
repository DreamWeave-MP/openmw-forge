#!/usr/bin/env bash

if [ "${OPENMW_DEPS_CONFIG_LOADED:-0}" -eq 1 ] && [ "${OPENMW_DEPS_CONFIG_PID:-0}" -eq "$$" ]; then
    return 0
fi

set -u

CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENMW_DEPS_REPO_ROOT="${OPENMW_DEPS_REPO_ROOT:-$(cd "$CONFIG_LIB_DIR/../.." && pwd)}"
OPENMW_DEPS_BUILD_CONF="${OPENMW_DEPS_BUILD_CONF:-$OPENMW_DEPS_REPO_ROOT/build.conf}"

if [ ! -f "$OPENMW_DEPS_BUILD_CONF" ]; then
    echo "ERROR: build config not found at $OPENMW_DEPS_BUILD_CONF" >&2
    return 1
fi

# shellcheck source=/dev/null
source "$OPENMW_DEPS_BUILD_CONF"

if [ -z "${DEFAULT_PROFILE:-}" ]; then
    echo "ERROR: DEFAULT_PROFILE is not set in $OPENMW_DEPS_BUILD_CONF" >&2
    return 1
fi

if [ -z "${VCPKG_REVISION:-}" ]; then
    echo "ERROR: VCPKG_REVISION is not set in $OPENMW_DEPS_BUILD_CONF" >&2
    return 1
fi

PROFILE="${PROFILE:-$DEFAULT_PROFILE}"
PROFILE_UPPER="$(printf '%s' "$PROFILE" | tr '[:lower:]-' '[:upper:]_')"

_profile_var_prefix="PROFILE_${PROFILE_UPPER}_"

config_profile_get() {
    local key="$1"
    local var_name="${_profile_var_prefix}${key}"
    printf '%s' "${!var_name:-}"
}

config_require_non_empty() {
    local name="$1"
    local value="$2"
    if [ -z "$value" ]; then
        echo "ERROR: Missing required config value: $name (profile=$PROFILE)" >&2
        return 1
    fi
}

resolve_7zip_cmd() {
    local candidate

    for candidate in 7z 7zz 7za; do
        if command -v "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    printf ''
}

resolve_effective_7zip_cmd() {
    if [ -n "${OPENMW_DEPS_7ZIP_CMD:-}" ] && command -v "$OPENMW_DEPS_7ZIP_CMD" >/dev/null 2>&1; then
        printf '%s' "$OPENMW_DEPS_7ZIP_CMD"
        return 0
    fi

    resolve_7zip_cmd
}

BUILD_IMAGE="$(config_profile_get IMAGE)"
BUILD_TOOLSET_PACKAGE="$(config_profile_get TOOLSET_PACKAGE)"
BUILD_TOOLSET_ENABLE="$(config_profile_get TOOLSET_ENABLE)"
BUILD_AUTOCONF_VERSION="$(config_profile_get AUTOCONF_VERSION)"
BUILD_AUTOCONF_URL="$(config_profile_get AUTOCONF_URL)"
BUILD_AUTOCONF_SHA512="$(config_profile_get AUTOCONF_SHA512)"
BUILD_GLIBC_MAX="$(config_profile_get GLIBC_MAX)"
BUILD_GLIBCXX_MAX="$(config_profile_get GLIBCXX_MAX)"
BUILD_CXXABI_MAX="$(config_profile_get CXXABI_MAX)"
OPENMW_DEPS_7ZIP_CMD="$(resolve_effective_7zip_cmd)"

missing_config=0
config_require_non_empty "PROFILE_${PROFILE_UPPER}_IMAGE" "$BUILD_IMAGE" || missing_config=1
config_require_non_empty "PROFILE_${PROFILE_UPPER}_TOOLSET_PACKAGE" "$BUILD_TOOLSET_PACKAGE" || missing_config=1
config_require_non_empty "PROFILE_${PROFILE_UPPER}_TOOLSET_ENABLE" "$BUILD_TOOLSET_ENABLE" || missing_config=1
config_require_non_empty "PROFILE_${PROFILE_UPPER}_AUTOCONF_VERSION" "$BUILD_AUTOCONF_VERSION" || missing_config=1
config_require_non_empty "PROFILE_${PROFILE_UPPER}_AUTOCONF_URL" "$BUILD_AUTOCONF_URL" || missing_config=1
config_require_non_empty "PROFILE_${PROFILE_UPPER}_AUTOCONF_SHA512" "$BUILD_AUTOCONF_SHA512" || missing_config=1
config_require_non_empty "PROFILE_${PROFILE_UPPER}_GLIBC_MAX" "$BUILD_GLIBC_MAX" || missing_config=1
config_require_non_empty "PROFILE_${PROFILE_UPPER}_GLIBCXX_MAX" "$BUILD_GLIBCXX_MAX" || missing_config=1
config_require_non_empty "PROFILE_${PROFILE_UPPER}_CXXABI_MAX" "$BUILD_CXXABI_MAX" || missing_config=1

if [ "$missing_config" -ne 0 ]; then
    return 1
fi

export OPENMW_DEPS_REPO_ROOT
export OPENMW_DEPS_BUILD_CONF
export PROFILE
export DEFAULT_PROFILE
export DEFAULT_TRIPLET
export VCPKG_REVISION
export BUILD_IMAGE
export BUILD_TOOLSET_PACKAGE
export BUILD_TOOLSET_ENABLE
export BUILD_AUTOCONF_VERSION
export BUILD_AUTOCONF_URL
export BUILD_AUTOCONF_SHA512
export BUILD_GLIBC_MAX
export BUILD_GLIBCXX_MAX
export BUILD_CXXABI_MAX
export OPENMW_DEPS_7ZIP_CMD

OPENMW_DEPS_CONFIG_LOADED=1
OPENMW_DEPS_CONFIG_PID=$$
