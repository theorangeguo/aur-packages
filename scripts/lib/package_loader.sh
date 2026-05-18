#!/bin/bash

reset_package_spec_state() {
    local var

    for var in $(compgen -A variable); do
        case "$var" in
            STATE_FILE)
                ;;
            ASSET_SELECTOR_*|UPSTREAM_ASSET_NAME_*|SOURCE_RENAME_*|RESOLVED_SOURCE_URL_*|STATE_*|BINARY_RELEASE_ASSET_*)
                unset "$var"
                ;;
        esac
    done

    PACKAGE_SPEC_VERSION=""
    PACKAGE_SPEC_FORMAT=""
    PACKAGE_DEFINITION_PATH=""
    PKGNAME=""
    PKGDESC=""
    URL=""
    PACKAGE_TEMPLATE=""
    UPSTREAM_TYPE=""
    PACKAGING_REPO_URL=""
    RESOLVED_VERSION=""
    RESOLVED_SOURCE_URL=""
    GITHUB_RELEASE_TAG=""

    UPSTREAM_REPO_USER=""
    UPSTREAM_REPO_NAME=""
    UPSTREAM_TAG_PREFIX=""
    UPSTREAM_RELEASE_TAG_PREFIX=""
    UPSTREAM_ALLOW_PRERELEASE=""

    SOURCE_RENAME=""
    BINARY_NAME=""
    BINARY_SOURCE_PATH=""
    INSTALL_BIN_PATH=""
    WRAPPER_SOURCE_PATH=""
    WRAPPER_INSTALL_PATH=""
    WRAPPER_MODE=""

    INSTALL_MODE=""
    INSTALL_FILE=""
    SERVICE_MODE=""
    SERVICE_SCOPE=""
    SERVICE_NAME=""
    SERVICE_FILE=""
    SERVICE_EXEC=""
    SERVICE_RESTART=""
    SERVICE_RESTART_SEC=""

    DEB_RELOCATE_USR_LOCAL=""
    APPIMAGE_APPDIR_NAME=""
    APPIMAGE_INSTALL_DIR=""
    DESKTOP_EXEC_REWRITE=""
    DESKTOP_NAME_REWRITE=""
    SOURCE_DIR=""
    BUILD_DIR=""
    RUN_CHECK=""

    BINARY_RELEASE_ENABLED=""
    BINARY_RELEASE_TEMPLATE=""
    BINARY_RELEASE_REV=""
    BINARY_RELEASE_VERSION_TEMPLATE=""
    BINARY_RELEASE_TAG_PREFIX=""
    BINARY_RELEASE_REPO=""
    BINARY_RELEASE_UPSTREAM_TYPE=""
    BINARY_RELEASE_UPSTREAM_REPO_USER=""
    BINARY_RELEASE_UPSTREAM_REPO_NAME=""
    BINARY_RELEASE_UPSTREAM_TAG_PREFIX=""
    BINARY_RELEASE_SOURCE_DIR=""
    BINARY_RELEASE_RUN_CHECK=""

    ARCHES=()
    LICENSES=()
    DEPENDS=()
    MAKEDEPENDS=()
    CHECKDEPENDS=()
    OPTDEPENDS=()
    OPTIONS=()
    PROVIDES=()
    CONFLICTS=()
    VALIDPGPKEYS=()
    LOCAL_FILES=()
    PATCH_FILES=()
    DOC_FILES=()
    LICENSE_FILES=()
    INSTALL_HINTS=()
    DESKTOP_CANDIDATES=()
    ICON_CANDIDATES=()
    MESON_OPTIONS=()
    CHECK_ARGS=()
    BINARY_RELEASE_ARCHES=()
    BINARY_RELEASE_MAKEDEPENDS=()
    BINARY_RELEASE_PATCH_FILES=()
    BINARY_RELEASE_CARGO_FETCH_ARGS=()
    BINARY_RELEASE_CARGO_BUILD_ARGS=()
    BINARY_RELEASE_CARGO_CHECK_ARGS=()
    BINARY_RELEASE_ARCHIVE_FILES=()
    PERSIST_STATE_KEYS=()
    TEST_PATHS=()
    TEST_EXECUTABLES=()
    TEST_COMMANDS=()
}

