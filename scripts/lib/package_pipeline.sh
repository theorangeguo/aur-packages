#!/bin/bash

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
        source-cargo)
            render_source_cargo_pkgbuild "$workspace"
            ;;
        *)
            die "Unsupported PACKAGE_TEMPLATE: $PACKAGE_TEMPLATE"
            ;;
    esac
}

prepare_workspace_for_build() {
    local workspace=$1

    prepare_workspace_assets "$workspace"
    render_pkgbuild "$workspace"
    prefetch_resolved_sources
}

build_workspace_as_builder() {
    local workspace=$1
    local skip_build=$2
    local noninteractive=$3
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
if [ $(printf '%q' "$skip_build") = true ]; then
    log_info "Skipping build (--skip-build)"
else
    makepkg_opts="-sf"
    if [ $(printf '%q' "$noninteractive") = true ]; then
        makepkg_opts="\$makepkg_opts --noconfirm"
    fi
    makepkg \$makepkg_opts
    makepkg --packagelist > .packagelist
fi
EOF

    chmod +x "$builder_script"
    chmod 755 "$TMP_ROOT"
    chown builder:builder "$builder_script"
    chown -R builder:builder "$workspace" "$SRCDEST" "$PKGDEST"
    su builder -c "HOME=/home/builder bash $(printf %q "$builder_script")"
}

build_workspace_as_current_user() {
    local workspace=$1
    local skip_build=$2
    local noninteractive=$3
    local makepkg_opts="-sf"

    (
        cd "$workspace"
        ensure_valid_pgp_keys
        updpkgsums
        makepkg --printsrcinfo > .SRCINFO
        if [ "$skip_build" = true ]; then
            log_info "Skipping build (--skip-build)"
        else
            if [ "$noninteractive" = true ]; then
                makepkg_opts="$makepkg_opts --noconfirm"
            fi
            makepkg $makepkg_opts
            makepkg --packagelist > .packagelist
        fi
    )
}

build_workspace() {
    local workspace=$1
    local skip_build=${2:-false}
    local noninteractive=${3:-false}

    if [ "$(id -u)" -eq 0 ]; then
        id -u builder >/dev/null 2>&1 || die "builder user not found; run ./scripts/ci_manager.sh setup_user first"
        build_workspace_as_builder "$workspace" "$skip_build" "$noninteractive"
    else
        build_workspace_as_current_user "$workspace" "$skip_build" "$noninteractive"
    fi
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

assert_path_owned_by_package() {
    local path=$1
    local owner

    [[ "$path" = /* ]] || die "Owned-path checks require absolute paths: $path"
    owner=$(pacman -Qoq "$path" 2>/dev/null || true)
    [ "$owner" = "$PKGNAME" ] || die "Expected installed path to be owned by $PKGNAME: $path"
}

assert_packaged_path_exists() {
    local path=$1

    assert_path_exists "$path"
    assert_path_owned_by_package "$path"
}

assert_packaged_path_executable() {
    local path=$1

    assert_path_executable "$path"
    assert_path_owned_by_package "$path"
}

run_smoke_checks() {
    pacman -Q "$PKGNAME" >/dev/null 2>&1 || die "Installed package not found in pacman database: $PKGNAME"

    if [ -n "$INSTALL_BIN_PATH" ]; then
        assert_packaged_path_executable "$INSTALL_BIN_PATH"
    fi

    if [ "$SERVICE_MODE" != "none" ]; then
        assert_packaged_path_exists "$(service_install_path)"
    fi

    if [ "$PACKAGE_TEMPLATE" = "appimage-desktop" ] && [ -n "$BINARY_NAME" ]; then
        assert_packaged_path_exists "/usr/share/applications/${BINARY_NAME}.desktop"
    fi

    local license_file
    for license_file in "${LICENSE_FILES[@]}"; do
        [ -n "$license_file" ] || continue
        assert_packaged_path_exists "/usr/share/licenses/${PKGNAME}/$(basename "$license_file")"
    done

    local test_path
    for test_path in "${TEST_PATHS[@]}"; do
        [ -n "$test_path" ] || continue
        assert_packaged_path_exists "$test_path"
    done

    local test_executable
    for test_executable in "${TEST_EXECUTABLES[@]}"; do
        [ -n "$test_executable" ] || continue
        assert_packaged_path_executable "$test_executable"
    done

    local test_command
    for test_command in "${TEST_COMMANDS[@]}"; do
        [ -n "$test_command" ] || continue
        log_info "Running smoke-test command: $test_command"
        bash -lc "$test_command" || die "Smoke-test command failed: $test_command"
    done
}

install_and_verify_workspace() {
    local workspace=$1
    local package_files=()

    [ "$(id -u)" -eq 0 ] || die "Install verification must run as root"

    mapfile -t package_files < "${workspace}/.packagelist"
    [ "${#package_files[@]}" -gt 0 ] || die "No built package files were produced"

    log_group_start "Install Package"
    pacman -U --noconfirm "${package_files[@]}"
    run_smoke_checks
    log_info "Package install smoke tests passed: $PKGNAME"
    log_group_end
}
