#!/bin/bash

load_package_config() {
    local package_dir=$1
    local config_path="${package_dir}/package.conf"

    [ -f "$config_path" ] || die "package.conf not found in ${package_dir}"

    PACKAGE_DIR=$(realpath "$package_dir")
    PACKAGE_NAME=$(basename "$PACKAGE_DIR")

    # shellcheck disable=SC1090
    source "$config_path"

    ARCHES=("${ARCHES[@]}")
    LICENSES=("${LICENSES[@]}")
    DEPENDS=("${DEPENDS[@]}")
    MAKEDEPENDS=("${MAKEDEPENDS[@]}")
    CHECKDEPENDS=("${CHECKDEPENDS[@]}")
    OPTDEPENDS=("${OPTDEPENDS[@]}")
    OPTIONS=("${OPTIONS[@]}")
    PROVIDES=("${PROVIDES[@]}")
    CONFLICTS=("${CONFLICTS[@]}")
    VALIDPGPKEYS=("${VALIDPGPKEYS[@]}")
    LOCAL_FILES=("${LOCAL_FILES[@]}")
    PATCH_FILES=("${PATCH_FILES[@]}")
    DOC_FILES=("${DOC_FILES[@]}")
    LICENSE_FILES=("${LICENSE_FILES[@]}")
    INSTALL_HINTS=("${INSTALL_HINTS[@]}")
    DESKTOP_CANDIDATES=("${DESKTOP_CANDIDATES[@]}")
    ICON_CANDIDATES=("${ICON_CANDIDATES[@]}")
    MESON_OPTIONS=("${MESON_OPTIONS[@]}")
    CHECK_ARGS=("${CHECK_ARGS[@]}")
    PERSIST_STATE_KEYS=("${PERSIST_STATE_KEYS[@]}")
    TEST_PATHS=("${TEST_PATHS[@]}")
    TEST_EXECUTABLES=("${TEST_EXECUTABLES[@]}")

    [ -n "$PKGNAME" ] || die "PKGNAME is required in ${config_path}"
    [ "$PKGNAME" = "$PACKAGE_NAME" ] || die "Package directory must match PKGNAME: ${PACKAGE_NAME} != ${PKGNAME}"
    [ -n "$PACKAGE_TEMPLATE" ] || die "PACKAGE_TEMPLATE is required in ${config_path}"
    [ -n "$UPSTREAM_TYPE" ] || die "UPSTREAM_TYPE is required in ${config_path}"
    [ -n "$PKGDESC" ] || die "PKGDESC is required in ${config_path}"
    [ -n "$URL" ] || die "URL is required in ${config_path}"
    [ "${#ARCHES[@]}" -gt 0 ] || die "ARCHES must not be empty in ${config_path}"
    [ "${#LICENSES[@]}" -gt 0 ] || die "LICENSES must not be empty in ${config_path}"

    if [ "${#PROVIDES[@]}" -eq 0 ] && [[ "$PKGNAME" == *-bin ]]; then
        PROVIDES=("${PKGNAME%-bin}")
    fi

    if [ "${#CONFLICTS[@]}" -eq 0 ] && [[ "$PKGNAME" == *-bin ]]; then
        CONFLICTS=("${PKGNAME%-bin}")
    fi

    INSTALL_MODE=${INSTALL_MODE:-none}
    SERVICE_MODE=${SERVICE_MODE:-none}
    SERVICE_SCOPE=${SERVICE_SCOPE:-user}
    WRAPPER_SOURCE_PATH=${WRAPPER_SOURCE_PATH:-}
    WRAPPER_INSTALL_PATH=${WRAPPER_INSTALL_PATH:-}
    WRAPPER_MODE=${WRAPPER_MODE:-755}
    UPSTREAM_TAG_PREFIX=${UPSTREAM_TAG_PREFIX:-}
    UPSTREAM_ALLOW_PRERELEASE=${UPSTREAM_ALLOW_PRERELEASE:-false}
    DEB_RELOCATE_USR_LOCAL=${DEB_RELOCATE_USR_LOCAL:-false}
    APPIMAGE_APPDIR_NAME=${APPIMAGE_APPDIR_NAME:-squashfs-root}
    SOURCE_DIR=${SOURCE_DIR:-$PKGNAME}
    BUILD_DIR=${BUILD_DIR:-build}
    RUN_CHECK=${RUN_CHECK:-false}

    case "$INSTALL_MODE" in
        none|generated|static) ;;
        *) die "Unsupported INSTALL_MODE in ${config_path}: ${INSTALL_MODE}" ;;
    esac

    case "$SERVICE_MODE" in
        none|generated|static) ;;
        *) die "Unsupported SERVICE_MODE in ${config_path}: ${SERVICE_MODE}" ;;
    esac

    case "$SERVICE_SCOPE" in
        user|system) ;;
        *) die "Unsupported SERVICE_SCOPE in ${config_path}: ${SERVICE_SCOPE}" ;;
    esac

    if [ "$UPSTREAM_TYPE" = "github-release-assets" ]; then
        [ -n "$UPSTREAM_REPO_USER" ] || die "UPSTREAM_REPO_USER is required for github-release-assets"
        [ -n "$UPSTREAM_REPO_NAME" ] || die "UPSTREAM_REPO_NAME is required for github-release-assets"
    fi

    if [ "$PACKAGE_TEMPLATE" = "binary-archive" ] || [ "$PACKAGE_TEMPLATE" = "appimage-desktop" ]; then
        [ -n "$BINARY_NAME" ] || die "BINARY_NAME is required for template ${PACKAGE_TEMPLATE}"
        [ -n "$INSTALL_BIN_PATH" ] || die "INSTALL_BIN_PATH is required for template ${PACKAGE_TEMPLATE}"
    fi

    if [ -n "$WRAPPER_SOURCE_PATH" ] || [ -n "$WRAPPER_INSTALL_PATH" ]; then
        [ -n "$WRAPPER_SOURCE_PATH" ] || die "WRAPPER_SOURCE_PATH is required when WRAPPER_INSTALL_PATH is set"
        [ -n "$WRAPPER_INSTALL_PATH" ] || die "WRAPPER_INSTALL_PATH is required when WRAPPER_SOURCE_PATH is set"
    fi

    if [ "$PACKAGE_TEMPLATE" = "source-meson" ]; then
        [ -n "$SOURCE_RENAME" ] || die "SOURCE_RENAME is required for template ${PACKAGE_TEMPLATE}"
    fi

    if [ "$SERVICE_MODE" != "none" ]; then
        [ -n "$SERVICE_NAME" ] || die "SERVICE_NAME is required when SERVICE_MODE is ${SERVICE_MODE}"
    fi

    if [ "$SERVICE_MODE" = "generated" ]; then
        [ -n "$SERVICE_EXEC" ] || die "SERVICE_EXEC is required when SERVICE_MODE=generated"
        SERVICE_RESTART=${SERVICE_RESTART:-always}
        SERVICE_RESTART_SEC=${SERVICE_RESTART_SEC:-10}
    fi

    if [ "$SERVICE_MODE" = "static" ]; then
        [ -n "$SERVICE_FILE" ] || die "SERVICE_FILE is required when SERVICE_MODE=static"
    fi

    if [ "$INSTALL_MODE" = "static" ]; then
        [ -n "$INSTALL_FILE" ] || die "INSTALL_FILE is required when INSTALL_MODE=static"
    fi

    local test_path
    for test_path in "${TEST_PATHS[@]}"; do
        [ -z "$test_path" ] && continue
        [[ "$test_path" = /* ]] || die "TEST_PATHS entries must be absolute paths in ${config_path}: ${test_path}"
    done

    local test_executable
    for test_executable in "${TEST_EXECUTABLES[@]}"; do
        [ -z "$test_executable" ] && continue
        [[ "$test_executable" = /* ]] || die "TEST_EXECUTABLES entries must be absolute paths in ${config_path}: ${test_executable}"
    done
}

load_package_hooks() {
    local hooks_path="${PACKAGE_DIR}/hooks.sh"

    if [ -f "$hooks_path" ]; then
        # shellcheck disable=SC1090
        source "$hooks_path"
    fi
}