normalize_package_spec_arrays() {
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
    BINARY_RELEASE_ARCHES=("${BINARY_RELEASE_ARCHES[@]}")
    BINARY_RELEASE_MAKEDEPENDS=("${BINARY_RELEASE_MAKEDEPENDS[@]}")
    BINARY_RELEASE_PATCH_FILES=("${BINARY_RELEASE_PATCH_FILES[@]}")
    BINARY_RELEASE_CARGO_FETCH_ARGS=("${BINARY_RELEASE_CARGO_FETCH_ARGS[@]}")
    BINARY_RELEASE_CARGO_BUILD_ARGS=("${BINARY_RELEASE_CARGO_BUILD_ARGS[@]}")
    BINARY_RELEASE_CARGO_CHECK_ARGS=("${BINARY_RELEASE_CARGO_CHECK_ARGS[@]}")
    BINARY_RELEASE_ARCHIVE_FILES=("${BINARY_RELEASE_ARCHIVE_FILES[@]}")
    PERSIST_STATE_KEYS=("${PERSIST_STATE_KEYS[@]}")
    TEST_PATHS=("${TEST_PATHS[@]}")
    TEST_EXECUTABLES=("${TEST_EXECUTABLES[@]}")
    TEST_COMMANDS=("${TEST_COMMANDS[@]}")
}

package_spec_definition_variable_names() {
    local fixed_vars=(
        PACKAGE_SPEC_VERSION PKGNAME PACKAGE_TEMPLATE UPSTREAM_TYPE PKGDESC URL LICENSES ARCHES DEPENDS MAKEDEPENDS CHECKDEPENDS OPTDEPENDS OPTIONS PROVIDES CONFLICTS VALIDPGPKEYS PACKAGING_REPO_URL
        UPSTREAM_REPO_USER UPSTREAM_REPO_NAME UPSTREAM_TAG_PREFIX UPSTREAM_RELEASE_TAG_PREFIX UPSTREAM_ALLOW_PRERELEASE
        SOURCE_RENAME BINARY_NAME BINARY_SOURCE_PATH INSTALL_BIN_PATH WRAPPER_SOURCE_PATH WRAPPER_INSTALL_PATH WRAPPER_MODE
        LOCAL_FILES PATCH_FILES DOC_FILES LICENSE_FILES INSTALL_MODE INSTALL_HINTS INSTALL_FILE SERVICE_MODE SERVICE_SCOPE SERVICE_NAME SERVICE_FILE SERVICE_EXEC SERVICE_RESTART SERVICE_RESTART_SEC
        DEB_RELOCATE_USR_LOCAL APPIMAGE_APPDIR_NAME APPIMAGE_INSTALL_DIR DESKTOP_CANDIDATES ICON_CANDIDATES DESKTOP_EXEC_REWRITE DESKTOP_NAME_REWRITE
        SOURCE_DIR BUILD_DIR MESON_OPTIONS RUN_CHECK CHECK_ARGS
        BINARY_RELEASE_ENABLED BINARY_RELEASE_TEMPLATE BINARY_RELEASE_REV BINARY_RELEASE_VERSION_TEMPLATE BINARY_RELEASE_TAG_PREFIX BINARY_RELEASE_REPO BINARY_RELEASE_ARCHES
        BINARY_RELEASE_UPSTREAM_TYPE BINARY_RELEASE_UPSTREAM_REPO_USER BINARY_RELEASE_UPSTREAM_REPO_NAME BINARY_RELEASE_UPSTREAM_TAG_PREFIX BINARY_RELEASE_SOURCE_DIR
        BINARY_RELEASE_PATCH_FILES BINARY_RELEASE_MAKEDEPENDS BINARY_RELEASE_CARGO_FETCH_ARGS BINARY_RELEASE_CARGO_BUILD_ARGS BINARY_RELEASE_CARGO_CHECK_ARGS BINARY_RELEASE_RUN_CHECK BINARY_RELEASE_ARCHIVE_FILES
        PERSIST_STATE_KEYS TEST_PATHS TEST_EXECUTABLES TEST_COMMANDS
    )
    local var

    printf '%s\n' "${fixed_vars[@]}"
    while IFS= read -r var; do
        case "$var" in
            ASSET_SELECTOR_*|UPSTREAM_ASSET_NAME_*|SOURCE_RENAME_*|BINARY_RELEASE_ASSET_*)
                printf '%s\n' "$var"
                ;;
        esac
    done < <(compgen -A variable)
}

