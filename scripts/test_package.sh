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

PKG_DIR=""
TMP_ROOT=""
TARGET_PKGVER=""
TARGET_PKGREL=1

show_help() {
    echo "Usage: ./scripts/test_package.sh <package_dir>"
}

cleanup() {
    if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}

trap cleanup EXIT

dispatch_upstream_resolution() {
    case "$UPSTREAM_TYPE" in
        github-release-assets)
            resolve_github_release_assets
            ;;
        custom-hook)
            resolve_custom_upstream_state
            ;;
        *)
            die "Unsupported UPSTREAM_TYPE: $UPSTREAM_TYPE"
            ;;
    esac
}

render_pkgbuild() {
    local workspace=$1

    case "$PACKAGE_TEMPLATE" in
        binary-archive)
            render_binary_archive_pkgbuild "$workspace"
            ;;
        deb-repack)
            render_deb_repack_pkgbuild "$workspace"
            ;;
        appimage-desktop)
            render_appimage_desktop_pkgbuild "$workspace"
            ;;
        source-meson)
            render_source_meson_pkgbuild "$workspace"
            ;;
        *)
            die "Unsupported PACKAGE_TEMPLATE: $PACKAGE_TEMPLATE"
            ;;
    esac
}

build_package_as_builder() {
    local workspace=$1
    local builder_script="${TMP_ROOT}/builder-build.sh"

    cat > "$builder_script" <<EOF
#!/bin/bash
set -e
source $(printf '%q' "${SCRIPT_DIR}/lib/common.sh")
$(render_array_assignment "VALIDPGPKEYS" "${VALIDPGPKEYS[@]}")
export SRCDEST=$(printf '%q' "$SRCDEST")
export PKGDEST=$(printf '%q' "$PKGDEST")
cd $(printf '%q' "$workspace")
ensure_valid_pgp_keys
updpkgsums
makepkg --printsrcinfo > .SRCINFO
makepkg -sf --noconfirm
makepkg --packagelist > .packagelist
EOF

    chmod +x "$builder_script"
    chown -R builder:builder "$TMP_ROOT"
    su builder -c "HOME=/home/builder bash $(printf %q "$builder_script")"
}

assert_path_exists() {
    local path=$1
    [[ "$path" = /* ]] || die "Smoke-test paths must be absolute: $path"
    [ -e "$path" ] || die "Expected installed path missing: $path"
}

assert_path_executable() {
    local path=$1
    [[ "$path" = /* ]] || die "Smoke-test executable paths must be absolute: $path"
    [ -x "$path" ] || die "Expected executable path missing or not executable: $path"
}

run_smoke_checks() {
    pacman -Q "$PKGNAME" >/dev/null 2>&1 || die "Installed package not found in pacman database: $PKGNAME"

    if [ -n "$INSTALL_BIN_PATH" ]; then
        assert_path_executable "$INSTALL_BIN_PATH"
    fi

    if [ "$SERVICE_MODE" != "none" ]; then
        assert_path_exists "$(service_install_path)"
    fi

    if [ "$PACKAGE_TEMPLATE" = "appimage-desktop" ] && [ -n "$BINARY_NAME" ]; then
        assert_path_exists "/usr/share/applications/${BINARY_NAME}.desktop"
    fi

    local license_file
    for license_file in "${LICENSE_FILES[@]}"; do
        [ -n "$license_file" ] || continue
        assert_path_exists "/usr/share/licenses/${PKGNAME}/$(basename "$license_file")"
    done

    local test_path
    for test_path in "${TEST_PATHS[@]}"; do
        [ -n "$test_path" ] || continue
        assert_path_exists "$test_path"
    done

    local test_executable
    for test_executable in "${TEST_EXECUTABLES[@]}"; do
        [ -n "$test_executable" ] || continue
        assert_path_executable "$test_executable"
    done
}

main() {
    PKG_DIR=$1

    [ -n "$PKG_DIR" ] || {
        show_help
        die "No package directory specified."
    }

    [ "$(id -u)" -eq 0 ] || die "scripts/test_package.sh must run as root inside the test container"
    id -u builder >/dev/null 2>&1 || die "builder user not found; run ./scripts/ci_manager.sh setup_user first"

    cd "$REPO_ROOT"

    require_cmd git
    require_cmd makepkg
    require_cmd updpkgsums
    require_cmd pacman

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

    prepare_workspace_assets "$workspace"
    render_pkgbuild "$workspace"

    log_group_start "Build Package"
    build_package_as_builder "$workspace"
    log_group_end

    local package_files=()
    mapfile -t package_files < "${workspace}/.packagelist"
    [ "${#package_files[@]}" -gt 0 ] || die "No built package files were produced"

    log_group_start "Install Package"
    pacman -U --noconfirm "${package_files[@]}"
    run_smoke_checks
    log_info "Package install smoke tests passed: $PKGNAME"
    log_group_end
}

main "$@"
