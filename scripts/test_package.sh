#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/package_loader.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/upstream_github_release.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/upstream_custom_hook.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/render_install.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/template_binary_archive.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/template_deb_repack.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/template_appimage_desktop.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/template_source_meson.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/package_pipeline.sh"

PKG_DIR=""
TMP_ROOT=""
TARGET_PKGVER=""
TARGET_PKGREL=1

show_help() {
    echo "Usage: ./scripts/test_package.sh <package_name_or_dir>"
}

cleanup() {
    if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}

trap cleanup EXIT

main() {
    PKG_DIR=$1

    [ -n "$PKG_DIR" ] || {
        show_help
        die "No package directory specified."
    }

    [ "$(id -u)" -eq 0 ] || die "scripts/test_package.sh must run as root inside the test container"

    cd "$REPO_ROOT"

    require_cmd git
    require_cmd makepkg
    require_cmd updpkgsums
    require_cmd pacman

    PKG_DIR=$(resolve_package_dir_input "$PKG_DIR")

    load_package_config "$PKG_DIR"
    load_package_hooks

    TMP_ROOT=$(mktemp -d)
    export SRCDEST="${TMP_ROOT}/srcdest"
    export PKGDEST="${TMP_ROOT}/pkgdest"
    mkdir -p "$SRCDEST" "$PKGDEST"

    local workspace="${TMP_ROOT}/workspace"
    mkdir -p "$workspace"
    AUR_REPO_DIR="${TMP_ROOT}/aur"
    mkdir -p "$AUR_REPO_DIR"
    AUR_CURRENT_VER=""
    AUR_CURRENT_REL=0

    log_group_start "Test Initialization: ${PKG_DIR}"
    dispatch_upstream_resolution
    TARGET_PKGVER=$RESOLVED_VERSION
    TARGET_PKGREL=1
    log_info "Package: $PKGNAME"
    log_info "Resolved Version: $TARGET_PKGVER"
    log_group_end

    prepare_workspace_for_build "$workspace"

    log_group_start "Build Package"
    build_workspace "$workspace" false true
    log_group_end

    install_and_verify_workspace "$workspace"
}

main "$@"
