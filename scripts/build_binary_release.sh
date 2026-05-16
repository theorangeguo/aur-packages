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
source "${SCRIPT_DIR}/lib/binary_release.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/binary_release_source_cargo.sh"

ARCH_BASE_DEVEL_IMAGE=${ARCH_BASE_DEVEL_IMAGE:-archlinux:base-devel@sha256:01bd0ee1c23c3dec1dcb0fce558150a222ee2ef0a3776404de33d0714bcefbb0}
PKG_DIR=""
REQUESTED_UPSTREAM_VERSION=""
FORCE=false
DRY_RUN=false
SKIP_PUBLISH=false
TMP_ROOT=""

show_help() {
    cat <<EOF
Usage: scripts/build_binary_release.sh <pkgname-or-path> [options]

Options:
  --upstream-version <version>  Build a specific upstream version
  --force                       Rebuild/upload even if release assets already exist
  --dry-run                     Resolve and print planned assets without building
  --skip-publish                Build local assets but do not publish to GitHub Releases
  -h, --help                    Show this help
EOF
}

cleanup() {
    if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}

trap cleanup EXIT

main() {
    while [ "$#" -gt 0 ]; do
        case $1 in
            --upstream-version)
                shift || die "Missing value for --upstream-version"
                REQUESTED_UPSTREAM_VERSION=$1
                ;;
            --force) FORCE=true ;;
            --dry-run) DRY_RUN=true ;;
            --skip-publish) SKIP_PUBLISH=true ;;
            -h|--help) show_help; exit 0 ;;
            -*) die "Unknown parameter: $1" ;;
            *) PKG_DIR=$1 ;;
        esac
        shift || true
    done

    [ -n "$PKG_DIR" ] || { show_help; die "No package specified."; }

    cd "$REPO_ROOT"
    PKG_DIR=$(resolve_package_dir_input "$PKG_DIR")
    load_package_config "$PKG_DIR"
    load_package_hooks

    [ "$BINARY_RELEASE_ENABLED" = true ] || die "BINARY_RELEASE_ENABLED=true is required for ${PKGNAME}"

    if [ "${#BINARY_RELEASE_MAKEDEPENDS[@]}" -eq 0 ]; then
        BINARY_RELEASE_MAKEDEPENDS=('ca-certificates' 'curl' 'git' 'patch' 'rust' 'tar')
    fi

    local upstream_version
    local pkgver
    local release_tag
    local arch
    local asset_name
    local asset_path

    upstream_version=$(binary_release_resolve_upstream_version "$REQUESTED_UPSTREAM_VERSION")
    pkgver=$(binary_release_pkgver "$upstream_version")
    release_tag=$(binary_release_tag "$pkgver")

    log_group_start "Binary Release Plan: ${PKGNAME}"
    log_info "Package: ${PKGNAME}"
    log_info "Template: ${BINARY_RELEASE_TEMPLATE}"
    log_info "Upstream Version: ${upstream_version}"
    log_info "Package Version: ${pkgver}"
    log_info "Release Tag: ${release_tag}"
    log_info "Release Repo: $(binary_release_repo)"
    log_group_end

    if [ "$DRY_RUN" = true ]; then
        for arch in "${BINARY_RELEASE_ARCHES[@]}"; do
            asset_name=$(binary_release_asset_name_for_arch "$arch" "$pkgver")
            log_info "[DRY RUN] Would build ${arch}: ${asset_name}"
        done
        return 0
    fi

    TMP_ROOT=$(mktemp -d)
    mkdir -p "${TMP_ROOT}/assets"

    for arch in "${BINARY_RELEASE_ARCHES[@]}"; do
        asset_name=$(binary_release_asset_name_for_arch "$arch" "$pkgver")

        if [ "$FORCE" != true ] && [ "$SKIP_PUBLISH" != true ] && binary_release_asset_exists "$release_tag" "$asset_name"; then
            log_info "Release asset already exists: ${release_tag}/${asset_name}"
            continue
        fi

        asset_path="${TMP_ROOT}/assets/${asset_name}"
        case "$BINARY_RELEASE_TEMPLATE" in
            source-cargo)
                build_binary_release_source_cargo "$arch" "$upstream_version" "$pkgver" "$asset_path"
                ;;
            *)
                die "Unsupported BINARY_RELEASE_TEMPLATE: $BINARY_RELEASE_TEMPLATE"
                ;;
        esac

        (cd "$(dirname "$asset_path")" && sha256sum "$(basename "$asset_path")") > "${asset_path}.sha256sum"
        write_binary_release_buildinfo "${asset_path}.buildinfo" "$arch" "$upstream_version" "$pkgver" "$release_tag" "$asset_name"

        if [ "$SKIP_PUBLISH" = true ]; then
            log_info "Built release asset without publishing: ${asset_path}"
        else
            publish_binary_release_asset "$release_tag" "$pkgver" "$asset_path"
            log_info "Published release asset: ${release_tag}/${asset_name}"
        fi
    done

    if [ "$SKIP_PUBLISH" != true ]; then
        log_group_start "Post-publish preflight: ${PKGNAME}"
        bash "${SCRIPT_DIR}/auto_update.sh" "$PKG_DIR" --preflight
        log_group_end
    fi
}

main "$@"