package_spec_definition_state_digest() {
    local var

    while IFS= read -r var; do
        declare -p "$var" 2>/dev/null || true
    done < <(package_spec_definition_variable_names | sort -u) | sha256sum | cut -d' ' -f1
}

validate_package_asset_path() {
    local role=$1
    local relative_path=$2
    local asset_path

    [ -n "$relative_path" ] || return 0

    [[ "$relative_path" != /* ]] || die "${role} must be package-relative in ${PACKAGE_DEFINITION_PATH}: ${relative_path}"
    case "$relative_path" in
        ../*|*/../*|*/..)
            die "${role} must not escape the package directory in ${PACKAGE_DEFINITION_PATH}: ${relative_path}"
            ;;
    esac

    [ -e "${PACKAGE_DIR}/${relative_path}" ] || die "${role} not found in ${PACKAGE_DEFINITION_PATH}: ${relative_path}"
    asset_path=$(realpath "${PACKAGE_DIR}/${relative_path}")
    case "$asset_path" in
        "${PACKAGE_DIR}"/*) ;;
        *) die "${role} must resolve inside the package directory in ${PACKAGE_DEFINITION_PATH}: ${relative_path}" ;;
    esac

    [ -f "$asset_path" ] || die "${role} must resolve to a file in ${PACKAGE_DEFINITION_PATH}: ${relative_path}"
}

validate_package_name_value() {
    local value=$1
    local role=$2

    [[ "$value" =~ ^[a-zA-Z0-9._+-]+$ ]] || die "${role} contains unsupported characters in ${PACKAGE_DEFINITION_PATH}: ${value}"
}

validate_absolute_install_path() {
    local role=$1
    local path_value=$2

    [ -n "$path_value" ] || return 0
    [[ "$path_value" = /* ]] || die "${role} must be absolute in ${PACKAGE_DEFINITION_PATH}: ${path_value}"
    case "$path_value" in
        *'/../'*|*'/..'|'/')
            die "${role} must be a normalized install path in ${PACKAGE_DEFINITION_PATH}: ${path_value}"
            ;;
    esac
}

validate_relative_source_pattern() {
    local role=$1
    local pattern=$2

    [ -n "$pattern" ] || return 0
    [[ "$pattern" != /* ]] || die "${role} must be relative to source roots in ${PACKAGE_DEFINITION_PATH}: ${pattern}"
    case "$pattern" in
        ../*|*/../*|*/..)
            die "${role} must not escape source roots in ${PACKAGE_DEFINITION_PATH}: ${pattern}"
            ;;
    esac
}

