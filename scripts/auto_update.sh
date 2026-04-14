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
source "${SCRIPT_DIR}/lib/aur_state.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/package_pipeline.sh"

DRY_RUN=false
SKIP_BUILD=false
VERIFY_INSTALL=false
PKG_DIR=""
TMP_ROOT=""
SSH_KEY_FILE=""
SSH_KNOWN_HOSTS_FILE=""
AUR_CURRENT_VER=""
AUR_CURRENT_REL=0
TARGET_PKGVER=""
TARGET_PKGREL=1
FINAL_WORKSPACE=""
AUR_SSH_HOST=aur.archlinux.org
AUR_SSH_HOST_ED25519_FINGERPRINT='SHA256:RFzBCUItH9LZS0cKB5UE6ceAYhBD5C8GeOBip8Z11+4'

show_help() {
    echo "Usage: ./auto_update.sh [package_dir] [options]"
    echo ""
    echo "Options:"
    echo "  --dry-run            Simulate run, do not push to AUR"
    echo "  --skip-build         Skip makepkg step (metadata update only)"
    echo "  --verify-install     Install built package and run smoke checks before publish (recommended in CI/container only)"
    echo "  -h, --help           Show this help"
}

cleanup() {
    if [ -n "$SSH_KEY_FILE" ] && [ -f "$SSH_KEY_FILE" ]; then
        rm -f "$SSH_KEY_FILE"
    fi

    if [ -n "$SSH_KNOWN_HOSTS_FILE" ] && [ -f "$SSH_KNOWN_HOSTS_FILE" ]; then
        rm -f "$SSH_KNOWN_HOSTS_FILE"
    fi

    if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}

trap cleanup EXIT

prepare_aur_ssh() {
    local fingerprint

    require_cmd ssh-keyscan
    require_cmd ssh-keygen
    require_cmd awk

    SSH_KEY_FILE=$(mktemp)
    printf '%s\n' "$AUR_SSH_PRIVATE_KEY" | tr -d '\r' > "$SSH_KEY_FILE"
    chmod 600 "$SSH_KEY_FILE"

    SSH_KNOWN_HOSTS_FILE=$(mktemp)
    ssh-keyscan -t ed25519 "$AUR_SSH_HOST" > "$SSH_KNOWN_HOSTS_FILE" 2>/dev/null \
        || die "Failed to fetch AUR SSH host key"
    [ -s "$SSH_KNOWN_HOSTS_FILE" ] || die "Fetched empty AUR SSH host key set"

    fingerprint=$(ssh-keygen -lf "$SSH_KNOWN_HOSTS_FILE" -E sha256 | awk 'NR == 1 { print $2 }')
    [ "$fingerprint" = "$AUR_SSH_HOST_ED25519_FINGERPRINT" ] \
        || die "Unexpected AUR SSH host key fingerprint: ${fingerprint:-unknown}"
    chmod 600 "$SSH_KNOWN_HOSTS_FILE"
}

build_and_stage_workspace() {
    local workspace="${TMP_ROOT}/workspace-${TARGET_PKGREL}"

    rm -rf "$workspace"
    mkdir -p "$workspace"

    prepare_workspace_for_build "$workspace"

    log_group_start "Render + Verify (${TARGET_PKGVER}-${TARGET_PKGREL})"
    build_workspace "$workspace" "$SKIP_BUILD" "${CI:-false}"
    log_group_end

    register_workspace_sync_file ".SRCINFO"
    sync_workspace_to_aur_repo "$workspace" "${WORKSPACE_SYNC_FILES[@]}"
    FINAL_WORKSPACE="$workspace"
}

publish_to_aur() {
    local commit_msg="update: ${TARGET_PKGVER}-${TARGET_PKGREL}"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would commit: ${commit_msg}"
        log_info "[DRY RUN] Staged files:"
        git -C "$AUR_REPO_DIR" status --short
        return 0
    fi

    if [ "$CI" = "true" ] && [ -z "$AUR_SSH_PRIVATE_KEY" ]; then
        die "AUR_SSH_PRIVATE_KEY is required to publish from CI"
    fi

    if [ "$CI" = "true" ] && [ -n "$AUR_SSH_PRIVATE_KEY" ]; then
        local remote_url="ssh://aur@aur.archlinux.org/${PKGNAME}.git"
        local git_ssh_command

        prepare_aur_ssh
        git_ssh_command="ssh -i $SSH_KEY_FILE -o UserKnownHostsFile=$SSH_KNOWN_HOSTS_FILE -o StrictHostKeyChecking=yes"

        if git -C "$AUR_REPO_DIR" remote get-url origin >/dev/null 2>&1; then
            git -C "$AUR_REPO_DIR" remote set-url origin "$remote_url"
        else
            git -C "$AUR_REPO_DIR" remote add origin "$remote_url"
        fi

        GIT_SSH_COMMAND="$git_ssh_command" \
            git -C "$AUR_REPO_DIR" -c user.name="${AUR_USERNAME:-orange-guo}" -c user.email="${AUR_EMAIL:-aur@example.invalid}" commit -m "$commit_msg"
        GIT_SSH_COMMAND="$git_ssh_command" \
            git -C "$AUR_REPO_DIR" push origin master
        rm -f "$SSH_KEY_FILE"
        SSH_KEY_FILE=""
        rm -f "$SSH_KNOWN_HOSTS_FILE"
        SSH_KNOWN_HOSTS_FILE=""
    else
        log_info "Skipping push (local run or missing AUR SSH key)."
        log_info "AUR repository prepared at: $AUR_REPO_DIR"
    fi
}

main() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --dry-run) DRY_RUN=true ;;
            --skip-build) SKIP_BUILD=true ;;
            --verify-install) VERIFY_INSTALL=true ;;
            -h|--help) show_help; exit 0 ;;
            -*) die "Unknown parameter: $1" ;;
            *) PKG_DIR=$1 ;;
        esac
        shift
    done

    [ -n "$PKG_DIR" ] || {
        show_help
        die "No package directory specified."
    }

    [[ "$PKG_DIR" =~ ^(\./)?[a-zA-Z0-9._-]+$ ]] || die "Invalid package directory: $PKG_DIR"
    PKG_DIR=${PKG_DIR#./}

    [ -d "$PKG_DIR" ] || die "Directory '$PKG_DIR' does not exist."
    [ -f "$PKG_DIR/package.conf" ] || die "package.conf not found in '$PKG_DIR'."

    if [ "$SKIP_BUILD" = true ] && [ "$VERIFY_INSTALL" = true ]; then
        die "--verify-install cannot be used with --skip-build"
    fi

    if [ "$VERIFY_INSTALL" = true ] && [ "$(id -u)" -ne 0 ]; then
        die "--verify-install requires running as root"
    fi

    cd "$REPO_ROOT"

    require_cmd git
    require_cmd makepkg
    require_cmd updpkgsums

    load_package_config "$PKG_DIR"
    load_package_hooks

    TMP_ROOT=$(mktemp -d)
    AUR_DIR="${TMP_ROOT}/aur"
    export SRCDEST="${TMP_ROOT}/srcdest"
    export PKGDEST="${TMP_ROOT}/pkgdest"
    mkdir -p "$SRCDEST" "$PKGDEST"

    log_group_start "Initialization: ${PKG_DIR}"
    prepare_aur_repo "$PKGNAME" "$AUR_DIR"
    load_aur_state
    log_info "Package: $PKGNAME"
    log_info "Template: $PACKAGE_TEMPLATE"
    log_info "Upstream Resolver: $UPSTREAM_TYPE"
    log_info "Current AUR Version: ${AUR_CURRENT_VER:-<none>}"
    log_info "Current AUR pkgrel: ${AUR_CURRENT_REL}"
    log_group_end

    log_group_start "Resolve Upstream"
    dispatch_upstream_resolution
    log_info "Resolved Upstream Version: $RESOLVED_VERSION"
    log_group_end

    TARGET_PKGVER=$RESOLVED_VERSION
    if [ -n "$AUR_CURRENT_VER" ] && [ "$TARGET_PKGVER" = "$AUR_CURRENT_VER" ]; then
        TARGET_PKGREL=${AUR_CURRENT_REL:-1}
        [ "$TARGET_PKGREL" -ge 1 ] || TARGET_PKGREL=1
    else
        TARGET_PKGREL=1
    fi

    build_and_stage_workspace

    if [ -n "$AUR_CURRENT_VER" ] && [ "$TARGET_PKGVER" = "$AUR_CURRENT_VER" ] && aur_repo_has_packaging_changes; then
        TARGET_PKGREL=$((AUR_CURRENT_REL + 1))
        log_info "Packaging content changed without upstream version change; bumping pkgrel to ${TARGET_PKGREL}."
        build_and_stage_workspace
    elif [ -n "$AUR_CURRENT_VER" ] && [ "$TARGET_PKGVER" = "$AUR_CURRENT_VER" ] && aur_repo_has_staged_changes; then
        log_info "Only sync metadata changed; keeping pkgrel at ${TARGET_PKGREL}."
    fi

    if ! aur_repo_has_staged_changes; then
        log_info "No changes to publish."
        exit 0
    fi

    if [ "$VERIFY_INSTALL" = true ]; then
        install_and_verify_workspace "$FINAL_WORKSPACE"
    fi

    log_group_start "Publish to AUR"
    publish_to_aur
    log_group_end
}

main "$@"