validate_package_spec() {
    local config_path=$PACKAGE_DEFINITION_PATH

    [ -n "$PACKAGE_SPEC_VERSION" ] || die "PACKAGE_SPEC_VERSION=${PACKAGE_SPEC_SUPPORTED_VERSION} is required in ${config_path}"
    [ "$PACKAGE_SPEC_VERSION" = "$PACKAGE_SPEC_SUPPORTED_VERSION" ] || die "Unsupported PACKAGE_SPEC_VERSION in ${config_path}: ${PACKAGE_SPEC_VERSION}"
    [ -n "$PKGNAME" ] || die "PKGNAME is required in ${config_path}"
    validate_package_name_value "$PKGNAME" "PKGNAME"
    [ "$PKGNAME" = "$PACKAGE_NAME" ] || die "Package directory must match PKGNAME: ${PACKAGE_NAME} != ${PKGNAME}"
    [ -n "$PACKAGE_TEMPLATE" ] || die "PACKAGE_TEMPLATE is required in ${config_path}"
    [ -n "$UPSTREAM_TYPE" ] || die "UPSTREAM_TYPE is required in ${config_path}"
    [ -n "$PKGDESC" ] || die "PKGDESC is required in ${config_path}"
    [ -n "$URL" ] || die "URL is required in ${config_path}"
    [ "${#ARCHES[@]}" -gt 0 ] || die "ARCHES must not be empty in ${config_path}"
    [ "${#LICENSES[@]}" -gt 0 ] || die "LICENSES must not be empty in ${config_path}"

    case "$PACKAGE_TEMPLATE" in
        binary-archive|deb-repack|appimage-desktop|source-meson) ;;
        *) die "Unsupported PACKAGE_TEMPLATE in ${config_path}: ${PACKAGE_TEMPLATE}" ;;
    esac

    case "$UPSTREAM_TYPE" in
        github-release-assets|custom-hook) ;;
        *) die "Unsupported UPSTREAM_TYPE in ${config_path}: ${UPSTREAM_TYPE}" ;;
    esac

    if [ "${#PROVIDES[@]}" -eq 0 ] && [[ "$PKGNAME" == *-bin ]]; then
        PROVIDES=("${PKGNAME%-bin}")
    fi

    if [ "${#CONFLICTS[@]}" -eq 0 ] && [[ "$PKGNAME" == *-bin ]]; then
        CONFLICTS=("${PKGNAME%-bin}")
    fi

    INSTALL_MODE=${INSTALL_MODE:-none}
    SERVICE_MODE=${SERVICE_MODE:-none}
    SERVICE_SCOPE=${SERVICE_SCOPE:-user}
    PACKAGING_REPO_URL=${PACKAGING_REPO_URL:-https://github.com/orange-guo/aur-packages/tree/main/packages/${PKGNAME}}
    WRAPPER_SOURCE_PATH=${WRAPPER_SOURCE_PATH:-}
    WRAPPER_INSTALL_PATH=${WRAPPER_INSTALL_PATH:-}
    WRAPPER_MODE=${WRAPPER_MODE:-755}
    UPSTREAM_TAG_PREFIX=${UPSTREAM_TAG_PREFIX:-}
    UPSTREAM_RELEASE_TAG_PREFIX=${UPSTREAM_RELEASE_TAG_PREFIX:-}
    UPSTREAM_ALLOW_PRERELEASE=${UPSTREAM_ALLOW_PRERELEASE:-false}
    DEB_RELOCATE_USR_LOCAL=${DEB_RELOCATE_USR_LOCAL:-false}
    APPIMAGE_APPDIR_NAME=${APPIMAGE_APPDIR_NAME:-squashfs-root}
    SOURCE_DIR=${SOURCE_DIR:-$PKGNAME}
    BUILD_DIR=${BUILD_DIR:-build}
    RUN_CHECK=${RUN_CHECK:-false}
    BINARY_RELEASE_ENABLED=${BINARY_RELEASE_ENABLED:-false}
    BINARY_RELEASE_TEMPLATE=${BINARY_RELEASE_TEMPLATE:-}
    BINARY_RELEASE_REV=${BINARY_RELEASE_REV:-1}
    BINARY_RELEASE_VERSION_TEMPLATE=${BINARY_RELEASE_VERSION_TEMPLATE:-'${upstream_version}.r${release_rev}'}
    BINARY_RELEASE_TAG_PREFIX=${BINARY_RELEASE_TAG_PREFIX:-${PKGNAME}-v}
    BINARY_RELEASE_UPSTREAM_TYPE=${BINARY_RELEASE_UPSTREAM_TYPE:-}
    BINARY_RELEASE_UPSTREAM_TAG_PREFIX=${BINARY_RELEASE_UPSTREAM_TAG_PREFIX:-}
    BINARY_RELEASE_SOURCE_DIR=${BINARY_RELEASE_SOURCE_DIR:-}
    BINARY_RELEASE_RUN_CHECK=${BINARY_RELEASE_RUN_CHECK:-false}

    if [ "${#BINARY_RELEASE_ARCHES[@]}" -eq 0 ]; then
        BINARY_RELEASE_ARCHES=("${ARCHES[@]}")
    fi

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

    if [ "$BINARY_RELEASE_ENABLED" = true ]; then
        [ -n "$BINARY_RELEASE_TEMPLATE" ] || die "BINARY_RELEASE_TEMPLATE is required when BINARY_RELEASE_ENABLED=true"
        [ -n "$BINARY_RELEASE_UPSTREAM_TYPE" ] || die "BINARY_RELEASE_UPSTREAM_TYPE is required when BINARY_RELEASE_ENABLED=true"
        [ "${#BINARY_RELEASE_ARCHES[@]}" -gt 0 ] || die "BINARY_RELEASE_ARCHES must not be empty when BINARY_RELEASE_ENABLED=true"
        [ "${#BINARY_RELEASE_ARCHIVE_FILES[@]}" -gt 0 ] || die "BINARY_RELEASE_ARCHIVE_FILES must not be empty when BINARY_RELEASE_ENABLED=true"

        case "$BINARY_RELEASE_TEMPLATE" in
            source-cargo) ;;
            *) die "Unsupported BINARY_RELEASE_TEMPLATE: $BINARY_RELEASE_TEMPLATE" ;;
        esac

        case "$BINARY_RELEASE_UPSTREAM_TYPE" in
            github-source-archive)
                [ -n "$BINARY_RELEASE_UPSTREAM_REPO_USER" ] || die "BINARY_RELEASE_UPSTREAM_REPO_USER is required for github-source-archive"
                [ -n "$BINARY_RELEASE_UPSTREAM_REPO_NAME" ] || die "BINARY_RELEASE_UPSTREAM_REPO_NAME is required for github-source-archive"
                ;;
            *) die "Unsupported BINARY_RELEASE_UPSTREAM_TYPE: $BINARY_RELEASE_UPSTREAM_TYPE" ;;
        esac

        local binary_release_arch
        for binary_release_arch in "${BINARY_RELEASE_ARCHES[@]}"; do
            local binary_release_suffix
            binary_release_suffix=$(arch_var_suffix "$binary_release_arch")
            local binary_release_asset_var="BINARY_RELEASE_ASSET_${binary_release_suffix}"
            [ -n "${!binary_release_asset_var}" ] || die "${binary_release_asset_var} is required when BINARY_RELEASE_ENABLED=true"
        done
    fi

    if [ "$PACKAGE_TEMPLATE" = "binary-archive" ] || [ "$PACKAGE_TEMPLATE" = "appimage-desktop" ]; then
        [ -n "$BINARY_NAME" ] || die "BINARY_NAME is required for template ${PACKAGE_TEMPLATE}"
        [ -n "$INSTALL_BIN_PATH" ] || die "INSTALL_BIN_PATH is required for template ${PACKAGE_TEMPLATE}"
        validate_package_name_value "$BINARY_NAME" "BINARY_NAME"
        validate_relative_source_pattern "BINARY_SOURCE_PATH" "${BINARY_SOURCE_PATH:-$BINARY_NAME}"
        validate_absolute_install_path "INSTALL_BIN_PATH" "$INSTALL_BIN_PATH"
    fi

    if [ -n "$WRAPPER_SOURCE_PATH" ] || [ -n "$WRAPPER_INSTALL_PATH" ]; then
        [ -n "$WRAPPER_SOURCE_PATH" ] || die "WRAPPER_SOURCE_PATH is required when WRAPPER_INSTALL_PATH is set"
        [ -n "$WRAPPER_INSTALL_PATH" ] || die "WRAPPER_INSTALL_PATH is required when WRAPPER_SOURCE_PATH is set"
        validate_relative_source_pattern "WRAPPER_SOURCE_PATH" "$WRAPPER_SOURCE_PATH"
        validate_absolute_install_path "WRAPPER_INSTALL_PATH" "$WRAPPER_INSTALL_PATH"
    fi

    if [ "$PACKAGE_TEMPLATE" = "source-meson" ]; then
        [ -n "$SOURCE_RENAME" ] || die "SOURCE_RENAME is required for template ${PACKAGE_TEMPLATE}"
        validate_relative_source_pattern "SOURCE_DIR" "$SOURCE_DIR"
        validate_relative_source_pattern "BUILD_DIR" "$BUILD_DIR"
    fi

    if [ "$PACKAGE_TEMPLATE" = "appimage-desktop" ]; then
        validate_relative_source_pattern "APPIMAGE_APPDIR_NAME" "$APPIMAGE_APPDIR_NAME"
        validate_relative_source_pattern "APPIMAGE_INSTALL_DIR" "${APPIMAGE_INSTALL_DIR:-$BINARY_NAME}"
    fi

    if [ "$SERVICE_MODE" != "none" ]; then
        [ -n "$SERVICE_NAME" ] || die "SERVICE_NAME is required when SERVICE_MODE is ${SERVICE_MODE}"
        case "$SERVICE_NAME" in
            */*|../*|*/../*|*/..)
                die "SERVICE_NAME must be a unit filename, not a path, in ${PACKAGE_DEFINITION_PATH}: ${SERVICE_NAME}"
                ;;
        esac
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

    local doc_file
    for doc_file in "${DOC_FILES[@]}"; do
        validate_relative_source_pattern "DOC_FILES entry" "$doc_file"
    done

    local license_file
    for license_file in "${LICENSE_FILES[@]}"; do
        validate_relative_source_pattern "LICENSE_FILES entry" "$license_file"
    done

    local desktop_candidate
    for desktop_candidate in "${DESKTOP_CANDIDATES[@]}"; do
        validate_relative_source_pattern "DESKTOP_CANDIDATES entry" "$desktop_candidate"
    done

    local icon_candidate
    for icon_candidate in "${ICON_CANDIDATES[@]}"; do
        validate_relative_source_pattern "ICON_CANDIDATES entry" "$icon_candidate"
    done

    local local_file
    for local_file in "${LOCAL_FILES[@]}"; do
        validate_package_asset_path "LOCAL_FILES entry" "$local_file"
    done

    local patch_file
    for patch_file in "${PATCH_FILES[@]}"; do
        validate_package_asset_path "PATCH_FILES entry" "$patch_file"
    done

    local binary_release_patch_file
    for binary_release_patch_file in "${BINARY_RELEASE_PATCH_FILES[@]}"; do
        validate_package_asset_path "BINARY_RELEASE_PATCH_FILES entry" "$binary_release_patch_file"
    done

    if [ "$SERVICE_MODE" = "static" ]; then
        validate_package_asset_path "SERVICE_FILE" "$SERVICE_FILE"
    fi

    if [ "$INSTALL_MODE" = "static" ]; then
        validate_package_asset_path "INSTALL_FILE" "$INSTALL_FILE"
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

load_package_spec() {
    local package_dir=$1
    local config_path

    config_path=$(package_definition_path "$package_dir") || die "PackageSpec definition not found in ${package_dir}"
    validate_package_spec_data_only "$config_path" || die "PackageSpec must contain declarative assignments only: ${config_path}"

    reset_package_spec_state

    PACKAGE_DIR=$(realpath "$package_dir")
    PACKAGE_NAME=$(basename "$PACKAGE_DIR")
    PACKAGE_DEFINITION_PATH=$(realpath "$config_path")
    PACKAGE_SPEC_FORMAT=package.conf

    # shellcheck disable=SC1090
    source "$PACKAGE_DEFINITION_PATH"

    normalize_package_spec_arrays
    validate_package_spec
}

load_package_config() {
    load_package_spec "$@"
}

load_package_hooks() {
    local hooks_path="${PACKAGE_DIR}/hooks.sh"

    if [ -f "$hooks_path" ]; then
        # shellcheck disable=SC1090
        source "$hooks_path"
    fi
}
